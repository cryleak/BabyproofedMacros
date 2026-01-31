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
            SendInput(extraInput)
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
            SendInput("{Blind}{Wheel" direction "}")
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

    DllCall("ntdll\ZwDelayExecution", "Int", 0, "Int64*", -(ms * 10000))
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
    return { x: pixelX, y: pixelY }
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
    frequency := 0
    CounterBefore := 0
    DllCall("QueryPerformanceFrequency", "Int64P", &frequency)
    DllCall("QueryPerformanceCounter", "Int64P", &CounterBefore)
    return CounterBefore / frequency
}

stopCounting(startTime) {
    frequency := 0
    CounterAfter := 0
    DllCall("QueryPerformanceFrequency", "Int64P", &frequency)
    DllCall("QueryPerformanceCounter", "Int64P", &CounterAfter)
    return (CounterAfter / frequency - startTime) * 1000
}

onChatClose() {
    global chatOpen := false
}

isCursorHidden() {
    return A_Cursor == "Unknown"
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
        shouldUseCursor := retrieveSetting("Use cursor in interaction menu for slightly faster macros").value
        interactionKey := retrieveSetting("Interaction menu keybind").value

        SendInput("{Blind}{lbutton up}{enter down}")
        Send("{Blind}{" interactionKey "}")
        scrollInDirection("Down", inCEO ? 3 : 2)
        SendInput("{Blind}{enter up}")
        if (shouldUseCursor) {
            Send("{Blind}{f24 up}")
            SendInput("{Blind}{lbutton down}{enter down}")
            Send("{Blind}{f24 up}")
            moveToPixelCoordinates(0.1175, 0.32075) ; Exact center of the "Ammo" button on 16:9, interaction menu is wider on ultrawide so it won't be the center but still relatively centered.
            SendInput("{Blind}{lbutton up}")
            Send("{Blind}{enter up}{up down}")
            SendInput("{Blind}{enter down}")
            Send("{Blind}{up up}")
            SendInput("{Blind}{enter up}")
        } else {
            frameSleep(1)
            scrollInDirection("Down", 5, "{Blind}{enter down}")
            SendInput("{Blind}{enter up}")
            Send("{Blind}{up down}")
            SendInput("{Blind}{enter down}")
            Send("{Blind}{up up}")
            SendInput("{Blind}{enter up}")
        }
        Send("{Blind}{" interactionKey "}")
        BlockInput("MouseMoveOff")
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

        shouldSleep := false
        if (shouldShoot) {
            SendInput("{Blind}{lbutton down}")
            shouldSleep := true
        }
        if (GetKeyState(lookBehindKey, "P")) {
            SendInput("{Blind}{" lookBehindKey " up}")
            shouldSleep := true
        }
        if (shouldSleep) {
            frameSleep(1)
        }
        startTime := startCounting()
        SendInput("{Blind}{lbutton up}{rbutton up}{w up}{a up}{s up}{d up}{enter down}{up down}{lshift up}{" meleePunchKey " down}{" interactionKey " down}{" lookBehindKey " down}{" sprintKey " up}{" animationKey " down}")

        frameSleep(1)
        SendInput("{Blind}{" animationKey " up}{" interactionKey " up}{" meleePunchKey " up}")
        frameSleep(1)
        Send("{Blind}{up up}")
        Send("{Blind}{up}") ; Not using mousewheel because it breaks a lot for some people or something idk retards dude.
        if (ewoDelay != "" && ewoDelay > 0) {
            timeDelta := stopCounting(startTime)
            remainingTime := ewoDelay - timeDelta
            if (remainingTime > 0) {
                accurateSleep(Ceil(remainingTime))
            }
        }

        ; We press animation key twice in case the first one was blocked by the game because the game sometimes disables the key.
        SendInput("{Blind}{" animationKey " down}{enter up}{" lookBehindKey " up}")
        frameSleep(2)
        SendInput("{Blind}{" animationKey " up}{up up}")
        SetCapsLockState("Off")
    })
    SettingElement("EWO delay (ms) (for cleaner looking ragdoll)", "string", "0", enumTabs["GENERAL"])
    SettingElement("Shoot before EWOing", "bool", false, enumTabs["GENERAL"])

    HotkeyElement("Toggle CEO", "", enumTabs["GENERAL"], (*) {
        interactionKey := retrieveSetting("Interaction menu keybind").value

        SendInput("{Blind}{enter down}")
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
        global inCEO := !inCEO
    })

    HotkeyElement("Chat Spam", "", enumTabs["GENERAL"], (*) {
        chatSpamText := retrieveSetting("Chat Spam Text").value
        thisKeybind := retrieveSetting("Chat Spam").value
        chatKeybind := retrieveSetting("Chat keybind (automatically suspend macros when chat open)").value
        ; while (GetKeyState(thisKeybind, "P")) {
            Send("{Blind}{" chatKeybind " down}")
            SendInput("{Blind}{enter down}")
            Send("{Blind}{" chatKeybind " up}")
            frameSleep(1)
            SendInput("{Raw}" chatSpamText)
            Send("{Blind}{enter up}")
       ; }
    })
    SettingElement("Chat Spam Text", "string", "Ω", enumTabs["GENERAL"])
    HotkeyElement("Fast respawn", "", enumTabs["GENERAL"], (*) {
        loop 30 {
            SendInput("{Blind}{lbutton down}")
            frameSleep(1)
            SendInput("{Blind}{lbutton up}")
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
        Send("{Blind}{" weaponKey " down}{tab down}")
        SendInput("{Blind}{" weaponKey " up}")
        Send("{Blind}{tab up}")
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
        Send("{Blind}{" heavyWeaponKey " down}{tab down}")
        SendInput("{Blind}{" heavyWeaponKey " up}{" stickyBombKey " up}")
        Send("{Blind}{tab up}")
    })
    HotkeyElement("Sniper Spam", "", enumTabs["WEAPONSWITCH"], (*) {
        sniperRifleKey := retrieveSetting("Sniper rifle keybind").value
        stickyBombKey := retrieveSetting("Sticky bomb keybind").value
        Send("{Blind}{" stickyBombKey " down}{" sniperRifleKey " down}{tab down}")
        SendInput("{Blind}{" sniperRifleKey " up}{" stickyBombKey " up}")
        Send("{Blind}{tab up}")
    })
}
