class ChatShortcuts {
	static Digits := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
	static Modifiers := Map("Ctrl", "$^", "Alt", "$!", "Shift", "$+", "CapsLock", "CapsLock & ")
	static Modifier := "Ctrl"
	static Enabled := false
	static DelayMs := 350
	static RepeatCount := 1
	static Phrases := Map()
	static Targets := []
	static Popup := 0
	static Queue := []
	static QueueTick := 0

	static Init() {
		global ConfigFile
		this.QueueTick := ObjBindMethod(this, "DrainQueue")
		this.Enabled := IniRead(ConfigFile, "ChatShortcuts", "Enabled", "0") = "1"
		delay := IniRead(ConfigFile, "ChatShortcuts", "DelayMs", "350")
		if IsInteger(delay) && delay >= 0 && delay <= 5000
			this.DelayMs := Integer(delay)
		count := IniRead(ConfigFile, "ChatShortcuts", "RepeatCount", "1")
		if IsInteger(count) && count >= 1 && count <= 10
			this.RepeatCount := Integer(count)
		modifier := IniRead(ConfigFile, "ChatShortcuts", "Modifier", "Ctrl")
		if this.Modifiers.Has(modifier)
			this.Modifier := modifier
		for digit in this.Digits
			this.Phrases[digit] := IniRead(ConfigFile, "ChatShortcuts", "Key" digit, "")
		for modifier, prefix in this.Modifiers {
			for digit in this.Digits {
				HotIf(ObjBindMethod(this, "CanSend", modifier, digit))
				Hotkey(prefix digit, ObjBindMethod(this, "EnqueuePhrase", digit), "On T1")
			}
		}
		HotIf()
	}

	static CanSend(modifier, digit, *) {
		if !DeviceAccess.Allowed || !this.Enabled || this.Modifier != modifier || this.Phrases[digit] = ""
			|| IsObject(this.Popup) || PcRecorder.Busy
			return false
		for target in this.Targets
			if RobberyProtection.ValidTarget(target.Hwnd, target.Pid)
				return true
		return false
	}

	static SelectTargets(webview, selection, *) {
		targets := [], seen := Map()
		for entry in StrSplit(selection, ",") {
			if !RegExMatch(entry, "^(\d+):(\d+)$", &match)
				continue
			hwnd := Integer(match[1]), pid := Integer(match[2])
			if hwnd > 0 && pid > 0 && !seen.Has(hwnd) && RobberyProtection.ValidTarget(hwnd, pid) {
				targets.Push({Hwnd: hwnd, Pid: pid})
				seen[hwnd] := true
			}
		}
		this.Targets := targets
	}

	static Toggle(webview, enabled, *) {
		global ConfigFile
		try {
			IniWrite(enabled ? "1" : "0", ConfigFile, "ChatShortcuts", "Enabled")
			this.Enabled := !!enabled
			if !this.Enabled {
				this.Queue := []
				SetTimer(this.QueueTick, 0)
			}
			this.Report(this.Enabled ? "채팅 단축키 켜짐" : "채팅 단축키 꺼짐")
		} catch {
			this.Report("채팅 설정을 저장하지 못했습니다")
		}
		this.SendState()
	}

	static SendState(*) {
		global MyGui
		MyGui.PostWebMessageAsJson('{"type":"shortcutState","content":{"enabled":' (this.Enabled ? "true" : "false") ',"modifier":"' this.Modifier '","delayMs":' this.DelayMs ',"repeatCount":' this.RepeatCount '}}')
	}

	static SetRepeatCount(webview, value, *) {
		global ConfigFile
		if !IsInteger(value) || value < 1 || value > 10 {
			this.Report("보낼 횟수는 1~10회로 입력하세요")
		} else {
			try {
				IniWrite(Integer(value), ConfigFile, "ChatShortcuts", "RepeatCount")
				this.RepeatCount := Integer(value)
				this.Report("채팅 보낼 횟수 " this.RepeatCount "회 저장됨")
			} catch {
				this.Report("보낼 횟수를 저장하지 못했습니다")
			}
		}
		this.SendState()
	}

