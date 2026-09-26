#Requires AutoHotkey v2.0 64-bit
;@Ahk2Exe-SetName 딘 로블록스 도우미
;@Ahk2Exe-SetProductName 딘 로블록스 도우미
;@Ahk2Exe-SetDescription 로블록스의 불편함 보조도구
;@Ahk2Exe-SetVersion 1.0.2.0
;@Ahk2Exe-SetCompanyName Roblox_DEAN
;@Ahk2Exe-SetCopyright Roblox_DEAN
#SingleInstance force

; ---------------- 실행 모드 ----------------
; 개발: `npm run dev` (Vite 서버 화면). 컴파일: 예전 방식의 단일 exe.
; 코어: 런처(exe)가 core.dll 안의 이 스크립트를 스레드로 실행합니다. 런처가
; 인자로 "--core 화면폴더 WebView2Loader경로 설정폴더"를 넘깁니다.
CoreMode := (A_Args.Length >= 4 && A_Args[1] = "--core")
if (CoreMode) {
	AppDir := A_Args[4]
	; 오류가 나면 설정 폴더에 기록 (dll 안에서는 콘솔이 없어서 원인 파악용)
	OnError((e, mode) => (FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " e.Message " (" e.What ", line " e.Line ")`n", AppDir "\core-error.log", "UTF-8"), 0))
} else {
	AppDir := A_ScriptDir
	SetWorkingDir(A_ScriptDir)
}

OnExit(trueExit)
SetWinDelay(-1)

#Include webview\WebViewToo.ahk

ConfigFile   := AppDir "\setting.dean"
; 예전 이름(setting.milky)의 설정이 있으면 새 이름으로 옮겨서 값을 유지합니다.
if (FileExist(AppDir "\setting.milky") && !FileExist(ConfigFile))
	FileMove(AppDir "\setting.milky", ConfigFile)

; ---------------- 잠수 방지 매크로 상태 ----------------
targetExe    := "RobloxPlayerBeta.exe"
running      := false
targetHwnd   := 0
intervalMs   := 60000
startTick    := 0
nextJumpTick := 0
jumpKey      := IniRead(ConfigFile, "Afk", "JumpKey", "Space")
jumpCount    := IniRead(ConfigFile, "Afk", "JumpCount", "1")
afkSec       := IniRead(ConfigFile, "Afk", "Interval", "60")
afkSec       := IsInteger(afkSec) ? Max(Integer(afkSec), 5) : 60
holdMs       := 50

; ---------------- 채팅 한/영 자동전환 상태 ----------------
chatEnabled  := IniRead(ConfigFile, "Chat", "Enabled", "1") = "1"
; 로블록스에서는 IME API로 현재 한/영 상태를 읽어도 정확하지 않아서(항상
; "영어"로 잘못 읽음), Windows에 상태를 물어보는 대신 우리가 직접 상태를
; 기억합니다. 한/영 키(vk15)를 누르는 모든 경로(물리 키·"/"·Enter)를 전부
; 우리 스크립트가 가로채서 대신 눌러주므로, 이 값만 잘 관리하면 실제 상태와
; 어긋날 일이 없습니다. (기능을 켤 때는 영어라고 가정)
imeIsKorean  := false
lastImeShown := -1
; HotIf 조건은 함수 객체의 동일성(identity)으로 구분되므로, 다시 호출할 때마다
; 새 람다를 만들면 이전에 등록된 변형이 실제로 꺼지지 않고 남아있게 됩니다.
; 그래서 조건 함수를 한 번만 만들어 재사용합니다.
RobloxActiveCond := (*) => WinActive("ahk_exe " targetExe)

; ---------------- 클릭 도우미 상태 ----------------
; 켜짐/꺼짐 상태는 안전을 위해 저장하지 않고 항상 꺼진 상태로 시작합니다.
holdKey      := IniRead(ConfigFile, "Click", "HoldKey", "F1")
macroKey     := IniRead(ConfigFile, "Click", "MacroKey", "F2")
macroSec     := IniRead(ConfigFile, "Click", "MacroInterval", "1")
macroButton  := IniRead(ConfigFile, "Click", "MacroButton", "LButton")
if !RegExMatch(holdKey, "^F([1-9]|1[0-2])$")
	holdKey := "F1"
if !RegExMatch(macroKey, "^F([1-9]|1[0-2])$") || macroKey = holdKey
	macroKey := (holdKey = "F2") ? "F3" : "F2"
macroSec     := IsNumber(macroSec) ? Min(Max(Float(macroSec), 0.05), 3600) : 1
if (macroButton != "LButton" && macroButton != "RButton")
	macroButton := "LButton"
holdOn       := false
macroOn      := false
regHoldKey   := ""
regMacroKey  := ""
holdClickMs  := 40
; 연타는 켜진 상태 + 로블록스 창일 때만 반응하도록 조건 함수를 한 번만 만들어 재사용
HoldClickCond := (*) => holdOn && WinActive("ahk_exe " targetExe)

WebViewSettings := {}
if (CoreMode) {
	; 캐시 폴더를 exe 옆이 아니라 사용자 폴더에 둡니다
	WebViewSettings := {DllPath: A_Args[3], DataDir: EnvGet("LOCALAPPDATA") "\DEAN_ROBLOX\webview"}
} else if (A_IsCompiled) {
	WebViewCtrl.CreateFileFromResource("64bit\WebView2Loader.dll", WebViewCtrl.TempDir)
    WebViewSettings := {DllPath: WebViewCtrl.TempDir "\64bit\WebView2Loader.dll"}
}

MyGui := WebViewGui("-Resize -Caption",,, WebViewSettings)
MyGui.OnEvent("Close", mygui_Close)
MyGui.IsParentWindowDraggingEnabled := true
if (CoreMode)
	MyGui.BrowseFolder(A_Args[2])   ; 화면 파일이 풀려 있는 폴더를 ahk.localhost 로 연결

MyGui.AddCallbackToScript("GetWindows", WebviewGetWindows)
MyGui.AddCallbackToScript("Start", WebviewStart)
MyGui.AddCallbackToScript("Stop", WebviewStop)
MyGui.AddCallbackToScript("Exit", WebviewExit)
MyGui.AddCallbackToScript("GetAfkConfig", WebviewGetAfkConfig)
MyGui.AddCallbackToScript("SetJumpKey", WebviewSetJumpKey)
MyGui.AddCallbackToScript("SetJumpCount", WebviewSetJumpCount)
MyGui.AddCallbackToScript("SetAfkInterval", WebviewSetAfkInterval)
MyGui.AddCallbackToScript("GetChatState", WebviewGetChatState)
MyGui.AddCallbackToScript("SetChatEnabled", WebviewSetChatEnabled)
MyGui.AddCallbackToScript("GetClickConfig", WebviewGetClickConfig)
MyGui.AddCallbackToScript("SetClickSetting", WebviewSetClickSetting)

if (A_IsCompiled || CoreMode) {
	MyGui.Navigate("index.html")
} else {
	MyGui.Navigate("http://localhost:5173")
	MyGui.Debug()
}

MyGui.Show("w440 h560")
ApplyChatEnabled(chatEnabled)
SetupClickHotkeys()
SetTimer(PollImeState, 400)
return

; ---------------- 로블록스 창 목록 ----------------
WebviewGetWindows(webview, *) {
	global targetExe

	parts := []
	for hwnd in WinGetList("ahk_exe " targetExe) {
		title := WinGetTitle("ahk_id " hwnd)
		pid := WinGetPID("ahk_id " hwnd)
		label := JsonEscape((title ? title : "Roblox") " (PID " pid ")")
		parts.Push('{"hwnd":' hwnd ',"label":"' label '"}')
	}

	MyGui.PostWebMessageAsJson('{"type":"windows","content":[' JoinArr(parts, ",") ']}')
}

; ---------------- 점프 키 설정 ----------------
WebviewGetAfkConfig(webview, *) {
	global jumpKey, jumpCount, afkSec

	MyGui.PostWebMessageAsJson('{"type":"afkConfig","content":{"key":"' JsonEscape(jumpKey) '","count":' Integer(jumpCount) ',"interval":' afkSec '}}')
}

WebviewSetAfkInterval(webview, interval, *) {
	global afkSec, ConfigFile

	if !IsNumber(interval)
		return
	afkSec := Max(Integer(interval), 5)
	IniWrite(afkSec, ConfigFile, "Afk", "Interval")
	WebviewGetAfkConfig(webview)
}

WebviewSetJumpKey(webview, key, *) {
	global jumpKey, ConfigFile

	jumpKey := key
	IniWrite(key, ConfigFile, "Afk", "JumpKey")
}

WebviewSetJumpCount(webview, count, *) {
	global jumpCount, ConfigFile

	n := Integer(count)
	if (n < 1)
		n := 1
	if (n > 20)
		n := 20
	jumpCount := n
	IniWrite(n, ConfigFile, "Afk", "JumpCount")
}

; ---------------- 시작 ----------------
WebviewStart(webview, hwnd, interval, *) {
	global running, targetHwnd, intervalMs, startTick, nextJumpTick

	if !WinExist("ahk_id " hwnd) {
		MyGui.PostWebMessageAsJson('{"type":"error","content":"선택한 로블록스 창을 찾을 수 없습니다"}')
		return
	}

	sec := Integer(interval)
	if sec < 5
		sec := 5
	afkSec := sec
	IniWrite(sec, ConfigFile, "Afk", "Interval")

	targetHwnd := hwnd
	intervalMs := sec * 1000
	running := true
	startTick := A_TickCount
	nextJumpTick := A_TickCount + intervalMs

	SetTimer(DoJump, intervalMs)
	SetTimer(SendStatus, 1000)
	MyGui.PostWebMessageAsJson('{"type":"started","content":{}}')
	SendStatus()
}

; ---------------- 정지 ----------------
WebviewStop(webview, *) {
	global running

	running := false
	SetTimer(DoJump, 0)
	SetTimer(SendStatus, 0)
	MyGui.PostWebMessageAsJson('{"type":"stopped","content":{"reason":"user"}}')
}

; ---------------- 종료 ----------------
WebviewExit(webview, *) {
	ExitApp(0)
}

; ---------------- 점프 입력 (잠깐만 전환 후 이전 창으로 복귀) ----------------
DoJump() {
	global running, targetHwnd, intervalMs, nextJumpTick, jumpKey, jumpCount, holdMs

	if !running
		return

	if !WinExist("ahk_id " targetHwnd) {
		running := false
		SetTimer(DoJump, 0)
		SetTimer(SendStatus, 0)
		MyGui.PostWebMessageAsJson('{"type":"stopped","content":{"reason":"window_closed"}}')
		return
	}

	alreadyActive := WinActive("ahk_id " targetHwnd)
	prevHwnd := 0

	if !alreadyActive {
		prevHwnd := WinExist("A")
		WinActivate("ahk_id " targetHwnd)
		WinWaitActive("ahk_id " targetHwnd, , 1)
	}

	Loop jumpCount {
		SendEvent("{" jumpKey " down}")
		Sleep(holdMs)
		SendEvent("{" jumpKey " up}")
		if (A_Index < jumpCount)
			Sleep(100)
	}

	if !alreadyActive && prevHwnd && prevHwnd != targetHwnd && WinExist("ahk_id " prevHwnd)
		WinActivate("ahk_id " prevHwnd)

	nextJumpTick := A_TickCount + intervalMs
}

; ---------------- 경과 시간 / 다음 점프까지 남은 시간 통지 ----------------
SendStatus() {
	global running, startTick, nextJumpTick

	if !running
		return

	elapsed := Round((A_TickCount - startTick) / 1000)
	nextIn := Round((nextJumpTick - A_TickCount) / 1000)
	if nextIn < 0
		nextIn := 0

	MyGui.PostWebMessageAsJson('{"type":"status","content":{"elapsed":' elapsed ',"nextIn":' nextIn '}}')
}

; ---------------- 채팅 한/영 자동전환 ----------------
WebviewGetChatState(webview, *) {
	global chatEnabled

	MyGui.PostWebMessageAsJson('{"type":"chatState","content":{"enabled":' (chatEnabled ? "true" : "false") '}}')
}

WebviewSetChatEnabled(webview, enabled, *) {
	global chatEnabled, ConfigFile

	chatEnabled := (enabled = 1 || enabled = "1" || enabled = "true")
	ApplyChatEnabled(chatEnabled)
	IniWrite(chatEnabled ? "1" : "0", ConfigFile, "Chat", "Enabled")
	UpdateChatStatus(chatEnabled ? "대기 중" : "비활성화됨")
}

; 로블록스 창에서만 활성화되는 채팅/한영 핫키를 켜고 끕니다.
; 물리 키를 가로챈 뒤 SendEvent로 재전송합니다 (기본 SendInput 방식이나 실제
; 하드웨어 키 입력 그대로는 로블록스에서 막히는 경우가 있어, 잠수 방지 매크로의
; DoJump와 동일하게 SendEvent로 재전송해야 실제로 통합니다).
ApplyChatEnabled(enabled) {
	global RobloxActiveCond, imeIsKorean

	imeIsKorean := false
	HotIf(RobloxActiveCond)

	if (enabled) {
		Hotkey("vk15", ChatToggleHangul, "On")   ; 실제 한/영 키 자체를 강제로 통하게 함
		Hotkey("/", ChatOpenToKorean, "On")
		Hotkey("Enter", ChatSendToEnglish, "On")
	} else {
		for k in ["vk15", "/", "Enter"]
			try Hotkey(k, "Off")
	}

	HotIf()
}

; 현재 한/영 상태를 실제로 읽습니다. 1 = 한글, 0 = 영어, "" = 읽을 수 없음.
; 한국어 IME의 한/영은 "IME 열림 상태"가 아니라 "변환 모드"의 한글 비트(0x1)이고,
; 창에 연결된 IME 컨텍스트(ImmGetContext)는 로블록스에서 비어 있어서, 창의 기본 IME
; 윈도우(ImmGetDefaultIMEWnd)에 WM_IME_CONTROL(IMC_GETCONVERSIONMODE)을 보내 읽습니다.
GetHangulMode() {
	hwnd := WinExist("A")
	if !hwnd
		return ""
	ime := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
	if !ime
		return ""
	mode := 0
	if !DllCall("SendMessageTimeout", "ptr", ime, "uint", 0x283, "ptr", 1, "ptr", 0, "uint", 2, "uint", 300, "ptr*", &mode)
		return ""
	return (mode & 1) ? 1 : 0
}

; 실제 상태를 읽을 수 있으면 그 값으로 우리가 기억하는 값을 바로잡고, 읽을 수
; 없을 때만 기억해둔 값을 씁니다. (시작할 때 이미 한글이었던 경우도 여기서 맞춰짐)
IsKoreanNow() {
	global imeIsKorean

	mode := GetHangulMode()
	if (mode != "")
		imeIsKorean := mode
	return imeIsKorean
}

; 물리 한/영 키(VK_HANGUL, 0x15): 로블록스가 실제 하드웨어 키 입력은 무시해도
; SendEvent로 재전송하면 통과되는 경우가 많아, 그대로 다시 눌러줍니다.
ChatToggleHangul(*) {
	global imeIsKorean

	before := IsKoreanNow()
	SendEvent("{vk15}")
	imeIsKorean := !before
	UpdateChatStatus(imeIsKorean ? "한글 전환됨 (수동)" : "영어 전환됨 (수동)")
}

; "/" 키: 채팅을 열고, 이미 한글이면 아무것도 안 하고 영어일 때만 한 번 토글해서
; 한글로 확정합니다. 여러 번 눌러도 계속 한글로만 유지됩니다.
ChatOpenToKorean(*) {
	global imeIsKorean

	SendEvent("/")
	if (!IsKoreanNow()) {
		SendEvent("{vk15}")
		imeIsKorean := true
	}
	UpdateChatStatus("채팅 열림 - 한글 전환됨")
}

; Enter 키: 이미 영어면 아무것도 안 하고 한글일 때만 (채팅창이 닫히기 전에)
; 한 번 토글해서 영어로 확정한 뒤 전송합니다. 여러 번 눌러도 계속 영어로만 유지됩니다.
ChatSendToEnglish(*) {
	global imeIsKorean

	if (IsKoreanNow()) {
		; 한글 입력 중(채팅창이 열린 상태)일 때만 전송 전에 스페이스를 먼저 누릅니다.
		; 영어 상태에서 Enter로 채팅을 열 때 스페이스가 들어가면 점프해버리기 때문입니다.
		SendEvent("{Space}")
		SendEvent("{vk15}")
		imeIsKorean := false
	}
	SendEvent("{Enter}")
	UpdateChatStatus("전송 완료 - 영어로 전환됨")
}

; 로블록스가 활성화돼 있는 동안 실제 한/영 상태를 화면에 보여주고, 기억값도 맞춥니다.
PollImeState() {
	global chatEnabled, targetExe, lastImeShown, imeIsKorean

	if (!chatEnabled || !WinActive("ahk_exe " targetExe))
		return
	mode := GetHangulMode()
	if (mode = lastImeShown)
		return
	lastImeShown := mode
	if (mode != "")
		imeIsKorean := mode
	MyGui.PostWebMessageAsJson('{"type":"imeState","content":"' (mode = "" ? "unknown" : (mode ? "korean" : "english")) '"}')
}

UpdateChatStatus(text) {
	MyGui.PostWebMessageAsJson('{"type":"chatStatus","content":"' JsonEscape(text) '"}')
}

; ---------------- 클릭 도우미 ----------------
; 프론트에서 이름/값 한 쌍으로 설정을 바꿉니다 (holdKey, macroKey, macroInterval,
; macroButton, holdEnabled, macroEnabled).
WebviewGetClickConfig(webview, *) {
	SendClickConfig()
}

WebviewSetClickSetting(webview, name, value, *) {
	global holdKey, macroKey, macroSec, macroButton, macroOn, ConfigFile

	switch name {
		case "holdKey", "macroKey":
			if !RegExMatch(value, "^F([1-9]|1[0-2])$")
				return
			otherKey := (name = "holdKey") ? macroKey : holdKey
			if (value = otherKey) {
				MyGui.PostWebMessageAsJson('{"type":"clickError","content":"연타와 클릭 매크로의 온오프 키가 겹칩니다"}')
				SendClickConfig()
				return
			}
			if (name = "holdKey") {
				holdKey := value
				IniWrite(value, ConfigFile, "Click", "HoldKey")
			} else {
				macroKey := value
				IniWrite(value, ConfigFile, "Click", "MacroKey")
			}
			ApplyClickToggleKeys()
		case "macroInterval":
			if IsNumber(value) {
				macroSec := Round(Min(Max(Float(value), 0.05), 3600), 2)
				IniWrite(macroSec, ConfigFile, "Click", "MacroInterval")
				if (macroOn)
					SetTimer(MacroClickTick, Round(macroSec * 1000))
			}
			SendClickConfig()
		case "macroButton":
			if (value = "LButton" || value = "RButton") {
				macroButton := value
				IniWrite(value, ConfigFile, "Click", "MacroButton")
			}
		case "holdEnabled":
			SetClickOn("hold", value = "1")
		case "macroEnabled":
			SetClickOn("macro", value = "1")
	}
}

; 온오프 키(F1~F12)를 로블록스 창에서만 동작하도록 (재)등록합니다.
ApplyClickToggleKeys() {
	global holdKey, macroKey, regHoldKey, regMacroKey, RobloxActiveCond

	HotIf(RobloxActiveCond)
	for k in [regHoldKey, regMacroKey] {
		if (k != "")
			try Hotkey(k, "Off")
	}
	Hotkey(holdKey, ToggleHoldClick, "On")
	Hotkey(macroKey, ToggleMacroClick, "On")
	HotIf()

	regHoldKey := holdKey
	regMacroKey := macroKey
}

SetupClickHotkeys() {
	global HoldClickCond

	; 누르고 있는 동안 연타: 실제 클릭은 그대로 통과(~)시키고 옆에서 추가 클릭만 보냄
	HotIf(HoldClickCond)
	Hotkey("~LButton", HoldClickLeft, "On")
	Hotkey("~RButton", HoldClickRight, "On")
	HotIf()

	ApplyClickToggleKeys()
}

ToggleHoldClick(*) {
	global holdOn

	SetClickOn("hold", !holdOn)
}

ToggleMacroClick(*) {
	global macroOn

	SetClickOn("macro", !macroOn)
}

SetClickOn(which, on) {
	global holdOn, macroOn, macroSec

	if (which = "hold") {
		holdOn := on
		label := "연타"
	} else {
		macroOn := on
		SetTimer(MacroClickTick, on ? Round(macroSec * 1000) : 0)
		label := "클릭 매크로"
	}

	SendClickState()
	; 게임 화면에서도 상태를 알 수 있도록 잠깐 표시
	ToolTip(label (on ? " ON" : " OFF"))
	SetTimer(() => ToolTip(), -1000)
}

HoldClickLeft(*) {
	HoldClickLoop("LButton")
}

HoldClickRight(*) {
	HoldClickLoop("RButton")
}

; 버튼을 누르고 있는 동안 계속 눌렀다 뗐다를 반복합니다. 짧게 톡 누르고 떼면
; (0.15초 이내) 일반 클릭 한 번으로 두고 아무것도 추가하지 않습니다.
; 매 반복을 "뗌 → 누름" 순서로 끝내서, 반복 중에도 버튼이 눌린 상태가 유지되고
; 실제로 손을 뗄 때 자연스럽게 마무리됩니다.
HoldClickLoop(btn) {
	global holdOn, holdClickMs

	if KeyWait(btn, "P T0.15")
		return
	while (holdOn && GetKeyState(btn, "P")) {
		SendEvent("{" btn " up}")
		Sleep(10)
		SendEvent("{" btn " down}")
		Sleep(holdClickMs)
	}
}

; 클릭 매크로: 설정한 간격마다 현재 마우스 위치에서 선택한 버튼을 클릭합니다.
; 로블록스 창이 활성화돼 있을 때만 클릭합니다.
MacroClickTick() {
	global macroButton, targetExe

	if !WinActive("ahk_exe " targetExe)
		return
	SendEvent("{" macroButton " down}")
	Sleep(10)
	SendEvent("{" macroButton " up}")
}

SendClickState() {
	global holdOn, macroOn

	MyGui.PostWebMessageAsJson('{"type":"clickState","content":{"holdOn":' (holdOn ? "true" : "false") ',"macroOn":' (macroOn ? "true" : "false") '}}')
}

SendClickConfig() {
	global holdKey, macroKey, macroSec, macroButton, holdOn, macroOn

	sec := RTrim(RTrim(Round(macroSec, 2), "0"), ".")
	MyGui.PostWebMessageAsJson('{"type":"clickConfig","content":{"holdKey":"' holdKey '","macroKey":"' macroKey '","interval":' sec ',"button":"' macroButton '","holdOn":' (holdOn ? "true" : "false") ',"macroOn":' (macroOn ? "true" : "false") '}}')
}

; ---------------- 유틸 ----------------
JsonEscape(s) {
	s := StrReplace(s, "\", "\\")
	s := StrReplace(s, '"', '\"')
	return s
}

JoinArr(arr, sep) {
	out := ""
	for i, v in arr
		out .= (i > 1 ? sep : "") v
	return out
}

mygui_Close(*) {
	trueExit(0, 0)
}
trueExit(ExitReason, ExitCode){
	ExitApp(ExitCode)
}

#Include ./resource.ahk

;@Ahk2Exe-IgnoreBegin
; For dev
F6::ExitApp(5173)
;@Ahk2Exe-IgnoreEnd
