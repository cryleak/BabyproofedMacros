#Include ErrorLogger.ahk
#Include WebView2\WebView2.ahk

global uiInteropLastError := ""

; AutoHotkey 2.1 can report a missing callback return value for GUI event
; callbacks which intentionally only perform side effects. Register this
; before the WebView2 window is created so its first Size event is covered.
OnError(UIInteropErrorHandler, -1)

UIInteropErrorHandler(exception, mode) {
    global uiInteropLastError := FormatErrorDetails(exception, mode)
    ErrorLogger.Log("ahk", uiInteropLastError)
    if (exception.Message = "No value was returned.") {
        return -1
    }
    return 0
}

FormatErrorDetails(exception, mode := "") {
    if (!IsObject(exception)) {
        return "Thrown value: " exception
    }

    details := "Message: " exception.Message
    if (mode != "") {
        details .= "`nMode: " mode
    }

    for property in ["What", "File", "Line", "Extra", "Stack"] {
        try value := exception.%property%
        catch {
            continue
        }
        if (value != "") {
            details .= "`n" property ": " value
        }
    }
    return details
}

class SettingsWebUI {
    __New(manager) {
        this.manager := manager
        this.window := Gui("+Resize +MinSize960x640", "Babyproofed Macros")
        this.window.MarginX := 0
        this.window.MarginY := 0
        this.window.BackColor := "10131D"
        this.window.OnEvent("Close", (*) => ExitApp())
        this.window.OnEvent("Size", (guiObj, minMax, width, height) => this.Resize(width, height))

        this.surface := this.window.Add("Text", "x0 y0 w1120 h760")
        this.window.Show("w1120 h760")

        dataDir := A_AppData "\BabyproofedMacros\WebView2"
        DirCreate(dataDir)
        loaderPath := A_WorkingDir "\lib\WebView2\WebView2Loader.dll"
        runtimePath := A_WorkingDir "\lib\WebView2\FixedVersionRuntime\Microsoft.WebView2.FixedVersionRuntime.150.0.4078.105.x64"
        uiPath := A_WorkingDir "\ui\index.html"
        if !FileExist(loaderPath) {
            throw Error("The WebView2 loader is missing: " loaderPath)
        }
        if !FileExist(uiPath) {
            throw Error("The settings UI files are missing: " uiPath)
        }
        if !FileExist(runtimePath "\msedgewebview2.exe") {
            throw Error("The WebView2 runtime is missing: " runtimePath)
        }

        try {
            this.controller := WebView2.CreateControllerAsync(this.surface.Hwnd, 0, dataDir, runtimePath, loaderPath).await2(15000)
            this.webview := this.controller.CoreWebView2
            this.webview.add_WebMessageReceived(ObjBindMethod(this, "_handleWebMessage"))
            this.webview.AddHostObjectToScript("ahk", SettingsWebBridge(manager))
            ; Install the wrapper's explicit host-object call API before the
            ; document is loaded. Without it, WebView2's raw proxy treats
            ; zero-argument AHK methods as malformed sync requests.
            this.webview.InjectAhkComponent().await2(15000)
            this.webview.Navigate(this._fileUri(uiPath))
        } catch as err {
            this.window.Destroy()
            throw err
        }
    }

    _fileUri(path) {
        uri := "file:///" StrReplace(path, "\", "/")
        uri := StrReplace(uri, " ", "%20")
        uri := StrReplace(uri, "#", "%23")
        return uri
    }

    Resize(width, height) {
        if (width <= 0 || height <= 0) {
            return 0
        }
        this.surface.Move(0, 0, width, height)
        try this.controller.Fill()
        return 0
    }

    Show() {
        this.window.Show()
        return 0
    }

    Hide() {
        this.window.Hide()
        return 0
    }

    IsActive() {
        return WinActive("Babyproofed Macros")
    }

    Execute(script) {
        try this.webview.ExecuteScriptAsync(script)
        catch as err {
            ErrorLogger.Log("ahk_webview_execute", FormatErrorDetails(err))
        }
        return 0
    }

    Send(eventName, payload) {
        this.Execute("window.bpmReceive && window.bpmReceive(" JsonStringify(eventName) "," JsonStringify(payload) ");")
        return 0
    }

    SendState(stateJson) {
        this.Execute("window.bpmReceive && window.bpmReceive('state'," stateJson ");")
        return 0
    }

    Toast(message, kind := "info") {
        this.Send("toast", Map("message", message, "kind", kind))
        return 0
    }

    HotkeyCaptured(name, value) {
        this.Send("hotkeyCaptured", Map("name", name, "value", value))
        return 0
    }

    _handleWebMessage(sender, args) {
        try {
            ErrorLogger.Log("webview_message", args.TryGetWebMessageAsString())
        } catch as err {
            ErrorLogger.Log("webview_message_handler", FormatErrorDetails(err))
        }
        return 0
    }
}

class SettingsWebBridge {
    __New(manager) {
        this.manager := manager
    }

