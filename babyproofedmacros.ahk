global macroVersion := "1.0.4.2"
;@Ahk2Exe-AddResource *24 input.manifest, 1
#Requires AutoHotkey v2.1-alpha.18
#SingleInstance Force
#Warn All, Off
#UseHook true
InstallKeybdHook(1, 1)
InstallMouseHook(1, 1)

#MaxThreadsPerHotkey 1
#MaxThreads 255
#MaxThreadsBuffer true
A_MaxHotkeysPerInterval := 99000000
A_HotkeyInterval := 99000000
SendMode("Event")
SetKeyDelay(-1, -1)
KeyHistory(0)
ListLines(0)
SetMouseDelay(-1)
SetDefaultMouseSpeed(0)
SetWinDelay(-1)
SetControlDelay(-1)
DllCall("Winmm\timeBeginPeriod", "UInt", 1)

; I need to create a pointer to store the old resolution value so the function can write to a valid memory address. This variable is never used.
oldRes := 0
DllCall("ntdll\ZwSetTimerResolution", "Int", 5000, "Int", 1, "Int*", &oldRes)

targetDir := A_MyDocuments "\HorribleBaseMacros"
if !DirExist(targetDir)
    DirCreate(targetDir)
SetWorkingDir(targetDir)

global settings := Map()
global tabs := {
    GENERAL: "General Macros",
    WEAPONSWITCH: "Weapon switching Macros",
    KEYBINDS: "In-game keybinds"
}
global guiTabs := []
for key, value in tabs.OwnProps() {
    guiTabs.Push(value)
}
global controlOverMouse := ""
global DPIScale := 1 ; A_ScreenDPI / 96
global yOffset := 35 * DPIScale
global textOffset := 20 * DPIScale
global elementOffset := (textOffset + 400) * DPIScale
global settingYOffset := 20 * DPIScale
global inCEO := false
global chatOpen := false
global activeTab := 1
global hTimer := DllCall("CreateWaitableTimer", "Ptr", 0, "Int", 0, "Ptr", 0, "Ptr")
global queryPerformanceFrequency := 0
global coutObj := unset
global macroExecutionStart := 0
global macroExecutionTime := 0
global lastMacroExecutionTime := 0
global sendInputTextElements := []
global lastTabSwitchData := { weaponKey: "", time: 0 }
global driftAccumulatorX := 0
global driftAccumulatorY := 0
global lastTurnTime := 0
global lastHorizontalMovementKeyReleaseTime := 0
DllCall("QueryPerformanceFrequency", "Int64P", &queryPerformanceFrequency)
Hotkey("~$*Enter", (*) => onChatClose())
Hotkey("~$*Esc", (*) => onChatClose())
if (!isRunningInExeContainer()) {
    Hotkey("*$F12", (*) => Reload())
}

doVersionCheck()

global settingsManagerInstance := SettingsManager()
global spamManagerInstance := SpamManager()

SetTimer((*) {
    str := "A state: " KeyState.getKeyState("a") " D state: " KeyState.getKeyState("d") " Time: " startCounting()
    str .= "`nA disabled: " KeyDisabler.isKeyDisabled("a") " D disabled: " KeyDisabler.isKeyDisabled("d")
    ToolTip(str, 0, 0)
}, 1)

class SettingsManager {
    __New() {
        this.clicksOnThisControl := 0
        this.controlLastClicked := 0
        for tab in guiTabs {
            settings[tab] := []
        }
        this.mouseHookActive := false
        makeSettings()

        this.makeGUI()

        SetTimer((*) {
            ; Initialize Hotkeys after loading settings
            for tabName in guiTabs {
                for setting in settings[tabName] {
                    if (setting is HotkeyElement) {
                        setting.register()
                    }
                }
            }
        }, -100)
    }

    makeGUI() {
        global settingsGui := Gui(, "Horrible Base Macros Settings")
        settingsGui.Opt("-DPIScale")
        settingsGui.OnEvent("Close", (*) => ExitApp())

        tab := settingsGui.Add("Tab3", , guiTabs)
        tab.OnEvent("Change", (guiCtrl, *) {
            ControlFocus("Hide this fucking bullshit GUI " guiCtrl.value)
            global activeTab := guiCtrl.value
        })

        for tabName in guiTabs {
            tab.UseTab(tabName)
            settingsGui.Add("Text", "x500 y0") ; Here to fix the layout...
            i := 0
            for setting in settings[tabName] {
                if (setting.invisible) {
                    continue
                }
                i++
                settingsGui.Add("Text", "x" textOffset " y" (i * settingYOffset) + yOffset, setting.name)

                eventName := ""
                if (setting.type = "bool") {
                    ctrl := settingsGui.Add("Checkbox", "W28 x" elementOffset " y" (i * settingYOffset) + yOffset + 6) ; Why is the hitbox for the checkbox not at all matching the visual checkbox?
                    eventName := "Click"
                } else if (setting.type = "hotkey") {
                    ctrl := settingsGui.Add("Hotkey", "W80 x" elementOffset " y" (i * settingYOffset) + yOffset)
                    eventName := "Change"
                } else if (setting.type == "string") {
                    ctrl := settingsGui.Add("Edit", "W80 x" elementOffset " y" (i * settingYOffset) + yOffset)
                    eventName := "Change"
                }

                try ctrl.Value := setting.value

                ctrl.OnEvent(eventName, ObjBindMethod(setting, "handleUpdate"))
            }
        }

        buttonOffset := 500
        for index, tabName in guiTabs { ; Add multiple buttons so we can make hotkeys less painful and set focus on the button so that the hotkeys don't change when you don't want them to.
            tab.useTab(tabName)
            settingsGui.Add("Button", "x20 y" buttonOffset " w200", "Update hotkeys and save").OnEvent("Click", (*) => this._updateHotkeys())
            settingsGui.Add("Button", "x20 y" buttonOffset + yOffset " w200", "Hide this fucking bullshit GUI " index).OnEvent("Click", (*) => settingsGui.Hide())
            sendInputTextElements.Push(settingsGui.Add("Text", "x24 w400 y" buttonOffset + yOffset * 2, "SendInput: N/A"))
        }
        settingsGui.Show()
        if (InStr(A_ScriptName, ".ahk")) {
            A_TrayMenu.Delete("&Help")
            A_TrayMenu.Delete("&Window Spy")
            A_TrayMenu.Delete("&Edit Script")
            A_TrayMenu.Delete("&Reload Script")
            A_TrayMenu.Delete("4&")
            A_TrayMenu.Delete("2&")
        }
        A_TrayMenu.Delete("&Pause Script")
        A_TrayMenu.Add("Reload Script", (*) => Reload())
        A_TrayMenu.Add("Show Settings", (*) => settingsGui.Show(), "P100000")
        A_TrayMenu.Default := "Show Settings"
        this._addMouseHook()
        Sleep(50)
        ControlFocus("Hide this fucking bullshit GUI 1", "Horrible Base Macros Settings")

        SetTimer((*) {
            if (WinActive("Horrible Base Macros Settings")) {
                this._addMouseHook()
            } else {
                this._removeMouseHook()
            }
        }, 100)

        SetTimer((*) {
            if (WinActive("ahk_class grcWindow")) {
                this._updateSendInputState()
            }
            static gtaOpen := false
            if (WinExist("ahk_class grcWindow") && !gtaOpen) {
                InstallKeybdHook(1, 1)
                gtaOpen := true
            }
        }, 1000)
    }

