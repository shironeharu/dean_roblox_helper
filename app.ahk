#Requires AutoHotkey v2.0 64-bit
;@Ahk2Exe-SetName 딘 로블록스 도우미
;@Ahk2Exe-SetProductName 딘 로블록스 도우미
;@Ahk2Exe-SetDescription DEAN ROBLOX
;@Ahk2Exe-SetVersion 1.5.0.0
;@Ahk2Exe-SetCompanyName Roblox_DEAN
;@Ahk2Exe-SetCopyright Roblox_DEAN
#SingleInstance force
#Include ./require-admin.ahk

; ---------------- 실행 모드 ----------------
; 개발: `npm run dev` (Vite 서버 화면). 컴파일: 예전 방식의 단일 exe.
; 코어: 런처(exe)가 dean.dll 안의 이 스크립트를 스레드로 실행합니다. 런처가
; 인자로 "--core 화면폴더 WebView2Loader경로 설정폴더"를 넘깁니다.
CoreMode := (A_Args.Length >= 4 && A_Args[1] = "--core")
RequireAdministrator(CoreMode)
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
#Include ./session-unlocker.ahk

ConfigFile   := AppDir "\setting.dean"
; 예전 이름(setting.milky)의 설정이 있으면 새 이름으로 옮겨서 값을 유지합니다.
if (FileExist(AppDir "\setting.milky") && !FileExist(ConfigFile))
	FileMove(AppDir "\setting.milky", ConfigFile)

; ---------------- 잠수 방지 매크로 상태 ----------------
targetExe    := "RobloxPlayerBeta.exe"
running      := false
targetWindows := Map()
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
imeStates    := Map()
lastImeShown := -1
; 채팅 입력 범위: 로블록스 창(클라이언트 영역) 대비 비율(0~1)로 저장해서
; 창 위치·크기가 달라져도 같은 자리를 가리킵니다.
regionOn     := IniRead(ConfigFile, "Chat", "RegionEnabled", "0") = "1"
regionL      := IniRead(ConfigFile, "Chat", "RegionL", "")
regionT      := IniRead(ConfigFile, "Chat", "RegionT", "")
regionR      := IniRead(ConfigFile, "Chat", "RegionR", "")
regionB      := IniRead(ConfigFile, "Chat", "RegionB", "")
regionSet    := IsNumber(regionL) && IsNumber(regionT) && IsNumber(regionR) && IsNumber(regionB)
if (regionSet) {
	regionL := Float(regionL), regionT := Float(regionT), regionR := Float(regionR), regionB := Float(regionB)
	regionSet := (0 <= regionL && regionL < regionR && regionR <= 1 && 0 <= regionT && regionT < regionB && regionB <= 1)
}
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
; 좌클릭 후킹은 연타와 채팅 범위 클릭이 함께 쓰므로 같은 키에 조건이 다른 핫키를 두지 않고
; (겹치면 하나만 동작) 하나의 조건으로 합칩니다.
LClickCond := (*) => WinActive("ahk_exe " targetExe) && (holdOn || (chatEnabled && regionOn && regionSet))

WebViewSettings := {}
if (CoreMode) {
	; 캐시 폴더를 exe 옆이 아니라 사용자 폴더에 둡니다
	WebViewSettings := {DllPath: A_Args[3], DataDir: EnvGet("LOCALAPPDATA") "\DEAN_ROBLOX\webview"}
} else if (A_IsCompiled) {
	WebViewCtrl.CreateFileFromResource("64bit\WebView2Loader.dll", WebViewCtrl.TempDir)
    WebViewSettings := {DllPath: WebViewCtrl.TempDir "\64bit\WebView2Loader.dll"}
}

DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "wstr", "DEAN.ROBLOX.Helper", "int")
MyGui := WebViewGui("-Resize -Caption", "DEAN ROBLOX",, WebViewSettings)
MyGui.OnEvent("Close", mygui_Close)
MyGui.IsParentWindowDraggingEnabled := true
if (CoreMode)
	MyGui.BrowseFolder(A_Args[2])   ; 화면 파일이 풀려 있는 폴더를 ahk.localhost 로 연결
