// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as C
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedShortcutEditor"
    width: 1700; height: 1280
    visible: true; when: windowShown
    Component { id: editorComponent; RedesignShortcutEditor { } }
    property var rows: [
        {name: "key-fullscreen", globalName: "global-key-fullscreen", title: "Toggle fullscreen", group: "Basic"},
        {name: "key-hide", globalName: "global-key-hide", title: "Show / hide controls", group: "Basic"},
        {name: "key-quit", globalName: "global-key-quit", title: "Quit", group: "Basic"},
        {name: "key-settings", globalName: "global-key-settings", title: "Settings", group: "Basic"},
        {name: "key-play", globalName: "global-key-play", title: "Play / pause", group: "Playback"},
        {name: "key-stop", globalName: "global-key-stop", title: "Stop", group: "Playback"},
        {name: "key-next", globalName: "global-key-next", title: "Next", group: "Playback"},
        {name: "key-previous", globalName: "global-key-previous", title: "Previous", group: "Playback"},
        {name: "key-faster", globalName: "global-key-faster", title: "Faster", group: "Playback"}
    ]
    function makeEditor(options = {}) {
        const dialog = createTemporaryObject(editorComponent, testCase,
            Object.assign({parent: testCase, shortcuts: rows, dirty: true,
                values: {"key-fullscreen": "f", "key-play": "Space", "global-key-play": "Ctrl+Alt+P"}}, options))
        verify(dialog !== null)
        dialog.open(); tryCompare(dialog, "opened", true)
        return dialog
    }
    function child(dialog, name) {
        const item = findChild(dialog.contentItem, name)
        verify(item !== null, name)
        return item
    }
    function test_referenceTable_data() {
        return [{tag: "dark", light: false, scale: 1}, {tag: "light", light: true, scale: 1},
            {tag: "scaled", light: false, scale: 1.5}]
    }
    function test_referenceTable(data) {
        const dialog = makeEditor({lightTheme: data.light, scaleFactor: data.scale})
        const s = data.scale
        compare(dialog.width, 1048*s); compare(dialog.height, 800*s)
        compare(child(dialog, "shortcutHeader").height, 96*s)
        const search = child(dialog, "shortcutSearch")
        const searchPosition = search.mapToItem(dialog.contentItem, 0, 0)
        compare(searchPosition, Qt.point(9*s, 53*s)); compare(search.height, 34*s)
        compare(search.width, 820*s)
        const filter = child(dialog, "shortcutFilter")
        compare(filter.mapToItem(dialog.contentItem, 0, 0), Qt.point(839*s, 53*s))
        compare(filter.width, 200*s)
        const list = child(dialog, "shortcutList")
        compare(list.y, 161*s); compare(list.height, (800-161-72)*s)
        for (const [index, y] of [[0,229],[1,276],[2,323],[3,370],[4,496],[8,684]]) {
            const cell = child(dialog, "shortcut_"+rows[index].name)
            const position = cell.mapToItem(dialog.contentItem, 0, 0)
            fuzzyCompare(position.x, 399*s, 0.1*s)
            fuzzyCompare(position.y, y*s, 0.1*s)
            fuzzyCompare(cell.width, 270*s, 0.15*s); compare(cell.height, 33*s)
        }
        for (const name of ["shortcutCancel", "shortcutSave"]) {
            const button = child(dialog, name)
            compare(button.width, 100*s); compare(button.height, 32*s); compare(button.y, 748*s)
        }
        dialog.close(); tryCompare(dialog, "visible", false)
    }
    function test_searchFieldScopesAndKeepsFooterVisible() {
        const dialog = makeEditor()
        const search = child(dialog, "shortcutSearch"), filter = child(dialog, "shortcutFilter")
        const list = child(dialog, "shortcutList")
        search.text = "Ctrl+Alt+P"
        compare(list.count, 1); compare(list.model[0].name, "key-play")
        filter.currentIndex = 1
        compare(list.count, 0)
        filter.currentIndex = 3
        compare(list.count, 1)
        search.text = "No result"
        compare(list.count, 0)
        verify(child(dialog, "shortcutSave").visible); verify(child(dialog, "shortcutCancel").visible)
        dialog.close(); tryCompare(dialog, "visible", false)
    }
    function test_smallPlayerScrollDoesNotMoveFooter() {
        const holder = createTemporaryObject(holderComponent, testCase)
        const moreRows = rows.concat(Array.from({length: 20}, (_, i) =>
            ({name: "audio-"+i, globalName: "global-audio-"+i, title: "Audio "+i, group: "Audio"})))
        const dialog = makeEditor({parent: holder, shortcuts: moreRows})
        const list = child(dialog, "shortcutList"), save = child(dialog, "shortcutSave")
        const before = save.mapToItem(dialog.contentItem, 0, 0)
        list.positionViewAtEnd(); wait(20)
        verify(list.contentY > 0); compare(save.mapToItem(dialog.contentItem, 0, 0), before)
        const lastCell = child(dialog, "shortcut_audio-19")
        const lastPosition = lastCell.mapToItem(dialog.contentItem, 0, 0)
        verify(lastPosition.y >= list.y)
        verify(lastPosition.y + lastCell.height <= list.y + list.height)
        verify(list.y+list.height <= save.y)
        holder.height = 700; holder.width = 1000
        compare(dialog.width, 970); compare(dialog.height, 670)
        compare(save.y, 618)
        dialog.close(); tryCompare(dialog, "visible", false)
    }
    function test_escapeStopsRecordingBeforeClosingTheEditor() {
        const dialog = makeEditor()
        const canceled = createTemporaryObject(cancelSpy, testCase, {target: dialog})
        const cell = child(dialog, "shortcut_key-fullscreen")
        mouseClick(cell)
        compare(dialog.recordingName, "key-fullscreen")
        keyClick(Qt.Key_Escape)
        compare(dialog.recordingName, ""); compare(canceled.count, 0)
        keyClick(Qt.Key_Escape)
        compare(canceled.count, 1)
        dialog.close(); tryCompare(dialog, "visible", false)
    }
    function test_clearKeepsOtherBindingsVisibleUntilTheStoreUpdates() {
        const dialog = makeEditor({values: {"key-fullscreen": "f\tCtrl+F"}})
        const cleared = createTemporaryObject(clearSpy, testCase, {target: dialog})
        const cell = child(dialog, "shortcut_key-fullscreen")
        verify(cell.text.includes("Ctrl+F"))
        mouseMove(cell, cell.width/2, cell.height/2)
        const button = findChild(cell, "shortcutClear")
        tryCompare(button, "visible", true)
        mouseClick(button)
        compare(cleared.count, 1)
        compare(cleared.signalArguments[0][0], "key-fullscreen")
        compare(dialog.valueFor("key-fullscreen"), "f\tCtrl+F")
        dialog.values = {"key-fullscreen": ""}
        tryCompare(button, "visible", false)
        compare(dialog.recordingName, "")
        dialog.close(); tryCompare(dialog, "visible", false)
    }
    Component { id: cancelSpy; SignalSpy { signalName: "cancelRequested" } }
    Component { id: clearSpy; SignalSpy { signalName: "clearRequested" } }
    Component { id: holderComponent; Item { width: 640; height: 440 } }
}