    _updateSendInputState() { ; Informational text to show if SendInput is working properly or not
        start := startCounting()
        SendInput("{Blind}{f24 2}")
        /*
        Low level keyboard hooks can be hooked in a specific order that causes every individual input in a SendInput stream to take an entire game frame to execute, making SendInput the same speed as SendEvent.
        This is impossible to fix without removing the offending keyboard hook (practically impossible since hooks are private for the application that created it only, unless you want to create something resembling an antivirus...
        or create a list of known offending applications and DLL inject into them, which is absurdly complicated and unstable).
        If SendInput is failing, you need to figure out what application is installing a low level keyboard hook other than AutoHotkey and GTA and close the application.
        You could likely fix this by forking Wine, but that's only for Linux only obviously.
        TLDR: Windows API is fucking stupid.
        */
        end := stopCounting(start)
        for textElement in sendInputTextElements {
            textElement.Value := "SendInput: " . (end < 5 ? "WORKING" : "FAILING (MACROS WILL BE SLOWER)") ; This check could technically be inaccurate if you have more than ~800 FPS... welp, guess I'll have to improve it when the Ryzen 7 12800X3D comes out.
        }
    }

    _addMouseHook() {
        if (this.mouseHookActive) {
            return
        }
        this.mouseHookActive := true

        ; Need to bind them to this for some reason otherwise this is undefined in the handler
        try Hotkey("~LButton", ObjBindMethod(this, "_mouseClickHandler"), "On")
        try Hotkey("~RButton", ObjBindMethod(this, "_mouseClickHandler"), "On")
        try Hotkey("~MButton", ObjBindMethod(this, "_mouseClickHandler"), "On")
        try Hotkey("~XButton1", ObjBindMethod(this, "_mouseClickHandler"), "On")
        try Hotkey("~XButton2", ObjBindMethod(this, "_mouseClickHandler"), "On")
    }

    _removeMouseHook() {
        if (!this.mouseHookActive) {
            return
        }
        this.mouseHookActive := false

        try Hotkey("~LButton", "Off")
        try Hotkey("~RButton", "Off")
        try Hotkey("~MButton", "Off")
        try Hotkey("~XButton1", "Off")
        try Hotkey("~XButton2", "Off")
        settingsManagerInstance._reregisterHotkeys()
    }

