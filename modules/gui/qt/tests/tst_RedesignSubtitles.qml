// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedSubtitles"
    width: 400; height: 1250
    property bool mirrored: false
    LayoutMirroring.enabled: mirrored
    LayoutMirroring.childrenInherit: true
    visible: true; when: windowShown
    QtObject {
        id: store
        property int revision: 0
        property var values: ({})
        property string lastName
        property var lastValue
        function value(name) { return values[name] }
        function describe(name) {
            if (name.endsWith("-track")) return {kind: "integer", editor: "track", maximum: 2147483647}
            if (name.endsWith("-language") || name === "freetype-font") return {kind: "string"}
            if (name === "sub-text-use-embedded-style") return {kind: "bool"}
            if (name.endsWith("-color")) return {kind: "integer", editor: "color"}
            return {kind: "float", minimum: 0, maximum: 20}
        }
        function stage(name, value) {
            lastName = name; lastValue = value
            const next = Object.assign({}, values); next[name] = value; values = next; revision++
            return true
        }
        function chooseColor(initial) { return "#FF1122" }
    }
    RedesignSubtitleSettings {
        id: subtitles
        x: 24; y: 24; width: 356
        backend: store
        subtitleDelaySeconds: Number(store.value("redesign-subtitle-delay")) / 1000
        subtitleFPS: Number(store.value("sub-fps"))
        onDelayRequested: seconds => store.stage("redesign-subtitle-delay", Math.round(seconds * 1000))
        onFpsRequested: fps => store.stage("sub-fps", fps)
    }
    function item(name) { return findChild(subtitles, name) }
    function slider(name) { return findChild(item(name), "settingSlider") }
    function field(name) { return findChild(item(name), "settingValueField") }
    function init() {
        mirrored = false
        subtitles.liveSizeMode = -1; subtitles.liveTextScale = undefined; subtitles.livePixelSize = undefined
        store.values = {"redesign-sub-track": 1, "redesign-sub-language": "English", "redesign-subtitle-delay": -4000,
            "sub-fps": 1, "redesign-subtitle-duration": 0, "sub-text-use-embedded-style": false,
            "freetype-font": "Inter", "freetype-color": 0xb8b8b8, "freetype-outline-color": 0x0c0c0c,
            "sub-margin": 0, "sub-text-size-mode": 0, "sub-text-scale": 100, "sub-text-size-pixels": 30,
            "freetype-outline-thickness": 4, "freetype-background-opacity": 0}
        store.lastName = ""; store.revision++; wait(10)
    }
    function test_delayFillRunsBetweenZeroAndTheSelectedTime_data() {
        return [
            {tag: "negative", delay: -4000, mirrored: false},
            {tag: "zero", delay: 0, mirrored: false},
            {tag: "positive", delay: 4000, mirrored: false},
            {tag: "negative-rtl", delay: -4000, mirrored: true},
            {tag: "zero-rtl", delay: 0, mirrored: true},
            {tag: "positive-rtl", delay: 4000, mirrored: true}
        ]
    }
    function test_delayFillRunsBetweenZeroAndTheSelectedTime(data) {
        mirrored = data.mirrored
        store.stage("redesign-subtitle-delay", data.delay)
        const control = slider("subtitleDelaySetting")
        tryCompare(control, "mirrored", data.mirrored)
        wait(30)
        const image = grabImage(testCase)
        const samples = [
            {position: 0.15, filled: false},
            {position: 0.4, filled: data.delay < 0},
            {position: 0.6, filled: data.delay > 0},
            {position: 0.85, filled: false}
        ]
        for (const sample of samples) {
            const position = data.mirrored ? 1 - sample.position : sample.position
            const point = control.mapToItem(testCase, position * control.width, control.height / 2)
            const x = Math.round(point.x), y = Math.floor(point.y)
            const expected = Qt.color(sample.filled ? "#371f06" : "#090909")
            verify(Math.abs(image.red(x, y) - Math.round(expected.r * 255)) <= 1, "Delay fill red at " + sample.position + ": got " + image.red(x, y) + ", image " + image.width + "x" + image.height)
            verify(Math.abs(image.green(x, y) - Math.round(expected.g * 255)) <= 1, "Delay fill green at " + sample.position)
            verify(Math.abs(image.blue(x, y) - Math.round(expected.b * 255)) <= 1, "Delay fill blue at " + sample.position)
        }
    }
    function test_completeReferenceOrderAndScaleLabels() {
        const names = ["defaultTrackSetting", "defaultLanguageSetting", "subtitleSynchronizationHeading",
            "subtitleDelaySetting", "subtitleFPSControl", "subtitleDurationSetting", "subtitleAppearanceHeading",
            "subtitleAppearance_sub-text-use-embedded-style", "subtitleAppearance_freetype-font", "subtitleAppearance_freetype-color",
            "subtitleAppearance_freetype-outline-color", "subtitleAppearance_sub-margin", "subtitleSizeModeSetting",
            "subtitleFontSizeSetting", "subtitleOutlineThicknessSetting", "subtitleBackgroundOpacitySetting"]
        let previous = -1
        for (const name of names) {
            const row = item(name); verify(row !== null, name)
            const y = row.mapToItem(subtitles, 0, 0).y; verify(y > previous, name); previous = y
        }
        compare(findChild(item("subtitleDelaySetting"), "settingTick_1").text, "0 s")
        compare(findChild(item("subtitleDelaySetting"), "settingTick_2").text, "+10 s")
        verify(!findChild(item("subtitleFPSControl"), "settingResetButton").visible)
        verify(!findChild(item("subtitleDurationSetting"), "settingResetButton").visible)
        compare(item("subtitleFontSizeSetting").valueLabel, "Auto")
        compare(item("subtitleOutlineThicknessSetting").valueLabel, "Normal")
    }
    function test_timingKeepsNativePrecisionAndExtendedRange() {
        const delay = field("subtitleDelaySetting")
        mouseClick(delay); keyClick(Qt.Key_A, Qt.ControlModifier)
        for (const character of "-3.975") keyClick(character)
        keyClick(Qt.Key_Return)
        compare(store.value("redesign-subtitle-delay"), -3975)
        compare(field("subtitleFPSControl").stepSize, 1)
        verify(field("subtitleFPSControl").to > 60000)
        slider("subtitleDurationSetting").forceActiveFocus(); keyClick(Qt.Key_End)
        compare(store.lastName, "redesign-subtitle-duration"); compare(store.lastValue, 20)
    }
    function test_relativeAndPixelsKeepSeparateValuesAndFullNativeRange() {
        mouseClick(item("subtitleSizePixels"))
        compare(store.lastName, "sub-text-size-mode"); compare(store.lastValue, 1)
        compare(item("subtitleFontSizeSetting").valueLabel, "30 px")
        slider("subtitleFontSizeSetting").forceActiveFocus(); keyClick(Qt.Key_Right)
        compare(store.lastName, "sub-text-size-pixels"); compare(store.lastValue, 31)
        keyClick(Qt.Key_End); compare(store.lastValue, 500)
        mouseClick(item("subtitleSizeRelative"))
        compare(item("subtitleFontSizeSetting").valueLabel, "Auto")
        slider("subtitleFontSizeSetting").forceActiveFocus(); keyClick(Qt.Key_Left)
        compare(store.lastName, "sub-text-scale"); compare(store.lastValue, 99)
        keyClick(Qt.Key_Home); compare(store.lastValue, 10)
        keyClick(Qt.Key_End); compare(store.lastValue, 500)
        compare(store.value("sub-text-size-pixels"), 500)
    }
    function test_outlineAndOpacityUseNativeValues() {
        slider("subtitleOutlineThicknessSetting").forceActiveFocus(); keyClick(Qt.Key_Right)
        compare(store.lastName, "freetype-outline-thickness"); compare(store.lastValue, 5)
        keyClick(Qt.Key_End); compare(store.lastValue, 50)
        slider("subtitleBackgroundOpacitySetting").forceActiveFocus(); keyClick(Qt.Key_End)
        compare(store.lastName, "freetype-background-opacity"); compare(store.lastValue, 255)
        keyClick(Qt.Key_Home); compare(store.lastValue, 0)
        keyClick(Qt.Key_Right); compare(store.lastValue, 3)
        keyClick(Qt.Key_Right); compare(store.lastValue, 5)
        compare(item("subtitleBackgroundOpacitySetting").valueLabel, "2 %")
    }
    function test_embeddedFormattingKeepsFallbackAppearanceEditable() {
        mouseClick(findChild(item("subtitleAppearance_sub-text-use-embedded-style"), "preferenceToggleEditor"))
        verify(store.value("sub-text-use-embedded-style"))
        verify(item("subtitleEmbeddedStyleHelp").visible)
        verify(item("subtitleAppearance_freetype-font").editorEnabled)
        verify(item("subtitleAppearance_freetype-color").editorEnabled)
        verify(item("subtitleAppearance_freetype-outline-color").editorEnabled)
        verify(item("subtitleOutlineThicknessSetting").enabled)
        verify(item("subtitleBackgroundOpacitySetting").enabled)
        verify(item("subtitleAppearance_sub-margin").editorEnabled)
        verify(item("subtitleFontSizeSetting").enabled)
        slider("subtitleOutlineThicknessSetting").forceActiveFocus(); keyClick(Qt.Key_End)
        compare(store.lastName, "freetype-outline-thickness"); compare(store.lastValue, 50)
        slider("subtitleBackgroundOpacitySetting").forceActiveFocus(); keyClick(Qt.Key_End)
        compare(store.lastName, "freetype-background-opacity"); compare(store.lastValue, 255)
        verify(store.value("sub-text-use-embedded-style"))
        mouseClick(findChild(item("subtitleAppearance_sub-text-use-embedded-style"), "preferenceToggleEditor"))
        verify(!item("subtitleEmbeddedStyleHelp").visible)
        verify(item("subtitleOutlineThicknessSetting").enabled)
    }
    function test_liveSizingShowsShortcutValuesWithoutChangingSavedDefaults() {
        subtitles.liveTextScale = 130
        compare(item("subtitleFontSizeSetting").valueLabel, "130 %")
        compare(store.value("sub-text-scale"), 100)
        subtitles.liveSizeMode = 1; subtitles.livePixelSize = 47
        compare(item("subtitleFontSizeSetting").valueLabel, "47 px")
        compare(store.value("sub-text-size-pixels"), 30)
        subtitles.liveSizeMode = -1; subtitles.liveTextScale = undefined
        compare(item("subtitleFontSizeSetting").valueLabel, "Auto")
    }
}
