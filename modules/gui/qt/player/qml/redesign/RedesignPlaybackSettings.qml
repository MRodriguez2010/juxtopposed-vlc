// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property bool showStatistics: false
    property bool showSubtitleTimeline: false
    property string subtitleTimelineState: "off"
    property bool reversed: false
    property bool reverseAvailable: false
    property real playbackRate: 1
    property bool rateAvailable: false
    property int sleepTimerMinutes: 0
    property var visualizationModel
    readonly property var sleepChoices: [
        {label: qsTr("Off"), value: 0}, {label: qsTr("15 minutes"), value: 15},
        {label: qsTr("30 minutes"), value: 30}, {label: qsTr("60 minutes"), value: 60},
        {label: qsTr("90 minutes"), value: 90}
    ]
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal statisticsRequested(bool enabled)
    signal subtitleTimelineRequested(bool enabled)
    signal reverseRequested(bool reversed)
    signal rateRequested(real rate)
    signal sleepTimerRequested(int minutes)
    signal visualizationRequested(int index)
    spacing: 0

    RedesignSwitchRow {
        objectName: "showSubtitleTimelineSetting"
        Layout.fillWidth: true
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        label: qsTr("Show Subtitle Timeline on Seekbar"); checked: root.showSubtitleTimeline
        labelColor: theme.playerLabel
        onToggled: checked => root.subtitleTimelineRequested(checked)
    }
    Text {
        Layout.fillWidth: true; Layout.bottomMargin: theme.dp(10)
        visible: root.showSubtitleTimeline && root.subtitleTimelineState !== "ready" && root.subtitleTimelineState !== "off"
        text: root.subtitleTimelineState === "loading" ? qsTr("Reading subtitle times…")
            : root.subtitleTimelineState === "no-track" ? qsTr("Select a subtitle track to show its times.")
            : root.subtitleTimelineState === "empty" ? qsTr("This subtitle track has no cue times.")
            : qsTr("VLC cannot read the times for this subtitle track.")
        color: theme.foreground; font.pixelSize: theme.dp(12); wrapMode: Text.WordWrap
    }
    RedesignSwitchRow {
        objectName: "showStatisticsSetting"
        Layout.fillWidth: true
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        label: qsTr("Show Statistics"); checked: root.showStatistics
        labelColor: theme.playerLabel
        onToggled: checked => root.statisticsRequested(checked)
    }
    RedesignSwitchRow {
        objectName: "reverseSetting"
        Layout.fillWidth: true
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        label: qsTr("Reverse"); checked: root.reversed; enabled: root.reverseAvailable || root.reversed
        labelColor: theme.playerLabel
        onToggled: checked => root.reverseRequested(checked)
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.minimumHeight: theme.dp(68)
        spacing: theme.dp(12)
        Text {
            Layout.fillWidth: true
            text: qsTr("Sleep Timer"); color: theme.playerLabel
            font.pixelSize: theme.dp(14); wrapMode: Text.WordWrap
        }
        RedesignComboBox {
            objectName: "sleepTimerChoice"
            Layout.preferredWidth: theme.dp(217)
            Layout.minimumWidth: 0
            implicitHeight: theme.dp(46)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            model: root.sleepChoices; textRole: "label"; valueRole: "value"
            currentIndex: root.sleepChoices.findIndex(choice => choice.value === root.sleepTimerMinutes)
            Accessible.name: qsTr("Sleep Timer")
            onActivated: root.sleepTimerRequested(currentValue)
        }
    }
    RedesignModelChoice {
        objectName: "visualizerSetting"
        Layout.fillWidth: true
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        label: qsTr("Audio Visualizer"); emptyText: qsTr("Disabled")
        labelColor: theme.playerLabel
        choiceModel: root.visualizationModel
        labelOverrides: ({"Disable": qsTr("Disabled")})
        onSelectionRequested: index => root.visualizationRequested(index)
    }
    RedesignSettingSlider {
        objectName: "playbackRateControl"
        Layout.fillWidth: true; Layout.topMargin: theme.dp(16)
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        label: qsTr("Speed"); suffix: "x"; decimals: 5; trimTrailingZeros: true
        labelColor: theme.playerLabel
        valueColor: theme.playerLabel
        from: 0.25; to: 2; stepSize: 0.05
        inputFrom: 0.03125; inputTo: 31.25
        ticks: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
        sliderTopMargin: 10
        sliderLeftMargin: -4
        currentValue: Math.abs(root.playbackRate); enabled: root.rateAvailable
        onMoved: value => root.rateRequested(value)
    }
}