    _mouseClickHandler(*) {
        MouseGetPos(, , , &controlNN, 2)
        if (!controlNN) {
            this.clicksOnThisControl := 0
            return
        } else if (this.controlLastClicked != controlNN) {
            this.controlLastClicked := controlNN
            this.clicksOnThisControl := 0
            return
        }

        this.clicksOnThisControl++
        if (this.clicksOnThisControl < 1) {
            return
        }
        this.clicksOnThisControl := 0
        global controlOverMouse := GuiCtrlFromHwnd(controlNN)
        className := WinGetClass("ahk_id " controlNN)
        if (className == "msctls_hotkey32" && WinActive("Horrible Base Macros Settings")) {
            className := WinGetClass("ahk_id " controlOverMouse.hwnd)
            mouseButtonPressed := SubStr(A_ThisHotkey, 2) ; Remove the '~' prefix
            if (className == "msctls_hotkey32" && WinActive("Horrible Base Macros Settings")) {
                controlOverMouse.Value := mouseButtonPressed

                ; holy shit im such a fucking genius this is so stupid but it works so fucking flawlessly
                ControlGetPos(&x, &y, , , controlOverMouse, , "Horrible Base Macros Settings")
                hotkeyName := ControlGetText(GetControlFromCoordinates(textOffset, y), "Horrible Base Macros Settings")
                setting := retrieveSetting(hotkeyName, true)
                if (setting == "") {
                    throw UnsetError("Why isn't this defined? Kill yourself.")
                    return
                }
                setting.handleUpdate(controlOverMouse)
                ToolTip("The hotkey your mouse is hovering over has been set to `"" mouseButtonPressed "`".")
                SetTimer((*) => ToolTip(), -1000)
                return
            }
        }
    }

    _updateHotkeys() {
        for tabName in guiTabs {
            for setting in settings[tabName] {
                if (setting is HotkeyElement) {
                    setting.updateHotkey()
                }
                setting.saveValue()
            }
        }
    }

    _reregisterHotkeys() {
        for tabName in guiTabs {
            for setting in settings[tabName] {
                if (setting is HotkeyElement) {
                    setting.register()
                }
            }
        }
    }

    findHotkeyBoundToAKey(key) {
        for tabName in guiTabs {
            for setting in settings[tabName] {
                if (setting is HotkeyElement && setting.value == key && setting.macroExec != "") {
                    return setting
                }
            }
        }
        return false
    }

    isAHotkeyBoundToKey(key) {
        return !!this.findHotkeyBoundToAKey(key)
    }

}

class SettingElement {
    __New(name, type, defaultValue, tab, onChange := "", invisible := false) {
        this.name := name
        this.type := type
        this.defaultValue := defaultValue
        this.value := this.getValue()
        this.oldValue := this.value
        this.tab := tab
        this.onChange := onChange
        this.invisible := invisible
        settings[tab].Push(this)
        this.saveValue()
    }

    saveValue() {
        IniWrite(this.value, "config.ini", "config", this.name)
    }

    getValue() {
        return IniRead("config.ini", "config", this.name, this.defaultValue)
    }

    handleUpdate(guiCtrl, *) {
        this.oldValue := this.value
        this.value := guiCtrl.Value
        if (this.onChange != "") {
            this.onChange(this.value, this.oldValue, guiCtrl)
        }
        ; ToolTip("Setting Updated: " this.name " = " this.value)
        ; SetTimer(() => ToolTip(), -500)
    }
}

class HotkeyElement extends SettingElement {
    __New(name, defaultValue, tab, macroExec := "", invisible := false, hotkeyValueAddendumPre := "", hotkeyValueAddendumPost := "", runWhenDisabled := false) {
        super.__New(name, "hotkey", defaultValue, tab, , invisible)
        this.macroExec := macroExec
        this.hotkeyValueAddendumPre := hotkeyValueAddendumPre
        this.hotkeyValueAddendumPost := hotkeyValueAddendumPost == "" ? "" : " " hotkeyValueAddendumPost
        this.disabledByKeyDisabler := false
        this.runWhenDisabled := runWhenDisabled
    }

    register() {
        if (this.disabledByKeyDisabler) {
            this.unregister()
            return
        }
        if (this.value != "" && this.macroExec != "") {
            try {
                HotIfWinActive("ahk_class grcWindow")
                if (!settingsManagerInstance.isAHotkeyBoundToKey(this.oldValue)) {
                    try Hotkey(this.hotkeyValueAddendumPre "*$" this.oldValue this.hotkeyValueAddendumPost, , "Off")
                    try Hotkey(this.hotkeyValueAddendumPre "*$" this.oldValue this.hotkeyValueAddendumPost " up", , "Off")
                }
                this._bindHotkey()
            } catch as err {
                MsgBox("Could not register hotkey: " this.value "`nError: " err.Message)
            }
        }
    }

    unregister() {
        if (this.value != "") {
            HotIfWinActive("ahk_class grcWindow")
            try Hotkey(this.hotkeyValueAddendumPre "*$" this.value this.hotkeyValueAddendumPost, "Off")
            try Hotkey(this.hotkeyValueAddendumPre "*$" this.value this.hotkeyValueAddendumPost " up", "Off")
            HotIfWinActive()
        }
    }

    performHotkey(*) {
        if (InStr(this.hotkeyValueAddendumPost, "Up")) {
            KeyState.setKeyState(this.value, false)
        } else {
            KeyState.setKeyState(this.value, true)
        }
        if (chatOpen) {
            thisKeybind := retrieveSetting(this.name).value
            Send("{Blind}{" thisKeybind "}")
            return
        }
        try {
            global macroExecutionStart := startCounting()
            this.macroExec()
            global macroExecutionTime
            if (retrieveSetting("Enable macro speed profiling (only useful for developers)").value && macroExecutionTime != 0) {
                cout("Macro " this.name " took " Round(macroExecutionTime, 2) " ms to execute. Last macro was executed " Round(stopCounting(lastMacroExecutionTime), 2) " ms ago.")
                macroExecutionTime := 0
                global lastMacroExecutionTime := startCounting()
            }
        } catch as err {
            BlockInput("Off")
            BlockInput("MouseMoveOff")
            throw err
            ExitApp
        }
    }

    handleUpdate(guiCtrl, *) {
        super.handleUpdate(guiCtrl)
        ; ToolTip("Setting Updated: " this.name " = " this.value)
        ; SetTimer(() => ToolTip(), -500)
    }

    ; manage disabling old hotkeys and enabling new ones
    updateHotkey() {
        if (this.disabledByKeyDisabler) {
            this.unregister()
            return
        }
        if (this.oldValue == this.value) {
            return
        }
        if (this.oldValue != "" && this.macroExec != "" && !settingsManagerInstance.isAHotkeyBoundToKey(this.oldValue)) {
            HotIfWinActive("ahk_class grcWindow")
            try Hotkey(this.hotkeyValueAddendumPre "*$" this.oldValue this.hotkeyValueAddendumPost, "Off")
            try Hotkey(this.hotkeyValueAddendumPre "*$" this.oldValue this.hotkeyValueAddendumPost " up", "Off")
            HotIfWinActive()
        }

        if (this.value != "" && this.macroExec != "") {
            try {
                this._bindHotkey()
            } catch {
                throw UnsetError("Could not register hotkey: " this.value)
            }
        }
        this.oldValue := this.value
        this.saveValue()
    }

    _bindHotkey() {
        HotIfWinActive("ahk_class grcWindow")
        if (InStr(this.hotkeyValueAddendumPost, "Up")) {
            try Hotkey(this.hotkeyValueAddendumPre "*$" this.value, (*) {
                KeyState.setKeyState(this.value, true)
            }, "On")
        } else {
            try Hotkey(this.hotkeyValueAddendumPre "*$" this.value this.hotkeyValueAddendumPost " up", (*) {
                KeyState.setKeyState(this.value, false)
            }, "On")
        }
        try Hotkey(this.hotkeyValueAddendumPre "*$" this.value this.hotkeyValueAddendumPost, ObjBindMethod(this, "performHotkey"), "On")
        HotIfWinActive()
    }
}

doVersionCheck() {
    url := "https://raw.githubusercontent.com/cryleak/BabyproofedMacros/refs/heads/main/babyproofedmacros.ahk"

    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", url, true)
        whr.Send()

        if !whr.WaitForResponse(5) {
            throw Error("No response received from version check request.")
        }

        responseText := whr.ResponseText

        firstLine := StrSplit(responseText, "`n")[1]

        if RegExMatch(firstLine, '"([\d\.]+)"', &match) {
            version := match[1]
            if (VerCompare(version, macroVersion) > 0) {
                MsgBox("A new version of Babyproofed Macros is available! Please download it from the GitHub page. `nCurrent version: " . macroVersion . "`nLatest version: " . version)
            }
            /*
            else {
                MsgBox("Detected Version: " . version)
            }
            */
        } else {
            throw Error("Version couldn't be parsed.")
        }

    } catch Error as err {
        MsgBox("Version check failed. Please check for updates manually. `nError: " . err.Message)
    }
}

; Waits exactly 1 frame thanks to the keyboard hook in GTA
frameSleep(amount) {
    loop amount {
        Send("{Blind}{f24 up}")
    }
}

; Uses a combination of the scroll wheel and the arrow keys to scroll faster, you can scroll twice in 2 frames with this instead of 4.
scrollInDirection(direction, amount, extraInput := "") {
    doExtraInput := () { ; Send an extra input if provided by the caller
        if (extraInput != "") {
            SendInput(extraInput)
            extraInput := ""
        }
    }

    cursorHidden := isCursorHidden()

    if (amount == 1) {
        if (cursorHidden) {
            frameSleep(1)
            SendInput("{Blind}{Wheel" direction "}")
        } else {
            Send("{Blind}{" direction "}")
        }
        doExtraInput()
        return
    }

    loop Floor(amount / 2) {
        if (cursorHidden) {
            Send("{Blind}{" direction " down}")
            doExtraInput()
            SendInput("{Blind}{Wheel" direction "}")
            Send("{Blind}{" direction " up}")
        } else {
            Send("{Blind}{" direction "}")
            doExtraInput()
            Send("{Blind}{" direction "}")
        }
    }

    if (amount & 1) {
        if (cursorHidden) {
            frameSleep(1)
            SendInput("{Blind}{Wheel" direction "}")
        } else {
            Send("{Blind}{" direction "}")
        }
    }
}

