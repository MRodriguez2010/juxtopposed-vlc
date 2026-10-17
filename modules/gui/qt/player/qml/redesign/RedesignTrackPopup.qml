// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

C.Popup {
    id: root
    property Component videoBackdropContent
    // The device list is read once upstream; re-read it so hotplugged outputs show up.
    onAboutToShow: if (root.audioDevices) root.audioDevices.refresh()
    // Cheap: copies the list PipeWire already keeps; refresh() is a no-op when unchanged.
    Timer {
        interval: 2000
        repeat: true
        running: root.opened && root.page === "audio" && !!root.audioDevices
        onTriggered: root.audioDevices.refresh()
    }
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property string page: "subtitles"
    property Item placementArea: parent
    property real bottomLimit: placementArea ? placementArea.height - theme.dp(54) : 0
    property var videoTracks
    property var audioTracks
    property var subtitleTracks
    property bool canAddTracks: true
    property var audioDevices
    readonly property var currentTracks: page === "video" ? videoTracks : page === "audio" ? audioTracks : subtitleTracks
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal preferencesRequested(string page)
    signal selectionRequested(var model, int index, bool selected)
    signal disableRequested(var model)
    signal addTracksRequested(string page)
    signal editTracksRequested(string page)
    width: Math.max(0, Math.min(placementArea.width - theme.dp(40), theme.dp(400)))
    height: Math.max(0, Math.min(placementArea.height - theme.dp(134), theme.dp(524)))
    padding: 0
    margins: theme.dp(20)
    topMargin: theme.dp(60)
    bottomMargin: theme.dp(74)
    focus: true
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutsideParent
    background: Rectangle {
        color: theme.floatingPanel; radius: theme.dp(10)
        Loader {
            anchors.fill: parent
            z: -1
            active: root.visible
            sourceComponent: root.videoBackdropContent
        }
    }
    function toggleFrom(anchor, requestedPage) {
        if (visible && page === requestedPage) { close(); return }
        page = requestedPage
        // Exclude the opening button from outside-click dismissal. Its next
        // click must close this popup, rather than dismiss and reopen it.
        parent = anchor
        const left = Math.max(theme.dp(20), Math.min(anchor.mapToItem(placementArea, 0, 0).x, placementArea.width - width - theme.dp(20)))
        const top = Math.max(theme.dp(60), bottomLimit - height - theme.dp(20))
        const point = placementArea.mapToItem(anchor, left, top)
        x = point.x; y = point.y
        open()
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: theme.dp(50)
            Layout.maximumHeight: theme.dp(50)
            color: theme.field
            radius: theme.dp(10)
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height / 2; color: parent.color }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: theme.dp(14); anchors.rightMargin: theme.dp(14)
                spacing: theme.dp(18)
                Repeater {
                    model: [{key: "video", label: qsTr("Video"), icon: "video"}, {key: "audio", label: qsTr("Audio"), icon: "audio"}, {key: "subtitles", label: qsTr("Subtitles"), icon: "subtitles"}]
                    RedesignButton {
                        required property var modelData
                        objectName: "trackTab_" + modelData.key
                        Layout.fillWidth: true; Layout.fillHeight: true
                        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                        text: modelData.label; caption: root.width > theme.dp(360) ? text : ""; iconName: modelData.icon
                        iconSize: theme.dp(20)
                        foreground: root.page === modelData.key ? root.theme.foreground : Qt.darker(root.theme.foreground, 1.3)
                        onClicked: root.page = modelData.key
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: root.theme.dp(2)
                            color: root.theme.accent
                            visible: root.page === parent.modelData.key
                        }
                    }
                }
            }
        }
        C.ScrollView {
            id: scroll
            objectName: "trackScrollView"
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: scroll.availableWidth
                spacing: 0
                RedesignTracks {
                    objectName: "embeddedTrackChoices"
                    Layout.fillWidth: true
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    heading: qsTr("Embedded Tracks")
                    trackModel: root.currentTracks
                    allowDisable: true
                    trackGroup: 0
                    onSelectionRequested: (index, selected) => root.selectionRequested(trackModel, index, selected)
                    onDisableRequested: root.disableRequested(trackModel)
                }
                RedesignTracks {
                    id: externalChoices
                    objectName: "externalTrackChoices"
                    Layout.fillWidth: true
                    Layout.topMargin: root.theme.dp(16)
                    visible: root.page === "subtitles" || count > 0
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    heading: qsTr("External Tracks"); trackModel: root.currentTracks
                    trackGroup: 1; showEmptyMessage: false
                    editableTracks: root.page !== "video"; canEditTracks: root.canAddTracks
                    onSelectionRequested: (index, selected) => root.selectionRequested(trackModel, index, selected)
                    onEditRequested: { root.close(); root.editTracksRequested(root.page) }
                    onAddRequested: { root.close(); root.addTracksRequested(root.page) }
                }
                Rectangle {
                    visible: root.page === "audio"
                    Layout.fillWidth: true; Layout.preferredHeight: theme.dp(1)
                    Layout.topMargin: theme.dp(12)
                    color: theme.border
                }
                RedesignTracks {
                    objectName: "outputDeviceChoices"
                    Layout.fillWidth: true
                    visible: root.page === "audio"
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    heading: qsTr("Output Device"); trackModel: root.audioDevices
                    refreshable: true
                    onRefreshRequested: if (root.audioDevices) root.audioDevices.refresh()
                    onSelectionRequested: (index, selected) => root.selectionRequested(trackModel, index, selected)
                }

            }
        }
        RedesignButton {
            objectName: "trackPreferencesButton"
            Layout.fillWidth: true
            Layout.preferredHeight: theme.dp(32); Layout.maximumHeight: theme.dp(32)
            Layout.margins: theme.dp(20)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("Show Preferences"); text: caption
            background: Rectangle { color: parent.hovered ? root.theme.hover : root.theme.field; radius: root.theme.dp(4); border.width: parent.visualFocus ? 1 : 0; border.color: root.theme.accent }
            onClicked: { root.close(); root.preferencesRequested(root.page) }
        }
    }
}
