; Windows x64 세션 이벤트 해제. 별도 exe 없이 코어 번들에 포함됩니다.
; 기능 참고: https://github.com/ko9ma7/Session-Unlocker-for-Roblox
class RobloxMulti {
	static Busy := false
	static Message := "버튼을 누를 때마다 Roblox를 하나씩 추가합니다"
	static Path := ""
	static Before := Map()
	static Seen := Map()
	static Started := 0

	static Processes() {
		items := Map()
		for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='RobloxPlayerBeta.exe'")
			items[Integer(p.ProcessId)] := true
		return items
	}

	static FindPath() {
		global ConfigFile
		if this.Path && FileExist(this.Path)
			return this.Path
		this.Path := ""
		; 현재 실행 중인 버전을 우선 사용합니다. 다른 권한으로 실행된
		; 프로세스의 경로를 읽지 못하더라도 다음 후보를 계속 확인합니다.
		for pid in this.Processes() {
			handle := DllCall("OpenProcess", "uint", 0x1000, "int", false, "uint", pid, "ptr")
			if !handle
				continue
			try {
				buf := Buffer(65536), chars := 32768
				if DllCall("QueryFullProcessImageNameW", "ptr", handle, "uint", 0, "ptr", buf, "uint*", &chars) {
					candidate := StrGet(buf, chars, "UTF-16")
					if FileExist(candidate)
						return this.Path := candidate
				}
			} finally {
				DllCall("CloseHandle", "ptr", handle)
			}
		}
		saved := IniRead(ConfigFile, "Multi", "Path", "")
		if FileExist(saved)
			return this.Path := saved
		for key in ["HKCU\Software\Classes\roblox-player\shell\open\command", "HKCR\roblox-player\shell\open\command"] {
			try {
				command := RegRead(key)
				if RegExMatch(command, 'i)^"([^"\r\n]+\\RobloxPlayerBeta\.exe)"', &match) && FileExist(match[1])
					return this.Path := match[1]
			}
		}
		newest := 0
		Loop Files EnvGet("LOCALAPPDATA") "\Roblox\Versions\*", "D" {
			candidate := A_LoopFileFullPath "\RobloxPlayerBeta.exe"
			if FileExist(candidate) && (stamp := FileGetTime(candidate, "M")) > newest {
				newest := stamp
				this.Path := candidate
			}
		}
		return this.Path
	}

	static Publish() {
		global MyGui
		processes := this.Processes()
		count := processes.Count
		items := []
		for pid in processes
			items.Push('{"pid":' pid '}')
		path := ""
		try path := this.FindPath()
		catch as e
			this.Message := "실행 파일 자동 탐지 실패: " e.Message
		MyGui.PostWebMessageAsJson('{"type":"multiState","content":{"count":' count ',"items":[' JoinArr(items, ",") '],"busy":' (this.Busy ? "true" : "false") ',"path":"' JsonEscape(path) '","message":"' JsonEscape(StrReplace(StrReplace(this.Message, "`r", " "), "`n", " ")) '"}}')
	}

	static Launch() {
		if this.Busy
			return
		this.Busy := true
		try {
			this.Before := this.Processes()
			path := this.FindPath()
			if !path || !FileExist(path)
				throw Error("RobloxPlayerBeta.exe를 선택해 주세요")
			SplitPath(path, &name, &dir)
			if StrLower(name) != "robloxplayerbeta.exe"
				throw Error("RobloxPlayerBeta.exe만 실행할 수 있습니다")
			this.Message := "세션 확인 및 추가 실행 중…"
			this.Publish()
			; 두 번째 이후 프로세스에도 같은 이벤트가 생기므로 매번 모두 확인합니다.
			for pid in this.Before
				this.Unlock(pid)
			Run('"' path '" --app --rloc ko_kr --gloc ko_kr', dir, , &launchedPid)
			this.Started := A_TickCount
			this.Seen := Map()
			SetTimer(MultiWatch, 300)
		} catch as e {
			this.Busy := false
			this.Message := e.Message
			this.Publish()
		}
	}

	static Watch() {
		try {
			current := this.Processes()
			for pid in current {
				if this.Before.Has(pid)
					continue
				if !this.Seen.Has(pid)
					this.Seen[pid] := A_TickCount
				if A_TickCount - this.Seen[pid] >= 1500 {
					this.Finish("추가 실행 확인: 총 " current.Count "개 (PID " pid ")")
					return
				}
			}
			for pid in this.Seen.Clone()
				if !current.Has(pid)
					this.Seen.Delete(pid)
			if A_TickCount - this.Started > 15000
				this.Finish("새 Roblox 실행이 유지되지 않았습니다 경로와 권한을 확인한 뒤 재시도하세요")
		} catch as e
			this.Finish(e.Message)
	}

	static Finish(message) {
		SetTimer(MultiWatch, 0)
		this.Busy := false
		this.Message := message
		this.Publish()
	}

