// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import QtTest
import "../player/qml/redesign"

TestCase {
    id: testCase
    name: "JuxtopposedWindowBackdrop"
    width: 640; height: 440
    visible: true; when: windowShown
    QtObject { id: redesignAppearance; property bool backdropBlurEnabled: true }
    QtObject {
        id: backend
        property bool supported: true
        property var requests: []
        function setWindowBackdrop(window, enabled, bounds, radius, dark) {
            requests = requests.concat([{window, enabled, bounds, radius, dark}])
            return enabled && supported
        }
    }
    Window { id: targetWindow; width: 400; height: 300; visible: false }
    RedesignWindowBackdrop {
        id: backdrop
        backend: backend; window: targetWindow
        enabled: redesignAppearance.backdropBlurEnabled
        clipRect: Qt.rect(15, 15, targetWindow.width - 30, targetWindow.height - 30)
    }
    RedesignWindowSurface {
        id: surface
        width: 300; height: 200
        backdropActive: backdrop.active
    }
    function init() {
        targetWindow.visible = false
        backend.supported = true
        redesignAppearance.backdropBlurEnabled = true
        targetWindow.width = 400; targetWindow.height = 300
        backdrop.darkTheme = true; surface.theme.lightTheme = false
        wait(20)
        backend.requests = []
    }
    function cleanup() { targetWindow.visible = false; wait(20) }
    function test_showHideReleasesBackdrop() {
        compare(backdrop.active, false); compare(surface.color.a, 1)
        targetWindow.show()
        tryCompare(backdrop, "active", true)
        fuzzyCompare(surface.color.a, 0.95, 0.001)
        compare(backend.requests[backend.requests.length - 1].enabled, true)
        targetWindow.hide()
        tryCompare(backdrop, "applied", false)
        compare(backend.requests[backend.requests.length - 1].enabled, false)
        compare(surface.color.a, 1)
    }
    function test_liveSwitchUsesSolidFallback() {
        targetWindow.show(); tryCompare(backdrop, "active", true)
        redesignAppearance.backdropBlurEnabled = false
        compare(surface.color.a, 1)
        tryCompare(backdrop, "applied", false)
        redesignAppearance.backdropBlurEnabled = true
        tryCompare(backdrop, "active", true)
        fuzzyCompare(surface.color.a, 0.95, 0.001)
    }
    function test_unavailableBackdropStaysOpaque() {
        backend.supported = false
        targetWindow.show(); wait(20)
        compare(backdrop.active, false); compare(surface.color.a, 1)
        compare(surface.color, "#0e0e0e")
    }
    function test_resizeAndThemeUpdateWithoutIdleWork() {
        targetWindow.show(); tryCompare(backdrop, "active", true)
        targetWindow.width = 500; targetWindow.height = 350
        backdrop.darkTheme = false
        surface.theme.lightTheme = true
        wait(20)
        const request = backend.requests[backend.requests.length - 1]
        compare(request.bounds, Qt.rect(15, 15, 470, 320))
        compare(request.radius, 14); compare(request.dark, false)
        compare(Qt.rgba(surface.color.r, surface.color.g, surface.color.b, 1), surface.theme.panel)
        const count = backend.requests.length
        wait(200)
        compare(backend.requests.length, count)
    }
}
