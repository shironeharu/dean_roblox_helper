; Only a derived PC ID is displayed. Raw drive/Windows identifiers never leave this PC.
class DeviceAccess {
	static Url := "https://api.github.com/repos/shironeharu/dean_roblox_helper/contents/access/allowlist.txt?ref=main"
	static PcId := ""
	static Allowed := false
	static Name := ""
	static Expires := "-"
	static ServerUtc := ""
	static ServerTick := 0
	static LastSuccess := 0
	static NextCheck := 0
	static Request := 0
	static RequestStarted := 0
	static StartupRequest := false
	static Gate := 0
	static GateCancelled := false
	static GateMessage := ""
	static GateBusy := false
	static OnChanged := 0
	static OnRevoked := 0

	static Tick() => DllCall("GetTickCount64", "uint64")

	static DeviceId() {
		machine := StrUpper(Trim(RegRead("HKLM\SOFTWARE\Microsoft\Cryptography", "MachineGuid")))
		serial := DriveGetSerial(EnvGet("SystemDrive") "\")
		if !machine || !serial
			throw Error("PC 식별 정보를 읽을 수 없습니다")
		digest := this.HashText("DEAN-PC-V1|" machine "|" Format("{:08X}", serial))
		return "DEAN-" SubStr(digest, 1, 8) "-" SubStr(digest, 9, 8) "-" SubStr(digest, 17, 8) "-" SubStr(digest, 25, 8)
	}

	static HashText(text) {
		provider := 0, hash := 0
		try {
			if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &provider, "wstr", "SHA256", "ptr", 0, "uint", 0, "int")
				throw Error("PC ID 해시 준비 실패")
			length := Buffer(4, 0), used := 0
			if DllCall("bcrypt\BCryptGetProperty", "ptr", provider, "wstr", "ObjectLength", "ptr", length, "uint", 4, "uint*", &used, "uint", 0, "int")
				throw Error("PC ID 해시 정보 읽기 실패")
			hashObject := Buffer(NumGet(length, 0, "uint"), 0)
			if DllCall("bcrypt\BCryptCreateHash", "ptr", provider, "ptr*", &hash, "ptr", hashObject, "uint", hashObject.Size, "ptr", 0, "uint", 0, "uint", 0, "int")
				throw Error("PC ID 해시 생성 실패")
			data := Buffer(StrPut(text, "UTF-8"), 0)
			StrPut(text, data, "UTF-8")
			digest := Buffer(32, 0)
			if DllCall("bcrypt\BCryptHashData", "ptr", hash, "ptr", data, "uint", data.Size - 1, "uint", 0, "int")
				|| DllCall("bcrypt\BCryptFinishHash", "ptr", hash, "ptr", digest, "uint", digest.Size, "uint", 0, "int")
				throw Error("PC ID 해시 계산 실패")
			hex := ""
			Loop digest.Size
				hex .= Format("{:02X}", NumGet(digest, A_Index - 1, "uchar"))
			return hex
		} finally {
			if hash
				DllCall("bcrypt\BCryptDestroyHash", "ptr", hash)
			if provider
				DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", provider, "uint", 0)
		}
	}

	static Require() {
		this.GateCancelled := false
		this.Allowed := false
		this.Gate := 0
		try this.PcId := this.DeviceId()
		catch {
			MsgBox("PC ID를 읽을 수 없습니다. 관리자 권한과 시스템 드라이브를 확인해 주세요.", "DEAN ROBLOX", "Iconx")
			return false
		}
		; Check before creating a window so approved PCs never flash the login form.
		this.StartRequest(true)
		while this.GateBusy
			Sleep(50)
		if this.Allowed
			return true
		this.GateMessage := ""
		return this.ShowGate()
	}

	static ShowGate() {
		global CoreMode
		settings := {}
		if CoreMode
			settings := {DllPath: A_Args[3], DataDir: EnvGet("LOCALAPPDATA") "\DEAN_ROBLOX\webview"}
		else if A_IsCompiled {
			WebViewCtrl.CreateFileFromResource("64bit\WebView2Loader.dll", WebViewCtrl.TempDir)
			settings := {DllPath: WebViewCtrl.TempDir "\64bit\WebView2Loader.dll"}
		}
		this.Gate := WebViewGui("-Resize -Caption", "DEAN ROBLOX · PC 인증", , settings)
		gateWindow := this.Gate
		ApplyAppWindowIcon(gateWindow)
		gateWindow.AreDefaultContextMenusEnabled := false
		gateWindow.IsParentWindowDraggingEnabled := true
		gateWindow.AddCallbackToScript("GetLoginState", (*) => this.PostGate())
		gateWindow.AddCallbackToScript("Login", (*) => this.StartRequest(true))
		gateWindow.AddCallbackToScript("CopyPcId", ObjBindMethod(this, "CopyId"))
		gateWindow.AddCallbackToScript("ExitLogin", ObjBindMethod(this, "CancelGate"))
		gateWindow.OnEvent("Close", ObjBindMethod(this, "CancelGate"))
		if CoreMode
			gateWindow.BrowseFolder(A_Args[2])
		gateWindow.Navigate(CoreMode || A_IsCompiled ? "login.html" : "http://localhost:5173/login.html")
		gateWindow.Show("w380 h536")
		WinWaitClose("ahk_id " gateWindow.Hwnd)
		this.Gate := 0
		return this.Allowed
	}

