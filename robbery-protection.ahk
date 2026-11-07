; 창 캡처는 별도 프로세스에서 실행하며 게임 창을 활성화하지 않습니다.
class RobberyProtection {
	static Active := false
	static Busy := false
	static Count := 0
	static PendingRespawns := Map()
	static RespawnKeys := ["Esc", "r", "Enter", "r", "Enter", "r", "Enter"]
	static RespawnDelayMs := 1000
	static CurrentInput := 0
	static States := Map()
	static Jobs := Map()
	static Workers := Map()
	static CaptureErrors := Map()
	static LastCapture := 0
	static NextJumpTick := 0
	static Helper := ""
	static MatcherHelper := ""
	static MatcherHandle := 0
	static MatcherBorn := 0
	static TempRoot := A_Temp "\DEAN-protection-" DllCall("GetCurrentProcessId")

	static Start() {
		global CoreMode, AppDir
		this.Stop()
		if CoreMode
			this.Helper := A_Args[2] "\assets\dean-window-capture.exe"
		else if A_IsCompiled {
			WebViewCtrl.CreateFileFromResource("assets\dean-window-capture.exe", WebViewCtrl.TempDir)
			this.Helper := WebViewCtrl.TempDir "\assets\dean-window-capture.exe"
		} else
			this.Helper := A_ScriptDir "\frontend\public\assets\dean-window-capture.exe"
		if CoreMode
			this.MatcherHelper := A_Args[2] "\assets\dean-warning-match.exe"
		else if A_IsCompiled {
			WebViewCtrl.CreateFileFromResource("assets\dean-warning-match.exe", WebViewCtrl.TempDir)
			this.MatcherHelper := WebViewCtrl.TempDir "\assets\dean-warning-match.exe"
		} else
			this.MatcherHelper := A_ScriptDir "\frontend\public\assets\dean-warning-match.exe"
		if !FileExist(this.Helper) || !FileExist(this.MatcherHelper)
			throw Error("창 캡처 도우미를 빌드한 뒤 다시 실행해 주세요")
		DirCreate(this.TempRoot)
		DirCreate(AppDir "\소매치기 범인")
		this.CaptureErrors := Map()
		this.LastCapture := A_TickCount - 1000
		this.States := Map()
		this.Count := 0
		this.Active := true
		SetTimer(RobberyProtectionTick, 100)
		SetTimer(ProtectionRespawnTick, 25)
		this.NextJumpTick := A_TickCount + 300000
		SetTimer(ProtectionHeartbeat, 1000)
	}

	static Stop() {
		this.Active := false
		SetTimer(RobberyProtectionTick, 0)
		SetTimer(ProtectionRespawnTick, 0)
		this.CancelRespawns()
		SetTimer(ProtectionHeartbeat, 0)
		this.StopMatcher()
		for hwnd, job in this.Jobs
			this.FinishJob(job, true)
		this.Jobs := Map()
		for hwnd, worker in this.Workers.Clone()
			this.DropWorker(hwnd)
		if DirExist(this.TempRoot)
			try DirDelete(this.TempRoot)
	}

	static Dispose() => this.Stop()

