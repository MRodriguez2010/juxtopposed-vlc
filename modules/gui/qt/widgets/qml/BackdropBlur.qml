// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window

// sourceItem must contain the content below the surface, excluding the surface
// itself. Transparent pixels remain transparent over separately composed video.
Item {
    id: root
    property Item sourceItem
    property real radius: 25
    property real cornerRadius: 10
    readonly property real padding: Math.ceil(3 * radius)
    property rect captureRect
    readonly property bool ready: !!effectLoader.item && effectLoader.item.ready
    readonly property bool available: GraphicsInfo.shaderType === GraphicsInfo.RhiShader
        && !!sourceItem && sourceItem.Window.window === root.Window.window && !sourceContainsSurface()

    function sourceContainsSurface() {
        for (let item = root; item; item = item.parent)
            if (item === sourceItem) return true
        return false
    }
    function updateCaptureRect() {
        if (available && visible) {
            const next = sourceItem.mapFromItem(root, -padding, -padding,
                                               width + 2 * padding, height + 2 * padding)
            if (next.x !== captureRect.x || next.y !== captureRect.y
                || next.width !== captureRect.width || next.height !== captureRect.height)
                captureRect = next
        }
    }
    onWidthChanged: updateCaptureRect()
    onHeightChanged: updateCaptureRect()
    onPaddingChanged: updateCaptureRect()
    onSourceItemChanged: updateCaptureRect()
    onAvailableChanged: updateCaptureRect()
    onVisibleChanged: updateCaptureRect()
    Component.onCompleted: updateCaptureRect()
    Connections {
        target: root.Window.window
        enabled: root.visible && root.available
        function onAfterAnimating() { root.updateCaptureRect() }
    }

    Loader {
        id: effectLoader
        anchors.fill: parent
        active: root.visible && root.available && root.radius > 0 && root.width > 0 && root.height > 0
        sourceComponent: Item {
            readonly property bool ready: blur.ready
            ShaderEffectSource {
                id: capture
                width: root.width + 2 * root.padding
                height: root.height + 2 * root.padding
                sourceItem: root.available ? root.sourceItem : null
                sourceRect: root.captureRect
                textureSize: Qt.size(Math.ceil(width * blur.eDPR), Math.ceil(height * blur.eDPR))
                visible: false
                smooth: true
            }
            DualKawaseBlur {
                id: blur
                objectName: "backdropBlurPasses"
                x: -root.padding; y: -root.padding
                width: capture.width; height: capture.height
                source: capture
                // Four passes have variance 175/6 * (radius - 0.5)^2.
                // Convert the requested logical Gaussian radius to texture pixels.
                radius: Math.max(1, Math.round(0.5 + root.radius * eDPR / Math.sqrt(175 / 6)))
                mode: DualKawaseBlur.Mode.FourPass
                postprocess: true
                cornerRadius: root.cornerRadius
                visualRect: Qt.rect(root.padding, root.padding, root.width, root.height)
            }
        }
    }
}
