#Requires AutoHotkey v2.0 64-bit
;@Ahk2Exe-SetName 딘 로블록스 도우미
;@Ahk2Exe-SetProductName 딘 로블록스 도우미
;@Ahk2Exe-SetDescription 로블록스의 불편함 보조도구
;@Ahk2Exe-SetVersion 1.2.0.0
;@Ahk2Exe-SetCompanyName Roblox_DEAN
;@Ahk2Exe-SetCopyright Roblox_DEAN
#SingleInstance Force
SetWorkingDir(A_ScriptDir)

; 런처: 같은 폴더의 dean.dll(화면 + 기능)을 실행하고, 시작할 때 GitHub 릴리스의
; 버전과 다르면(더 높으면) 새 dean.dll을 받아 교체합니다.
; 업데이트 실패(오프라인, 해시 불일치 등)는 조용히 무시하고 기존 dean.dll로 실행합니다.

UPDATE_BASE := "https://github.com/shironeharu/dean_roblox_helper/releases/latest/download/"
CoreDll     := A_ScriptDir "\dean.dll"
LogFile     := A_ScriptDir "\launcher.log"
APP_TITLE   := "딘 로블록스 도우미"

CheckUpdate()

if !FileExist(CoreDll) {
	MsgBox("dean.dll 을 찾을 수 없고 받아오지도 못했습니다.`n인터넷 연결을 확인하거나 dean.dll 을 이 폴더에 넣어주세요.", APP_TITLE, "Iconx")
	ExitApp(1)
}

hMod := DllCall("LoadLibraryW", "str", CoreDll, "ptr")
if !hMod {
	MsgBox("dean.dll 을 불러올 수 없습니다 (오류 " A_LastError ").`n파일이 손상됐을 수 있습니다. 삭제 후 다시 실행하면 새로 받아옵니다.", APP_TITLE, "Iconx")
	ExitApp(1)
}
version := ResourceText(hMod, "APP_VERSION")
script := ResourceText(hMod, "APP_SCRIPT")
if (!version || !script) {
	MsgBox("dean.dll 이 올바른 형식이 아닙니다.", APP_TITLE, "Iconx")
	ExitApp(1)
}

uiDir := ExtractUi(hMod, version)
args := "--core " QuoteArg(uiDir) " " QuoteArg(uiDir "\WebView2Loader.dll") " " QuoteArg(A_ScriptDir)
tid := DllCall(CoreDll "\NewThread", "str", script, "str", args, "str", "", "uint")
if !tid {
	Log("NewThread 실패")
	MsgBox("프로그램을 시작하지 못했습니다.`n" LogFile " 를 확인해 주세요.", APP_TITLE, "Iconx")
	ExitApp(1)
}

A_IconTip := APP_TITLE " v" version
A_TrayMenu.Delete()
A_TrayMenu.Add("종료", (*) => ExitApp())
Persistent()
; 화면(코어 스레드)이 끝나면 런처도 함께 종료
SetTimer(WatchCore, 1000)
return

WatchCore() {
	global CoreDll, tid
	static grace := 3
	if (grace > 0) {
		grace--
		return
	}
	if !DllCall(CoreDll "\ahkReady", "uint", tid, "int")
		ExitApp()
}

; ---------------- 업데이트 ----------------
CheckUpdate() {
	global UPDATE_BASE, CoreDll
	tmp := CoreDll ".download"
	try FileDelete(tmp)
	try {
		current := LocalVersion()
		ToolTip(APP_TITLE " - 업데이트 확인 중...")
		remote := Trim(BufText(HttpGet(UPDATE_BASE "dean.version", 5000)), " `t`r`n")
		if !(remote ~= "^\d+(\.\d+)*$") {
			Log("원격 버전 형식 오류: " remote)
			return
		}
		if (CompareVersion(remote, current) <= 0)
			return

		ToolTip(APP_TITLE " - v" remote " 업데이트 받는 중...")
		expected := ""
		if RegExMatch(BufText(HttpGet(UPDATE_BASE "dean.dll.sha256", 8000)), "i)\b([0-9a-f]{64})\b", &m)
			expected := StrLower(m[1])
		if !expected {
			Log("해시 파일을 읽을 수 없어 업데이트를 건너뜁니다")
			return
		}

		data := HttpGet(UPDATE_BASE "dean.dll", 120000)
		; 정상적인 dean.dll 인지 최소한의 확인: 크기, 실행 파일 헤더(MZ)
		if (data.Size < 1000000 || NumGet(data, 0, "UShort") != 0x5A4D) {
			Log("받은 파일이 dean.dll 형식이 아닙니다 (" data.Size " bytes)")
			return
		}
		f := FileOpen(tmp, "w")
		f.RawWrite(data, data.Size)
		f.Close()

		actual := Sha256File(tmp)
		if (actual != expected) {
			Log("해시 불일치: 받은 것 " actual " / 릴리스에 적힌 것 " expected)
			FileDelete(tmp)
			return
		}

		; 교체: 기존 파일은 .bak 로 남겨두고, 실패하면 되돌림
		bak := CoreDll ".bak"
		if FileExist(CoreDll)
			FileMove(CoreDll, bak, true)
		try {
			FileMove(tmp, CoreDll, true)
		} catch as e {
			if FileExist(bak)
				FileMove(bak, CoreDll, true)
			throw e
		}
		Log("v" current " -> v" remote " 업데이트 완료")
	} catch as e {
		Log("업데이트 확인 실패: " e.Message)
		try FileDelete(tmp)
	}
	ToolTip()
}

