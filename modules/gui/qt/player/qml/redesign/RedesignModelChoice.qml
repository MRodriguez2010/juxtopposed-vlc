// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQml.Models

RowLayout {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property string label
    property color labelColor: theme.foreground
    property string emptyText
    property var choiceModel
    property var labelOverrides: ({})
    property bool fullWidth: false
    property int revision: 0
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    readonly property int selectedIndex: {
        revision
        for (let i = 0; i < entries.count; ++i) {
            const entry = entries.objectAt(i)
            if (entry && entry.checked) return i
        }
        return -1
    }
    signal selectionRequested(int index)
    Layout.minimumHeight: theme.dp(fullWidth ? 46 : 68)
    spacing: theme.dp(12)
    Text {
        visible: !root.fullWidth
        Layout.fillWidth: true
        text: root.label; color: root.labelColor
        font.pixelSize: theme.dp(14); wrapMode: Text.WordWrap
    }
    Instantiator {
        id: entries
        model: root.choiceModel
        delegate: QtObject { required property bool checked }
        onObjectAdded: root.revision++
        onObjectRemoved: root.revision++
    }
    RedesignComboBox {
        objectName: "modelChoiceField"
        Layout.fillWidth: root.fullWidth
        Layout.preferredWidth: root.fullWidth ? 1 : theme.dp(217)
        Layout.minimumWidth: 0
        implicitHeight: theme.dp(46)
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        model: root.choiceModel; textRole: "display"
        currentIndex: root.selectedIndex
        labelOverrides: root.labelOverrides
        displayText: currentIndex < 0 ? root.emptyText : root.labelOverrides[currentText] || currentText
        enabled: count > 0
        opacity: enabled ? 1 : 0.5
        Accessible.name: root.label
        onActivated: index => root.selectionRequested(index)
    }
}
