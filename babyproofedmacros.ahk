;@Ahk2Exe-AddResource *24 input.manifest, 1
#Requires AutoHotkey v2.1-alpha.18
#SingleInstance Force
#Warn All, Off
#UseHook true
InstallKeybdHook()
InstallMouseHook()

#MaxThreadsPerHotkey 1
#MaxThreads 255
#MaxThreadsBuffer true
A_MaxHotkeysPerInterval := 99000000
A_HotkeyInterval := 99000000
SendMode("Event")
SetKeyDelay(-1, -1)
SetKeyDelay(-1, -1, "Play")
KeyHistory(0)
ListLines(0)
SetMouseDelay(-1)
SetMouseDelay(-1, "Play")
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
global enumTabs := Map(
    "GENERAL", "General Macros",
    "WEAPONSWITCH", "Weapon switching Macros",
    "KEYBINDS", "In-game keybinds"
)
global tabs := []
for key, value in enumTabs {
    tabs.Push(value)
}
global controlOverMouse := ""
global DPIScale := 1 ; A_ScreenDPI / 96
global yOffset := 35 * DPIScale
global textOffset := 20 * DPIScale
global elementOffset := (textOffset + 300) * DPIScale
global settingYOffset := 20 * DPIScale
global inCEO := false
global chatOpen := false
global activeTab := 1
global hTimer := DllCall("CreateWaitableTimer", "Ptr", 0, "Int", 0, "Ptr", 0, "Ptr")
global queryPerformanceFrequency := 0
global isOnLinux := IsWine()
DllCall("QueryPerformanceFrequency", "Int64P", &queryPerformanceFrequency)
Hotkey("~$*Enter", (*) => onChatClose())
Hotkey("~$*Esc", (*) => onChatClose())

global settingsManagerInstance := SettingsManager()

class SettingsManager {
    __New() {
        this.clicksOnThisControl := 0
        this.controlLastClicked := 0
        for tab in tabs {
            settings[tab] := []
        }
        this.mouseHookActive := false
        makeSettings()

        this.makeGUI()

        ; Initialize Hotkeys after loading settings
        for tabName in tabs {
            for setting in settings[tabName] {
                if (setting is HotkeyElement) {
                    setting.register()
                }
            }
        }
    }

