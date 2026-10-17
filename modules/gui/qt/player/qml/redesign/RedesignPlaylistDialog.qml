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
    property alias playlistName: nameField.text
    property url cover: ""
    readonly property int fileCount: files.count
    readonly property var urls: { filesRevision; return Array.from({length: files.count}, (_, i) => files.get(i).url) }
    property int filesRevision: 0
    readonly property bool valid: playlistName.trim().length > 0
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal filesRequested()
    signal coverRequested()
    signal saveRequested(string name, var urls, url cover)
    title: qsTr("New Playlist")
    anchors.centerIn: parent
    width: Math.min(theme.dp(714), parent ? parent.width - theme.dp(32) : theme.dp(714))
    height: Math.min(theme.dp(590), parent ? parent.height - theme.dp(32) : theme.dp(590))
    padding: 0
    modal: true; dim: true; focus: true
    closePolicy: busy ? C.Popup.NoAutoClose : C.Popup.CloseOnEscape
    background: RedesignDialogSurface { theme: root.theme; videoBackdropContent: root.videoBackdropContent }
    C.Overlay.modal: Rectangle { color: "#80000000" }
    ListModel { id: files }
    function displayName(url) {
        const part = String(url).replace(/\\/g, "/").split("/").pop()
        try { return decodeURIComponent(part) } catch (error) { return part }
    }
    function addFiles(values) {
        if (busy) return
        for (const value of values) {
            const url = String(value)
            if (!/^[a-z][a-z0-9+.-]*:/i.test(url)) continue
            files.append({url: url, name: displayName(url)})
        }
        ++filesRevision
        errorMessage = ""
    }
    function removeFile(index) {
        if (busy || index < 0 || index >= files.count) return
        files.remove(index); ++filesRevision
    }
    function begin() {
        if (!visible) { playlistName = ""; cover = ""; errorMessage = ""; files.clear(); ++filesRevision; open() }
        nameField.forceActiveFocus()
    }
    function submit() {
        if (!valid || busy) return
        errorMessage = ""; busy = true
        saveRequested(playlistName.trim(), urls, cover)
    }
    function finish(success, message) {
        busy = false
        if (success) accept()
        else { errorMessage = message || qsTr("VLC cannot save this playlist. Try again."); nameField.forceActiveFocus() }
    }
    onOpened: nameField.forceActiveFocus()
    onPlaylistNameChanged: errorMessage = ""
    onCoverChanged: errorMessage = ""
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
            objectName: "playlistCloseButton"
            anchors.right: parent.right; anchors.rightMargin: root.theme.dp(8); anchors.verticalCenter: parent.verticalCenter
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            iconName: "close"; text: qsTr("Close"); enabled: !root.busy
            onClicked: root.reject()
        }
    }
    contentItem: C.ScrollView {
        id: scroll
        clip: true; contentWidth: availableWidth
        C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 0
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: root.theme.dp(30)
                Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                spacing: root.theme.dp(24)
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    spacing: root.theme.dp(12)
                    Text { text: qsTr("Playlist Details"); color: root.theme.bright; font.pixelSize: root.theme.dp(16) }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Save the playlist with this name and thumbnail."); color: root.theme.foreground
                        font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
                    }
                    C.TextField {
                        id: nameField
                        objectName: "playlistNameField"
                        Layout.fillWidth: true; Layout.topMargin: root.theme.dp(12); Layout.preferredHeight: root.theme.dp(32)
                        placeholderText: qsTr("e.g., Favorite Videos")
                        color: root.theme.bright; placeholderTextColor: root.theme.foreground
                        selectionColor: root.theme.accent; selectedTextColor: root.theme.field
                        font.pixelSize: root.theme.dp(14); leftPadding: root.theme.dp(12)
                        readOnly: root.busy; selectByMouse: true
                        Accessible.name: qsTr("Playlist name")
                        background: Rectangle { color: root.theme.field; radius: root.theme.dp(4); border.color: nameField.activeFocus ? root.theme.accent : "transparent" }
                        onAccepted: root.submit()
                    }
                }
                Item {
                    Layout.preferredWidth: root.theme.dp(108); Layout.preferredHeight: root.theme.dp(108)
                    Layout.alignment: Qt.AlignTop
                    Rectangle { anchors.fill: parent; radius: root.theme.dp(4); color: root.theme.field }
                    Image {
                        anchors.fill: parent; anchors.margins: root.theme.dp(4)
                        source: root.cover; asynchronous: true; fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(root.theme.dp(216), root.theme.dp(216))
                    }
                    RedesignButton {
                        objectName: "playlistCoverButton"
                        anchors.centerIn: parent
                        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                        iconName: "add"; text: root.cover.toString().length ? qsTr("Change thumbnail") : qsTr("Add thumbnail")
                        enabled: !root.busy
                        background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                        onClicked: root.coverRequested()
                    }
                    RedesignButton {
                        objectName: "playlistRemoveCoverButton"
                        anchors.right: parent.right; anchors.top: parent.top
                        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                        implicitWidth: root.theme.dp(28); implicitHeight: root.theme.dp(28); iconSize: root.theme.dp(18)
                        iconName: "close"; text: qsTr("Remove thumbnail"); visible: root.cover.toString().length > 0; enabled: !root.busy
                        onClicked: root.cover = ""
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.topMargin: root.theme.dp(20); Layout.bottomMargin: root.theme.dp(24)
                implicitHeight: root.theme.dp(1); color: root.theme.border
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                text: qsTr("Select Files"); color: root.theme.bright; font.pixelSize: root.theme.dp(16)
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20); Layout.topMargin: root.theme.dp(12)
                text: qsTr("These files will be added to the playlist."); color: root.theme.foreground
                font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
            }
            Item {
                id: dropBox
                objectName: "playlistDropBox"
                Layout.fillWidth: true; Layout.leftMargin: root.theme.dp(20); Layout.rightMargin: root.theme.dp(20)
                Layout.topMargin: root.theme.dp(18); Layout.preferredHeight: root.theme.dp(184)
                Rectangle { anchors.fill: parent; radius: root.theme.dp(4); color: root.theme.field }
                RedesignSvg {
                    anchors.fill: parent
                    svg: '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height + '"><rect x="1" y="1" width="' + Math.max(0, width - 2) + '" height="' + Math.max(0, height - 2) + '" rx="4" fill="none" stroke="' + (fileDrop.containsDrag ? root.theme.accent : root.theme.border) + '" stroke-width="2" stroke-dasharray="4 4"/></svg>'
                }
                DropArea {
                    id: fileDrop
                    objectName: "playlistFileDropArea"
                    anchors.fill: parent; enabled: !root.busy
                    onEntered: drag => drag.accepted = drag.hasUrls
                    onDropped: drop => { if (drop.hasUrls) { root.addFiles(drop.urls); drop.acceptProposedAction() } }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.busy && files.count === 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.filesRequested()
                }
                Column {
                    anchors.centerIn: parent; width: parent.width - root.theme.dp(32)
                    spacing: root.theme.dp(18); visible: files.count === 0
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Drop files here or select files."); color: root.theme.foreground
                        font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
                    }
                    RedesignButton {
                        objectName: "playlistSelectFilesButton"
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: root.theme.dp(84); implicitHeight: root.theme.dp(32)
                        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                        iconName: "add"; text: qsTr("Select files"); enabled: !root.busy
                        background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                        onClicked: root.filesRequested()
                    }
                }
                ListView {
                    id: fileList
                    objectName: "playlistSelectedFiles"
                    anchors.fill: parent; anchors.margins: root.theme.dp(8); anchors.bottomMargin: root.theme.dp(44)
                    visible: files.count > 0; clip: true
                    model: files
                    C.ScrollBar.vertical: C.ScrollBar { }
                    delegate: RowLayout {
                        required property int index
                        required property string name
                        required property string url
                        width: fileList.width; height: root.theme.dp(36)
                        Text { Layout.fillWidth: true; text: name; elide: Text.ElideRight; color: root.theme.foreground; font.pixelSize: root.theme.dp(14) }
                        RedesignButton {
                            objectName: "playlistRemoveFile" + index
                            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                            iconName: "remove"; text: qsTr("Remove %1").arg(name); enabled: !root.busy
                            onClicked: root.removeFile(index)
                        }
                    }
                }
                RedesignButton {
                    objectName: "playlistAddMoreFilesButton"
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(8)
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    iconName: "add"; caption: qsTr("Add files"); text: caption
                    visible: files.count > 0; enabled: !root.busy
                    onClicked: root.filesRequested()
                }
            }
            Item { Layout.preferredHeight: root.theme.dp(20) }
        }
    }
    footer: Item {
        implicitHeight: root.theme.dp(70) + (errorText.visible ? errorText.implicitHeight + root.theme.dp(12) : 0)
        Text {
            id: errorText
            objectName: "playlistErrorMessage"
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: root.theme.dp(20); anchors.rightMargin: root.theme.dp(20); anchors.topMargin: root.theme.dp(8)
            visible: root.errorMessage.length > 0
            text: root.errorMessage; color: root.theme.danger; font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
            Accessible.role: Accessible.AlertMessage
        }
        RedesignButton {
            objectName: "playlistCancelButton"
            x: root.theme.dp(20); anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(19)
            implicitWidth: root.theme.dp(100); implicitHeight: root.theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("Cancel"); text: caption; enabled: !root.busy
            background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.panel; radius: root.theme.dp(6); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
            onClicked: root.reject()
        }
        RedesignButton {
            objectName: "playlistSaveButton"
            anchors.right: parent.right; anchors.rightMargin: root.theme.dp(20); anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(19)
            implicitWidth: root.theme.dp(100); implicitHeight: root.theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: root.busy ? qsTr("Saving…") : qsTr("Save"); text: caption
            enabled: root.valid && !root.busy; foreground: root.theme.accent
            background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.progress; radius: root.theme.dp(6); border.color: parent.visualFocus ? root.theme.accent : "transparent"; opacity: parent.enabled ? 1 : .35 }
            onClicked: root.submit()
        }
    }
}
