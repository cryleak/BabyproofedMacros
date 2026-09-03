global macroVersion := "1.1.5"
#Requires AutoHotkey v2.1-alpha.28
#SingleInstance Force
#Warn All, Off
#UseHook 1
#include RAGEKeyMap.ahk
#include lib/UIInterop.ahk
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

if !IsWindows10OrLater() {
  MsgBox("Babyproofed Macros does not support Windows 7, Windows 8, or Windows 8.1. Please use Windows 10 or later.", "Babyproofed Macros", "Iconx")
  ExitApp()
}

((*) { ; Don't pollute the global namespace with variables that are useless after initialization
  fullCommandLine := DllCall("GetCommandLine", "str")

  if (!A_IsAdmin || !RegExMatch(fullCommandLine, " /restart(?!\S)")) {
    try
    {
      if A_IsCompiled
        Run '*RunAs "' A_ScriptFullPath '" /restart'
      else
        Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
    }
    ExitApp
  }
  oldRes := 0
  DllCall("ntdll\ZwSetTimerResolution", "Int", 5000, "Int", 1, "Int*", &oldRes)
})()

targetDir := A_MyDocuments "\HorribleBaseMacros"
if !DirExist(targetDir)
  DirCreate(targetDir)
SetWorkingDir(A_ScriptDir)

IsWindows10OrLater() {
  osVersion := Buffer(284, 0)
  NumPut("UInt", osVersion.Size, osVersion)
  DllCall("ntdll\RtlGetVersion", "Ptr", osVersion)
  return NumGet(osVersion, 4, "UInt") >= 10
}

global settings := Map()
global tabs := {
  GENERAL: "General Macros",
  WEAPONSWITCH: "Weapon switching Macros",
  KEYBINDS: "In-game keybinds",
  ADVANCED: "Advanced Settings"
}
global guiTabs := []

((*) {
  tabOrder := ["GENERAL", "WEAPONSWITCH", "KEYBINDS", "ADVANCED"] ; Apparently Object.OwnProps() returns them in alphabetical order, not the order they were defined in...
  for key in tabOrder {
    guiTabs.Push(tabs.%key%)
  }
})()

global inCEO := false
global chatOpen := false
global coutObj := unset

global macroExecutionStart := 0
global macroExecutionTime := 0
global lastMacroExecutionTime := 0

global lastTabSwitchData := { weaponKey: "", time: 0 }
global queryPerformanceFrequency := 0
DllCall("QueryPerformanceFrequency", "Int64P", &queryPerformanceFrequency)
Hotkey("~*Enter", (*) {
  onChatClose()
  return 0
})
Hotkey("~*Esc", (*) {
  onChatClose()
  return 0
})

if (!isRunningInExeContainer()) {
  Hotkey("*F12", (*) {
    Reload()
    return 0
  })
}

InstallRuntimeAssets(targetDir) {
  uiDir := targetDir "\ui"
  webView2Dir := targetDir "\lib\WebView2"
  DirCreate(uiDir)
  DirCreate(webView2Dir)

  FileInstall "ui\index.html", uiDir "\index.html", 1
  FileInstall "ui\app.js", uiDir "\app.js", 1
  FileInstall "ui\styles.css", uiDir "\styles.css", 1
  FileInstall "lib\WebView2\WebView2Loader.dll", webView2Dir "\WebView2Loader.dll", 1
  InstallWebView2Runtime(webView2Dir)
  return 0
}

InstallWebView2Runtime(webView2Dir) {
  runtimeRoot := webView2Dir "\FixedVersionRuntime"
  runtimeDir := runtimeRoot "\Microsoft.WebView2.FixedVersionRuntime.150.0.4078.105.x64"
  if FileExist(runtimeDir "\msedgewebview2.exe") {
    return 0
  }

  cabPath := webView2Dir "\WebView2Runtime.cab"
  expandLogPath := webView2Dir "\WebView2Runtime.expand.log"
  try {
    DownloadWebView2Runtime(cabPath)
    try {
      DirCreate(runtimeRoot)
    } catch as err {
      throw Error("Could not create the WebView2 runtime folder:`n`n" runtimeRoot "`n`n" err.Message)
    }

    if FileExist(expandLogPath) {
      FileDelete(expandLogPath)
    }
    expandExitCode := RunWait(A_ComSpec ' /d /c expand.exe -F:* "' cabPath '" "' runtimeRoot '" > "' expandLogPath '" 2>&1', , "Hide")
    expandOutput := ""
    if (FileExist(expandLogPath) && FileGetSize(expandLogPath) > 0) {
      expandOutput := Trim(FileRead(expandLogPath))
    }
    if (expandExitCode != 0) {
      message := "Could not unpack the WebView2 runtime.`n`nexpand.exe exit code: " expandExitCode
      if (expandOutput != "") {
        message .= "`n`nexpand.exe output:`n" expandOutput
      }
      throw Error(message)
    }
    if !FileExist(runtimeDir "\msedgewebview2.exe") {
      message := "WebView2 unpacking finished, but the expected executable was not found:`n`n" runtimeDir "\msedgewebview2.exe"
      if (expandOutput != "") {
        message .= "`n`nexpand.exe output:`n" expandOutput
      }
      throw Error(message)
    }
  } finally {
    if FileExist(cabPath) {
      FileDelete(cabPath)
    }
    if FileExist(expandLogPath) {
      FileDelete(expandLogPath)
    }
  }
  return 0
}

DownloadWebView2Runtime(cabPath) {
  url := "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b401c036-cfb8-4dc4-a58e-8766441df4ac/Microsoft.WebView2.FixedVersionRuntime.150.0.4078.105.x64.cab?cache=" A_NowUTC "_" A_TickCount
  request := ComObject("WinHttp.WinHttpRequest.5.1")
  try {
    request.Open("HEAD", url, false)
    request.Send()
  } catch as err {
    throw Error("Could not contact the WebView2 download server. Check the internet connection, firewall, proxy, or antivirus settings.`n`n" err.Message)
  }

  if (request.Status < 200 || request.Status >= 300) {
    throw Error("The WebView2 download server returned HTTP status " request.Status ".")
  }

  try {
    totalBytes := Integer(request.GetResponseHeader("Content-Length"))
  } catch as err {
    throw Error("The WebView2 download server did not provide a valid file size.`n`n" err.Message)
  }
  if (totalBytes <= 0) {
    throw Error("The WebView2 download server returned an invalid file size.")
  }

  curlErrorPath := cabPath ".error.txt"
  try {
    if FileExist(curlErrorPath) {
      FileDelete(curlErrorPath)
    }

    pid := 0
    try {
      Run('curl.exe -L --fail --silent --show-error --stderr "' curlErrorPath '" -o "' cabPath '" "' url '"', , "Hide", &pid)
    } catch as err {
      throw Error("Could not start curl.exe to download the WebView2 runtime.`n`n" err.Message)
    }

    while ProcessExist(pid) {
      downloadedBytes := FileExist(cabPath) ? FileGetSize(cabPath) : 0
      ToolTip("Downloading WebView2 runtime: " Min(100, Floor(downloadedBytes / totalBytes * 100)) "%")
      Sleep(100)
    }
    ToolTip()

    curlOutput := ""
    if (FileExist(curlErrorPath) && FileGetSize(curlErrorPath) > 0) {
      curlOutput := Trim(FileRead(curlErrorPath))
    }
    if !FileExist(cabPath) {
      message := "The WebView2 download did not create a CAB file."
      if (curlOutput != "") {
        message .= "`n`nDownload tool output:`n" curlOutput
      }
      throw Error(message)
    }

    downloadedBytes := FileGetSize(cabPath)
    if (downloadedBytes != totalBytes) {
      message := "The WebView2 download was incomplete.`n`nExpected: " totalBytes " bytes`nReceived: " downloadedBytes " bytes"
      if (curlOutput != "") {
        message .= "`n`nDownload tool output:`n" curlOutput
      }
      throw Error(message)
    }
  } finally {
    ToolTip()
    if FileExist(curlErrorPath) {
      FileDelete(curlErrorPath)
    }
  }
  return 0
}

try {
  InstallRuntimeAssets(targetDir)
  SetWorkingDir(targetDir)
  settingsManagerInstance := SettingsManager()
} catch as err {
  userMessage := GetStartupErrorMessage(err)
  technicalDetails := FormatErrorDetails(err)
  if (uiInteropLastError != "" && uiInteropLastError != technicalDetails) {
    technicalDetails .= "`n`nLast OnError callback details:`n" uiInteropLastError
  }
  technicalDetails .= "`n`nAutoHotkey: " A_AhkVersion
  technicalDetails .= "`nCompiled: " (A_IsCompiled ? "yes" : "no")
  technicalDetails .= "`nScript: " A_ScriptFullPath
  ErrorLogger.Log("startup", technicalDetails)
  A_Clipboard := technicalDetails
  MsgBox("Babyproofed Macros could not start its settings UI.`n`n" userMessage "`n`nTechnical details were copied to the clipboard and logged when possible.", "Babyproofed Macros", "Iconx")
  ExitApp()
}

GetStartupErrorMessage(exception) {
  try {
    message := exception.Message
    if (message != "") {
      return message
    }
  } catch {
  }
  return "An unknown error occurred while starting the application."
}

global spamManagerInstance := SpamManager()

/*
SetTimer((*) {
    str := "A state: " KeyState.getKeyState("a") " D state: " KeyState.getKeyState("d") " Time: " startCounting()
    str .= "`nA disabled: " KeyDisabler.isKeyDisabled("a") " D disabled: " KeyDisabler.isKeyDisabled("d")
    ToolTip(str, 0, 0)
}, 1)
*/