	static ObjectString(handle, kind) {
		size := 1024
		Loop 5 {
			buf := Buffer(size, 0), needed := 0
			status := DllCall("ntdll\NtQueryObject", "ptr", handle, "int", kind, "ptr", buf, "uint", size, "uint*", &needed, "int")
			if status >= 0 {
				length := NumGet(buf, 0, "ushort"), ptr := NumGet(buf, 8, "ptr")
				if !length
					return ""
				if ptr < buf.Ptr || ptr + length > buf.Ptr + size || Mod(length, 2)
					throw Error("이벤트 정보 형식이 올바르지 않습니다")
				return StrGet(ptr, length // 2, "UTF-16")
			}
			if !(status = -1073741820 || status = -1073741789 || status = -2147483643)
				throw Error("이벤트 정보를 읽지 못했습니다")
			size := Max(size * 2, needed + 256)
			if size > 1048576
				break
		}
		throw Error("이벤트 정보가 너무 큽니다")
	}

	static Unlock(pid) {
		process := DllCall("OpenProcess", "uint", 0x1040, "int", false, "uint", pid, "ptr")
		if !process
			throw Error("PID " pid " 접근 실패 앱을 관리자 권한으로 실행해 주세요")
		try {
			; 열린 프로세스 핸들로 실행 파일을 다시 검증하여 PID 재사용에 대비합니다.
			pathBuffer := Buffer(65536), chars := 32768
			if !DllCall("QueryFullProcessImageNameW", "ptr", process, "uint", 0, "ptr", pathBuffer, "uint*", &chars)
				throw Error("대상 프로세스 경로를 확인할 수 없습니다")
			SplitPath(StrGet(pathBuffer, chars, "UTF-16"), &name)
			if StrLower(name) != "robloxplayerbeta.exe"
				throw Error("Roblox 프로세스가 아닙니다")
			size := 1048576, status := -1
			Loop 8 {
				table := Buffer(size), needed := 0
				status := DllCall("ntdll\NtQuerySystemInformation", "int", 64, "ptr", table, "uint", size, "uint*", &needed, "int")
				if status >= 0
					break
				if !(status = -1073741820 || status = -1073741789 || status = -2147483643)
					break
				size := Max(size * 2, needed + 65536)
				if size > 134217728
					break
			}
			if status < 0
				throw Error("Windows 핸들 목록을 읽지 못했습니다")
			count := NumGet(table, 0, "uptr")
			if count > (table.Size - 16) // 40
				throw Error("Windows 핸들 목록 형식이 올바르지 않습니다")
			Loop count {
				offset := 16 + (A_Index - 1) * 40
				if NumGet(table, offset + 8, "uptr") != pid
					continue
				source := NumGet(table, offset + 16, "uptr"), copy := 0
				if !DllCall("DuplicateHandle", "ptr", process, "ptr", source, "ptr", -1, "ptr*", &copy, "uint", 0, "int", false, "uint", 2)
					continue
				try {
					; File/Pipe에는 이름 조회를 하지 않아 동기 호출 정지를 피합니다.
					if this.ObjectString(copy, 2) != "Event"
						continue
					if !RegExMatch(this.ObjectString(copy, 1), "i)^\\Sessions\\\d+\\BaseNamedObjects\\ROBLOX_singletonEvent$")
						continue
					closed := 0
					if !DllCall("DuplicateHandle", "ptr", process, "ptr", source, "ptr", -1, "ptr*", &closed, "uint", 0, "int", false, "uint", 3)
						throw Error("세션 잠금 해제 실패 (PID " pid ").")
					if closed
						DllCall("CloseHandle", "ptr", closed)
				} finally {
					DllCall("CloseHandle", "ptr", copy)
				}
			}
		} finally {
			DllCall("CloseHandle", "ptr", process)
		}
	}
}

WebviewGetMultiState(*) {
	try RobloxMulti.Publish()
	catch as e {
		RobloxMulti.Message := e.Message
		MyGui.PostWebMessageAsJson('{"type":"multiError","content":"' JsonEscape(StrReplace(StrReplace(e.Message, "`r", " "), "`n", " ")) '"}')
	}
}

WebviewLaunchMulti(*) {
	RobloxMulti.Launch()
}

WebviewPickMultiPath(*) {
	global ConfigFile
	if RobloxMulti.Busy
		return
	path := FileSelect(1, , "RobloxPlayerBeta.exe 선택", "Roblox (RobloxPlayerBeta.exe)")
	if !path
		return
	SplitPath(path, &name)
	if StrLower(name) != "robloxplayerbeta.exe" {
		RobloxMulti.Message := "RobloxPlayerBeta.exe를 선택해 주세요"
	} else {
		RobloxMulti.Path := path
		IniWrite(path, ConfigFile, "Multi", "Path")
		RobloxMulti.Message := "실행 파일을 선택했습니다"
	}
	RobloxMulti.Publish()
}

MultiWatch() {
	RobloxMulti.Watch()
}

WebviewFocusRoblox(webview, value, *) {
	if !IsInteger(value)
		return
	try {
		hwnd := WinExist("ahk_pid " Integer(value) " ahk_exe RobloxPlayerBeta.exe")
		if hwnd
			WinActivate("ahk_id " hwnd)
	}
}
