// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedAudio"
    width: 400; height: 1100
    visible: true; when: windowShown
    property real delaySeconds: 0
    property int stereoRequest: -1
    QtObject {
        id: store
        property int revision: 0
        property bool stereoTestRunning: false
        property string stereoTestMessage: ""
        property int stereoStarts: 0
        property int stereoStops: 0
        function startStereoTest() {
            stereoStarts++; stereoTestRunning = true; stereoTestMessage = "Left channel"
            return true
        }
        function stopStereoTest() {
            stereoStops++; stereoTestRunning = false; stereoTestMessage = ""
        }
        property var values: ({})
        property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        property bool supported: true
        property bool spatializerSupported: true
        property string lastOption
        property var lastValue
        function value(name) { return values[name] }
        function describe(name) {
            if (name === "filter:audio-filter:spatializer") return spatializerSupported ? {kind: "bool"} : {}
            if (name.endsWith("-track")) return {kind: "integer", editor: "track", maximum: 2147483647}
            if (name === "redesign-equalizer-preset") {
                if (!supported) return {}
                const choices = [{label: "None", value: ""}, {label: "Rock", value: "rock", curve: [4, 2, -2, -4, -1, 2, 4, 5, 5, 4]}]
                if (value(name) === "custom") choices.splice(1, 0, {label: "Custom", value: "custom", curve: gains})
                return {kind: "string", choices: choices}
            }
            return {kind: "string"}
        }
        function refresh() { revision++ }
        function stage(name, value) {
            lastOption = name; lastValue = value
            const next = Object.assign({}, values); next[name] = value; values = next; revision++
            return true
        }
        function equalizerBands() { return gains }
        function setEqualizerBand(index, gain) {
            const next = gains.slice(); next[index] = gain; gains = next
            stage("redesign-equalizer-preset", "custom")
            return true
        }
    }
    ListModel { id: stereoChoices }
    RedesignAudioSettings {
        id: audio
        width: 352; x: 24
        backend: store; stereoModel: stereoChoices
        audioDelaySeconds: testCase.delaySeconds
        onStereoRequested: index => testCase.stereoRequest = index
        onDelayRequested: seconds => {
            store.stage("audio-desync", Math.round(seconds * 1000))
            testCase.delaySeconds = seconds
        }
    }
    function item(name) { return findChild(audio, name) }
    function init() {
        audio.visible = true
        store.stereoTestRunning = false; store.stereoTestMessage = ""
        store.stereoStarts = 0; store.stereoStops = 0
        store.values = {"redesign-audio-track": 0, "redesign-audio-language": "Automatic", "redesign-equalizer-preset": "", "equalizer-2pass": false, "equalizer-preamp": 12}
        store.gains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]; store.supported = true; store.spatializerSupported = true; store.revision++
        store.lastOption = ""; store.lastValue = undefined
        delaySeconds = 0; stereoRequest = -1
        stereoChoices.clear(); stereoChoices.append({display: "Mono", checked: false}); stereoChoices.append({display: "Stereo", checked: true})
        item("inlineEqualizer").expanded = false
        wait(20)
    }
    function test_stereoTestUsesItsOwnStateAndKeepsPreferences() {
        const button = item("stereoTestButton")
        compare(button.caption, "Test")
        mouseClick(button)
        compare(store.stereoStarts, 1); compare(button.caption, "Stop")
        compare(item("stereoTestMessage").text, "Left channel")
        store.stereoTestMessage = "Right channel"
        compare(item("stereoTestMessage").text, "Right channel")
        compare(store.lastOption, ""); compare(stereoRequest, -1)
        mouseClick(button)
        compare(store.stereoStops, 1); compare(button.caption, "Test")
        verify(!item("stereoTestMessage").visible)
    }
    function test_hidingAudioStopsTheSoundTest() {
        mouseClick(item("stereoTestButton"))
        audio.visible = false
        compare(store.stereoStops, 1); verify(!store.stereoTestRunning)
        audio.visible = true
        verify(!store.stereoTestRunning)
    }
    function test_stereoTestSupportsKeyboardActivation() {
        const button = item("stereoTestButton")
        button.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(store.stereoTestRunning)
        keyClick(Qt.Key_Space)
        verify(!store.stereoTestRunning)
    }
    function test_zeroDelayHasNoActiveFill() {
        const control = findChild(item("audioDelaySetting"), "settingSlider")
        wait(20)
        const image = grabImage(testCase)
        for (const position of [0.25, 0.75]) {
            const point = control.mapToItem(testCase, position * control.width, control.height / 2)
            const x = Math.round(point.x), y = Math.floor(point.y)
            compare(image.red(x, y), 9)
            compare(image.green(x, y), 9)
            compare(image.blue(x, y), 9)
        }
    }
    function test_audioGroupsFollowReferenceOrder() {
        verify(item("defaultTrackSetting").mapToItem(audio, 0, 0).y < item("stereoModeHeading").y)
        verify(item("stereoModeSetting").y < item("audioSynchronizationHeading").y)
        verify(item("audioDelaySetting").y < item("audioFiltersHeading").y)
        verify(item("inlineEqualizerPreset").y < item("inlineEqualizer").y)
        verify(item("inlineEqualizer").y < item("inlineEqualizerTwoPass").y)
        verify(!item("inlineEqualizer").expanded)
        verify(item("inlineEqualizerTwoPass").y < item("inlineSpatializerSetting").y)
    }
    function test_stereoSelectorUsesFullPanelWidthAndNativeSelection() {
        const field = findChild(item("stereoModeSetting"), "modelChoiceField")
        compare(field.width, audio.width)
        compare(field.displayText, "Stereo")
        mouseClick(field); keyClick(Qt.Key_Up); keyClick(Qt.Key_Return)
        compare(stereoRequest, 0)
        stereoChoices.setProperty(1, "checked", false); stereoChoices.setProperty(0, "checked", true)
        compare(field.displayText, "Mono")
        stereoChoices.clear()
        verify(!field.enabled)
    }
    function test_delayHasSecondsTicksAndKeepsNativePrecision() {
        const delay = item("audioDelaySetting")
        compare(findChild(delay, "settingTick_0").text, "-10 s")
        compare(findChild(delay, "settingTick_1").text, "0 s")
        compare(findChild(delay, "settingTick_2").text, "10 s")
        const field = findChild(delay, "settingValueField")
        mouseClick(field); keyClick(Qt.Key_A, Qt.ControlModifier)
        for (const letter of "0.375") keyClick(letter)
        keyClick(Qt.Key_Return)
        compare(store.lastOption, "audio-desync"); compare(store.lastValue, 375)
        delaySeconds = 20.125
        compare(field.displayText, "20.125 s")
        compare(findChild(delay, "settingSlider").value, 10)
    }
    function test_presetChoiceStagesEffectAndShowsExternalChanges() {
        const preset = item("inlineEqualizerPreset")
        compare(preset.displayText, "None")
        mouseClick(preset); keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
        compare(store.lastOption, "redesign-equalizer-preset"); compare(store.lastValue, "rock")
        compare(preset.displayText, "Rock")
        store.stage("redesign-equalizer-preset", "")
        compare(preset.displayText, "None")
        verify(preset.showCurvePreviews)
    }
    function test_expansionAndCustomBandsStayInThePanel() {
        const equalizer = item("inlineEqualizer")
        mouseClick(findChild(equalizer, "equalizerExpander"))
        verify(equalizer.expanded)
        compare(equalizer.width, audio.width)
        const band = findChild(equalizer, "equalizerValue_1")
        band.text = "6.2"; band.editingFinished()
        compare(store.gains[0], 6.2); compare(store.gains[1], 0)
        compare(item("inlineEqualizerPreset").displayText, "Custom")
        mouseClick(findChild(equalizer, "equalizerExpander"))
        verify(!equalizer.expanded)
    }
    function test_twoPassControlTracksSavedValue() {
        const toggle = findChild(item("inlineEqualizerTwoPass"), "settingSwitch")
        mouseClick(toggle)
        compare(store.lastOption, "equalizer-2pass"); compare(store.lastValue, true)
        store.stage("equalizer-2pass", false)
        verify(!toggle.checked)
    }
    function test_unavailableSpatializerDoesNotShowEditors() {
        verify(item("inlineSpatializerSetting").visible)
        store.spatializerSupported = false; store.revision++
        verify(!item("inlineSpatializerSetting").visible)
    }
    function test_unavailableEqualizerDoesNotShowEditors() {
        store.supported = false; store.revision++
        verify(!item("inlineEqualizerPreset").visible)
        verify(!item("inlineEqualizer").visible)
        verify(!item("inlineEqualizerTwoPass").visible)
    }
}