accurateSleep(ms) {
    ; DllCall("Sleep", "UInt", ms)

    ; lets you sleep in 0.5ms intervals instead of 1ms
    dueTime := Buffer(8, 0)
    NumPut("Int64", -(ms * 10000), dueTime, 0)

    if (!DllCall("SetWaitableTimer", "Ptr", hTimer, "Ptr", dueTime, "Int", 0, "Ptr", 0, "Ptr", 0, "Int", 0)) {
        throw Error("Failed to set waitable timer for some reason")
        ExitApp()
    }

    DllCall("WaitForSingleObject", "Ptr", hTimer, "UInt", 0xFFFFFFFF)
}

GetControlFromCoordinates(x, y) {
    controls := WinGetControls("Horrible Base Macros Settings")
    for index, control in controls {
        ControlGetPos(&ctrlX, &ctrlY, &ctrlW, &ctrlH, control, "Horrible Base Macros Settings")
        text := ControlGetText(control, "Horrible Base Macros Settings")
        setting := retrieveSetting(text, true)
        if (setting == "") {
            continue
        }
        if (setting.tab != guiTabs[activeTab]) {
            continue
        }
        if (x == ctrlX && y == ctrlY) {
            return control
        }
    }
    MsgBox("why am i fucked? wtf")
    ; If this happens we are fucked anyways
}

retrieveSetting(settingName, ignoreErrors := false) {
    for tabName in guiTabs {
        for setting in settings[tabName] {
            if (setting.name == settingName) {
                if (setting is HotkeyElement && setting.value == "" && !ignoreErrors) {
                    throw UnsetError("Hotkey setting " setting.name " has no value set and we are trying to get the fucking value!")
                }
                return setting
            }
        }
    }
    return ""
}

lockCursorToPixelCoordinates(x, y) {
    coords := getPixelCoordinates(x, y)

    rect := Buffer(16, 0) ; rect is 4 ints (4 bytes each) = 16 bytes

    NumPut("Int", coords.x, rect, 0)   ; left
    NumPut("Int", coords.y, rect, 4)   ; top
    NumPut("Int", coords.x, rect, 8)   ; right
    NumPut("Int", coords.y, rect, 12)  ; bottom

    DllCall("ClipCursor", "Ptr", rect)
}

releaseCursor() {
    DllCall("ClipCursor", "Ptr", 0)
}

moveToPixelCoordinates(x, y) {
    coords := getPixelCoordinates(x, y)
    ; MouseMove, % coords.x, % coords.y
    DllCall("SetCursorPos", "Int", coords.x, "Int", coords.y)
}

; Get the coordinates on the main screen for a certain x and y from 0 to 1
getPixelCoordinates(x, y) {
    widescreenWidth := A_ScreenHeight * (16 / 9)
    offsetX := (A_ScreenWidth - widescreenWidth) / 2
    pixelX := offsetX + (widescreenWidth * x)
    pixelY := A_ScreenHeight * y
    return { x: Round(pixelX), y: Round(pixelY) }
}

getPixelCoordinatesReverse(pixelX, pixelY) {
    widescreenWidth := A_ScreenHeight * (16 / 9)
    offsetX := (A_ScreenWidth - widescreenWidth) / 2
    x := (pixelX - offsetX) / widescreenWidth
    y := pixelY / A_ScreenHeight
    return { x: x, y: y }
}

debugShowMouseCoords() {
    CoordMode("Mouse", "Screen")

    MouseGetPos(&mouseX, &mouseY)
    coords := getPixelCoordinatesReverse(mouseX, mouseY)
    ToolTip("X: " coords.x " Y: " coords.y)
}

startCounting() {
    CounterBefore := 0
    DllCall("QueryPerformanceCounter", "Int64P", &CounterBefore)
    return (CounterBefore / queryPerformanceFrequency) * 1000
}

stopCounting(startTime) {
    CounterAfter := 0
    DllCall("QueryPerformanceCounter", "Int64P", &CounterAfter)
    return (CounterAfter * 1000 / queryPerformanceFrequency - startTime)
}

onChatClose() {
    global chatOpen := false
}

isCursorHidden() {
    return A_Cursor == "Unknown"
}

isRunningInExeContainer() {
    fileName := A_ScriptName

    return InStr(fileName, ".exe")
}

; Compensates for fractional pixels and turns a certain amount of degrees
turnDegrees(degrees) {
    global driftAccumulatorX, driftAccumulatorY, lastTurnTime
    if (stopCounting(lastTurnTime) > 500) { ; The player likely already moved their mouse so we should just reset the drift compensation
        driftAccumulatorX := 0
        driftAccumulatorY := 0
    }
    lastTurnTime := startCounting()

    scalar := GetKeyState("RButton", "P") ? 320.7 / 180 : 262.5 / 180
    pixelsPerDegree := scalar / (3840 / A_ScreenWidth)

    exactPixelsX := -(degrees * pixelsPerDegree)
    totalPixelsX := exactPixelsX + driftAccumulatorX
    moveX := Round(totalPixelsX)
    driftAccumulatorX := totalPixelsX - moveX

    driftRate := 0.032 / (3840 / A_ScreenWidth)

    driftAccumulatorY += driftRate
    moveY := 0

    if (driftAccumulatorY >= 1.0) {
        moveY := -1
        driftAccumulatorY -= 1
    }

    MouseMove(moveX, moveY, 0)
}

convertToCharArray(text) {
    charArray := []
    loop parse text {
        charArray.Push(Ord(A_LoopField))
    }
    return charArray
}

SendStringByMessage(charArray) {
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if (!hwnd) {
        return
    }

    for char in charArray {
        DllCall("PostMessage", "Ptr", hwnd, "UInt", 0x0102, "Ptr", char, "Ptr", 1)
    }
}

shouldPreserveLeftClick() {
    return retrieveSetting("Preserve left click state").value && GetKeyState("LButton", "P")
}

cacheLastMacroExecutionTime() {
    global macroExecutionTime := stopCounting(macroExecutionStart)
}

cout(text) {
    if (!IsSet(coutObj)) {
        if (FileExist(A_ScriptDir "\BabyProofedMacros.log")) {
            FileDelete(A_ScriptDir "\BabyProofedMacros.log")
        }
        global coutObj := FileOpen(A_ScriptDir "\BabyProofedMacros.log", "a", "UTF-8")
    }
    coutObj.WriteLine(text)
    coutObj.Read(0)
}

