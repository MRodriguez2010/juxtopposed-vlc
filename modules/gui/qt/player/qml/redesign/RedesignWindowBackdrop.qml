// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window

QtObject {
    id: root
    required property var backend
    required property Window window
    property bool enabled: true
    property rect clipRect
    property real cornerRadius: 14
    property bool darkTheme: true
    property bool applied: false
    readonly property bool active: enabled && !!window && window.visible && applied
    function update() {
        applied = !!window && !!backend && backend.setWindowBackdrop(window,
            enabled && window.visible, clipRect, cornerRadius, darkTheme)
    }
    onWindowChanged: Qt.callLater(update)
    onEnabledChanged: Qt.callLater(update)
    onClipRectChanged: Qt.callLater(update)
    onCornerRadiusChanged: Qt.callLater(update)
    onDarkThemeChanged: Qt.callLater(update)
    Component.onCompleted: Qt.callLater(update)
    Component.onDestruction: if (window && backend && applied)
        backend.setWindowBackdrop(window, false, clipRect, cornerRadius, darkTheme)
    readonly property Connections visibility: Connections {
        target: root.window
        function onVisibleChanged() { Qt.callLater(root.update) }
    }
}
