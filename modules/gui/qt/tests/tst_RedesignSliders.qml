// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedSliderOrigins"
    width: 800; height: 620
    visible: true; when: windowShown
    property bool light: false
    property bool mirrored: false

    QtObject {
        id: store
        property int revision: 0
        property real gain: 0
        property real minimum: -20
        property real maximum: 20
        function describe(name) { return {kind: "float", minimum, maximum} }
        function value(name) { return name === "equalizer-vlcfreqs" ? true : gain }
        function stage(name, value) { gain = value; revision++; return true }
        function equalizerBands() { return [gain, gain, gain, gain, gain, gain, gain, gain, gain, gain] }
        function setEqualizerBand(index, value) { return stage("band", value) }
    }
    RedesignSettingSlider {
        id: setting
        x: 20; y: 20; width: 700
        label: "Hue"; from: -20; to: 20; currentValue: store.gain
        resetValue: 0; stepSize: 1
        lightTheme: testCase.light; accentColor: "#19a234"
        LayoutMirroring.enabled: testCase.mirrored
        LayoutMirroring.childrenInherit: true
        onMoved: value => store.stage("gain", value)
    }
    RedesignPreferenceRow {
        id: preference
        x: 20; y: 145; width: 700
        backend: store; optionName: "gain"; label: "Gain"
        presentation: ({editor: "slider", step: 1})
        lightTheme: testCase.light; accentColor: "#19a234"
        LayoutMirroring.enabled: testCase.mirrored
        LayoutMirroring.childrenInherit: true
    }
    RedesignEqualizer {
        id: equalizer
        x: 20; y: 240; width: 740
        backend: store; expanded: true; compact: true
        lightTheme: testCase.light; accentColor: "#19a234"
    }

    function init() {
        light = false; mirrored = false
        store.stage("gain", 0)
        setting.from = -20; setting.to = 20
        store.minimum = -20; store.maximum = 20
        mouseMove(testCase, 790, 610)
    }
    function checkPixel(item, horizontal, fraction, color) {
        const point = item.mapToItem(testCase,
            item.width * (horizontal ? fraction : 0.5),
            item.height * (horizontal ? 0.5 : fraction))
        const image = grabImage(testCase)
        const x = Math.round(point.x), y = Math.round(point.y)
        const expected = Qt.color(color)
        verify(Math.abs(image.red(x, y) - Math.round(expected.r * 255)) <= 1
            && Math.abs(image.green(x, y) - Math.round(expected.g * 255)) <= 1
            && Math.abs(image.blue(x, y) - Math.round(expected.b * 255)) <= 1,
            "Unexpected pixel at " + x + "," + y + "; expected " + color
            + ", got " + image.red(x, y) + "," + image.green(x, y) + "," + image.blue(x, y))
    }
    function test_fillStartsAtZero_data() {
        const rows = []
        for (const light of [false, true]) {
            for (const mirrored of [false, true]) {
                for (const gain of [-20, -10, 0, 10, 20])
                    rows.push({tag: light + "-" + mirrored + "-" + gain, light, mirrored, gain})
            }
        }
        return rows
    }
    function test_fillStartsAtZero(data) {
        light = data.light; mirrored = data.mirrored
        store.stage("gain", data.gain)
        wait(30)
        const controls = [findChild(setting, "settingSlider"), findChild(preference, "preferenceSliderEditor")]
        for (const slider of controls) {
            for (const fraction of [0.125, 0.375, 0.625, 0.875]) {
                const logical = mirrored ? 1 - fraction : fraction
                const value = -20 + logical * 40
                const filled = value < 0 ? data.gain < value : data.gain > value
                checkPixel(slider.background, true, fraction, filled ? setting.theme.progress : setting.theme.field)
            }
        }
        // All ten bands and the preamp use the same zero point.
        for (let index = 0; index < 11; ++index) {
            const slider = findChild(equalizer, "equalizerSlider_" + index)
            for (const fraction of [0.125, 0.375, 0.625, 0.875]) {
                const value = 20 - fraction * 40
                const filled = value < 0 ? data.gain < value : data.gain > value
                checkPixel(slider.background, false, fraction, filled ? setting.theme.progress : setting.theme.field)
            }
        }
    }
    function test_positiveRangeStillStartsAtMinimum() {
        setting.from = 0; setting.to = 20
        store.minimum = 0; store.maximum = 20
        store.stage("gain", 10)
        wait(30)
        for (const slider of [findChild(setting, "settingSlider"), findChild(preference, "preferenceSliderEditor")]) {
            checkPixel(slider.background, true, 0.125, setting.theme.progress)
            checkPixel(slider.background, true, 0.875, setting.theme.field)
        }
    }
    function test_asymmetricRangeStartsAtZero() {
        setting.from = -10; setting.to = 30
        store.minimum = -10; store.maximum = 30
        store.stage("gain", 10)
        wait(30)
        for (const slider of [findChild(setting, "settingSlider"), findChild(preference, "preferenceSliderEditor")]) {
            checkPixel(slider.background, true, 0.125, setting.theme.field)
            checkPixel(slider.background, true, 0.375, setting.theme.progress)
            checkPixel(slider.background, true, 0.625, setting.theme.field)
        }
    }
    function test_keyboardCanCrossZero() {
        const controls = [findChild(setting, "settingSlider"), findChild(preference, "preferenceSliderEditor"),
            findChild(equalizer, "equalizerSlider_1")]
        for (const slider of controls) {
            const step = slider.stepSize
            store.stage("gain", -step)
            slider.forceActiveFocus()
            const increase = slider.orientation === Qt.Vertical ? Qt.Key_Up : Qt.Key_Right
            const decrease = slider.orientation === Qt.Vertical ? Qt.Key_Down : Qt.Key_Left
            keyClick(increase)
            verify(Math.abs(store.gain) < 0.00001)
            keyClick(increase)
            verify(Math.abs(store.gain - step) < 0.00001)
            keyClick(decrease); keyClick(decrease)
            verify(Math.abs(store.gain + step) < 0.00001)
        }
    }
}
