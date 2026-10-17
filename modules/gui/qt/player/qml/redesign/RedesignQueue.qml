// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

FocusScope {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property Component videoBackdropContent
    property var queueModel
    property int itemCount: 0
    property int currentIndex: -1
    property int selectedIndex: -1
    property string totalDurationText: ""
    property var sortChoices: []
    property int sortKey: -1
    property bool sortDescending: false
    property bool random: false
    property bool repeating: false
    readonly property int actionIndex: selectedIndex >= 0 && selectedIndex < itemCount ? selectedIndex : currentIndex
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal closeRequested()
    signal addRequested()
    signal saveRequested()
    signal clearRequested()
    signal shuffleRequested()
    signal repeatRequested()
    signal sortRequested(int key, bool descending)
    signal playRequested(int index)
    signal removeRequested(int index)
    // The destination is the insertion point before removal, as in moveItemsPre.
    signal moveRequested(int from, int to)
    signal libraryDropRequested(var source)
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Queue")

    function removeSelection() {
        if (actionIndex >= 0 && actionIndex < itemCount) removeRequested(actionIndex)
    }
    function moveToRow(from, to) {
        if (from < 0 || from >= itemCount || to < 0 || to >= itemCount || from === to) return
        moveRequested(from, to > from ? to + 1 : to)
        selectedIndex = to
    }
    function openActions() { actionsMenu.popup() }
    function runAction(action) {
        if (action === "remove") removeSelection()
        else if (action === "earlier") moveToRow(actionIndex, actionIndex - 1)
        else if (action === "later") moveToRow(actionIndex, actionIndex + 1)
        else if (action === "save" && itemCount > 0) saveRequested()
        else if (action === "clear" && itemCount > 0) clearRequested()
        else if (action === "close") closeRequested()
    }
    function durationText(value) {
        return value && value.valid && value.valid() ? value.formatHMS(0) : ""
    }
    function summaryDuration(value) {
        if (!value || !value.valid || !value.valid()) return ""
        const seconds = value.toSeconds()
        const minutes = Math.floor(seconds / 60)
        if (minutes < 1) return qsTr("%1s").arg(seconds)
        if (minutes < 60) return qsTr("%1m").arg(minutes)
        const hours = Math.floor(minutes / 60)
        return minutes % 60 ? qsTr("%1h %2m").arg(hours).arg(minutes % 60) : qsTr("%1h").arg(hours)
    }
    onItemCountChanged: if (selectedIndex >= itemCount) selectedIndex = itemCount - 1
    Keys.onDeletePressed: removeSelection()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier)) {
            openActions(); event.accepted = true
        } else if (event.modifiers & Qt.AltModifier && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            moveToRow(actionIndex, actionIndex + (event.key === Qt.Key_Up ? -1 : 1)); event.accepted = true
        }
    }
    component QueueButton: RedesignButton {
        Keys.forwardTo: [root]
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: theme.dp(28); anchors.rightMargin: theme.dp(12)
        anchors.topMargin: theme.dp(16); anchors.bottomMargin: theme.dp(12)
        spacing: theme.dp(12)
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                objectName: "queueSummary"
                Layout.fillWidth: true
                text: qsTr("%n item", "%n items", root.itemCount) + (root.totalDurationText.length > 0 ? " - " + root.totalDurationText : "")
                elide: Text.ElideRight; color: theme.foreground; font.pixelSize: theme.dp(14)
            }
            QueueButton { objectName: "queueSortButton"; iconName: "sort"; text: qsTr("Sort queue"); enabled: root.itemCount > 1 && root.sortChoices.length > 0; onClicked: sortMenu.popup() }
            QueueButton { objectName: "queueRepeatButton"; iconName: "repeat"; text: qsTr("Repeat"); selected: root.repeating; onClicked: root.repeatRequested() }
            QueueButton { objectName: "queueShuffleButton"; iconName: "shuffle"; text: qsTr("Shuffle"); selected: root.random; onClicked: root.shuffleRequested() }
            QueueButton { objectName: "queueRemoveButton"; iconName: "remove"; text: qsTr("Remove from queue"); enabled: root.actionIndex >= 0 && root.actionIndex < root.itemCount; onClicked: root.removeSelection() }
            QueueButton { objectName: "queueAddButton"; iconName: "add"; text: qsTr("Add files to queue"); onClicked: root.addRequested() }
        }
        ListView {
            id: list
            objectName: "queueList"
            Layout.fillWidth: true; Layout.fillHeight: true
            model: root.queueModel
            clip: true
            C.ScrollBar.vertical: C.ScrollBar {}
            delegate: RowLayout {
                id: row
                required property int index
                required property string title
                required property bool isCurrent
                required property var model
                width: list.width; height: theme.dp(44)
                spacing: theme.dp(8)
                QueueButton {
                    objectName: "queueMoveHandle_" + row.index
                    Layout.preferredWidth: theme.dp(24)
                    iconName: row.isCurrent ? "play" : "drag"
                    foreground: row.isCurrent ? theme.accent : theme.foreground
                    text: qsTr("Move queue item")
                    onClicked: { root.selectedIndex = row.index; root.forceActiveFocus() }
                    DragHandler {
                        id: mover
                        target: null
                        property int originIndex: -1
                        property int destinationIndex: -1
                        onActiveChanged: {
                            if (active) { originIndex = row.index; destinationIndex = originIndex; root.selectedIndex = originIndex }
                            else if (originIndex >= 0) { if (root.visible) root.moveToRow(originIndex, destinationIndex); originIndex = -1 }
                        }
                        onActiveTranslationChanged: if (active) {
                            destinationIndex = Math.max(0, Math.min(root.itemCount - 1, originIndex + Math.round(activeTranslation.y / row.height)))
                        }
                        onCanceled: originIndex = -1
                    }
                }
                QueueButton {
                    objectName: "queueItem_" + row.index
                    Layout.fillWidth: true
                    text: row.title
                    selected: root.selectedIndex === row.index
                    selectedForeground: row.isCurrent ? theme.accent : theme.foreground
                    contentItem: RowLayout {
                        spacing: theme.dp(12)
                        Text { Layout.fillWidth: true; text: row.title; elide: Text.ElideRight; font.pixelSize: theme.dp(14); color: row.isCurrent ? theme.accent : theme.foreground }
                        Text { objectName: "queueDuration_" + row.index; text: root.durationText(row.model.duration); font.pixelSize: theme.dp(14); color: theme.foreground }
                    }
                    onClicked: { root.selectedIndex = row.index; root.playRequested(row.index) }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: { root.selectedIndex = row.index; root.openActions() } }
                }
                Rectangle {
                    parent: list.contentItem
                    x: 0; y: (mover.destinationIndex + (mover.destinationIndex > mover.originIndex ? 1 : 0)) * row.height
                    width: list.width; height: theme.dp(2); color: theme.accent
                    visible: mover.active
                }
            }
            Text {
                anchors.fill: parent; anchors.topMargin: theme.dp(12)
                visible: root.itemCount === 0
                text: qsTr("Drop files here, or add media from your library.")
                wrapMode: Text.WordWrap; color: theme.foreground; font.pixelSize: theme.dp(14)
            }
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.openActions() }
        }
    }
    RedesignActionMenu {
        id: sortMenu
        videoBackdropContent: root.videoBackdropContent
        objectName: "queueSortMenu"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        onAboutToShow: {
            entries = root.sortChoices.map(choice => ({ action: String(choice.criteria), label: choice.text, checked: choice.criteria === root.sortKey }))
                .concat([{ action: "reverse", label: qsTr("Reverse order"), checked: root.sortDescending }])
        }
        onActionRequested: action => {
            if (action === "reverse") {
                if (root.sortChoices.length) root.sortRequested(root.sortChoices.some(choice => choice.criteria === root.sortKey) ? root.sortKey : root.sortChoices[0].criteria, !root.sortDescending)
            } else root.sortRequested(Number(action), root.sortDescending)
        }
    }
    RedesignActionMenu {
        id: actionsMenu
        videoBackdropContent: root.videoBackdropContent
        objectName: "queueActionsMenu"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        onAboutToShow: entries = [
            { action: "earlier", label: qsTr("Move earlier"), enabled: root.actionIndex > 0 },
            { action: "later", label: qsTr("Move later"), enabled: root.actionIndex >= 0 && root.actionIndex < root.itemCount - 1 },
            { action: "remove", label: qsTr("Remove from queue"), icon: "remove", enabled: root.actionIndex >= 0 && root.actionIndex < root.itemCount },
            { action: "save", label: qsTr("Save queue to file"), enabled: root.itemCount > 0 },
            { action: "clear", label: qsTr("Clear queue"), enabled: root.itemCount > 0 },
            { action: "close", label: qsTr("Close queue"), icon: "close" }
        ]
        onActionRequested: action => root.runAction(action)
    }
    DropArea {
        anchors.fill: parent
        keys: ["vlc-redesign-library"]
        onDropped: drop => {
            if (drop.source && drop.source["libraryView"]) {
                root.libraryDropRequested(drop.source)
                drop.acceptProposedAction()
            }
        }
    }
}
