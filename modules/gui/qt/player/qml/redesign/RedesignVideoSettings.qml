// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C
import QtQml.Models

ColumnLayout {
    id: root
    required property var backend
    property var rendererModel
    property var videoTracksModel
    property var deinterlaceModel
    property real scaleFactor: 1
    property bool lightTheme: false
    property color accentColor: "#d37918"
    property int liveRevision: 0
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal trackRequested(int index)
    signal deinterlaceRequested(int index)
    spacing: 0

    function current(name) { backend.revision; liveRevision; return backend.videoValue(name) }
    readonly property var hdrDescription: { backend.revision; return backend.describe("d3d11-hdr-mode") }
    readonly property bool hdrSupported: hdrDescription.kind !== undefined
    function supportsHdrPolicy(value) {
        return (hdrDescription.choices || []).some(row => row.value === value)
    }
    function enabledFilter(name, chain = "video-filter") {
        return String(current(chain) || "").split(":").includes(name)
            || (chain === "sub-source" && String(current("sub-filter") || "").split(":").includes(name))
    }
    function effect(name, enabled, chain = "video-filter") { return backend.stage("filter:" + chain + ":" + name, enabled) }
    function options(name, rows) {
        const result = rows.slice()
        const value = current(name)
        if (value !== undefined && !result.some(row => row.value === value))
            result.push({label: name === "crop" && String(value).includes("+") ? qsTr("Custom") : String(value), value: value})
        return result
    }
    readonly property real zoomSelection: current("autoscale") ? -Math.max(1, Number(current("fit")) || 1) : Number(current("zoom"))
    function setZoomSelection(value) {
        if (value < 0) {
            backend.stage("fit", -value)
            backend.stage("autoscale", true)
        } else {
            backend.stage("zoom", value)
            backend.stage("fit", 0)
            backend.stage("autoscale", false)
        }
    }
    readonly property string videoTransform: enabledFilter("transform") ? String(current("transform-type")) : ""
    readonly property real pixelRotation: enabledFilter("rotate") ? Number(current("rotate-angle")) : 0
    readonly property var orientation: {
        // Several Rotate/Flip pairs have the same native transform. Retain the
        // chosen pair only while its native settings still match the output.
        try {
            const state = JSON.parse(String(current("qt-video-transform-state") || "{}"))
            if (state.transform === videoTransform && state.pixelRotation === pixelRotation
                && Number.isInteger(state.flip) && state.flip >= 0 && state.flip <= 2
                && Number.isFinite(state.angle) && Math.abs(state.angle) <= 360)
                return state
        } catch (error) { }
        return {
            flip: videoTransform === "hflip" || videoTransform === "transpose" ? 1 : videoTransform === "vflip" || videoTransform === "antitranspose" ? 2 : 0,
            angle: -pixelRotation + ({"90": 90, "180": 180, "270": 270, "transpose": 90, "antitranspose": 90}[videoTransform] || 0)
        }
    }
    readonly property int flip: orientation.flip
    readonly property real rotationDegrees: orientation.angle
    function setOrientation(angle, flipIndex) {
        if (!Number.isFinite(angle) || Math.abs(angle) > 360 || !Number.isInteger(flipIndex) || flipIndex < 0 || flipIndex > 2) return false
        const quarter = angle % 90 === 0
        const turns = ((angle / 90) % 4 + 4) % 4
        const transforms = [["", "90", "180", "270"], ["hflip", "transpose", "vflip", "antitranspose"], ["vflip", "antitranspose", "hflip", "transpose"]]
        const transform = quarter ? transforms[flipIndex][turns] : flipIndex === 1 ? "hflip" : flipIndex === 2 ? "vflip" : ""
        // Native free-angle rotation uses the opposite sign to transform.
        const pixels = quarter ? 0 : -angle
        // Keep the orientation transform last. Pixel filters can replace an
        // earlier orientation with their output format.
        effect("transform", false)
        if (!backend.stage("rotate-angle", pixels)) return false
        effect("rotate", !quarter)
        if (transform.length && !backend.stage("transform-type", transform)) return false
        effect("transform", transform.length > 0)
        return backend.stage("qt-video-transform-state", JSON.stringify({transform: transform, pixelRotation: pixels, flip: flipIndex, angle: angle}))
    }
    function setFlip(index) { return setOrientation(rotationDegrees, index) }
    function setRotation(angle) { return setOrientation(angle, flip) }
    function borders() {
        const parts = String(current("crop") || "").split("+")
        return parts.length === 4 && parts.every(value => /^\d+$/.test(value)) ? parts.map(Number) : [0, 0, 0, 0]
    }
    function setBorder(index, value) {
        if (!Number.isInteger(value) || value < 0 || value > 2147483647) return false
        const values = borders()
        values[index] = value
        if (index % 2 === 0 && cropSection.contentItem.linkHorizontal) values[2 - index] = value
        if (index % 2 === 1 && cropSection.contentItem.linkVertical) values[4 - index] = value
        return backend.stage("crop", values.join("+"))
    }
    Timer { interval: 400; running: root.visible; repeat: true; onTriggered: root.liveRevision++ }

    component Choice: RowLayout {
        property string label
        property string optionName
        property var choices
        property bool zoomControl: false
        property bool restrictChoices: false
        property real choiceHeight: 34
        property real popupGap: 4
        property var selectedValue: root.current(optionName)
        property string help
        property string emptyText
        Layout.fillWidth: true; Layout.minimumHeight: theme.dp(68)
        Text { Layout.fillWidth: true; text: parent.label; color: theme.playerLabel; font.pixelSize: theme.dp(14); wrapMode: Text.WordWrap }
        RedesignComboBox {
            objectName: parent.optionName + "Choice"
            Layout.preferredWidth: Math.min(theme.dp(217), root.width * .61); Layout.minimumWidth: 0
            implicitHeight: theme.dp(46)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            model: parent.choices; textRole: "label"; valueRole: "value"
            restrictChoices: parent.restrictChoices
            showSelectionMark: parent.restrictChoices
            choiceHeight: parent.choiceHeight
            popupGap: parent.popupGap
            currentIndex: model.findIndex(row => row.value === parent.selectedValue)
            function restoreIndexBinding() {
                currentIndex = Qt.binding(() => model.findIndex(row => row.value === parent.selectedValue))
            }
            // ComboBox resets its index when a custom value changes the model.
            // Restore the binding after the new model has been installed.
            onModelChanged: Qt.callLater(restoreIndexBinding)
            displayText: currentIndex < 0 ? parent.emptyText : currentText
            Accessible.name: parent.label
            onActivated: {
                if (!choiceEnabled(currentIndex)) { restoreIndexBinding(); return }
                if (parent.zoomControl) root.setZoomSelection(currentValue)
                else root.backend.stage(parent.optionName, currentValue)
                restoreIndexBinding()
            }
            RedesignToolTip { theme: root.theme; text: parent.parent.help; visible: parent.hovered && text.length > 0 }
        }
    }
    component FilterSlider: RedesignSettingSlider {
        required property string optionName
        Layout.fillWidth: true
        labelColor: theme.playerLabel
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        visible: root.backend.describe(optionName).kind !== undefined
        currentValue: Number(root.current(optionName))
        valueFieldVisible: false; scaleLabelsVisible: false; sliderTopMargin: 8
        onMoved: value => root.backend.stage(optionName, value)
    }
    component FilterSwitch: RedesignSwitchRow {
        required property string filterName
        Layout.fillWidth: true
        labelColor: theme.playerLabel
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        visible: root.backend.describe("filter:video-filter:" + filterName).kind !== undefined
        checked: root.enabledFilter(filterName)
        onToggled: checked => root.effect(filterName, checked)
    }

    QtObject {
        id: videoStore
        property int revision: root.backend.revision + root.liveRevision
        function value(name) {
            if (name.startsWith("filter:")) { const parts = name.split(":"); return root.enabledFilter(parts[2], parts[1]) }
            return root.current(name)
        }
        function describe(name) { return root.backend.describe(name) }
        function stage(name, value) { return root.backend.stage(name, value) }
        function reset(name) { root.backend.reset(name) }
        function choosePath(name) { return root.backend.choosePath(name) }
        function chooseColor(initial) { return root.backend.chooseColor(initial) }
        function refresh() { root.backend.refresh() }
    }
    component Option: RedesignPreferenceRow {
        Layout.fillWidth: true
        backend: videoStore
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        presentation: ({compact: true})
    }
    component NumberOption: RedesignSettingSlider {
        required property string optionName
        Layout.fillWidth: true
        labelColor: theme.playerLabel
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        visible: root.backend.describe(optionName).kind !== undefined
        currentValue: Number(root.current(optionName) || 0)
        sliderVisible: false; decimals: 0; stepSize: 1
        from: 0; to: 2147483647
        onMoved: value => root.backend.stage(optionName, value)
    }
    component ParameterSlider: RedesignSettingSlider {
        required property string optionName
        property real valueFactor: 1
        Layout.fillWidth: true; Layout.topMargin: theme.dp(10); Layout.bottomMargin: theme.dp(10)
        labelColor: theme.playerLabel
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        visible: root.backend.describe(optionName).kind !== undefined
        currentValue: Number(root.current(optionName) || 0) * valueFactor
        scaleLabelsVisible: false; sliderTopMargin: 6
        onMoved: value => root.backend.stage(optionName, root.backend.describe(optionName).kind === "integer" ? Math.round(value / valueFactor) : value / valueFactor)
    }
    component OverlaySwitch: RedesignSwitchRow {
        required property string sourceName
        Layout.fillWidth: true
        labelColor: theme.playerLabel
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        visible: root.backend.describe("filter:sub-source:" + sourceName).kind !== undefined
        checked: root.enabledFilter(sourceName, "sub-source")
        onToggled: checked => root.effect(sourceName, checked, "sub-source")
    }

    Text { Layout.topMargin: theme.dp(12); Layout.bottomMargin: theme.dp(26); text: qsTr("Defaults"); color: theme.playerHeading; font.pixelSize: theme.dp(16) }
    Text { Layout.bottomMargin: theme.dp(18); text: qsTr("Flip"); color: theme.playerLabel; font.pixelSize: theme.dp(14) }
    RowLayout {
        Layout.fillWidth: true; Layout.preferredHeight: theme.dp(44); spacing: theme.dp(2)
        Repeater {
            model: [qsTr("None"), qsTr("Horizontal"), qsTr("Vertical")]
            RedesignButton {
                required property int index
                required property string modelData
                objectName: "videoFlip_" + index
                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                foreground: theme.playerLabel
                caption: modelData; text: qsTr("Flip: %1").arg(modelData); selected: root.flip === index
                background: Rectangle { radius: theme.dp(4); color: parent.selected ? theme.progress : parent.hovered ? theme.hover : theme.background; border.color: parent.visualFocus ? theme.accent : theme.field }
                onClicked: root.setFlip(index)
            }
        }
    }
    RedesignSettingSlider {
        objectName: "videoRotation"
        Layout.fillWidth: true; Layout.topMargin: theme.dp(28); Layout.bottomMargin: theme.dp(16)
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        labelColor: theme.playerLabel
        label: qsTr("Rotate"); suffix: " deg"; decimals: 1; trimTrailingZeros: true
        from: -360; to: 360; stepSize: 1; currentValue: root.rotationDegrees
        sliderVisible: false
        onMoved: value => root.setRotation(value)
    }
    Choice {
        label: qsTr("Zoom"); optionName: "zoom"; zoomControl: true
        selectedValue: root.zoomSelection
        choices: root.options(optionName, [{label: qsTr("1:4 Quarter"), value: .25}, {label: qsTr("1:2 Half"), value: .5}, {label: qsTr("1:1 Original"), value: 1}, {label: qsTr("2:1 Double"), value: 2}]).concat([
            {label: qsTr("Fit Inside Window"), value: -1}, {label: qsTr("Fill Window"), value: -2},
            {label: qsTr("Fit Window Width"), value: -3}, {label: qsTr("Fit Window Height"), value: -4}])
        help: qsTr("Zoom ratios use the video's actual pixel size.")
    }
    Choice {
        label: qsTr("HDR"); optionName: "d3d11-hdr-mode"
        enabled: root.hdrSupported
        opacity: enabled ? 1 : .5
        restrictChoices: true
        choiceHeight: 46; popupGap: 22
        choices: [
            {label: qsTr("Auto"), value: "auto", enabled: root.supportsHdrPolicy("auto")},
            {label: qsTr("Off"), value: "never", enabled: root.supportsHdrPolicy("never")},
            {label: "HDR10", value: "always", enabled: root.supportsHdrPolicy("always")},
            {label: "HDR10+", value: "hdr10plus", enabled: false},
            {label: "Dolby Vision", value: "dolbyvision", enabled: false},
            {label: "HLG", value: "hlg", enabled: false}
        ]
        help: enabled ? qsTr("Use Direct3D11 output for this setting. The mode applies when a video output starts. Unavailable formats are dimmed.")
                      : qsTr("This VLC build does not include Direct3D11 HDR output.")
        emptyText: root.current(optionName) === "generate" ? qsTr("SDR to HDR") : qsTr("Auto")
    }
    Choice {
        label: qsTr("Resolution"); optionName: "preferred-resolution"
        choices: (root.backend.describe(optionName).choices || []).map(row => Object.assign({}, row, {label: row.value === -1 ? qsTr("Best Available") : row.label}))
        help: qsTr("Set the maximum resolution for the next video.")
    }
    Choice { label: qsTr("Aspect Ratio"); optionName: "aspect-ratio"; choices: root.options(optionName, ["", "1:1", "4:3", "5:4", "16:9", "16:10", "2.21:1", "2.35:1", "2.39:1"].map(value => ({label: value || qsTr("Default"), value: value}))) }
    Choice { label: qsTr("Crop"); optionName: "crop"; choices: root.options(optionName, ["", "16:10", "16:9", "1.85:1", "2.21:1", "2.35:1", "2.39:1", "5:3", "4:3", "5:4", "1:1"].map(value => ({label: value || qsTr("Default"), value: value}))) }
    RowLayout {
        Layout.fillWidth: true; Layout.minimumHeight: theme.dp(68)
        Text { Layout.fillWidth: true; text: qsTr("Render"); color: theme.playerLabel; font.pixelSize: theme.dp(14) }
        Instantiator {
            id: renderers
            model: root.rendererModel
            delegate: QtObject { required property string name; required property bool selected }
        }
        RedesignComboBox {
            objectName: "videoRendererChoice"
            Layout.preferredWidth: Math.min(theme.dp(217), root.width * .61); Layout.minimumWidth: 0; implicitHeight: theme.dp(46)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            model: {
                const rows = [qsTr("Local")]
                for (let i = 0; i < renderers.count; ++i) rows.push(renderers.objectAt(i).name)
                return rows
            }
            currentIndex: {
                if (!root.rendererModel || !root.rendererModel.useRenderer) return 0
                for (let i = 0; i < renderers.count; ++i) if (renderers.objectAt(i).selected) return i + 1
                return -1
            }
            Accessible.name: qsTr("Render")
            onAboutToOpen: if (root.rendererModel) root.rendererModel.StartScan()
            onActivated: index => {
                if (!root.rendererModel) return
                if (index === 0) root.rendererModel.disableRenderer()
                else root.rendererModel.setData(root.rendererModel.index(index - 1, 0), true, Qt.CheckStateRole)
            }
        }
    }
    Rectangle { Layout.fillWidth: true; Layout.leftMargin: -theme.dp(24); Layout.rightMargin: -theme.dp(20); Layout.topMargin: theme.dp(12); height: theme.dp(1); color: theme.border }
    Text { Layout.topMargin: theme.dp(20); text: qsTr("Filters"); color: theme.playerHeading; font.pixelSize: theme.dp(16) }
    RedesignFilterSection {
        objectName: "videoEssentialSection"
        Layout.fillWidth: true; label: qsTr("Essential")
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        settings: ColumnLayout {
            spacing: theme.dp(19)
            FilterSlider { objectName: "videoHue"; label: qsTr("Hue"); optionName: "hue"; from: -180; to: 180; decimals: 1; stepSize: 1 }
            FilterSlider { objectName: "videoBrightness"; label: qsTr("Brightness"); optionName: "brightness"; from: 0; to: 2; decimals: 2; stepSize: .01 }
            FilterSlider { objectName: "videoContrast"; label: qsTr("Contrast"); optionName: "contrast"; from: 0; to: 2; decimals: 2; stepSize: .01 }
            FilterSlider { objectName: "videoSaturation"; label: qsTr("Saturation"); optionName: "saturation"; from: 0; to: 3; decimals: 2; stepSize: .01; ticks: [0, 1, 2, 3] }
            FilterSlider { objectName: "videoGamma"; label: qsTr("Gamma"); optionName: "gamma"; from: .01; to: 10; decimals: 2; stepSize: .01; ticks: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }
            FilterSlider { objectName: "videoSharpen"; label: qsTr("Sharpen Sigma"); optionName: "sharpen-sigma"; from: 0; to: 2; decimals: 2; stepSize: .01; ticks: [0, .5, 1, 1.5, 2] }
            FilterSlider { objectName: "videoBanding"; label: qsTr("Banding Removal Radius"); optionName: "gradfun-radius"; from: 4; to: 32; stepSize: 1; ticks: [4, 8, 12, 16, 20, 24, 28, 32] }
            FilterSlider { objectName: "videoGrain"; label: qsTr("Film Grain Variance"); optionName: "grain-variance"; from: 0; to: 10; decimals: 2; stepSize: .01; ticks: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }
        }
    }
    RedesignFilterSection {
        id: cropSection
        objectName: "videoCropSection"
        Layout.fillWidth: true; label: qsTr("Crop")
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        settings: ColumnLayout {
            id: cropSettings
            property bool linkVertical: false
            property bool linkHorizontal: false
            spacing: theme.dp(14)
            Repeater {
                model: [[{label: qsTr("Top"), side: 1}, {label: qsTr("Bottom"), side: 3}], [{label: qsTr("Left"), side: 0}, {label: qsTr("Right"), side: 2}]]
                RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true; spacing: theme.dp(8)
                    Repeater {
                        model: parent.modelData
                        C.TextField {
                            required property var modelData
                            objectName: "videoCropBorder_" + modelData.side
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            implicitHeight: theme.dp(34); leftPadding: theme.dp(12); rightPadding: theme.dp(8)
                            color: theme.foreground; font.pixelSize: theme.dp(14)
                            Binding on text { restoreMode: Binding.RestoreNone; when: !activeFocus; value: root.borders()[modelData.side] + " px" }
                            horizontalAlignment: TextInput.AlignRight
                            leftInset: 0; rightInset: 0
                            background: Rectangle { radius: theme.dp(4); color: theme.field; border.color: parent.activeFocus ? theme.accent : "transparent" }
                            Text { anchors.left: parent.left; anchors.leftMargin: theme.dp(12); anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; color: theme.playerLabel; font: parent.font }
                            onActiveFocusChanged: if (activeFocus) selectAll()
                            onEditingFinished: {
                                const input = text.trim().replace(/\s*px$/, "")
                                if (/^\d+$/.test(input)) root.setBorder(modelData.side, Number(input))
                                text = root.borders()[modelData.side] + " px"
                            }
                            Accessible.name: qsTr("Crop %1").arg(modelData.label)
                        }
                    }
                    RedesignButton {
                        objectName: "videoCropLink_" + index
                        Layout.preferredWidth: theme.dp(30); Layout.preferredHeight: theme.dp(34)
                        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                        text: index === 0 ? qsTr("Link top and bottom") : qsTr("Link left and right")
                        selected: index === 0 ? cropSettings.linkVertical : cropSettings.linkHorizontal
                        contentItem: RedesignSvg {
                            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                            svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M9 7H7a5 5 0 0 0 0 10h2m6-10h2a5 5 0 0 1 0 10h-2' + (parent.selected ? 'M8 12h8' : '') + '" fill="none" stroke="' + (parent.selected ? theme.accent : theme.foreground) + '" stroke-width="1.5" stroke-linecap="round"/></svg>'
                        }
                        onClicked: { if (index === 0) cropSettings.linkVertical = !cropSettings.linkVertical; else cropSettings.linkHorizontal = !cropSettings.linkHorizontal }
                    }
                }
            }
        }
    }
    RedesignFilterSection {
        objectName: "videoColorsSection"
        Layout.fillWidth: true; label: qsTr("Colors"); contentTopMargin: -3
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        settings: ColumnLayout {
            spacing: 0
            Repeater {
                model: [{label: qsTr("Color Extraction"), name: "extract", option: "extract-component"}, {label: qsTr("Color Threshold"), name: "colorthres", option: "colorthres-color"}]
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true; Layout.bottomMargin: modelData.name === "extract" ? theme.dp(20) : theme.dp(12); spacing: theme.dp(12)
                    GridLayout {
                        columns: root.width < theme.dp(320) ? 2 : 3
                        columnSpacing: theme.dp(10); rowSpacing: theme.dp(10)
                        Layout.fillWidth: true; Layout.minimumHeight: theme.dp(52)
                        Text { Layout.columnSpan: parent.columns === 2 ? 2 : 1; Layout.fillWidth: true; text: modelData.label; color: theme.playerLabel; font.pixelSize: theme.dp(14); wrapMode: Text.WordWrap }
                        C.TextField {
                            id: colorField
                            objectName: "videoColor_" + modelData.name
                            Layout.fillWidth: parent.columns === 2; Layout.minimumWidth: 0; Layout.preferredWidth: theme.dp(112); implicitHeight: theme.dp(34)
                            leftPadding: theme.dp(12); rightPadding: theme.dp(32)
                            Binding on text { restoreMode: Binding.RestoreNone; when: !colorField.activeFocus; value: "#" + Number(root.current(modelData.option)).toString(16).padStart(6, "0").toUpperCase() }
                            color: theme.foreground; font.pixelSize: theme.dp(14)
                            background: Rectangle { radius: theme.dp(4); color: theme.field; border.color: parent.activeFocus ? theme.accent : "transparent" }
                            onEditingFinished: {
                                const input = text.trim().replace(/^#/, "")
                                if (/^[0-9a-fA-F]{6}$/.test(input)) root.backend.stage(modelData.option, parseInt(input, 16))
                                text = "#" + Number(root.current(modelData.option)).toString(16).padStart(6, "0").toUpperCase()
                            }
                            Accessible.name: modelData.label
                            RedesignButton {
                                anchors.right: parent.right; anchors.rightMargin: theme.dp(5); anchors.verticalCenter: parent.verticalCenter
                                width: theme.dp(22); height: width
                                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                                text: qsTr("Choose %1 color").arg(modelData.label)
                                background: Rectangle { radius: theme.dp(2); color: colorField.text; border.color: parent.visualFocus ? theme.accent : theme.border }
                                onClicked: { const color = root.backend.chooseColor(colorField.text); if (color) root.backend.stage(modelData.option, parseInt(color.replace(/^#/, ""), 16)) }
                            }
                        }
                        FilterSwitch { Layout.fillWidth: false; Layout.preferredWidth: theme.dp(64); label: ""; accessibleName: modelData.label; filterName: modelData.name }
                    }
                    FilterSlider { Layout.topMargin: -theme.dp(8); Layout.bottomMargin: theme.dp(8); visible: modelData.name === "colorthres"; label: qsTr("Saturation"); optionName: "colorthres-saturationthres"; from: 0; to: 100; stepSize: 1 }
                    FilterSlider { Layout.bottomMargin: theme.dp(16); visible: modelData.name === "colorthres"; label: qsTr("Similarity"); optionName: "colorthres-similaritythres"; from: 0; to: 100; stepSize: 1 }
                }
            }
            FilterSwitch { label: qsTr("Negate Colors"); filterName: "invert" }
            FilterSwitch { label: qsTr("Posterize"); filterName: "posterize" }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: theme.dp(6); height: theme.dp(1); color: theme.border }
            FilterSwitch { label: qsTr("Gradient"); filterName: "gradient" }
            RedesignComboBox {
                objectName: "videoGradientMode"
                Layout.fillWidth: true; Layout.topMargin: theme.dp(7); implicitHeight: theme.dp(46)
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                model: root.backend.describe("gradient-mode").choices || []; textRole: "label"; valueRole: "value"
                currentIndex: model.findIndex(row => row.value === root.current("gradient-mode"))
                Accessible.name: qsTr("Gradient mode")
                onActivated: root.backend.stage("gradient-mode", currentValue)
            }
            Repeater {
                model: [{label: qsTr("Color"), option: "gradient-color"}, {label: qsTr("Cartoon"), option: "gradient-cartoon"}]
                RedesignSwitchRow {
                    required property var modelData
                    Layout.fillWidth: true
                    labelColor: theme.playerLabel
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    objectName: "videoGradientFlag_" + modelData.option
                    label: modelData.label; checked: root.enabledFilter("gradient") && !!root.current(modelData.option)
                    onToggled: checked => {
                        if (root.backend.stage(modelData.option, checked) && checked) root.effect("gradient", true)
                    }
                }
            }
            FilterSlider { objectName: "videoSepia"; Layout.topMargin: theme.dp(20); label: qsTr("Sepia Intensity"); optionName: "sepia-intensity"; from: 0; to: 255; stepSize: 1; ticks: [0, 85, 170, 255] }
        }
    }
    RedesignFilterSection {
        objectName: "videoGeometrySection"
        Layout.fillWidth: true; label: qsTr("Geometry")
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        settings: ColumnLayout {
            spacing: theme.dp(8)
            FilterSwitch { objectName: "videoInteractiveZoom"; label: qsTr("Interactive Zoom"); filterName: "magnify" }
            FilterSwitch { objectName: "videoPuzzle"; label: qsTr("Puzzle"); filterName: "puzzle" }
            ColumnLayout {
                objectName: "videoPuzzleOptions"
                Layout.fillWidth: true; visible: root.enabledFilter("puzzle"); spacing: theme.dp(12)
                NumberOption { objectName: "videoPuzzleRows"; label: qsTr("Rows"); optionName: "puzzle-rows"; from: 2; to: 42 }
                NumberOption { objectName: "videoPuzzleColumns"; label: qsTr("Columns"); optionName: "puzzle-cols"; from: 2; to: 42 }
                Option { optionName: "puzzle-mode"; label: qsTr("Game Mode") }
                Option { optionName: "puzzle-rotation"; label: qsTr("Piece Rotation") }
                NumberOption { label: qsTr("Border"); optionName: "puzzle-border"; suffix: " %"; to: 40 }
                Option { objectName: "videoPuzzlePreview"; optionName: "puzzle-preview"; label: qsTr("Preview") }
                ParameterSlider { label: qsTr("Preview Size"); optionName: "puzzle-preview-size"; from: 0; to: 100; suffix: " %"; stepSize: 1; enabled: !!root.current("puzzle-preview"); opacity: enabled ? 1 : .5 }
                ParameterSlider { label: qsTr("Piece Size"); optionName: "puzzle-shape-size"; from: 0; to: 100; suffix: " %"; stepSize: 1 }
                NumberOption { label: qsTr("Auto Shuffle"); optionName: "puzzle-auto-shuffle"; to: 30000 }
                NumberOption { label: qsTr("Auto Solve"); optionName: "puzzle-auto-solve"; to: 30000 }
            }
        }
    }
    RedesignFilterSection {
        objectName: "videoOverlaySection"
        Layout.fillWidth: true; label: qsTr("Overlay")
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        settings: ColumnLayout {
            spacing: theme.dp(8)
            OverlaySwitch { objectName: "videoTextOverlay"; label: qsTr("Text Overlay"); sourceName: "marq" }
            Option { objectName: "videoOverlayText"; optionName: "marq-marquee"; label: qsTr("Text"); presentation: ({compact: true, fullWidth: true}) }
            ColumnLayout {
                objectName: "videoTextOverlayOptions"
                Layout.fillWidth: true; visible: root.enabledFilter("marq", "sub-source"); spacing: theme.dp(10)
                Option { optionName: "marq-position"; label: qsTr("Position"); presentation: ({compact: true, choices: [{label: qsTr("Custom"), value: -1}].concat(root.backend.describe(optionName).choices || [])}) }
                NumberOption { label: qsTr("X Offset"); optionName: "marq-x"; suffix: " px" }
                NumberOption { label: qsTr("Y Offset"); optionName: "marq-y"; suffix: " px" }
                NumberOption { label: qsTr("Font Size"); optionName: "marq-size"; to: 4096; minimumValueText: qsTr("Auto"); suffix: " px" }
                Option { optionName: "marq-color"; label: qsTr("Text Color") }
                ParameterSlider {
                    objectName: "videoTextOpacity"
                    label: qsTr("Opacity"); optionName: "marq-opacity"; suffix: " %"
                    from: 0; to: 100; stepSize: 1
                    currentValue: Math.round(Number(root.current(optionName)) * 100 / 255)
                    valueFactor: 100 / 255
                }
                Option { objectName: "videoOverlayTextFile"; optionName: "marq-file"; label: qsTr("Text File"); presentation: ({compact: true, fullWidth: true}) }
                Text { Layout.fillWidth: true; text: qsTr("Keep the file path empty to use the text above."); color: theme.foreground; font.pixelSize: theme.dp(12); wrapMode: Text.WordWrap }
                NumberOption { label: qsTr("Timeout"); optionName: "marq-timeout"; suffix: " ms"; minimumValueText: qsTr("None") }
                NumberOption { label: qsTr("Refresh Interval"); optionName: "marq-refresh"; suffix: " ms" }
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: theme.dp(12); Layout.bottomMargin: theme.dp(12); height: theme.dp(1); color: theme.border }
            OverlaySwitch { objectName: "videoImageOverlay"; label: qsTr("Image Overlay"); sourceName: "logo" }
            Option { objectName: "videoOverlayImageFile"; optionName: "logo-file"; label: qsTr("Image File"); presentation: ({compact: true, fullWidth: true}) }
            ColumnLayout {
                objectName: "videoImageOverlayOptions"
                Layout.fillWidth: true; visible: root.enabledFilter("logo", "sub-source"); spacing: theme.dp(10)
                Option { optionName: "logo-position"; label: qsTr("Position"); presentation: ({compact: true, choices: [{label: qsTr("Custom"), value: -1}].concat(root.backend.describe(optionName).choices || [])}) }
                NumberOption { label: qsTr("X Offset"); optionName: "logo-x"; from: -1; minimumValueText: qsTr("Auto"); suffix: " px" }
                NumberOption { label: qsTr("Y Offset"); optionName: "logo-y"; from: -1; minimumValueText: qsTr("Auto"); suffix: " px" }
                ParameterSlider {
                    objectName: "videoImageOpacity"
                    label: qsTr("Opacity"); optionName: "logo-opacity"; suffix: " %"
                    from: 0; to: 100; stepSize: 1
                    currentValue: Math.round(Number(root.current(optionName)) * 100 / 255)
                    valueFactor: 100 / 255
                }
                NumberOption { label: qsTr("Image Delay"); optionName: "logo-delay"; suffix: " ms" }
                NumberOption { label: qsTr("Repeat"); optionName: "logo-repeat"; from: -1; minimumValueText: qsTr("Always") }
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: theme.dp(12); Layout.bottomMargin: theme.dp(12); height: theme.dp(1); color: theme.border }
            FilterSwitch { objectName: "videoErase"; label: qsTr("Logo Erase"); filterName: "erase" }
            ColumnLayout {
                Layout.fillWidth: true; visible: root.enabledFilter("erase"); spacing: theme.dp(10)
                Option { optionName: "erase-mask"; label: qsTr("Mask File"); presentation: ({compact: true, fullWidth: true}) }
                NumberOption { label: qsTr("X Offset"); optionName: "erase-x"; suffix: " px" }
                NumberOption { label: qsTr("Y Offset"); optionName: "erase-y"; suffix: " px" }
            }
        }
    }
    RedesignFilterSection {
        objectName: "videoAdvancedSection"
        Layout.fillWidth: true; label: qsTr("Advanced")
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        settings: ColumnLayout {
            spacing: theme.dp(8)
            RedesignSwitchRow {
                objectName: "videoGenerateHdr"
                Layout.fillWidth: true
                visible: root.supportsHdrPolicy("generate")
                labelColor: theme.playerLabel
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                label: qsTr("Generate HDR from SDR")
                checked: root.current("d3d11-hdr-mode") === "generate"
                onToggled: checked => root.backend.stage("d3d11-hdr-mode", checked ? "generate" : "auto")
            }
            RedesignModelChoice { Layout.fillWidth: true; scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; labelColor: theme.playerLabel; label: qsTr("Video Track"); choiceModel: root.videoTracksModel; onSelectionRequested: index => root.trackRequested(index) }
            RedesignModelChoice { Layout.fillWidth: true; scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; labelColor: theme.playerLabel; label: qsTr("Deinterlace"); choiceModel: root.deinterlaceModel; onSelectionRequested: index => root.deinterlaceRequested(index) }
            RedesignSwitchRow {
                Layout.fillWidth: true
                labelColor: theme.playerLabel
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                label: qsTr("Brightness Threshold"); checked: root.enabledFilter("adjust") && !!root.current("brightness-threshold")
                onToggled: checked => { if (root.backend.stage("brightness-threshold", checked) && checked) root.effect("adjust", true) }
            }
            FilterSwitch { label: qsTr("Motion Detect"); filterName: "motiondetect" }
            FilterSwitch { objectName: "videoMotionBlur"; label: qsTr("Motion Blur"); filterName: "motionblur" }
            ParameterSlider { objectName: "videoMotionBlurFactor"; label: qsTr("Blur Factor"); optionName: "blur-factor"; from: 1; to: 127; stepSize: 1; visible: root.enabledFilter("motionblur") }
            FilterSwitch { objectName: "videoGaussianBlur"; label: qsTr("Gaussian Blur"); filterName: "gaussianblur" }
            ParameterSlider { objectName: "videoGaussianSigma"; label: qsTr("Sigma"); optionName: "gaussianblur-sigma"; from: .01; to: 8; inputTo: 4096; stepSize: .01; decimals: 2; visible: root.enabledFilter("gaussianblur") }
            FilterSwitch { label: qsTr("Antiflicker"); filterName: "antiflicker" }
            ColumnLayout {
                Layout.fillWidth: true; visible: root.enabledFilter("antiflicker")
                ParameterSlider { label: qsTr("Window Size"); optionName: "antiflicker-window-size"; from: 0; to: 100; stepSize: 1 }
                ParameterSlider { label: qsTr("Softening Size"); optionName: "antiflicker-softening-size"; from: 0; to: 31; stepSize: 1 }
            }
            FilterSwitch { objectName: "videoDenoise"; label: qsTr("Denoise"); filterName: "hqdn3d" }
            ColumnLayout {
                Layout.fillWidth: true; visible: root.enabledFilter("hqdn3d")
                Repeater {
                    model: [{label: qsTr("Luma Spatial"), option: "hqdn3d-luma-spat"}, {label: qsTr("Chroma Spatial"), option: "hqdn3d-chroma-spat"}, {label: qsTr("Luma Temporal"), option: "hqdn3d-luma-temp"}, {label: qsTr("Chroma Temporal"), option: "hqdn3d-chroma-temp"}]
                    ParameterSlider { required property var modelData; label: modelData.label; optionName: modelData.option; from: 0; to: 10; inputTo: 254; stepSize: .1; decimals: 1 }
                }
            }
            FilterSwitch { label: qsTr("Mirror"); filterName: "mirror" }
            FilterSwitch { label: qsTr("Wave"); filterName: "wave" }
            FilterSwitch { label: qsTr("Ripple"); filterName: "ripple" }
            FilterSwitch { label: qsTr("Psychedelic"); filterName: "psychedelic" }
            FilterSwitch { label: qsTr("Anaglyph 3D"); filterName: "anaglyph" }
            Option { optionName: "anaglyph-scheme"; label: qsTr("Color Scheme"); visible: root.enabledFilter("anaglyph") }
        }
    }
}
