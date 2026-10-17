// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Basic as C

T.Slider {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property var timeForPosition: function(position) { return "" }
    property bool previewEnabled: false
    property url previewImage
    property Component thumbnailContent
    property Component videoBackdropContent
    Component {
        id: defaultThumbnail
        Image {
            objectName: "seekThumbnailImage"
            source: root.previewImage; cache: false; fillMode: Image.PreserveAspectFit
        }
    }
    property real previewImagePosition: -1
    property bool timelineEnabled: false
    property var timelineCues: []
    property string timelineState: "off"
    property real durationSeconds: 0
    // Keep the unbounded player position: Slider.value is clamped to the zoom.
    property real playbackPosition: value
    property int subtitleDelayMS: 0
    signal subtitleDelayRequested(int milliseconds)
    readonly property bool timelineActive: timelineEnabled && timelineState === "ready" && durationSeconds > 0 && timelineCues.length > 0
    property real timelineZoom: 1
    property real timelineCenter: 0.5
    readonly property real timelineSpan: 1 / timelineZoom
    readonly property real rangeStart: timelineActive ? Math.max(0, Math.min(1 - timelineSpan, timelineCenter - timelineSpan / 2)) : 0
    property int cueGeneration: 0
    readonly property bool cueDragging: cueDrag.pressed && cueDrag.adjusting && cueDrag.generation === cueGeneration
    readonly property real displayedDelayMS: cueDragging ? cueDrag.proposedDelay : subtitleDelayMS
    readonly property var mergedCues: {
        const merged = []
        for (const cue of timelineCues) {
            if (!Number.isFinite(cue.start) || !Number.isFinite(cue.stop) || cue.stop <= cue.start) continue
            const last = merged.length ? merged[merged.length - 1] : null
            if (last && cue.start <= last.stop) last.stop = Math.max(last.stop, cue.stop)
            else merged.push({start: cue.start, stop: cue.stop})
        }
        return merged
    }
    readonly property var projectedCues: {
        if (!timelineActive || cueTrack.width <= 0) return []
        const shift = displayedDelayMS / 1000
        const firstTime = from * durationSeconds - shift
        const lastTime = to * durationSeconds - shift
        let low = 0, high = mergedCues.length
        while (low < high) {
            const mid = Math.floor((low + high) / 2)
            if (mergedCues[mid].stop <= firstTime) low = mid + 1
            else high = mid
        }
        const blocks = []
        const factor = cueTrack.width / ((to - from) * durationSeconds)
        for (let i = low; i < mergedCues.length && mergedCues[i].start < lastTime; ++i) {
            const cue = mergedCues[i]
            const left = Math.max(0, (cue.start - firstTime) * factor)
            const right = Math.min(cueTrack.width, Math.max(left + 1, (cue.stop - firstTime) * factor))
            const prior = blocks.length ? blocks[blocks.length - 1] : null
            if (prior && left <= prior.stop + 1) prior.stop = Math.max(prior.stop, right)
            else blocks.push({start: left, stop: right})
        }
        return blocks
    }
    function cueAt(x) {
        return projectedCues.some(cue => x >= cue.start && x <= cue.stop)
    }
    function positionAt(x) { return from + Math.max(0, Math.min(1, x / Math.max(1, cueTrack.width))) * (to - from) }
    function zoomTimeline(factor) {
        timelineCenter = value
        timelineZoom = Math.max(1, Math.min(Math.max(1, durationSeconds / 2), timelineZoom * factor))
    }
    onTimelineActiveChanged: { ++cueGeneration; timelineZoom = 1; timelineCenter = value }
    onTimelineCuesChanged: { ++cueGeneration; timelineZoom = 1; timelineCenter = value }
    onSubtitleDelayMSChanged: if (cueDrag.pressed) ++cueGeneration
    onPlaybackPositionChanged: {
        if (timelineActive && timelineZoom > 1 && !pressed && !cueDrag.pressed
            && (playbackPosition < from || playbackPosition > to)) timelineCenter = playbackPosition
    }
    readonly property bool previewActive: enabled && visible && previewEnabled && !cueDragging && (hovered || pressed || visualFocus)
    readonly property real previewPosition: pressed || visualFocus && !hovered ? value
        : from + Math.max(0, Math.min(1, (pointer.point.position.x - leftPadding - handle.width / 2) / Math.max(1, availableWidth - handle.width))) * (to - from)
    readonly property bool previewReady: previewActive && previewImage.toString().length > 0
        && previewImagePosition >= 0 && !!thumbnail.item && thumbnail.item.status === Image.Ready
    signal previewRequested(real position)
    signal previewEnded()
    function refreshPreview() {
        previewEnded()
        if (previewActive) previewDelay.restart()
    }
    onPreviewPositionChanged: if (previewActive && !previewDelay.running) previewDelay.start()
    onPreviewActiveChanged: {
        if (previewActive) previewDelay.restart()
        else { previewDelay.stop(); previewEnded() }
    }
    Component.onDestruction: previewEnded()
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    implicitHeight: theme.dp(28)
    implicitWidth: theme.dp(200)
    padding: theme.dp(2)
    leftPadding: timelineActive ? theme.dp(52) : padding
    rightPadding: timelineActive ? theme.dp(52) : padding
    from: rangeStart
    to: timelineActive ? rangeStart + timelineSpan : 1
    stepSize: 0.005 / timelineZoom
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    Accessible.name: qsTr("Playback position")

    background: Rectangle {
        color: theme.field
        radius: theme.dp(6)
        border.color: root.visualFocus ? theme.accent : "transparent"
        border.width: theme.dp(1)
        Rectangle {
            x: root.leftPadding
            y: root.topPadding
            width: root.visualPosition * (root.availableWidth - root.handle.width) + root.handle.width
            height: root.availableHeight
            radius: theme.dp(4)
            color: theme.progress
            visible: root.value > root.from
        }
    }
    Item {
        id: cueTrack
        x: root.leftPadding + root.handle.width / 2
        y: root.topPadding + root.theme.dp(2)
        width: Math.max(0, root.availableWidth - root.handle.width)
        height: Math.max(0, root.availableHeight - root.theme.dp(4))
        visible: root.timelineActive
        Repeater {
            model: root.projectedCues
            Rectangle {
                required property var modelData
                x: modelData.start; width: modelData.stop - modelData.start
                height: cueTrack.height; radius: root.theme.dp(2)
                color: root.theme.subtitleCue
                Rectangle {
                    width: Math.max(0, Math.min(parent.width, root.visualPosition * cueTrack.width - parent.x))
                    height: parent.height; radius: parent.radius
                    color: root.theme.subtitleCueProgress
                }
            }
        }
        MouseArea {
            id: cueDrag
            objectName: "subtitleCueDragArea"
            anchors.fill: parent
            preventStealing: true
            property real originX: 0
            property int originDelay: 0
            property int proposedDelay: 0
            property bool adjusting: false
            property int generation: -1
            onPressed: mouse => {
                if (!root.cueAt(mouse.x)) { mouse.accepted = false; return }
                root.forceActiveFocus()
                originX = mouse.x; originDelay = root.subtitleDelayMS
                proposedDelay = originDelay; adjusting = false
                generation = root.cueGeneration
            }
            onPositionChanged: mouse => {
                if (!pressed || generation !== root.cueGeneration) return
                if (Math.abs(mouse.x - originX) >= root.theme.dp(6)) adjusting = true
                if (adjusting) proposedDelay = Math.round(originDelay + (mouse.x - originX) / Math.max(1, width) * (root.to - root.from) * root.durationSeconds * 1000)
            }
            onReleased: mouse => {
                if (generation !== root.cueGeneration) { adjusting = false; return }
                if (adjusting) root.subtitleDelayRequested(proposedDelay)
                else { root.value = root.positionAt(mouse.x); root.moved() }
                adjusting = false
            }
            onCanceled: adjusting = false
        }
    }
    component TimelineButton: RedesignButton {
        width: root.theme.dp(22); height: root.availableHeight
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        accent: true; captionFontSize: 22
        background: Rectangle {
            color: parent.down ? Qt.darker(root.theme.accent, 1.15) : parent.hovered ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent
            radius: root.theme.dp(3)
            border.width: parent.visualFocus ? 1 : 0; border.color: root.theme.accent
            opacity: parent.enabled ? 1 : 0.35
        }
    }
    Row {
        visible: root.timelineActive
        x: root.theme.dp(3); y: root.topPadding
        spacing: root.theme.dp(2)
        TimelineButton {
            objectName: "subtitleEarlierButton"; caption: "‹"
            text: qsTr("Show subtitles 0.1 seconds earlier")
            onClicked: root.subtitleDelayRequested(root.subtitleDelayMS - 100)
        }
        TimelineButton {
            objectName: "subtitleZoomOutButton"; caption: "−"
            text: qsTr("Zoom out on subtitle times"); enabled: root.timelineZoom > 1
            onClicked: root.zoomTimeline(0.5)
        }
    }
    Row {
        visible: root.timelineActive
        x: root.width - width - root.theme.dp(3); y: root.topPadding
        spacing: root.theme.dp(2)
        TimelineButton {
            objectName: "subtitleZoomInButton"; caption: "+"
            text: qsTr("Zoom in on subtitle times"); enabled: root.timelineZoom < Math.max(1, root.durationSeconds / 2)
            onClicked: root.zoomTimeline(2)
        }
        TimelineButton {
            objectName: "subtitleLaterButton"; caption: "›"
            text: qsTr("Show subtitles 0.1 seconds later")
            onClicked: root.subtitleDelayRequested(root.subtitleDelayMS + 100)
        }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding
        width: theme.dp(8)
        height: root.availableHeight
        radius: theme.dp(4)
        color: theme.accent
        opacity: root.enabled ? 1 : 0.35
    }
    HoverHandler { id: pointer }
    Timer {
        id: previewDelay
        interval: 160
        onTriggered: if (root.previewActive) root.previewRequested(root.previewPosition)
    }
    C.Popup {
        id: preview
        objectName: "seekThumbnailPopup"
        visible: root.previewReady
        focus: false; modal: false
        closePolicy: C.Popup.NoAutoClose
        width: root.theme.dp(272); height: root.theme.dp(189)
        padding: root.theme.dp(10)
        x: {
            if (!root.Window.window) return 0
            const left = root.mapToItem(root.Window.window.contentItem, 0, 0).x
            const cursor = root.leftPadding + root.handle.width / 2 + (root.previewPosition - root.from) / (root.to - root.from) * (root.availableWidth - root.handle.width)
            return Math.max(-left, Math.min(cursor - width / 2, root.Window.window.width - left - width))
        }
        y: -height - root.theme.dp(12)
        background: Rectangle {
            radius: root.theme.dp(14)
            color: root.lightTheme ? Qt.rgba(root.theme.panel.r, root.theme.panel.g, root.theme.panel.b, root.theme.floatingOpacity) : Qt.rgba(25 / 255, 25 / 255, 25 / 255, root.theme.floatingOpacity)
            Loader {
                anchors.fill: parent
                z: -1
                active: preview.visible
                sourceComponent: root.videoBackdropContent
                onLoaded: if (item && item.cornerRadius !== undefined)
                    item.cornerRadius = Qt.binding(() => root.theme.dp(14))
            }
        }
        contentItem: Item {
            Rectangle {
                width: parent.width; height: root.theme.dp(142); radius: root.theme.dp(4)
                color: "#000000"
                Loader {
                    id: thumbnail
                    anchors.fill: parent
                    clip: true
                    sourceComponent: root.thumbnailContent || defaultThumbnail
                }
            }
            Text {
                objectName: "seekThumbnailTime"
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                text: root.timeForPosition(root.previewImagePosition)
                font.pixelSize: root.theme.dp(14); color: root.theme.foreground
            }
        }
    }
    RedesignToolTip { theme: root.theme; text: root.cueDragging ? qsTr("Subtitle delay: %1 s").arg((root.displayedDelayMS / 1000).toFixed(3)) : root.timeForPosition(root.previewPosition); visible: root.enabled && (root.hovered || root.pressed || root.visualFocus || root.cueDragging) && !root.previewReady; delay: 0 }
}
