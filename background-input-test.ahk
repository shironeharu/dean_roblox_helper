; ============================================================
;  백그라운드 입력 테스트 스크립트
;  목적: 로블록스 창을 활성화하지 않은 상태에서
;        ControlSend / PostMessage / SendMessage 중
;        어떤 방식이 실제로 점프를 발생시키는지 확인
;
;  사용법: 이 창이 떠 있는 동안 로블록스는 백그라운드 상태입니다.
;          아래 버튼을 누르면서 로블록스 화면을 직접 관찰하세요.
;  요구사항: AutoHotkey v2.0 이상
; ============================================================
#Requires AutoHotkey v2.0
#SingleInstance Force

targetExe := "RobloxPlayerBeta.exe"
VK_SPACE := 0x20
SPACE_SCANCODE := 0x39
WM_KEYDOWN := 0x100
WM_KEYUP := 0x101
WM_ACTIVATE := 0x0006
WM_SETFOCUS := 0x0007
WM_KILLFOCUS := 0x0008

MainGui := Gui("+AlwaysOnTop", "백그라운드 입력 테스트")
MainGui.SetFont("s10", "Segoe UI")
MainGui.OnEvent("Close", (*) => ExitApp())

MainGui.Add("Text", "w420", "이 창이 포커스된 상태 = 로블록스는 백그라운드입니다.")
MainGui.Add("Text", "w420", "버튼을 누르고 로블록스 화면에서 점프 여부를 직접 확인하세요.")

MainGui.Add("Text", "y+15 w80", "대상 창")
WindowSelect := MainGui.Add("DropDownList", "x+5 w300")
RefreshBtn := MainGui.Add("Button", "x+5 w60", "새로고침")
RefreshBtn.OnEvent("Click", (*) => RefreshWindows())

MainGui.Add("Text", "x10 y+15 w420", "테스트 방식")
ControlSendBtn := MainGui.Add("Button", "x10 y+5 w130 h40", "① ControlSend")
PostMsgBtn := MainGui.Add("Button", "x+10 w130 h40", "② PostMessage")
SendMsgBtn := MainGui.Add("Button", "x+10 w130 h40", "③ SendMessage")
ControlSendBtn.OnEvent("Click", (*) => RunTest("ControlSend"))
PostMsgBtn.OnEvent("Click", (*) => RunTest("PostMessage"))
SendMsgBtn.OnEvent("Click", (*) => RunTest("SendMessage"))

FindChildBtn := MainGui.Add("Button", "x10 y+10 w420", "④ 자식 창(컨트롤) 탐색")
FindChildBtn.OnEvent("Click", (*) => FindChildren())

FakeFocusBtn := MainGui.Add("Button", "x10 y+10 w420 h40", "⑤ 가짜 포커스 + ControlSend")
FakeFocusBtn.OnEvent("Click", (*) => RunTest("FakeFocus"))

MainGui.Add("Text", "x10 y+15 w420", "로그")
LogBox := MainGui.Add("Edit", "x10 w420 h180 y+5 ReadOnly -WantReturn")

MainGui.Show()
RefreshWindows()
return

; ---------------- 창 목록 ----------------
RefreshWindows() {
	global targetExe, WindowSelect

	WindowSelect.Delete()
	hwndList := WinGetList("ahk_exe " targetExe)

	if hwndList.Length = 0 {
		WindowSelect.Add(["실행 중인 로블록스 없음"])
		AddLog("로블록스 창을 찾을 수 없습니다 (ahk_exe " targetExe ")")
		return
	}

	labels := []
	for hwnd in hwndList {
		pid := WinGetPID("ahk_id " hwnd)
		title := WinGetTitle("ahk_id " hwnd)
		labels.Push(hwnd " | " (title ? title : "Roblox") " (PID " pid ")")
	}
	WindowSelect.Add(labels)
	WindowSelect.Choose(1)
	AddLog(hwndList.Length " 개의 로블록스 창을 찾았습니다")
}

GetSelectedHwnd() {
	global WindowSelect
	text := WindowSelect.Text
	if !text
		return 0
	parts := StrSplit(text, " | ")
	return Integer(parts[1])
}

; ---------------- 테스트 실행 ----------------
RunTest(method) {
	hwnd := GetSelectedHwnd()
	if !hwnd || !WinExist("ahk_id " hwnd) {
		AddLog("[" method "] 대상 창이 유효하지 않습니다")
		return
	}

	if WinActive("ahk_id " hwnd) {
		AddLog("[" method "] 경고: 로블록스가 현재 활성 창입니다. 다른 창을 클릭한 뒤 다시 테스트하세요")
	}

	switch method {
		case "ControlSend":
			ControlSend("{Space down}", , "ahk_id " hwnd)
			Sleep(50)
			ControlSend("{Space up}", , "ahk_id " hwnd)
		case "PostMessage":
			PostMessage(WM_KEYDOWN, VK_SPACE, (SPACE_SCANCODE << 16) | 1, , "ahk_id " hwnd)
			Sleep(50)
			PostMessage(WM_KEYUP, VK_SPACE, (SPACE_SCANCODE << 16) | 0xC0000001, , "ahk_id " hwnd)
		case "SendMessage":
			SendMessage(WM_KEYDOWN, VK_SPACE, (SPACE_SCANCODE << 16) | 1, , "ahk_id " hwnd)
			Sleep(50)
			SendMessage(WM_KEYUP, VK_SPACE, (SPACE_SCANCODE << 16) | 0xC0000001, , "ahk_id " hwnd)
		case "FakeFocus":
			PostMessage(WM_ACTIVATE, 1, 0, , "ahk_id " hwnd) ; WA_ACTIVE
			PostMessage(WM_SETFOCUS, 0, 0, , "ahk_id " hwnd)
			Sleep(10)
			ControlSend("{Space down}", , "ahk_id " hwnd)
			Sleep(50)
			ControlSend("{Space up}", , "ahk_id " hwnd)
			PostMessage(WM_KILLFOCUS, 0, 0, , "ahk_id " hwnd)
	}

	AddLog("[" method "] 전송 완료 → 로블록스 화면 확인")
}

; ---------------- 자식 창 탐색 ----------------
FindChildren() {
	hwnd := GetSelectedHwnd()
	if !hwnd || !WinExist("ahk_id " hwnd) {
		AddLog("대상 창이 유효하지 않습니다")
		return
	}

	global childList := []
	cb := CallbackCreate(EnumChildProc, "F", 2)
	DllCall("EnumChildWindows", "ptr", hwnd, "ptr", cb, "ptr", 0)
	CallbackFree(cb)

	if childList.Length = 0 {
		AddLog("자식 창 없음 (최상위 창 자체가 렌더링 표면)")
		return
	}
	for entry in childList
		AddLog("  ㄴ " entry)
	AddLog(childList.Length " 개의 자식 창 발견")
}

EnumChildProc(hwnd, lParam) {
	global childList
	cls := WinGetClass("ahk_id " hwnd)
	childList.Push(hwnd " - " cls)
	return true
}

; ---------------- 로그 ----------------
AddLog(msg) {
	global LogBox
	ts := FormatTime(, "HH:mm:ss")
	LogBox.Text := ts " - " msg "`r`n" LogBox.Text
}