	static Scan() {
		global running, targetWindows, afkInputBusy
		if !this.Active || !running || this.Busy || PcRecorder.Busy
			return
		; 점프 시간이 되면 다음 캡처보다 먼저 처리합니다.
		if A_TickCount >= this.NextJumpTick && !afkInputBusy && !this.PendingRespawns.Count {
			ProtectionHeartbeat()
			return
		}
		this.Busy := true
		stage := "capture tick"
		try {
			for hwnd, job in this.Jobs.Clone() {
				stage := "capture result HWND " hwnd " PID " job.Pid " file=" job.Path ".result"
				exitCode := 259
				DllCall("GetExitCodeProcess", "ptr", job.Handle, "uint*", &exitCode)
				if exitCode = 259 && FileExist(job.Path ".result")
					exitCode := Integer(Trim(FileRead(job.Path ".result")))
				if exitCode = 259 && A_TickCount - job.Start < 2500
					continue
				if exitCode = 259
					this.Trace("HWND " hwnd ": capture timeout; restarting worker")
				if exitCode = 0 && FileExist(job.Path ".ready") && this.ValidTarget(hwnd, job.Pid) {
					if !job.HasOwnProp("MatchStart") {
						stage := "publish match request HWND " hwnd " file=" job.Path ".match.request"
						this.RequestMatch(job)
						continue
					}
					if !FileExist(job.Path ".match.result") {
						if FileExist(job.Path ".match.started") {
							if !job.HasOwnProp("MatchingSince")
								job.MatchingSince := A_TickCount
							waiting := A_TickCount - job.MatchingSince < 2500
						} else {
							; 검색 대기를 검색 중 멈춤으로 취급하지 않으며 창 수에 따라 대기 상한을 둡니다.
							waiting := A_TickCount - job.MatchStart < Max(5000, targetWindows.Count * 2500 + 1000)
						}
						if waiting
							continue
						this.ResetMatcher()
						break
					}
				}
				this.Jobs.Delete(hwnd)
				try {
					if exitCode = 0 && FileExist(job.Path ".ready") && this.ValidTarget(hwnd, job.Pid) {
						if this.CaptureErrors.Has(hwnd)
							this.CaptureErrors.Delete(hwnd)
						this.CheckFrame(hwnd, job)
					} else {
						if !this.CaptureErrors.Has(hwnd)
							this.Trace("capture failed HWND " hwnd " PID " job.Pid " code " exitCode " ready=" (FileExist(job.Path ".ready") ? 1 : 0) " target=" this.ValidTarget(hwnd, job.Pid))
						this.CaptureErrors[hwnd] := true
					}
				} catch as e {
					this.CaptureErrors[hwnd] := true
					this.Trace("process frame HWND " hwnd " PID " job.Pid ": " e.Message)
				} finally {
					this.FinishJob(job)
				}
				break
			}
			if !this.Active || !running || PcRecorder.Busy
				return
			if A_TickCount - this.LastCapture >= 1000 {
				this.LastCapture := A_TickCount
				for hwnd, pid in targetWindows.Clone() {
					if !this.ValidTarget(hwnd, pid) {
						targetWindows.Delete(hwnd)
						if this.Jobs.Has(hwnd)
							this.Jobs.Delete(hwnd)
						this.DropWorker(hwnd)
						if this.States.Has(hwnd)
							this.States.Delete(hwnd)
						if this.CaptureErrors.Has(hwnd)
							this.CaptureErrors.Delete(hwnd)
						continue
					}
					if this.Jobs.Has(hwnd)
						continue
					if WinGetMinMax("ahk_id " hwnd) = -1 {
						this.CaptureErrors[hwnd] := true
						continue
					}
					path := this.TempRoot "\" hwnd
					this.CleanFiles(path)
					try {
						handle := this.CreateWorker(hwnd, pid, path)
						this.Jobs[hwnd] := {Hwnd: hwnd, Pid: pid, Path: path, Handle: handle, Start: A_TickCount}
						this.RequestFrame(path)
					} catch as e {
						this.CaptureErrors[hwnd] := true
						this.Trace("start capture HWND " hwnd " PID " pid " file=" path ".request: " e.Message)
					}
				}
			}
			if !targetWindows.Count {
				this.Stop()
				running := false
				SetTimer(SendStatus, 0)
				MyGui.PostWebMessageAsJson('{"type":"stopped","content":{"reason":"window_closed"}}')
			}
		} catch as e {
			; 한 번의 파일/캡처 오류로 감지와 필수 점프를 함께 끄지 않습니다.
			this.Trace(stage ": " e.Message)
		} finally {
			this.Busy := false
		}
	}

	static CreateWorker(hwnd, pid, path) {
		if this.Workers.Has(hwnd) {
			worker := this.Workers[hwnd]
			code := 0
			if worker.Pid = pid && DllCall("GetExitCodeProcess", "ptr", worker.Handle, "uint*", &code) && code = 259
				return worker.Handle
			this.DropWorker(hwnd)
		}
		handle := this.LaunchHidden(this.Helper, hwnd ' ' pid ' "' path '" --serve ' DllCall("GetCurrentProcessId"))
		this.Workers[hwnd] := {Pid: pid, Handle: handle, Path: path}
		return handle
	}

	static LaunchHidden(executable, arguments) {
		; STARTF_FORCEOFFFEEDBACK | STARTF_USESHOWWINDOW: 실행 로딩 커서·창 표시 억제.
		startup := Buffer(104, 0)
		NumPut("uint", startup.Size, startup, 0)
		NumPut("uint", 0x81, startup, 60)
		NumPut("ushort", 0, startup, 64)
		command := '"' executable '" ' arguments
		commandBuffer := Buffer((StrLen(command) + 1) * 2, 0)
		StrPut(command, commandBuffer, "UTF-16")
		process := Buffer(24, 0)
		if !DllCall("CreateProcessW", "wstr", executable, "ptr", commandBuffer, "ptr", 0, "ptr", 0, "int", false, "uint", 0x08000000, "ptr", 0, "ptr", 0, "ptr", startup, "ptr", process)
			throw OSError(A_LastError, "CreateProcessW", "캡처 도우미 실행 실패")
		DllCall("CloseHandle", "ptr", NumGet(process, 8, "ptr"))
		handle := NumGet(process, 0, "ptr")
		return handle
	}

	static RequestFrame(path) {
		file := FileOpen(path ".request.tmp", "w")
		file.Write("capture")
		file.Close()
		FileMove(path ".request.tmp", path ".request", true)
	}

