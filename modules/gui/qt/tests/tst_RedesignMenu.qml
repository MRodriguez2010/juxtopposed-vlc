// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedMenu"
    width: 1280; height: 900
    visible: true
    when: windowShown
    property int activeBackdrops: 0
    Component {
        id: backdropProbe
        Item {
            objectName: "menuBackdropProbe"
            property real cornerRadius: 0
            property bool menuShadow: false
            Component.onCompleted: testCase.activeBackdrops++
            Component.onDestruction: testCase.activeBackdrops--
        }
    }
    ListModel { id: recentFiles }
    RedesignMenu {
        id: menu
        parent: testCase
        x: 20; y: 20
        recentModel: recentFiles
        profiles: [{id: "movies", name: "Movies"}, {id: "music", name: "Music"}]
        onProfileRequested: profileId => selectedProfile = profileId
        onClearRecentRequested: recentFiles.clear()
    }
    RedesignButton {
        id: menuButton
        x: 1100; y: 10
        text: "Menu"
        onClicked: menu.toggleFrom(this, testCase)
    }
    SignalSpy { id: actions; target: menu; signalName: "actionRequested" }
    SignalSpy { id: recent; target: menu; signalName: "recentRequested" }
    SignalSpy { id: profiles; target: menu; signalName: "profileRequested" }
    function init() {
        menu.dismiss()
        menu.parent = testCase
        menu.x = 20; menu.y = 20
        menu.scaleFactor = 1
        menu.lightTheme = false
        menu.recentFilesEnabled = true
        menu.recentFilesAvailable = true
        menu.selectedProfile = "movies"
        menu.videoBackdropContent = null
        recentFiles.clear()
        recentFiles.append({id: 42, url: "/videos/cat.mkv"})
        recentFiles.append({id: 43, url: "/videos/second.mkv"})
        actions.clear(); recent.clear(); profiles.clear()
        menu.open()
        tryCompare(menu, "opened", true)
    }
    function cleanup() { menu.dismiss() }
    function test_menuButtonTogglesTheMenu() {
        menu.dismiss()
        tryCompare(menu, "visible", false)
        mouseClick(menuButton)
        tryCompare(menu, "opened", true)
        const origin = menu.background.mapToItem(testCase, 0, 0)
        compare(origin.x, testCase.width - menu.width)
        compare(origin.y, menuButton.y + menuButton.height)
        // The press on the open menu's button must not dismiss it and let the click reopen it.
        mouseClick(menuButton)
        tryCompare(menu, "visible", false)
        mouseClick(menuButton)
        tryCompare(menu, "opened", true)
        mouseClick(testCase, 100, 800)
        tryCompare(menu, "visible", false)
    }
    function openSubmenu(index) {
        menu.currentIndex = index
        menu.itemAt(index).forceActiveFocus()
        keyClick(Qt.Key_Right)
        const submenu = menu.itemAt(index).subMenu
        tryCompare(submenu, "opened", true)
        return submenu
    }
    function test_orderAndSize() {
        compare(menu.width, 375)
        compare(menu.count, 13)
        compare(menu.height, 585)
        compare(menu.itemAt(0).height, 48)
        compare(menu.itemAt(1).text, "Open Folder")
        compare(menu.itemAt(2).text, "Open Network Stream")
        compare(menu.itemAt(6).text, "Open Recent")
        compare(menu.itemAt(8).text, "Profile (Movies)")
        compare(menu.itemAt(9).text, "Keyboard Shortcuts")
    }
    function test_backdropsFollowMenuAndSubmenuLifetime() {
        menu.videoBackdropContent = backdropProbe
        tryCompare(testCase, "activeBackdrops", 1)
        function verifyBackdrop(popup) {
            const backdrop = findChild(popup.background, "menuBackdropProbe")
            verify(backdrop !== null)
            compare(backdrop.width, popup.background.width)
            compare(backdrop.height, popup.background.height)
            compare(backdrop.cornerRadius, popup.background.radius)
            compare(backdrop.menuShadow, true)
            compare(popup.background.opacity, 1)
            fuzzyCompare(popup.background.color.a, 0.90, 0.001)
        }
        verifyBackdrop(menu)
        for (const index of [6, 8]) {
            const submenu = openSubmenu(index)
            tryCompare(testCase, "activeBackdrops", 2)
            verifyBackdrop(submenu)
            keyClick(Qt.Key_Escape)
            tryCompare(testCase, "activeBackdrops", 1)
        }
        menu.scaleFactor = 1.5
        compare(findChild(menu.background, "menuBackdropProbe").cornerRadius, 15)
        menu.dismiss()
        tryCompare(testCase, "activeBackdrops", 0)
        menu.open()
        tryCompare(testCase, "activeBackdrops", 1)
        menu.dismiss()
        tryCompare(testCase, "activeBackdrops", 0)
    }
    function test_keyboardActionAndDismissal() {
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(actions.count, 1)
        compare(actions.signalArguments[0][0], "directory")
        tryCompare(menu, "visible", false)
    }
    function test_keyboardHomeEnd() {
        keyClick(Qt.Key_End)
        compare(menu.currentIndex, menu.count - 1)
        keyClick(Qt.Key_Home)
        compare(menu.currentIndex, 0)
    }
    function test_recentFileKeyboardSelection() {
        const submenu = openSubmenu(6)
        tryCompare(submenu, "count", 5)
        submenu.currentIndex = 1
        submenu.itemAt(1).forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(recent.count, 1)
        compare(recent.signalArguments[0][0], 43)
        tryCompare(menu, "visible", false)
        tryCompare(submenu, "visible", false)
    }
    function test_historyPrivacyAndClear() {
        const submenu = openSubmenu(6)
        submenu.itemAt(submenu.count - 1).triggered()
        tryCompare(recentFiles, "count", 0)
        menu.open()
        tryCompare(menu, "opened", true)
        openSubmenu(6)
        verify(submenu.itemAt(0).visible)
        verify(!submenu.itemAt(submenu.count - 1).enabled)
        menu.recentFilesEnabled = false
        tryCompare(submenu.itemAt(0), "text", "Recent file history is off")
        recentFiles.append({id: 44, url: "/private.mkv"})
        compare(submenu.count, 3)
    }
    function test_profileSelectionAndDefault() {
        let submenu = openSubmenu(8)
        tryCompare(submenu, "count", 3)
        verify(submenu.itemAt(1).checked)
        submenu.itemAt(2).forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(profiles.count, 1)
        compare(menu.selectedProfile, "music")
        compare(menu.itemAt(8).text, "Profile (Music)")
        menu.open()
        tryCompare(menu, "opened", true)
        submenu = openSubmenu(8)
        submenu.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(menu.selectedProfile, "")
        compare(menu.itemAt(8).text, "Profile (Default Preset)")
    }
    function test_historyWithoutMediaLibrary() {
        menu.recentFilesAvailable = false
        const submenu = openSubmenu(6)
        tryCompare(submenu, "count", 3)
        compare(submenu.itemAt(0).text, "Recent files need the media library.")
        verify(!submenu.itemAt(2).enabled)
    }
    function test_shortcutsEntry() {
        menu.currentIndex = 9
        menu.itemAt(9).forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(actions.signalArguments[0][0], "shortcuts")
    }
    function test_escapeClosesSubmenuFirst() {
        const submenu = openSubmenu(6)
        keyClick(Qt.Key_Escape)
        tryCompare(submenu, "visible", false)
        verify(menu.visible)
        keyClick(Qt.Key_Escape)
        tryCompare(menu, "visible", false)
    }
    function test_scalingAndLightTheme() {
        menu.scaleFactor = 1.5
        menu.lightTheme = true
        compare(menu.width, 562.5)
        compare(menu.itemAt(0).implicitHeight, 72)
        compare(menu.background.color, Qt.rgba(menu.theme.background.r, menu.theme.background.g,
                                               menu.theme.background.b, 0.90))
    }
}
