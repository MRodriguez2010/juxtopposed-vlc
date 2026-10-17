// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property bool playing: false
    property bool started: false
    property bool seekable: false
    property bool pausable: true
    property bool hasPrevious: false
    property bool hasNext: false
    property bool hasVideo: false
    property bool previewEnabled: false
    property real position: 0
    property string mediaTitle: ""
    property string folderTitle: ""
    property string artist: ""
    property bool canBrowseMedia: true
    property url previewImage
    property Component thumbnailContent
    property Component videoBackdropContent
    property real previewImagePosition: -1
    property var timeForPosition: function(position) { return "" }
    property bool userMoved: false
    property real draggedX: 0
    property real draggedY: 0
    property real minimumY: theme.dp(46)
    readonly property alias videoArea: videoHost
    readonly property real seekY: seek.y
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal togglePlayback()
    signal previous()
    signal next()
    signal seekRequested(real position)
    signal seekDragStarted()
    signal seekDragFinished(real position, bool commit)
    signal previewRequested(real position)
    signal previewEnded()
    signal openPlayerRequested()
    signal closeRequested()
    signal queueRequested()
    signal folderRequested()
    signal artistRequested()

    implicitWidth: theme.dp(391)
    height: Math.ceil(videoHost.height + theme.dp(130))
    x: userMoved ? draggedX : parent ? parent.width - width - theme.dp(6) : 0
    y: userMoved ? draggedY : parent ? parent.height - height - theme.dp(6) : 0
    color: theme.background; radius: theme.dp(14)
    HoverHandler { id: hover; blocking: false }

    function refreshPreview() { seek.refreshPreview() }
    function constrainPosition() {
        if (!parent || !userMoved) return
        draggedX = Math.max(theme.dp(6), Math.min(draggedX, parent.width - width - theme.dp(6)))
        draggedY = Math.max(minimumY, Math.min(draggedY, parent.height - height - theme.dp(6)))
    }
    onWidthChanged: constrainPosition()
    onHeightChanged: constrainPosition()
    Connections {
        target: root.parent
        function onWidthChanged() { root.constrainPosition() }
        function onHeightChanged() { root.constrainPosition() }
    }
    component MoveHandler: DragHandler {
        target: null
        property real originX: 0
        property real originY: 0
        onActiveChanged: if (active) {
            originX = root.x; originY = root.y
            root.draggedX = originX; root.draggedY = originY
            root.userMoved = true
        }
        onActiveTranslationChanged: if (active) {
            root.draggedX = originX + activeTranslation.x
            root.draggedY = originY + activeTranslation.y
            root.constrainPosition()
        }
    }
    component MiniButton: RedesignButton {
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
    }
    Item {
        id: videoHost
        objectName: "miniPlayerVideoHost"
        x: theme.dp(10); y: theme.dp(10)
        width: parent.width - theme.dp(20); height: width * 9 / 16
        MoveHandler {}
        Rectangle { anchors.fill: parent; z: 3; color: "transparent"; border.color: root.theme.field; border.width: root.theme.dp(2); radius: root.theme.dp(5) }
        Item {
            anchors.fill: parent; z: 4
            HoverHandler { id: videoHover; blocking: false }
            FocusScope {
                id: controlsScope
                anchors.fill: parent
                visible: hover.hovered || videoHover.hovered || activeFocus || seek.activeFocus || folder.activeFocus || artistButton.activeFocus || queueButton.activeFocus
                RowLayout {
                    anchors.top: parent.top; anchors.right: parent.right
                    anchors.margins: root.theme.dp(4); spacing: 0
                    MiniButton { objectName: "miniPlayerExpandButton"; iconName: "expand"; text: qsTr("Open player"); onClicked: root.openPlayerRequested() }
                    MiniButton { objectName: "miniPlayerCloseButton"; iconName: "close"; text: qsTr("Hide mini player"); onClicked: root.closeRequested() }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: controls.implicitWidth; height: root.theme.dp(40)
                    radius: root.theme.dp(6); color: root.theme.panel; opacity: 0.9
                }
                RowLayout {
                    id: controls
                    anchors.centerIn: parent; spacing: root.theme.dp(4)
                    MiniButton { objectName: "miniPlayerPreviousButton"; iconName: "previous"; text: qsTr("Previous"); enabled: root.hasPrevious; onClicked: root.previous() }
                    MiniButton { objectName: "miniPlayerPlayButton"; iconName: root.playing ? "pause" : "play"; text: root.playing ? qsTr("Pause") : qsTr("Play"); enabled: !root.started || root.pausable; onClicked: root.togglePlayback() }
                    MiniButton { objectName: "miniPlayerNextButton"; iconName: "next"; text: qsTr("Next"); enabled: root.hasNext; onClicked: root.next() }
                }
            }
        }
    }
    RedesignPlayerSeekBar {
        id: seek
        objectName: "miniPlayerSeekBar"
        x: theme.dp(8); y: videoHost.y + videoHost.height + theme.dp(4)
        width: parent.width - theme.dp(16); height: theme.dp(16)
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        enabled: root.seekable
        mediaStarted: root.started; playerPosition: root.position
        previewEnabled: root.previewEnabled && root.hasVideo && root.started
        thumbnailContent: root.thumbnailContent
        videoBackdropContent: root.videoBackdropContent
        previewImage: root.previewImage; previewImagePosition: root.previewImagePosition
        timeForPosition: root.timeForPosition
        onSeekRequested: position => root.seekRequested(position)
        onDragStarted: root.seekDragStarted()
        onDragFinished: (position, commit) => root.seekDragFinished(position, commit)
        onPreviewRequested: position => root.previewRequested(position)
        onPreviewEnded: root.previewEnded()
    }
    Text {
        objectName: "miniPlayerTitle"
        x: theme.dp(16); y: videoHost.height + theme.dp(54)
        width: parent.width - theme.dp(32)
        text: root.mediaTitle; elide: Text.ElideRight
        color: theme.foreground; font.pixelSize: theme.dp(16)
        MoveHandler {}
    }
    RowLayout {
        x: theme.dp(8); y: videoHost.height + theme.dp(92)
        width: parent.width - theme.dp(16); height: theme.dp(36)
        spacing: 0
        MiniButton {
            id: folder
            objectName: "miniPlayerFolderButton"
            text: qsTr("Open media folder"); enabled: root.canBrowseMedia && root.folderTitle.length > 0
            Layout.fillWidth: true; Layout.preferredWidth: 1
            onClicked: root.folderRequested()
            contentItem: RowLayout {
                spacing: root.theme.dp(6)
                RedesignIcon { sourceSize: Qt.size(root.theme.dp(24) * Screen.devicePixelRatio, root.theme.dp(24) * Screen.devicePixelRatio); Layout.preferredWidth: root.theme.dp(24); Layout.preferredHeight: root.theme.dp(24); name: "folder"; color: root.theme.foreground }
                Text { Layout.fillWidth: true; text: root.folderTitle; elide: Text.ElideRight; color: root.theme.foreground; font.pixelSize: root.theme.dp(14) }
            }
        }
        MiniButton {
            id: artistButton
            objectName: "miniPlayerArtistButton"
            text: qsTr("Find artist"); visible: root.artist.length > 0
            enabled: root.canBrowseMedia
            Layout.fillWidth: true; Layout.preferredWidth: 1
            onClicked: root.artistRequested()
            contentItem: RowLayout {
                spacing: root.theme.dp(6)
                RedesignIcon { sourceSize: Qt.size(root.theme.dp(24) * Screen.devicePixelRatio, root.theme.dp(24) * Screen.devicePixelRatio); Layout.preferredWidth: root.theme.dp(24); Layout.preferredHeight: root.theme.dp(24); name: "artist"; color: root.theme.foreground }
                Text { Layout.fillWidth: true; text: root.artist; elide: Text.ElideRight; color: root.theme.foreground; font.pixelSize: root.theme.dp(14) }
            }
        }
        MiniButton { id: queueButton; objectName: "miniPlayerQueueButton"; iconName: "queue"; text: qsTr("Play queue"); onClicked: root.queueRequested() }
    }
}
