; PC 전체 입력 녹화. 파일에는 명령어 대신 검증된 숫자 이벤트만 저장합니다.
class PcRecorder {
	static Mode := "idle"
	static Events := []
	static Duration := 0
	static Started := 0
	static Geometry := ""
	static Message := "녹화 전 대상 창과 입력 언어를 준비해 주세요"
	static Hook := 0
	static MouseBindings := Map()
	static Held := Map()
	static Index := 1
	static Round := 1
	static Repeats := 1
	static Speed := 1
	static PreviousMouse := ""
	static Keys := Map("record", "F8", "play", "F9", "stop", "F10")
	static PausedHeld := Map()
	static PausedAt := 0
	static Busy => this.Mode != "idle"

	static Init() {
		global ConfigFile, holdKey, macroKey
		used := Map(holdKey, true, macroKey, true)
		for action, fallback in this.Keys {
			key := IniRead(ConfigFile, "Recorder", action, fallback)
			if !this.ValidKey(key) || used.Has(key) {
				for candidate in ["F8", "F9", "F10", "F11", "F12", "Insert", "Home", "PgUp", "PgDn", "Delete", "End"]
					if !used.Has(candidate) {
						key := candidate
						break
					}
			}
			this.Keys[action] := key, used[key] := true
		}
		HotIf()
		for action, key in this.Keys
			Hotkey("$*" key, ObjBindMethod(this, "Control", action), "On")
		HotIf((*) => this.Busy)
		Hotkey("$^!Escape", (*) => this.Stop())
		HotIf()
		for vk, name in Map(1, "LButton", 2, "RButton", 4, "MButton", 5, "XButton1", 6, "XButton2") {
			this.MouseBindings["~*" name] := ObjBindMethod(this, "MouseButton", vk, 1)
			this.MouseBindings["~*" name " Up"] := ObjBindMethod(this, "MouseButton", vk, 0)
		}
		for n, name in ["WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
			this.MouseBindings["~*" name] := ObjBindMethod(this, "Wheel", n)
	}

	static Screen() => SysGet(76) "," SysGet(77) "," SysGet(78) "," SysGet(79)
	static ValidKey(key) => RegExMatch(key, "^(F([1-9]|1[0-2])|Insert|Home|PgUp|PgDn|Delete|End)$")
	static UsesKey(key) {
		for action, assigned in this.Keys
			if assigned = key
				return true
		return false
	}
	static Control(action, *) {
		key := this.Keys[action]
		switch action {
			case "record": this.Record()
			case "play": this.Play(this.Repeats, this.Speed)
			case "stop": this.Stop()
		}
		KeyWait(key)
	}
	static SetKey(action, key) {
		global ConfigFile, holdKey, macroKey
		if this.Busy || !this.Keys.Has(action) || !this.ValidKey(key)
			return
		old := this.Keys[action]
		try {
			if key = old
				return
			if this.UsesKey(key) || key = holdKey || key = macroKey
				throw Error("다른 녹화 단축키 또는 클릭도우미 키와 겹칩니다")
			HotIf()
			Hotkey("$*" key, ObjBindMethod(this, "Control", action), "On")
			try IniWrite(key, ConfigFile, "Recorder", action)
			catch as e {
				Hotkey("$*" key, "Off")
				throw e
			}
			Hotkey("$*" old, "Off")
			this.Keys[action] := key
			this.Message := "단축키를 저장했습니다"
		} catch as e
			this.Message := e.Message
		this.Publish()
	}

	static Publish(*) {
		global MyGui
		elapsed := this.Mode = "recording" ? A_TickCount - this.Started : this.Duration
		message := JsonEscape(StrReplace(StrReplace(this.Message, "`r", " "), "`n", " "))
		MyGui.PostWebMessageAsJson('{"type":"recorderState","content":{"mode":"' this.Mode '","count":' this.Events.Length ',"seconds":' Round(elapsed / 1000, 1) ',"round":' this.Round ',"recordKey":"' this.Keys["record"] '","playKey":"' this.Keys["play"] '","stopKey":"' this.Keys["stop"] '","message":"' message '"}}')
	}

	static PauseHelpers() {
		global running, holdOn, macroOn, regHoldKey, regMacroKey
		if running
			WebviewStop(0)
		SetClickOn("hold", false)
		SetClickOn("macro", false)
		ApplyChatEnabled(false)
		HotIfWinActive("ahk_exe RobloxPlayerBeta.exe")
		for key in [regHoldKey, regMacroKey, "~LButton", "~RButton"]
			if key != ""
				try Hotkey(key, "Off")
		HotIf()
	}

	static Arm(mode) {
		global afkInputBusy, RobloxMulti
		if this.Busy
			return false
		if afkInputBusy || RobloxMulti.Busy {
			this.Message := "현재 도우미 동작이 끝난 뒤 다시 시도해 주세요"
			this.Publish()
			return false
		}
		this.Mode := mode
		try this.PauseHelpers()
		catch as e {
			this.Stop(e.Message)
			return false
		}
		this.Message := "2초 뒤 시작 · 대상 창을 준비하세요 · Ctrl+Alt+Esc 취소"
		this.Started := A_TickCount
		SetTimer(RecorderTick, 10)
		SetTimer(RecorderState, 500)
		this.Publish()
		return true
	}

	static Record() {
		if this.Busy
			return
		if this.Events.Length && MsgBox("기존 녹화를 새 녹화로 바꿀까요", "녹화 매크로", "YesNo Icon?") != "Yes"
			return
		this.Arm("record-wait")
	}

	static Play(repeats, speed) {
		if this.Mode = "playing" {
			Critical("On")
			this.PausedAt := (A_TickCount - this.Started) * this.Speed
			this.Mode := "paused"
			this.PausedHeld := this.Held.Clone()
			this.Release()
			Critical("Off")
			this.Message := "일시정지 · 재생을 누르면 이어서 재생합니다"
			this.Publish()
			return
		}
		if this.Mode = "paused" {
			if this.Geometry != this.Screen() {
				this.Message := "녹화 당시의 모니터 배치와 해상도로 되돌려 주세요"
				this.Publish()
				return
			}
			this.Mode := "resume-wait", this.Started := A_TickCount
			this.Message := "2초 뒤 이어서 재생 · 대상 창을 준비하세요"
			this.Publish()
			return
		}
		if this.Busy
			return
		try {
			if !IsInteger(repeats) || repeats < 0 || repeats > 9999 || !IsNumber(speed) || speed < 0.25 || speed > 4
				throw Error("반복은 0~9999회, 속도는 0.25~4배로 설정해 주세요")
			if !this.Events.Length
				throw Error("먼저 녹화하거나 파일을 불러와 주세요")
			if this.Geometry != this.Screen()
				throw Error("녹화 당시와 모니터 배치 또는 해상도가 다릅니다")
			this.Repeats := Integer(repeats), this.Speed := Float(speed)
			this.Arm("play-wait")
		} catch as e {
			this.Message := e.Message
			this.Publish()
		}
	}

	static Tick() {
		try {
			if InStr(this.Mode, "-wait") {
				if A_TickCount - this.Started < 2000
					return
				; 시작 단축키와 버튼을 놓은 후 시작해 녹화에 섞이지 않게 합니다.
				for key in ["Ctrl", "Alt", "Shift", "LWin", "RWin", "LButton", "RButton", this.Keys["record"], this.Keys["play"], this.Keys["stop"]]
					if GetKeyState(key, "P")
						return
				if this.Mode = "record-wait"
					this.BeginRecord()
				else if this.Mode = "resume-wait" {
					Critical("On")
					try {
						this.Held := this.PausedHeld.Clone()
						for key in this.Held
							SendEvent("{Blind}{" key " down}")
						this.PausedHeld := Map()
						this.Started := A_TickCount - this.PausedAt / this.Speed
						this.Mode := "playing", this.Message := "이어서 재생 중"
					} finally {
						Critical("Off")
					}
				} else {
					this.Mode := "playing", this.Index := 1, this.Round := 1
					this.Started := A_TickCount, this.Held := Map()
					this.Message := "재생 중 · 설정한 중단 키 또는 Ctrl+Alt+Esc 중단"
				}
				this.Publish()
			} else if this.Mode = "recording" {
				this.Move()
				if A_TickCount - this.Started >= 1800000
					this.Stop("30분 녹화 한도에 도달했습니다")
			} else if this.Mode = "playing" {
				elapsed := (A_TickCount - this.Started) * this.Speed
				Loop 40 {
					if this.Mode != "playing" || this.Index > this.Events.Length
						break
					event := this.Events[this.Index]
					if event[1] > elapsed
						break
					this.Emit(event)
					this.Index++
				}
				if this.Index > this.Events.Length && elapsed >= this.Duration {
					this.Release()
					if this.Repeats && this.Round >= this.Repeats
						this.Stop("재생 완료")
					else {
						this.Round++, this.Index := 1, this.Started := A_TickCount
					}
				}
			}
		} catch as e
			this.Stop("중단: " e.Message)
	}

	static BeginRecord() {
		this.Events := [], this.Duration := 0, this.Geometry := this.Screen()
		this.Started := A_TickCount, this.PreviousMouse := "", this.Mode := "recording"
		this.Hook := InputHook("V L0")
		this.Hook.MinSendLevel := 1
		this.Hook.KeyOpt("{All}", "N")
		this.Hook.OnKeyDown := ObjBindMethod(this, "Key", 1)
		this.Hook.OnKeyUp := ObjBindMethod(this, "Key", 0)
		this.Hook.Start()
		HotIf()
		for key, callback in this.MouseBindings
			Hotkey(key, callback, "On")
		this.Move()
		this.Message := "PC 전체 녹화 중 · 설정한 중단 키 또는 Ctrl+Alt+Esc 중단"
	}

	static Add(kind, a, b := 0, c := 0) {
		if this.Mode != "recording"
			return
		if this.Events.Length >= 100000 {
			this.Stop("입력 10만 개 한도에 도달했습니다")
			return
		}
		this.Events.Push([A_TickCount - this.Started, kind, a, b, c])
	}

	static Key(down, hook, vk, sc) {
		for action, key in this.Keys
			if vk = GetKeyVK(key)
				return
		if vk = 0x1B && GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P")
			return
		this.Add("K", vk, sc, down)
	}

	static Move() {
		CoordMode("Mouse", "Screen")
		MouseGetPos(&x, &y)
		position := x "," y
		if position != this.PreviousMouse {
			this.PreviousMouse := position
			this.Add("M", x, y)
		}
	}

	static MouseButton(vk, down, *) {
		global MyGui
		MouseGetPos(, , &window)
		if window && DllCall("GetAncestor", "ptr", window, "uint", 2, "ptr") = MyGui.Hwnd
			return
		this.Move()
		this.Add("B", vk, down)
	}

	static Wheel(direction, *) {
		this.Move()
		this.Add("W", direction)
	}

	static Emit(event) {
		Critical("On")
		try {
		SetKeyDelay(-1, -1)
		SetMouseDelay(-1)
		CoordMode("Mouse", "Screen")
		switch event[2] {
			case "M": MouseMove(event[3], event[4], 0)
			case "K", "B":
				key := Format("vk{:02X}", event[3])
				if event[2] = "B"
					key := Map(1, "LButton", 2, "RButton", 4, "MButton", 5, "XButton1", 6, "XButton2")[event[3]]
				if event[2] = "K" && event[4]
					key .= Format("sc{:03X}", event[4])
				down := event[2] = "K" ? event[5] : event[4]
				; 정지 시 주입한 키만 해제합니다.
				if down
					this.Held[key] := true
				else if this.Held.Has(key)
					this.Held.Delete(key)
				SendEvent("{Blind}{" key (down ? " down}" : " up}"))
			case "W": Click(["WheelUp", "WheelDown", "WheelLeft", "WheelRight"][event[3]])
		}
		} finally {
			Critical("Off")
		}
	}

	static Release() {
		for key in this.Held
			try SendEvent("{Blind}{" key " up}")
		this.Held := Map()
	}

	static Stop(message := "정지됨") {
		global chatEnabled
		if !this.Busy
			return
		wasRecording := this.Mode = "recording"
		if wasRecording
			this.Duration := Max(1, A_TickCount - this.Started)
		this.Mode := "idle"
		SetTimer(RecorderTick, 0)
		SetTimer(RecorderState, 0)
		if this.Hook {
			this.Hook.Stop()
			this.Hook := 0
		}
		HotIf()
		for key in this.MouseBindings
			try Hotkey(key, "Off")
		if wasRecording {
			; 정지 조합키의 끝부분은 재생하지 않습니다.
			while this.Events.Length {
				last := this.Events[-1]
				if last[2] != "K" || !(last[3] >= 0xA2 && last[3] <= 0xA5)
					break
				this.Events.Pop()
			}
		}
		this.Release()
		this.PausedHeld := Map()
		ApplyChatEnabled(chatEnabled)
		SetupClickHotkeys()
		this.Message := message
		this.Publish()
	}

	static Save() {
		if this.Busy || !this.Events.Length
			return
		path := FileSelect("S16", "녹화.deanrec", "녹화 저장", "DEAN 녹화 (*.deanrec)")
		if !path
			return
		if !RegExMatch(path, "i)\.deanrec$") {
			path .= ".deanrec"
			if FileExist(path) && MsgBox("같은 이름의 녹화 파일을 덮어쓸까요", "녹화 저장", "YesNo Icon?") != "Yes"
				return
		}
		try {
			text := "DEANREC1|" this.Duration "|" this.Geometry "`n"
			for event in this.Events
				text .= JoinArr(event, "|") "`n"
			FileOpen(path, "w", "UTF-8").Write(text)
			SplitPath(path, &filename)
			this.Message := "저장 완료 · " filename
		} catch as e
			this.Message := "저장 실패: " e.Message
		this.Publish()
	}

	static Parse(text) {
		lines := StrSplit(Trim(text, " `t`r`n"), "`n", "`r")
		if !lines.Length
			throw Error("빈 녹화 파일입니다")
		header := StrSplit(lines[1], "|")
		if header.Length != 3 || header[1] != "DEANREC1" || !IsInteger(header[2]) || header[2] < 1 || header[2] > 1800000
			throw Error("지원하지 않는 녹화 파일입니다")
		if !RegExMatch(header[3], "^-?\d+,-?\d+,\d+,\d+$") || lines.Length > 100001
			throw Error("녹화 파일 범위를 벗어났습니다")
		events := [], previous := 0
		for index, line in lines {
			if index = 1
				continue
			fields := StrSplit(line, "|")
			if fields.Length != 5
				throw Error("녹화 입력 형식 오류")
			for n in [1, 3, 4, 5] {
				if !IsInteger(fields[n])
					throw Error("숫자가 아닌 녹화 입력입니다")
				fields[n] := Integer(fields[n])
			}
			if fields[1] < previous || fields[1] > Integer(header[2])
				throw Error("녹화 시간 순서 오류")
			previous := fields[1]
			a := fields[3], b := fields[4], c := fields[5]
			switch fields[2] {
				case "K": valid := a >= 8 && a <= 254 && b >= 0 && b <= 511 && (c = 0 || c = 1)
				case "M": valid := Abs(a) <= 100000 && Abs(b) <= 100000 && c = 0
				case "B": valid := (a = 1 || a = 2 || a = 4 || a = 5 || a = 6) && (b = 0 || b = 1) && c = 0
				case "W": valid := a >= 1 && a <= 4 && b = 0 && c = 0
				default: valid := false
			}
			if !valid
				throw Error("지원하지 않는 입력 값입니다")
			events.Push(fields)
		}
		if !events.Length
			throw Error("녹화된 입력이 없습니다")
		return {events: events, duration: Integer(header[2]), geometry: header[3]}
	}

	static Load() {
		if this.Busy
			return
		path := FileSelect(1, , "녹화 불러오기", "DEAN 녹화 (*.deanrec)")
		if !path
			return
		try {
			if FileGetSize(path) > 8388608
				throw Error("8MB 이하의 녹화 파일만 불러올 수 있습니다")
			loaded := this.Parse(FileRead(path, "UTF-8"))
			this.Events := loaded.events, this.Duration := loaded.duration, this.Geometry := loaded.geometry
			SplitPath(path, &filename)
			this.Message := "불러옴 · " filename
		} catch as e
			this.Message := "불러오기 실패: " e.Message
		this.Publish()
	}
}

RecorderTick() => PcRecorder.Tick()
RecorderState(*) => PcRecorder.Publish()
WebviewRecord(*) => PcRecorder.Record()
WebviewRecordStop(*) => PcRecorder.Stop()
WebviewRecordPlay(webview, repeats, speed, *) => PcRecorder.Play(repeats, speed)
WebviewRecordSave(*) => PcRecorder.Save()
WebviewRecordLoad(*) => PcRecorder.Load()
WebviewRecordKey(webview, action, key, *) => PcRecorder.SetKey(action, key)
WebviewRecordOptions(webview, repeats, speed, *) {
	if !PcRecorder.Busy && IsInteger(repeats) && repeats >= 0 && repeats <= 9999 && IsNumber(speed) && speed >= 0.25 && speed <= 4 {
		PcRecorder.Repeats := Integer(repeats)
		PcRecorder.Speed := Float(speed)
	}
}