    getState() {
        try return this.manager.GetUiStateJson()
        catch as err {
            ErrorLogger.Log("bridge_getState", FormatErrorDetails(err))
            throw err
        }
    }

    setSetting(name, value) {
        try return this.manager.HandleUiSetting(name, value)
        catch as err {
            ErrorLogger.Log("bridge_setSetting", FormatErrorDetails(err))
            throw err
        }
    }

    saveSettings() {
        try return this.manager.SaveFromUi()
        catch as err {
            ErrorLogger.Log("bridge_saveSettings", FormatErrorDetails(err))
            throw err
        }
    }

    discardSettings() {
        try return this.manager.DiscardFromUi()
        catch as err {
            ErrorLogger.Log("bridge_discardSettings", FormatErrorDetails(err))
            throw err
        }
    }

    checkForUpdate() {
        try return CheckForUpdate()
        catch as err {
            ErrorLogger.Log("bridge_checkForUpdate", FormatErrorDetails(err))
            throw err
        }
    }

    downloadAndInstallUpdate() {
        try return DownloadAndInstallUpdate()
        catch as err {
            ErrorLogger.Log("bridge_downloadAndInstallUpdate", FormatErrorDetails(err))
            throw err
        }
    }

    importGtaKeys() {
        try return this.manager.ImportFromUi()
        catch as err {
            ErrorLogger.Log("bridge_importGtaKeys", FormatErrorDetails(err))
            throw err
        }
    }

    beginHotkeyCapture(name) {
        try return this.manager.BeginHotkeyCapture(name)
        catch as err {
            ErrorLogger.Log("bridge_beginHotkeyCapture", FormatErrorDetails(err))
            throw err
        }
    }

    cancelHotkeyCapture() {
        try return this.manager.CancelHotkeyCapture()
        catch as err {
            ErrorLogger.Log("bridge_cancelHotkeyCapture", FormatErrorDetails(err))
            throw err
        }
    }

    logError(message, context := "") {
        ErrorLogger.Log("webview" (context = "" ? "" : "_" context), message)
        return "ok"
    }

    hideWindow() {
        try {
            this.manager.ui.Hide()
            return "ok"
        } catch as err {
            ErrorLogger.Log("bridge_hideWindow", FormatErrorDetails(err))
            throw err
        }
    }
}

JsonStringify(value) {
    if (value is Map) {
        result := "{"
        first := true
        for key, item in value {
            if (!first) {
                result .= ","
            }
            first := false
            result .= JsonStringify(key) ":" JsonStringify(item)
        }
        return result "}"
    }

    if (value is Array) {
        result := "["
        first := true
        for item in value {
            if (!first) {
                result .= ","
            }
            first := false
            result .= JsonStringify(item)
        }
        return result "]"
    }

    if (value is String) {
        return Chr(34) JsonEscape(value) Chr(34)
    }

    if (value is Integer || value is Float) {
        return value
    }

    if (IsObject(value)) {
        result := "{"
        first := true
        for key in value.OwnProps() {
            if (!first) {
                result .= ","
            }
            first := false
            result .= JsonStringify(key) ":" JsonStringify(value.%key%)
        }
        return result "}"
    }

    return "null"
}

JsonEscape(value) {
    value := StrReplace(value, Chr(92), Chr(92) Chr(92))
    value := StrReplace(value, Chr(34), Chr(92) Chr(34))
    value := StrReplace(value, "`r", Chr(92) "r")
    value := StrReplace(value, "`n", Chr(92) "n")
    value := StrReplace(value, "`t", Chr(92) "t")
    return value
}
