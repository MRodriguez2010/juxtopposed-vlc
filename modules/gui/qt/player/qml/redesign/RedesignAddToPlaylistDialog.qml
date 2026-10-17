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
    property var playlistModel
    property int itemCount: 0
    property bool busy: false
    property string errorMessage: ""
    property string selectedKey: ""
    property alias newName: nameField.text
    property alias filterText: searchField.text
    readonly property bool valid: itemCount > 0 && (selectedKey.length > 0 || newName.trim().length > 0)
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal saveRequested(string key, string name)
    title: qsTr("Add to Playlist")
    anchors.centerIn: parent
    width: Math.min(theme.dp(714), parent ? parent.width - theme.dp(32) : theme.dp(714))
    height: Math.min(theme.dp(590), parent ? parent.height - theme.dp(32) : theme.dp(590))
    padding: 0
    modal: true; dim: true; focus: true
    closePolicy: busy ? C.Popup.NoAutoClose : C.Popup.CloseOnEscape
    background: RedesignDialogSurface { theme: root.theme; videoBackdropContent: root.videoBackdropContent }
    C.Overlay.modal: Rectangle { color: "#80000000" }
    function begin(count) {
        if (visible) return false
        itemCount = count; selectedKey = ""; newName = ""; filterText = ""; errorMessage = ""
        open()
        return true
    }
    function submit() {
        if (!valid || busy) return
        busy = true; errorMessage = ""
        saveRequested(selectedKey, newName.trim())
    }
    function finish(success, message) {
        busy = false
        if (success) accept()
        else errorMessage = message || qsTr("VLC cannot save this selection. Try again.")
    }
    onNewNameChanged: { if (newName.length) selectedKey = ""; errorMessage = "" }
    onFilterTextChanged: { selectedKey = ""; errorMessage = "" }
    onOpened: searchField.forceActiveFocus()
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
            objectName: "addToPlaylistClose"
            anchors.right: parent.right; anchors.rightMargin: root.theme.dp(8); anchors.verticalCenter: parent.verticalCenter
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            iconName: "close"; text: qsTr("Close"); enabled: !root.busy
            onClicked: root.reject()
        }
    }
    contentItem: C.ScrollView {
        id: scroll
        contentWidth: availableWidth; clip: true
        C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth; spacing: root.theme.dp(12)
            Item { Layout.preferredHeight: root.theme.dp(8) }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Choose a Playlist"); color: root.theme.bright; font.pixelSize: root.theme.dp(16)
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Add the selected media to a saved playlist, or create a new playlist.")
                color: root.theme.foreground; font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
            }
            C.TextField {
                id: searchField
                objectName: "addToPlaylistSearch"
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.preferredHeight: root.theme.dp(32)
                enabled: !root.busy; placeholderText: qsTr("Search playlists")
                color: root.theme.bright; placeholderTextColor: root.theme.foreground
                selectionColor: root.theme.accent; selectedTextColor: root.theme.field
                font.pixelSize: root.theme.dp(14); leftPadding: root.theme.dp(12)
                background: Rectangle { color: root.theme.field; radius: root.theme.dp(4); border.color: searchField.activeFocus ? root.theme.accent : "transparent" }
                onAccepted: root.submit()
            }
            ListView {
                id: destinations
                objectName: "playlistDestinations"
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.preferredHeight: root.theme.dp(204)
                clip: true; model: root.playlistModel
                C.ScrollBar.vertical: C.ScrollBar { }
                delegate: C.ItemDelegate {
                    id: destination
                    required property var model
                    required property int index
                    readonly property string key: model.id.toString()
                    objectName: "playlistDestination" + index
                    width: destinations.width; height: root.theme.dp(48)
                    enabled: !root.busy && model.readOnly !== true
                    highlighted: root.selectedKey === key
                    onClicked: { root.newName = ""; root.selectedKey = key; root.errorMessage = "" }
                    background: Rectangle {
                        radius: root.theme.dp(6)
                        color: destination.highlighted ? root.theme.selected : destination.hovered ? root.theme.hover : "transparent"
                        border.color: destination.visualFocus ? root.theme.accent : "transparent"
                    }
                    contentItem: RowLayout {
                        spacing: root.theme.dp(12); opacity: destination.enabled ? 1 : 0.35
                        RedesignLibraryArtwork {
                            Layout.preferredWidth: root.theme.dp(32); Layout.preferredHeight: root.theme.dp(32)
                            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                            source: destination.model.thumbnail || ""; iconName: "playlist"; iconSize: 24; cornerRadius: 2
                        }
                        Text {
                            Layout.fillWidth: true; text: destination.model.name; elide: Text.ElideRight
                            color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
                        }
                        RedesignIcon {
                            Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20)
                            sourceSize: Qt.size(root.theme.dp(20) * Screen.devicePixelRatio, root.theme.dp(20) * Screen.devicePixelRatio)
                            name: "check"; visible: destination.highlighted; color: root.theme.accent
                        }
                        Text {
                            visible: destination.model.readOnly === true
                            text: qsTr("Read only"); color: root.theme.foreground; font.pixelSize: root.theme.dp(12)
                        }
                    }
                }
                Text {
                    anchors.fill: parent; anchors.margins: root.theme.dp(20)
                    visible: destinations.count === 0
                    text: root.filterText.length ? qsTr("No playlists match your search.") : qsTr("VLC has no saved playlists.")
                    color: root.theme.foreground; font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.preferredHeight: root.theme.dp(1); color: root.theme.border
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Or create a new playlist"); color: root.theme.bright; font.pixelSize: root.theme.dp(14)
            }
            C.TextField {
                id: nameField
                objectName: "addToPlaylistName"
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.preferredHeight: root.theme.dp(32)
                enabled: !root.busy; placeholderText: qsTr("Playlist name")
                color: root.theme.bright; placeholderTextColor: root.theme.foreground
                selectionColor: root.theme.accent; selectedTextColor: root.theme.field
                font.pixelSize: root.theme.dp(14); leftPadding: root.theme.dp(12)
                background: Rectangle { color: root.theme.field; radius: root.theme.dp(4); border.color: nameField.activeFocus ? root.theme.accent : "transparent" }
                onAccepted: root.submit()
            }
            Item { Layout.preferredHeight: root.theme.dp(8) }
        }
    }
    footer: Item {
        implicitHeight: root.theme.dp(70) + (errorText.visible ? errorText.implicitHeight + root.theme.dp(12) : 0)
        Text {
            id: errorText
            objectName: "addToPlaylistError"
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: root.theme.dp(20); anchors.rightMargin: root.theme.dp(20); anchors.topMargin: root.theme.dp(8)
            visible: root.errorMessage.length > 0
            text: root.errorMessage; color: root.theme.danger; font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
        }
        RowLayout {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: root.theme.dp(20)
            RedesignButton {
                objectName: "addToPlaylistCancel"
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                implicitHeight: root.theme.dp(32); implicitWidth: root.theme.dp(100)
                caption: qsTr("Cancel"); text: caption; enabled: !root.busy
                background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.panel; radius: root.theme.dp(4) }
                onClicked: root.reject()
            }
            Item { Layout.fillWidth: true }
            RedesignButton {
                objectName: "addToPlaylistSave"
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                implicitHeight: root.theme.dp(32); implicitWidth: root.theme.dp(100)
                caption: root.busy ? qsTr("Saving…") : qsTr("Add"); text: caption; accent: true
                enabled: root.valid && !root.busy
                onClicked: root.submit()
            }
        }
    }
}