	static CopyId(*) {
		A_Clipboard := this.PcId
	}

	static UpdateGate(message, busy := false) {
		this.GateMessage := message
		this.GateBusy := busy
		this.PostGate()
	}

	static PostGate() {
		if IsObject(this.Gate) && HasMethod(this.Gate, "PostWebMessageAsJson")
			this.Gate.PostWebMessageAsJson('{"type":"loginState","content":{"pcId":"' this.PcId '","message":"' this.GateMessage '","busy":' (this.GateBusy ? "true" : "false") '}}')
	}

	static CancelGate(*) {
		this.GateCancelled := true
		if IsObject(this.Request)
			try this.Request.Abort()
		this.Request := 0
		SetTimer(DeviceAccessPoll, 0)
		if IsObject(this.Gate)
			this.Gate.Destroy()
		this.Gate := 0
	}

	static StartRequest(startup := false) {
		if IsObject(this.Request)
			return
		this.StartupRequest := startup
		if startup {
			this.UpdateGate("", true)
		}
		try {
			req := ComObject("WinHttp.WinHttpRequest.5.1")
			req.SetTimeouts(3000, 3000, 3000, 3000)
			req.Open("GET", this.Url "&v=" A_NowUTC "-" this.Tick() "-" Random(100000, 999999), true)
			req.SetRequestHeader("Cache-Control", "no-cache")
			req.SetRequestHeader("Accept", "application/vnd.github.raw+json")
			req.SetRequestHeader("User-Agent", "DEAN-ROBLOX-Access")
			this.Request := req
			this.RequestStarted := this.Tick()
			req.Send()
			SetTimer(DeviceAccessPoll, 100)
		} catch {
			this.Request := 0
			this.NetworkFailure()
		}
	}

	static Poll() {
		if !IsObject(this.Request)
			return
		try {
			if !this.Request.WaitForResponse(0) {
				if this.Tick() - this.RequestStarted < 8000
					return
				throw Error("Request timeout")
			}
			req := this.Request
			this.Request := 0
			SetTimer(DeviceAccessPoll, 0)
			if req.Status != 200
				throw Error("Access list unavailable")
			serverUtc := this.ParseServerDate(req.GetResponseHeader("Date"))
			verdict := this.ParsePolicy(req.ResponseText, this.PcId, serverUtc)
			if this.StartupRequest && this.GateCancelled
				return
			if !verdict.Allowed {
				if this.StartupRequest {
					this.UpdateGate("등록되지 않은 PC 입니다")
				} else
					this.Revoke(verdict.Message)
				return
			}
			this.Allowed := true
			this.Name := verdict.Name
			this.Expires := verdict.Expires
			this.ServerUtc := serverUtc
			this.ServerTick := this.Tick()
			this.LastSuccess := this.Tick()
			this.NextCheck := this.Tick() + 600000
			if this.StartupRequest {
				this.GateBusy := false
				if IsObject(this.Gate)
					this.Gate.Destroy()
			} else if IsObject(this.OnChanged) {
				callback := this.OnChanged
				callback.Call()
			}
		} catch {
			if IsObject(this.Request)
				try this.Request.Abort()
			this.Request := 0
			SetTimer(DeviceAccessPoll, 0)
			this.NetworkFailure()
		}
	}

	static NetworkFailure() {
		if this.StartupRequest {
			this.UpdateGate("등록되지 않은 PC 입니다")
		}
	}

	static BeginSession() => SetTimer(DeviceAccessTick, 1000)

	static SessionTick() {
		if !this.Allowed
			return
		trustedNow := DateAdd(this.ServerUtc, Floor((this.Tick() - this.ServerTick) / 1000), "Seconds")
		if this.Expires != "-" && trustedNow > this.Expires {
			this.Revoke("사용 기간이 만료되었습니다. ddu._.에게 DM 주세요.")
			return
		}
		if this.Tick() - this.LastSuccess > 1800000 {
			this.Revoke("30분 동안 등록 상태를 확인하지 못했습니다. 인터넷 연결 후 다시 로그인해 주세요.")
			return
		}
		if this.Tick() >= this.NextCheck {
			this.NextCheck := this.Tick() + 600000
			this.StartRequest()
		}
	}

