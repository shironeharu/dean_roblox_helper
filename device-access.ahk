; Only a derived PC ID is displayed. Raw drive/Windows identifiers never leave this PC.
class DeviceAccess {
	static Url := "https://raw.githubusercontent.com/shironeharu/dean_roblox_helper/main/access/allowlist.txt"
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
		try this.PcId := this.DeviceId()
		catch {
			MsgBox("PC ID를 읽을 수 없습니다. 관리자 권한과 시스템 드라이브를 확인해 주세요.", "DEAN ROBLOX", "Iconx")
			return false
		}
		this.Gate := Gui("-MaximizeBox -MinimizeBox", "DEAN ROBLOX · PC 인증")
		gateWindow := this.Gate
		gateWindow.BackColor := "1D1C23"
		gateWindow.SetFont("s16 Bold cCBB9EF", "Segoe UI")
		gateWindow.AddText("x24 y20 w332 h32 Center", "DEAN ROBLOX")
		gateWindow.SetFont("s10 Norm cEFEcf5")
		gateWindow.AddText("x24 y62 w332 h22 Center", "등록된 PC만 사용할 수 있습니다")
		gateWindow.AddText("x24 y98 w332 h20", "내 PC ID")
		gateWindow.SetFont("s9", "Consolas")
		gateWindow.AddEdit("x24 y121 w332 h28 ReadOnly cEFEcf5 Background29282F", this.PcId)
		gateWindow.SetFont("s10", "Segoe UI")
		gateWindow.AddButton("x24 y159 w100 h30", "ID 복사").OnEvent("Click", ObjBindMethod(this, "CopyId"))
		gateWindow.AddText("x24 y204 w332 h40", "Discord: ddu._.`n등록 요청은 PC ID와 함께 DM 주세요.")
		this.StatusLabel := gateWindow.AddText("x24 y252 w332 h44 cCBB9EF", "PC ID를 등록받은 뒤 로그인해 주세요.")
		this.LoginButton := gateWindow.AddButton("x24 y305 w210 h34 Default", "로그인")
		this.LoginButton.OnEvent("Click", (*) => this.StartRequest(true))
		gateWindow.AddButton("x246 y305 w110 h34", "종료").OnEvent("Click", ObjBindMethod(this, "CancelGate"))
		gateWindow.OnEvent("Close", ObjBindMethod(this, "CancelGate"))
		gateWindow.OnEvent("Escape", ObjBindMethod(this, "CancelGate"))
		gateWindow.Show("w380 h360")
		WinWaitClose("ahk_id " gateWindow.Hwnd)
		this.Gate := 0
		return this.Allowed
	}

	static CopyId(*) {
		A_Clipboard := this.PcId
		this.StatusLabel.Text := "PC ID가 복사되었습니다. ddu._.에게 DM 주세요."
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
			this.LoginButton.Enabled := false
			this.StatusLabel.Text := "등록 상태를 확인하고 있습니다…"
		}
		try {
			req := ComObject("WinHttp.WinHttpRequest.5.1")
			req.SetTimeouts(3000, 3000, 3000, 3000)
			req.Open("GET", this.Url "?t=" this.Tick(), true)
			req.SetRequestHeader("Cache-Control", "no-cache")
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
					this.LoginButton.Enabled := true
					this.StatusLabel.Text := verdict.Message
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
		if this.StartupRequest && IsObject(this.Gate) {
			this.LoginButton.Enabled := true
			this.StatusLabel.Text := "등록 확인에 실패했습니다. 인터넷 연결 후 다시 로그인해 주세요."
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
