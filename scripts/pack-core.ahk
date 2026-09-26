#Requires AutoHotkey v2.0 64-bit
; dean.dll 만들기
;   vendor\AutoHotkey64.dll(실행 엔진)을 복사한 뒤, 아래 내용을 리소스로 넣습니다.
;     APP_SCRIPT      합쳐진 앱 스크립트 (build\app.bundle.ahk)
;     APP_VERSION     version.txt 의 버전 문자열
;     WEBVIEW2LOADER  webview\64bit\WebView2Loader.dll
;     UI_MANIFEST     화면 파일 목록 (줄마다 상대 경로)
;     UI_0, UI_1 ...  화면 파일(dist\ 아래 전부), 목록 순서와 같음
;   그리고 build\dean.dll.sha256, build\dean.version 을 함께 만듭니다.
; 실행: npm run build:core

SetWorkingDir(A_ScriptDir "\..")
root := A_WorkingDir
buildDir := root "\build"
outDll := buildDir "\dean.dll"
RT_RCDATA := 10

if !FileExist(buildDir "\app.bundle.ahk")
	Fail("build\app.bundle.ahk 가 없습니다. npm run build:core 로 실행하세요")
if !FileExist(root "\dist\index.html")
	Fail("dist\index.html 이 없습니다. 프론트엔드를 먼저 빌드하세요")

version := Trim(FileRead(root "\version.txt", "UTF-8"), " `t`r`n")
if !(version ~= "^\d+(\.\d+)*$")
	Fail("version.txt 형식이 올바르지 않습니다: " version)

FileCopy(root "\vendor\AutoHotkey64.dll", outDll, true)

hUpdate := DllCall("BeginUpdateResourceW", "str", outDll, "int", false, "ptr")
if !hUpdate
	Fail("BeginUpdateResource 실패 (오류 " A_LastError ")")

try {
	AddFile("APP_SCRIPT", buildDir "\app.bundle.ahk")
	AddText("APP_VERSION", version)
	AddFile("WEBVIEW2LOADER", root "\webview\64bit\WebView2Loader.dll")

	files := []
	distLen := StrLen(root "\dist") + 2
	Loop Files, root "\dist\*", "FR"
		files.Push(A_LoopFileFullPath)
	manifest := ""
	for i, path in files {
		rel := StrReplace(SubStr(path, distLen), "\", "/")
		manifest .= (i > 1 ? "`n" : "") rel
		AddFile("UI_" (i - 1), path)
	}
	AddText("UI_MANIFEST", manifest)
} catch as e {
	DllCall("EndUpdateResourceW", "ptr", hUpdate, "int", true)   ; 변경 취소
	Fail("리소스 추가 실패: " e.Message)
}

if !DllCall("EndUpdateResourceW", "ptr", hUpdate, "int", false)
	Fail("EndUpdateResource 실패 (오류 " A_LastError ")")

; 만들어진 dll에서 다시 읽어서 검증
hMod := DllCall("LoadLibraryExW", "str", outDll, "ptr", 0, "uint", 0x2, "ptr")   ; LOAD_LIBRARY_AS_DATAFILE
if !hMod
	Fail("만들어진 dean.dll 을 열 수 없습니다")
check := ReadResource(hMod, "APP_VERSION")
DllCall("FreeLibrary", "ptr", hMod)
if (!check || StrGet(check, check.Size, "UTF-8") != version)
	Fail("dean.dll 검증 실패: 버전 리소스가 다릅니다")

hash := Sha256File(outDll)
FileOpen(buildDir "\dean.dll.sha256", "w").Write(hash "  dean.dll`n")
FileOpen(buildDir "\dean.version", "w").Write(version)
FileAppend("dean.dll v" version " 생성 (" Round(FileGetSize(outDll) / 1024) " KB, 화면 파일 " files.Length "개)`nSHA256 " hash "`n", "*", "UTF-8")
ExitApp(0)

AddFile(name, path) {
	buf := FileRead(path, "RAW")
	Add(name, buf, buf.Size)
}

AddText(name, text) {
	size := StrPut(text, "UTF-8") - 1
	buf := Buffer(Max(size, 1))
	StrPut(text, buf, "UTF-8")
	Add(name, buf, size)
}

Add(name, buf, size) {
	global hUpdate, RT_RCDATA
	if !DllCall("UpdateResourceW", "ptr", hUpdate, "ptr", RT_RCDATA, "str", name, "ushort", 0, "ptr", buf, "uint", size, "int")
		throw Error(name " (오류 " A_LastError ")")
}

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

Sha256File(path) {
	out := ComObject("WScript.Shell").Exec('certutil -hashfile "' path '" SHA256').StdOut.ReadAll()
	if RegExMatch(out, "im)^\s*([0-9a-f]{64})\s*$", &m)
		return m[1]
	throw Error("해시 계산 실패")
}

Fail(msg) {
	FileAppend("ERROR: " msg "`n", "*", "UTF-8")
	ExitApp(1)
}