if (CoreMode || A_IsCompiled) {
	; dll 스레드가 만든 창에는 아이콘·이름이 자동으로 붙지 않으므로, 이 프로세스를 실행한
	; 런처 exe의 아이콘을 작업표시줄/창 아이콘으로 직접 지정합니다.
	; Ahk2Exe 가 /icon 으로 지정한 아이콘은 exe 안의 아이콘 ID 159 자리에 들어갑니다
	hostModule := DllCall("GetModuleHandleW", "ptr", 0, "ptr")
	hIconBig := DllCall("LoadImageW", "ptr", hostModule, "ptr", 159, "uint", 1, "int", 32, "int", 32, "uint", 0, "ptr")
	hIconSmall := DllCall("LoadImageW", "ptr", hostModule, "ptr", 159, "uint", 1, "int", 16, "int", 16, "uint", 0, "ptr")
} else {
	hIconBig := DllCall("LoadImageW", "ptr", 0, "str", A_ScriptDir "\app.ico", "uint", 1, "int", 32, "int", 32, "uint", 0x10, "ptr")
	hIconSmall := DllCall("LoadImageW", "ptr", 0, "str", A_ScriptDir "\app.ico", "uint", 1, "int", 16, "int", 16, "uint", 0x10, "ptr")
}
if (hIconBig || hIconSmall) {
	; 창이 아직 화면에 나오기 전이라 AHK의 SendMessage(숨은 창을 못 찾음) 대신 핸들로 직접 보냄
	if (hIconBig)
		DllCall("SendMessageW", "ptr", MyGui.Hwnd, "uint", 0x80, "ptr", 1, "ptr", hIconBig)     ; WM_SETICON, ICON_BIG
	if (hIconSmall)
		DllCall("SendMessageW", "ptr", MyGui.Hwnd, "uint", 0x80, "ptr", 0, "ptr", hIconSmall)   ; WM_SETICON, ICON_SMALL
	TraySetIcon("HICON:" (hIconBig ? hIconBig : hIconSmall))
}
A_IconTip := "DEAN ROBLOX"

MyGui.AddCallbackToScript("GetWindows", WebviewGetWindows)
MyGui.AddCallbackToScript("Start", WebviewStart)
MyGui.AddCallbackToScript("Stop", WebviewStop)
MyGui.AddCallbackToScript("Exit", WebviewExit)
MyGui.AddCallbackToScript("GetAfkConfig", WebviewGetAfkConfig)
MyGui.AddCallbackToScript("SetJumpKey", WebviewSetJumpKey)
MyGui.AddCallbackToScript("SetJumpCount", WebviewSetJumpCount)
MyGui.AddCallbackToScript("SetAfkInterval", WebviewSetAfkInterval)
MyGui.AddCallbackToScript("GetChatState", WebviewGetChatState)
MyGui.AddCallbackToScript("PickChatRegion", WebviewPickChatRegion)
MyGui.AddCallbackToScript("SetChatRegionEnabled", WebviewSetChatRegionEnabled)
MyGui.AddCallbackToScript("SetChatEnabled", WebviewSetChatEnabled)
MyGui.AddCallbackToScript("GetClickConfig", WebviewGetClickConfig)
MyGui.AddCallbackToScript("SetClickSetting", WebviewSetClickSetting)
MyGui.AddCallbackToScript("GetMultiState", WebviewGetMultiState)
MyGui.AddCallbackToScript("LaunchMulti", WebviewLaunchMulti)
MyGui.AddCallbackToScript("PickMultiPath", WebviewPickMultiPath)
MyGui.AddCallbackToScript("FocusRoblox", WebviewFocusRoblox)

if (A_IsCompiled || CoreMode) {
	MyGui.Navigate("index.html")
} else {
	MyGui.Navigate("http://localhost:5173")
	MyGui.Debug()
}