LocalVersion() {
	global CoreDll
	if !FileExist(CoreDll)
		return "0"
	hMod := DllCall("LoadLibraryExW", "str", CoreDll, "ptr", 0, "uint", 0x2, "ptr")   ; 데이터 파일로만 열기
	if !hMod
		return "0"
	v := ResourceText(hMod, "APP_VERSION")
	DllCall("FreeLibrary", "ptr", hMod)
	return v ? v : "0"
}

CompareVersion(a, b) {
	pa := StrSplit(a, "."), pb := StrSplit(b, ".")
	Loop Max(pa.Length, pb.Length) {
		x := A_Index <= pa.Length ? Integer(pa[A_Index]) : 0
		y := A_Index <= pb.Length ? Integer(pb[A_Index]) : 0
		if (x != y)
			return x > y ? 1 : -1
	}
	return 0
}

; 버퍼로 응답 본문을 받습니다. HTTP 200이 아니면 예외.
HttpGet(url, timeoutMs) {
	req := ComObject("WinHttp.WinHttpRequest.5.1")
	req.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
	req.Open("GET", url, false)
	req.SetRequestHeader("User-Agent", "DEAN-ROBLOX-Launcher")
	req.Send()
	if (req.Status != 200)
		throw Error("HTTP " req.Status " " url)
	body := req.ResponseBody
	size := body.MaxIndex() + 1
	buf := Buffer(size)
	DllCall("RtlMoveMemory", "ptr", buf, "ptr", NumGet(ComObjValue(body), 8 + A_PtrSize, "ptr"), "uptr", size)
	return buf
}

Sha256File(path) {
	tmp := A_Temp "\dean_hash_" A_TickCount ".txt"
	RunWait(A_ComSpec ' /c certutil -hashfile "' path '" SHA256 > "' tmp '"', , "Hide")
	out := FileExist(tmp) ? FileRead(tmp) : ""
	try FileDelete(tmp)
	if RegExMatch(out, "im)^\s*([0-9a-f]{64})\s*$", &m)
		return StrLower(m[1])
	throw Error("해시 계산 실패")
}

; ---------------- dean.dll 리소스 ----------------
ReadResource(hMod, name) {
	res := DllCall("FindResourceW", "ptr", hMod, "str", name, "ptr", 10, "ptr")
	if !res
		return ""
	size := DllCall("SizeofResource", "ptr", hMod, "ptr", res, "uint")
	data := DllCall("LockResource", "ptr", DllCall("LoadResource", "ptr", hMod, "ptr", res, "ptr"), "ptr")
	buf := Buffer(size)
	DllCall("RtlMoveMemory", "ptr", buf, "ptr", data, "uptr", size)
	return buf
}

ResourceText(hMod, name) {
	buf := ReadResource(hMod, name)
	return buf ? Trim(BufText(buf), " `t`r`n") : ""
}

; 리소스·응답 본문은 끝에 널 문자가 없으므로 반드시 길이를 지정해서 읽습니다
BufText(buf) {
	return StrGet(buf, buf.Size, "UTF-8")
}

; 화면 파일과 WebView2Loader.dll 을 %LocalAppData%\DEAN_ROBLOX\ui\<버전> 에 풉니다.
; dean.dll 이 바뀌지 않았으면(크기·수정 시간 동일) 다시 풀지 않습니다.
ExtractUi(hMod, version) {
	global CoreDll
	root := EnvGet("LOCALAPPDATA") "\DEAN_ROBLOX\ui"
	base := root "\" version
	stamp := FileGetSize(CoreDll) "|" FileGetTime(CoreDll, "M")
	marker := base "\.ok"
	if (FileExist(marker) && FileRead(marker) = stamp)
		return base

	try DirDelete(base, true)
	DirCreate(base)
	for i, rel in StrSplit(ResourceText(hMod, "UI_MANIFEST"), "`n", "`r") {
		if (rel = "")
			continue
		WriteResource(hMod, "UI_" (i - 1), base "\" StrReplace(rel, "/", "\"))
	}
	WriteResource(hMod, "WEBVIEW2LOADER", base "\WebView2Loader.dll")
	FileOpen(marker, "w").Write(stamp)

	; 이전 버전 폴더 정리
	Loop Files, root "\*", "D" {
		if (A_LoopFileName != version)
			try DirDelete(A_LoopFileFullPath, true)
	}
	return base
}

WriteResource(hMod, name, path) {
	buf := ReadResource(hMod, name)
	if !buf
		throw Error("리소스 없음: " name)
	SplitPath(path, , &dir)
	DirCreate(dir)
	f := FileOpen(path, "w")
	f.RawWrite(buf, buf.Size)
	f.Close()
}

; 명령줄 인자 하나를 따옴표로 감쌉니다 (끝의 역슬래시는 2배로)
QuoteArg(s) {
	return '"' RegExReplace(s, "(\\+)$", "$1$1") '"'
}

Log(msg) {
	global LogFile
	try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", LogFile, "UTF-8")
}
