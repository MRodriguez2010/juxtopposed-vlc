// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic as C
import VLC.MainInterface
import VLC.Style
import VLC.Dialogs
import VLC.Player

Window {
    id: root
    title: qsTr("Settings — VLC Media Player")
    width: Math.min(theme.dp(1078), Screen.desktopAvailableWidth - theme.dp(40))
    height: Math.min(theme.dp(895), Screen.desktopAvailableHeight - theme.dp(60))
    minimumWidth: theme.dp(640); minimumHeight: theme.dp(440)
    flags: Qt.Dialog | Qt.FramelessWindowHint
    modality: Qt.ApplicationModal
    transientParent: MainCtx.intfMainWindow
    color: "transparent"
    property real scaleFactor: VLCStyle.scale
    property color accentColor: MainCtx.redesignAccent
    property bool lightTheme: !VLCStyle.palette.isDark
    property string category: "general"
    readonly property string categoryTitle: specification.pageTitles[category] || ""
    property bool advanced: false
    property bool expert: false
    property string search: ""
    property string actionMessage: ""
    property bool actionMessageIsError: true
    property bool resetFailed: false
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    RedesignPreferences { id: preferenceStore; ctx: MainCtx; autoSave: true }
    RedesignPreferencesCatalog { id: specification }
    RedesignConfirmationDialog {
        id: resetDialog
        parent: content
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        title: qsTr("Reset all settings")
        message: qsTr("This action replaces all VLC settings with the default settings. Restart VLC after this action.")
        confirmText: qsTr("Reset"); destructive: true
        onAccepted: root.resetSettings()
    }
    Connections {
        target: preferenceStore
        function onChanged() { if (!preferenceStore.errorMessage.length) root.resetFailed = false }
    }
    RedesignShortcuts {
        id: shortcuts
        parent: content
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        onSaved: preferenceStore.discard()
    }
    function begin() {
        preferenceStore.discard()
        actionMessage = ""
        resetFailed = false
        searchField.clear()
        visible = true
        raise(); requestActivate()
    }
    function closeSettings() {
        content.forceActiveFocus()
        if (!preferenceStore.dirty || preferenceStore.save()) visible = false
    }
    function runAction(action) {
        if (action === "redesign-reset-all") { resetDialog.open(); return }
        if (action !== "redesign-config-folder") return
        actionMessageIsError = true
        const folder = preferenceStore.configurationFolder()
        actionMessage = folder.toString().length && Qt.openUrlExternally(folder) ? "" : qsTr("VLC cannot open the settings folder.")
    }
    function resetSettings() {
        resetFailed = !preferenceStore.resetAll()
        if (!resetFailed) {
            actionMessageIsError = false
            actionMessage = qsTr("VLC saved the default settings. Restart VLC to use all settings.")
        }
    }
    onClosing: event => { event.accepted = false; closeSettings() }
    Connections {
        target: DialogsProvider
        function onShowRedesignPreferences() { if (!root.visible) root.begin(); else { root.raise(); root.requestActivate() } }
        function onShowRedesignPreferencesPage(page) {
            if (!specification.pageTitles[page]) return
            root.begin()
            root.category = page
            root.advanced = false
            root.expert = false
            scroll.contentItem.contentY = 0
        }
    }
    Item {
        id: content
        anchors.fill: parent
        anchors.margins: theme.dp(15)
        focus: true
        Rectangle { anchors.fill: parent; color: theme.panel; radius: theme.dp(15) }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: theme.dp(50); radius: theme.dp(10); color: theme.field
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height / 2; color: parent.color }
        }
        Keys.onEscapePressed: root.closeSettings()
        Rectangle {
            id: navigation
            width: theme.dp(208); anchors.top: parent.top; anchors.bottom: parent.bottom
            color: "transparent"
            Rectangle {
                x: theme.dp(8); y: theme.dp(58); width: parent.width - theme.dp(8)
                height: parent.height - y - theme.dp(8); radius: theme.dp(6)
                color: theme.background
            }
            C.TextField {
                id: searchField
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: theme.dp(8); height: theme.dp(34)
                leftPadding: theme.dp(42)
                placeholderText: qsTr("Search")
                color: theme.foreground; placeholderTextColor: theme.foreground
                font.pixelSize: theme.dp(14); selectByMouse: true
                background: Rectangle { color: theme.background; radius: theme.dp(4); border.color: searchField.activeFocus ? theme.accent : theme.border }
                RedesignIcon { x: theme.dp(10); anchors.verticalCenter: parent.verticalCenter; width: theme.dp(20); height: width; name: "search"; color: theme.foreground }
                onTextEdited: root.search = text
                onTextChanged: if (!text.length) root.search = ""
            }
            C.ScrollView {
                anchors.top: searchField.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: theme.dp(16); anchors.bottomMargin: theme.dp(8)
                clip: true
                Column {
                    width: navigation.width
                    Repeater {
                        model: [
                            {group: qsTr("App"), key: "general", title: qsTr("General"), icon: "nav-preferences"},
                            {key: "interface", title: qsTr("Interface"), icon: "nav-interface"},
                            {key: "privacy", title: qsTr("Privacy"), icon: "nav-privacy"},
                            {key: "controls", title: qsTr("Controls"), icon: "nav-hotkeys"},
                            {group: qsTr("Media"), key: "playback", title: qsTr("Playback"), icon: "nav-playback"},
                            {key: "video", title: qsTr("Video"), icon: "nav-video"},
                            {key: "audio", title: qsTr("Audio"), icon: "nav-audio"},
                            {key: "subtitles", title: qsTr("Subtitles"), icon: "nav-subtitles"},
                            {key: "library", title: qsTr("Library"), icon: "nav-folder"},
                            {group: qsTr("System"), key: "network", title: qsTr("Network"), icon: "nav-streaming"},
                            {key: "performance", title: qsTr("Performance"), icon: "nav-preferences"},
                            {key: "recording", title: qsTr("Recording"), icon: "nav-record"},
                            {key: "extensions", title: qsTr("Extensions"), icon: "nav-plugins"} ]
                        delegate: Column {
                            required property var modelData
                            width: navigation.width
                            Text {
                                visible: !!modelData.group
                                height: visible ? theme.dp(47) : 0
                                leftPadding: theme.dp(24); topPadding: theme.dp(16)
                                text: modelData.group || ""; color: theme.foreground; font.pixelSize: theme.dp(14)
                            }
                            Item {
                                width: parent.width; height: theme.dp(48)
                                RedesignButton {
                                    objectName: "settingsCategory_" + modelData.key
                                    width: parent.width - theme.dp(20); x: theme.dp(14); height: theme.dp(40)
                                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                                    caption: modelData.title; text: caption; iconName: modelData.icon + (selected ? "-active" : "")
                                    leftAligned: true
                                    selectedForeground: theme.bright
                                    background: Rectangle { radius: theme.dp(3); color: parent.selected ? root.lightTheme ? theme.selected : "#222222" : parent.hovered ? theme.hover : "transparent"; border.width: parent.visualFocus ? 1 : 0; border.color: theme.accent }
                                    selected: root.category === modelData.key && !root.search.length
                                    onClicked: {
                                        root.category = modelData.key
                                        root.search = ""; searchField.clear(); root.advanced = false; root.expert = false
                                        scroll.contentItem.contentY = 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            id: heading
            anchors.left: navigation.right; anchors.leftMargin: theme.dp(32)
            y: theme.dp(16)
            text: root.search.length ? qsTr("Search results") : root.categoryTitle
            color: theme.foreground; font.pixelSize: theme.dp(16)
        }
        MouseArea {
            anchors.left: navigation.right; anchors.right: closeButton.left; anchors.top: parent.top; height: theme.dp(60)
            z: -1
            onPressed: root.startSystemMove()
        }
        RedesignButton {
            id: closeButton
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: theme.dp(7)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            iconName: "close"; text: qsTr("Close settings")
            onClicked: root.closeSettings()
        }
        C.ScrollView {
            id: scroll
            anchors.top: parent.top; anchors.topMargin: theme.dp(68)
            anchors.left: navigation.right; anchors.right: parent.right; anchors.bottom: footer.top
            anchors.leftMargin: theme.dp(32); anchors.rightMargin: theme.dp(24)
            clip: true
            contentWidth: availableWidth
            Column {
                width: scroll.availableWidth
                spacing: theme.dp(6)
                ColumnLayout {
                    visible: root.category === "general" && !root.search.length
                    width: parent.width
                    spacing: theme.dp(16)
                    Text { text: qsTr("Appearance"); color: theme.settingsHeading; font.pixelSize: theme.dp(16); Layout.topMargin: theme.dp(8) }
                    RedesignPreferenceRow { Layout.fillWidth: true; backend: preferenceStore; optionName: "language"; label: qsTr("Interface language"); scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: qsTr("Theme"); color: theme.foreground; font.pixelSize: theme.dp(14) }
                        Row {
                            spacing: theme.dp(2)
                            Repeater {
                                model: [{label: qsTr("Dark"), value: 2}, {label: qsTr("Light"), value: 1}, {label: qsTr("System"), value: 0}]
                                RedesignButton {
                                    required property var modelData
                                    width: theme.dp(105); height: theme.dp(34)
                                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                                    caption: modelData.label; text: caption
                                    selected: MainCtx.colorScheme.scheme === modelData.value
                                    background: Rectangle { color: parent.selected ? theme.progress : theme.background; radius: theme.dp(4); border.color: theme.field }
                                    onClicked: { MainCtx.colorScheme.setData(MainCtx.colorScheme.index(modelData.value, 0), true, Qt.CheckStateRole); preferenceStore.save() }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: theme.dp(34)
                        Text { Layout.fillWidth: true; text: qsTr("Accent color"); color: theme.foreground; font.pixelSize: theme.dp(14) }
                        Item {
                            Layout.preferredWidth: theme.dp(320); Layout.preferredHeight: theme.dp(34)
                            Rectangle { anchors.fill: parent; color: theme.background; radius: theme.dp(4) }
                            Row {
                                anchors.fill: parent
                                Repeater {
                                    model: ["#d37918", "#e15032", "#c49e23", "#19a234", "#18aad3", "#185dd3", "#8e42ff", "#f052b3", "#afafaf"]
                                    RedesignButton {
                                        required property string modelData
                                        readonly property bool active: { preferenceStore.revision; return root.accentColor.toString() === modelData }
                                        width: theme.dp(320 / 9); height: theme.dp(34)
                                        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                                        text: modelData
                                        background: Rectangle { color: parent.active ? theme.progress : "transparent"; radius: theme.dp(4) }
                                        contentItem: Item { Rectangle { anchors.centerIn: parent; width: theme.dp(20); height: width; radius: theme.dp(1); color: parent.parent.modelData; opacity: parent.parent.active ? 1 : 0.7 } }
                                        onClicked: preferenceStore.stage("qt-accent-color", modelData)
                                    }
                                }
                            }
                            TapHandler { acceptedButtons: Qt.RightButton; onTapped: accentMenu.popup() }
                            C.Menu {
                                id: accentMenu
                                C.MenuItem { text: qsTr("Custom accent color"); onTriggered: { const color = preferenceStore.chooseColor(root.accentColor.toString()); if (color.length) preferenceStore.stage("qt-accent-color", color) } }
                            }
                        }
                    }
                    Repeater {
                        model: specification.sections.general.find(section => section.appearance).rows
                        delegate: RedesignPreferenceRow {
                            required property var modelData
                            Layout.fillWidth: true
                            backend: preferenceStore; optionName: modelData[0]; label: modelData[1]
                            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                        }
                    }
                }
                Repeater {
                    model: root.search.length ? [] : (specification.sections[root.category] || []).filter(section => !section.appearance)
                    delegate: Column {
                        required property var modelData
                        required property int index
                        width: parent.width
                        visible: modelData.rows.some(row => preferenceStore.describe(row[0]).kind !== undefined) || root.category === "controls" && modelData.title === qsTr("Keyboard Shortcuts")
                        Text {
                            topPadding: theme.dp(index === 0 && root.category !== "general" ? 8 : 24); bottomPadding: theme.dp(10)
                            text: modelData.title; color: theme.settingsHeading; font.pixelSize: theme.dp(16)
                        }
                        ColumnLayout {
                            width: parent.width
                            visible: root.category === "controls" && modelData.title === qsTr("Keyboard Shortcuts")
                            spacing: theme.dp(10)
                            RowLayout {
                                Layout.fillWidth: true
                                Text { Layout.fillWidth: true; text: qsTr("Defaults"); color: theme.foreground; font.pixelSize: theme.dp(14) }
                                RedesignButton {
                                    Layout.preferredWidth: theme.dp(320); height: theme.dp(34)
                                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                                    caption: qsTr("Edit Keyboard Shortcuts"); text: caption
                                    background: Rectangle { radius: theme.dp(4); color: parent.hovered ? theme.hover : theme.background }
                                    onClicked: { content.forceActiveFocus(); if (!preferenceStore.dirty || preferenceStore.save()) shortcuts.open() }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { Layout.fillWidth: true; text: qsTr("Reset all shortcuts"); color: theme.foreground; font.pixelSize: theme.dp(14) }
                                RedesignButton {
                                    Layout.preferredWidth: theme.dp(320); height: theme.dp(34)
                                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                                    caption: qsTr("Reset"); text: caption
                                    background: Rectangle { radius: theme.dp(4); color: parent.hovered ? theme.hover : theme.background }
                                    onClicked: {
                                        for (const entry of preferenceStore.catalog("controls", ""))
                                            if (entry.name.startsWith("key-") || entry.name.startsWith("global-key-")) preferenceStore.reset(entry.name)
                                    }
                                }
                            }
                        }
                        Repeater {
                            model: modelData.rows
                            delegate: RedesignPreferenceRow {
                                required property var modelData
                                width: parent.width
                                backend: preferenceStore; optionName: modelData[0]; label: modelData[1]
                                presentation: modelData[2] || {}
                                onActionRequested: action => root.runAction(action)
                                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                            }
                        }
                    }
                }
                RedesignSubtitleSourcePreferences {
                    width: parent.width
                    visible: root.search.length ? [qsTr("Online Subtitles"), "OpenSubtitles", qsTr("API key")].some(text => text.toLowerCase().includes(root.search.toLowerCase())) : root.category === "subtitles"
                    sourceService: SubtitleSources
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                }
                RedesignButton {
                    visible: !root.search.length
                    width: parent.width; height: theme.dp(40)
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    caption: root.advanced ? qsTr("Hide Advanced Options") : qsTr("Advanced Options")
                    text: caption
                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent; spacing: theme.dp(10)
                            Text { text: qsTr("Advanced Options"); color: theme.foreground; font.pixelSize: theme.dp(14); anchors.verticalCenter: parent.verticalCenter }
                            RedesignIcon { name: root.advanced ? "chevron-down" : "chevron-right"; color: theme.foreground; width: theme.dp(20); height: width }
                        }
                    }
                    background: Rectangle { color: parent.hovered ? theme.hover : theme.background; radius: theme.dp(2) }
                    onClicked: root.advanced = !root.advanced
                }
                Repeater {
                    model: root.advanced && !root.search.length ? specification.advancedSections[root.category] || [] : []
                    delegate: Column {
                        required property var modelData
                        width: parent.width
                        Text {
                            visible: text.length > 0; topPadding: theme.dp(20); bottomPadding: theme.dp(10)
                            text: modelData.title; color: theme.settingsHeading; font.pixelSize: theme.dp(16)
                        }
                        Repeater {
                            model: modelData.rows
                            delegate: RedesignPreferenceRow {
                                required property var modelData
                                width: parent.width; backend: preferenceStore; optionName: modelData[0]; label: modelData[1]
                                presentation: modelData[2] || {}
                                onActionRequested: action => root.runAction(action)
                                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                            }
                        }
                    }
                }
                RedesignButton {
                    visible: root.advanced && !root.search.length
                    width: parent.width
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    caption: root.expert ? qsTr("Hide all VLC options") : qsTr("All VLC options")
                    text: caption; selected: root.expert
                    onClicked: root.expert = !root.expert
                }
                Repeater {
                    model: {
                        if (root.search.length) {
                            const matches = specification.find(root.search)
                            for (const entry of preferenceStore.catalog("", root.search))
                                if (!matches.some(row => row.name === entry.name)) matches.push(entry)
                            return matches
                        }
                        return root.expert ? preferenceStore.catalog(root.category, "") : []
                    }
                    delegate: RedesignPreferenceRow {
                        required property var modelData
                        width: parent.width
                        backend: preferenceStore; optionName: modelData.name; label: modelData.title || ""; presentation: modelData.presentation || {}
                        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                        onActionRequested: action => root.runAction(action)
                    }
                }
                Item { width: 1; height: theme.dp(24) }
            }
        }
        Rectangle {
            id: footer
            anchors.left: navigation.right; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: preferenceStore.errorMessage.length || root.actionMessage.length ? theme.dp(64) : 0
            visible: height > 0
            color: theme.background
            RowLayout {
                anchors.fill: parent; anchors.margins: theme.dp(16)
                Text {
                    Layout.fillWidth: true
                    text: preferenceStore.errorMessage || root.actionMessage
                    color: preferenceStore.errorMessage.length || root.actionMessageIsError ? "#e56b6b" : theme.foreground; font.pixelSize: theme.dp(13); wrapMode: Text.WordWrap
                }
                RedesignButton {
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    caption: qsTr("Retry"); text: caption; onClicked: root.resetFailed ? root.resetSettings() : preferenceStore.save()
                    visible: preferenceStore.errorMessage.length > 0
                }
            }
        }
    }
}
