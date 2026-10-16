// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

RowLayout {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property string label
    property color labelColor: theme.foreground
    property string accessibleName: label
    property bool checked: false
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal toggled(bool checked)
    spacing: theme.dp(12)
    Layout.minimumHeight: theme.dp(52)
    opacity: enabled ? 1 : 0.5
    Text {
        Layout.fillWidth: true
        visible: root.label.length > 0
        text: root.label; color: root.labelColor
        font.pixelSize: theme.dp(14); wrapMode: Text.WordWrap
    }
    T.Button {
        id: toggle
        objectName: "settingSwitch"
        Layout.preferredWidth: theme.dp(64); Layout.preferredHeight: theme.dp(30)
        checkable: true; checked: root.checked
        hoverEnabled: true; focusPolicy: Qt.StrongFocus
        Accessible.name: root.accessibleName
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true; Accessible.checked: checked
        onClicked: root.toggled(checked)
        background: Rectangle {
            radius: root.theme.dp(4); color: toggle.checked ? root.theme.progress : root.theme.field
            border.color: toggle.visualFocus ? root.theme.accent : root.theme.background
        }
        contentItem: Item {
            Rectangle {
                x: toggle.checked ? parent.width - width - root.theme.dp(3) : root.theme.dp(3)
                y: root.theme.dp(3); width: root.theme.dp(26); height: parent.height - root.theme.dp(6)
                radius: root.theme.dp(3); color: toggle.checked ? root.theme.accent : "#444444"
            }
            Text {
                x: toggle.checked ? root.theme.dp(8) : root.theme.dp(34)
                anchors.verticalCenter: parent.verticalCenter
                text: toggle.checked ? qsTr("ON") : qsTr("OFF")
                font.pixelSize: root.theme.dp(12); color: toggle.checked ? root.theme.accent : root.theme.foreground
            }
        }
    }
}
