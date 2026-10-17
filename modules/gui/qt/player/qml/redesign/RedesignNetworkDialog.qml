// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

C.Dialog {
    id: root
    popupType: C.Popup.Item
    property real scaleFactor: 1
    property bool lightTheme: false
    property color accentColor: "#d37918"
    property Component videoBackdropContent
    property bool busy: false
    property string errorMessage: ""
    property alias urlsText: urlsField.text
    property alias playlistName: nameField.text
    readonly property var urls: urlsText.split(/\r?\n/).map(line => line.trim()).filter(line => line.length > 0)
    readonly property bool valid: urls.length > 0 && urls.every(url => /^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(url))
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal saveRequested(var urls, string name)

    title: qsTr("Open Network Stream")
    anchors.centerIn: parent
    width: Math.min(theme.dp(1048), parent ? parent.width - theme.dp(32) : theme.dp(1048))
    height: Math.min(theme.dp(630), parent ? parent.height - theme.dp(32) : theme.dp(630))
    padding: 0
    modal: true; dim: true; focus: true
    closePolicy: busy ? C.Popup.NoAutoClose : C.Popup.CloseOnEscape
    background: RedesignDialogSurface { theme: root.theme; videoBackdropContent: root.videoBackdropContent }
    C.Overlay.modal: Rectangle { color: "#80000000" }

    function begin() {
        if (!visible) { urlsText = ""; playlistName = ""; errorMessage = ""; open() }
        urlsField.forceActiveFocus()
    }
    function submit() {
        if (!valid || busy) return
        errorMessage = ""
        busy = true
        saveRequested(urls, playlistName.trim())
    }
    function finish(success) {
        busy = false
        if (success) accept()
        else { errorMessage = qsTr("VLC cannot save these streams. Check the links and try again."); urlsField.forceActiveFocus() }
    }
    onOpened: urlsField.forceActiveFocus()
    onUrlsTextChanged: errorMessage = ""
    Shortcut { sequence: "Ctrl+Return"; enabled: root.visible && root.valid && !root.busy; onActivated: root.submit() }
    Shortcut { sequence: "Ctrl+Enter"; enabled: root.visible && root.valid && !root.busy; onActivated: root.submit() }

    header: Item {
        implicitHeight: root.theme.dp(50)
        Rectangle {
            anchors.fill: parent; radius: root.theme.dp(14); color: root.theme.field
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height / 2; color: parent.color }
        }
        Text {
            anchors.left: parent.left; anchors.leftMargin: root.theme.dp(20); anchors.verticalCenter: parent.verticalCenter
            text: root.title; color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
        }
        RedesignButton {
            objectName: "networkCloseButton"
            anchors.right: parent.right; anchors.rightMargin: root.theme.dp(8); anchors.verticalCenter: parent.verticalCenter
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            iconName: "close"; text: qsTr("Close"); enabled: !root.busy
            onClicked: root.reject()
        }
    }
    contentItem: C.ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth
        C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: root.theme.dp(12)
            Item { Layout.preferredHeight: root.theme.dp(6) }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Network URL"); color: root.theme.bright; font.pixelSize: root.theme.dp(16)
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Enter one link on each line."); color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
                wrapMode: Text.WordWrap
            }
            C.ScrollView {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.topMargin: root.theme.dp(20)
                Layout.preferredHeight: root.theme.dp(190)
                clip: true
                C.TextArea {
                    id: urlsField
                    objectName: "networkUrlsField"
                    placeholderText: qsTr("e.g., https://www.example.com/stream.avi")
                    color: root.theme.bright; placeholderTextColor: root.theme.foreground
                    selectionColor: root.theme.accent; selectedTextColor: root.theme.field
                    font.pixelSize: root.theme.dp(14)
                    padding: root.theme.dp(12)
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true; readOnly: root.busy
                    Accessible.name: qsTr("Network URLs")
                    background: Rectangle { color: root.theme.field; radius: root.theme.dp(4); border.color: urlsField.activeFocus ? root.theme.accent : "transparent" }
                }
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                visible: root.errorMessage.length > 0
                text: root.errorMessage; color: root.theme.danger; font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
                Accessible.role: Accessible.AlertMessage
            }
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.topMargin: root.theme.dp(8); Layout.bottomMargin: root.theme.dp(8)
                implicitHeight: root.theme.dp(1); color: root.theme.border
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Playlist Name (optional)"); color: root.theme.bright; font.pixelSize: root.theme.dp(16)
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Save these links in a playlist with this name."); color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
                wrapMode: Text.WordWrap
            }
            C.TextField {
                id: nameField
                objectName: "networkPlaylistNameField"
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.topMargin: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(32)
                placeholderText: qsTr("e.g., Favorite TV Channels")
                color: root.theme.bright; placeholderTextColor: root.theme.foreground
                selectionColor: root.theme.accent; selectedTextColor: root.theme.field
                font.pixelSize: root.theme.dp(14); leftPadding: root.theme.dp(12)
                readOnly: root.busy; selectByMouse: true
                Accessible.name: qsTr("Playlist name")
                background: Rectangle { color: root.theme.field; radius: root.theme.dp(4); border.color: nameField.activeFocus ? root.theme.accent : "transparent" }
                onAccepted: root.submit()
            }
            Item { Layout.preferredHeight: root.theme.dp(12) }
        }
    }
    footer: Item {
        implicitHeight: root.theme.dp(70)
        RedesignButton {
            objectName: "networkCancelButton"
            x: root.theme.dp(20); anchors.verticalCenter: parent.verticalCenter
            implicitWidth: root.theme.dp(100); implicitHeight: root.theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("Cancel"); text: caption; enabled: !root.busy
            background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.panel; radius: root.theme.dp(6); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
            onClicked: root.reject()
        }
        RedesignButton {
            objectName: "networkSaveButton"
            anchors.right: parent.right; anchors.rightMargin: root.theme.dp(20); anchors.verticalCenter: parent.verticalCenter
            implicitWidth: root.theme.dp(100); implicitHeight: root.theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: root.busy ? qsTr("Saving…") : qsTr("Save"); text: caption
            enabled: root.valid && !root.busy; foreground: root.theme.accent
            background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.progress; radius: root.theme.dp(6); border.color: parent.visualFocus ? root.theme.accent : "transparent"; opacity: parent.enabled ? 1 : .35 }
            onClicked: root.submit()
        }
    }
}
