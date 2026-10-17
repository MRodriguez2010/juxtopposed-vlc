// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedBookmarks"
    width: 420; height: 600
    visible: true; when: windowShown
    property int activeBackdrops: 0
    Component {
        id: backdropProbe
        Item {
            objectName: "contextBackdropProbe"
            property real cornerRadius: 0
            Component.onCompleted: testCase.activeBackdrops++
            Component.onDestruction: testCase.activeBackdrops--
        }
    }
    ListModel { id: bookmarks }
    RedesignBookmarksView {
        id: view
        width: 400; height: 550
        bookmarkModel: bookmarks; canAdd: true
        onRemoveRequested: index => bookmarks.remove(index)
        onRenameRequested: (index, name) => bookmarks.setProperty(index, "name", name)
    }
    SignalSpy { id: add; target: view; signalName: "addRequested" }
    SignalSpy { id: remove; target: view; signalName: "removeRequested" }
    SignalSpy { id: activate; target: view; signalName: "activateRequested" }
    SignalSpy { id: rename; target: view; signalName: "renameRequested" }
    function item(name) { return findChild(view, name) }
    function test_contextBackdropLifetime() {
        view.videoBackdropContent = backdropProbe
        for (const name of ["bookmarkActionsMenu"]) {
            const menu = findChild(view, name)
            compare(menu.videoBackdropContent, backdropProbe)
            menu.open()
            tryCompare(testCase, "activeBackdrops", 1)
            const backdrop = findChild(menu.background, "contextBackdropProbe")
            verify(backdrop !== null)
            compare(backdrop.width, menu.background.width)
            compare(backdrop.height, menu.background.height)
            compare(backdrop.cornerRadius, 10)
            for (let parent = menu.background; parent; parent = parent.parent)
                verify(parent !== view, "The menu must stay outside its capture source.")
            menu.close()
            tryCompare(testCase, "activeBackdrops", 0)
        }
        view.videoBackdropContent = null
    }
    function init() {
        view.videoBackdropContent = null
        failOnWarning(/Binding loop detected/)
        bookmarks.clear()
        bookmarks.append({name: "DON’T BLINK 1", timeMS: 42023})
        bookmarks.append({name: "DON’T BLINK 2", timeMS: 44125})
        view.selectedIndex = -1; view.canAdd = true
        view.lightTheme = false; view.accentColor = "#d37918"; view.scaleFactor = 1
        view.width = 400; view.height = 550
        add.clear(); remove.clear(); activate.clear(); rename.clear()
        mouseMove(testCase, 415, 590); wait(20)
    }
    function test_referenceRowsUsePreciseTimesAndSharedActions() {
        compare(item("bookmarkTime0").text, "00:00:42:023")
        compare(item("bookmarkTime1").text, "00:00:44:125")
        compare(item("bookmarkRow0").height, 44)
        compare(item("bookmarkRow0").mapToItem(view, 0, 0).x, 20)
        verify(!item("bookmarkRemoveButton").enabled)
        mouseClick(item("bookmarkAddButton")); compare(add.count, 1)
        mouseClick(item("bookmarkRow1")); compare(view.selectedIndex, 1)
        compare(activate.signalArguments[0][0], 1)
        mouseClick(item("bookmarkRemoveButton")); compare(remove.signalArguments[0][0], 1)
        compare(bookmarks.count, 1); compare(view.selectedIndex, -1)
    }
    function test_keyboardSelectionRenameAndDelete() {
        view.forceActiveFocus(); keyClick(Qt.Key_Down); compare(view.selectedIndex, 0)
        keyClick(Qt.Key_Down); compare(view.selectedIndex, 1)
        keyClick(Qt.Key_F2)
        const editor = item("bookmarkName1")
        verify(editor.visible); verify(editor.activeFocus); verify(view.editing)
        editor.text = "New name"; keyClick(Qt.Key_Return)
        compare(rename.count, 1); compare(bookmarks.get(1).name, "New name"); verify(!view.editing)
        keyClick(Qt.Key_F2); editor.text = "Cancelled"; keyClick(Qt.Key_Escape)
        compare(rename.count, 1); compare(bookmarks.get(1).name, "New name"); verify(!view.editing)
        keyClick(Qt.Key_Delete); compare(bookmarks.count, 1)
    }
    function test_removalCannotUseSelectionFromOldMedia() {
        mouseClick(item("bookmarkRow1"))
        bookmarks.clear(); bookmarks.append({name: "Other video", timeMS: 10})
        tryCompare(view, "selectedIndex", -1)
        verify(!item("bookmarkRemoveButton").enabled)
        view.forceActiveFocus(); keyClick(Qt.Key_Delete); compare(remove.count, 0)
    }
    function test_emptyKeyboardNavigationDoesNotSelectARow() {
        bookmarks.clear(); view.forceActiveFocus()
        keyClick(Qt.Key_Up); keyClick(Qt.Key_Down)
        compare(view.selectedIndex, -1)
        keyClick(Qt.Key_F2); keyClick(Qt.Key_Delete)
        compare(rename.count, 0); compare(remove.count, 0)
    }
    function test_lightAccentAndNarrowLayoutKeepTimesVisible() {
        view.lightTheme = true; view.accentColor = "#19a234"; view.width = 290
        bookmarks.setProperty(0, "name", "A very long bookmark name that must fit beside its timestamp")
        wait(20)
        const time = item("bookmarkTime0"), position = time.mapToItem(view, 0, 0)
        verify(position.x >= 20 && position.x + time.width <= view.width - 23)
        compare(item("bookmarkAddButton").accentColor, "#19a234")
        view.canAdd = false; verify(!item("bookmarkAddButton").enabled)
        compare(view.timeText(90061001), "25:01:01:001")
    }
}
