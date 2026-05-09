; from gta source

global RAGE_INPUT_MAP := Map(
    "KEY_BACK", "BackSpace", "KEY_TAB", "Tab",
    "KEY_RETURN", "Enter", "KEY_PAUSE", "Pause",
    "KEY_CAPITAL", "CapsLock", "KEY_ESCAPE", "Esc",
    "KEY_SPACE", "Space", "KEY_PAGEUP", "PgUp",
    "KEY_PRIOR", "PgUp", "KEY_PAGEDOWN", "PgDn",
    "KEY_NEXT", "PgDn", "KEY_END", "End",
    "KEY_HOME", "Home", "KEY_LEFT", "Left",
    "KEY_UP", "Up", "KEY_RIGHT", "Right",
    "KEY_DOWN", "Down", "KEY_SNAPSHOT", "PrintScreen",
    "KEY_SYSRQ", "PrintScreen", "KEY_INSERT", "Insert",
    "KEY_DELETE", "Delete", "KEY_LWIN", "LWin",
    "KEY_RWIN", "RWin", "KEY_APPS", "AppsKey",
    "KEY_0", "0", "KEY_1", "1", "KEY_2", "2", "KEY_3", "3", "KEY_4", "4",
    "KEY_5", "5", "KEY_6", "6", "KEY_7", "7", "KEY_8", "8", "KEY_9", "9",
    "KEY_A", "a", "KEY_B", "b", "KEY_C", "c", "KEY_D", "d", "KEY_E", "e",
    "KEY_F", "f", "KEY_G", "g", "KEY_H", "h", "KEY_I", "i", "KEY_J", "j",
    "KEY_K", "k", "KEY_L", "l", "KEY_M", "m", "KEY_N", "n", "KEY_O", "o",
    "KEY_P", "p", "KEY_Q", "q", "KEY_R", "r", "KEY_S", "s", "KEY_T", "t",
    "KEY_U", "u", "KEY_V", "v", "KEY_W", "w", "KEY_X", "x", "KEY_Y", "y", "KEY_Z", "z",
    "KEY_NUMPAD0", "Numpad0", "KEY_NUMPAD1", "Numpad1",
    "KEY_NUMPAD2", "Numpad2", "KEY_NUMPAD3", "Numpad3",
    "KEY_NUMPAD4", "Numpad4", "KEY_NUMPAD5", "Numpad5",
    "KEY_NUMPAD6", "Numpad6", "KEY_NUMPAD7", "Numpad7",
    "KEY_NUMPAD8", "Numpad8", "KEY_NUMPAD9", "Numpad9",
    "KEY_MULTIPLY", "NumpadMult", "KEY_ADD", "NumpadAdd",
    "KEY_SUBTRACT", "NumpadSub", "KEY_DECIMAL", "NumpadDot",
    "KEY_DIVIDE", "NumpadDiv", "KEY_NUMPADENTER", "NumpadEnter",
    "KEY_F1", "F1", "KEY_F2", "F2", "KEY_F3", "F3", "KEY_F4", "F4",
    "KEY_F5", "F5", "KEY_F6", "F6", "KEY_F7", "F7", "KEY_F8", "F8",
    "KEY_F9", "F9", "KEY_F10", "F10", "KEY_F11", "F11", "KEY_F12", "F12",
    "KEY_F13", "F13", "KEY_F14", "F14", "KEY_F15", "F15", "KEY_F16", "F16",
    "KEY_NUMLOCK", "NumLock", "KEY_SCROLL", "ScrollLock",
    "KEY_LSHIFT", "LShift", "KEY_RSHIFT", "RShift",
    "KEY_LCONTROL", "LCtrl", "KEY_RCONTROL", "RCtrl",
    "KEY_LMENU", "LAlt", "KEY_RMENU", "RAlt",
    "KEY_SEMICOLON", "vkBA", "KEY_PLUS", "vkBB",
    "KEY_COMMA", "vkBC", "KEY_MINUS", "vkBD",
    "KEY_PERIOD", "vkBE", "KEY_SLASH", "vkBF",
    "KEY_GRAVE", "vkC0", "KEY_LBRACKET", "vkDB",
    "KEY_BACKSLASH", "vkDC", "KEY_RBRACKET", "vkDD",
    "KEY_APOSTROPHE", "vkDE",
    "MOUSE_LEFT", "LButton",
    "MOUSE_RIGHT", "RButton",
    "MOUSE_MIDDLE", "MButton",
    "MOUSE_EXTRABTN1", "XButton1",
    "MOUSE_EXTRABTN2", "XButton2",
    "IOM_WHEEL_UP", "WheelUp",
    "IOM_WHEEL_DOWN", "WheelDown"
)

MapRAGEKeyToAHKKey(rageName, default := "Unknown") {
    if RAGE_INPUT_MAP.Has(rageName)
        return RAGE_INPUT_MAP[rageName]
    return default
}