	static ValidTarget(hwnd, pid) {
		try return WinGetPID("ahk_id " hwnd) = pid && WinGetProcessName("ahk_id " hwnd) = "RobloxPlayerBeta.exe"
		catch
			return false
	}

	static RequestMatch(job) {
		; 12시간 이상 실행을 위해 검색 도우미도 대기 프레임이 없을 때 교체합니다.
		if this.MatcherHandle && A_TickCount - this.MatcherBorn >= 1800000 {
			pending := false
			for hwnd, other in this.Jobs
				if other.HasOwnProp("MatchStart")
					pending := true
			if !pending
				this.StopMatcher()
		}
		job.MatchStart := A_TickCount
		code := 0
		if !this.MatcherHandle || !DllCall("GetExitCodeProcess", "ptr", this.MatcherHandle, "uint*", &code) || code != 259 {
			this.StopMatcher()
			this.MatcherHandle := this.LaunchHidden(this.MatcherHelper, DllCall("GetCurrentProcessId") ' "' this.TempRoot '"')
			this.MatcherBorn := A_TickCount
		}
		file := FileOpen(job.Path ".match.request.tmp", "w")
		file.Write("match")
		file.Close()
		FileMove(job.Path ".match.request.tmp", job.Path ".match.request", true)
	}

	static StopMatcher() {
		if !this.MatcherHandle
			return
		code := 0
		if DllCall("GetExitCodeProcess", "ptr", this.MatcherHandle, "uint*", &code) && code = 259 {
			DllCall("TerminateProcess", "ptr", this.MatcherHandle, "uint", 1)
			DllCall("WaitForSingleObject", "ptr", this.MatcherHandle, "uint", 100)
		}
		DllCall("CloseHandle", "ptr", this.MatcherHandle)
		this.MatcherHandle := 0
		this.MatcherBorn := 0
	}

	static ResetMatcher() {
		this.Trace("image search timeout; restarting matcher")
		this.StopMatcher()
		for hwnd, job in this.Jobs.Clone() {
			if !job.HasOwnProp("MatchStart")
				continue
			this.Jobs.Delete(hwnd)
			this.CaptureErrors[hwnd] := true
			this.FinishJob(job)
		}
	}

	static FinishJob(job, force := false) {
		code := 0
		alive := DllCall("GetExitCodeProcess", "ptr", job.Handle, "uint*", &code) && code = 259
		if force || !alive || !FileExist(job.Path ".result")
			this.DropWorker(job.Hwnd)
		this.CleanFiles(job.Path)
	}

	static DropWorker(hwnd) {
		if !this.Workers.Has(hwnd)
			return
		worker := this.Workers[hwnd]
		this.Workers.Delete(hwnd)
		code := 0
		if DllCall("GetExitCodeProcess", "ptr", worker.Handle, "uint*", &code) && code = 259 {
			DllCall("TerminateProcess", "ptr", worker.Handle, "uint", 1)
			DllCall("WaitForSingleObject", "ptr", worker.Handle, "uint", 100)
		}
		DllCall("CloseHandle", "ptr", worker.Handle)
		this.CleanFiles(worker.Path)
	}

	static Trace(message) {
		global AppDir
		try {
			path := AppDir "\protection.log"
			if FileExist(path) && FileGetSize(path) > 262144
				FileDelete(path)
			FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", path, "UTF-8")
		}
	}

	static CleanFiles(path) {
		for extension in [".bmp", ".jpg", ".ready", ".request", ".result", ".request.tmp", ".result.tmp", ".match.request", ".match.request.tmp", ".match.tmp", ".match.result", ".match.started"]
			if FileExist(path extension)
				try FileDelete(path extension)
	}

	static CheckFrame(hwnd, job) {
		global AppDir
		try result := Trim(FileRead(job.Path ".match.result"))
		catch as e
			throw Error("read " job.Path ".match.result: " e.Message)
		if result != "0" && result != "1"
			throw Error("캡처 이미지 검색 실패")
		found := result = "1"
		if !this.States.Has(hwnd)
			this.States[hwnd] := {Latched: false, Missing: 0, Last: -10000, Saved: false}
		state := this.States[hwnd]
		if !found {
			state.Missing += 1
			if state.Missing >= 3 {
				state.Latched := false
				state.Saved := false
			}
			return
		}
		state.Missing := 0
		if !state.Latched && A_TickCount - state.Last >= 10000
			this.Respawn(hwnd, job.Pid, state)
		if !state.Saved && A_TickCount - state.Last >= 10000 {
			folder := AppDir "\소매치기 범인"
			DirCreate(folder)
			stamp := A_Now
			period := Integer(FormatTime(stamp, "HH")) < 12 ? "AM" : "PM"
			base := folder "\범인 " FormatTime(stamp, "yyMMdd") "_" period "_" FormatTime(stamp, "hh_mm")
			filename := base ".jpg"
			index := 2
			while FileExist(filename) {
				filename := base "_" index ".jpg"
				index += 1
			}
			try FileMove(job.Path ".jpg", filename)
			catch as e
				throw Error("move " job.Path ".jpg -> " filename ": " e.Message)
			state.Saved := true
			this.Trace("warning photo saved HWND " hwnd " file=" filename)
		}
	}

