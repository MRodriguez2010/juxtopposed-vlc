// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import VLC.MainInterface
import VLC.Widgets as Widgets

Item {
    id: root
    property Item sourceItem
    property real scaleFactor: 1
    property real blurRadius: 25 * scaleFactor
    property real cornerRadius: 10 * scaleFactor
    property bool menuShadow: false
    property bool nativeVideo: true
    Widgets.RoundedRectangleShadow {
        anchors.alignWhenCentered: false
        visible: root.menuShadow && GraphicsInfo.shaderType === GraphicsInfo.RhiShader
        blurRadius: 7.5 * root.scaleFactor
        yOffset: 8 * root.scaleFactor
        radius: Math.max(0, Math.min(root.cornerRadius, root.width / 2, root.height / 2))
        color: Qt.rgba(0, 0, 0, 0.46)
        exclusionRect: Qt.rect(blurRadius * compensationFactor,
                               blurRadius * compensationFactor - yOffset,
                               root.width, root.height)
        exclusionRadius: radius
    }
    VideoBackdrop {
        visible: root.nativeVideo && MainCtx.backdropBlurEnabled
        anchors.fill: parent
        videoSurfaceProvider: MainCtx.videoSurfaceProvider
        blurRadius: root.blurRadius
        cornerRadius: root.cornerRadius
    }
    Widgets.BackdropBlur {
        visible: MainCtx.backdropBlurEnabled
        anchors.fill: parent
        sourceItem: root.sourceItem
        radius: root.blurRadius
        cornerRadius: root.cornerRadius
    }
}
