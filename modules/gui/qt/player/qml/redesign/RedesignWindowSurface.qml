// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Rectangle {
    property RedesignTheme theme: RedesignTheme { }
    property bool backdropActive: false
    readonly property color fill: theme.lightTheme ? theme.panel : "#0e0e0e"
    color: Qt.rgba(fill.r, fill.g, fill.b,
                   backdropActive && theme.transparencyEnabled ? theme.floatingOpacity : 1)
    radius: theme.dp(14)
}
