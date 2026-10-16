// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

QtObject {
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    readonly property color background: lightTheme ? "#acacac" : "#1b1b1b"
    readonly property color panel: lightTheme ? "#c3c3c3" : "#0f0f0f"
    readonly property color floatingPanel: lightTheme ? Qt.rgba(195 / 255, 195 / 255, 195 / 255, 0.95) : Qt.rgba(14 / 255, 14 / 255, 14 / 255, 0.95)
    readonly property color field: lightTheme ? "#dedede" : "#090909"
    readonly property color border: lightTheme ? "#969696" : "#292929"
    readonly property color foreground: lightTheme ? "#404040" : "#8f8f8f"
    readonly property color bright: lightTheme ? "#2e2e2e" : "#e5e5e5"
    readonly property color settingsHeading: lightTheme ? bright : "#c6c6c6"
    readonly property color playerHeading: lightTheme ? bright : "#969696"
    readonly property color playerLabel: lightTheme ? foreground : "#6b6b6b"
    readonly property color hover: lightTheme ? "#d5d5d5" : "#292929"
    readonly property color selected: lightTheme ? "#b8b8b8" : "#333333"
    readonly property color accent: accentColor
    readonly property color menuAccent: accentColor.toString() === "#d37918" ? "#ab6314" : Qt.darker(accentColor, 1.23)
    // Keep the original orange palette; other accents use the Figma fill opacity.
    readonly property bool originalAccent: accentColor.toString() === "#d37918"
    readonly property real accentFillOpacity: lightTheme ? 0.35 : accentColor.toString() === "#185dd3" ? 0.30 : 0.24
    readonly property color progress: originalAccent ? lightTheme ? "#d8ba9a" : "#371f06" : tintAccent(field, accentFillOpacity)
    readonly property color subtitleCue: lightTheme ? "#a3a3a3" : "#202020"
    readonly property color subtitleCueProgress: originalAccent ? lightTheme ? "#a27b53" : "#4e3823" : tintAccent(subtitleCue, accentFillOpacity)
    readonly property color danger: "#d33718"
    readonly property color dangerBackground: lightTheme ? "#f8e2d9" : "#1a1111"

    function dp(value: real): real { return value * scaleFactor }
    function tintAccent(background: color, opacity: real): color {
        return Qt.tint(background, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, opacity))
    }
}
