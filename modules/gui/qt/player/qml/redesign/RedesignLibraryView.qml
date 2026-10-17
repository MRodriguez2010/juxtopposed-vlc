// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

Item {
    id: root
    property real scaleFactor: 1
    property color accentColor: "#d37918"
    property bool lightTheme: false
    property Component videoBackdropContent
    property var mediaModel
    readonly property int libraryMediaCount: mediaView.count
    property int itemCount: libraryMediaCount
    property bool homeSectionsVisible: category === 0
    property var homeSections: []
    property int category: 1
    property string heading: qsTr("Videos")
    property var breadcrumbs: []
    property var pins: []
    property string selectedPinId: ""
    property var locationPinTarget
    property bool locationPinned: false
    property var menuForItem: (index, section) => null
    property string searchText: ""
    property bool grid: false
    property bool expanded: false
    property bool playlistOpen: false
    property bool playlistEditing: false
    property bool playlistBusy: false
    property string playlistKey: ""
    property string playlistEditMessage: ""
    property int dragDestination: -1
    readonly property bool wideToolbar: expanded && width >= theme.dp(1000)
    readonly property bool squareCards: category === 2 || showingFolders
    property var settingsContext
    property string sortScope: "media"
    property var sortFields: ["played", "insertion", "title", "main_artist", "album_title", "track_number", "uri", "disc_number"]
    property string defaultSortChoice: "unwatched"
    property var extraSortOptions: []
    readonly property alias sortState: sorting
    readonly property bool descending: sorting.selection.descending
    readonly property string sortField: sorting.selection.field
    property bool canGoBack: false
    property bool canGoForward: false
    property bool canEnqueue: true
    property string defaultItemIcon: category === 4 ? "queue" : category === 2 ? "music" : "video"
    property bool showingFolders: false
    property bool showAddRow: category > 0 && category < 5
    property string addLabel: playlistOpen ? qsTr("Add files") : category === 4 ? qsTr("Create playlist") : category === 3 ? qsTr("Add Network Stream") : qsTr("Add")
    property string emptyText: qsTr("Add a folder to your library to see your media here.")
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    signal homeActivated(string section, int index)
    signal homeEnqueueRequested(string section, int index)
    signal homeSectionRequested(string section)
    signal categoryRequested(int category)
    signal activated(int index)
    signal enqueueRequested(int index)
    signal addRequested()
    signal filesRequested()
    signal folderRequested()
    signal fullLibraryRequested()
    signal backRequested()
    signal forwardRequested()
    signal newPlaylistRequested()
    signal preferencesRequested()
    signal breadcrumbActivated(int index)
    signal pinActivated(var pin)
    signal pinRemoved(var pin)
    signal pinEnqueueRequested(var pin)
    signal pinLocationRequested()
    signal itemActionRequested(var target, string action)
    signal playlistEditRequested()
    signal playlistMoveRequested(int from, int to, var id)
    signal playlistRemoveRequested(int row, var id)
    signal playlistFilesDropped(var urls)

    function nameFromUrl(url) {
        const value = url.toString()
        const name = value.replace(/\\/g, "/").replace(/\/+$/, "").split("/").pop()
        if (!name || name === "file:") return "/"
        if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) return name
        try { return decodeURIComponent(name) } catch (error) { return name }
    }
    function addMedia() {
        if (playlistOpen && playlistBusy) return
        if (category === 4 && !playlistOpen) newPlaylistRequested()
        else addRequested()
    }
    RedesignLibrarySort {
        id: sorting
        ctx: root.settingsContext; scope: root.sortScope
        fields: root.sortFields; defaultChoice: root.defaultSortChoice; extraOptions: root.extraSortOptions
    }
    property var sortPopup: null
    Component {
        id: sortMenuComponent
        RedesignActionMenu {
            id: menu
            videoBackdropContent: root.videoBackdropContent
            objectName: "librarySortMenu"
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            checkedAction: sorting.selection.id
            onActionRequested: action => sorting.select(action)
            onOpened: currentIndex = sorting.options.findIndex(option => option.id === sorting.selection.id)
            onClosed: {
                if (root.sortPopup === menu) root.sortPopup = null
                destroy()
            }
        }
    }
    Connections {
        target: sorting
        function onOptionsChanged() { if (root.sortPopup) root.sortPopup.close() }
    }
    function openSortMenu(anchor) {
        if (sortPopup) { sortPopup.close(); return }
        sortPopup = sortMenuComponent.createObject(root, {
            entries: sorting.options.map(option => ({action: option.id, label: option.label}))
        })
        sortPopup.popup(anchor, 0, anchor.height)
    }
    property int menuRequest: 0
    onBreadcrumbsChanged: { ++menuRequest; itemMenu.close() }
    function openItemMenu(anchor, index, point, section) {
        const request = ++menuRequest
        const context = menuForItem(index, section || "")
        function show(context) {
            if (request !== menuRequest || !anchor || !root.visible || !context || !context.target || !context.entries.length) return
            itemMenu.target = context.target
            itemMenu.entries = context.entries
            itemMenu.popup(anchor, point)
        }
        if (context && typeof context.then === "function") context.then(show)
        else show(context)
    }
    RedesignActionMenu {
        id: itemMenu
        videoBackdropContent: root.videoBackdropContent
        objectName: "libraryItemMenu"
        property var target
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        onActionRequested: action => { itemMenu.close(); root.itemActionRequested(target, action) }
    }
    RedesignActionMenu {
        id: moreMenu
        videoBackdropContent: root.videoBackdropContent
        objectName: "libraryMoreMenu"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        entries: root.locationPinTarget && root.locationPinTarget.kind === "folder" ? [
            {action: "add-files", label: qsTr("Add File"), icon: "add"},
            {action: "add-folder", label: qsTr("Add Folder"), icon: "new-folder-two-tone", accent: true},
            {action: "subtitle-tracks", label: qsTr("Edit Subtitle Tracks"), icon: "subtitles-two-tone", accent: true},
            {action: "audio-tracks", label: qsTr("Edit Audio Tracks"), icon: "audio-two-tone", accent: true},
            {action: "resync", label: qsTr("Resync"), icon: "refresh-two-tone", accent: true},
            {action: "folder-info", label: qsTr("Info"), icon: "info-two-tone", accent: true}
        ] : ([1,2].includes(root.category) && !root.playlistOpen ? [
            {action: "add-files", label: qsTr("Add File"), icon: "add"},
            {action: "add-folder", label: qsTr("Add Folder"), icon: "new-folder-two-tone", accent: true}
        ] : [{action: "add", label: root.addLabel, icon: "add", enabled: !root.playlistOpen || !root.playlistBusy}])
            .concat([{action: "settings", label: qsTr("Library settings"), icon: "settings"}])
            .concat(root.playlistOpen ? [{action: "edit-playlist", label: root.playlistEditing ? qsTr("Done") : qsTr("Edit playlist"), icon: root.playlistEditing ? "check" : "drag", enabled: !root.playlistBusy}] : [])
            .concat(root.playlistOpen && root.locationPinTarget ? [
                {action: "add-playlist", label: qsTr("Add to Playlist"), icon: "playlist", accent: true},
                {action: "properties", label: qsTr("Properties & Metadata"), icon: "info-two-tone", accent: true}] : [])
            .concat(root.locationPinTarget ? [{action: "pin", label: root.locationPinned ? qsTr("Remove from sidebar") : qsTr("Add to sidebar"), icon: root.locationPinned ? "favorite-active" : "favorite", accent: true}] : [])
            .concat(root.expanded ? [{action: "compact", label: qsTr("Open compact library"), icon: "sidebar"}] : [])
        onActionRequested: action => {
            moreMenu.close()
            if (action === "add") root.addMedia()
            else if (action === "add-files") root.filesRequested()
            else if (action === "add-folder") root.folderRequested()
            else if (action === "edit-playlist") root.playlistEditRequested()
            else if (action === "pin") root.pinLocationRequested()
            else if (["add-playlist", "properties", "resync", "folder-info", "subtitle-tracks", "audio-tracks"].includes(action)) root.itemActionRequested(root.locationPinTarget, action)
            else if (action === "compact") root.fullLibraryRequested()
            else root.preferencesRequested()
        }
    }
    RedesignActionMenu {
        id: viewMenu
        videoBackdropContent: root.videoBackdropContent
        objectName: "libraryViewMenu"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        checkedAction: root.grid ? "grid" : "list"
        entries: [
            { action: "grid", label: qsTr("Grid View"), icon: "grid" },
            { action: "list", label: qsTr("List View"), icon: "list-view" }
        ]
        onActionRequested: action => root.grid = action === "grid"
    }

    RedesignLibraryNavigation {
        id: rail
        videoBackdropContent: root.videoBackdropContent
        objectName: "libraryNavigation"
        x: root.expanded ? theme.dp(8) : 0
        anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.topMargin: root.expanded ? theme.dp(8) : 0
        anchors.bottomMargin: root.expanded ? theme.dp(8) : 0
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        expanded: root.expanded; category: root.category
        pins: root.pins; selectedPinId: root.selectedPinId
        onCategoryRequested: category => root.categoryRequested(category)
        onAddRequested: root.addRequested()
        onPinActivated: pin => root.pinActivated(pin)
        onPinRemoved: pin => root.pinRemoved(pin)
        onPinEnqueueRequested: pin => root.pinEnqueueRequested(pin)
    }
    DropArea {
        id: playlistDrop
        anchors.fill: parent
        enabled: root.playlistOpen && !root.playlistBusy
        onEntered: drag => drag.accepted = drag.hasUrls
        onDropped: drop => { if (drop.hasUrls) { root.playlistFilesDropped(drop.urls); drop.acceptProposedAction() } }
    }
    Rectangle {
        anchors.fill: parent; anchors.leftMargin: rail.width
        color: "transparent"; border.color: root.theme.accent; border.width: root.theme.dp(2)
        visible: playlistDrop.containsDrag
    }
    property bool searchOpen: false
    component LibraryButton: RedesignButton {
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
    }
    component BackButton: LibraryButton {
        objectName: "libraryBackButton"
        iconName: "back"; text: qsTr("Back"); enabled: root.canGoBack
        onClicked: root.backRequested()
    }
    component ForwardButton: LibraryButton {
        iconName: "forward"; text: qsTr("Forward"); enabled: root.canGoForward
        onClicked: root.forwardRequested()
    }
    component MoreButton: LibraryButton {
        id: button
        objectName: "libraryMoreButton"
        iconName: "more"; text: qsTr("More library actions")
        onClicked: moreMenu.popup(button, 0, height)
    }
    component SortButton: LibraryButton {
        id: button
        objectName: "librarySortButton"
        enabled: sorting.options.length > 0
        iconName: enabled && (root.sortPopup || sorting.selection.id !== root.defaultSortChoice) ? "sort-active" : "sort"
        iconDetailColor: root.theme.accent
        text: qsTr("Sort options")
        onClicked: root.openSortMenu(button)
    }
    component ViewButton: LibraryButton {
        id: button
        objectName: "libraryViewButton"
        iconName: root.grid ? "grid" : "list-view"; text: qsTr("View options")
        onClicked: viewMenu.popup(button, 0, height)
    }
    component ItemCount: Text {
        text: qsTr("%n item", "%n items", root.itemCount)
        color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
    }
    component Location: RedesignBreadcrumbs {
        videoBackdropContent: root.videoBackdropContent
        objectName: "libraryLocation"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        boldCurrent: root.expanded
        entries: root.breadcrumbs.length ? root.breadcrumbs : [{label: root.heading}]
        onActivated: index => root.breadcrumbActivated(index)
    }
    component SearchField: C.TextField {
        objectName: "librarySearchField"
        placeholderText: qsTr("Search")
        text: root.searchText
        onTextEdited: root.searchText = text
        color: root.theme.bright
        font.pixelSize: root.theme.dp(14)
        implicitHeight: root.theme.dp(34)
        leftPadding: root.expanded ? root.theme.dp(42) : root.theme.dp(10)
        background: Rectangle { color: root.theme.field; radius: root.theme.dp(6); border.width: parent.activeFocus ? 1 : 0; border.color: root.theme.accent }
        RedesignIcon { visible: root.expanded; x: root.theme.dp(12); anchors.verticalCenter: parent.verticalCenter; width: root.theme.dp(24); height: width; name: "search"; color: root.theme.foreground }
    }
    Component {
        id: compactToolbar
        ColumnLayout {
            spacing: root.theme.dp(10)
            RowLayout {
                Layout.fillWidth: true; Layout.rightMargin: -root.theme.dp(6)
                spacing: 0
                BackButton {}
                ForwardButton {}
                Location { Layout.fillWidth: true }
                MoreButton {}
                LibraryButton {
                    objectName: "expandLibraryButton"
                    iconName: "expand"; text: qsTr("Open full library")
                    onClicked: root.fullLibraryRequested()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                ItemCount { Layout.fillWidth: true }
                SortButton {}
                ViewButton {}
                LibraryButton {
                    iconName: "search"; text: qsTr("Search library"); selected: root.searchOpen
                    onClicked: {
                        root.searchOpen = !root.searchOpen
                        if (root.searchOpen) compactSearch.forceActiveFocus()
                        else root.searchText = ""
                    }
                }
            }
            SearchField { id: compactSearch; visible: root.searchOpen || root.searchText.length > 0; Layout.fillWidth: true }
        }
    }
    Component {
        id: expandedToolbar
        RowLayout {
            spacing: root.theme.dp(4)
            BackButton {}
            ForwardButton {}
            Location { Layout.fillWidth: true }
            ItemCount { Layout.rightMargin: root.theme.dp(12) }
            SortButton {}
            ViewButton {}
            SearchField { Layout.preferredWidth: Math.min(root.theme.dp(325), root.width * 0.24); Layout.leftMargin: root.theme.dp(12); Layout.rightMargin: root.theme.dp(12) }
            LibraryButton { visible: root.showAddRow; enabled: !root.playlistOpen || !root.playlistBusy; iconName: "add"; text: root.addLabel; onClicked: root.addMedia() }
            MoreButton {}
        }
    }
    ColumnLayout {
        anchors { top: parent.top; bottom: parent.bottom; left: rail.right; right: parent.right; margins: theme.dp(20); leftMargin: theme.dp(root.expanded ? 28 : 20); topMargin: theme.dp(root.wideToolbar ? 20 : 12) }
        spacing: theme.dp(root.wideToolbar ? 16 : 10)
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: root.wideToolbar ? theme.dp(34) : implicitHeight
            sourceComponent: root.wideToolbar ? expandedToolbar : compactToolbar
        }
        Rectangle { Layout.fillWidth: true; height: theme.dp(1); color: theme.border }
        RowLayout {
            Layout.fillWidth: true
            visible: root.playlistEditing || root.playlistEditMessage.length > 0
            Text {
                Layout.fillWidth: true
                text: root.playlistEditMessage || (root.playlistBusy ? qsTr("Saving…") : qsTr("Changes are saved automatically."))
                color: root.playlistEditMessage.length ? root.theme.danger : root.theme.foreground
                font.pixelSize: root.theme.dp(14); wrapMode: Text.WordWrap
            }
            LibraryButton {
                objectName: "playlistDoneButton"
                visible: root.playlistEditing
                caption: qsTr("Done"); text: caption; enabled: !root.playlistBusy
                onClicked: root.playlistEditRequested()
            }
        }
        RedesignButton {
            objectName: "libraryAddRow"
            visible: root.showAddRow && !root.expanded
            Layout.topMargin: theme.dp(5)
            Layout.fillWidth: true
            implicitHeight: theme.dp(42)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            text: root.addLabel
            enabled: !root.playlistOpen || !root.playlistBusy
            onClicked: root.addMedia()
            contentItem: Row {
                spacing: theme.dp(10)
                Item {
                    width: theme.dp(32); height: theme.dp(42)
                    RedesignIcon { anchors.centerIn: parent; width: theme.dp(24); height: width; name: "add"; color: theme.foreground }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: root.addLabel; color: theme.foreground; font.pixelSize: theme.dp(14) }
            }
        }
        RedesignHomeView {
            objectName: "libraryHomeView"
            visible: root.homeSectionsVisible
            Layout.topMargin: theme.dp(root.expanded ? 25 : 9)
            Layout.fillWidth: true; Layout.fillHeight: true
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            expanded: root.expanded
            searchText: root.searchText
            sections: root.homeSectionsVisible ? root.homeSections : []
            onActivated: (section, index) => root.homeActivated(section, index)
            onEnqueueRequested: (section, index) => root.homeEnqueueRequested(section, index)
            onSectionRequested: section => root.homeSectionRequested(section)
            onContextRequested: (section, index, anchor, point) => root.openItemMenu(anchor, index, point, section)
        }
        GridView {
            id: mediaView
            objectName: "libraryMediaView"
            Layout.topMargin: root.expanded ? theme.dp(4) : root.showAddRow ? -theme.dp(10) : theme.dp(5)
            Layout.rightMargin: root.expanded ? -theme.dp(20) : 0
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            model: root.mediaModel
            visible: !root.homeSectionsVisible && root.itemCount > 0
            cellWidth: root.expanded ? Math.min(width, theme.dp(root.grid ? root.squareCards ? 220 : 336 : 416)) : root.grid ? width / Math.max(1, Math.floor(width / theme.dp(130))) : width
            cellHeight: root.grid ? root.expanded ? (cellWidth - theme.dp(20)) * (root.squareCards ? 1 : 9 / 16) + theme.dp(root.category === 2 ? 88 : 78) : theme.dp(142) : theme.dp(42)
            keyNavigationEnabled: true
            currentIndex: -1
            C.ScrollBar.vertical: C.ScrollBar { policy: C.ScrollBar.AsNeeded }
            delegate: Item {
                id: delegate
                required property int index
                required property var model
                width: mediaView.cellWidth - (root.expanded ? theme.dp(20) : 0)
                height: mediaView.cellHeight
                readonly property string itemTitle: model.title || model.name || model.fileName || (model.url ? root.nameFromUrl(model.url) : "")
                readonly property string itemArtist: model.main_artist || ""
                readonly property string displayTitle: itemTitle + ((!root.expanded || !root.grid) && itemArtist ? " - " + itemArtist : "")
                readonly property string itemArtwork: model.thumbnail || model.small_cover || model.cover || ""
                RedesignButton {
                    id: grip
                    objectName: "playlistGrip" + delegate.index
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: theme.dp(24); implicitHeight: theme.dp(36)
                    visible: root.playlistEditing && !root.grid; enabled: !root.playlistBusy
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    iconName: "drag"; text: qsTr("Move playlist item")
                    onClicked: { mediaView.currentIndex = delegate.index; mediaButton.forceActiveFocus() }
                    DragHandler {
                        id: rowMover
                        target: null; enabled: grip.enabled && grip.visible
                        property int from: -1
                        property int to: -1
                        property var originId
                        property string originPlaylist: ""
                        onActiveChanged: {
                            if (active) { from = delegate.index; to = from; originId = delegate.model.id; originPlaylist = root.playlistKey; mediaView.currentIndex = from }
                            else if (from >= 0) {
                                if (root.visible && root.playlistEditing && originPlaylist === root.playlistKey && from !== to)
                                    root.playlistMoveRequested(from, to, originId)
                                from = -1; root.dragDestination = -1
                            }
                        }
                        onCentroidChanged: if (active) {
                            const point = grip.mapToItem(mediaView, centroid.position.x, centroid.position.y)
                            const index = mediaView.indexAt(point.x + mediaView.contentX, point.y + mediaView.contentY)
                            to = index >= 0 ? index : point.y < 0 ? 0 : root.itemCount - 1
                            root.dragDestination = to
                        }
                        onCanceled: { from = -1; root.dragDestination = -1 }
                    }
                }
                RedesignButton {
                    id: mediaButton
                    objectName: "libraryMediaItem" + delegate.index
                    anchors.fill: parent
                    anchors.margins: 0
                    anchors.leftMargin: root.playlistEditing && !root.grid ? theme.dp(28) : 0
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    text: delegate.displayTitle
                    selected: mediaView.currentIndex === delegate.index
                    onClicked: { mediaView.currentIndex = delegate.index; if (root.playlistEditing) forceActiveFocus(); else root.activated(delegate.index) }
                    Keys.onMenuPressed: root.openItemMenu(this, delegate.index, Qt.point(0, height), "")
                    Keys.onPressed: event => {
                        if (root.playlistEditing && !root.playlistBusy && event.key === Qt.Key_Delete) {
                            root.playlistRemoveRequested(delegate.index, delegate.model.id); event.accepted = true
                        } else if (root.playlistEditing && !root.playlistBusy && event.modifiers & Qt.AltModifier && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                            const target = delegate.index + (event.key === Qt.Key_Up ? -1 : 1)
                            if (target >= 0 && target < root.itemCount) root.playlistMoveRequested(delegate.index, target, delegate.model.id)
                            event.accepted = true
                        } else if (event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier) {
                            root.openItemMenu(this, delegate.index, Qt.point(0, height), ""); event.accepted = true
                        } else event.accepted = false
                    }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: event => root.openItemMenu(mediaButton, delegate.index, event.position, "") }
                    contentItem: Item {
                        RedesignLibraryArtwork {
                            id: thumbnail
                            objectName: "libraryArtwork" + delegate.index
                            x: root.grid && !root.expanded ? theme.dp(4) : 0
                            y: root.grid ? 0 : (parent.height - height) / 2
                            width: root.grid ? parent.width - (root.expanded ? 0 : theme.dp(8)) : theme.dp(32)
                            height: root.grid ? root.expanded ? width * (root.squareCards ? 1 : 9 / 16) : theme.dp(90) : theme.dp(32)
                            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                            cornerRadius: root.grid && root.expanded ? 12 : 2
                            iconName: model.fileIsDir || root.showingFolders ? "folder" : model.iconName || root.defaultItemIcon
                            iconSize: root.grid && root.expanded ? 48 : 24
                            source: delegate.itemArtwork
                            progress: root.grid ? Number(model.progress || 0) : 0
                            surroundColor: mediaButton.down || mediaButton.selected ? theme.selected : mediaButton.hovered ? theme.hover : theme.panel
                        }
                        Text {
                            x: root.grid ? root.expanded ? 0 : theme.dp(4) : thumbnail.width + theme.dp(10)
                            y: root.grid ? thumbnail.y + thumbnail.height + theme.dp(root.expanded ? 20 : 6) : (parent.height - height) / 2
                            width: root.grid ? parent.width - (root.expanded ? 0 : theme.dp(8)) : Math.max(0, parent.width - x - theme.dp(26))
                            text: delegate.displayTitle; elide: Text.ElideRight
                            color: mediaButton.hovered || mediaButton.visualFocus ? theme.bright : theme.foreground
                            font.pixelSize: theme.dp(root.expanded && root.grid ? 16 : 14)
                        }
                        Text {
                            visible: root.expanded && root.grid && delegate.itemArtist.length > 0
                            x: 0; y: thumbnail.height + theme.dp(50); width: parent.width
                            text: delegate.itemArtist; elide: Text.ElideRight
                            color: theme.foreground; font.pixelSize: theme.dp(16)
                        }
                    }
                    DragHandler {
                        id: dragHandler
                        target: null
                        enabled: root.canEnqueue && !root.playlistEditing
                    }
                    RedesignLibraryDrag {
                        handler: dragHandler
                        libraryView: root
                        mediaIndex: delegate.index
                    }
                }
                RedesignButton {
                    objectName: "libraryRowAction" + delegate.index
                    visible: (root.playlistEditing || root.canEnqueue) && !root.grid && (root.playlistEditing || mediaButton.hovered || hovered || mediaButton.visualFocus)
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    implicitWidth: theme.dp(28)
                    iconName: root.playlistEditing ? "remove" : "add"; text: root.playlistEditing ? qsTr("Remove from playlist") : qsTr("Add to queue")
                    enabled: !root.playlistEditing || !root.playlistBusy
                    onClicked: root.playlistEditing ? root.playlistRemoveRequested(delegate.index, delegate.model.id) : root.enqueueRequested(delegate.index)
                }
                Rectangle { anchors.fill: parent; color: "transparent"; border.color: theme.accent; border.width: theme.dp(2); visible: root.playlistEditing && root.dragDestination === delegate.index }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.homeSectionsVisible && root.itemCount === 0
            text: root.searchText.length > 0 ? qsTr("No media matches your search.") : root.emptyText
            wrapMode: Text.WordWrap; color: theme.foreground; font.pixelSize: theme.dp(14)
            verticalAlignment: Text.AlignTop
        }
    }
}
