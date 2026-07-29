class ErrorLogger {
    static Log(source, details) {
        try {
            errorsDir := A_ScriptDir "\errors"
            DirCreate(errorsDir)

            static sequence := 0
            sequence += 1
            timestamp := FormatTime(, "yyyyMMdd_HHmmss")
            fileName := timestamp "_" A_TickCount "_" sequence "_" this._SafeName(source) ".txt"
            path := errorsDir "\" fileName
            FileAppend("Source: " source "`nTimestamp: " A_Now "`n`n" details "`n", path, "UTF-8")
        } catch {
            ; Logging must never replace or obscure the original failure.
        }
        return 0
    }

    static _SafeName(value) {
        return RegExReplace(String(value), "[^A-Za-z0-9_-]", "_")
    }
}