    makeGUI() {
        global settingsGui := Gui(, "Horrible Base Macros Settings")
        settingsGui.Opt("-DPIScale")
        settingsGui.OnEvent("Close", (*) => ExitApp())

        tab := settingsGui.Add("Tab3", , tabs)
        tab.OnEvent("Change", (guiCtrl, *) {
            ControlFocus("Hide this fucking bullshit GUI " guiCtrl.value)
            global activeTab := guiCtrl.value
        })

        for tabName in tabs {
            tab.UseTab(tabName)
            settingsGui.Add("Text", "x500 y0") ; Here to fix the layout...
            for i, setting in settings[tabName] {
                settingsGui.Add("Text", "x" textOffset " y" (i * settingYOffset) + yOffset, setting.name)

                eventName := ""
                if (setting.type = "bool") {
                    ctrl := settingsGui.Add("Checkbox", "x" elementOffset " y" (i * settingYOffset) + yOffset + 3)
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

        buttonOffset := 375
        for index, tabName in tabs { ; Add multiple buttons so we can make hotkeys less painful and set focus on the button so that the hotkeys don't change when you don't want them to.
            tab.useTab(tabName)
            settingsGui.Add("Button", "x20 y" buttonOffset " w200", "Update hotkeys and save").OnEvent("Click", (*) => this._updateHotkeys())
            settingsGui.Add("Button", "x20 y" buttonOffset + yOffset " w200", "Hide this fucking bullshit GUI " index).OnEvent("Click", (*) => settingsGui.Hide())
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
    }

    _addMouseHook() {
        if (this.mouseHookActive) {
            return
        }
        this.mouseHookActive := true

        ; Need to bind them to this for some reason otherwise this is undefined in the handler
        Hotkey("~LButton", ObjBindMethod(this, "_mouseClickHandler"), "On")
        Hotkey("~RButton", ObjBindMethod(this, "_mouseClickHandler"), "On")
        Hotkey("~MButton", ObjBindMethod(this, "_mouseClickHandler"), "On")
        Hotkey("~XButton1", ObjBindMethod(this, "_mouseClickHandler"), "On")
        Hotkey("~XButton2", ObjBindMethod(this, "_mouseClickHandler"), "On")
    }

    _removeMouseHook() {
        if (!this.mouseHookActive) {
            return
        }
        this.mouseHookActive := false

        Hotkey("~LButton", "Off")
        Hotkey("~RButton", "Off")
        Hotkey("~MButton", "Off")
        Hotkey("~XButton1", "Off")
        Hotkey("~XButton2", "Off")
    }

    _mouseClickHandler(*) {
        MouseGetPos(, , , &controlNN, 2)
        if (!controlNN) { ; Why can't i reference "this" here????
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
        for tabName in tabs {
            for setting in settings[tabName] {
                if (setting is HotkeyElement) {
                    setting.updateHotkey()
                }
                setting.saveValue()
            }
        }
    }
}

class SettingElement {
    __New(name, type, defaultValue, tab) {
        this.name := name
        this.type := type
        this.defaultValue := defaultValue
        this.value := this.getValue()
        this.oldValue := this.value
        this.tab := tab
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
        ; ToolTip("Setting Updated: " this.name " = " this.value)
        ; SetTimer(() => ToolTip(), -500)
    }
}

class HotkeyElement extends SettingElement {
    __New(name, defaultValue, tab, macroExec?) {
        super.__New(name, "hotkey", defaultValue, tab)
        if (IsSet(macroExec)) {
            this.macroExec := macroExec
        } else {
            this.macroExec := ""
        }
    }

    register() {
        if (this.value != "" && this.macroExec != "") {
            try {
                HotIfWinActive "ahk_class grcWindow"
                Hotkey("*$" this.value, ObjBindMethod(this, "performHotkey"), "On")
                HotIfWinActive
            } catch as err {
                MsgBox("Could not register hotkey: " this.value "`nError: " err.Message)
            }
        }
    }

    performHotkey(*) {
        if (chatOpen) {
            thisKeybind := retrieveSetting(this.name).value
            Send("{Blind}{" thisKeybind "}")
            return
        }
        try {
            this.macroExec()
        } catch as err {
            BlockInput("Off")
            BlockInput("MouseMoveOff")
            throw err
            ExitApp
        }
    }

    handleUpdate(guiCtrl, *) {
        this.value := guiCtrl.Value
        ; ToolTip("Setting Updated: " this.name " = " this.value)
        ; SetTimer(() => ToolTip(), -500)
    }

    ; manage disabling old hotkeys and enabling new ones
    updateHotkey() {
        if (this.oldValue == this.value) {
            return
        }
        if (this.oldValue != "" && this.macroExec != "") {
            HotIfWinActive "ahk_class grcWindow"
            Hotkey("*$" this.oldValue, "Off")
            HotIfWinActive
        }

        if (this.value != "" && this.macroExec != "") {
            try {
                HotIfWinActive "ahk_class grcWindow"
                Hotkey("*$" this.value, ObjBindMethod(this, "performHotkey"), "On")
                HotIfWinActive
            } catch {
                throw UnsetError("Could not register hotkey: " this.value)
            }
        }
        this.oldValue := this.value
        this.saveValue()
    }
}

; Waits exactly 1 frame thanks to the keyboard hook in GTA
frameSleep(amount) {
    loop amount {
        Send("{Blind}{f24 up}")
    }
}

; Uses a combination of the scroll wheel and the arrow keys to scroll faster, you can scroll twice in 3 frames with this instead of 4.
scrollInDirection(direction, amount, extraInput?) {
    doExtraInput := () { ; Send an extra input if provided by the caller
        if (IsSet(extraInput) && extraInput != "") {
            SendInputLinux(extraInput)
            extraInput := ""
        }
    }

    if (amount == 1) {
        Send("{Blind}{" direction "}")
        doExtraInput()
        return
    }

    loop Floor(amount / 2) {
        Send("{Blind}{" direction " down}")
        doExtraInput()
        Send ("{Blind}{" direction " up}")

        if (isCursorHidden()) {
            Send("{Blind}{Wheel" direction "}")
        } else {
            Send("{Blind}{" direction "}")
        }
        if (amount >= 3) {
            frameSleep(1)
        }
    }

    if (amount & 1) {
        Send("{Blind}{" direction "}")
    }
}

accurateSleep(ms) {
    ; DllCall("Sleep", "UInt", ms)

    ; DllCall("ntdll\ZwDelayExecution", "Int", 0, "Int64*", -(ms * 10000))

    ; lets you sleep in 0.5ms intervals instead of 1ms
    dueTime := Buffer(8, 0)
    NumPut("Int64", -(ms * 10000), dueTime, 0)

    start := Buffer(8, 0)
    DllCall("QueryPerformanceCounter", "Ptr", start)

    if (!DllCall("SetWaitableTimer", "Ptr", hTimer, "Ptr", dueTime, "Int", 0, "Ptr", 0, "Ptr", 0, "Int", 0)) {
        throw Error("Failed to set waitable timer for some reason")
        ExitApp()
    }

    DllCall("WaitForSingleObject", "Ptr", hTimer, "UInt", 0xFFFFFFFF)
}

setKeyboardHookState(state) {
    FILE_MAP_ALL_ACCESS := 0xF001F
    MAP_NAME := "Local\ParagonKeyboardHookDisabler"

    hMapFile := DllCall("OpenFileMapping", "UInt", FILE_MAP_ALL_ACCESS, "Int", 0, "Str", MAP_NAME, "Ptr")

    if (!hMapFile) {
        return false
    }

    pSharedSignal := DllCall("MapViewOfFile", "Ptr", hMapFile, "UInt", FILE_MAP_ALL_ACCESS, "UInt", 0, "UInt", 0, "Ptr", 1024, "Ptr")
    if (!pSharedSignal) {
        DllCall("CloseHandle", "Ptr", hMapFile)
        return false 
    }

    NumPut("Char", !state, pSharedSignal)

    DllCall("UnmapViewOfFile", "Ptr", pSharedSignal)
    DllCall("CloseHandle", "Ptr", hMapFile)
    return true
}

getKeyboardHookState() {
    FILE_MAP_ALL_ACCESS := 0xF001F
    MAP_NAME := "Local\ParagonKeyboardHookDisabler"

    hMapFile := DllCall("OpenFileMapping", "UInt", FILE_MAP_ALL_ACCESS, "Int", 0, "Str", MAP_NAME, "Ptr")

    if (!hMapFile) {
        return false
    }

    pSharedSignal := DllCall("MapViewOfFile", "Ptr", hMapFile, "UInt", FILE_MAP_ALL_ACCESS, "UInt", 0, "UInt", 0, "Ptr", 1024, "Ptr")
    if (!pSharedSignal) {
        DllCall("CloseHandle", "Ptr", hMapFile)
        return false 
    }

    state := NumGet(pSharedSignal, "Char")

    DllCall("UnmapViewOfFile", "Ptr", pSharedSignal)
    DllCall("CloseHandle", "Ptr", hMapFile)
    return state
}

SendInputLinux(keys) {
    if (isOnLinux) {
        ; setKeyboardHookState(false)
        Send(keys)
        ; SetTimer((*) => reinstallHooks(), -50)
    } else {
        SendInput(keys)
    }
}

reinstallHooks() {
    InstallKeybdHook(0, 1)
    InstallKeybdHook(1, 1)
}

IsWine() {
    try {
        if hNtdll := DllCall("GetModuleHandle", "Str", "ntdll.dll", "Ptr") {
            if pWineVersion := DllCall("GetProcAddress", "Ptr", hNtdll, "AStr", "wine_get_version", "Ptr") {
                version := DllCall(pWineVersion, "CDecl Str")
                return version
            }
        }
    }
    return false
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
        if (setting.tab != tabs[activeTab]) {
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
    for tabName in tabs {
        for setting in settings[tabName] {
            if (setting.name == settingName) {
                if (setting.type == "hotkey" && setting.value == "" && !ignoreErrors) {
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
    ; DllCall("SetCursorPos", "Int", coords.x, "Int", coords.y)
    CoordMode("mouse","screen")
    MouseMove(coords.x, coords.y)
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
    return CounterBefore / queryPerformanceFrequency
}

stopCounting(startTime) {
    CounterAfter := 0
    DllCall("QueryPerformanceCounter", "Int64P", &CounterAfter)
    return (CounterAfter / queryPerformanceFrequency - startTime) * 1000
}

onChatClose() {
    global chatOpen := false
}

isCursorHidden() {
    return false ; A_Cursor == "Unknown"
}

turnDegrees(degrees) {
    ; These values aren't fully accurate but it's impossible to get perfect accuracy because you can only move the mouse 1 pixel, not half a pixel. So the higher resolution, the more accurate it should theoretically be.
    scalar := GetKeyState("RButton", "P") ? (322 / 180) : (263 / 180) ; Different sensitivy for when aiming down sights. Won't work if you zoom in with sniper scope though. Measurements done at 4K resolution.
    pixelsPerDegree := scalar / (3840 / A_ScreenWidth) ; Empirical value for converting degrees to pixels with raw input mode and lowest in-game sensitivity.
    MouseMove(-(degrees * pixelsPerDegree), 0, 0)
}

; I decided to put this in the bottom of the file because it'll be really long.
makeSettings() {
    HotkeyElement("Sniper rifle keybind", "9", enumTabs["KEYBINDS"])
    HotkeyElement("Heavy weapon keybind", "4", enumTabs["KEYBINDS"])
    HotkeyElement("Sticky bomb keybind", "5", enumTabs["KEYBINDS"])
    HotkeyElement("Pistol keybind", "6", enumTabs["KEYBINDS"])
    HotkeyElement("Shotgun keybind", "3", enumTabs["KEYBINDS"])
    HotkeyElement("Rifle keybind", "8", enumTabs["KEYBINDS"])
    HotkeyElement("SMG keybind", "7", enumTabs["KEYBINDS"])
    HotkeyElement("Fists keybind", "1", enumTabs["KEYBINDS"])
    HotkeyElement("Melee weapon keybind", "2", enumTabs["KEYBINDS"])
    HotkeyElement("Interaction menu keybind", "m", enumTabs["KEYBINDS"])
    HotkeyElement("EWO Animation keybind", "capslock", enumTabs["KEYBINDS"])
    HotkeyElement("Melee punch keybind", "r", enumTabs["KEYBINDS"])
    HotkeyElement("Look behind keybind", "c", enumTabs["KEYBINDS"])
    HotkeyElement("Chat keybind (automatically suspend macros when chat open)", "", enumTabs["KEYBINDS"], (*) {
        thisKeybind := retrieveSetting("Chat keybind (automatically suspend macros when chat open)").value
        Send("{Blind}{" thisKeybind "}")
        global chatOpen := true
    })
    HotkeyElement("Sprint keybind", "lshift", enumTabs["KEYBINDS"])

    SettingElement("Use cursor in interaction menu for slightly faster macros", "bool", false, enumTabs["GENERAL"])
    HotkeyElement("Ammo", "", enumTabs["GENERAL"], (*) {
        interactionKey := retrieveSetting("Interaction menu keybind").value

        SendInputLinux("{Blind}{lbutton up}{enter down}")
        Send("{Blind}{" interactionKey "}")
        scrollInDirection("Down", inCEO ? 3 : 2)
        SendInputLinux("{Blind}{enter up}")
        Send("{Blind}{enter down}")
        scrollInDirection("Down", 5)
        SendInputLinux("{Blind}{enter up}")
        Send("{Blind}{up}")
        SendInputLinux("{Blind}{enter}")
        Send("{Blind}{" interactionKey "}")
        accurateSleep(100)
    })
    HotkeyElement("EWO", "", enumTabs["GENERAL"], (*) {
        interactionKey := retrieveSetting("Interaction menu keybind").value
        animationKey := retrieveSetting("EWO Animation keybind").value
        meleePunchKey := retrieveSetting("Melee punch keybind").value
        lookBehindKey := retrieveSetting("Look behind keybind").value
        sprintKey := retrieveSetting("Sprint keybind").value
        ewoDelay := retrieveSetting("EWO delay (ms) (for cleaner looking ragdoll)").value
        shouldShoot := retrieveSetting("Shoot before EWOing").value

        if (shouldShoot) {
            SendInputLinux("{Blind}{lbutton down}")
        }
        if (GetKeyState(lookBehindKey, "P")) {
            SendInputLinux("{Blind}{" lookBehindKey " up}")
        }
        startTime := startCounting()
        SendInputLinux("{Blind}{" lookBehindKey " down}{lbutton up}{rbutton up}{enter down}{up down}{" meleePunchKey " down}{" interactionKey " down}{" animationKey " down}")

        SendInputLinux("{Blind}{" animationKey " up}{" interactionKey " up}")
        Send("{Blind}{WheelUp}") ; Not using mousewheel because it breaks a lot for some people or something idk retards dude.
        if (ewoDelay != "" && ewoDelay > 0) {
            timeDelta := stopCounting(startTime)
            remainingTime := ewoDelay - timeDelta
            if (remainingTime > 0) {
                accurateSleep(Ceil(remainingTime))
            }
        }

        ; We press animation key twice in case the first one was blocked by the game because the game sometimes disables the key.
        SendInputLinux("{Blind}{" animationKey " down}{enter up}{" lookBehindKey " up}")
        frameSleep(2)
        SendInputLinux("{Blind}{" animationKey " up}{up up}{ " meleePunchKey " up}")
        SetCapsLockState("Off")
    })
    SettingElement("EWO delay (ms) (for cleaner looking ragdoll)", "string", "0", enumTabs["GENERAL"])
    SettingElement("Shoot before EWOing", "bool", false, enumTabs["GENERAL"])

    HotkeyElement("Toggle CEO", "", enumTabs["GENERAL"], (*) {
        interactionKey := retrieveSetting("Interaction menu keybind").value

        SendInputLinux("{Blind}{enter down}")
        if (inCEO) {
            Send("{Blind}{" interactionKey "}{enter up}{up down}")
            SendInputLinux("{Blind}{enter down}")
            Send("{Blind}{up up}{enter up}")
        } else {
            Send("{Blind}{" interactionKey "}")
            scrollInDirection("Down", 6)
            SendInputLinux("{Blind}{enter up}")
            Send("{Blind}{enter}")
        }
        global inCEO := !inCEO
    })

    HotkeyElement("Chat Spam", "", enumTabs["GENERAL"], (*) {
        chatSpamText := retrieveSetting("Chat Spam Text").value
        thisKeybind := retrieveSetting("Chat Spam").value
        chatKeybind := retrieveSetting("Chat keybind (automatically suspend macros when chat open)").value
        while (GetKeyState(thisKeybind, "P")) {
        Send("{Blind}{" chatKeybind "}")
        SendStringByMessage(chatSpamText)
        Send("{Blind}{enter}")
        }
    })
    SettingElement("Chat Spam Text", "string", "Ω", enumTabs["GENERAL"])
    HotkeyElement("Fast respawn", "", enumTabs["GENERAL"], (*) {
        loop 30 {
            SendInputLinux("{Blind}{lbutton down}")
            frameSleep(1)
            SendInputLinux("{Blind}{lbutton up}")
            frameSleep(1)
        }
    })
    HotkeyElement("Quick turn keybind", "", enumTabs["GENERAL"], (*) {
        degrees := retrieveSetting("Degrees to turn").value
        turnDegrees(degrees)
    })
    SettingElement("Degrees to turn", "string", "180", enumTabs["GENERAL"])

    quickSwitchMethod := (keybind, *) {
        weaponKey := retrieveSetting(keybind).value
        Send("{Blind}{" weaponKey " down}{tab}")
        Send("{Blind}{" weaponKey " up}")
    }
    HotkeyElement("Sniper rifle tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Sniper rifle keybind"))
    HotkeyElement("Heavy weapon tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Heavy weapon keybind"))
    HotkeyElement("Sticky bomb tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Sticky bomb keybind"))
    HotkeyElement("Pistol tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Pistol keybind"))
    HotkeyElement("Shotgun tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Shotgun keybind"))
    HotkeyElement("Rifle tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Rifle keybind"))
    HotkeyElement("SMG tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("SMG keybind"))
    HotkeyElement("Fists tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Fists keybind"))
    HotkeyElement("Melee weapon tab switch", "", enumTabs["WEAPONSWITCH"], (*) => quickSwitchMethod("Melee weapon keybind"))
    HotkeyElement("RPG Spam", "", enumTabs["WEAPONSWITCH"], (*) {
        heavyWeaponKey := retrieveSetting("Heavy weapon keybind").value
        stickyBombKey := retrieveSetting("Sticky bomb keybind").value
        Send("{Blind}{" stickyBombKey " down}")
        frameSleep(2)
        Send("{Blind}{" heavyWeaponKey " down}{tab}")
        SendInputLinux("{Blind}{" heavyWeaponKey " up}{" stickyBombKey " up}")
    })
    HotkeyElement("Sniper Spam", "", enumTabs["WEAPONSWITCH"], (*) {
        sniperRifleKey := retrieveSetting("Sniper rifle keybind").value
        stickyBombKey := retrieveSetting("Sticky bomb keybind").value
        Send("{Blind}{" stickyBombKey " down}{" sniperRifleKey " down}{tab}")
        SendInputLinux("{Blind}{" sniperRifleKey " up}{" stickyBombKey " up}")
    })
    HotkeyElement("Double heavy switch","", enumTabs["WEAPONSWITCH"], (*) {
        heavyWeaponKey := retrieveSetting("Heavy weapon keybind").value
        Send("{Blind}{" heavyWeaponKey "}{" heavyWeaponKey " down}{tab}{" heavyWeaponKey " up}")
    })
}

SendString(text) {
    ; --- Constants from WinUser.h ---
    static INPUT_KEYBOARD := 1
    static KEYEVENTF_UNICODE := 0x0004
    static KEYEVENTF_KEYUP   := 0x0002
    
    ; --- Structure Sizing & Offsets ---
    ; The INPUT structure is larger on x64 due to alignment padding.
    ; x64: type(4) + pad(4) + union(32) = 40 bytes
    ; x86: type(4) + union(24) = 28 bytes
    cbSize := (A_PtrSize == 8) ? 40 : 28
    
    ; Offsets within the KEYBOARDINPUT union
    ; x64: wVk is at offset 8, wScan at 10, dwFlags at 12
    ; x86: wVk is at offset 4, wScan at 6, dwFlags at 8
    off_wScan   := (A_PtrSize == 8) ? 10 : 6
    off_dwFlags := (A_PtrSize == 8) ? 12 : 8
    
    ; --- buffer Creation ---
    ; We need 2 events (Down + Up) per character
    inputCount := StrLen(text) * 2
    inputs := Buffer(inputCount * cbSize, 0) ; Initialize with 0
    
    ; --- Fill the Buffer ---
    loop parse text {
        char := Ord(A_LoopField) ; Get Unicode value
        i := A_Index - 1
        
        ; 1. Key Down Event
        baseOffset := (i * 2) * cbSize
        NumPut("UInt",   INPUT_KEYBOARD,    inputs, baseOffset)
        NumPut("UShort", char,              inputs, baseOffset + off_wScan)
        NumPut("UInt",   KEYEVENTF_UNICODE, inputs, baseOffset + off_dwFlags)
        
        ; 2. Key Up Event
        baseOffset := (i * 2 + 1) * cbSize
        NumPut("UInt",   INPUT_KEYBOARD,    inputs, baseOffset)
        NumPut("UShort", char,              inputs, baseOffset + off_wScan)
        ; Combine flags: UNICODE | KEYUP
        NumPut("UInt",   KEYEVENTF_UNICODE | KEYEVENTF_KEYUP, inputs, baseOffset + off_dwFlags)
    }
    
    ; --- DllCall ---
    ; UINT SendInput(UINT cInputs, LPINPUT pInputs, int cbSize)
    DllCall("SendInput", "UInt", inputCount, "Ptr", inputs, "Int", cbSize)
}

SendStringByMessage(text) {
    ; WM_CHAR = 0x0102
    ; PostMessage places the message in the queue and returns immediately.
    ; This bypasses the LowLevelKeyboardHook because that hook monitors
    ; the hardware input stream, not the application message queue.
    
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if !hwnd
        return

    loop parse text {
        char := Ord(A_LoopField)
        
        ; PostMessageW(hWnd, Msg, wParam, lParam)
        ; wParam = The character code (Unicode)
        ; lParam = 1 (Repeat count, etc. - usually 1 or 0 is fine for simple text)
        DllCall("PostMessage", "Ptr", hwnd, "UInt", 0x0102, "Ptr", char, "Ptr", 1)
        
        ; Optional: Small sleep to prevent message queue flooding if string is huge
    }
}