unpressHorizontalMovementKeys() {
    KeyDisabler.disableKey("a")
    KeyDisabler.disableKey("d")
    SendInput("{Blind}{a up}{d up}")
}

repressHorizontalMovementKeys() {
    KeyDisabler.enableKey("a")
    KeyDisabler.enableKey("d")
    if (KeyState.getKeyState("a")) {
        SendInput("{Blind}{a down}")
    }
    if (KeyState.getKeyState("d")) {
        SendInput("{Blind}{d down}")
    }
}

shouldHandleHorizontalMovementKeys() {
    return retrieveSetting("Automatic horizontal key handling (experimental)").value && KeyState.getKeyState(retrieveSetting("Sprint keybind").value) ; && (stopCounting(lastHorizontalMovementKeyReleaseTime) < 200 || KeyState.getKeyState("a") || KeyState.getKeyState("d"))
}

makeSettings() {

    HotkeyElement("Sniper rifle keybind", "9", tabs.KEYBINDS)
    HotkeyElement("Heavy weapon keybind", "4", tabs.KEYBINDS)
    HotkeyElement("Sticky bomb keybind", "5", tabs.KEYBINDS)
    HotkeyElement("Pistol keybind", "6", tabs.KEYBINDS)
    HotkeyElement("Shotgun keybind", "3", tabs.KEYBINDS)
    HotkeyElement("Rifle keybind", "8", tabs.KEYBINDS)
    HotkeyElement("SMG keybind", "7", tabs.KEYBINDS)
    HotkeyElement("Fists keybind", "1", tabs.KEYBINDS)
    HotkeyElement("Melee weapon keybind", "2", tabs.KEYBINDS)
    HotkeyElement("Interaction menu keybind", "m", tabs.KEYBINDS)
    HotkeyElement("EWO Animation keybind", "capslock", tabs.KEYBINDS)
    HotkeyElement("Melee punch keybind", "r", tabs.KEYBINDS)
    HotkeyElement("Look behind keybind", "c", tabs.KEYBINDS)
    HotkeyElement("Chat keybind (automatically suspend macros when chat open)", "", tabs.KEYBINDS, (*) {
        thisKeybind := retrieveSetting("Chat keybind (automatically suspend macros when chat open)").value
        Send("{Blind}{" thisKeybind "}")
        global chatOpen := true
    })
    HotkeyElement("Sprint keybind", "lshift", tabs.KEYBINDS)

    HotkeyElement("a keybind", "a", tabs.GENERAL, (*) {
        lastHorizontalMovementKeyReleaseTime := startCounting()
    }, true, "~", "up")
    HotkeyElement("d keybind", "d", tabs.GENERAL, (*) {
        lastHorizontalMovementKeyReleaseTime := startCounting()
    }, true, "~", "up")

    SettingElement("Use cursor in interaction menu for slightly faster macros", "bool", false, tabs.GENERAL)
    SettingElement("Preserve left click state", "bool", false, tabs.GENERAL)
    HotkeyElement("Ammo", "", tabs.GENERAL, (*) {
        shouldUseCursor := retrieveSetting("Use cursor in interaction menu for slightly faster macros").value
        interactionKey := retrieveSetting("Interaction menu keybind").value

        if (shouldUseCursor) {
            lockCursorToPixelCoordinates(0.1175, 0.32075)
        }
        SendInput("{Blind}{lbutton up}{enter down}")
        Send("{Blind}{" interactionKey "}")
        scrollInDirection("Down", inCEO ? 3 : 2)
        SendInput("{Blind}{enter up}")
        if (shouldUseCursor) {
            frameSleep(1)
            SendInput("{Blind}{lbutton down}{enter down}")
            frameSleep(1)
            SendInput("{Blind}{lbutton up}")
            Send("{Blind}{enter up}")
            frameSleep(1)
            SendInput("{Blind}{WheelUp}{enter down}")
            Send("{Blind}{enter up}")
            releaseCursor()
        } else {
            frameSleep(1)
            scrollInDirection("Down", 5, "{Blind}{enter down}")
            SendInput("{Blind}{enter up}")
            frameSleep(1)
            SendInput("{Blind}{enter down}{WheelUp}")
            Send("{Blind}{enter up}")
        }
        cacheLastMacroExecutionTime()
        Send("{Blind}{" interactionKey "}")
        if (shouldPreserveLeftClick()) {
            SendInput("{Blind}{lbutton down}")
        }
        accurateSleep(100)
    })
    HotkeyElement("EWO", "", tabs.GENERAL, (*) {
        c4Mode := retrieveSetting("C4 Mode").value
        if (c4Mode) {
            thisKeybind := retrieveSetting("EWO").value
            while (GetKeyState(thisKeybind, "P")) {
                Send("{Blind}{g}")
            }
            return
        }
        interactionKey := retrieveSetting("Interaction menu keybind").value
        animationKey := retrieveSetting("EWO Animation keybind").value
        meleePunchKey := retrieveSetting("Melee punch keybind").value
        lookBehindKey := retrieveSetting("Look behind keybind").value
        sprintKey := retrieveSetting("Sprint keybind").value
        useExperimentalEwo := retrieveSetting("Use experimental EWO macro (slower and can't be customized)").value
        if (useExperimentalEwo) {
            SetMouseDelay(1)
            BlockInput("On")
            Send("{Blind}{lbutton down}")
            SendInput("{Blind}{s up}{" lookBehindKey " down}{enter down}{a up}{" interactionKey " down}{" sprintKey " up}{lshift up}{w up}{rbutton up}{" meleePunchKey " down}{lbutton up}{d up}{tab up}")
            Send("{Blind}{" interactionKey " up}{up}{up}{" animationKey "}")
            frameSleep(1)
            SendInput("{enter up}")
            cacheLastMacroExecutionTime()
            Send("{" lookBehindKey " Up}{" meleePunchKey " Up}")
            BlockInput("Off")
            SetMouseDelay(-1)
        } else {
            ewoDelay := retrieveSetting("EWO delay (ms) (for cleaner looking ragdoll)").value
            shouldShoot := retrieveSetting("Shoot before EWOing").value

            shouldSleep := 0
            if (shouldShoot) {
                SendInput("{Blind}{lbutton down}")
                shouldSleep := 1
            }
            if (GetKeyState(lookBehindKey, "P")) {
                KeyDisabler.disableKey(lookBehindKey)
                SendInput("{Blind}{" lookBehindKey " up}")
                shouldSleep := 1
            }
            frameSleep(shouldSleep)
            startTime := startCounting()
            SendInput("{Blind}{lbutton up}{rbutton up}{w up}{a up}{s up}{d up}{enter down}{lshift up}{" meleePunchKey " down}{" interactionKey " down}{" lookBehindKey " down}{" sprintKey " up}{" animationKey " down}")

            Send("{Blind}{" interactionKey " up}{up down}")
            SendInput("{Blind}{" animationKey " up}")
            Send("{Blind}{up up}")
            if (isCursorHidden()) {
                SendInput("{Blind}{WheelUp}")
            } else {
                Send("{Blind}{up down}")
            }
            if (ewoDelay != "" && ewoDelay > 0) {
                timeDelta := stopCounting(startTime)
                remainingTime := ewoDelay - timeDelta
                if (remainingTime >= 0.5) {
                    accurateSleep(Round(remainingTime * 2) / 2)
                }
            }

            ; We press animation key twice in case the first one was blocked by the game because the game sometimes disables the key.
            SendInput("{Blind}{" animationKey " down}{enter up}")
            cacheLastMacroExecutionTime()
            frameSleep(2)
            SendInput("{Blind}{" animationKey " up}{up up}{" lookBehindKey " up}{" meleePunchKey " up}")
            KeyDisabler.enableKey(lookBehindKey)
        }
        SetCapsLockState("Off")
    })
    SettingElement("EWO delay (ms) (for cleaner looking ragdoll)", "string", "0", tabs.GENERAL)
    SettingElement("Shoot before EWOing", "bool", false, tabs.GENERAL)
    SettingElement("Use experimental EWO macro (slower and can't be customized)", "bool", false, tabs.GENERAL)
    SettingElement("C4 Mode", "bool", false, tabs.GENERAL)
    HotkeyElement("Instant EWO", "", tabs.GENERAL, (*) {
        c4Mode := retrieveSetting("C4 Mode").value
        if (c4Mode) {
            thisKeybind := retrieveSetting("Instant EWO").value
            while (GetKeyState(thisKeybind, "P")) {
                Send("{Blind}{g}")
            }
            return
        }
        interactionKey := retrieveSetting("Interaction menu keybind").value
        animationKey := retrieveSetting("EWO Animation keybind").value
        meleePunchKey := retrieveSetting("Melee punch keybind").value
        lookBehindKey := retrieveSetting("Look behind keybind").value
        sprintKey := retrieveSetting("Sprint keybind").value

        SendInput("{Blind}{lbutton up}{rbutton up}{w up}{a up}{s up}{d up}{enter down}{lshift up}{" meleePunchKey " down}{" interactionKey " down}{" lookBehindKey " down}{" sprintKey " up}{" animationKey " down}")
        Send("{Blind}{" interactionKey " up}")
        SendInput("{Blind}{" animationKey " up}")
        Send("{Blind}{up down}")
        if (isCursorHidden()) {
            SendInput("{Blind}{WheelUp}")
        } else {
            Send("{Blind}{up up}{up down}")
        }
        SendInput("{Blind}{" animationKey " down}{enter up}")
        cacheLastMacroExecutionTime()
        Send("{Blind}{enter}") ; If we had to look back then we needed to wait another frame
        frameSleep(2)
        SendInput("{Blind}{" animationKey " up}{up up}{" lookBehindKey " up}{" meleePunchKey " up}")
    })

    HotkeyElement("Toggle CEO", "", tabs.GENERAL, (*) {
        interactionKey := retrieveSetting("Interaction menu keybind").value

        SendInput("{Blind}{lbutton up}{enter down}")
        if (inCEO) {
            Send("{Blind}{" interactionKey "}{enter up}{up down}")
            SendInput("{Blind}{enter down}")
            Send("{Blind}{up up}{enter up}")
        } else {
            Send("{Blind}{" interactionKey "}")
            scrollInDirection("Down", 6)
            SendInput("{Blind}{enter up}")
            Send("{Blind}{enter}")
        }
        if (shouldPreserveLeftClick()) {
            SendInput("{Blind}{lbutton down}")
        }
        global inCEO := !inCEO
    })

    HotkeyElement("Chat Spam", "", tabs.GENERAL, (*) {
        chatSpamText := retrieveSetting("Chat Spam Text").value
        thisKeybind := retrieveSetting("Chat Spam").value
        chatKeybind := retrieveSetting("Chat keybind (automatically suspend macros when chat open)").value
        charArray := convertToCharArray(chatSpamText)
        while (GetKeyState(thisKeybind, "P")) {
            Send("{Blind}{" chatKeybind " down}{enter down}")
            SendInput("{Blind}{" chatKeybind " up}")
            frameSleep(1)
            SendStringByMessage(charArray)
            Send("{Blind}{enter up}")
        }
    })
    SettingElement("Chat Spam Text", "string", "Ω", tabs.GENERAL)
    HotkeyElement("Fast respawn", "", tabs.GENERAL, (*) {
        thisKeybind := retrieveSetting("Fast respawn").value
        while (GetKeyState(thisKeybind, "P")) {
            SendInput("{Blind}{lbutton down}")
            frameSleep(1)
            SendInput("{Blind}{lbutton up}")
            frameSleep(1)
        }
        cacheLastMacroExecutionTime()
    })
    HotkeyElement("Quick turn keybind", "", tabs.GENERAL, (*) {
        degrees := retrieveSetting("Degrees to turn").value
        turnDegrees(degrees)
    })
    SettingElement("Degrees to turn", "string", "180", tabs.GENERAL)
    HotkeyElement("BST", "", tabs.GENERAL, (*) {
        if (!inCEO) {
            if (FileExist(A_ScriptDir . "\communication 1.ahk") && FileExist(A_ScriptDir . "\communication 2.ahk")) {
                Run(A_ScriptDir . "\communication 1.ahk")
                Run(A_ScriptDir . "\communication 2.ahk")
                return
            }
            coordinates := getPixelCoordinates(0.5, 0.5)
            ToolTip("You're not in a CEO silly", coordinates.x, coordinates.y)
            SetTimer(() => ToolTip(), -1000)
            return
        }
        interactionMenuKey := retrieveSetting("Interaction menu keybind").value

        SendInput("{Blind}{lbutton up}{enter down}")

        Send("{Blind}{" interactionMenuKey "}{enter up}")
        scrollInDirection("Down", 4, "{Blind}{enter down}")
        SendInput("{Blind}{enter up}")
        frameSleep(1)
        SendInput("{Blind}{WheelDown}{enter down}")
        Send("{Blind}{enter up}")
        if (shouldPreserveLeftClick()) {
            SendInput("{Blind}{lbutton down}")
        }
        cacheLastMacroExecutionTime()
    })
    SettingElement("Enable macro speed profiling (only useful for developers)", "bool", false, tabs.GENERAL)

    quickSwitchMethod := (keybind, *) {
        weaponKey := retrieveSetting(keybind).value
        useAutomatedSpam := retrieveSetting("Use fully automated spam (extremely buggy)").value
        if (useAutomatedSpam && spamManagerInstance.isSpamming()) {
            spamManagerInstance.queueSpam(weaponKey, false)
            return
        }
        c4Keybind := retrieveSetting("Sticky bomb keybind").value
        heavyWeaponKey := retrieveSetting("Heavy weapon keybind").value
        leftClickHandlingSetting := retrieveSetting("Automatic left click handling (buggy)").value
        shiftKeybind := retrieveSetting("Sprint keybind").value
        automaticLButtonHandling := leftClickHandlingSetting && (lastTabSwitchData.weaponKey != c4Keybind || stopCounting(lastTabSwitchData.time) > 390) && weaponKey != c4Keybind && KeyState.getKeyState(shiftKeybind)
        if (automaticLButtonHandling) {
            unpressHorizontalMovementKeys()
        }
        if (automaticLButtonHandling) {
            SendInput("{Blind}{lbutton up}")
        }
        Send("{Blind}{" weaponKey " down}{tab}")
        SendInput("{Blind}{" weaponKey " up}{" c4Keybind " up}")
        if (weaponKey == heavyWeaponKey) {
            SendInput("{Blind}{WheelDown}") ; automatic zoom out?
        }
        if (automaticLButtonHandling) {
            SetTimer(() {
                if (GetKeyState("LButton", "P")) {
                    SendInput("{Blind}{lbutton down}")
                }
            }, -100)
        }
        SetTimer(() {
            if (shouldHandleHorizontalMovementKeys() && automaticLButtonHandling) {
                repressHorizontalMovementKeys()
            }
        }, -190)
        global lastTabSwitchData := { time: startCounting(), weaponKey: weaponKey }
        cacheLastMacroExecutionTime()
    }
    HotkeyElement("Sniper rifle tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Sniper rifle keybind"))
    HotkeyElement("Heavy weapon tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Heavy weapon keybind"))
    HotkeyElement("Sticky bomb tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Sticky bomb keybind"))
    HotkeyElement("Pistol tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Pistol keybind"))
    HotkeyElement("Shotgun tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Shotgun keybind"))
    HotkeyElement("Rifle tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Rifle keybind"))
    HotkeyElement("SMG tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("SMG keybind"))
    HotkeyElement("Fists tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Fists keybind"))
    HotkeyElement("Melee weapon tab switch", "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod("Melee weapon keybind"))
    HotkeyElement("RPG Spam", "", tabs.WEAPONSWITCH, (*) {
        heavyWeaponKey := retrieveSetting("Heavy weapon keybind").value
        stickyBombKey := retrieveSetting("Sticky bomb keybind").value
        Send("{Blind}{" stickyBombKey " down}")
        frameSleep(2)
        Send("{Blind}{" heavyWeaponKey " down}{tab}")
        SendInput("{Blind}{" heavyWeaponKey " up}{" stickyBombKey " up}")
        cacheLastMacroExecutionTime()
    })
    HotkeyElement("Sniper Spam", "", tabs.WEAPONSWITCH, (*) {
        sniperRifleKey := retrieveSetting("Sniper rifle keybind").value
        stickyBombKey := retrieveSetting("Sticky bomb keybind").value
        Send("{Blind}{" stickyBombKey " down}{" sniperRifleKey " down}{tab}")
        SendInput("{Blind}{" sniperRifleKey " up}{" stickyBombKey " up}")
        cacheLastMacroExecutionTime()
    })
    SettingElement("Use fully automated spam (extremely buggy)", "bool", false, tabs.WEAPONSWITCH, (newValue, oldValue, *) {
        if (oldValue == newValue) {
            return
        }
        if (newValue) {
            SetTimer(ObjBindMethod(spamManagerInstance, "runLoop"), 1, -2147483648)
        } else {
            SetTimer(ObjBindMethod(spamManagerInstance, "runLoop"), 0)
        }
    })
    SettingElement("Automatic left click handling (buggy)", "bool", false, tabs.WEAPONSWITCH)
    SettingElement("Automatic horizontal key handling (experimental)", "bool", false, tabs.WEAPONSWITCH)
    SettingElement("Queue double switching", "bool", false, tabs.WEAPONSWITCH)
    HotkeyElement("Automated RPG Spam", "", tabs.WEAPONSWITCH)
    HotkeyElement("Double switch", "", tabs.WEAPONSWITCH, (*) {
        heavyWeaponKey := retrieveSetting("Heavy weapon keybind").value
        useAutomatedSpam := retrieveSetting("Use fully automated spam (extremely buggy)").value
        if (useAutomatedSpam && spamManagerInstance.isSpamming()) {
            spamManagerInstance.queueSpam(heavyWeaponKey, false, 2)
            return
        }
        c4Keybind := retrieveSetting("Sticky bomb keybind").value
        leftClickHandlingSetting := retrieveSetting("Automatic left click handling (buggy)").value
        sprintKeybind := retrieveSetting("Sprint keybind").value
        automaticLButtonHandling := leftClickHandlingSetting && (lastTabSwitchData.weaponKey != c4Keybind || stopCounting(lastTabSwitchData.time) > 390) && heavyWeaponKey != c4Keybind && KeyState.getKeyState(sprintKeybind)
        if (automaticLButtonHandling) {
            unpressHorizontalMovementKeys()
        }
        Send("{Blind}{" heavyWeaponKey "}")
        Send("{Blind}{" heavyWeaponKey " down}")
        if (automaticLButtonHandling) {
            SendInput("{Blind}{lbutton up}")
        }
        Send("{Blind}{tab}")
        SendInput("{Blind}{" heavyWeaponKey " up}{" c4Keybind " up}")

        if (automaticLButtonHandling) {
            SetTimer(() {
                if (GetKeyState("LButton", "P")) {
                    SendInput("{Blind}{lbutton down}")
                }
            }, -100)
        }
        SetTimer(() {
            if (shouldHandleHorizontalMovementKeys() && automaticLButtonHandling) {
                repressHorizontalMovementKeys()
            }
        }, -185)
        cacheLastMacroExecutionTime()
    })
    explicitSwitchMethod := (weaponKey, pressAmount, *) {
        LButtonState := GetKeyState("LButton", "P")
        SendInput("{Blind}{lbutton up}")
        KeyDisabler.disableKey("LButton")
        fistsKey := retrieveSetting("Fists keybind").value
        Send("{Blind}{" fistsKey " down}")
        if (pressAmount > 1) {
            loop pressAmount - 1 {
                Send("{Blind}{" weaponKey "}")
            }
        }
        Send("{Blind}{" weaponKey " down}{tab}")
        SendInput("{Blind}{" fistsKey " up}{" weaponKey " up}")
        if (LButtonState) {
            SendInput("{Blind}{lbutton down}")
        }
        cacheLastMacroExecutionTime()
    }
    HotkeyElement("Explicit RPG Switch", "", tabs.WEAPONSWITCH, (*) => explicitSwitchMethod(retrieveSetting("Heavy weapon keybind").value, 1))
    HotkeyElement("Explicit Homing Launcher Switch", "", tabs.WEAPONSWITCH, (*) => explicitSwitchMethod(retrieveSetting("Heavy weapon keybind").value, 2))
    HotkeyElement("Explicit Grenade Launcher Switch", "", tabs.WEAPONSWITCH, (*) => explicitSwitchMethod(retrieveSetting("Heavy weapon keybind").value, 3))
    HotkeyElement("Safe heavy weapon swap", "", tabs.WEAPONSWITCH, (*) {
        heavyWeaponKey := retrieveSetting("Heavy weapon keybind").value
        meleeWeaponKey := retrieveSetting("Melee weapon keybind").value
        Send("{Blind}{" meleeWeaponKey " down}{" heavyWeaponKey " down}{tab}")
        SendInput("{Blind}{" meleeWeaponKey " up}{" heavyWeaponKey " up}")
        cacheLastMacroExecutionTime()
    })
}

