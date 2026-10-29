; Hold Space to Talk for Windows (Claude and ChatGPT apps). Needs AutoHotkey v2 (free, autohotkey.com).
; Hold Space: voice typing turns on and your sound goes quiet.
; Tap Space:  voice typing turns off, your words stay in the box.
; Enter:      voice typing turns off and the message sends once your words land.
; A quick tap of Space is still a normal space. Space works normally in every other app.
#Requires AutoHotkey v2.0
#SingleInstance Force

HOLD_MS := 350          ; how long Space must be held to start talking
SEND_WAIT_MS := 900     ; time for the last words to land before Enter sends
global talking := false

IsChatApp() => WinActive("ahk_exe claude.exe") || WinActive("ahk_exe Claude.exe") || WinActive("ahk_exe ChatGPT.exe")

#HotIf IsChatApp()
$Space:: {
    global talking
    if talking {                       ; tap while talking: stop, keep the words
        KeyWait "Space"
        StopTalking()
        return
    }
    if KeyWait("Space", "T" HOLD_MS / 1000) {   ; let go quickly: a normal space
        Send "{Space}"
        return
    }
    StartTalking()                     ; held: start talking (it keeps listening after you let go)
    KeyWait "Space"
}

$Enter:: {
    global talking
    if talking {
        StopTalking()
        Sleep SEND_WAIT_MS
    }
    Send "{Enter}"
}
#HotIf

StartTalking() {
    global talking
    talking := true
    try SoundSetMute true              ; quiet the music and videos while you talk
    Send "#h"                          ; Windows voice typing on
}

StopTalking() {
    global talking
    talking := false
    Send "#h"                          ; Windows voice typing off
    try SoundSetMute false
}