	static SetDelay(webview, value, *) {
		global ConfigFile
		if !IsInteger(value) || value < 0 || value > 5000 {
			this.Report("딜레이는 0~5000ms로 입력하세요")
		} else {
			try {
				IniWrite(Integer(value), ConfigFile, "ChatShortcuts", "DelayMs")
				this.DelayMs := Integer(value)
				this.Report("채팅 입력 딜레이 " this.DelayMs "ms 저장됨")
			} catch {
				this.Report("딜레이를 저장하지 못했습니다")
			}
		}
		this.SendState()
	}

	static Report(message) {
		global MyGui
		try MyGui.PostWebMessageAsJson('{"type":"shortcutStatus","content":"' JsonEscape(message) '"}')
	}

	static OpenSettings(*) {
		; WebView2 초기화는 메인 WebView 콜백이 반환된 뒤 실행합니다.
		SetTimer(ObjBindMethod(this, "ShowSettings"), -1)
	}

	static ShowSettings() {
		try this.CreateSettingsWindow()
		catch as e {
			this.CloseSettings()
			this.Report("설정창을 열지 못했습니다: " e.Message)
		}
	}

	static CreateSettingsWindow() {
		global CoreMode, WebViewSettings, MyGui
		if !DeviceAccess.Allowed
			return
		if IsObject(this.Popup) {
			WinActivate("ahk_id " this.Popup.Hwnd)
			return
		}
		popup := WebViewGui("-Resize -Caption +Owner" MyGui.Hwnd, "DEAN ROBLOX · 채팅 설정", , WebViewSettings)
		this.Popup := popup
		ApplyAppWindowIcon(popup)
		popup.AreDefaultContextMenusEnabled := false
		popup.IsParentWindowDraggingEnabled := true
		popup.OnEvent("Close", ObjBindMethod(this, "CloseSettings"))
		popup.AddCallbackToScript("GetShortcutSettings", ObjBindMethod(this, "SendSettings"))
		popup.AddCallbackToScript("SaveShortcutSettings", ObjBindMethod(this, "SaveSettings"))
		popup.AddCallbackToScript("CloseShortcutSettings", ObjBindMethod(this, "CloseSettings"))
		if CoreMode
			popup.BrowseFolder(A_Args[2])
		popup.Navigate(CoreMode || A_IsCompiled ? "chat-shortcuts.html" : "http://localhost:5173/chat-shortcuts.html")
		popup.Show("w540 h680")
	}

	static CloseSettings(*) {
		if IsObject(this.Popup) {
			popup := this.Popup
			this.Popup := 0
			popup.Destroy()
		}
	}

	static SendSettings(webview, *) {
		parts := []
		for digit in this.Digits
			parts.Push('"' JsonEscape(this.Phrases[digit]) '"')
		webview.PostWebMessageAsJson('{"type":"settings","modifier":"' this.Modifier '","phrases":[' JoinArr(parts, ",") ']}')
	}

	static SaveSettings(webview, modifier, phrases*) {
		global ConfigFile
		if !DeviceAccess.Allowed || !this.Modifiers.Has(modifier) || phrases.Length != this.Digits.Length
			return
		next := Map()
		section := "Enabled=" (this.Enabled ? "1" : "0") "`nModifier=" modifier "`nDelayMs=" this.DelayMs "`nRepeatCount=" this.RepeatCount
		for index, digit in this.Digits {
			phrase := Trim(phrases[index])
			if StrLen(phrase) > 200 || RegExMatch(phrase, "[\x00-\x1f\x7f]") {
				webview.PostWebMessageAsJson('{"type":"error","message":"문구는 한 줄에 200자까지 입력할 수 있습니다."}')
				return
			}
			next[digit] := phrase
			section .= "`nKey" digit '="' phrase '"'
		}
		try IniWrite(section, ConfigFile, "ChatShortcuts")
		catch {
			webview.PostWebMessageAsJson('{"type":"error","message":"설정 파일에 저장하지 못했습니다."}')
			return
		}
		this.Modifier := modifier
		this.Phrases := next
		this.SendState()
		this.Report("채팅 문구를 저장했습니다")
		SetTimer(ObjBindMethod(this, "CloseSettings"), -1)
	}