MyGui.Show("w380 h536")
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
		parts.Push('{"hwnd":' hwnd ',"pid":' pid ',"label":"' label '"}')
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
WebviewStart(webview, hwndList, interval, *) {
	global running, targetWindows, intervalMs, startTick, nextJumpTick, afkSec, ConfigFile

	selected := Map()
	for value in StrSplit(hwndList, ",") {
		if !IsInteger(value)
			continue
		hwnd := Integer(value)
		try {
			if WinGetProcessName("ahk_id " hwnd) = "RobloxPlayerBeta.exe"
				selected[hwnd] := WinGetPID("ahk_id " hwnd)
		}
	}
	if !selected.Count {
		MyGui.PostWebMessageAsJson('{"type":"error","content":"실행 중인 로블록스 창을 하나 이상 선택해 주세요"}')
		return
	}

	sec := Integer(interval)
	if sec < 5
		sec := 5
	afkSec := sec
	IniWrite(sec, ConfigFile, "Afk", "Interval")

	targetWindows := selected
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
	global running, targetWindows, intervalMs, nextJumpTick, jumpKey, jumpCount, holdMs
	static busy := false

	if !running || busy
		return
	busy := true
	prevHwnd := WinExist("A")
	try {
		for hwnd, pid in targetWindows.Clone() {
			if !running
				break
			try {
				if WinGetPID("ahk_id " hwnd) != pid || WinGetProcessName("ahk_id " hwnd) != "RobloxPlayerBeta.exe" {
					targetWindows.Delete(hwnd)
					continue
				}
			} catch {
				targetWindows.Delete(hwnd)
				continue
			}
			try {
				WinActivate("ahk_id " hwnd)
				if !WinWaitActive("ahk_id " hwnd, , 1)
					continue
				Loop jumpCount {
					if !running || !WinActive("ahk_id " hwnd)
						break
					SendEvent("{" jumpKey " down}")
					Sleep(holdMs)
					SendEvent("{" jumpKey " up}")
					if A_Index < jumpCount
						Sleep(100)
				}
			}
		}
	} finally {
		if prevHwnd && WinExist("ahk_id " prevHwnd)
			try WinActivate("ahk_id " prevHwnd)
		busy := false
	}
	if !targetWindows.Count {
		running := false
		SetTimer(DoJump, 0)
		SetTimer(SendStatus, 0)
		MyGui.PostWebMessageAsJson('{"type":"stopped","content":{"reason":"window_closed"}}')
		return
	}

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
	SendChatState()
}

SendChatState() {
	global chatEnabled, regionOn, regionSet

	MyGui.PostWebMessageAsJson('{"type":"chatState","content":{"enabled":' (chatEnabled ? "true" : "false") ',"regionOn":' (regionOn ? "true" : "false") ',"regionSet":' (regionSet ? "true" : "false") '}}')
}

WebviewSetChatEnabled(webview, enabled, *) {
	global chatEnabled, ConfigFile, lastImeShown

	chatEnabled := (enabled = 1 || enabled = "1" || enabled = "true")
	if (!chatEnabled) {
		; 꺼져 있을 때는 예전 입력 상태가 남아 있지 않게 비움
		lastImeShown := -1
		MyGui.PostWebMessageAsJson('{"type":"imeState","content":"unknown"}')
	}
	ApplyChatEnabled(chatEnabled)
	IniWrite(chatEnabled ? "1" : "0", ConfigFile, "Chat", "Enabled")
	UpdateChatStatus(chatEnabled ? "대기 중" : "비활성화됨")
}

; 로블록스 창에서만 활성화되는 채팅/한영 핫키를 켜고 끕니다.
; 물리 키를 가로챈 뒤 SendEvent로 재전송합니다 (기본 SendInput 방식이나 실제
; 하드웨어 키 입력 그대로는 로블록스에서 막히는 경우가 있어, 잠수 방지 매크로의
; DoJump와 동일하게 SendEvent로 재전송해야 실제로 통합니다).
ApplyChatEnabled(enabled) {
	global RobloxActiveCond, imeStates

	imeStates.Clear()
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
	global imeStates

	hwnd := WinExist("A")
	mode := GetHangulMode()
	if (mode != "")
		RememberIme(mode)
	if imeStates.Has(hwnd) && imeStates[hwnd].pid = WinGetPID("ahk_id " hwnd)
		return imeStates[hwnd].korean
	return false
}

RememberIme(korean) {
	global imeStates
	hwnd := WinActive("ahk_exe RobloxPlayerBeta.exe")
	if hwnd
		imeStates[hwnd] := {pid: WinGetPID("ahk_id " hwnd), korean: korean}
}

; 물리 한/영 키(VK_HANGUL, 0x15): 로블록스가 실제 하드웨어 키 입력은 무시해도
; SendEvent로 재전송하면 통과되는 경우가 많아, 그대로 다시 눌러줍니다.
ChatToggleHangul(*) {
	before := IsKoreanNow()
	SendEvent("{vk15}")
	RememberIme(!before)
	UpdateChatStatus(!before ? "한글 전환됨 (수동)" : "영어 전환됨 (수동)")
}

