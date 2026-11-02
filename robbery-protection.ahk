; 창 캡처는 별도 프로세스에서 실행하며 게임 창을 활성화하지 않습니다.
class RobberyProtection {
	static Active := false
	static Busy := false
	static Count := 0
	static States := Map()
	static Jobs := Map()
	static CaptureErrors := Map()
	static LastCapture := 0
	static NextJumpTick := 0
	static Helper := ""
	static TempRoot := A_Temp "\DEAN-protection-" DllCall("GetCurrentProcessId")
	static MatchError := 0.15
	static Scales := [1.0, 0.95, 1.05, 0.9, 1.1, 0.85, 1.15, 0.8, 1.2, 0.75, 1.25, 0.7, 1.3, 0.65, 1.35, 0.6, 1.4, 1.45, 1.5]

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
		if !FileExist(this.Helper)
			throw Error("창 캡처 도우미를 빌드한 뒤 다시 실행해 주세요")
		DirCreate(this.TempRoot)
		DirCreate(AppDir "\소매치기 범인")
		this.CaptureErrors := Map()
		this.LastCapture := A_TickCount - 1000
		this.States := Map()
		this.Count := 0
		this.Active := true
		SetTimer(RobberyProtectionTick, 100)
		this.NextJumpTick := A_TickCount + 300000
		SetTimer(ProtectionHeartbeat, 1000)
	}

	static Stop() {
		this.Active := false
		SetTimer(RobberyProtectionTick, 0)
		SetTimer(ProtectionHeartbeat, 0)
		for hwnd, job in this.Jobs
			this.FinishJob(job)
		this.Jobs := Map()
		if DirExist(this.TempRoot)
			try DirDelete(this.TempRoot)
	}

	static Dispose() => this.Stop()

	static Scan() {
		global running, targetWindows, afkInputBusy
		if !this.Active || !running || this.Busy || afkInputBusy || PcRecorder.Busy
			return
		; 점프 시간이 되면 다음 캡처보다 먼저 처리합니다.
		if A_TickCount >= this.NextJumpTick {
			ProtectionHeartbeat()
			return
		}
		this.Busy := true
		try {
			for hwnd, job in this.Jobs.Clone() {
				exitCode := 259
				DllCall("GetExitCodeProcess", "ptr", job.Handle, "uint*", &exitCode)
				if exitCode = 259 && A_TickCount - job.Start < 2500
					continue
				this.Jobs.Delete(hwnd)
				try {
					if exitCode = 0 && FileExist(job.Path ".ready") && this.ValidTarget(hwnd, job.Pid) {
						if this.CaptureErrors.Has(hwnd)
							this.CaptureErrors.Delete(hwnd)
						this.CheckFrame(hwnd, job)
					} else
						this.CaptureErrors[hwnd] := true
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
					handle := this.CreateWorker(hwnd, pid, path)
					this.Jobs[hwnd] := {Pid: pid, Path: path, Handle: handle, Start: A_TickCount}
				}
			}
			if !targetWindows.Count {
				this.Stop()
				running := false
				SetTimer(SendStatus, 0)
				MyGui.PostWebMessageAsJson('{"type":"stopped","content":{"reason":"window_closed"}}')
			}
		} catch as e {
			WebviewStop(0)
			MyGui.PostWebMessageAsJson('{"type":"error","content":"감지 오류: ' JsonEscape(e.Message) '"}')
		} finally {
			this.Busy := false
		}
	}

	static CreateWorker(hwnd, pid, path) {
		; STARTF_FORCEOFFFEEDBACK | STARTF_USESHOWWINDOW: 실행 로딩 커서·창 표시 억제.
		startup := Buffer(104, 0)
		NumPut("uint", startup.Size, startup, 0)
		NumPut("uint", 0x81, startup, 60)
		NumPut("ushort", 0, startup, 64)
		command := '"' this.Helper '" ' hwnd ' ' pid ' "' path '"'
		commandBuffer := Buffer((StrLen(command) + 1) * 2, 0)
		StrPut(command, commandBuffer, "UTF-16")
		process := Buffer(24, 0)
		if !DllCall("CreateProcessW", "wstr", this.Helper, "ptr", commandBuffer, "ptr", 0, "ptr", 0, "int", false, "uint", 0x08000000, "ptr", 0, "ptr", 0, "ptr", startup, "ptr", process)
			throw OSError(A_LastError, "CreateProcessW", "캡처 도우미 실행 실패")
		DllCall("CloseHandle", "ptr", NumGet(process, 8, "ptr"))
		return NumGet(process, 0, "ptr")
	}

	static ValidTarget(hwnd, pid) {
		try return WinGetPID("ahk_id " hwnd) = pid && WinGetProcessName("ahk_id " hwnd) = "RobloxPlayerBeta.exe"
		catch
			return false
	}

	static FinishJob(job) {
		code := 259
		DllCall("GetExitCodeProcess", "ptr", job.Handle, "uint*", &code)
		if code = 259
			DllCall("TerminateProcess", "ptr", job.Handle, "uint", 1)
		DllCall("WaitForSingleObject", "ptr", job.Handle, "uint", 100)
		DllCall("CloseHandle", "ptr", job.Handle)
		this.CleanFiles(job.Path)
	}

	static CleanFiles(path) {
		for extension in [".bmp", ".jpg", ".ready"]
			if FileExist(path extension)
				try FileDelete(path extension)
	}

	static CheckFrame(hwnd, job) {
		global AppDir
		if !FindText().ShowPic(job.Path ".jpg", 0)
			throw Error("캡처 이미지를 읽을 수 없습니다")
		size := StrSplit(FileRead(job.Path ".ready"), ",")
		width := Integer(size[1]), height := Integer(size[2])
		searchW := Min(width, 600), searchH := Min(height, 200)
		searchX := (width - searchW) // 2
		found := this.FindWarning(searchX, 0, searchX + searchW - 1, searchH - 1, 0)
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
			FileMove(job.Path ".jpg", filename)
			state.Saved := true
		}
		if state.Latched || A_TickCount - state.Last < 10000
			return
		this.Respawn(hwnd, job.Pid, state)
	}

	static FindWarning(x1, y1, x2, y2, screenshot := 1) {
		global RobberyWarningPatterns
		; 창당 한 번만 캡처하고 나머지 배율은 같은 화면 버퍼를 재사용합니다.
		for scale in this.Scales {
			result := FindText(&fx, &fy, x1, y1, x2, y2, this.MatchError, this.MatchError, RobberyWarningPatterns, screenshot, 0, 0, 20, 10, 1, scale, scale)
			if result
				return result
			screenshot := 0
		}
		return 0
	}

	static Respawn(hwnd, pid, state) {
		global running, afkInputBusy
		previous := WinExist("A")
		afkInputBusy := true
		try {
			WinActivate("ahk_id " hwnd)
			if !WinWaitActive("ahk_id " hwnd, , 1)
				return
			Sleep(450)
			for keyIndex, key in ["Esc", "r", "Enter"] {
				if !running || !this.Active || PcRecorder.Busy || !WinActive("ahk_id " hwnd)
					return
				if WinGetPID("ahk_id " hwnd) != pid || WinGetProcessName("ahk_id " hwnd) != "RobloxPlayerBeta.exe"
					return
				; 중간에 사용자가 개입해도 Esc를 반복해 메뉴를 토글하지 않습니다.
				state.Latched := true
				state.Last := A_TickCount
				SendEvent("{" key " down}")
				try Sleep(150)
				finally SendEvent("{" key " up}")
				if keyIndex < 3
					Sleep(1800)
			}
			this.Count += 1
			SendStatus()
		} finally {
			if previous && WinExist("ahk_id " previous) && WinActive("ahk_id " hwnd)
				try WinActivate("ahk_id " previous)
			afkInputBusy := false
		}
	}
}

RobberyProtectionTick(*) => RobberyProtection.Scan()
