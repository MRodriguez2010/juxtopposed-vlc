// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedDialogSurfaces"
    width: 1400; height: 1000
    visible: true; when: windowShown
    property int activeBackdrops: 0
    QtObject { id: redesignAppearance; property bool backdropBlurEnabled: true }
    Component {
        id: backdropProbe
        Item {
            objectName: "dialogBackdropProbe"
            property real cornerRadius: 0
            property real blurRadius: 0
            property bool menuShadow: false
            Component.onCompleted: testCase.activeBackdrops++
            Component.onDestruction: testCase.activeBackdrops--
        }
    }
    Component { id: network; RedesignNetworkDialog { } }
    Component { id: playlist; RedesignPlaylistDialog { } }
    Component { id: addToPlaylist; RedesignAddToPlaylistDialog { } }
    Component { id: tracks; RedesignTrackAssignmentDialog { } }
    Component { id: shortcuts; RedesignShortcutEditor { } }
    function test_referenceSurface_data() {
        const rows = []
        for (const light of [false, true]) {
            for (const spec of [{name: "network", component: network}, {name: "playlist", component: playlist},
                {name: "add-to-playlist", component: addToPlaylist}, {name: "tracks", component: tracks, fill: "#0e0e0e"},
                {name: "shortcuts", component: shortcuts}])
                rows.push({tag: spec.name + "-" + light, light, component: spec.component, fill: spec.fill || "#191919"})
        }
        return rows
    }
    function test_referenceSurface(data) {
        redesignAppearance.backdropBlurEnabled = true
        const dialog = createTemporaryObject(data.component, testCase,
            {parent: testCase, lightTheme: data.light, videoBackdropContent: backdropProbe})
        verify(dialog !== null)
        const surface = dialog.background
        const loader = findChild(surface, "dialogBackdropLoader")
        compare(testCase.activeBackdrops, 0)
        dialog.open(); tryCompare(dialog, "opened", true)
        tryCompare(testCase, "activeBackdrops", 1)
        const backdrop = findChild(surface, "dialogBackdropProbe")
        verify(backdrop !== null)
        compare(backdrop.width, surface.width); compare(backdrop.height, surface.height)
        compare(backdrop.cornerRadius, 14); compare(backdrop.blurRadius, 25)
        compare(backdrop.menuShadow, true)
        compare(surface.radius, 14)
        compare(Qt.rgba(surface.color.r, surface.color.g, surface.color.b, 1),
                data.light ? dialog.theme.panel : Qt.color(data.fill))
        for (let parent = surface; parent; parent = parent.parent)
            verify(parent !== testCase, "Dialog surfaces must stay outside the captured interface.")
        for (const enabled of [true, false, true]) {
            redesignAppearance.backdropBlurEnabled = enabled
            fuzzyCompare(surface.color.a, enabled ? 0.95 : 1, 0.001)
        }
        dialog.scaleFactor = 1.5
        compare(surface.radius, 21); compare(backdrop.cornerRadius, 21)
        compare(backdrop.blurRadius, 37.5)
        dialog.close(); tryCompare(dialog, "visible", false)
        tryCompare(testCase, "activeBackdrops", 0)
        verify(!loader.active)
    }
}
