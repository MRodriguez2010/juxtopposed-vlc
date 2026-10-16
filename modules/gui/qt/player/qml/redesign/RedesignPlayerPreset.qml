// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

Item {
    id: root
    required property var backend
    property real scaleFactor: 1
    property bool lightTheme: false
    property color accentColor: "#d37918"
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    readonly property var presets: { backend.revision; return backend.playerPresets }
    readonly property string selectedId: { backend.revision; return backend.selectedPlayerPreset }
    readonly property string selectedName: {
        const preset = presets.find(row => row.id === selectedId)
        return preset ? preset.name : qsTr("Default Preset")
    }
    property string contextId
    property string contextName
    property string nameAction
    property bool retryNameSave: false
    readonly property var shortcutContext: root.backend.ctx === undefined ? null : root.backend.ctx
    readonly property var controlWindow: root.Window.window
    readonly property var hostWindow: controlWindow && controlWindow.renderWindow !== undefined ? controlWindow.renderWindow : controlWindow
    Binding {
        target: root.shortcutContext; property: "useGlobalShortcuts"; value: false
        when: !!root.shortcutContext && root.visible && root.hostWindow && root.hostWindow.visible
            && (dropdown.visible || actions.visible || nameDialog.visible || deleteDialog.visible)
        restoreMode: Binding.RestoreBindingOrValue
    }
    implicitHeight: theme.dp(42)

    function namePreset(action, id, name) {
        nameAction = action; contextId = id || ""; contextName = name || ""
        retryNameSave = false
        presetName.text = action === "rename" ? contextName : ""
        dropdown.close()
        nameDialog.open()
    }
    function saveName() {
        let success
        if (retryNameSave) success = backend.save()
        else if (nameAction === "rename") success = backend.renamePlayerPreset(contextId, presetName.text)
        else if (nameAction === "duplicate") success = backend.duplicatePlayerPreset(contextId, presetName.text)
        else success = backend.createPlayerPreset(presetName.text)
        retryNameSave = !success && backend.pendingPlayerPreset
        if (success) { retryNameSave = false; nameDialog.close() }
    }
    function activate(row) {
        if (row.action === "create") namePreset("create", "", "")
        else { dropdown.close(); backend.selectPlayerPreset(row.id) }
    }

    RedesignButton {
        id: field
        objectName: "playerPresetSelector"
        anchors.fill: parent
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        text: root.selectedName
        enabled: !root.backend.pendingPlayerPreset
        background: Rectangle { color: root.theme.field; radius: root.theme.dp(6); border.width: field.visualFocus ? 1 : 0; border.color: root.theme.accent }
        contentItem: RowLayout {
            anchors.fill: parent; anchors.leftMargin: root.theme.dp(14); anchors.rightMargin: root.theme.dp(14)
            Text { Layout.fillWidth: true; text: root.selectedName; color: root.theme.foreground; font.pixelSize: root.theme.dp(14); elide: Text.ElideRight }
            RedesignIcon { sourceSize: Qt.size(root.theme.dp(20) * Screen.devicePixelRatio, root.theme.dp(20) * Screen.devicePixelRatio); Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20); name: "chevron-down"; rotation: dropdown.visible ? 0 : 180; color: root.theme.foreground }
        }
        onClicked: dropdown.visible ? dropdown.close() : dropdown.open()
    }
    C.Popup {
        id: dropdown
        objectName: "playerPresetMenu"
        y: -height - root.theme.dp(8)
        width: root.width
        height: Math.min(list.count * root.theme.dp(40) + padding * 2, root.theme.dp(340), root.mapToItem(C.Overlay.overlay, 0, 0).y - root.theme.dp(12))
        padding: root.theme.dp(1)
        focus: true
        background: Rectangle { color: root.lightTheme ? root.theme.background : "#191919"; radius: root.theme.dp(6) }
        onOpened: {
            list.currentIndex = Math.max(0, list.model.findIndex(row => row.id === root.selectedId && row.action !== "create"))
            list.forceActiveFocus()
        }
        contentItem: ListView {
            id: list
            clip: true
            model: [{action: "create", name: qsTr("New Preset"), id: ""}].concat(root.presets).concat([{name: qsTr("Default Preset"), id: ""}])
            keyNavigationEnabled: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home) { currentIndex = 0; event.accepted = true }
                else if (event.key === Qt.Key_End) { currentIndex = count - 1; event.accepted = true }
            }
            Keys.onReturnPressed: root.activate(model[currentIndex])
            Keys.onEnterPressed: root.activate(model[currentIndex])
            Keys.onRightPressed: {
                const row = model[currentIndex]
                if (row.id) openActions(row, currentItem)
            }
            function openActions(row, item) {
                root.contextId = row.id; root.contextName = row.name
                actions.x = width - root.theme.dp(4)
                actions.y = Math.max(0, Math.min(item.y - contentY, height - actions.implicitHeight))
                actions.open()
            }
            delegate: C.ItemDelegate {
                id: row
                required property var modelData
                required property int index
                objectName: modelData.action === "create" ? "playerPresetCreate" : modelData.id ? "playerPreset_" + index : "playerPresetDefault"
                width: list.width; height: root.theme.dp(40)
                leftPadding: root.theme.dp(16); rightPadding: root.theme.dp(18)
                text: modelData.name
                hoverEnabled: true
                highlighted: list.currentIndex === index
                onHoveredChanged: if (hovered) list.currentIndex = index
                onClicked: root.activate(modelData)
                background: Rectangle {
                    x: root.theme.dp(1); y: x
                    width: row.width - 2 * x; height: row.height - 2 * y
                    radius: root.theme.dp(4)
                    color: row.highlighted ? root.lightTheme ? root.theme.hover : "#1f1f1f" : "transparent"
                }
                contentItem: RowLayout {
                    spacing: root.theme.dp(10)
                    Item {
                        Layout.preferredWidth: root.theme.dp(24); Layout.fillHeight: true
                        visible: row.modelData.action === "create" || !!row.modelData.id
                        RedesignButton {
                            anchors.centerIn: parent; width: root.theme.dp(30); height: width
                            visible: !!row.modelData.id
                            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                            iconName: "more"; iconSize: root.theme.dp(20)
                            text: qsTr("Preset actions for %1").arg(row.modelData.name)
                            onClicked: list.openActions(row.modelData, row)
                        }
                        RedesignIcon { anchors.centerIn: parent; width: root.theme.dp(20); height: width; visible: row.modelData.action === "create"; name: "add"; color: root.theme.playerLabel }
                    }
                    Text { Layout.fillWidth: true; text: row.modelData.name; font.pixelSize: root.theme.dp(14); color: row.modelData.action === "create" ? root.theme.playerLabel : root.theme.foreground; elide: Text.ElideRight }
                    RedesignIcon { objectName: "presetSelectionMark" + row.index; sourceSize: Qt.size(root.theme.dp(20) * Screen.devicePixelRatio, root.theme.dp(20) * Screen.devicePixelRatio); Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20); name: "check"; color: root.theme.accent; opacity: row.modelData.action !== "create" && row.modelData.id === root.selectedId ? 1 : 0 }
                }
            }
            C.ScrollIndicator.vertical: C.ScrollIndicator { }
        }
    }
    C.Menu {
        id: actions
        objectName: "playerPresetActions"
        parent: dropdown.contentItem
        focus: true
        onOpened: { currentIndex = 0; itemAt(0).forceActiveFocus() }
        width: root.theme.dp(260); padding: root.theme.dp(4)
        background: Rectangle { color: root.theme.background; radius: root.theme.dp(6); border.color: root.theme.border }
        delegate: C.MenuItem {
            id: actionItem
            implicitHeight: root.theme.dp(48)
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Home && event.key !== Qt.Key_End) return
                actions.currentIndex = event.key === Qt.Key_Home ? 0 : actions.count - 1
                actions.itemAt(actions.currentIndex).forceActiveFocus()
                event.accepted = true
            }
            contentItem: Text { text: actionItem.text; color: root.theme.foreground; font.pixelSize: root.theme.dp(14); verticalAlignment: Text.AlignVCenter; leftPadding: root.theme.dp(44) }
            background: Rectangle { color: actionItem.highlighted ? root.theme.hover : "transparent"; radius: root.theme.dp(4) }
        }
        C.Action { text: qsTr("Rename"); onTriggered: root.namePreset("rename", root.contextId, root.contextName) }
        C.Action { text: qsTr("Duplicate"); onTriggered: root.namePreset("duplicate", root.contextId, root.contextName) }
        C.Action { text: qsTr("Delete"); onTriggered: { dropdown.close(); deleteDialog.open() } }
    }
    C.Popup {
        id: nameDialog
        objectName: "playerPresetNameDialog"
        parent: C.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(root.theme.dp(420), parent.width - root.theme.dp(32))
        padding: root.theme.dp(24)
        modal: true; dim: true; focus: true
        closePolicy: C.Popup.CloseOnEscape
        background: Rectangle { color: root.theme.panel; radius: root.theme.dp(12); border.color: root.theme.border }
        onOpened: { presetName.forceActiveFocus(); presetName.selectAll() }
        onClosed: {
            if (root.retryNameSave) root.backend.cancelPlayerPreset()
            root.retryNameSave = false
        }
        contentItem: ColumnLayout {
            spacing: root.theme.dp(20)
            Text { Layout.fillWidth: true; text: root.nameAction === "rename" ? qsTr("Rename Preset") : root.nameAction === "duplicate" ? qsTr("Duplicate Preset") : qsTr("New Preset"); color: root.theme.bright; font.pixelSize: root.theme.dp(20) }
            C.TextField {
                id: presetName
                objectName: "playerPresetName"
                Layout.fillWidth: true; implicitHeight: root.theme.dp(42)
                maximumLength: 80; readOnly: root.retryNameSave
                placeholderText: qsTr("Preset name"); font.pixelSize: root.theme.dp(14)
                color: root.theme.bright; placeholderTextColor: root.theme.foreground
                selectByMouse: true
                background: Rectangle { color: root.theme.field; radius: root.theme.dp(4); border.color: presetName.activeFocus ? root.theme.accent : root.theme.border }
                onAccepted: root.saveName()
            }
            Text { Layout.fillWidth: true; visible: root.backend.errorMessage.length > 0; text: root.backend.errorMessage; color: root.theme.danger; wrapMode: Text.WordWrap; font.pixelSize: root.theme.dp(13) }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                RedesignButton { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; caption: qsTr("Cancel"); text: caption; onClicked: nameDialog.close() }
                RedesignButton { objectName: "playerPresetNameSave"; scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; caption: root.retryNameSave ? qsTr("Retry") : qsTr("Save"); text: caption; enabled: presetName.text.trim().length > 0; foreground: root.theme.accent; onClicked: root.saveName() }
            }
        }
    }
    RedesignConfirmationDialog {
        id: deleteDialog
        objectName: "playerPresetDeleteDialog"
        parent: C.Overlay.overlay
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        title: qsTr("Delete Preset")
        message: qsTr("Delete “%1”?").arg(root.contextName)
        confirmText: qsTr("Delete"); destructive: true
        onAccepted: root.backend.deletePlayerPreset(root.contextId)
    }
}
