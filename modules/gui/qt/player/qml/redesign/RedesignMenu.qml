// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQml.Models
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

C.Menu {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property Component videoBackdropContent
    property var recentModel: null
    property bool recentFilesAvailable: true
    property bool recentFilesEnabled: true
    property var profiles: []
    property string selectedProfile: ""
    readonly property string profileName: profiles.find(profile => profile.id === selectedProfile)?.name || qsTr("Default Preset")
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal actionRequested(string action)
    signal recentRequested(var mediaId)
    signal clearRecentRequested()
    signal profileRequested(string profileId)
    width: theme.dp(375)
    padding: theme.dp(4)
    focus: true
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutsideParent

    // Opens below anchor, kept inside area; closes when already open.
    function toggleFrom(anchor, area) {
        if (visible) { close(); return }
        // Exclude the opening button from outside-click dismissal. Its next
        // click must close this menu, rather than dismiss and reopen it.
        const point = anchor.mapToItem(area, 0, anchor.height)
        const local = area.mapToItem(anchor, Math.min(point.x, area.width - width), point.y)
        parent = anchor
        x = local.x; y = local.y
        open()
    }
    popupType: C.Popup.Item
    background: MenuSurface { shown: root.visible }
    delegate: MenuRow { }
    onOpened: { currentIndex = 0; itemAt(0).forceActiveFocus() }

    function activate(action) { dismiss(); actionRequested(action) }

    component MenuSurface: Rectangle {
        id: surface
        property bool shown: false
        readonly property color fill: root.lightTheme ? root.theme.background : "#191919"
        color: Qt.rgba(fill.r, fill.g, fill.b, root.theme.floatingOpacity)
        radius: root.theme.dp(10)
        Loader {
            anchors.fill: parent
            z: -1
            active: surface.shown
            sourceComponent: root.videoBackdropContent
            onLoaded: if (item.cornerRadius !== undefined)
                item.cornerRadius = Qt.binding(() => surface.radius)
        }
    }

    component MenuRow: C.MenuItem {
        id: row
        property string glyph: subMenu === recentMenu ? "menu-recent" : subMenu === profileMenu ? "menu-profile" : ""
        property string hint: ""
        property int textElide: Text.ElideRight
        implicitHeight: root.theme.dp(48)
        leftPadding: root.theme.dp(16); rightPadding: root.theme.dp(16)
        topPadding: 0; bottomPadding: 0
        hoverEnabled: true
        indicator: null
        arrow: null
        background: Rectangle { color: row.highlighted ? root.theme.hover : "transparent"; radius: root.theme.dp(6) }
        contentItem: RowLayout {
            spacing: root.theme.dp(12)
            RedesignIcon {
                Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20)
                sourceSize: Qt.size(root.theme.dp(20) * Screen.devicePixelRatio, root.theme.dp(20) * Screen.devicePixelRatio)
                name: row.checkable ? "check" : row.glyph
                color: row.checkable ? root.theme.accent : root.theme.foreground
                detailColor: Qt.darker(root.theme.accent, 1.2)
                opacity: row.checkable && !row.checked ? 0 : 1
            }
            Text {
                Layout.fillWidth: true
                text: row.text; color: root.theme.foreground
                font.pixelSize: root.theme.dp(14)
                elide: row.textElide
            }
            Text { text: row.hint; color: root.theme.foreground; opacity: 0.65; font.pixelSize: root.theme.dp(14) }
            RedesignIcon {
                visible: !!row.subMenu
                Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20)
                sourceSize: Qt.size(root.theme.dp(20) * Screen.devicePixelRatio, root.theme.dp(20) * Screen.devicePixelRatio)
                name: "chevron-right"; color: root.theme.foreground
            }
        }
        Keys.onPressed: event => {
            if (event.key !== Qt.Key_Home && event.key !== Qt.Key_End) return
            const menu = row.menu
            menu.currentIndex = event.key === Qt.Key_Home ? 0 : menu.count - 1
            menu.itemAt(menu.currentIndex).forceActiveFocus()
            event.accepted = true
        }
    }
    component MenuDivider: C.MenuSeparator {
        padding: 0
        implicitHeight: root.theme.dp(1)
        contentItem: Rectangle { implicitHeight: root.theme.dp(1); color: root.theme.border }
    }

    MenuRow { text: qsTr("Open File(s)"); glyph: "menu-file"; hint: "Ctrl+O"; onTriggered: root.activate("file") }
    MenuRow { text: qsTr("Open Folder"); glyph: "menu-folder"; hint: "Ctrl+F"; onTriggered: root.activate("directory") }
    MenuRow { text: qsTr("Open Network Stream"); glyph: "menu-network"; hint: "Ctrl+N"; onTriggered: root.activate("network") }
    MenuRow { text: qsTr("Open Disc"); glyph: "menu-disc"; hint: "Ctrl+D"; onTriggered: root.activate("disc") }
    MenuRow { text: qsTr("Open Capture Device"); glyph: "menu-capture"; hint: "Ctrl+C"; onTriggered: root.activate("capture") }
    MenuRow { text: qsTr("Convert"); glyph: "menu-convert"; hint: "Ctrl+R"; onTriggered: root.activate("convert") }
    C.Menu {
        id: recentMenu
        objectName: "redesignRecentMenu"
        title: qsTr("Open Recent")
        width: root.theme.dp(375); padding: root.padding
        popupType: C.Popup.Item
        delegate: MenuRow { }
        background: MenuSurface { shown: recentMenu.visible }
        Instantiator {
            model: root.recentFilesAvailable && root.recentFilesEnabled ? root.recentModel : null
            delegate: MenuRow {
                id: recentRow
                required property var model
                text: model.url; glyph: "video"
                textElide: Text.ElideMiddle
                RedesignToolTip { theme: root.theme; text: recentRow.text; visible: recentRow.hovered }
                onTriggered: { root.dismiss(); root.recentRequested(model.id) }
            }
            onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => recentMenu.removeItem(object)
        }
        MenuRow {
            text: !root.recentFilesAvailable ? qsTr("Recent files need the media library.") : root.recentFilesEnabled ? qsTr("No recent files") : qsTr("Recent file history is off")
            enabled: false
            visible: !root.recentFilesAvailable || !root.recentFilesEnabled || !root.recentModel || root.recentModel.count === 0
            height: visible ? implicitHeight : 0
        }
        MenuDivider { }
        MenuRow {
            text: qsTr("Clear Recent Files"); glyph: "close"
            enabled: root.recentFilesAvailable && root.recentFilesEnabled && !!root.recentModel && root.recentModel.count > 0
            onTriggered: { root.dismiss(); root.clearRecentRequested() }
        }
    }
    MenuDivider { }
    C.Menu {
        id: profileMenu
        objectName: "redesignProfileMenu"
        title: qsTr("Profile (%1)").arg(root.profileName)
        width: root.theme.dp(300); padding: root.padding
        popupType: C.Popup.Item
        delegate: MenuRow { }
        background: MenuSurface { shown: profileMenu.visible }
        Instantiator {
            model: [{id: "", name: qsTr("Default Preset")}].concat(root.profiles)
            delegate: MenuRow {
                required property var modelData
                text: modelData.name
                checkable: true
                checked: root.selectedProfile === modelData.id
                onTriggered: { root.dismiss(); root.profileRequested(modelData.id) }
            }
            onObjectAdded: (index, object) => profileMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => profileMenu.removeItem(object)
        }
    }
    MenuRow { text: qsTr("Keyboard Shortcuts"); glyph: "menu-keyboard"; onTriggered: root.activate("shortcuts") }
    MenuRow { text: qsTr("Customize Player"); glyph: "menu-customize"; onTriggered: root.activate("customize") }
    MenuRow { text: qsTr("Settings"); glyph: "menu-settings"; hint: "Ctrl+P"; onTriggered: root.activate("settings") }
    MenuRow { text: qsTr("About VLC"); glyph: "menu-about"; hint: "Shift+F1"; onTriggered: root.activate("about") }
}