class SettingsManager {
  __New() {
    this.pendingHotkeyName := ""
    this.captureHotkeysSuspended := false
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
      return 0
    }, -50)
  }

  makeGUI() {
    global settingsGui := (this.ui := SettingsWebUI(this)).window
    this.ui.Show()
    if (InStr(A_ScriptName, ".ahk")) {
      A_TrayMenu.Delete("&Help")
      A_TrayMenu.Delete("&Window Spy")
      A_TrayMenu.Delete("&Edit Script")
      A_TrayMenu.Delete("&Reload Script")
      A_TrayMenu.Delete("4&")
      A_TrayMenu.Delete("2&")
    }
    A_TrayMenu.Delete("&Pause Script")
    A_TrayMenu.Add("Reload Script", (*) {
      Reload()
      return 0
    })
    A_TrayMenu.Add("Show Settings", (*) {
      this.ui.Show()
      return 0
    }, "P100000")
    A_TrayMenu.Default := "Show Settings"
    this._addMouseHook()

    SetTimer((*) {
      if (this.ui.IsActive()) {
        this._addMouseHook()
      } else {
        this._removeMouseHook()
      }
      return 0
    }, 100)

    ; Keep the SendInput health indicator updated while GTA is running.
    ; This timer was part of the pre-WebView2 settings window and was lost
    ; during the UI bridge refactor.
    SetTimer((*) {
      if (WinActive("ahk_class grcWindow")) {
        this._updateSendInputState()
      }
      static gtaOpen := false
      if (WinExist("ahk_class grcWindow") && !gtaOpen) {
        InstallKeybdHook(1, 1)
        gtaOpen := true
      }
      return 0
    }, 1000)
    return 0
  }

  _updateSendInputState() { ; Informational text to show if SendInput is working properly or not
    start := startCounting()
    SendInput("{Blind}{f24 2}")
    /*
    Low level keyboard hooks can be hooked in a specific order that causes every individual input in a SendInput stream to take an entire game frame to execute, making SendInput the same speed as SendEvent.
    This is impossible to fix without removing the offending keyboard hook (practically impossible since hooks are private for the application that created it only, unless you want to create something resembling an antivirus...
    or create a list of known offending applications and inject into them, which is absurdly complicated and unstable).
    If SendInput is failing, you need to figure out what application is installing a low level keyboard hook other than AutoHotkey and GTA and close the application.
    You could likely fix this by forking Wine, but that's only for Linux only obviously.
    TLDR: Windows API is fucking stupid.
    */
    end := stopCounting(start)
    status := "SendInput: " . (end < 5 ? "WORKING" : "FAILING (MACROS WILL BE SLOWER)") ; This check could technically be inaccurate if you have more than ~800 FPS... welp, guess I'll have to improve it when the Ryzen 7 12800X3D comes out.
    try this.ui.Send("sendInputStatus", status)
    return 0
  }

  _addMouseHook() {
    if (this.mouseHookActive) {
      return 0
    }
    this.mouseHookActive := true

    ; Need to bind them to this for some reason otherwise this is undefined in the handler
    try Hotkey("~LButton up", ObjBindMethod(this, "_mouseClickHandler"), "On")
    try Hotkey("~RButton up", ObjBindMethod(this, "_mouseClickHandler"), "On")
    try Hotkey("~MButton up", ObjBindMethod(this, "_mouseClickHandler"), "On")
    try Hotkey("~XButton1 up", ObjBindMethod(this, "_mouseClickHandler"), "On")
    try Hotkey("~XButton2 up", ObjBindMethod(this, "_mouseClickHandler"), "On")
    return 0
  }

  _removeMouseHook() {
    if (!this.mouseHookActive) {
      return 0
    }
    this.mouseHookActive := false

    try Hotkey("~LButton up", "Off")
    try Hotkey("~RButton up", "Off")
    try Hotkey("~MButton up", "Off")
    try Hotkey("~XButton1 up", "Off")
    try Hotkey("~XButton2 up", "Off")
    if (!this.captureHotkeysSuspended) {
      settingsManagerInstance._reregisterHotkeys()
    }
    InstallKeybdHook(1, 1)
    return 0
  }

  _mouseClickHandler(*) {
    if (!this.HasPendingHotkey()) {
      return 0
    }
    mouseKey := RegExReplace(SubStr(A_ThisHotkey, 2), "i)\s+up$", "")
    value := BuildCapturedHotkey(mouseKey)
    SetTimer(() {
      if (this.HasPendingHotkey()) {
        this.CaptureHotkey(value)
      }
      return 0
    }, -10)
    return 0
  }

  _parseFromGameKeys() {
    try settingsFile := FileRead(A_MyDocuments . "/Rockstar Games/GTA V/default/control/user.xml")
    catch {
      throw Error("Failed to read game key bindings from the controls file.")
    }
    settingsParser := XMLParser(settingsFile)

    for tabName in guiTabs {
      for setting in settings[tabName] {
        if (setting is HotkeyElement && setting.HasProp("xmlName")) {
          parsedKey := NormalizeHotkeyName(MapRAGEKeyToAHKKey(settingsParser.GetValueOrDefault("//Item[Input='" setting.xmlName "']/Parameters/Item", setting.defaultValue)))
          setting.SetValue(parsedKey)
        }
      }
    }
    return 0
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
    return 0
  }

  _reregisterHotkeys() {
    for tabName in guiTabs {
      for setting in settings[tabName] {
        if (setting is HotkeyElement) {
          setting.register()
        }
      }
    }
    return 0
  }

  GetUiStateJson() {
    tabDescriptions := Map(
      tabs.GENERAL, Map("description", "Your everyday macro controls", "help", "Bind the actions you use most and keep the common controls close at hand."),
      tabs.WEAPONSWITCH, Map("description", "Fast weapon switching and spam controls", "help", "Streamlines weapon swapping using the weapon wheel keybind to instantly hide the weapon wheel after swapping."),
      tabs.KEYBINDS, Map("description", "The keys Babyproofed Macros reads from GTA", "help", "These bindings are shared with GTA and can be imported directly from the game configuration."),
      tabs.ADVANCED, Map("description", "Power-user controls and experimental behavior", "help", "These options can change timing or input behavior. Change them deliberately and test in-game.")
    )

    state := Map("version", macroVersion, "compiled", (A_IsCompiled ? 1 : 0), "tabs", [])
    for tabName in guiTabs {
      tabInfo := tabDescriptions[tabName]
      tabState := Map("id", tabName, "label", tabName, "description", tabInfo["description"], "help", tabInfo["help"], "settings", [])
      for setting in settings[tabName] {
        if (setting.invisible) {
          continue
        }
        meta := this.GetSettingUiMeta(setting)
        value := setting.value
        if (setting.type = "bool") {
          value := (setting.value = 1 || setting.value = "1" || setting.value = true) ? 1 : 0
        }
        tabState["settings"].Push(Map(
          "name", setting.name,
          "label", meta["label"],
          "description", meta["description"],
          "type", setting.type,
          "value", value,
          "experimental", meta["experimental"],
          "danger", meta["danger"]
        ))
      }
      state["tabs"].Push(tabState)
    }
    return JsonStringify(state)
  }

  GetSettingUiMeta(setting) {
    label := setting.name
    label := RegExReplace(label, "i) \(automatically suspend macros when chat open\)", "")
    label := RegExReplace(label, "i) keybind$", "")

    description := setting.type = "hotkey" ? "Choose a key, modifier, or modifier combination that triggers this macro." : setting.type = "bool" ? "Enable or disable this behavior." : "Set the value used by this macro."
    experimental := InStr(setting.name, "experimental") || InStr(setting.name, "buggy") || InStr(setting.name, "developers")
    danger := setting.name = SettingKey.C4_MODE || setting.name = SettingKey.FULLY_AUTOMATED_SPAM

    if (setting.uiMeta.Has("label")) {
      label := setting.uiMeta["label"]
    }
    if (setting.uiMeta.Has("description")) {
      description := setting.uiMeta["description"]
    }
    return Map("label", label, "description", description, "experimental", !!experimental, "danger", !!danger)
  }
  HandleUiSetting(name, value) {
    setting := retrieveSetting(name, true)
    if (setting = "" || setting.invisible) {
      throw Error("Unknown setting: " name)
    }
    if (setting is HotkeyElement) {
      value := NormalizeHotkeyName(value)
    }
    setting.SetValue(value)
    if (this.pendingHotkeyName = name) {
      this.pendingHotkeyName := ""
      this._setCaptureHotkeys(true)
    }
    return "ok"
  }
  SaveFromUi() {
    try {
      this._updateHotkeys()
      return JsonStringify(Map("ok", 1))
    } catch as err {
      return JsonStringify(Map("ok", 0, "message", err.Message))
    }
  }
  DiscardFromUi() {
    this.pendingHotkeyName := ""
    this._setCaptureHotkeys(true)
    for tabName in guiTabs {
      for setting in settings[tabName] {
        setting.ReloadFromDisk()
      }
    }
    return this.GetUiStateJson()
  }
  ImportFromUi() {
    try {
      this._parseFromGameKeys()
      return JsonStringify(Map("ok", 1, "state", this.GetUiStateJson()))
    } catch as err {
      return JsonStringify(Map("ok", 0, "message", err.Message))
    }
  }
  BeginHotkeyCapture(name) {
    setting := retrieveSetting(name, true)
    if (setting = "" || !(setting is HotkeyElement) || setting.invisible) {
      throw Error("That setting cannot capture a hotkey.")
    }
    this.pendingHotkeyName := name
    this._setCaptureHotkeys(false)
    return "ok"
  }
  CancelHotkeyCapture() {
    this.pendingHotkeyName := ""
    this._setCaptureHotkeys(true)
    return "ok"
  }
  HasPendingHotkey() {
    return this.pendingHotkeyName != ""
  }
  CaptureHotkey(value) {
    if (this.pendingHotkeyName = "") {
      return 0
    }
    name := this.pendingHotkeyName
    this.pendingHotkeyName := ""
    this._setCaptureHotkeys(true)
    this.ui.HotkeyCaptured(name, NormalizeHotkeyName(value))
    return 0
  }
  _setCaptureHotkeys(enabled) {
    if (enabled) {
      if (!this.captureHotkeysSuspended) {
        return 0
      }
      this.captureHotkeysSuspended := false
      this._reregisterHotkeys()
      return 0
    }
    if (this.captureHotkeysSuspended) {
      return 0
    }
    this.captureHotkeysSuspended := true
    for tabName in guiTabs {
      for setting in settings[tabName] {
        if (setting is HotkeyElement) {
          setting.unregister()
        }
      }
    }
    return 0
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
    this.uiMeta := Map()
    settings[tab].Push(this)
    this.saveValue()
  }

  Describe(label := "", description := "") {
    if (label != "") {
      this.uiMeta["label"] := label
    }
    if (description != "") {
      this.uiMeta["description"] := description
    }
    return this
  }

  saveValue() {
    IniWrite(this.value, "config.ini", "config", this.name)
    return 0
  }

  getValue() {
    return IniRead("config.ini", "config", this.name, this.defaultValue)
  }

  SetValue(value) {
    this.oldValue := this.value
    if (this.type = "bool") {
      this.value := (value = 1 || value = "1" || value = true) ? 1 : 0
    } else {
      this.value := value
    }
    if (this.onChange != "") {
      this.onChange(this.value, this.oldValue, 0)
    }
    return 0
  }

  ReloadFromDisk() {
    this.SetValue(this.getValue())
    this.oldValue := this.value
    return 0
  }

  handleUpdate(guiCtrl, *) {
    this.SetValue(guiCtrl.Value)
    return 0
  }
}

