// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls.Basic as C

C.Popup {
    id: root
    popupType: C.Popup.Item
    property real scaleFactor: 1
    property bool lightTheme: false
    property color accentColor: "#d37918"
    property Component videoBackdropContent
    readonly property RedesignTheme theme: RedesignTheme {
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
    }
    signal dismissRequested()
    anchors.centerIn: parent
    width: Math.max(0, Math.min(theme.dp(1048), parent ? parent.width - theme.dp(32) : theme.dp(1048)))
    height: Math.max(0, Math.min(theme.dp(865), parent ? parent.height - theme.dp(32) : theme.dp(865)))
    padding: 0
    modal: true; dim: false; focus: true
    // The settings store must finish saving before the card can close.
    closePolicy: C.Popup.NoAutoClose
    background: RedesignDialogSurface {
        objectName: "preferencesWindowSurface"
        theme: root.theme
        fill: root.lightTheme ? root.theme.panel : "#0e0e0e"
        videoBackdropContent: root.videoBackdropContent
    }
    contentItem: Item { Keys.onEscapePressed: root.dismissRequested() }
}