class SpamManager {
    __New() {
        this.timeUntilSwapAvailable := startCounting()
        this.spamDelay := 550
        this.quickSwitchDelay := 430
        this.customSwaps := []
        this.queuedThisShot := 0
        if (retrieveSetting("Use fully automated spam (extremely buggy)").value) {
            SetTimer(ObjBindMethod(this, "runLoop"), 1, -2147483648)
        }
    }

    queueSpam(weaponKey, swapToSticky, amount := 1) {
        if (this.customSwaps.Length && this.customSwaps[1].keyPresses <= 1 && this.customSwaps[1].weaponKey == weaponKey && this.customSwaps[1].swapToSticky == swapToSticky && retrieveSetting("Queue double switching").value) {
            this.customSwaps[1].keyPresses += 1
            return
        }
        this.lastQueue := startCounting()
        this.customSwaps.Push({ weaponKey: weaponKey, swapToSticky: swapToSticky, keyPresses: amount })
    }

    runLoop() {
        if (stopCounting(this.timeUntilSwapAvailable) < 0 || !WinActive("ahk_class grcWindow")) {
            return
        }
        stickyBombKey := retrieveSetting("Sticky bomb keybind").value
        heavyWeaponKey := retrieveSetting("Heavy weapon keybind").value
        automatedSpamKey := retrieveSetting("Automated RPG Spam", true).value
        if (!automatedSpamKey) {
            return
        }
        shouldHandleLButton := retrieveSetting("Automatic left click handling (buggy)").value
        if (GetKeyState(automatedSpamKey, "P")) {
            action := this.customSwaps.Length ? this.customSwaps.RemoveAt(1) : { weaponKey: heavyWeaponKey, swapToSticky: true, keyPresses: 1 }
            lbuttonState := GetKeyState("LButton", "P") && shouldHandleLButton
            if (action.swapToSticky) {
                Send("{Blind}{" stickyBombKey " down}")
            } else if (lbuttonState) {
                SendInput("{Blind}{lbutton up}")
            }

            if (action.keyPresses > 1) {
                loop action.keyPresses - 1 {
                    Send("{Blind}{" action.weaponKey "}")
                }
            }
            Send("{Blind}{" action.weaponKey " down}{tab}")
            SendInput("{Blind}{" action.weaponKey " up}{" stickyBombKey " up}")
            this.timeUntilSwapAvailable := startCounting() + (action.swapToSticky ? this.spamDelay : this.quickSwitchDelay)
            if (lbuttonState) {
                SendInput("{Blind}{lbutton down}")
                if (action.keyPresses > 1) {
                    accurateSleep(50)
                }
            }
            Sleep(-1)
            return
        } else {
            this.customSwaps := []
        }
    }

