#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include ./vendor/FindText.ahk
#Include ./robbery-patterns.ahk
#Include ./warning-matcher.ahk

; This helper has no UI and never captures the desktop or sends input.
if A_Args.Length != 2
	ExitApp(2)
workerRoot := A_Args[2]
parentHandle := DllCall("OpenProcess", "uint", 0x100000, "int", false, "uint", Integer(A_Args[1]), "ptr")
if !parentHandle
	ExitApp(3)
lastRequest := A_TickCount
try {
	while DllCall("WaitForSingleObject", "ptr", parentHandle, "uint", 0) = 258 {
		if A_TickCount - lastRequest > 30000
			break
		Loop Files workerRoot "\*.match.request", "F" {
			lastRequest := A_TickCount
			path := SubStr(A_LoopFileFullPath, 1, -StrLen(".match.request"))
			if !RegExMatch(A_LoopFileName, "^\d+\.match\.request$")
				continue
			try {
				FileDelete(A_LoopFileFullPath)
				size := StrSplit(FileRead(path ".ready"), ",")
				width := Integer(size[1]), height := Integer(size[2])
				if width < 24 || height < 24 || width > 8192 || height > 8192
					throw Error("Invalid capture size")
				engine := FindText()
				; Allocate for the file, not for the entire virtual desktop.
				engine.UpdateBits(engine.bits, 0, 0, width, height)
				if !engine.ShowPic(path ".jpg", 0)
					throw Error("Cannot read capture")
				left := (width - Min(width, 600)) // 2
				found := WarningMatcher.Find(left, 0, left + Min(width, 600) - 1, Min(height, 200) - 1, 0)
				result := found ? "1" : "0"
			} catch {
				result := "error"
			}
			try {
				resultFile := FileOpen(path ".match.tmp", "w")
				resultFile.Write(result)
				resultFile.Close()
				FileMove(path ".match.tmp", path ".match.result", true)
			}
			break
		}
		Sleep(20)
	}
} finally {
	DllCall("CloseHandle", "ptr", parentHandle)
}
ExitApp(0)