class HotkeyElement extends SettingElement {
  __New(name, defaultValue, tab, macroExec := "", invisible := false, hotkeyValueAddendumPre := "", hotkeyValueAddendumPost := "", runWhenDisabled := false) {
    super.__New(name, "hotkey", defaultValue, tab, , invisible)
    this.value := NormalizeHotkeyName(this.value)
    this.oldValue := this.value
    this.saveValue()
    this.macroExec := macroExec
    this.hotkeyValueAddendumPre := hotkeyValueAddendumPre
    this.hotkeyValueAddendumPost := hotkeyValueAddendumPost == "" ? "" : " " hotkeyValueAddendumPost
    this.disabledByKeyDisabler := false
    this.runWhenDisabled := runWhenDisabled
  }

  SetValue(value) {
    return super.SetValue(NormalizeHotkeyName(value))
  }

  setXMLName(name) {
    this.xmlName := name
    return 0
  }

  register() {
    if (this.disabledByKeyDisabler) {
      this.unregister()
      return 0
    }
    if (this.value != "" && this.macroExec != "") {
      try {
        HotIfWinActive("ahk_class grcWindow")
        if (!settingsManagerInstance.isAHotkeyBoundToKey(this.oldValue)) {
          try Hotkey(this.hotkeyValueAddendumPre "*" this.oldValue this.hotkeyValueAddendumPost, , "Off")
          try Hotkey(this.hotkeyValueAddendumPre "*" this.oldValue this.hotkeyValueAddendumPost " up", , "Off")
        }
        this._bindHotkey()
      } catch as err {
        MsgBox("Could not register hotkey: " this.value "`nError: " err.Message)
      }
    }
    return 0
  }

  unregister() {
    if (this.value != "") {
      HotIfWinActive("ahk_class grcWindow")
      try Hotkey(this.hotkeyValueAddendumPre "*" this.value this.hotkeyValueAddendumPost, "Off")
      try Hotkey(this.hotkeyValueAddendumPre "*" this.value this.hotkeyValueAddendumPost " up", "Off")
      HotIfWinActive()
    }
    return 0
  }

