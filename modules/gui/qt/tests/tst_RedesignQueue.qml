// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedQueue"
    width: 400; height: 600
    visible: true; when: windowShown
    property int activeBackdrops: 0
    Component {
        id: backdropProbe
        Item {
            objectName: "contextBackdropProbe"
            property real cornerRadius: 0
            property bool menuShadow: false
            Component.onCompleted: testCase.activeBackdrops++
            Component.onDestruction: testCase.activeBackdrops--
        }
    }
    ListModel { id: media }
    RedesignQueue {
        id: queue
        anchors.fill: parent
        queueModel: media; itemCount: media.count; currentIndex: 1
        totalDurationText: "1h 12m"
        sortChoices: [{ criteria: 11, text: "Title" }, { criteria: 22, text: "Duration" }]
        onMoveRequested: (from, to) => media.move(from, to > from ? to - 1 : to, 1)
        onRemoveRequested: index => media.remove(index)
        onSortRequested: (key, descending) => { sortKey = key; sortDescending = descending }
    }
    SignalSpy { id: moveSpy; target: queue; signalName: "moveRequested" }
    SignalSpy { id: removeSpy; target: queue; signalName: "removeRequested" }
    SignalSpy { id: sortSpy; target: queue; signalName: "sortRequested" }
    SignalSpy { id: playSpy; target: queue; signalName: "playRequested" }
    SignalSpy { id: saveSpy; target: queue; signalName: "saveRequested" }
    SignalSpy { id: clearSpy; target: queue; signalName: "clearRequested" }
    function test_contextBackdropLifetime() {
        queue.videoBackdropContent = backdropProbe
        for (const name of ["queueSortMenu", "queueActionsMenu"]) {
            const menu = findChild(queue, name)
            compare(menu.videoBackdropContent, backdropProbe)
            menu.open()
            tryCompare(testCase, "activeBackdrops", 1)
            const backdrop = findChild(menu.background, "contextBackdropProbe")
            verify(backdrop !== null)
            compare(backdrop.width, menu.background.width)
            compare(backdrop.height, menu.background.height)
            compare(backdrop.cornerRadius, 10)
            compare(backdrop.menuShadow, true)
            for (let parent = menu.background; parent; parent = parent.parent)
                verify(parent !== queue, "The menu must stay outside its capture source.")
            menu.close()
            tryCompare(testCase, "activeBackdrops", 0)
        }
        queue.videoBackdropContent = null
    }
    function init() {
        queue.videoBackdropContent = null
        queue.visible = true
        media.clear()
        media.append({title: "First", isCurrent: false})
        media.append({title: "Second", isCurrent: true})
        media.append({title: "Third", isCurrent: false})
        queue.selectedIndex = -1; queue.sortKey = -1; queue.sortDescending = false
        moveSpy.clear(); removeSpy.clear(); sortSpy.clear(); playSpy.clear(); saveSpy.clear(); clearSpy.clear()
        findChild(queue, "queueSortMenu").close()
        findChild(queue, "queueActionsMenu").close()
        wait(50)
    }
    function test_summaryAndRemoveUseCurrentThenSelectedItem() {
        // VLC's translator uses the disambiguation string for plurals.
        // Standalone Qt has no VLC translator, so check the count and duration here.
        verify(findChild(queue, "queueSummary").text.startsWith("3 "))
        verify(findChild(queue, "queueSummary").text.endsWith(" - 1h 12m"))
        mouseClick(findChild(queue, "queueRemoveButton"))
        compare(removeSpy.signalArguments[0][0], 1)
        compare(media.get(1).title, "Third")
        mouseClick(findChild(queue, "queueItem_0"))
        compare(playSpy.signalArguments[0][0], 0)
        mouseClick(findChild(queue, "queueRemoveButton"))
        compare(media.get(0).title, "Third")
        compare(findChild(queue, "queueSummary").text, "1 item - 1h 12m")
    }
    function test_dragReordersWithoutPlayingAndHandlesDownwardInsertion() {
        const handle = findChild(queue, "queueMoveHandle_0")
        mouseDrag(handle, handle.width / 2, handle.height / 2, 0, 88)
        compare(moveSpy.count, 1)
        compare(Array.from(moveSpy.signalArguments[0]), [0, 3])
        compare(media.get(0).title, "Second")
        compare(media.get(2).title, "First")
        compare(playSpy.count, 0)
    }
    function test_keyboardMoveAndDeleteKeepSelectionOnMovedItem() {
        mouseClick(findChild(queue, "queueMoveHandle_0"))
        compare(queue.selectedIndex, 0)
        verify(queue.activeFocus)
        keyClick(Qt.Key_Down, Qt.AltModifier)
        compare(media.get(1).title, "First")
        compare(queue.selectedIndex, 1)
        keyClick(Qt.Key_Delete)
        compare(media.get(0).title, "Second")
        compare(media.get(1).title, "Third")
        compare(playSpy.count, 0)
    }
    function test_hiddenQueueCancelsRowDrag() {
        const handle = findChild(queue, "queueMoveHandle_0")
        mousePress(handle, handle.width / 2, handle.height / 2)
        mouseMove(handle, handle.width / 2, handle.height / 2 + 88, 50)
        queue.visible = false
        mouseRelease(handle)
        compare(moveSpy.count, 0)
        compare(media.get(0).title, "First")
    }
    function test_reverseWithoutSortStartsWithFirstNativeCriterion() {
        queue.sortKey = 999
        mouseClick(findChild(queue, "queueSortButton"))
        const menu = findChild(queue, "queueSortMenu")
        tryCompare(menu, "opened", true); wait(200)
        mouseClick(findChild(menu, "libraryAction_reverse"))
        compare(Array.from(sortSpy.signalArguments[0]), [11, true])
    }
    function test_sortAndReverseUseSelectedNativeCriterion() {
        mouseClick(findChild(queue, "queueSortButton"))
        const menu = findChild(queue, "queueSortMenu")
        tryCompare(menu, "opened", true); wait(200)
        mouseClick(findChild(menu, "libraryAction_22"))
        compare(Array.from(sortSpy.signalArguments[0]), [22, false])
        tryCompare(menu, "opened", false)
        mouseClick(findChild(queue, "queueSortButton"))
        tryCompare(menu, "opened", true); wait(200)
        verify(findChild(menu, "libraryAction_22").checked)
        mouseClick(findChild(menu, "libraryAction_reverse"))
        compare(Array.from(sortSpy.signalArguments[1]), [22, true])
    }
    function test_contextActionsSaveAndClearAndEmptyRemovalIsDisabled() {
        queue.forceActiveFocus(); keyClick(Qt.Key_Menu)
        const menu = findChild(queue, "queueActionsMenu")
        tryCompare(menu, "opened", true); wait(200)
        mouseClick(findChild(menu, "libraryAction_save"))
        compare(saveSpy.count, 1)
        tryCompare(menu, "opened", false)
        queue.forceActiveFocus(); keyClick(Qt.Key_Menu)
        tryCompare(menu, "opened", true); wait(200)
        mouseClick(findChild(menu, "libraryAction_clear"))
        compare(clearSpy.count, 1)
        media.clear()
        verify(!findChild(queue, "queueRemoveButton").enabled)
        queue.removeSelection(); compare(removeSpy.count, 0)
    }
}
