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
    property var bookmarkModel
    property bool canAdd: false
    property int selectedIndex: -1
    readonly property int count: list.count
    readonly property bool editing: !!list.currentItem && list.currentItem.editing
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal addRequested()
    signal removeRequested(int index)
    signal activateRequested(int index)
    signal renameRequested(int index, string name)
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Bookmarks")

    function timeText(milliseconds) {
        const total = Math.max(0, Math.floor(Number(milliseconds) || 0))
        const pad = (value, digits) => String(value).padStart(digits, "0")
        return pad(Math.floor(total / 3600000), 2) + ":" + pad(Math.floor(total / 60000) % 60, 2)
            + ":" + pad(Math.floor(total / 1000) % 60, 2) + ":" + pad(total % 1000, 3)
    }
    function clearInvalidSelection() {
        if (selectedIndex >= count) selectedIndex = -1
    }
    function removeSelection() {
        if (selectedIndex >= 0 && selectedIndex < count) removeRequested(selectedIndex)
    }
    function renameSelection() { if (list.currentItem) list.currentItem.beginRename() }
    Keys.onDeletePressed: removeSelection()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_F2) { renameSelection(); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            if (count > 0) {
                selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + (event.key === Qt.Key_Up ? -1 : 1)))
                list.positionViewAtIndex(selectedIndex, ListView.Contain)
            }
            event.accepted = true
        } else event.accepted = false
    }
    Connections {
        target: root.bookmarkModel
        ignoreUnknownSignals: true
        function onModelReset() { root.selectedIndex = -1 }
        function onRowsRemoved() { root.selectedIndex = -1 }
    }
    RedesignActionMenu {
        id: actions
        videoBackdropContent: root.videoBackdropContent
        objectName: "bookmarkActionsMenu"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        entries: [{action: "rename", label: qsTr("Rename"), icon: "edit"},
                  {action: "remove", label: qsTr("Remove bookmark"), icon: "remove"}]
        onActionRequested: action => { if (action === "rename") root.renameSelection(); else root.removeSelection() }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: theme.dp(8)
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: theme.dp(28); Layout.rightMargin: theme.dp(14); Layout.topMargin: theme.dp(16)
            spacing: 0
            Text {
                objectName: "bookmarkSummary"; Layout.fillWidth: true
                text: qsTr("%n bookmark", "%n bookmarks", list.count)
                color: theme.foreground; font.pixelSize: theme.dp(14); elide: Text.ElideRight
            }
            RedesignButton {
                objectName: "bookmarkRemoveButton"
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                width: theme.dp(36); iconName: "remove"; text: qsTr("Remove bookmark")
                enabled: root.selectedIndex >= 0 && root.selectedIndex < list.count
                onClicked: root.removeSelection()
            }
            RedesignButton {
                objectName: "bookmarkAddButton"
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                width: theme.dp(36); iconName: "add"; text: qsTr("Bookmark current time")
                enabled: root.canAdd; onClicked: root.addRequested()
            }
        }
        ListView {
            id: list
            objectName: "bookmarkList"
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.leftMargin: theme.dp(20); Layout.rightMargin: theme.dp(24); Layout.bottomMargin: theme.dp(16)
            clip: true; model: root.bookmarkModel; currentIndex: root.selectedIndex
            // Model changes can update count while currentIndex is evaluated.
            onCountChanged: Qt.callLater(root.clearInvalidSelection)
            C.ScrollBar.vertical: C.ScrollBar {}
            delegate: RedesignButton {
                id: row
                required property int index
                required property string name
                required property var timeMS
                property bool editing: false
                objectName: "bookmarkRow" + index
                width: list.width; height: theme.dp(44); padding: 0
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                text: row.name + " " + root.timeText(timeMS)
                selected: root.selectedIndex === index
                Keys.forwardTo: [root]
                onClicked: { row.forceActiveFocus(Qt.MouseFocusReason); root.selectedIndex = index; if (!editing) root.activateRequested(index) }
                function beginRename() {
                    editor.text = row.name; editing = true
                    editor.forceActiveFocus(); editor.selectAll()
                }
                background: Rectangle { radius: theme.dp(4); color: row.selected ? theme.selected : row.hovered ? theme.hover : "transparent"; border.color: row.visualFocus ? theme.accent : "transparent" }
                contentItem: RowLayout {
                    spacing: theme.dp(12)
                    Text { Layout.fillWidth: true; visible: !row.editing; text: row.name; elide: Text.ElideRight; color: theme.foreground; font.pixelSize: theme.dp(14) }
                    C.TextField {
                        id: editor
                        objectName: "bookmarkName" + row.index
                        Layout.fillWidth: true; visible: row.editing
                        color: theme.bright; selectionColor: theme.accent; selectedTextColor: theme.background
                        font.pixelSize: theme.dp(14); selectByMouse: true
                        background: Rectangle { color: theme.field; radius: theme.dp(4); border.color: theme.accent }
                        onAccepted: {
                            if (!text.trim().length) return
                            root.renameRequested(row.index, text.trim()); row.editing = false; row.forceActiveFocus()
                        }
                        Keys.onEscapePressed: { row.editing = false; row.forceActiveFocus() }
                    }
                    Text {
                        objectName: "bookmarkTime" + row.index
                        text: root.timeText(row.timeMS); color: theme.foreground; font.pixelSize: theme.dp(14)
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: event => { root.selectedIndex = row.index; actions.popup(row, event.position) }
                }
            }
            Text {
                anchors.fill: parent; anchors.topMargin: theme.dp(16); visible: list.count === 0
                text: qsTr("Select + to save the current time.")
                color: theme.foreground; font.pixelSize: theme.dp(14); wrapMode: Text.WordWrap
            }
        }
    }
}
