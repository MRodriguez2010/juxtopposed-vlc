// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedPreferences"
    width: 900; height: 600
    when: windowShown
    visible: true
    QtObject { id: shortcuts; property bool useGlobalShortcuts: true }
    QtObject {
        id: store
        property int revision: 0
        property int refreshCount: 0
        property var values: ({resize: true, fastSeek: false, timeout: 1800})
        property QtObject ctx: shortcuts
        property bool invalidLanguage: false
        property string providedHelp: ""
        function cancelLanguageEdit(name) { invalidLanguage=false;revision++ }
        function value(name) { return values[name] }
        function refresh() { refreshCount++; revision++ }
        function describe(name) {
            if (name.endsWith("-track")) return {kind: "integer", editor: "track", maximum: 2147483647}
            if (name.endsWith("-language")) return {kind: "string", editor: "language", choices: [
                {label:"System language",value:"system"},{label:"Automatic",value:""},
                {label:"English",value:"en"},{label:"French",value:"fr"},{label:"Creoles, English based",value:"cpe"},{label:"Custom…",value:"__custom__"}]}
            if (name === "folderAction") return {kind: "action", editor: "action", buttonLabel: "Open"}
            if (name === "audio-spatial-mode") return {kind: "integer", title: "Spatial audio mode", choices: [{label: "Headphone virtualization", value: 2}, {label: "Surround speakers", value: 0}]}
            if (name === "volumeStep") return {kind: "float", title: "Volume step", choices: []}
            if (name === "device") return {kind: "string", title: "Output device", choices: [{label: "System default", value: ""}, {label: "Headphones", value: "native-headphones"}]}
            return {kind: name === "timeout" ? "integer" : name === "clickPolicy" ? "string" : "bool", title: name, help: providedHelp, choices: []}
        }
        function stage(name, value) {
            if (name.endsWith("-language") && value==="invalid") { invalidLanguage=true;return false }
            if (name === "redesign-startup-volume") {
                const number = Number(value)
                if (!String(value).trim().length || !Number.isInteger(number) || number < 0 || number > 300) return false
                value = number
            }
            const next = Object.assign({}, values)
            next[name] = value
            values = next
            revision++
            return true
        }
        function reset(name) { stage(name, name === "timeout" ? 1800 : name === "resize") }
    }
    QtObject {
        id: equalizerStore
        property int revision: 0
        property var gains: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        property real preamp: 12
        function equalizerBands() { return gains }
        function value(name) { return name === "equalizer-preamp" ? preamp : true }
        function stage(name, gain) { if (name === "equalizer-preamp") preamp = gain; revision++; return true }
        function setEqualizerBand(index, gain) { const next = gains.slice(); next[index] = gain; gains = next; revision++; return true }
    }
    RedesignEqualizer {
        id: equalizer
        x: 0; y: 80; width: 784
        backend: equalizerStore
        visible: false
    }
    RedesignPreferencesCatalog { id: catalog }
    QtObject {
        id: subtitleService
        property bool configured: true
        property bool hasConsumerKey: true
        property bool hasCustomKey: false
        property bool preparing: false
        property string submittedKey: ""
        function setApiKey(key) { if (key === "invalid") return false; submittedKey = key; hasCustomKey = true; configured = true; return true }
        function clearApiKey() { submittedKey = ""; hasCustomKey = false; configured = hasConsumerKey; return true }
    }
    RedesignSubtitleSourcePreferences {
        id: subtitlePreferences
        sourceService: subtitleService
        width: parent.width; y: 20; visible: false
    }
    function test_subtitleProviderSetupAndConsumerFallback() {
        subtitlePreferences.visible = true
        mouseClick(findChild(subtitlePreferences,"subtitleProviderConfigure"))
        const setup=findChild(subtitlePreferences,"subtitlePreferencesProviderSetup")
        tryCompare(setup,"opened",true)
        const field=findChild(setup,"subtitleProviderApiKey")
        verify(field.echoMode!==TextInput.Normal)
        field.text="invalid"
        mouseClick(findChild(setup,"subtitleProviderSaveKey"))
        verify(setup.errorMessage.length>0);verify(setup.visible);verify(!subtitleService.hasCustomKey)
        field.text="test-user-key"
        mouseClick(findChild(setup,"subtitleProviderSaveKey"))
        tryCompare(setup,"visible",false);compare(field.text,"");verify(subtitleService.hasCustomKey)
        mouseClick(findChild(subtitlePreferences,"subtitleProviderConfigure"));tryCompare(setup,"opened",true)
        mouseClick(findChild(setup,"subtitleProviderRemoveKey"))
        tryCompare(setup,"visible",false);verify(!subtitleService.hasCustomKey);verify(subtitleService.configured)
        subtitlePreferences.visible=false
    }
    RedesignTrackDefaults {
        id: defaults
        width: 352; y: 450; backend: store
        visible: false
    }
    Column {
        width: parent.width
        RedesignPreferenceRow {
            id: resizeRow
            width: parent.width; backend: store; optionName: "resize"
            label: "Resize window to fit video"
            presentation: ({choices: [{label: "Never", value: false}, {label: "Always", value: true}]})
        }
        RedesignPreferenceRow {
            id: seekRow
            width: parent.width; backend: store; optionName: "fastSeek"
            label: "Seek precisely"; presentation: ({inverted: true})
        }
        RedesignPreferenceRow {
            id: delayRow
            width: parent.width; backend: store; optionName: "timeout"
            label: "Hide after"
            presentation: ({editor: "slider", from: 0, to: 10, factor: 0.001, step: 0.1, suffix: " s"})
        }
    }
    RedesignPreferenceRow {
        id: timingTextRow
        y: 160; width: parent.width; backend: store; optionName: "timeout"
        label: "Popup duration"
        presentation: ({factor: 0.001, suffix: " s"})
    }
    RedesignPreferenceRow {
        id: clickPolicyRow
        y: 230; width: parent.width; backend: store; optionName: "clickPolicy"
        label: "Single click on the video"
        presentation: catalog.sections.controls.find(section => section.title === "Mouse").rows[0][2]
    }
    RedesignPreferenceRow {
        id: remotePortRow
        y: 290; width: parent.width; backend: store; optionName: "timeout"
        label: "Port"; presentation: ({enabledWhen: "resize"})
    }
    RedesignStartupVolume {
        id: startupVolume
        y: 350; width: 320
        backend: store
        visible: false
    }
    RedesignPreferenceRow {
        id: deviceRow
        y: 350; width: parent.width
        backend: store; optionName: "device"; label: "Output device"
        presentation: ({dynamicChoices: true})
        visible: false
    }
    RedesignPreferenceRow {
        id: actionRow
        y: 350; width: parent.width
        backend: store; optionName: "folderAction"; label: "Open configurations folder"
        visible: false
    }
    SignalSpy { id: actionSpy; target: actionRow; signalName: "actionRequested" }
    property bool passthroughTestActive: false
    QtObject {
        id: passthroughStore
        property int revision: 0
        property string driver: "mmdevice"
        property var currentValue: false
        property var lastValue
        function value(name) { return currentValue }
        function stage(name, value) { lastValue = value; currentValue = value; revision++; return true }
        function describe(name) {
            if (driver === "automatic") return {}
            if (driver === "mmdevice") return {kind: "bool", defaultValue: false, choices: []}
            return {kind: "integer", defaultValue: 0, minimum: 0, maximum: 2,
                choices: [{label: "None", value: 0}, {label: "S/PDIF", value: 1}, {label: "HDMI", value: 2}]}
        }
    }
    RedesignPreferenceRow {
        id: passthroughRow
        y: 350; width: parent.width
        backend: passthroughStore; optionName: "redesign-audio-passthrough"
        label: "Pass compressed audio to the receiver"
        presentation: catalog.advancedSections.audio[0].rows.find(row => row[0] === passthroughRow.optionName)?.[2] || ({})
        visible: available && testCase.passthroughTestActive
    }
    RedesignPreferenceRow {
        id: spatialModeRow
        y: 350; width: parent.width
        backend: store; optionName: "audio-spatial-mode"; label: "Spatial audio mode"
        presentation: ({enabledWhen: "audio-spatial"})
        visible: false
    }
    RedesignPreferenceRow {
        id: volumeStepRow
        y: 430; width: parent.width
        backend: store; optionName: "volumeStep"; label: "Volume step"
        presentation: ({factor: 100 / 256, decimals: 1, suffix: "%"})
        visible: false
    }
    RedesignShortcutEditor {
        id: shortcutEditor
        parent: testCase
        shortcuts: [{name: "key-toggle-fullscreen", globalName: "global-key-toggle-fullscreen", title: "Toggle fullscreen", group: "Basic"},
            {name: "key-play-pause", globalName: "global-key-play-pause", title: "Play / pause", group: "Playback"}]
        values: ({"key-toggle-fullscreen": "f", "key-play-pause": "Space"})
        dirty: true
        onCancelRequested: close()
        onSaveRequested: close()
    }
    SignalSpy { id: captureSpy; target: shortcutEditor; signalName: "captureRequested" }
    SignalSpy { id: cancelSpy; target: shortcutEditor; signalName: "cancelRequested" }
    SignalSpy { id: saveSpy; target: shortcutEditor; signalName: "saveRequested" }
    RedesignConfirmationDialog {
        id: confirmation
        parent: testCase
        title: "Reset all settings"
        message: "This action replaces all VLC settings with the default settings."
        confirmText: "Reset"; destructive: true
    }
    SignalSpy { id: confirmationAccepted; target: confirmation; signalName: "accepted" }
    SignalSpy { id: confirmationRejected; target: confirmation; signalName: "rejected" }
    function init() {
        passthroughTestActive = false
        passthroughStore.driver = "mmdevice"; passthroughStore.currentValue = false; passthroughStore.revision++
        store.providedHelp = ""
        defaults.visible = false; defaults.subtitles = false
        confirmation.close(); confirmationAccepted.clear(); confirmationRejected.clear()
        actionRow.visible = false; actionSpy.clear()
        shortcutEditor.close()
        startupVolume.visible = false; deviceRow.visible = false; volumeStepRow.visible = false; spatialModeRow.visible = false; store.refreshCount = 0
        equalizer.visible = false; equalizer.expanded = false
        equalizerStore.gains = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]; equalizerStore.preamp = 12; equalizerStore.revision++
        captureSpy.clear(); cancelSpy.clear(); saveSpy.clear()
        store.values = {resize: true, fastSeek: false, timeout: 1800, clickPolicy: "auto", "volume-save": true, "redesign-startup-volume": 200, device: "", volumeStep: 12.800000190734863, "audio-spatial": false, "audio-spatial-mode": 2}
        store.revision++
        wait(20)
    }
    function test_passthroughEditorUsesCurrentDriverMetadata() {
        passthroughTestActive = true
        let toggle = findChild(passthroughRow, "preferenceToggleEditor")
        verify(toggle !== null)
        mouseClick(toggle)
        compare(passthroughStore.lastValue, true)
        passthroughStore.driver = "alsa"; passthroughStore.currentValue = 2; passthroughStore.revision++
        tryVerify(() => findChild(passthroughRow, "preferenceChoiceEditor") !== null)
        const choice = findChild(passthroughRow, "preferenceChoiceEditor")
        compare(choice.currentValue, 2)
        choice.currentIndex = 1; choice.activated(1)
        compare(passthroughStore.lastValue, 1)
        passthroughStore.driver = "automatic"; passthroughStore.revision++
        tryCompare(passthroughRow, "visible", false)
        passthroughStore.driver = "mmdevice"; passthroughStore.currentValue = false; passthroughStore.revision++
        tryCompare(passthroughRow, "visible", true)
        toggle = findChild(passthroughRow, "preferenceToggleEditor")
        verify(toggle !== null); verify(!toggle.checked)
    }
    function editTrack(text) {
        const field = findChild(defaults, "preferenceTrackEditor")
        mouseClick(field)
        keyClick(Qt.Key_A, Qt.ControlModifier)
        for (const letter of text) keyClick(letter)
        keyClick(Qt.Key_Return)
    }
    function test_defaultTrackHasAutomaticAndOneBasedNumbers() {
        store.stage("redesign-audio-track", 0)
        defaults.visible = true
        const field = findChild(defaults, "preferenceTrackEditor")
        compare(field.displayText, "Automatic")
        editTrack("1")
        compare(store.value("redesign-audio-track"), 1)
        editTrack("2.5")
        compare(store.value("redesign-audio-track"), 1)
        editTrack("-1")
        compare(store.value("redesign-audio-track"), 1)
        editTrack("Automatic")
        compare(store.value("redesign-audio-track"), 0)
        store.stage("redesign-audio-track", 3)
        compare(field.displayText, "3")
    }
    function test_subtitleDefaultsUseTheirOwnPreferences() {
        store.stage("redesign-audio-track", 1)
        store.stage("redesign-sub-track", 2)
        store.stage("redesign-sub-language", "fr")
        defaults.subtitles = true; defaults.visible = true
        compare(findChild(defaults, "preferenceTrackEditor").displayText, "2")
        const language = findChild(defaults, "preferenceChoiceEditor")
        compare(language.currentText, "French")
        editTrack("3")
        compare(store.value("redesign-sub-track"), 3)
        compare(store.value("redesign-audio-track"), 1)
        language.activated(2)
        compare(store.value("redesign-sub-language"), "en")
    }
    function test_languageOrderCanBeEditedAndCanceled() {
        defaults.subtitles=true;defaults.visible=true;store.stage("redesign-sub-language","system")
        const choice=findChild(defaults,"preferenceChoiceEditor")
        compare(choice.currentText,"System language")
        tryVerify(() => !choice.contentItem.truncated)
        choice.activated(choice.model.findIndex(row=>row.value==="__custom__"))
        const field=findChild(defaults,"preferenceLanguageOrderEditor");verify(field.visible)
        field.text="ja,en";mouseClick(findChild(defaults,"languageOrderCancel"))
        compare(store.value("redesign-sub-language"),"system");verify(choice.visible);compare(choice.currentText,"System language")
        choice.activated(choice.model.findIndex(row=>row.value==="__custom__"));field.text="en,ja";field.accepted()
        compare(store.value("redesign-sub-language"),"en,ja");verify(choice.visible)
        choice.activated(choice.model.findIndex(row=>row.value==="__custom__"));field.text="invalid";field.accepted()
        verify(field.invalid);verify(store.invalidLanguage)
        mouseClick(findChild(defaults,"languageOrderCancel"));verify(!store.invalidLanguage)
        compare(store.value("redesign-sub-language"),"en,ja")
    }
    function test_languageSearchSelectsTheOriginalValue() {
        defaults.subtitles=true;defaults.visible=true;store.stage("redesign-sub-language","system")
        const choice=findChild(defaults,"preferenceChoiceEditor")
        mouseClick(choice)
        const popup=findChild(defaults,"languageChoicePopup");tryCompare(popup,"opened",true)
        verify(!shortcuts.useGlobalShortcuts)
        const search=findChild(defaults,"languageChoiceSearch");search.text="French"
        compare(popup.entries.length,1);compare(popup.entries[0].value,"fr")
        search.text="English";compare(popup.entries.length,2);compare(popup.entries[0].value,"en")
        search.text="French"
        search.accepted();compare(store.value("redesign-sub-language"),"fr");tryCompare(popup,"visible",false);verify(shortcuts.useGlobalShortcuts)
        mouseClick(choice);tryCompare(popup,"opened",true);search.text="not a language"
        compare(popup.entries.length,0);search.accepted();verify(popup.visible)
        popup.close()
    }
    function test_helpIconFollowsNativeMetadataAndCompactPresentation() {
        const icon = findChild(resizeRow, "preferenceHelpIcon")
        verify(icon); verify(!icon.visible)
        store.providedHelp = "Help from the native setting."
        verify(icon.visible)
        compare(findChild(resizeRow, "redesignToolTip").text, store.providedHelp)
        const previous = resizeRow.presentation
        resizeRow.presentation = Object.assign({}, previous, {compact: true})
        verify(!icon.visible)
        resizeRow.presentation = previous
        store.providedHelp = ""; verify(!icon.visible)
    }
    function test_advancedAudioSeparatesQualityFromResampler() {
        const section = catalog.advancedSections.audio[0]
        compare(section.title, "")
        compare(section.rows.slice(0, 4).map(row => row[1]).join("|"),
            "Pass compressed audio to the receiver|Detect Dolby Surround|Resampling quality|Media role")
        compare(section.rows[1][2].choiceLabels[0], "Automatic")
        const quality = catalog.find("Resampling quality")
        compare(quality.length, 1)
        compare(quality[0].name, "redesign-resampling-quality")
        verify(quality[0].presentation.dynamicChoices)
        const resampler = catalog.find("Resampler").find(row => row.name === "audio-resampler")
        verify(resampler)
        compare(resampler.title, "Resampler")
    }
    function test_volumeStepUsesPercentagePoints() {
        volumeStepRow.visible = true
        const field = findChild(volumeStepRow, "preferenceTextEditor")
        compare(field.text, "5.0")
        field.text = "2"; field.editingFinished()
        fuzzyCompare(store.value("volumeStep"), 5.12, 0.000001)
    }
    function test_confirmationDefaultsToCancel() {
        confirmation.open()
        tryCompare(confirmation, "opened", true)
        const cancel = findChild(confirmation.contentItem, "confirmationCancel")
        tryCompare(cancel, "activeFocus", true)
        keyClick(Qt.Key_Return)
        compare(confirmationAccepted.count, 0)
        compare(confirmationRejected.count, 1)
        tryCompare(confirmation, "opened", false)
    }
    function test_confirmationRequiresResetAction() {
        confirmation.open()
        tryCompare(confirmation, "opened", true)
        mouseClick(findChild(confirmation.contentItem, "confirmationAccept"))
        compare(confirmationAccepted.count, 1)
        compare(confirmationRejected.count, 0)
        tryCompare(confirmation, "opened", false)
        confirmation.open()
        tryCompare(confirmation, "opened", true)
        keyClick(Qt.Key_Escape)
        tryCompare(confirmation, "opened", false)
        compare(confirmationAccepted.count, 1)
    }
    function test_actionButtonUsesActionWithoutChangingSettings() {
        actionRow.visible = true
        const button = findChild(actionRow, "preferenceActionButton")
        compare(button.caption, "Open")
        verify(button.width < actionRow.width / 2)
        const revision = store.revision
        mouseClick(button)
        compare(actionSpy.count, 1)
        compare(actionSpy.signalArguments[0][0], "folderAction")
        compare(store.revision, revision)
    }
    function test_accessibleSwitchUpdatesTheSetting() {
        const button = findChild(seekRow, "preferenceToggleEditor")
        compare(button.Accessible.role, Accessible.CheckBox)
        compare(button.checked, true); compare(store.value("fastSeek"), false)
        button.Accessible.toggleAction()
        compare(button.checked, false); compare(store.value("fastSeek"), true)
        button.Accessible.pressAction()
        compare(button.checked, true); compare(store.value("fastSeek"), false)
        button.enabled = false
        button.Accessible.toggleAction()
        compare(store.value("fastSeek"), false)
        button.enabled = true
    }
    function test_accessibleActionRunsOnceWithoutChangingSettings() {
        actionRow.visible = true
        const button = findChild(actionRow, "preferenceActionButton")
        compare(button.Accessible.role, Accessible.Button)
        const revision = store.revision
        button.Accessible.pressAction()
        compare(actionSpy.count, 1)
        compare(actionSpy.signalArguments[0][0], "folderAction")
        compare(store.revision, revision)
    }
    Component { id: deferredSubtitleSetup; RedesignSubtitleProviderSetup { } }
    function test_subtitleSetupCanWaitForTheSettingsOverlay() {
        const setup = createTemporaryObject(deferredSubtitleSetup, testCase, {parent: null})
        verify(setup !== null)
        compare(setup.width, 560)
        setup.parent = testCase
        setup.open(); tryCompare(setup, "opened", true)
        verify(findChild(setup, "subtitleProviderApiKey").activeFocus)
        setup.close(); tryCompare(setup, "visible", false)
    }
    function test_spatialModeRetainsChoiceWhileDisabled() {
        spatialModeRow.visible = true
        const choice = findChild(spatialModeRow, "preferenceChoiceEditor")
        verify(!choice.enabled)
        compare(choice.displayText, "Headphone virtualization")
        store.stage("audio-spatial", true)
        verify(choice.enabled)
        choice.forceActiveFocus(); keyClick(Qt.Key_Down)
        compare(store.value("audio-spatial-mode"), 0)
        compare(choice.displayText, "Surround speakers")
        store.stage("audio-spatial", false)
        verify(!choice.enabled)
        compare(store.value("audio-spatial-mode"), 0)
        store.stage("audio-spatial", true)
        compare(choice.displayText, "Surround speakers")
    }
    function test_startupVolumeOffersRememberAndFixedChoices() {
        startupVolume.visible = true
        const field = findChild(startupVolume, "startupVolumeField")
        verify(startupVolume.remember)
        verify(!field.enabled)
        mouseClick(findChild(startupVolume, "fixedStartupVolume"))
        compare(store.value("volume-save"), false)
        verify(field.enabled)
        field.text = "150"; field.editingFinished()
        compare(store.value("redesign-startup-volume"), 150)
        const remember = findChild(startupVolume, "rememberStartupVolume")
        remember.forceActiveFocus(); keyClick(Qt.Key_Space)
        compare(store.value("volume-save"), true)
        verify(!field.enabled)
        compare(store.value("redesign-startup-volume"), 150)
    }
    function test_startupVolumeShowsRejectedValue() {
        startupVolume.visible = true
        mouseClick(findChild(startupVolume, "fixedStartupVolume"))
        const field = findChild(startupVolume, "startupVolumeField")
        field.text = "301"; field.editingFinished()
        verify(field.invalid)
        compare(store.value("redesign-startup-volume"), 200)
        field.text = "125"; field.editingFinished()
        verify(!field.invalid)
        compare(store.value("redesign-startup-volume"), 125)
        field.text = "301"; field.editingFinished()
        mouseClick(findChild(startupVolume, "rememberStartupVolume"))
        verify(startupVolume.remember)
        verify(!field.invalid)
        compare(field.text, "125")
    }
    function test_deviceChoicesRefreshAndUseNativeIdentifiers() {
        deviceRow.visible = true
        const choice = findChild(deviceRow, "preferenceChoiceEditor")
        compare(choice.displayText, "System default")
        choice.forceActiveFocus(); choice.popup.open()
        compare(store.refreshCount, 1)
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
        compare(store.value("device"), "native-headphones")
        compare(choice.displayText, "Headphones")
    }
    function test_friendlyClickChoiceKeepsNativePolicyValue() {
        const choice = findChild(clickPolicyRow, "preferenceChoiceEditor")
        compare(choice.displayText, "Play / Pause")
        choice.forceActiveFocus(); keyClick(Qt.Key_Down)
        compare(store.value("clickPolicy"), "disabled")
        compare(choice.displayText, "Do nothing")
    }
    function test_dependentEditorStaysVisibleWhenDisabled() {
        const field = findChild(remotePortRow, "preferenceTextEditor")
        verify(field.enabled)
        store.stage("resize", false)
        verify(remotePortRow.visible)
        verify(!field.enabled)
        store.stage("resize", true)
        verify(field.enabled)
    }
    function test_equalizerExpandsAndEditsIndividualGains() {
        equalizer.visible = true
        mouseClick(findChild(equalizer, "equalizerExpander"))
        verify(equalizer.expanded)
        const preamp = findChild(equalizer, "equalizerValue_0")
        compare(preamp.text, "12.0")
        preamp.text = "3.5"; preamp.editingFinished()
        compare(equalizerStore.preamp, 3.5)
        const band = findChild(equalizer, "equalizerValue_1")
        band.text = "6.2"; band.editingFinished()
        compare(equalizerStore.gains[0], 6.2)
        compare(equalizerStore.gains[1], 1)
        band.text = "21"; band.editingFinished()
        verify(band.invalid)
        compare(equalizerStore.gains[0], 6.2)
        const slider = findChild(equalizer, "equalizerSlider_2")
        slider.forceActiveFocus(); keyClick(Qt.Key_Up)
        verify(equalizerStore.gains[1] > 1)
        mouseClick(findChild(equalizer, "equalizerExpander"))
        verify(!equalizer.expanded)
    }
    function test_guidedChoiceWritesUnderlyingBoolean() {
        const choice = findChild(resizeRow, "preferenceChoiceEditor")
        compare(choice.currentIndex, 1)
        choice.forceActiveFocus()
        keyClick(Qt.Key_Up)
        compare(store.value("resize"), false)
    }
    function test_preciseSeekingInvertsFastSeekOption() {
        const toggle = findChild(seekRow, "preferenceToggleEditor")
        verify(toggle.checked)
        mouseClick(toggle)
        compare(store.value("fastSeek"), true)
        verify(!toggle.checked)
    }
    function test_secondsSliderWritesMilliseconds() {
        const slider = findChild(delayRow, "preferenceSliderEditor")
        compare(slider.value, 1.8)
        mouseClick(slider, slider.width / 2, slider.height / 2)
        verify(store.value("timeout") >= 4900 && store.value("timeout") <= 5100)
    }
    function test_numericTextShowsUnitsAndPreservesNativeScale() {
        const field = findChild(timingTextRow, "preferenceTextEditor")
        compare(field.text, "1.8")
        verify(field.height >= 34)
        verify(timingTextRow.height >= 44)
        field.text = "2.4"
        field.editingFinished()
        compare(store.value("timeout"), 2400)
        field.text = "invalid"
        field.editingFinished()
        verify(field.invalid)
        compare(store.value("timeout"), 2400)
        field.text = ""
        field.editingFinished()
        verify(field.invalid)
        compare(store.value("timeout"), 2400)
    }
    function test_resetClearsInvalidTextAndUsesTheDefault() {
        const field = findChild(timingTextRow, "preferenceTextEditor")
        field.text = "invalid"; field.editingFinished(); verify(field.invalid)
        const reset = findChild(timingTextRow, "preferenceResetButton")
        verify(reset !== null)
        reset.clicked()
        verify(!field.invalid); compare(field.text, "1.8"); compare(store.value("timeout"), 1800)
    }
    function test_simpleAndAdvancedHaveDifferentContents() {
        const appearance = catalog.sections.general.find(section => section.appearance)
        compare(appearance.title, "Appearance")
        verify(appearance.rows.some(row => row[0] === "qt-backdrop-blur" && row[1] === "Transparency and blur"))
        compare(catalog.find("transparency")[0].name, "qt-backdrop-blur")
        compare(catalog.find("blur")[0].name, "qt-backdrop-blur")
        const basicGeneral = catalog.sections.general.reduce((names, section) => names.concat(section.rows.map(row => row[0])), [])
        const advancedGeneral = catalog.advancedSections.general.reduce((names, section) => names.concat(section.rows.map(row => row[0])), [])
        verify(!basicGeneral.includes("stats"))
        verify(advancedGeneral.includes("stats"))
        const playback = catalog.sections.playback.reduce((names, section) => names.concat(section.rows.map(row => row[0])), [])
        verify(playback.includes("redesign-repeat"))
        verify(!playback.includes("repeat"))
        verify(!playback.includes("loop"))
        verify(!playback.includes("input-timeshift-path"))
        const seeking = catalog.sections.playback.find(section => section.title === "Seeking")
        verify(seeking.rows.some(row => row[0] === "qt-seek-preview"))
        const audio = catalog.sections.audio.reduce((names, section) => names.concat(section.rows.map(row => row[0])), [])
        verify(audio.includes("redesign-audio-device"))
        verify(!audio.includes("aout"))
        const visualizer = catalog.sections.audio.find(section => section.title === "Visualization").rows[0]
        compare(visualizer[2].choiceLabels.none, "Disabled")
        verify(!audio.includes("filter:audio-filter:spatializer"))
        const effects = catalog.sections.audio.find(section => section.title === "Effects").rows.map(row => row[0])
        verify(effects.includes("filter:audio-filter:stereo_widen"))
        const pitch = catalog.sections.audio.find(section => section.title === "Effects").rows.find(row => row[0] === "pitch-shift")
        compare(pitch[2].decimals, 2)
        verify(!effects.includes("filter:audio-filter:stereowiden"))
        verify(effects.indexOf("audio-spatial-mode") < effects.indexOf("filter:audio-filter:stereo_widen"))
        verify(effects.indexOf("filter:audio-filter:stereo_widen") < effects.indexOf("filter:audio-filter:compressor"))
        verify(catalog.advancedSections.audio.some(section => section.rows.some(row => row[0] === "filter:audio-filter:spatializer" && row[2].spatializer)))
        verify(catalog.advancedSections.audio.some(section => section.rows.some(row => row[0] === "aout")))
        const advancedAudio = catalog.advancedSections.audio.reduce((names, section) => names.concat(section.rows.map(row => row[0])), [])
        verify(!audio.includes("visualization-size"))
        verify(advancedAudio.indexOf("role") < advancedAudio.indexOf("visualization-size"))
        verify(advancedAudio.indexOf("visualization-size") < advancedAudio.indexOf("aout"))
        verify(catalog.advancedSections.playback[0].rows.some(row => row[0] === "input-timeshift-path"))
    }
    function test_shortcutEditorRecordsKeys() {
        shortcutEditor.open()
        tryCompare(shortcutEditor, "opened", true)
        tryVerify(() => !!findChild(shortcutEditor.contentItem, "shortcut_key-toggle-fullscreen"))
        const cell = findChild(shortcutEditor.contentItem, "shortcut_key-toggle-fullscreen")
        mouseClick(cell)
        compare(shortcutEditor.recordingName, "key-toggle-fullscreen")
        keyClick(Qt.Key_F2, Qt.ControlModifier)
        compare(captureSpy.count, 1)
        compare(captureSpy.signalArguments[0][0], "key-toggle-fullscreen")
        compare(captureSpy.signalArguments[0][1], Qt.Key_F2)
        compare(captureSpy.signalArguments[0][2], Qt.ControlModifier)
    }
    function test_shortcutEditorSearchAndCancel() {
        shortcutEditor.open()
        tryCompare(shortcutEditor, "opened", true)
        wait(20)
        const search = findChild(shortcutEditor.contentItem, "shortcutSearch")
        search.text = "pause"
        compare(findChild(shortcutEditor.contentItem, "shortcutList").count, 1)
        mouseClick(findChild(shortcutEditor.contentItem, "shortcutCancel"))
        compare(cancelSpy.count, 1)
        compare(saveSpy.count, 0)
        compare(shortcutEditor.values["key-play-pause"], "Space")
    }
    function test_shortcutEditorHasExplicitSave() {
        shortcutEditor.open()
        tryCompare(shortcutEditor, "opened", true)
        wait(20)
        mouseClick(findChild(shortcutEditor.contentItem, "shortcutSave"))
        compare(saveSpy.count, 1)
        compare(cancelSpy.count, 0)
    }

}
