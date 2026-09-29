; 런처, 개발 스크립트, 기존 단일 exe 모두 관리자 권한으로 실행합니다.
RequireAdministrator(coreMode := false) {
	if A_IsAdmin
		return
	for arg in A_Args {
		if arg = "--admin-relaunch" {
			MsgBox("관리자 권한으로 실행하지 못했습니다", "DEAN ROBLOX", "Iconx")
			ExitApp(1)
		}
	}
	try {
		if coreMode {
			; DLL 스레드에서는 스크립트 대신 호스트 런처를 재실행합니다.
			buf := Buffer(65536)
			if !DllCall("GetModuleFileNameW", "ptr", 0, "ptr", buf, "uint", 32768)
				throw Error("런처 경로를 확인할 수 없습니다")
			command := '"' StrGet(buf, "UTF-16") '" /restart'
		} else if A_IsCompiled {
			command := '"' A_ScriptFullPath '" /restart'
		} else {
			command := '"' A_AhkPath '" /restart "' A_ScriptFullPath '"'
		}
		Run("*RunAs " command " --admin-relaunch", A_WorkingDir)
	} catch {
		MsgBox("채팅·클릭도우미를 사용하려면 관리자 권한이 필요합니다`n다시 실행한 뒤 Windows 권한 요청을 승인해 주세요", "DEAN ROBLOX", "Icon!")
		ExitApp(1)
	}
	ExitApp(0)
}