  performHotkey(*) {
    if (InStr(this.hotkeyValueAddendumPost, "Up")) {
      KeyState.setKeyState(this.value, false)
    } else {
      KeyState.setKeyState(this.value, true)
    }
    if (chatOpen) {
      if (!InStr(this.hotkeyValueAddendumPre, "~")) {
        thisKeybind := retrieveSetting(this.name).value
        Send(ConfiguredHotkeySendString(thisKeybind))
      }
      return 0
    }
    try {
      global macroExecutionStart := startCounting()
      this.macroExec()
      global macroExecutionTime
      if (retrieveSetting(SettingKey.MACRO_SPEED_PROFILE).value && macroExecutionTime != 0) {
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
    return 0
  }

  handleUpdate(guiCtrl, *) {
    super.handleUpdate(guiCtrl)
    return 0
  }

  ; manage disabling old hotkeys and enabling new ones
  updateHotkey() {
    if (this.disabledByKeyDisabler) {
      this.unregister()
      return 0
    }
    if (this.oldValue == this.value) {
      return 0
    }
    if (this.oldValue != "" && this.macroExec != "" && !settingsManagerInstance.isAHotkeyBoundToKey(this.oldValue)) {
      HotIfWinActive("ahk_class grcWindow")
      try Hotkey(this.hotkeyValueAddendumPre "*" this.oldValue this.hotkeyValueAddendumPost, "Off")
      try Hotkey(this.hotkeyValueAddendumPre "*" this.oldValue this.hotkeyValueAddendumPost " up", "Off")
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
    return 0
  }

  _bindHotkey() {
    HotIfWinActive("ahk_class grcWindow")
    if (InStr(this.hotkeyValueAddendumPost, "Up")) {
      try Hotkey(this.hotkeyValueAddendumPre "*" this.value, (*) {
        KeyState.setKeyState(this.value, true)
        return 0
      }, "On")
    } else {
      try Hotkey(this.hotkeyValueAddendumPre "*" this.value this.hotkeyValueAddendumPost " up", (*) {
        KeyState.setKeyState(this.value, false)
        return 0
      }, "On")
    }
    try Hotkey(this.hotkeyValueAddendumPre "*" this.value this.hotkeyValueAddendumPost, ObjBindMethod(this, "performHotkey"), "On")
    HotIfWinActive()
    return 0
  }
}

NormalizeHotkeyName(value) {
  value := Trim(value)
  if (value = "") {
    return ""
  }

  value := StrReplace(value, "*", "")
  value := StrReplace(value, "~", "")
  modifierFlags := Map("^", false, "!", false, "+", false, "#", false)

  while RegExMatch(value, "i)^(Control|Ctrl|Alt|Shift|Win)\+", &match) {
    modifierName := StrLower(match[1])
    if (modifierName = "control" || modifierName = "ctrl") {
      modifierFlags["^"] := true
    } else if (modifierName = "alt") {
      modifierFlags["!"] := true
    } else if (modifierName = "shift") {
      modifierFlags["+"] := true
    } else {
      modifierFlags["#"] := true
    }
    value := SubStr(value, StrLen(match[0]) + 1)
  }

  for symbol in ["^", "!", "+", "#"] {
    if InStr(value, symbol) {
      modifierFlags[symbol] := true
      value := StrReplace(value, symbol, "")
    }
  }

  lowerValue := StrLower(value)
  if (lowerValue = "ctrl" || lowerValue = "control") {
    value := "Control"
  } else if (lowerValue = "lcontrol") {
    value := "LCtrl"
  } else if (lowerValue = "rcontrol") {
    value := "RCtrl"
  } else if (lowerValue = "lshift") {
    value := "LShift"
  } else if (lowerValue = "rshift") {
    value := "RShift"
  } else if (lowerValue = "lalt") {
    value := "LAlt"
  } else if (lowerValue = "ralt") {
    value := "RAlt"
  } else if (lowerValue = "lwin") {
    value := "LWin"
  } else if (lowerValue = "rwin") {
    value := "RWin"
  }

  prefix := ""
  for symbol in ["^", "!", "+", "#"] {
    if (modifierFlags[symbol]) {
      prefix .= symbol
    }
  }
  return prefix value
}

BuildCapturedHotkey(key) {
  prefix := ""
  if GetKeyState("Ctrl", "P") {
    prefix .= "^"
  }
  if GetKeyState("Alt", "P") {
    prefix .= "!"
  }
  if GetKeyState("Shift", "P") {
    prefix .= "+"
  }
  if GetKeyState("LWin", "P") || GetKeyState("RWin", "P") {
    prefix .= "#"
  }
  return NormalizeHotkeyName(prefix key)
}

GetPhysicalKeyState(key) {
  if (key = "") {
    return false
  }
  return GetKeyState(key, "P")
}

ConfiguredHotkeySendString(key, state := "") {
  key := NormalizeHotkeyName(key)
  if (key = "") {
    return ""
  }

  modifiers := ""
  baseKey := key
  for symbol in ["^", "!", "+", "#"] {
    if InStr(baseKey, symbol) {
      modifiers .= symbol
      baseKey := StrReplace(baseKey, symbol, "")
    }
  }

  if (state = "") {
    if (modifiers = "") {
      return "{Blind}{" baseKey "}"
    }
    result := "{Blind}"
    if InStr(modifiers, "^") {
      result .= "{Control down}"
    }
    if InStr(modifiers, "!") {
      result .= "{Alt down}"
    }
    if InStr(modifiers, "+") {
      result .= "{Shift down}"
    }
    if InStr(modifiers, "#") {
      result .= "{LWin down}"
    }
    result .= "{" baseKey " down}{" baseKey " up}"
    if InStr(modifiers, "#") {
      result .= "{LWin up}"
    }
    if InStr(modifiers, "+") {
      result .= "{Shift up}"
    }
    if InStr(modifiers, "!") {
      result .= "{Alt up}"
    }
    if InStr(modifiers, "^") {
      result .= "{Control up}"
    }
    return result
  }

  if (state = "down") {
    result := "{Blind}"
    if InStr(modifiers, "^") {
      result .= "{Control down}"
    }
    if InStr(modifiers, "!") {
      result .= "{Alt down}"
    }
    if InStr(modifiers, "+") {
      result .= "{Shift down}"
    }
    if InStr(modifiers, "#") {
      result .= "{LWin down}"
    }
    return result "{" baseKey " down}"
  }

  result := "{Blind}{" baseKey " up}"
  if InStr(modifiers, "#") {
    result .= "{LWin up}"
  }
  if InStr(modifiers, "+") {
    result .= "{Shift up}"
  }
  if InStr(modifiers, "!") {
    result .= "{Alt up}"
  }
  if InStr(modifiers, "^") {
    result .= "{Control up}"
  }
  return result
}

CheckForUpdate() {
  if (!A_IsCompiled) {
    return JsonStringify(Map("ok", 1, "compiled", 0, "available", 0, "currentVersion", macroVersion))
  }

  versionUrl := "https://raw.githubusercontent.com/cryleak/BabyproofedMacros/refs/heads/main/babyproofedmacros.ahk?cache=" A_NowUTC
  try {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.Open("GET", versionUrl, false)
    whr.SetRequestHeader("User-Agent", "BabyproofedMacros/" macroVersion)
    whr.SetRequestHeader("Cache-Control", "no-cache")
    whr.SetTimeouts(3000, 5000, 5000, 10000)
    whr.Send()
    if (whr.Status < 200 || whr.Status >= 300) {
      throw Error("Version request returned HTTP " whr.Status ".")
    }

    if !RegExMatch(whr.ResponseText, 'global macroVersion := "([\d\.]+)"', &match) {
      throw Error("Latest version could not be parsed.")
    }
    latestVersion := match[1]
    return JsonStringify(Map(
      "ok", 1,
      "compiled", 1,
      "available", (VerCompare(latestVersion, macroVersion) > 0 ? 1 : 0),
      "currentVersion", macroVersion,
      "latestVersion", latestVersion
    ))
  } catch as err {
    ErrorLogger.Log("update_check", FormatErrorDetails(err))
    return JsonStringify(Map("ok", 0, "compiled", 1, "available", 0, "currentVersion", macroVersion, "error", err.Message))
  }
}

DownloadAndInstallUpdate() {
  if (!A_IsCompiled) {
    throw Error("Updates are only available from a compiled executable.")
  }

  updateUrl := "https://github.com/cryleak/BabyproofedMacros/raw/refs/heads/main/babyproofedmacros.exe"
  SplitPath(A_ScriptFullPath, &currentExeName, &currentExeDir)
  if (currentExeName = "" || currentExeDir = "") {
    throw Error("Could not determine the current executable path.")
  }

  downloadPath := currentExeDir "\.babyproofedmacros-update-" A_TickCount ".exe"
  if FileExist(downloadPath) {
    FileDelete(downloadPath)
  }

  Download(updateUrl, downloadPath)
  if (!FileExist(downloadPath) || FileGetSize(downloadPath) < 100000) {
    try FileDelete(downloadPath)
    throw Error("The downloaded update was incomplete.")
  }
  signature := FileRead(downloadPath, "RAW")
  if (signature.Size < 2 || NumGet(signature, 0, "UChar") != 0x4D || NumGet(signature, 1, "UChar") != 0x5A) {
    try FileDelete(downloadPath)
    throw Error("The downloaded file was not a valid Windows executable.")
  }

  helperPath := A_Temp "\BabyproofedMacrosUpdate-" A_TickCount ".ps1"
  currentPid := DllCall("GetCurrentProcessId")
  helperScript := "$ErrorActionPreference = 'Stop'`r`n"
  helperScript .= "$targetPid = " currentPid "`r`n"
  helperScript .= "$source = '" PowerShellLiteral(downloadPath) "'`r`n"
  helperScript .= "$target = '" PowerShellLiteral(A_ScriptFullPath) "'`r`n"
  helperScript .= "$helper = '" PowerShellLiteral(helperPath) "'`r`n"
  helperScript .= "for ($i = 0; $i -lt 160; $i++) {`r`n"
  helperScript .= "  if (-not (Get-Process -Id $targetPid -ErrorAction SilentlyContinue)) { break }`r`n"
  helperScript .= "  Start-Sleep -Milliseconds 250`r`n"
  helperScript .= "}`r`n"
  helperScript .= "for ($i = 0; $i -lt 120; $i++) {`r`n"
  helperScript .= "  try {`r`n"
  helperScript .= "    Move-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop`r`n"
  helperScript .= "    Start-Process -FilePath $target`r`n"
  helperScript .= "    Remove-Item -LiteralPath $helper -Force -ErrorAction SilentlyContinue`r`n"
  helperScript .= "    exit 0`r`n"
  helperScript .= "  } catch {`r`n"
  helperScript .= "    Start-Sleep -Milliseconds 250`r`n"
  helperScript .= "  }`r`n"
  helperScript .= "}`r`n"

  helperFile := FileOpen(helperPath, "w", "UTF-8")
  try {
    helperFile.Write(helperScript)
  } finally {
    helperFile.Close()
  }

  powershellPath := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
  if !FileExist(powershellPath) {
    powershellPath := "powershell.exe"
  }
  Run('"' powershellPath '" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' helperPath '"', , "Hide")
  SetTimer(() => ExitApp(), -300)
  return JsonStringify(Map("ok", 1))
}

PowerShellLiteral(value) {
  return StrReplace(value, "'", "''")
}

; Waits exactly 1 frame thanks to the keyboard hook in GTA
frameSleep(amount) {
  loop amount {
    Send("{Blind}{f24 up}")
  }
  return 0
}

; Uses a combination of the scroll wheel and the arrow keys to scroll faster, you can scroll twice in 2 frames with this instead of 4.
scrollInDirection(direction, amount, extraInput := "") {
  doExtraInput := () { ; Send an extra input if provided by the caller
    if (extraInput != "") {
      SendInput(extraInput)
      extraInput := ""
    }
    return 0
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
    return 0
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
  return 0
}

accurateSleep(ms) {
  ; DllCall("Sleep", "UInt", ms)

  ; lets you sleep in 0.5ms intervals instead of 1ms
  if (!IsSet(hTimer)) {
    static hTimer := DllCall("CreateWaitableTimer", "Ptr", 0, "Int", 0, "Ptr", 0, "Ptr")
  }
  dueTime := Buffer(8, 0)
  NumPut("Int64", -(ms * 10000), dueTime, 0)

  if (!DllCall("SetWaitableTimer", "Ptr", hTimer, "Ptr", dueTime, "Int", 0, "Ptr", 0, "Ptr", 0, "Int", 0)) {
    throw Error("Failed to set waitable timer for some reason")
    ExitApp()
  }

  DllCall("WaitForSingleObject", "Ptr", hTimer, "UInt", 0xFFFFFFFF)
  return 0
}

retrieveSetting(settingName, ignoreErrors := false) {
  for tabName in guiTabs {
    for setting in settings[tabName] {
      if (setting.name == settingName) {
        if (setting is HotkeyElement && setting.value == "" && !ignoreErrors) {
          throw UnsetError("Hotkey setting " setting.name " is unbound. Please bind it to the proper key before trying to use a macro that relies on it.")
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
  return 0
}

releaseCursor() {
  DllCall("ClipCursor", "Ptr", 0)
  return 0
}

moveToPixelCoordinates(x, y) {
  coords := getPixelCoordinates(x, y)
  ; MouseMove, % coords.x, % coords.y
  DllCall("SetCursorPos", "Int", coords.x, "Int", coords.y)
  return 0
}

; Get the coordinates on the main screen for a certain x and y from 0 to 1 clamped to the 16:9 HUD screenspace
getPixelCoordinates(x, y) {
  WinGetClientPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_class grcWindow")

  aspect := windowWidth / windowHeight
  targetAspect := 16 / 9

  if (aspect <= targetAspect) {
    contentWidth := windowWidth
    contentHeight := windowHeight
    offsetX := 0
    offsetY := 0
  } else {
    contentHeight := windowHeight
    contentWidth := contentHeight * targetAspect
    offsetX := (windowWidth - contentWidth) / 2
    offsetY := 0
  }

  return {
    x: Round(windowX + offsetX + contentWidth * x),
    y: Round(windowY + offsetY + contentHeight * y)
  }
}

getPixelCoordinatesReverse(pixelX, pixelY) {
  WinGetClientPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_class grcWindow")

  aspect := windowWidth / windowHeight
  targetAspect := 16 / 9

  if (aspect <= targetAspect) {
    contentWidth := windowWidth
    contentHeight := windowHeight
    offsetX := 0
    offsetY := 0
  } else {
    contentHeight := windowHeight
    contentWidth := contentHeight * targetAspect
    offsetX := (windowWidth - contentWidth) / 2
    offsetY := 0
  }

  x := (pixelX - windowX - offsetX) / contentWidth
  y := (pixelY - windowY - offsetY) / contentHeight

  return {
    x: x,
    y: y
  }
}


debugShowMouseCoords() {
  CoordMode("Mouse", "Screen")

  MouseGetPos(&mouseX, &mouseY)
  coords := getPixelCoordinatesReverse(mouseX, mouseY)
  ToolTip("X: " coords.x " Y: " coords.y)
  return 0
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
  return 0
}

isCursorHidden() {
  return A_Cursor == "Unknown"
}

isRunningInExeContainer() {
  return A_IsCompiled
}

; Compensates for fractional pixels and turns a certain amount of degrees
turnDegrees(degrees, applyVerticalDrift := true) {
  static driftAccumulatorX := 0
  static driftAccumulatorY := 0
  static lastTurnTime := 0
  if (stopCounting(lastTurnTime) > 500) { ; The player likely already moved their mouse so we should just reset the drift compensation
    driftAccumulatorX := 0
    driftAccumulatorY := 0
  }
  lastTurnTime := startCounting()

  scalar := GetKeyState("RButton", "P") ? 321.435 / 180 : 263 / 180
  pixelsPerDegree := scalar / (3840 / A_ScreenWidth)

  exactPixelsX := -(degrees * pixelsPerDegree)
  totalPixelsX := exactPixelsX + driftAccumulatorX
  moveX := Round(totalPixelsX)
  driftAccumulatorX := totalPixelsX - moveX

  moveY := 0
  if (applyVerticalDrift) {
    driftRate := 0.032 / (3840 / A_ScreenWidth)
    driftAccumulatorY += driftRate
    if (driftAccumulatorY >= 1.0) {
      moveY := -1
      driftAccumulatorY -= 1
    }
  }

  MouseMove(moveX, moveY, 0)
  return 0
}

smoothTurnDegrees(degrees, durationMs) {
  durationMs := Max(1, Number(durationMs))
  startTime := startCounting()
  previousProgress := 0
  while (previousProgress < 1) {
    progress := Min(stopCounting(startTime) / durationMs, 1)
    easedProgress := progress * progress * (3 - 2 * progress)
    turnDegrees(degrees * (easedProgress - previousProgress), progress >= 1)
    previousProgress := easedProgress
    if (progress < 1) {
      accurateSleep(1)
    }
  }
  return 0
}

ChunkArray(arr, chunkSize) {
  chunks := []

  Loop Ceil(arr.Length / chunkSize) {
    chunk := []
    start := (A_Index - 1) * chunkSize + 1
    end := Min(start + chunkSize - 1, arr.Length)

    Loop end - start + 1
      chunk.Push(arr[start + A_Index - 1])

    chunks.Push(chunk)
  }

  return chunks
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
    return 0
  }

  chunks := ChunkArray(charArray, 30)
  for i, chunk in chunks {
    for char in chunk {
      DllCall("PostMessage", "Ptr", hwnd, "UInt", 0x0102, "Ptr", char, "Ptr", 1)
    }
    if (i < chunks.Length) {
      frameSleep(1)
    }

  }
  return 0
}

shouldPreserveLeftClick() {
  return retrieveSetting(SettingKey.PRESERVE_LEFT_CLICK).value && GetKeyState("LButton", "P")
}

cacheLastMacroExecutionTime() {
  global macroExecutionTime := stopCounting(macroExecutionStart)
  return 0
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
  return 0
}

unpressHorizontalMovementKeys() {
  KeyDisabler.disableKey("a")
  KeyDisabler.disableKey("d")
  SendInput("{Blind}{a up}{d up}")
  return 0
}

repressHorizontalMovementKeys() {
  if (chatOpen) {
    KeyDisabler.enableKey("a")
    KeyDisabler.enableKey("d")
    return 0
  }
  KeyDisabler.enableKey("a")
  KeyDisabler.enableKey("d")
  if (KeyState.getKeyState("a")) {
    SendInput("{Blind}{a down}")
  }
  if (KeyState.getKeyState("d")) {
    SendInput("{Blind}{d down}")
  }
  return 0
}

shouldHandleHorizontalMovementKeys() {
  return retrieveSetting(SettingKey.AUTO_HORIZONTAL).value ; && (stopCounting(lastHorizontalMovementKeyReleaseTime) < 200 || KeyState.getKeyState("a") || KeyState.getKeyState("d"))
}

class SettingKey {
  ; These values are persisted in config.ini and sent over the UI bridge.
  ; Keep them stable when renaming the display text for a setting.
  static SNIPER_RIFLE_KEYBIND := "Sniper rifle keybind"
  static HEAVY_WEAPON_KEYBIND := "Heavy weapon keybind"
  static STICKY_BOMB_KEYBIND := "Sticky bomb keybind"
  static PISTOL_KEYBIND := "Pistol keybind"
  static SHOTGUN_KEYBIND := "Shotgun keybind"
  static RIFLE_KEYBIND := "Rifle keybind"
  static SMG_KEYBIND := "SMG keybind"
  static FISTS_KEYBIND := "Fists keybind"
  static MELEE_WEAPON_KEYBIND := "Melee weapon keybind"
  static INTERACTION_MENU_KEYBIND := "Interaction menu keybind"
  static EWO_ANIMATION_KEYBIND := "EWO Animation keybind"
  static MELEE_PUNCH_KEYBIND := "Melee punch keybind"
  static LOOK_BEHIND_KEYBIND := "Look behind keybind"
  static WEAPON_WHEEL_KEYBIND := "Weapon wheel keybind"
  static CHAT_KEYBIND := "Chat keybind (automatically suspend macros when chat open)"
  static SPRINT_KEYBIND := "Sprint keybind"
  static A_KEYBIND := "a keybind"
  static D_KEYBIND := "d keybind"
  static USE_CURSOR := "Use cursor in interaction menu for slightly faster macros"
  static PRESERVE_LEFT_CLICK := "Preserve left click state"
  static AMMO := "Ammo"
  static EWO := "EWO"
  static EWO_DELAY := "EWO delay (ms) (for cleaner looking ragdoll)"
  static SHOOT_BEFORE_EWO := "Shoot before EWOing"
  static EXPERIMENTAL_EWO := "Use experimental EWO macro (slower and can't be customized)"
  static C4_MODE := "C4 Mode"
  static INSTANT_EWO := "Instant EWO"
  static TOGGLE_CEO := "Toggle CEO"
  static CHAT_SPAM := "Chat Spam"
  static CHAT_SPAM_TEXT := "Chat Spam Text"
  static FAST_RESPAWN := "Fast respawn"
  static QUICK_TURN := "Quick turn keybind"
  static DEGREES_TO_TURN := "Degrees to turn"
  static SMOOTH_TURN_DURATION := "Smooth turn duration (ms)"
  static BST := "BST"
  static PAUSE_MENU_EWO := "Pause menu EWO"
  static SNIPER_TAB_SWITCH := "Sniper rifle tab switch"
  static HEAVY_TAB_SWITCH := "Heavy weapon tab switch"
  static STICKY_BOMB_TAB_SWITCH := "Sticky bomb tab switch"
  static PISTOL_TAB_SWITCH := "Pistol tab switch"
  static SHOTGUN_TAB_SWITCH := "Shotgun tab switch"
  static RIFLE_TAB_SWITCH := "Rifle tab switch"
  static SMG_TAB_SWITCH := "SMG tab switch"
  static FISTS_TAB_SWITCH := "Fists tab switch"
  static MELEE_WEAPON_TAB_SWITCH := "Melee weapon tab switch"
  static RPG_SPAM := "RPG Spam"
  static SNIPER_SPAM := "Sniper Spam"
  static FULLY_AUTOMATED_SPAM := "Use fully automated spam (extremely buggy)"
  static AUTO_LEFT_CLICK := "Automatic left click handling (buggy)"
  static AUTO_HORIZONTAL := "Automatic horizontal key handling (experimental)"
  static QUEUE_DOUBLE_SWITCH := "Queue double switching"
  static AUTOMATED_RPG_SPAM := "Automated RPG Spam (experimental)"
  static DOUBLE_SWITCH := "Double switch"
  static EXPLICIT_RPG_SWITCH := "Explicit RPG Switch"
  static EXPLICIT_HOMING_SWITCH := "Explicit Homing Launcher Switch"
  static EXPLICIT_GRENADE_SWITCH := "Explicit Grenade Launcher Switch"
  static SAFE_HEAVY_SWAP := "Safe heavy weapon swap"
  static MACRO_SPEED_PROFILE := "Enable macro speed profiling (only useful for developers)"
  static TEST_SHIT := "Test shit"
}

class SettingFactory {
  ; Keep this positional order aligned with HotkeyElement.__New. In
  ; particular, the less common invisible/prefix/suffix/runWhenDisabled
  ; arguments must pass through unchanged.
  static Hotkey(name, defaultValue, tab, macroExec := "", invisible := false, hotkeyValueAddendumPre := "", hotkeyValueAddendumPost := "", runWhenDisabled := false, xmlName := "") {
    setting := HotkeyElement(name, defaultValue, tab, macroExec, invisible, hotkeyValueAddendumPre, hotkeyValueAddendumPost, runWhenDisabled)
    if (xmlName != "") {
      setting.setXMLName(xmlName)
    }
    return setting
  }

  static Bool(name, defaultValue, tab, onChange := "", invisible := false) {
    return SettingElement(name, "bool", defaultValue, tab, onChange, invisible)
  }

  static Text(name, defaultValue, tab, onChange := "", invisible := false) {
    return SettingElement(name, "string", defaultValue, tab, onChange, invisible)
  }
}

makeSettings() {
  SettingFactory.Hotkey(SettingKey.SNIPER_RIFLE_KEYBIND, "9", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_SNIPER")
  SettingFactory.Hotkey(SettingKey.HEAVY_WEAPON_KEYBIND, "4", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_HEAVY")
  SettingFactory.Hotkey(SettingKey.STICKY_BOMB_KEYBIND, "5", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_SPECIAL")
  SettingFactory.Hotkey(SettingKey.PISTOL_KEYBIND, "6", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_HANDGUN")
  SettingFactory.Hotkey(SettingKey.SHOTGUN_KEYBIND, "3", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_SHOTGUN")
  SettingFactory.Hotkey(SettingKey.RIFLE_KEYBIND, "8", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_AUTO_RIFLE")
  SettingFactory.Hotkey(SettingKey.SMG_KEYBIND, "7", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_SMG")
  SettingFactory.Hotkey(SettingKey.FISTS_KEYBIND, "1", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_UNARMED")
  SettingFactory.Hotkey(SettingKey.MELEE_WEAPON_KEYBIND, "2", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON_MELEE")
  SettingFactory.Hotkey(SettingKey.INTERACTION_MENU_KEYBIND, "m", tabs.KEYBINDS, , , , , , "INPUT_INTERACTION_MENU")
  SettingFactory.Hotkey(SettingKey.EWO_ANIMATION_KEYBIND, "capslock", tabs.KEYBINDS, , , , , , "INPUT_SPECIAL_ABILITY_PC").Describe("EWO Animation keybind", "Equivalent to the Special Ability keybind.")
  SettingFactory.Hotkey(SettingKey.MELEE_PUNCH_KEYBIND, "r", tabs.KEYBINDS, , , , , , "INPUT_MELEE_ATTACK_LIGHT")
  SettingFactory.Hotkey(SettingKey.LOOK_BEHIND_KEYBIND, "c", tabs.KEYBINDS, , , , , , "INPUT_LOOK_BEHIND")
  SettingFactory.Hotkey(SettingKey.WEAPON_WHEEL_KEYBIND, "tab", tabs.KEYBINDS, , , , , , "INPUT_SELECT_WEAPON")
  SettingFactory.Hotkey(SettingKey.CHAT_KEYBIND, "t", tabs.KEYBINDS, (*) {
    thisKeybind := retrieveSetting(SettingKey.CHAT_KEYBIND).value
    Send(ConfiguredHotkeySendString(thisKeybind))
    global chatOpen := true
    return 0
  }, , , , , "INPUT_MP_TEXT_CHAT_ALL")
  SettingFactory.Hotkey(SettingKey.SPRINT_KEYBIND, "lshift", tabs.KEYBINDS, , , , , , "INPUT_SPRINT")

  ; These are dummy keybinds to force them to go through the KeyState handler instead of having to rely on regular GetKeyState
  SettingFactory.Hotkey(SettingKey.A_KEYBIND, "a", tabs.GENERAL, (*) {
    ; lastHorizontalMovementKeyReleaseTime := startCounting()
    return 0
  }, true, "~", "up")
  SettingFactory.Hotkey(SettingKey.D_KEYBIND, "d", tabs.GENERAL, (*) {
    ; lastHorizontalMovementKeyReleaseTime := startCounting()
    return 0
  }, true, "~", "up")

  SettingFactory.Bool(SettingKey.USE_CURSOR, false, tabs.GENERAL).Describe("Faster interaction menu", "Use the mouse cursor to speed up interaction-menu navigation. Requires a safezone size 1 tick below the maximum to work properly.")
  SettingFactory.Bool(SettingKey.PRESERVE_LEFT_CLICK, true, tabs.ADVANCED).Describe("Preserve left click", "Restore left click after a macro if it was held before execution.")
  SettingFactory.Hotkey(SettingKey.AMMO, "", tabs.GENERAL, (*) {
    shouldUseCursor := retrieveSetting(SettingKey.USE_CURSOR).value
    interactionKey := retrieveSetting(SettingKey.INTERACTION_MENU_KEYBIND).value

    if (shouldUseCursor) {
      lockCursorToPixelCoordinates(0.1175, 0.32075)
    }
    SendInput("{Blind}{lbutton up}{enter down}")
    Send(ConfiguredHotkeySendString(interactionKey))
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
    Send(ConfiguredHotkeySendString(interactionKey))
    if (shouldPreserveLeftClick()) {
      SendInput("{Blind}{lbutton down}")
    }
    accurateSleep(100)
    return 0
  }).Describe("Ammo refill", "Quickly refill your current weapon from the interaction menu.")
  SettingFactory.Hotkey(SettingKey.EWO, "", tabs.GENERAL, (*) {
    c4Mode := retrieveSetting(SettingKey.C4_MODE).value
    if (c4Mode) {
      thisKeybind := retrieveSetting(SettingKey.EWO).value
      while (GetPhysicalKeyState(thisKeybind)) {
        Send("{Blind}{g}")
      }
      return 0
    }
    interactionKey := retrieveSetting(SettingKey.INTERACTION_MENU_KEYBIND).value
    animationKey := retrieveSetting(SettingKey.EWO_ANIMATION_KEYBIND).value
    meleePunchKey := retrieveSetting(SettingKey.MELEE_PUNCH_KEYBIND).value
    lookBehindKey := retrieveSetting(SettingKey.LOOK_BEHIND_KEYBIND).value
    sprintKey := retrieveSetting(SettingKey.SPRINT_KEYBIND).value
    useExperimentalEwo := retrieveSetting(SettingKey.EXPERIMENTAL_EWO).value
    if (useExperimentalEwo) {
      SetMouseDelay(1)
      BlockInput("On")
      Send("{Blind}{lbutton down}")
      SendInput("{Blind}{s up}{" lookBehindKey " down}{enter down}{a up}{" interactionKey " down}{" sprintKey " up}{lshift up}{w up}{rbutton up}{" meleePunchKey " down}{lbutton up}{d up}")
      Send("{Blind}{" interactionKey " up}{up}{up}{" animationKey "}")
      frameSleep(1)
      SendInput("{enter up}")
      cacheLastMacroExecutionTime()
      Send("{" lookBehindKey " Up}{" meleePunchKey " Up}")
      BlockInput("Off")
      SetMouseDelay(-1)
    } else {
      ewoDelay := 0
      try ewoDelay := Number(retrieveSetting(SettingKey.EWO_DELAY).value)
      shouldShoot := retrieveSetting(SettingKey.SHOOT_BEFORE_EWO).value

      shouldSleep := 0
      if (shouldShoot) {
        SendInput("{Blind}{lbutton down}")
        shouldSleep := 1
      }
      if (GetPhysicalKeyState(lookBehindKey)) {
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
      if (ewoDelay > 0) {
        timeDelta := stopCounting(startTime)
        remainingTime := ewoDelay - timeDelta
        if (remainingTime >= 0.5) {
          accurateSleep(Ceil(remainingTime * 2) / 2)
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
    return 0
  }).Describe("EWO", "Run the primary easy-way-out macro.")
  SettingFactory.Text(SettingKey.EWO_DELAY, "0", tabs.ADVANCED).Describe("EWO delay", "Delay the EWO sequence for a cleaner-looking ragdoll.")
  SettingFactory.Bool(SettingKey.SHOOT_BEFORE_EWO, true, tabs.ADVANCED).Describe("Shoot before EWO", "Left click before EWOing. Recommended to enable.")
  SettingFactory.Bool(SettingKey.EXPERIMENTAL_EWO, false, tabs.ADVANCED).Describe("Experimental EWO", "This is just Exility's EWO macro because someone asked me to add it")
  SettingFactory.Bool(SettingKey.C4_MODE, false, tabs.ADVANCED).Describe("C4 mode", "EWO macro presses the keybind to blow up C4 instead of using the Intraction Menu.")
  SettingFactory.Hotkey(SettingKey.INSTANT_EWO, "", tabs.ADVANCED, (*) {
    c4Mode := retrieveSetting(SettingKey.C4_MODE).value
    if (c4Mode) {
      thisKeybind := retrieveSetting(SettingKey.INSTANT_EWO).value
      while (GetPhysicalKeyState(thisKeybind)) {
        Send("{Blind}{g}")
      }
      return 0
    }
    interactionKey := retrieveSetting(SettingKey.INTERACTION_MENU_KEYBIND).value
    animationKey := retrieveSetting(SettingKey.EWO_ANIMATION_KEYBIND).value
    meleePunchKey := retrieveSetting(SettingKey.MELEE_PUNCH_KEYBIND).value
    lookBehindKey := retrieveSetting(SettingKey.LOOK_BEHIND_KEYBIND).value
    sprintKey := retrieveSetting(SettingKey.SPRINT_KEYBIND).value

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
    return 0
  }).Describe("Instant EWO", "Same as the EWO macro, but with 0 EWO Delay.")

  SettingFactory.Hotkey(SettingKey.TOGGLE_CEO, "", tabs.GENERAL, (*) {
    interactionKey := retrieveSetting(SettingKey.INTERACTION_MENU_KEYBIND).value

    SendInput("{Blind}{lbutton up}{enter down}")
    if (inCEO) {
      Send(ConfiguredHotkeySendString(interactionKey))
      Send("{Blind}{enter up}{up down}")
      SendInput("{Blind}{enter down}")
      Send("{Blind}{up up}{enter up}")
    } else {
      Send(ConfiguredHotkeySendString(interactionKey))
      scrollInDirection("Down", 6)
      SendInput("{Blind}{enter up}")
      Send("{Blind}{enter}")
    }
    if (shouldPreserveLeftClick()) {
      SendInput("{Blind}{lbutton down}")
    }
    global inCEO := !inCEO
    return 0
  }).Describe("Toggle CEO mode", "Switch CEO mode on or off while playing. This affects macros since the required inputs can be slightly different depending on if you're in an organization or not.")

  SettingFactory.Hotkey(SettingKey.CHAT_SPAM, "", tabs.GENERAL, (*) {
    chatSpamText := retrieveSetting(SettingKey.CHAT_SPAM_TEXT).value
    thisKeybind := retrieveSetting(SettingKey.CHAT_SPAM).value
    chatKeybind := retrieveSetting(SettingKey.CHAT_KEYBIND).value
    charArray := convertToCharArray(chatSpamText)
    while (GetPhysicalKeyState(thisKeybind)) {
      Send("{Blind}{" chatKeybind " down}{enter down}")
      SendInput("{Blind}{" chatKeybind " up}")
      frameSleep(1)
      SendStringByMessage(charArray)
      Send("{Blind}{enter up}")
    }
    return 0
  }).Describe("Chat spam", "Send the configured chat message repeatedly.")
  SettingFactory.Text(SettingKey.CHAT_SPAM_TEXT, "Ω", tabs.GENERAL).Describe("Chat spam text", "The message used by the chat spam macro.")
  SettingFactory.Hotkey(SettingKey.FAST_RESPAWN, "", tabs.GENERAL, (*) {
    thisKeybind := retrieveSetting(SettingKey.FAST_RESPAWN).value
    while (GetPhysicalKeyState(thisKeybind)) {
      SendInput("{Blind}{lbutton down}")
      frameSleep(1)
      SendInput("{Blind}{lbutton up}")
      frameSleep(1)
    }
    cacheLastMacroExecutionTime()
    return 0
  }).Describe("Fast respawn", "Left clicks 5 billion times so you respawn fast after being killed by another player.")
  SettingFactory.Hotkey(SettingKey.QUICK_TURN, "", tabs.GENERAL, (*) {
    degrees := retrieveSetting(SettingKey.DEGREES_TO_TURN).value
    turnDegrees(degrees)
    return 0
  }).Describe("Quick turn", "Turn your character by the configured number of degrees. Requires raw input method and 0 mouse sensitivity in the game settings.")
  SettingFactory.Text(SettingKey.DEGREES_TO_TURN, "180", tabs.GENERAL).Describe("Turn amount", "How many degrees the quick-turn macro should rotate.")
  SettingFactory.Hotkey(SettingKey.BST, "", tabs.GENERAL, (*) {
    if (!inCEO) {
      if (FileExist(A_ScriptDir . "\communication 1.ahk") && FileExist(A_ScriptDir . "\communication 2.ahk")) {
        Run(A_ScriptDir . "\communication 1.ahk")
        Run(A_ScriptDir . "\communication 2.ahk")
        return 0
      }
      coordinates := getPixelCoordinates(0.5, 0.5)
      ToolTip("You're not in a CEO silly", coordinates.x, coordinates.y)
      SetTimer(() {
        ToolTip()
        return 0
      }, -1000)
      return 0
    }
    interactionMenuKey := retrieveSetting(SettingKey.INTERACTION_MENU_KEYBIND).value

    SendInput("{Blind}{lbutton up}{enter down}")

    Send(ConfiguredHotkeySendString(interactionMenuKey))
    Send("{Blind}{enter up}")
    scrollInDirection("Down", 4, "{Blind}{enter down}")
    SendInput("{Blind}{enter up}")
    frameSleep(1)
    SendInput("{Blind}{WheelDown}{enter down}")
    Send("{Blind}{enter up}")
    if (shouldPreserveLeftClick()) {
      SendInput("{Blind}{lbutton down}")
    }
    cacheLastMacroExecutionTime()
    return 0
  })

  SettingFactory.Hotkey(SettingKey.PAUSE_MENU_EWO, "", tabs.GENERAL, (*) {
    meleePunchKey := retrieveSetting(SettingKey.MELEE_PUNCH_KEYBIND).value
    SendInput("{Blind}{" meleePunchKey " down}")
    Send("{Blind}{p}")
    frameSleep(7)
    Send("{Blind}{right}")
    accurateSleep(440)
    Send("{Blind}{enter}")
    accurateSleep(200)
    Send("{Blind}{up}{WheelUp}{f24 up}{up}{WheelUp}{f24 up}")
    SendInput("{Blind}{enter down}")
    accurateSleep(195)
    SendInput("{Blind}{enter up}")
    frameSleep(3)
    ; My scrollInDirection method uses behavior that I modified specifically for the interaction menu so I can't use it here
    Send("{Blind}{down down}{down up}{WheelDown}{f24 up}{down down}{down up}{WheelDown}{f24 up}{down down}{down up}{WheelDown}{f24 up}{down down}{down up}{WheelDown}{f24 up}{down down}{down up}{WheelDown}{f24 up}{down down}{down up}{WheelDown}{f24 up}{down}")
    frameSleep(1)
    startTime := startCounting()
    while (stopCounting(startTime) < 200) {
      Send("{Blind}{enter}")
    }
  }).Describe("Pause menu EWO", "EWOs via the pause menu. Allows you to EWO while ragdolled. Only works on very high FPS.")

  quickSwitchMethod := (keybind, *) {
    weaponKey := retrieveSetting(keybind).value
    useAutomatedSpam := retrieveSetting(SettingKey.FULLY_AUTOMATED_SPAM).value
    if (useAutomatedSpam && spamManagerInstance.isSpamming()) {
      spamManagerInstance.queueSpam(weaponKey, false)
      return 0
    }
    c4Keybind := retrieveSetting(SettingKey.STICKY_BOMB_KEYBIND).value
    heavyWeaponKey := retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value
    leftClickHandlingSetting := retrieveSetting(SettingKey.AUTO_LEFT_CLICK).value
    shiftKeybind := retrieveSetting(SettingKey.SPRINT_KEYBIND).value
    automaticLButtonHandling := leftClickHandlingSetting && (lastTabSwitchData.weaponKey != c4Keybind || stopCounting(lastTabSwitchData.time) > 390) && weaponKey != c4Keybind && KeyState.getKeyState(shiftKeybind)
    shouldHandleHorizontalMovementKeys := retrieveSetting(SettingKey.AUTO_HORIZONTAL).value && !chatOpen
    weaponWheelKey := retrieveSetting(SettingKey.WEAPON_WHEEL_KEYBIND).value
    if (automaticLButtonHandling && shouldHandleHorizontalMovementKeys) {
      unpressHorizontalMovementKeys()
    }
    if (automaticLButtonHandling) {
      SendInput("{Blind}{lbutton up}")
    }
    Send("{Blind}{" weaponKey " down}{" weaponWheelKey "}")
    SendInput("{Blind}{" weaponKey " up}")
    if (weaponKey == heavyWeaponKey) {
      SendInput("{Blind}{WheelDown}") ; automatic zoom out?
    }
    if (automaticLButtonHandling) {
      SetTimer(() {
        if (GetKeyState("LButton", "P")) {
          SendInput("{Blind}{lbutton down}")
        }
        return 0
      }, -100)
      if (shouldHandleHorizontalMovementKeys) {
        SetTimer(() {
          repressHorizontalMovementKeys()
          return 0
        }, -105)
      }
    }
    cacheLastMacroExecutionTime()
    global lastTabSwitchData := { time: startCounting(), weaponKey: weaponKey }
    return 0
  }
  SettingFactory.Hotkey(SettingKey.SNIPER_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.SNIPER_RIFLE_KEYBIND))
  SettingFactory.Hotkey(SettingKey.HEAVY_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.HEAVY_WEAPON_KEYBIND))
  SettingFactory.Hotkey(SettingKey.STICKY_BOMB_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.STICKY_BOMB_KEYBIND))
  SettingFactory.Hotkey(SettingKey.PISTOL_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.PISTOL_KEYBIND))
  SettingFactory.Hotkey(SettingKey.SHOTGUN_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.SHOTGUN_KEYBIND))
  SettingFactory.Hotkey(SettingKey.RIFLE_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.RIFLE_KEYBIND))
  SettingFactory.Hotkey(SettingKey.SMG_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.SMG_KEYBIND))
  SettingFactory.Hotkey(SettingKey.FISTS_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.FISTS_KEYBIND))
  SettingFactory.Hotkey(SettingKey.MELEE_WEAPON_TAB_SWITCH, "", tabs.WEAPONSWITCH, (*) => quickSwitchMethod(SettingKey.MELEE_WEAPON_KEYBIND))
  SettingFactory.Hotkey(SettingKey.RPG_SPAM, "", tabs.WEAPONSWITCH, (*) {
    heavyWeaponKey := retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value
    stickyBombKey := retrieveSetting(SettingKey.STICKY_BOMB_KEYBIND).value
    weaponWheelKey := retrieveSetting(SettingKey.WEAPON_WHEEL_KEYBIND).value
    Send("{Blind}{" stickyBombKey " down}")
    frameSleep(2)
    Send("{Blind}{" heavyWeaponKey " down}{" weaponWheelKey "}")
    SendInput("{Blind}{" heavyWeaponKey " up}{" stickyBombKey " up}")
    cacheLastMacroExecutionTime()
    return 0
  }).Describe("RPG Spam", "Switches to C4 and back to heavy weapon.")
  SettingFactory.Hotkey(SettingKey.SNIPER_SPAM, "", tabs.WEAPONSWITCH, (*) {
    sniperRifleKey := retrieveSetting(SettingKey.SNIPER_RIFLE_KEYBIND).value
    stickyBombKey := retrieveSetting(SettingKey.STICKY_BOMB_KEYBIND).value
    weaponWheelKey := retrieveSetting(SettingKey.WEAPON_WHEEL_KEYBIND).value
    Send("{Blind}{" stickyBombKey " down}{" sniperRifleKey " down}{" weaponWheelKey "}")
    SendInput("{Blind}{" sniperRifleKey " up}{" stickyBombKey " up}")
    cacheLastMacroExecutionTime()
    return 0
  }).Describe("Sniper Spam", "Switches to C4 and back to sniper rifle.")
  SettingFactory.Bool(SettingKey.FULLY_AUTOMATED_SPAM, false, tabs.ADVANCED, (newValue, oldValue, *) {
    if (oldValue == newValue) {
      return 0
    }
    if (newValue) {
      SetTimer(ObjBindMethod(spamManagerInstance, "runLoop"), 1, -2147483648)
    } else {
      SetTimer(ObjBindMethod(spamManagerInstance, "runLoop"), 0)
    }
    return 0
  })
  SettingFactory.Bool(SettingKey.AUTO_LEFT_CLICK, false, tabs.ADVANCED).Describe("Automatic left click handling", "Automatically handle releasing and pressing of the left mouse button when shift switching.")
  SettingFactory.Bool(SettingKey.AUTO_HORIZONTAL, false, tabs.ADVANCED).Describe("Automatic horizontal key handling", "Automatically handle releasing and pressing of horizontal movement keys when shift switching.")
  SettingFactory.Bool(SettingKey.QUEUE_DOUBLE_SWITCH, false, tabs.ADVANCED).Describe("Queue double switch", "I forgot what this does I think it sucks though")
  SettingFactory.Hotkey(SettingKey.AUTOMATED_RPG_SPAM, "", tabs.ADVANCED).Describe("Automated RPG spam", "I forgot what this does I think it sucks though")
  SettingFactory.Hotkey(SettingKey.DOUBLE_SWITCH, "", tabs.WEAPONSWITCH, (*) {
    heavyWeaponKey := retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value
    useAutomatedSpam := retrieveSetting(SettingKey.FULLY_AUTOMATED_SPAM).value
    if (useAutomatedSpam && spamManagerInstance.isSpamming()) {
      spamManagerInstance.queueSpam(heavyWeaponKey, false, 2)
      return 0
    }
    c4Keybind := retrieveSetting(SettingKey.STICKY_BOMB_KEYBIND).value
    leftClickHandlingSetting := retrieveSetting(SettingKey.AUTO_LEFT_CLICK).value
    sprintKeybind := retrieveSetting(SettingKey.SPRINT_KEYBIND).value
    automaticLButtonHandling := leftClickHandlingSetting && (lastTabSwitchData.weaponKey != c4Keybind || stopCounting(lastTabSwitchData.time) > 390) && heavyWeaponKey != c4Keybind && KeyState.getKeyState(sprintKeybind)
    shouldHandleHorizontalMovementKeys := retrieveSetting(SettingKey.AUTO_HORIZONTAL).value && !chatOpen
    weaponWheelKey := retrieveSetting(SettingKey.WEAPON_WHEEL_KEYBIND).value
    if (automaticLButtonHandling && shouldHandleHorizontalMovementKeys) {
      unpressHorizontalMovementKeys()
    }
    Send(ConfiguredHotkeySendString(heavyWeaponKey))
    Send("{Blind}{" heavyWeaponKey " down}")
    if (automaticLButtonHandling) {
      SendInput("{Blind}{lbutton up}")
    }
    Send(ConfiguredHotkeySendString(weaponWheelKey))
    SendInput("{Blind}{" heavyWeaponKey " up}")

    if (automaticLButtonHandling) {
      SetTimer(() {
        if (GetKeyState("LButton", "P")) {
          SendInput("{Blind}{lbutton down}")
        }
        return 0
      }, -100)
      if (shouldHandleHorizontalMovementKeys) {
        SetTimer(() {
          repressHorizontalMovementKeys()
          return 0
        }, -100)
      }
    }
    cacheLastMacroExecutionTime()
    global lastTabSwitchData := { time: startCounting(), weaponKey: heavyWeaponKey }
    return 0
  }).Describe("Double switch", "Presses your heavy weapon keybind twice. This allows you to switch heavy weapons very fast.")
  explicitSwitchMethod := (weaponKey, pressAmount, *) {
    fistsKey := retrieveSetting(SettingKey.FISTS_KEYBIND).value
    weaponWheelKey := retrieveSetting(SettingKey.WEAPON_WHEEL_KEYBIND).value
    LButtonState := GetKeyState("LButton", "P")
    SendInput("{Blind}{lbutton up}")
    KeyDisabler.disableKey("LButton")
    Send("{Blind}{" fistsKey " down}")
    if (pressAmount > 1) {
      loop pressAmount - 1 {
        Send(ConfiguredHotkeySendString(weaponKey))
      }
    }
    Send("{Blind}{" weaponKey " down}{" weaponWheelKey "}")
    SendInput("{Blind}{" fistsKey " up}{" weaponKey " up}")
    if (LButtonState) {
      SendInput("{Blind}{lbutton down}")
    }
    cacheLastMacroExecutionTime()
    return 0
  }
  SettingFactory.Hotkey(SettingKey.EXPLICIT_RPG_SWITCH, "", tabs.ADVANCED, (*) => explicitSwitchMethod(retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value, 1)).Describe("Explicit RPG switch ", "Guarantees a switch to RPG if your weapon loadout has the RPG in the first slot.")
  SettingFactory.Hotkey(SettingKey.EXPLICIT_HOMING_SWITCH, "", tabs.ADVANCED, (*) => explicitSwitchMethod(retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value, 2)).Describe("Explicit homing switch", "Guarantees a switch to homing launcher if your weapon loadout has the homing launcher in the second slot.")
  SettingFactory.Hotkey(SettingKey.EXPLICIT_GRENADE_SWITCH, "", tabs.ADVANCED, (*) => explicitSwitchMethod(retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value, 3)).Describe("Explicit grenade switch", "Guarantees a switch to grenade launcher if your weapon loadout has the grenade launcher in the third slot.")
  SettingFactory.Hotkey(SettingKey.SAFE_HEAVY_SWAP, "", tabs.ADVANCED, (*) {
    heavyWeaponKey := retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value
    meleeWeaponKey := retrieveSetting(SettingKey.MELEE_WEAPON_KEYBIND).value
    weaponWheelKey := retrieveSetting(SettingKey.WEAPON_WHEEL_KEYBIND).value
    Send("{Blind}{" meleeWeaponKey " down}{" heavyWeaponKey " down}{" weaponWheelKey "}")
    SendInput("{Blind}{" meleeWeaponKey " up}{" heavyWeaponKey " up}")
    cacheLastMacroExecutionTime()
    return 0
  }).Describe("Safe heavy swap", "Prevents your currently held heavy weapon from being reset when you switch to it after respawning. This is slower if you don't have 0 melee weapons in your loadout.")

  SettingFactory.Bool(SettingKey.MACRO_SPEED_PROFILE, false, tabs.ADVANCED, , isRunningInExeContainer() ? true : false).Describe("Macro speed profiling", "Log the execution time of each macro to a file. Only useful for analysis.")
  if (isRunningInExeContainer()) {
    retrieveSetting(SettingKey.MACRO_SPEED_PROFILE).value := false
  }
  SettingFactory.Hotkey(SettingKey.TEST_SHIT, "", tabs.ADVANCED, (*) {
    durationMs := retrieveSetting(SettingKey.SMOOTH_TURN_DURATION).value
    smoothTurnDegrees(180, durationMs)
    return 0
  }, isRunningInExeContainer() ? true : false)
  SettingFactory.Text(SettingKey.SMOOTH_TURN_DURATION, "500", tabs.ADVANCED, , isRunningInExeContainer() ? true : false).Describe("Smooth turn duration", "How long the Test shit smooth 180-degree turn should take, in milliseconds.")
  return 0
}

class SpamManager {
  __New() {
    this.timeUntilSwapAvailable := startCounting()
    this.spamDelay := 550
    this.quickSwitchDelay := 430
    this.customSwaps := []
    this.queuedThisShot := 0
    if (retrieveSetting(SettingKey.FULLY_AUTOMATED_SPAM).value) {
      SetTimer(ObjBindMethod(this, "runLoop"), 1, -2147483648)
    }
  }

  queueSpam(weaponKey, swapToSticky, amount := 1) {
    if (this.customSwaps.Length && this.customSwaps[1].keyPresses <= 1 && this.customSwaps[1].weaponKey == weaponKey && this.customSwaps[1].swapToSticky == swapToSticky && retrieveSetting(SettingKey.QUEUE_DOUBLE_SWITCH).value) {
      this.customSwaps[1].keyPresses += 1
      return 0
    }
    this.lastQueue := startCounting()
    this.customSwaps.Push({ weaponKey: weaponKey, swapToSticky: swapToSticky, keyPresses: amount })
    return 0
  }

  runLoop() {
    if (stopCounting(this.timeUntilSwapAvailable) < 0 || !WinActive("ahk_class grcWindow")) {
      return 0
    }
    stickyBombKey := retrieveSetting(SettingKey.STICKY_BOMB_KEYBIND).value
    heavyWeaponKey := retrieveSetting(SettingKey.HEAVY_WEAPON_KEYBIND).value
    automatedSpamKey := retrieveSetting(SettingKey.AUTOMATED_RPG_SPAM, true).value
    weaponWheelKey := retrieveSetting(SettingKey.WEAPON_WHEEL_KEYBIND).value
    if (!automatedSpamKey) {
      return 0
    }
    shouldHandleLButton := retrieveSetting(SettingKey.AUTO_LEFT_CLICK).value
    if (GetPhysicalKeyState(automatedSpamKey)) {
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
      Send("{Blind}{" action.weaponKey " down}{" weaponWheelKey "}")
      SendInput("{Blind}{" action.weaponKey " up}{" stickyBombKey " up}")
      this.timeUntilSwapAvailable := startCounting() + (action.swapToSticky ? this.spamDelay : this.quickSwitchDelay)
      if (lbuttonState) {
        SendInput("{Blind}{lbutton down}")
        if (action.keyPresses > 1) {
          accurateSleep(50)
        }
      }
      return 0
    } else {
      this.customSwaps := []
    }
    return 0
  }

  isSpamming() {
    keybind := retrieveSetting(SettingKey.AUTOMATED_RPG_SPAM, true).value
    if (!keybind) {
      return false
    }
    return GetPhysicalKeyState(keybind)
  }
}

class KeyDisabler {
  static disabledKeys := []

  static enableAllKeys() {
    for key in this.disabledKeys {
      HotIfWinActive("ahk_class grcWindow")
      Hotkey("*" key, "Off")
      HotIfWinActive()
    }
    this.disabledKeys := []
    return 0
  }

  static disableKey(key) {
    if (this.isKeyDisabled(key)) {
      return 0
    }
    hotkeySetting := settingsManagerInstance.findHotkeyBoundToAKey(key)
    if (!!hotkeySetting) {
      hotkeySetting.disabledByKeyDisabler := true
      hotkeySetting.unregister()
    }

    HotIfWinActive("ahk_class grcWindow")
    Hotkey("*" key, (*) {
      KeyState.setKeyState(key, true)
      if (!!hotkeySetting && hotkeySetting.runWhenDisabled) {
        hotkeySetting.performHotkey()
      }
      return 0
    }, "On")
    Hotkey("*" key " up", (*) {
      KeyState.setKeyState(key, false)
      return 0
    }, "On")
    HotIfWinActive()
    this.disabledKeys.Push({ key: key, hotkeySetting: hotkeySetting })
    return 0
  }

  static enableKey(key) {
    for index, keyObj in this.disabledKeys {
      disabledKey := keyObj.key
      if (disabledKey == key) {
        HotIfWinActive("ahk_class grcWindow")
        Hotkey("*" key, "Off")
        Hotkey("*" key " up", "Off")
        HotIfWinActive()
        this.disabledKeys.RemoveAt(index)
        if (!!keyObj.hotkeySetting) {
          keyObj.hotkeySetting.disabledByKeyDisabler := false
          keyObj.hotkeySetting.register()
        }
        /*
        if (GetKeyState(key, "P")) {
            SendInput("{Blind}{" key " down}")
        }
        */
        return 0
      }
    }
    return 0
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
    return 0
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

class XMLParser {
  __New(xmlString) {
    this.doc := ComObject("MSXML2.DOMDocument.6.0")
    this.doc.async := false
    this.doc.loadXML(xmlString)

    if (this.doc.parseError.errorCode != 0) {
      throw Error("XML Parse Error: " this.doc.parseError.reason)
    }
  }

  GetValueOrDefault(xpath, default := "") {
    try {
      node := this.doc.selectSingleNode(xpath)
      if (node) {
        return node.text
      }
    }
    return default
  }

  GetAttributeOrDefault(xpath, attributeName, default := "") {
    try {
      node := this.doc.selectSingleNode(xpath)
      if (node && node.attributes.getNamedItem(attributeName)) {
        return node.attributes.getNamedItem(attributeName).text
      }
    }
    return default
  }
}
