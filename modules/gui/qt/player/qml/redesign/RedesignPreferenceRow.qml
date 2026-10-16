// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic as C
import QtQuick.Templates as T

ColumnLayout {
    id: root
    required property var backend
    required property string optionName
    property string label
    property var presentation: ({})
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    signal actionRequested(string action)
    signal editorResetRequested()
    readonly property var description: { if (presentation.dynamicChoices || optionName.endsWith("-language")) backend.revision; return backend.describe(optionName) }
    readonly property var currentValue: { backend.revision; return backend.value(optionName) }
    readonly property var choices: {
        const options = presentation.choices || description.choices || []
        if (!presentation.choiceLabels) return options
        return options.map(row => Object.assign({}, row, {label: presentation.choiceLabels[row.value] || row.label}))
    }
    readonly property string editor: presentation.editor || description.editor || ""
    readonly property real factor: presentation.factor || 1
    readonly property bool fullWidth: !!presentation.fullWidth
    readonly property bool compact: !!presentation.compact
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    readonly property bool available: description.kind !== undefined
    visible: available
    spacing: theme.dp(4)
    readonly property bool editorEnabled: { backend.revision; return description.supported !== false && (!presentation.enabledWhen || !!backend.value(presentation.enabledWhen)) }
    opacity: editorEnabled ? 1 : 0.5
    function commit(value) {
        if (presentation.inverted) value = !value
        return backend.stage(optionName, value)
    }
    readonly property var displayedValue: presentation.inverted ? !currentValue : currentValue
    TextMetrics {
        id: languageMetrics
        font.family: Qt.application.font.family; font.pixelSize: root.theme.dp(14)
        text: root.editor === "language" ? (root.choices.find(row => row.value === root.currentValue)?.label || "") : ""
    }
    readonly property Component editorComponent: editor === "action" ? actionEditor : editor === "startup-volume" ? startupVolumeEditor : editor === "slider" ? sliderEditor
        : editor === "track" ? trackEditor : editor === "language" ? languageEditor
        : description.kind === "bool" && !choices.length ? toggleEditor
        : editor === "color" ? colorEditor
        : choices.length ? choiceEditor : textEditor
    RowLayout {
        Layout.fillWidth: true
        Layout.minimumHeight: !available ? 0 : theme.dp(root.compact ? 52 : root.editor === "startup-volume" ? 92 : root.editor === "slider" ? 68 : root.choices.length ? 46 : root.description.kind === "bool" ? 42 : 48)
        spacing: theme.dp(10)
        implicitHeight: available ? Math.max(theme.dp(44), labelText.implicitHeight + theme.dp(10)) : 0
        Item {
            id: labelArea
            Layout.fillWidth: true; Layout.preferredWidth: 1
            implicitHeight: Math.max(labelText.implicitHeight, theme.dp(20))
            HoverHandler { id: rowHover }
            Text {
                id: labelText
                width: Math.min(implicitWidth, parent.width - theme.dp(26))
                anchors.verticalCenter: parent.verticalCenter
                text: root.label || root.description.title || ""
                color: root.compact ? theme.playerLabel : theme.foreground; font.pixelSize: theme.dp(14)
                wrapMode: Text.WordWrap
            }
            RedesignIcon {
                objectName: "preferenceHelpIcon"
                name: "info"; color: theme.foreground; opacity: 0.4
                width: theme.dp(16); height: width
                x: labelText.width + theme.dp(8); anchors.verticalCenter: parent.verticalCenter
                visible: !!root.description.help && !root.compact
            }
            RedesignToolTip { theme: root.theme; text: root.description.help || ""; visible: rowHover.hovered && text.length > 0; delay: 500 }
            RedesignButton {
                objectName: "preferenceResetButton"
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                width: theme.dp(26); height: theme.dp(28); iconSize: theme.dp(18)
                iconName: "history"; text: qsTr("Reset to default")
                enabled: root.editorEnabled
                visible: root.description.kind !== "action" && (rowHover.hovered || hovered || visualFocus)
                onClicked: { root.backend.reset(root.optionName); root.editorResetRequested() }
            }
        }
        Loader {
            visible: !root.fullWidth
            active: visible
            enabled: root.editorEnabled
            Layout.preferredWidth: root.compact ? root.editor === "language"
                ? Math.min(theme.dp(184),Math.max(theme.dp(138),languageMetrics.advanceWidth+theme.dp(56))) : theme.dp(138)
                : Math.min(theme.dp(320), Math.max(theme.dp(150), root.width * 0.43))
            Layout.preferredHeight: item ? item.implicitHeight || theme.dp(34) : theme.dp(34)
            sourceComponent: root.editorComponent
        }

    }
    Loader {
        Layout.fillWidth: true
        Layout.preferredHeight: item ? item.implicitHeight : 0
        active: root.fullWidth; visible: active
        enabled: root.editorEnabled
        sourceComponent: root.editorComponent
    }
    Loader {
        Layout.fillWidth: true
        Layout.topMargin: active ? theme.dp(8) : 0
        active: !!root.presentation.equalizer
        visible: active
        sourceComponent: RedesignEqualizer {
            backend: root.backend
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        }
    }
    Loader {
        Layout.fillWidth: true
        Layout.topMargin: active ? theme.dp(8) : 0
        active: !!root.presentation.spatializer
        visible: active
        sourceComponent: RedesignSpatializer {
            backend: root.backend
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        }
    }
    Component {
        id: actionEditor
        Item {
            implicitHeight: theme.dp(34)
            RedesignButton {
                objectName: "preferenceActionButton"
                anchors.right: parent.right
                width: theme.dp(100); height: parent.height
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                caption: root.description.buttonLabel || ""; text: caption
                foreground: root.description.destructive ? theme.danger : theme.foreground
                background: Rectangle { radius: theme.dp(4); color: parent.hovered ? theme.hover : root.description.destructive ? theme.dangerBackground : theme.background; border.color: parent.visualFocus ? parent.foreground : "transparent" }
                onClicked: root.actionRequested(root.optionName)
            }
        }
    }
    Component {
        id: startupVolumeEditor
        RedesignStartupVolume {
            backend: root.backend
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        }
    }
    Component {
        id: toggleEditor
        Item {
            implicitHeight: theme.dp(34)
            RedesignButton {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: theme.dp(64); height: theme.dp(30)
                objectName: "preferenceToggleEditor"
                checkable: true; checked: !!root.displayedValue
                text: root.label || root.description.title
                onClicked: root.commit(checked)
                background: Rectangle {
                    radius: theme.dp(4); color: parent.checked ? theme.progress : theme.background
                    border.width: parent.visualFocus ? 1 : 0; border.color: theme.accent
                }
                contentItem: Item {
                    Rectangle {
                        x: parent.parent.checked ? parent.width - width - theme.dp(3) : theme.dp(3)
                        y: theme.dp(3); width: theme.dp(26); height: parent.height - theme.dp(6)
                        radius: theme.dp(3); color: parent.parent.checked ? theme.accent : "#444444"
                    }
                    Text {
                        x: parent.parent.checked ? theme.dp(8) : theme.dp(34)
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.parent.checked ? qsTr("ON") : qsTr("OFF")
                        font.pixelSize: theme.dp(12); color: parent.parent.checked ? theme.accent : theme.foreground
                    }
                }
            }
        }
    }
    Component {
        id: languageEditor
        Item {
            id: languageControl
            implicitHeight: theme.dp(34)
            property bool custom: false
            function cancelCustom() {
                if (languageOrder.invalid) root.backend.cancelLanguageEdit(root.optionName)
                languageOrder.invalid=false;custom=false
            }
            readonly property var shortcutContext: root.backend.ctx === undefined ? null : root.backend.ctx
            readonly property var controlWindow: languageControl.Window.window
            readonly property var hostWindow: controlWindow && controlWindow.renderWindow !== undefined ? controlWindow.renderWindow : controlWindow
            Binding {
                target: languageControl.shortcutContext
                property: "useGlobalShortcuts"; value: false
                when: !!languageControl.shortcutContext && languageControl.visible
                    && languageControl.hostWindow && languageControl.hostWindow.visible
                    && (languageMenu.visible || languageControl.custom)
                restoreMode: Binding.RestoreBindingOrValue
            }
            RedesignComboBox {
                id: languageCombo
                objectName: "preferenceChoiceEditor"
                anchors.fill: parent; visible: !languageControl.custom
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                model: root.choices; textRole: "label"; valueRole: "value"
                currentIndex: { languageControl.custom; return model.findIndex(row => row.value === root.currentValue) }
                onActivated: index => {
                    const selected = model[index].value
                    if (selected === "__custom__") {
                        languageOrder.text = root.currentValue
                        languageOrder.invalid = false; languageControl.custom = true
                        languageOrder.forceActiveFocus(); languageOrder.selectAll()
                    } else root.commit(selected)
                }
                popup: C.Popup {
                    id: languageMenu
                    objectName: "languageChoicePopup"
                    x: languageCombo.width - width; y: languageCombo.height + root.theme.dp(4)
                    width: Math.max(languageCombo.width, root.theme.dp(260)); padding: root.theme.dp(4)
                    implicitHeight: Math.min(root.theme.dp((Math.max(entries.length,1)+1)*34+12), root.theme.dp(320))
                    margins: root.theme.dp(8); focus: true
                    readonly property var entries: root.choices.map((row,index) => ({label:row.label,value:row.value,index:index})).filter(row =>
                        row.label.toLocaleLowerCase().includes(languageSearch.text.trim().toLocaleLowerCase()) || String(row.value).toLowerCase().includes(languageSearch.text.trim().toLowerCase()))
                        .sort((a,b) => matchRank(a)-matchRank(b))
                    function matchRank(row) {
                        const query=languageSearch.text.trim().toLocaleLowerCase()
                        const label=row.label.toLocaleLowerCase(),code=String(row.value).toLowerCase()
                        return label===query || code===query ? 0 : label.startsWith(query) || code.startsWith(query) ? 1 : 2
                    }
                    function choose(index) {
                        const row=entries[index]
                        if (!row) return
                        languageCombo.activated(row.index); close()
                    }
                    onOpened: {
                        languageSearch.text="";languageSearch.forceActiveFocus()
                        languageList.currentIndex=Math.max(0, entries.findIndex(row => row.value===root.currentValue))
                        languageList.positionViewAtIndex(languageList.currentIndex,ListView.Contain)
                    }
                    onClosed: if (languageControl.custom) Qt.callLater(() => { languageOrder.forceActiveFocus(); languageOrder.selectAll() })
                    background: Rectangle { color: root.theme.panel; radius: root.theme.dp(6); border.color: root.theme.border }
                    contentItem: ColumnLayout {
                        spacing: root.theme.dp(4)
                        C.TextField {
                            id: languageSearch
                            objectName: "languageChoiceSearch"
                            Layout.fillWidth: true; Layout.preferredHeight: root.theme.dp(34)
                            placeholderText: qsTr("Search languages"); Accessible.name: placeholderText
                            color: root.theme.foreground; font.pixelSize: root.theme.dp(14); selectByMouse: true
                            background: Rectangle { color: root.theme.background; radius: root.theme.dp(4); border.color: languageSearch.activeFocus ? root.theme.accent : root.theme.border }
                            onTextChanged: languageList.currentIndex=0
                            onAccepted: languageMenu.choose(languageList.currentIndex)
                            Keys.onDownPressed: { languageList.forceActiveFocus();languageList.currentIndex=0 }
                        }
                        ListView {
                            id: languageList
                            objectName: "languageChoiceList"
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: languageMenu.entries.length>0
                            clip: true; keyNavigationEnabled: true
                            model: languageMenu.entries
                            Keys.onReturnPressed: languageMenu.choose(currentIndex)
                            Keys.onEnterPressed: languageMenu.choose(currentIndex)
                            delegate: C.ItemDelegate {
                                required property var modelData
                                required property int index
                                width: ListView.view.width; height: root.theme.dp(34)
                                text: modelData.label; highlighted: languageList.currentIndex===index
                                font.pixelSize: root.theme.dp(14)
                                onClicked: languageMenu.choose(index)
                                contentItem: Text { text: parent.text; font: parent.font; color: root.theme.foreground; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                background: Rectangle { color: parent.highlighted || parent.hovered ? root.theme.hover : "transparent"; radius: root.theme.dp(4) }
                            }
                            C.ScrollIndicator.vertical: C.ScrollIndicator {}
                        }
                        Text {
                            visible: languageMenu.entries.length===0
                            Layout.fillWidth: true; Layout.preferredHeight: root.theme.dp(34)
                            text: qsTr("No languages found"); color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
                        }
                    }
                }
            }
            RowLayout {
                anchors.fill: parent; visible: languageControl.custom; spacing: root.theme.dp(4)
                RedesignButton {
                    objectName: "languageOrderCancel"
                    Layout.preferredWidth: root.theme.dp(26); Layout.fillHeight: true
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    iconName: "back"; text: qsTr("Cancel language order")
                    onClicked: languageControl.cancelCustom()
                }
                C.TextField {
                    id: languageOrder
                    objectName: "preferenceLanguageOrderEditor"
                    Layout.fillWidth: true; Layout.fillHeight: true
                    property bool invalid: false
                    placeholderText: "en, ja"
                    Accessible.name: qsTr("Language names or codes, separated by commas")
                    color: root.theme.foreground; font.pixelSize: root.theme.dp(14); selectByMouse: true
                    background: Rectangle { color: root.theme.background; radius: root.theme.dp(4); border.color: languageOrder.invalid ? root.theme.danger : languageOrder.activeFocus ? root.theme.accent : root.theme.field }
                    function save() {
                        invalid = !root.commit(text)
                        if (!invalid) languageControl.custom = false
                    }
                    onAccepted: save()
                    Keys.onEscapePressed: event => { languageControl.cancelCustom(); event.accepted = true }
                }
                RedesignButton {
                    objectName: "languageOrderSave"
                    Layout.preferredWidth: root.theme.dp(26); Layout.fillHeight: true
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    iconName: "check"; text: qsTr("Use this language order")
                    onClicked: languageOrder.save()
                }
            }
        }
    }
    Component {
        id: choiceEditor
        RedesignComboBox {
            id: choice
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            objectName: "preferenceChoiceEditor"
            implicitHeight: theme.dp(34)
            model: root.choices; textRole: "label"; valueRole: "value"
            showCurvePreviews: root.choices.some(row => row.curve !== undefined)
            currentIndex: {
                for (let i = 0; i < count; ++i) if (model[i].value == root.displayedValue) return i
                return -1
            }
            onAboutToOpen: if (root.presentation.dynamicChoices) root.backend.refresh()
            onActivated: root.commit(currentValue)
        }
    }
    Component {
        id: sliderEditor
        ColumnLayout {
            implicitHeight: theme.dp(48)
            spacing: theme.dp(2)
            C.Slider {
                id: slider
                objectName: "preferenceSliderEditor"
                Layout.fillWidth: true
                implicitHeight: theme.dp(28)
                from: root.presentation.from === undefined ? root.description.minimum : root.presentation.from
                to: root.presentation.to === undefined ? root.description.maximum : root.presentation.to
                stepSize: root.presentation.step || (root.description.kind === "integer" ? 1 : 0.01)
                value: Number(root.currentValue) * root.factor
                Accessible.name: root.label || root.description.title
                background: Rectangle {
                    x: slider.leftPadding; y: (slider.height - height) / 2
                    width: slider.availableWidth; height: theme.dp(14); radius: theme.dp(5); color: theme.field
                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: parent.radius; color: theme.progress }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: (slider.height - height) / 2
                    width: theme.dp(8); height: theme.dp(24); radius: theme.dp(4); color: theme.accent
                    border.width: slider.visualFocus ? 1 : 0; border.color: theme.bright
                }
                onMoved: root.commit(root.description.kind === "integer" ? Math.round(value / root.factor) : value / root.factor)
                hoverEnabled: true
                RedesignToolTip { theme: root.theme; text: Number(parent.value).toFixed(root.presentation.decimals || 0) + (root.presentation.suffix || ""); visible: parent.hovered || parent.pressed; delay: 0 }
            }
            RowLayout {
                visible: !root.presentation.ticks
                Layout.fillWidth: true
                Text { text: slider.from + (root.presentation.suffix || ""); color: theme.foreground; font.pixelSize: theme.dp(11) }
                Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: Number(slider.value).toFixed(root.presentation.decimals || 0) + (root.presentation.suffix || ""); color: theme.foreground; font.pixelSize: theme.dp(11) }
                Text { text: slider.to + (root.presentation.suffix || ""); color: theme.foreground; font.pixelSize: theme.dp(11) }
            }
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: theme.dp(14)
                visible: !!root.presentation.ticks
                Repeater {
                    model: root.presentation.ticks || []
                    Text {
                        required property int index
                        required property var modelData
                        x: index * parent.width / Math.max(1, (root.presentation.ticks || []).length - 1)
                            - (index === 0 ? 0 : index === (root.presentation.ticks || []).length - 1 ? width : width / 2)
                        text: modelData + (root.presentation.suffix || "")
                        color: theme.foreground; font.pixelSize: theme.dp(11)
                    }
                }
            }
        }
    }
    Component {
        id: colorEditor
        RedesignButton {
            implicitHeight: theme.dp(34)
            leftPadding: theme.dp(14); rightPadding: theme.dp(6)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            readonly property string chosenColor: "#" + Number(root.currentValue).toString(16).padStart(6, "0")
            caption: chosenColor.toUpperCase(); text: qsTr("Choose %1").arg(root.label)
            background: Rectangle { radius: theme.dp(4); color: theme.field; border.color: theme.border }
            contentItem: RowLayout {
                Text { Layout.fillWidth: true; text: parent.parent.caption; color: theme.foreground; font.pixelSize: theme.dp(14) }
                Rectangle { width: theme.dp(20); height: width; color: parent.parent.chosenColor; border.color: theme.border; radius: theme.dp(2) }
            }
            onClicked: { const color = root.backend.chooseColor(chosenColor); if (color.length) root.commit(parseInt(color.slice(1), 16)) }
        }
    }
    Component {
        id: trackEditor
        T.SpinBox {
            id: trackField
            objectName: "preferenceTrackEditor"
            implicitHeight: theme.dp(34)
            from: 0; to: root.description.maximum
            value: Number(root.currentValue)
            editable: true
            font.pixelSize: theme.dp(14)
            leftPadding: theme.dp(14); rightPadding: theme.dp(10)
            textFromValue: (value, locale) => value === 0 ? qsTr("Automatic") : String(value)
            valueFromText: (text, locale) => {
                const input = text.trim()
                if (input.toLocaleLowerCase() === qsTr("Automatic").toLocaleLowerCase()) return 0
                const number = Number(input)
                return input.length && Number.isInteger(number) && number >= 1 && number <= to ? number : value
            }
            contentItem: TextInput {
                text: trackField.displayText; font: trackField.font; color: theme.foreground
                selectionColor: theme.accent; selectedTextColor: theme.background
                verticalAlignment: TextInput.AlignVCenter; selectByMouse: true; clip: true
                onActiveFocusChanged: if (activeFocus) selectAll()
            }
            background: Rectangle {
                radius: theme.dp(4); color: theme.field
                border.color: trackField.activeFocus ? theme.accent : theme.background
            }
            Accessible.name: root.label
            onValueModified: root.commit(value)
        }
    }
    Component {
        id: textEditor
        RowLayout {
            implicitHeight: theme.dp(34)
            spacing: theme.dp(10)
            C.TextField {
                id: field
                objectName: "preferenceTextEditor"
                Layout.fillWidth: true; Layout.fillHeight: true
                property bool invalid: false
                readonly property bool numeric: root.description.kind === "integer" || root.description.kind === "float"
                readonly property string formattedValue: root.currentValue === undefined ? "" : numeric
                    ? root.presentation.decimals === undefined ? String(Number(root.currentValue) * root.factor) : (Number(root.currentValue) * root.factor).toFixed(root.presentation.decimals)
                    : String(root.currentValue)
                Binding on text {
                    when: !field.activeFocus && !field.invalid
                    restoreMode: Binding.RestoreNone
                    value: field.formattedValue
                }
                leftPadding: theme.dp(14); rightPadding: theme.dp(10)
                Layout.minimumHeight: theme.dp(34)
                color: invalid ? "#e56b6b" : theme.foreground; font.pixelSize: theme.dp(14)
                selectByMouse: true
                echoMode: root.description.kind === "password" ? TextInput.Password : TextInput.Normal
                inputMethodHints: root.description.kind === "integer" || root.description.kind === "float" ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
                Accessible.name: root.label || root.description.title
                background: Rectangle { radius: theme.dp(4); color: theme.field; border.color: field.invalid ? "#e56b6b" : field.activeFocus ? theme.accent : theme.border }
                onEditingFinished: {
                    const number = Number(text)
                    invalid = numeric ? !text.trim().length || !Number.isFinite(number) || !root.commit(root.description.kind === "integer" ? Math.round(number / root.factor) : number / root.factor) : !root.commit(text)
                    if (!invalid) text = formattedValue
                }
                Connections {
                    target: root
                    function onEditorResetRequested() { field.invalid = false; field.text = field.formattedValue }
                }
                TextMetrics { id: valueMetrics; text: field.text; font: field.font }
                Text {
                    x: field.leftPadding + valueMetrics.advanceWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.presentation.suffix || ""; color: theme.foreground; font.pixelSize: theme.dp(14)
                    visible: !field.activeFocus
                }
                onActiveFocusChanged: if (activeFocus) selectAll()
            }
            RedesignButton {
                visible: root.editor === "file" || root.editor === "directory"
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                caption: qsTr("Browse"); text: caption
                onClicked: { const path = root.backend.choosePath(root.optionName); if (path.length) root.commit(path) }
            }
        }
    }
}
