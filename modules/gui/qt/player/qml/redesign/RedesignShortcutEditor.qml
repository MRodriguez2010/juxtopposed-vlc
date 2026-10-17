// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls.Basic as C

C.Popup {
    id: root
    popupType: C.Popup.Item
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property Component videoBackdropContent
    property bool lightTheme: false
    property var shortcuts: []
    property var values: ({})
    property bool dirty: false
    property string errorMessage: ""
    property string recordingName: ""
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    readonly property var filteredRows: {
        const needle = search.text.toLocaleLowerCase()
        return shortcuts.filter(row => !needle ||
            (filter.currentIndex === 0 || filter.currentIndex === 1) && row.title.toLocaleLowerCase().includes(needle) ||
            (filter.currentIndex === 0 || filter.currentIndex === 2) && valueFor(row.name).toLocaleLowerCase().includes(needle) ||
            (filter.currentIndex === 0 || filter.currentIndex === 3) && valueFor(row.globalName).toLocaleLowerCase().includes(needle))
    }
    function valueFor(name) { return String(values[name] || "") }
    function displayValue(name) {
        const value = valueFor(name).split("\t")[0]
        return value.length === 1 ? value.toUpperCase() : value
    }
    signal captureRequested(string name, int key, int modifiers)
    signal clearRequested(string name)
    signal saveRequested()
    signal cancelRequested()
    width: Math.max(0, Math.min(theme.dp(1048), parent ? parent.width - theme.dp(30) : theme.dp(1048)))
    height: Math.max(0, Math.min(theme.dp(800), parent ? parent.height - theme.dp(30) : theme.dp(800)))
    x: parent ? (parent.width - width) / 2 : 0; y: parent ? (parent.height - height) / 2 : 0
    padding: 0
    modal: true; focus: true
    closePolicy: C.Popup.NoAutoClose
    background: RedesignDialogSurface { theme: root.theme; videoBackdropContent: root.videoBackdropContent }
    onAboutToShow: { recordingName = ""; search.clear(); filter.currentIndex = 0 }
    onOpened: if (!recordingName.length) search.forceActiveFocus()

    contentItem: Item {
        Keys.onEscapePressed: root.cancelRequested()
        Rectangle {
            objectName: "shortcutHeader"
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: theme.dp(96); radius: theme.dp(14); color: theme.field
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height / 2; color: parent.color }
        }
        Text {
            x: theme.dp(20); height: theme.dp(50)
            width: parent.width - theme.dp(80)
            text: qsTr("Keyboard Shortcuts"); color: theme.foreground; font.pixelSize: theme.dp(14)
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
        RedesignButton {
            objectName: "shortcutClose"
            anchors.right: parent.right; anchors.rightMargin: theme.dp(7); y: theme.dp(7)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            iconName: "close"; text: qsTr("Close shortcut editor"); onClicked: root.cancelRequested()
        }
        Item {
            x: theme.dp(9); y: theme.dp(53); width: parent.width - theme.dp(18); height: theme.dp(34)
            C.TextField {
                id: search
                objectName: "shortcutSearch"
                width: parent.width - filter.width - theme.dp(10); height: parent.height
                leftPadding: theme.dp(42); rightPadding: theme.dp(10)
                placeholderText: qsTr("Search Keyboard Shortcuts…"); Accessible.name: placeholderText
                color: theme.foreground; placeholderTextColor: root.lightTheme ? theme.foreground : "#404040"
                font.pixelSize: theme.dp(14); selectByMouse: true
                background: Rectangle {
                    radius: theme.dp(6); color: root.lightTheme ? theme.field : "#151515"
                    border.color: search.activeFocus ? theme.accent : "transparent"
                }
                RedesignIcon {
                    x: theme.dp(10); anchors.verticalCenter: parent.verticalCenter
                    width: theme.dp(20); height: width; name: "search"; color: theme.playerLabel
                }
            }
            RedesignComboBox {
                id: filter
                objectName: "shortcutFilter"
                anchors.right: parent.right
                width: Math.min(theme.dp(200), parent.width * 0.35); height: parent.height
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                model: [qsTr("All Fields"), qsTr("Action"), qsTr("Hotkey"), qsTr("Global Hotkey")]
                Accessible.name: qsTr("Search fields")
                background: Rectangle {
                    radius: theme.dp(6); color: root.lightTheme ? theme.field : "#151515"
                    border.color: filter.visualFocus ? theme.accent : "transparent"
                }
            }
        }
        Row {
            objectName: "shortcutColumns"
            x: theme.dp(20); y: theme.dp(120); width: parent.width - theme.dp(40); height: theme.dp(41)
            Text { width: parent.width * .376; text: qsTr("Action"); color: theme.playerLabel; font.pixelSize: theme.dp(14) }
            Text { width: parent.width * .268; horizontalAlignment: Text.AlignHCenter; text: qsTr("Hotkey"); color: theme.playerLabel; font.pixelSize: theme.dp(14) }
            Item { width: parent.width * .088; height: 1 }
            Text { width: parent.width * .268; horizontalAlignment: Text.AlignHCenter; text: qsTr("Global Hotkey"); color: theme.playerLabel; font.pixelSize: theme.dp(14) }
        }
        ListView {
            id: list
            objectName: "shortcutList"
            x: theme.dp(20); y: theme.dp(161); width: parent.width - theme.dp(40)
            height: Math.max(0, parent.height - y - theme.dp(72))
            clip: true; model: root.filteredRows
            C.ScrollBar.vertical: C.ScrollBar { }
            delegate: Item {
                id: row
                objectName: "shortcutRow_" + modelData.name
                required property int index
                required property var modelData
                readonly property bool groupStart: index === 0 || root.filteredRows[index - 1].group !== modelData.group
                readonly property bool groupEnd: index === list.count - 1 || root.filteredRows[index + 1].group !== modelData.group
                width: list.width; height: theme.dp(47 + (groupStart ? 61 : 0) + (groupEnd ? 18 : 0))
                Item {
                    visible: row.groupStart
                    width: parent.width; height: theme.dp(61)
                    Rectangle { width: parent.width; height: theme.dp(1); color: root.lightTheme ? theme.border : "#222222" }
                    Text {
                        y: theme.dp(20); height: theme.dp(30); width: parent.width
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.group; color: theme.playerHeading; font.pixelSize: theme.dp(16)
                        elide: Text.ElideRight
                    }
                }
                Row {
                    y: row.groupStart ? theme.dp(61) : 0
                    width: parent.width; height: theme.dp(47)
                    Text {
                        width: parent.width * .376; height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.title; color: theme.settingsHeading; font.pixelSize: theme.dp(14)
                        elide: Text.ElideRight; rightPadding: theme.dp(16)
                    }
                    Loader {
                        width: parent.width * .268; height: theme.dp(33); y: theme.dp(7)
                        property string actionName: row.modelData.title
                        property string optionName: row.modelData.name
                        sourceComponent: hotkeyCell
                    }
                    Item { width: parent.width * .088; height: 1 }
                    Loader {
                        width: parent.width * .268; height: theme.dp(33); y: theme.dp(7)
                        property string actionName: row.modelData.title
                        property string optionName: row.modelData.globalName
                        sourceComponent: hotkeyCell
                    }
                }
            }
            Text { anchors.centerIn: parent; visible: list.count === 0; text: qsTr("No matching shortcuts"); color: theme.foreground; font.pixelSize: theme.dp(14) }
        }
        RedesignButton {
            objectName: "shortcutCancel"
            x: theme.dp(20); y: parent.height - theme.dp(52); width: theme.dp(100); height: theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("Cancel"); text: caption; onClicked: root.cancelRequested()
            background: Rectangle { radius: theme.dp(6); color: parent.hovered ? theme.hover : theme.background; border.width: parent.visualFocus ? 1 : 0; border.color: theme.accent }
        }
        Text {
            x: theme.dp(136); y: parent.height - theme.dp(52); width: parent.width - theme.dp(272); height: theme.dp(32)
            text: root.errorMessage; color: "#e56b6b"; wrapMode: Text.WordWrap; font.pixelSize: theme.dp(12)
            verticalAlignment: Text.AlignVCenter
        }
        RedesignButton {
            objectName: "shortcutSave"
            anchors.right: parent.right; anchors.rightMargin: theme.dp(20)
            y: parent.height - theme.dp(52); width: theme.dp(100); height: theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("Save"); text: caption; enabled: root.dirty; onClicked: root.saveRequested()
            foreground: theme.accent
            background: Rectangle { radius: theme.dp(6); color: parent.hovered ? theme.selected : theme.progress; border.width: parent.visualFocus ? 1 : 0; border.color: theme.accent }
        }
    }
    Component {
        id: hotkeyCell
        RedesignButton {
            id: cell
            readonly property string optionName: parent.optionName
            readonly property bool recording: root.recordingName === optionName && optionName.length > 0
            objectName: "shortcut_" + optionName
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            enabled: optionName.length > 0
            text: {
                const title = optionName.startsWith("global-") ? qsTr("Record global shortcut for %1").arg(parent.actionName) : qsTr("Record shortcut for %1").arg(parent.actionName)
                const extras = root.valueFor(optionName).split("\t").slice(1)
                return extras.length ? title + "\n" + qsTr("Other bindings: %1").arg(extras.join(", ")) : title
            }
            background: Rectangle { radius: theme.dp(6); color: theme.field; border.width: cell.recording || cell.visualFocus ? 1 : 0; border.color: theme.accent }
            contentItem: Text {
                text: cell.recording ? qsTr("Press a shortcut…") : root.displayValue(cell.optionName)
                color: cell.recording ? theme.accent : theme.settingsHeading; font.pixelSize: theme.dp(14)
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight; leftPadding: theme.dp(26); rightPadding: theme.dp(26)
            }
            RedesignIcon { anchors.right: parent.right; anchors.rightMargin: theme.dp(5); anchors.verticalCenter: parent.verticalCenter; width: theme.dp(24); height: width; name: "edit"; color: root.lightTheme ? theme.foreground : "#404040"; visible: !clear.visible }
            RedesignButton {
                id: clear
                objectName: "shortcutClear"
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: theme.dp(26); height: theme.dp(28)
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                iconName: "close"; iconSize: theme.dp(14); text: qsTr("Clear all shortcuts for this action")
                visible: cell.hovered && root.valueFor(cell.optionName).length > 0
                onClicked: { root.recordingName = ""; root.clearRequested(cell.optionName) }
            }
            onClicked: { root.recordingName = optionName; forceActiveFocus() }
            Keys.onShortcutOverride: event => { event.accepted = cell.recording }
            Keys.onPressed: event => {
                if (!recording) { event.accepted = false; return }
                event.accepted = true
                if (event.key === Qt.Key_Escape) { root.recordingName = ""; return }
                if (event.isAutoRepeat || [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_AltGr].includes(event.key)) return
                root.captureRequested(optionName, event.key, event.modifiers)
                root.recordingName = ""
            }
        }
    }
}
