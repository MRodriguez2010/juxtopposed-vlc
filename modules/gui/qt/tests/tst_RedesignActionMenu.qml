// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls.Basic as C
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedActionMenu"
    width: 800; height: 600
    visible: true; when: windowShown
    RedesignButton {
        id: button
        x: 300; y: 20
        text: "Menu"
        onClicked: menu.toggleFrom(this)
    }
    RedesignActionMenu {
        id: menu
        entries: [{action: "first", label: "First"}, {action: "second", label: "Second"}]
    }
    SignalSpy { id: actions; target: menu; signalName: "actionRequested" }
    function init() {
        menu.close()
        tryCompare(menu, "visible", false)
        testCase.width = 800; testCase.height = 600
        button.x = 300; button.y = 20
        menu.entries = [{action: "first", label: "First"}, {action: "second", label: "Second"}]
        actions.clear()
        mouseMove(testCase, 10, 580)
    }
    function cleanup() { menu.close() }
    function topLeft() { return menu.background.mapToItem(testCase, 0, 0) }
    function checkInsideWindow() {
        const point = topLeft()
        verify(point.x >= menu.margins && point.x + menu.width <= testCase.width - menu.margins)
        verify(point.y >= menu.margins && point.y + menu.height <= testCase.height - menu.margins)
    }
    function test_buttonUsesItsPositionAndToggles() {
        mouseClick(button)
        tryCompare(menu, "opened", true)
        compare(topLeft().x, button.x)
        compare(topLeft().y, button.y + button.height)
        mouseClick(button)
        tryCompare(menu, "visible", false)
        mouseClick(button)
        tryCompare(menu, "opened", true)
        mouseClick(testCase, 20, 500)
        tryCompare(menu, "visible", false)
    }
    function test_keyboardOpensAtButtonWithPointerElsewhere() {
        button.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(menu, "opened", true)
        compare(topLeft().x, button.x)
        compare(topLeft().y, button.y + button.height)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(actions.count, 1)
        tryCompare(menu, "visible", false)
        button.forceActiveFocus(); keyClick(Qt.Key_Space)
        tryCompare(menu, "opened", true)
        keyClick(Qt.Key_Escape)
        tryCompare(menu, "visible", false)
    }
    function test_nearBottomOpensAbove() {
        button.y = 550
        mouseClick(button)
        tryCompare(menu, "opened", true)
        compare(topLeft().y + menu.height, button.y)
        checkInsideWindow()
        mouseClick(button)
        tryCompare(menu, "visible", false)
    }
    function test_nearRightEdgeStaysInWindow() {
        button.x = 750
        mouseClick(button)
        tryCompare(menu, "opened", true)
        checkInsideWindow()
        mouseClick(button)
        tryCompare(menu, "visible", false)
    }
    function test_tallMenuFitsBesideButtonAndCanReachLastAction() {
        testCase.height = 400
        button.y = 175
        const entries = []
        for (let index = 0; index < 16; ++index) entries.push({action: String(index), label: "Action " + index})
        menu.entries = entries
        mouseClick(button)
        tryCompare(menu, "opened", true)
        checkInsideWindow()
        const point = topLeft()
        verify(point.y + menu.height <= button.y || point.y >= button.y + button.height,
               "The menu must leave its opening button accessible.")
        for (let index = 0; index < 16; ++index) keyClick(Qt.Key_Down)
        const last = menu.itemAt(15)
        tryCompare(menu, "currentIndex", 15)
        tryVerify(() => {
            const row = last.mapToItem(menu.background, 0, 0)
            return row.y >= menu.padding && row.y + last.height <= menu.height - menu.padding
        })
        keyClick(Qt.Key_Return)
        compare(actions.signalArguments[0][0], "15")
    }
    function test_contextMenuStillClosesOnItsParent() {
        menu.toggleFrom(button)
        tryCompare(menu, "opened", true)
        menu.close(); tryCompare(menu, "visible", false)
        menu.popup(testCase, Qt.point(100, 120))
        tryCompare(menu, "opened", true)
        compare(topLeft().x, 100); compare(topLeft().y, 120)
        compare(menu.closePolicy, C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside)
        mouseClick(testCase, 20, 500)
        tryCompare(menu, "visible", false)
    }
    function test_resizeWhileOpenKeepsMenuInside() {
        button.y = 300
        mouseClick(button)
        tryCompare(menu, "opened", true)
        testCase.height = 380
        wait(50)
        checkInsideWindow()
    }
}