	static EnqueuePhrase(digit, *) {
		if !this.CanSend(this.Modifier, digit)
			return
		if this.Queue.Length < 100 {
			this.Queue.Push({Digit: digit, Phrase: this.Phrases[digit], Targets: this.Targets.Clone(),
				Count: this.RepeatCount, Delay: this.DelayMs})
			SetTimer(this.QueueTick, 25)
		} else
			this.Report("채팅 대기열이 가득 찼습니다")
		; T1과 함께 길게 누른 키의 자동 반복은 무시합니다.
		KeyWait(digit)
	}

	static DrainQueue() {
		global afkInputBusy
		if !DeviceAccess.Allowed || !this.Enabled {
			this.Queue := []
			SetTimer(this.QueueTick, 0)
			return
		}
		if !this.Queue.Length {
			SetTimer(this.QueueTick, 0)
			return
		}
		if afkInputBusy || PcRecorder.Busy || IsObject(this.Popup)
			return
		for modifier in this.Modifiers
			if GetKeyState(modifier, "P")
				return
		job := this.Queue.RemoveAt(1)
		afkInputBusy := true
		try this.SendPhrase(job)
		finally afkInputBusy := false
	}

	static SendPhrase(job) {
		targets := job.Targets
		clipboardSequence := 0
		try {
			previousClipboard := ClipboardAll()
			A_Clipboard := job.Phrase
			clipboardSequence := DllCall("GetClipboardSequenceNumber", "uint")
			completed := 0
			for target in targets {
				hwnd := target.Hwnd, pid := target.Pid
				if !DeviceAccess.Allowed || !this.Enabled || PcRecorder.Busy
					break
				if DllCall("GetClipboardSequenceNumber", "uint") != clipboardSequence
					throw Error("클립보드가 변경되어 입력을 중단했습니다")
				if !this.IsSelected(hwnd, pid) || !RobberyProtection.ValidTarget(hwnd, pid)
					continue
				try {
					WinActivate("ahk_id " hwnd)
					if !WinWaitActive("ahk_id " hwnd, , 1)
						continue
					Sleep(150)
					Loop job.Count {
						this.CheckFocus(hwnd, pid)
						SendEvent("/")
						Sleep(job.Delay)
						this.CheckFocus(hwnd, pid)
						if DllCall("GetClipboardSequenceNumber", "uint") != clipboardSequence
							throw Error("클립보드가 변경되어 입력을 중단했습니다")
						SendEvent("^v")
						Sleep(200)
						this.CheckFocus(hwnd, pid)
						SendEvent("{Enter}")
						if A_Index < job.Count
							Sleep(350)
					}
					completed += 1
				} catch as e {
					if DllCall("GetClipboardSequenceNumber", "uint") != clipboardSequence
						throw e
				}
			}
			this.Report(job.Digit "번 채팅 키 전송 " completed "/" targets.Length "개 창")
		} catch as e {
			this.Report(e.Message)
		} finally {
			if clipboardSequence && DllCall("GetClipboardSequenceNumber", "uint") = clipboardSequence
				try A_Clipboard := previousClipboard
		}
	}

	static CheckFocus(hwnd, pid) {
		if !DeviceAccess.Allowed || !this.Enabled || PcRecorder.Busy || !this.IsSelected(hwnd, pid)
			|| !WinActive("ahk_id " hwnd) || !RobberyProtection.ValidTarget(hwnd, pid)
			throw Error("대상 창이 바뀌어 입력을 중단했습니다")
	}

	static IsSelected(hwnd, pid) {
		for target in this.Targets
			if target.Hwnd = hwnd && target.Pid = pid
				return true
		return false
	}
}