	static FindWarning(x1, y1, x2, y2, screenshot := 1) => WarningMatcher.Find(x1, y1, x2, y2, screenshot)

	static Respawn(hwnd, pid, state) {
		if !this.PendingRespawns.Has(hwnd) {
			this.PendingRespawns[hwnd] := {Hwnd: hwnd, Pid: pid, State: state, Index: 1, Due: A_TickCount}
			this.Trace("warning detected; queued respawn HWND " hwnd " PID " pid)
		}
	}

	static ProcessRespawn() {
		global running, afkInputBusy
		if !this.Active || !running || PcRecorder.Busy {
			this.CancelRespawns()
			return
		}
		try {
			if IsObject(this.CurrentInput) {
				input := this.CurrentInput
				job := input.Job
				if input.Phase = "activate" {
					if WinActive("ahk_id " job.Hwnd) {
						input.Phase := "settle"
						input.Due := A_TickCount + 450
					} else if A_TickCount >= input.Due {
						this.ReleaseInput(true, "activation timeout")
					}
					return
				}
				if A_TickCount < input.Due
					return
				if !WinActive("ahk_id " job.Hwnd) || !this.ValidTarget(job.Hwnd, job.Pid) {
					this.ReleaseInput(true, "focus lost or target closed")
					return
				}
				if input.Phase = "settle" {
					key := this.RespawnKeys[job.Index]
					input.Key := key
					SendEvent("{" key " down}")
					job.State.Latched := true
					job.State.Last := A_TickCount
					input.Phase := "up"
					input.Due := A_TickCount + 150
				} else {
					SendEvent("{" input.Key " up}")
					this.Trace("respawn key sent HWND " job.Hwnd " PID " job.Pid " step=" job.Index "/" this.RespawnKeys.Length " key=" input.Key)
					input.Key := ""
					if job.Index = this.RespawnKeys.Length {
						this.PendingRespawns.Delete(job.Hwnd)
						this.Count += 1
						this.Trace("respawn keys completed HWND " job.Hwnd)
						SendStatus()
					} else {
						job.Index += 1
						job.Due := A_TickCount + this.RespawnDelayMs
					}
					this.ReleaseInput()
				}
				return
			}
			if this.Busy || afkInputBusy
				return
			chosen := 0
			for hwnd, job in this.PendingRespawns {
				if A_TickCount >= job.Due && (!IsObject(chosen) || job.Due < chosen.Due)
					chosen := job
			}
			if !IsObject(chosen)
				return
			if !this.ValidTarget(chosen.Hwnd, chosen.Pid) {
				this.PendingRespawns.Delete(chosen.Hwnd)
				return
			}
			this.CurrentInput := {Job: chosen, Previous: WinExist("A"), Phase: "activate", Due: A_TickCount + 1000, Key: ""}
			afkInputBusy := true
			WinActivate("ahk_id " chosen.Hwnd)
		} catch as e {
			this.Trace("respawn: " e.Message)
			this.ReleaseInput(true, "input error")
		}
	}

	static ReleaseInput(cancel := false, reason := "session stopped") {
		global afkInputBusy
		if !IsObject(this.CurrentInput)
			return
		input := this.CurrentInput
		this.CurrentInput := 0
		if input.Key != ""
			try SendEvent("{" input.Key " up}")
		if cancel {
			input.Job.State.Last := A_TickCount
			this.Trace("respawn interrupted HWND " input.Job.Hwnd " PID " input.Job.Pid " phase=" input.Phase " step=" input.Job.Index "/" this.RespawnKeys.Length " key=" this.RespawnKeys[input.Job.Index] " reason=" reason)
			if this.PendingRespawns.Has(input.Job.Hwnd)
				this.PendingRespawns.Delete(input.Job.Hwnd)
		}
		if input.Previous && WinExist("ahk_id " input.Previous) && WinActive("ahk_id " input.Job.Hwnd)
			try WinActivate("ahk_id " input.Previous)
		afkInputBusy := false
	}

	static CancelRespawns() {
		this.ReleaseInput(true)
		this.PendingRespawns := Map()
	}
}

RobberyProtectionTick(*) => RobberyProtection.Scan()
ProtectionRespawnTick(*) => RobberyProtection.ProcessRespawn()
