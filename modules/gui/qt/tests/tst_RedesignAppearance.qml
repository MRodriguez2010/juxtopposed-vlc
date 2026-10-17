// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedAppearance"
    width: 1280; height: 720
    visible: true; when: windowShown
    QtObject {
        id: redesignAppearance
        property bool backdropBlurEnabled: true
    }
    RedesignPlayerView { id: player; anchors.fill: parent; settingsPage: "playback" }
    RedesignTrackPopup { id: tracks; parent: testCase; placementArea: testCase }
    RedesignMenu { id: menu; parent: testCase }
    RedesignActionMenu { id: actions; parent: testCase }
    RedesignSeekBar { id: seek; x: 100; y: 650; width: 600 }

    function test_liveTransparency_data() {
        return [{tag: "dark", light: false}, {tag: "light", light: true}]
    }
    function test_liveTransparency(data) {
        player.lightTheme = tracks.lightTheme = menu.lightTheme = actions.lightTheme = seek.lightTheme = data.light
        const panel = findChild(player, "redesignRightPanel")
        const preview = findChild(seek, "seekThumbnailPopup")
        const surfaces = [panel, tracks.background, menu.background, actions.background, preview.background]
        const geometry = panel.mapToItem(player, 0, 0)
        for (const enabled of [true, false, true]) {
            redesignAppearance.backdropBlurEnabled = enabled
            for (const surface of surfaces)
                fuzzyCompare(surface.color.a, enabled ? 0.90 : 1, 0.001)
            compare(panel.mapToItem(player, 0, 0), geometry)
        }
    }
}