; "/" 키: 채팅을 열고, 이미 한글이면 아무것도 안 하고 영어일 때만 한 번 토글해서
; 한글로 확정합니다. 여러 번 눌러도 계속 한글로만 유지됩니다.
ChatOpenToKorean(*) {
	SendEvent("/")
	if (!IsKoreanNow()) {
		SendEvent("{vk15}")
		RememberIme(true)
	}
	UpdateChatStatus("채팅 열림 - 한글 전환됨")
}

; Enter 키: 이미 영어면 아무것도 안 하고 한글일 때만 (채팅창이 닫히기 전에)
; 한 번 토글해서 영어로 확정한 뒤 전송합니다. 여러 번 눌러도 계속 영어로만 유지됩니다.
ChatSendToEnglish(*) {
	if (IsKoreanNow()) {
		; 한글 입력 중(채팅창이 열린 상태)일 때만 전송 전에 스페이스를 먼저 누릅니다.
		; 영어 상태에서 Enter로 채팅을 열 때 스페이스가 들어가면 점프해버리기 때문입니다.
		SendEvent("{Space}")
		SendEvent("{vk15}")
		RememberIme(false)
	}
	SendEvent("{Enter}")
	UpdateChatStatus("전송 완료 - 영어로 전환됨")
}

; 로블록스가 활성화돼 있는 동안 실제 한/영 상태를 화면에 보여주고, 기억값도 맞춥니다.
PollImeState() {
	global chatEnabled, targetExe, lastImeShown, imeStates
	static lastHwnd := 0

	if (!chatEnabled || !WinActive("ahk_exe " targetExe))
		return
	mode := GetHangulMode()
	hwnd := WinExist("A")
	if (mode = lastImeShown && hwnd = lastHwnd)
		return
	lastHwnd := hwnd
	lastImeShown := mode
	if (mode != "")
		RememberIme(mode)
	for closedHwnd in imeStates.Clone()
		if !WinExist("ahk_id " closedHwnd)
			imeStates.Delete(closedHwnd)
	MyGui.PostWebMessageAsJson('{"type":"imeState","content":"' (mode = "" ? "unknown" : (mode ? "korean" : "english")) '"}')
}

UpdateChatStatus(text) {
	MyGui.PostWebMessageAsJson('{"type":"chatStatus","content":"' JsonEscape(text) '"}')
}

; ---------------- 채팅 입력 범위 (범위를 클릭하면 한글로 전환) ----------------
WebviewPickChatRegion(webview, *) {
	; 화면(WebView) 콜백을 오래 붙잡지 않도록 따로 실행
	SetTimer(PickChatRegion, -10)
}

WebviewSetChatRegionEnabled(webview, enabled, *) {
	global regionOn, ConfigFile

	regionOn := (enabled = 1 || enabled = "1" || enabled = "true")
	IniWrite(regionOn ? "1" : "0", ConfigFile, "Chat", "RegionEnabled")
	SendChatState()
}

