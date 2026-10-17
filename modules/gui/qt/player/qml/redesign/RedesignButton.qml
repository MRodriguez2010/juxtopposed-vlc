// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Basic as C

T.Button {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property string iconName
    property string caption
    property bool leftAligned: false
    property bool accent: false
    property bool selected: false
    property color foreground: theme.foreground
    property color selectedForeground: theme.accent
    property color selectedIconForeground: theme.accent
    property real iconSize: theme.dp(24)
    property real iconReveal: 0
    property var iconDetailColor
    property real captionFontSize: 14
    property real captionSpacing: 6
    property real captionMaximumWidth: Infinity
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }

    implicitWidth: caption.length > 0 ? Math.max(theme.dp(36), contentItem.implicitWidth + theme.dp(16)) : theme.dp(36)
    implicitHeight: theme.dp(36)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    Accessible.role: root.checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.onPressAction: root.click()
    Accessible.onToggleAction: if (root.checkable) root.click()
    RedesignToolTip {
        theme: root.theme
        text: root.text
        visible: root.text.length > 0 && (root.hovered || root.visualFocus)
    }

    background: Rectangle {
        radius: theme.dp(6)
        color: root.accent ? theme.accent : (root.down || root.selected) ? theme.selected : root.hovered ? theme.hover : "transparent"
        border.width: root.visualFocus ? theme.dp(2) : 0
        border.color: theme.accent
        opacity: root.enabled ? 1 : 0.35
    }
    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        Row {
        id: contentRow
        spacing: theme.dp(root.captionSpacing)
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.leftAligned ? undefined : parent.horizontalCenter
        anchors.left: root.leftAligned ? parent.left : undefined
        anchors.leftMargin: theme.dp(12)
        RedesignIcon {
            width: root.iconName ? root.iconSize : 0
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            sidebarReveal: root.iconReveal
            color: root.iconName === "cone" ? theme.accent : root.accent ? "#161616" : root.selected ? root.selectedIconForeground : root.hovered || root.visualFocus ? theme.bright : root.foreground
            detailColor: root.iconDetailColor === undefined ? color : root.iconDetailColor
            opacity: root.enabled ? 1 : 0.35
        }
        Text {
            visible: root.caption.length > 0
            width: Math.min(implicitWidth, root.captionMaximumWidth)
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            text: root.caption
            color: root.iconName === "cone" ? theme.accent : root.accent ? "#161616" : root.selected ? root.selectedForeground : root.foreground
            font.pixelSize: theme.dp(root.captionFontSize)
            opacity: root.enabled ? 1 : 0.35
        }
    }
    }
}
