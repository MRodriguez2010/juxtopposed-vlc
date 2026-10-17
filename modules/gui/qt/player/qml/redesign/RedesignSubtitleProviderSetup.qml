// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

C.Popup {
    id: root
    property real scaleFactor: 1
    property bool lightTheme: false
    property color accentColor: "#d37918"
    property bool hasCustomKey: false
    property bool hasConsumerKey: false
    property bool busy: false
    property string errorMessage: ""
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal saveRequested(string key)
    signal removeRequested()
    signal helpRequested()
    anchors.centerIn: parent
    width: Math.min(theme.dp(560), parent ? parent.width - theme.dp(32) : theme.dp(560))
    padding: theme.dp(20); modal: true; focus: true
    function finish(success, error = "") {
        if (success) close()
        else errorMessage = error || qsTr("VLC could not save this change. Check the key and try again.")
    }
    onOpened: { errorMessage = ""; apiKeyField.forceActiveFocus() }
    onClosed: apiKeyField.text = ""
    background: Rectangle { color: root.theme.panel; radius: root.theme.dp(10); border.color: root.theme.border }
    contentItem: ColumnLayout {
        spacing: root.theme.dp(16)
        Text { Layout.fillWidth: true; text: qsTr("OpenSubtitles setup"); font.pixelSize: root.theme.dp(16); color: root.theme.bright }
        Text {
            Layout.fillWidth: true
            text: root.hasConsumerKey
                ? qsTr("This app can use OpenSubtitles without a personal key. You can add your own application API key here. VLC stores it in your profile.")
                : qsTr("Add your OpenSubtitles application API key. VLC stores it in your profile.")
            wrapMode: Text.WordWrap; font.pixelSize: root.theme.dp(14); color: root.theme.foreground
        }
        C.TextField {
            id: apiKeyField
            objectName: "subtitleProviderApiKey"
            Layout.fillWidth: true; Layout.preferredHeight: root.theme.dp(36)
            echoMode: TextInput.Password; placeholderText: qsTr("API key"); Accessible.name: placeholderText
            color: root.theme.foreground; font.pixelSize: root.theme.dp(14); selectByMouse: true
            enabled: !root.busy
            background: Rectangle { color: root.theme.field; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
            onAccepted: if (text.trim().length) root.saveRequested(text)
        }
        RedesignButton {
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("Get an API key"); text: caption; iconName: "link"; onClicked: root.helpRequested()
        }
        Text { Layout.fillWidth: true; visible: text.length > 0; text: root.errorMessage; wrapMode: Text.WordWrap; font.pixelSize: root.theme.dp(14); color: root.theme.danger }
        RedesignButton {
            objectName: "subtitleProviderRemoveKey"
            visible: root.hasCustomKey; enabled: !root.busy
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: root.hasConsumerKey ? qsTr("Use app key") : qsTr("Remove key"); text: caption
            onClicked: root.removeRequested()
        }
        RowLayout {
            Layout.fillWidth: true
            RedesignButton { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; caption: qsTr("Cancel"); text: caption; onClicked: root.close() }
            Item { Layout.fillWidth: true }
            RedesignButton {
                objectName: "subtitleProviderSaveKey"
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                caption: qsTr("Save"); text: caption; enabled: !root.busy && apiKeyField.text.trim().length > 0
                onClicked: root.saveRequested(apiKeyField.text)
            }
        }
    }
}
