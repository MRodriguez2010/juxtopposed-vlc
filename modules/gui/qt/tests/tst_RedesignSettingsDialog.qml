// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls.Basic as C
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedSettingsDialog"
    width: 1400; height: 1000
    visible: true; when: windowShown
    property int activeBackdrops: 0
    property int playerClicks: 0
    QtObject { id: redesignAppearance; property bool backdropBlurEnabled: true }
    MouseArea { anchors.fill: parent; onClicked: testCase.playerClicks++ }
    Component {
        id: backdropProbe
        Item {
            property real cornerRadius: 0
            property real blurRadius: 0
            property bool menuShadow: false
            Component.onCompleted: testCase.activeBackdrops++
            Component.onDestruction: testCase.activeBackdrops--
        }
    }
    Component { id: settings; RedesignSettingsDialog { } }
    function makeDialog(parentItem) {
        const dialog = createTemporaryObject(settings, parentItem || testCase,
            {parent: parentItem || testCase, videoBackdropContent: backdropProbe})
        verify(dialog !== null)
        return dialog
    }
    function cleanup() { redesignAppearance.backdropBlurEnabled = true }
    function test_referenceCardAndLiveSwitch() {
        const dialog = makeDialog()
        compare(activeBackdrops, 0)
        dialog.open(); tryCompare(dialog, "opened", true)
        compare(dialog.popupType, C.Popup.Item)
        compare(dialog.modal, true); compare(dialog.dim, false)
        compare(dialog.width, 1048); compare(dialog.height, 865)
        compare(dialog.x, 176); compare(dialog.y, 67.5)
        tryCompare(testCase, "activeBackdrops", 1)
        const surface = dialog.background
        compare(surface.width, 1048); compare(surface.height, 865)
        compare(surface.radius, 14)
        const loader = findChild(surface, "dialogBackdropLoader")
        verify(loader.item !== null)
        compare(loader.item.cornerRadius, 14); compare(loader.item.blurRadius, 25)
        compare(loader.item.menuShadow, true)
        for (let parent = surface; parent; parent = parent.parent)
            verify(parent !== testCase, "The Settings card must not be captured into its own backdrop.")
        for (const enabled of [true, false, true]) {
            redesignAppearance.backdropBlurEnabled = enabled
            fuzzyCompare(surface.color.a, enabled ? 0.95 : 1, 0.001)
            compare(Qt.rgba(surface.color.r, surface.color.g, surface.color.b, 1), "#0e0e0e")
        }
        dialog.lightTheme = true
        compare(Qt.rgba(surface.color.r, surface.color.g, surface.color.b, 1), dialog.theme.panel)
        dialog.close(); tryCompare(dialog, "visible", false)
        tryCompare(testCase, "activeBackdrops", 0)
    }
    function test_modalDismissWaitsForSettingsStore() {
        const dialog = makeDialog()
        const spy = createTemporaryObject(signalSpy, testCase, {target: dialog})
        dialog.open(); tryCompare(dialog, "opened", true)
        const before = playerClicks
        mouseClick(testCase, 4, 4)
        compare(playerClicks, before); compare(dialog.visible, true)
        dialog.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 1); compare(dialog.visible, true)
        dialog.close(); tryCompare(dialog, "visible", false)
        tryCompare(testCase, "activeBackdrops", 0)
    }
    Component { id: signalSpy; SignalSpy { signalName: "dismissRequested" } }
    function test_smallPlayerAndResize() {
        const holder = createTemporaryObject(holderComponent, testCase)
        const dialog = makeDialog(holder)
        dialog.open(); tryCompare(dialog, "opened", true)
        compare(dialog.width, 608); compare(dialog.height, 408)
        compare(dialog.x, 16); compare(dialog.y, 16)
        holder.width = 1000; holder.height = 700
        compare(dialog.width, 968); compare(dialog.height, 668)
        compare(dialog.x, 16); compare(dialog.y, 16)
        dialog.close(); tryCompare(dialog, "visible", false)
        tryCompare(testCase, "activeBackdrops", 0)
    }
    Component { id: holderComponent; Item { width: 640; height: 440 } }
}