	static Revoke(message) {
		this.Shutdown()
		if IsObject(this.OnRevoked) {
			callback := this.OnRevoked
			callback.Call(message)
		}
	}

	static Shutdown() {
		this.Allowed := false
		SetTimer(DeviceAccessTick, 0)
		SetTimer(DeviceAccessPoll, 0)
		if IsObject(this.Request)
			try this.Request.Abort()
		this.Request := 0
	}

	static ParseServerDate(value) {
		if !RegExMatch(value, "i)^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$", &m)
			throw Error("Invalid server date")
		months := Map("jan", "01", "feb", "02", "mar", "03", "apr", "04", "may", "05", "jun", "06", "jul", "07", "aug", "08", "sep", "09", "oct", "10", "nov", "11", "dec", "12")
		stamp := m[3] months[StrLower(m[2])] m[1] m[4] m[5] m[6]
		DateAdd(stamp, 0, "Seconds")
		return stamp
	}

	static ParsePolicy(text, pcId, nowUtc) {
		if StrLen(text) > 262144
			throw Error("Access list too large")
		lines := StrSplit(StrReplace(text, "`r"), "`n")
		if !lines.Length || lines[1] != "DEAN_ACCESS_V1"
			throw Error("Invalid access list")
		seen := Map(), selected := 0
		for index, line in lines {
			if index = 1 || line = ""
				continue
			fields := StrSplit(line, "|")
			if fields.Length != 4 || !RegExMatch(fields[1], "^DEAN-([A-F0-9]{8}-){3}[A-F0-9]{8}$") || !RegExMatch(fields[2], "^[01]$") || seen.Has(fields[1])
				throw Error("Invalid access record")
			seen[fields[1]] := true
			if fields[3] != "-" {
				if !RegExMatch(fields[3], "^\d{14}$")
					throw Error("Invalid expiry")
				DateAdd(fields[3], 0, "Seconds")
			}
			name := this.DecodeName(fields[4])
			if !name || StrLen(name) > 48 || RegExMatch(name, "[\x00-\x1f\x7f|<>]")
				throw Error("Invalid display name")
			if fields[1] = pcId
				selected := {Name: name, Blocked: fields[2] = "1", Expires: fields[3]}
		}
		if !IsObject(selected)
			return {Allowed: false, Message: "등록되지 않은 PC입니다. PC ID를 ddu._.에게 DM 주세요."}
		if selected.Blocked
			return {Allowed: false, Message: "차단된 PC입니다. ddu._.에게 DM 주세요."}
		if selected.Expires != "-" && nowUtc > selected.Expires
			return {Allowed: false, Message: "사용 기간이 만료되었습니다. ddu._.에게 DM 주세요."}
		return {Allowed: true, Name: selected.Name, Expires: selected.Expires}
	}

	static DecodeName(value) {
		if !RegExMatch(value, "^[A-Za-z0-9+/]+={0,2}$")
			throw Error("Invalid name encoding")
		size := 0
		if !DllCall("crypt32\CryptStringToBinaryW", "wstr", value, "uint", 0, "uint", 1, "ptr", 0, "uint*", &size, "ptr", 0, "ptr", 0) || size > 128
			throw Error("Invalid name encoding")
		data := Buffer(size + 1, 0)
		if !DllCall("crypt32\CryptStringToBinaryW", "wstr", value, "uint", 0, "uint", 1, "ptr", data, "uint*", &size, "ptr", 0, "ptr", 0)
			throw Error("Invalid name encoding")
		return StrGet(data, size, "UTF-8")
	}
}

DeviceAccessPoll(*) => DeviceAccess.Poll()
DeviceAccessTick(*) => DeviceAccess.SessionTick()

; Both registration and main windows share the launcher icon.
ApplyAppWindowIcon(window) {
	global CoreMode
	DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "wstr", "DEAN.ROBLOX.Helper", "int")
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
			DllCall("SendMessageW", "ptr", window.Hwnd, "uint", 0x80, "ptr", 1, "ptr", hIconBig)     ; WM_SETICON, ICON_BIG
		if (hIconSmall)
			DllCall("SendMessageW", "ptr", window.Hwnd, "uint", 0x80, "ptr", 0, "ptr", hIconSmall)   ; WM_SETICON, ICON_SMALL
		TraySetIcon("HICON:" (hIconBig ? hIconBig : hIconSmall))
	}
	A_IconTip := "DEAN ROBLOX"
}
