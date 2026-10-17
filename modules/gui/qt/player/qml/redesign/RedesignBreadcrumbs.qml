// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls.Basic as C

C.Control {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property Component videoBackdropContent
    property bool boldCurrent: false
    property var entries: []
    signal activated(int index)
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    readonly property real separatorWidth: theme.dp(14)
    readonly property real overflowWidth: theme.dp(20)
    readonly property var widths: {
        // Measurement methods do not establish a dependency on their font.
        const normalFont = metrics.font
        const boldFont = currentMetrics.font
        return entries.map((entry, index) => Math.ceil(index === entries.length - 1 && boldCurrent
            ? currentMetrics.advanceWidth(entry.label) : metrics.advanceWidth(entry.label)))
    }
    readonly property int firstVisible: {
        let total = widths.reduce((sum, value) => sum + value, 0) + Math.max(0, widths.length - 1) * separatorWidth
        if (total <= width) return 0
        for (let first = 1; first < widths.length; ++first) {
            total -= widths[first - 1] + separatorWidth
            if (total + overflowWidth + separatorWidth <= width) return first
        }
        return Math.max(0, widths.length - 1)
    }
    readonly property real precedingWidth: firstVisible > 0 ? overflowWidth + separatorWidth
        + widths.slice(firstVisible, -1).reduce((sum, value) => sum + value + separatorWidth, 0)
        : widths.slice(0, -1).reduce((sum, value) => sum + value + separatorWidth, 0)
    implicitWidth: widths.reduce((sum, value) => sum + value, 0) + Math.max(0, widths.length - 1) * separatorWidth
    implicitHeight: theme.dp(36)
    font.pixelSize: theme.dp(16)
    font.weight: Font.Normal
    clip: true
    FontMetrics { id: metrics; font.family: root.font.family; font.pixelSize: root.font.pixelSize; font.weight: Font.Normal }
    FontMetrics { id: currentMetrics; font.family: root.font.family; font.pixelSize: root.font.pixelSize; font.weight: Font.DemiBold }
    onEntriesChanged: ancestors.close()
    RedesignActionMenu {
        id: ancestors
        videoBackdropContent: root.videoBackdropContent
        objectName: "libraryAncestorMenu"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        entries: root.entries.slice(0, root.firstVisible).map((entry, index) => ({action: index.toString(), label: entry.label}))
        onActionRequested: action => root.activated(Number(action))
    }
    component PathButton: C.Button {
        id: button
        implicitHeight: root.theme.dp(36)
        padding: 0
        horizontalPadding: 0
        hoverEnabled: true
        font.family: root.font.family
        font.pixelSize: root.font.pixelSize
        font.weight: Font.Normal
        Accessible.name: text
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        background: Rectangle {
            radius: root.theme.dp(4)
            color: button.down || button.hovered && button.enabled ? root.theme.hover : "transparent"
            border.width: button.visualFocus ? root.theme.dp(2) : 0
            border.color: root.theme.accent
        }
        contentItem: Text {
            text: button.text; font: button.font
            color: root.theme.foreground
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        property string toolTipText: text
        RedesignToolTip {
            theme: root.theme
            text: button.toolTipText
            visible: button.hovered || button.visualFocus
        }
    }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        PathButton {
            id: overflow
            objectName: "libraryPathOverflow"
            visible: root.firstVisible > 0
            width: root.overflowWidth
            text: "..."
            Accessible.name: qsTr("Parent locations")
            toolTipText: qsTr("Parent locations")
            onClicked: ancestors.popup(overflow, 0, height)
        }
        Repeater {
            model: root.entries
            Row {
                required property int index
                required property var modelData
                visible: index >= root.firstVisible
                Item {
                    visible: index > 0
                    width: visible ? root.separatorWidth : 0
                    height: root.theme.dp(36)
                    RedesignSvg {
                        anchors.centerIn: parent
                        width: root.theme.dp(6); height: root.theme.dp(8)
                        svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 6 8"><path d="M0 0 6 4 0 8Z" fill="' + root.theme.foreground + '"/></svg>'
                    }
                }
                PathButton {
                    objectName: "libraryPath" + index
                    width: index === root.entries.length - 1 ? Math.min(root.widths[index], Math.max(0, root.width - root.precedingWidth)) : root.widths[index]
                    text: modelData.label
                    font.weight: root.boldCurrent && index === root.entries.length - 1 ? Font.DemiBold : Font.Normal
                    enabled: index < root.entries.length - 1
                    onClicked: root.activated(index)
                }
            }
        }
    }
}