    isSpamming() {
        keybind := retrieveSetting("Automated RPG Spam", true).value
        if (!keybind) {
            return false
        }
        return GetKeyState(keybind, "P")
    }
}

class KeyDisabler {
    static disabledKeys := []

    static enableAllKeys() {
        for key in this.disabledKeys {
            HotIfWinActive("ahk_class grcWindow")
            Hotkey("*$" key, "Off")
            HotIfWinActive()
        }
        this.disabledKeys := []
    }

    static disableKey(key) {
        for disabledKey in this.disabledKeys {
            if (disabledKey == key) {
                return
            }
        }
        hotkeySetting := settingsManagerInstance.findHotkeyBoundToAKey(key)
        if (!!hotkeySetting) {
            hotkeySetting.disabledByKeyDisabler := true
            hotkeySetting.unregister()
        }

        HotIfWinActive("ahk_class grcWindow")
        Hotkey("*$" key, (*) {
            KeyState.setKeyState(key, true)
            if (!!hotkeySetting && hotkeySetting.runWhenDisabled) {
                hotkeySetting.performHotkey()
            }
        }, "On")
        Hotkey("*$" key " up", (*) {
            KeyState.setKeyState(key, false)
        }, "On")
        HotIfWinActive()
        this.disabledKeys.Push({ key: key, hotkeySetting: hotkeySetting })
    }