; 로블록스 창 위에 어두운 막을 덮고, 마우스로 드래그한 사각형을 채팅 입력 범위로 저장합니다.
; ESC로 취소. 저장은 창(클라이언트 영역) 대비 비율이라 창을 옮기거나 크기를 바꿔도 유지됩니다.
PickChatRegion() {
	global targetExe, regionL, regionT, regionR, regionB, regionSet, regionOn, ConfigFile
	static picking := false

	if (picking)
		return
	hwnds := WinGetList("ahk_exe " targetExe)
	if (hwnds.Length = 0) {
		UpdateChatStatus("로블록스 창을 찾을 수 없습니다")
		return
	}
	hwnd := hwnds[1]
	try WinActivate("ahk_id " hwnd)
	try WinWaitActive("ahk_id " hwnd, , 1)
	try {
		WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
	} catch {
		UpdateChatStatus("로블록스 창 정보를 읽을 수 없습니다")
		return
	}
	if (cw < 100 || ch < 100) {
		UpdateChatStatus("로블록스 창이 너무 작거나 최소화돼 있습니다")
		return
	}

	picking := true
	CoordMode("Mouse", "Screen")
	shade := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x8000000")
	shade.BackColor := "000000"
	box := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x8000000")
	box.BackColor := "FFC800"
	cancelled := false
	x := 0, y := 0, w := 0, h := 0
	try {
		shade.Show("NoActivate x" cx " y" cy " w" cw " h" ch)
		WinSetTransparent(90, shade)
		UpdateChatStatus("채팅창 클릭 범위를 드래그하세요 (ESC 취소)")
		KeyWait("LButton")
		Loop {
			if GetKeyState("Escape") {
				cancelled := true
				break
			}
			if GetKeyState("LButton")
				break
			Sleep(10)
		}
		if (!cancelled) {
			MouseGetPos(&sx, &sy)
			sx := Min(Max(sx, cx), cx + cw)
			sy := Min(Max(sy, cy), cy + ch)
			box.Show("NoActivate x" sx " y" sy " w1 h1")
			WinSetTransparent(140, box)
			while GetKeyState("LButton") {
				if GetKeyState("Escape") {
					cancelled := true
					break
				}
				MouseGetPos(&mx, &my)
				mx := Min(Max(mx, cx), cx + cw)
				my := Min(Max(my, cy), cy + ch)
				x := Min(sx, mx), y := Min(sy, my), w := Abs(mx - sx), h := Abs(my - sy)
				box.Move(x, y, Max(w, 1), Max(h, 1))
				Sleep(10)
			}
		}
	} finally {
		shade.Destroy()
		box.Destroy()
		picking := false
	}

	if (cancelled) {
		UpdateChatStatus("범위 지정을 취소했습니다")
		return
	}
	if (w < 10 || h < 10) {
		UpdateChatStatus("범위가 너무 작습니다")
		return
	}
	regionL := Round((x - cx) / cw, 4)
	regionT := Round((y - cy) / ch, 4)
	regionR := Round((x + w - cx) / cw, 4)
	regionB := Round((y + h - cy) / ch, 4)
	regionSet := true
	regionOn := true
	IniWrite(regionL, ConfigFile, "Chat", "RegionL")
	IniWrite(regionT, ConfigFile, "Chat", "RegionT")
	IniWrite(regionR, ConfigFile, "Chat", "RegionR")
	IniWrite(regionB, ConfigFile, "Chat", "RegionB")
	IniWrite("1", ConfigFile, "Chat", "RegionEnabled")
	SendChatState()
	UpdateChatStatus("채팅 입력 범위를 저장했습니다")
	try WinActivate("ahk_id " hwnd)
}

; 좌클릭 위치가 저장된 범위 안이면 한글로 확정합니다 (이미 한글이면 아무것도 안 함).
; 실제 클릭은 ~ 로 그대로 통과하므로 채팅창 클릭 자체는 게임에 정상 전달됩니다.
ChatRegionClick(mx?, my?, hwnd?) {
	global chatEnabled, regionOn, regionSet, regionL, regionT, regionR, regionB

	if (!chatEnabled || !regionOn || !regionSet)
		return
	; 좌표와 창은 시험할 때만 직접 넘기고, 평소(핫키)에는 현재 마우스 위치와 활성 창을 씁니다
	if (!IsSet(mx) || !IsSet(my)) {
		CoordMode("Mouse", "Screen")
		MouseGetPos(&mx, &my)
	}
	; 클릭하는 순간 창이 사라지거나 활성 창이 없으면 조용히 무시 (오류 창이 뜨지 않도록)
	try {
		WinGetClientPos(&cx, &cy, &cw, &ch, IsSet(hwnd) ? "ahk_id " hwnd : "A")
	} catch {
		return
	}
	if (cw <= 0 || ch <= 0)
		return
	rx := (mx - cx) / cw
	ry := (my - cy) / ch
	if (rx < regionL || rx > regionR || ry < regionT || ry > regionB)
		return
	if (!IsKoreanNow()) {
		SendEvent("{vk15}")
		RememberIme(true)
	}
	UpdateChatStatus("범위 클릭 - 한글 전환됨")
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
	global HoldClickCond, LClickCond

	; 누르고 있는 동안 연타: 실제 클릭은 그대로 통과(~)시키고 옆에서 추가 클릭만 보냄
	; (좌클릭은 채팅 입력 범위 클릭 감지도 같은 핫키에서 처리)
	HotIf(LClickCond)
	Hotkey("~LButton", HoldClickLeft, "On")
	HotIf(HoldClickCond)
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
	; 창 맨 아래 안내 문구로 표시
	UpdateChatStatus(label (on ? " ON" : " OFF"))
}

HoldClickLeft(*) {
	global holdOn

	ChatRegionClick()
	if (holdOn)
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