    static enableKey(key) {
        for index, keyObj in this.disabledKeys {
            disabledKey := keyObj.key
            if (disabledKey == key) {
                HotIfWinActive("ahk_class grcWindow")
                Hotkey("*$" key, "Off")
                Hotkey("*$" key " up", "Off")
                HotIfWinActive()
                this.disabledKeys.RemoveAt(index)
                if (!!keyObj.hotkeySetting) {
                    keyObj.hotkeySetting.disabledByKeyDisabler := false
                    keyObj.hotkeySetting.register()
                }
                if (GetKeyState(key, "P")) {
                    SendInput("{Blind}{" key " down}")
                }
                return
            }
        }
    }

    static isKeyDisabled(key) {
        for keyObj in this.disabledKeys {
            if (keyObj.key == key) {
                return true
            }
        }
        return false
    }
}

; Self implemented GetKeyState to fix key sticking hopefully. Not reliable for some things, so only used for horizontal movement key handling for now.
class KeyState {
    static keyStates := Map()

    static setKeyState(key, state) {
        this.keyStates[key] := state
    }

    static getKeyState(key) {
        if (!this.keyStates.Has(key)) {
            ; vkCode := GetKeyVK(key)
            ; return (DllCall("GetAsyncKeyState", "Int", vkCode) & 0x8000) != 0
            return GetKeyState(key, "P")
        }
        return this.keyStates[key]
    }
}
