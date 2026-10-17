// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import VLC.MainInterface
import VLC.Player
import VLC.Playlist
import VLC.Style
import VLC.Util
import VLC.Dialogs
import VLC.Widgets as Widgets

FocusScope {
    id: rootPlayer
    property var pagePrefix: []
    readonly property real positionSliderY: view.positionSliderY
    readonly property ColorContext colorContext: ColorContext { palette: VLCStyle.palette; colorSet: ColorContext.Window }
    property bool resumeAvailable: false
    property int queueTab: 0
    readonly property string mediaFolderUrl: {
        const url = String(Player.url || "")
        return url.startsWith("file:") ? url.substring(0, url.lastIndexOf("/") + 1) : ""
    }
    function mediaFolderName() {
        const name = mediaFolderUrl.replace(/\/+$/, "").split("/").pop()
        try { return decodeURIComponent(name) } catch (error) { return name }
    }
    Connections {
        target: Player
        function onInputChanged() { view.refreshSeekPreview() }
    }
    Connections {
        target: DialogsProvider
        function onShowRedesignBookmarks() {
            rootPlayer.queueTab = 1
            view.settingsPage = ""; view.queueOpen = true
            Qt.callLater(() => { if (view.queueItem) view.queueItem.tab = 1 })
        }
    }
    function clockText(tick) {
        if (!tick.valid()) return "00:00:00"
        const parts = tick.formatHMS(0).split(":")
        return parts.length === 2 ? "00:" + parts.join(":") : parts.join(":")
    }
    WheelToVLCConverter {
        id: volumeWheel
        function adjust(steps) {
            if (steps === 0) return
            Player.muted = false
            if (steps > 0) Player.setVolumeUp(steps)
            else Player.setVolumeDown(-steps)
        }
        onWheelUpDown: steps => adjust(steps)
        onWheelLeftRight: steps => adjust(steps)
    }
    RedesignSleepTimer { id: sleepTimer; onTriggered: MainPlaylistController.pause() }
    RedesignPreferences { id: playerPreferences; ctx: MainCtx; autoSave: true; editPlayerPreset: true }
    Shortcut {
        sequences: ["Menu", "Shift+F10"]
        context: Qt.WindowShortcut
        enabled: {
            const window = rootPlayer.Window.window
            const item = window ? window.activeFocusItem : null
            return MainCtx.useGlobalShortcuts && !(item instanceof TextInput) && !(item instanceof TextEdit)
        }
        onActivated: {
            mediaMenu.dismiss()
            tracksPopup.close()
            const item = rootPlayer.Window.window.activeFocusItem || view
            DialogsProvider.popupPlayerMenu(item.mapToGlobal(item.width / 2, item.height / 2))
        }
    }
    Shortcut {
        sequences: { playerPreferences.revision; return String(playerPreferences.value("key-toggle-library") || "").split("\t").filter(sequence => sequence.length > 0) }
        context: Qt.WindowShortcut
        enabled: MainCtx.useGlobalShortcuts
        onActivated: { view.libraryOpen = !view.libraryOpen; view.libraryExpanded = false }
    }
    Binding {
        target: MainCtx
        property: "preferHotkeys"
        value: MainCtx.useGlobalShortcuts && !view.controlsLocked && !tracksPopup.visible && !mediaMenu.visible && !shortcutEditor.visible
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding { target: Player; property: "seekPreviewEnabled"; value: MainCtx.redesignPlayerPreferences.seekPreview }
    Binding { target: Player; property: "subtitleTimelineEnabled"; value: MainCtx.redesignPlayerPreferences.subtitleTimeline }

    Component.onCompleted: {
        MainCtx.playqueuePanel.docked = true
        view.queueOpen = MainCtx.playqueuePanel.visible
    }

    RedesignPlayerView {
        id: view
        objectName: "redesignPlayer"
        anchors.fill: parent
        focus: true
        scaleFactor: VLCStyle.scale
        lightTheme: !VLCStyle.palette.isDark
        accentColor: MainCtx.redesignAccent
        playing: Player.playingState === Player.PLAYING_STATE_PLAYING
        started: Player.isStarted
        hasVideo: MainCtx.hasEmbededVideo
        seekable: started && Player.seekable
        pausable: Player.pausable
        hasPrevious: MainPlaylistController.hasPrev
        hasNext: MainPlaylistController.hasNext
        muted: Player.muted
        fullscreen: MainCtx.intfMainWindow.visibility === Window.FullScreen
        minimalView: MainCtx.minimalView
        autoHideMode: MainCtx.redesignPlayerPreferences.autoHide
        controlsHideTimeout: MainCtx.redesignPlayerPreferences.hideTimeout
        showFullscreenControls: MainCtx.redesignPlayerPreferences.fullscreenControls
        showSubtitleTimeline: MainCtx.redesignPlayerPreferences.subtitleTimeline
        showSeekPreview: MainCtx.redesignPlayerPreferences.seekPreview
        subtitleTimelineCues: Player.subtitleTimelineCues
        subtitleTimelineState: Player.subtitleTimelineState
        subtitleDelayMS: Player.subtitleDelayMS
        durationSeconds: started ? Player.lengthSeconds : 0
        onSubtitleDelayRequested: milliseconds => playerPreferences.stage("redesign-subtitle-delay", milliseconds)
        maximized: MainCtx.intfMainWindow.visibility === Window.Maximized
        showWindowButtons: MainCtx.clientSideDecoration && !fullscreen
        position: started ? Player.position : 0
        volume: Player.volume
        maxVolume: MainCtx.maxVolume / 100
        buffering: Player.buffering
        statistics: Player.playbackStatistics
        mediaTitle: Player.title || Player.name || qsTr("VLC Media Player")
        locationTitle: view.libraryItem ? view.libraryItem.locationTitle : qsTr("Videos")
        timeText: started ? rootPlayer.clockText(Player.time) : "00:00:00"
        lengthText: started ? rootPlayer.clockText(Player.length) : "00:00:00"
        artist: Player.artist
        mediaFolderTitle: rootPlayer.mediaFolderName()
        canBrowseMedia: MainCtx.mediaLibraryAvailable
        artwork: Player.artwork
        resumeAvailable: rootPlayer.resumeAvailable
        timeForPosition: value => rootPlayer.clockText(Player.length.scale(value))
        seekPreviewImage: Player.seekPreview
        videoBackdropContent: Component {
            Item {
                id: surfaceBackdrop
                property real blurRadius: 25 * view.scaleFactor
                property real cornerRadius: 10 * view.scaleFactor
                visible: MainCtx.backdropBlurRequested()
                VideoBackdrop {
                    anchors.fill: parent
                    videoSurfaceProvider: MainCtx.videoSurfaceProvider
                    blurRadius: surfaceBackdrop.blurRadius
                    cornerRadius: surfaceBackdrop.cornerRadius
                }
                Widgets.BackdropBlur {
                    anchors.fill: parent
                    sourceItem: view.backdropSource
                    radius: surfaceBackdrop.blurRadius
                    cornerRadius: surfaceBackdrop.cornerRadius
                }
            }
        }
        seekThumbnailContent: Component {
            Widgets.ImageExt {
                objectName: "seekThumbnailImage"
                source: view.seekPreviewImage; cache: false
                // Keep the shader's soft edge under the clip, without a dark outline.
                anchors.fill: parent; anchors.margins: -0.5
                radius: view.scaleFactor * 4 + 0.5
                // Thumbnail export can round the fitted height down by one pixel.
                fillMode: sourceTextureProviderItem.implicitHeight > 0 && parent && parent.width > 0
                    && Math.abs(sourceTextureProviderItem.implicitHeight - sourceTextureProviderItem.implicitWidth * parent.height / parent.width) <= 1.01
                    ? Image.Stretch : Image.PreserveAspectFit
            }
        }
        seekPreviewImagePosition: Player.seekPreviewPosition
        onSeekPreviewRequested: value => Player.requestSeekPreview(value)
        onSeekPreviewEnded: Player.cancelSeekPreview()
        onTogglePlayback: MainPlaylistController.empty ? DialogsProvider.simpleOpenDialog() : MainPlaylistController.togglePlayPause()
        onPrevious: MainPlaylistController.prevOrReset()
        onNext: MainPlaylistController.next()
        onSeekRequested: value => Player.jumpToPos(value)
        onSeekDragStarted: Player.beginSeekDrag()
        onSeekDragFinished: (value, commit) => Player.finishSeekDrag(value, commit)
        onVolumeRequested: value => { Player.muted = false; Player.volume = value }
        onVolumeWheelRequested: event => {
            // Match the standard volume widget's continuous touchpad scrolling.
            const pixels = Math.abs(event.pixelDelta.x) > Math.abs(event.pixelDelta.y)
                         ? event.pixelDelta.x : event.pixelDelta.y
            if (Math.abs(pixels) % 120 > 0) {
                Player.muted = false
                Player.volume = Math.max(0, Math.min(2, Player.volume + (event.inverted ? -pixels : pixels) * 0.001))
            } else {
                volumeWheel.qmlWheelEvent(event)
            }
        }
        onMuteRequested: Player.muted = !Player.muted
        onFullscreenRequested: MainCtx.toggleInterfaceFullScreen()
        onMinimizeRequested: MainCtx.requestInterfaceMinimized()
        onMaximizeRequested: maximized ? MainCtx.requestInterfaceNormal() : MainCtx.requestInterfaceMaximized()
        onCloseRequested: DialogsProvider.quit()
        onOpenRequested: DialogsProvider.simpleOpenDialog()
        onPreferencesRequested: DialogsProvider.prefsDialog()
        onFullLibraryRequested: { libraryOpen = true; libraryExpanded = !libraryExpanded }
        onMediaFolderRequested: {
            libraryOpen = true
            Qt.callLater(() => {
                const library = view.libraryItem ? view.libraryItem.item : null
                if (library && rootPlayer.mediaFolderUrl) library.openFolder(rootPlayer.mediaFolderUrl, Player.videoTracks.count > 0 ? 1 : 2)
            })
        }
        onArtistRequested: {
            const library = view.libraryItem ? view.libraryItem.item : null
            if (library && Player.artist) library.openArtistByName(Player.artist)
        }
        trackPopup: tracksPopup
        onMenuRequested: anchor => mediaMenu.toggleFrom(anchor, view)
        onResumeRequested: resume => {
            rootPlayer.resumeAvailable = false
            if (resume) Player.restorePlaybackPos()
            else Player.acknowledgeRestoreCallback()
        }
        onKeyPressed: event => {
            if (!event.accepted && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
                MainCtx.sendHotkey(event.key, event.modifiers)
        }
        titleBarDragContent: Component {
            Loader {
                active: MainCtx.clientSideDecoration && !view.fullscreen
                source: "qrc:///qt/qml/VLC/Widgets/CSDTitlebarTapNDrapHandler.qml"
            }
        }
        videoContent: Component {
            VideoSurface {
                id: video
                videoSurfaceProvider: MainCtx.videoSurfaceProvider
                // Clear the chrome background where the compositor displays video.
                renderingEnabled: true
                visible: MainCtx.hasEmbededVideo
                focus: visible
                cursorShape: view.fullscreen && !view.topVisible && !view.bottomVisible ? Qt.BlankCursor : Qt.ArrowCursor
            }
        }
        Connections {
            target: MainCtx.playqueuePanel
            function onVisibleChanged() { view.queueOpen = MainCtx.playqueuePanel.visible && MainCtx.playqueuePanel.docked }
        }
        onQueueOpenChanged: if (MainCtx.playqueuePanel.docked) MainCtx.playqueuePanel.visible = queueOpen
        libraryContent: Component {
            Loader {
                source: MainCtx.mediaLibraryAvailable ? "qrc:///qt/qml/VLC/Player/RedesignLibrary.qml" : ""
                onLoaded: {
                    item.scaleFactor = Qt.binding(() => view.scaleFactor)
                    item.lightTheme = Qt.binding(() => view.lightTheme)
                    item.accentColor = Qt.binding(() => view.accentColor)
                    item.expanded = Qt.binding(() => view.libraryExpanded)
                    item.fullLibraryRequested.connect(() => { view.libraryExpanded = !view.libraryExpanded })
                }
                RedesignLibraryView {
                    anchors.fill: parent
                    visible: !MainCtx.mediaLibraryAvailable
                    expanded: view.libraryExpanded
                    scaleFactor: view.scaleFactor; lightTheme: view.lightTheme; accentColor: view.accentColor
                    emptyText: qsTr("This VLC build has no media library. Open files or a folder to add them to the queue.")
                    onAddRequested: DialogsProvider.simpleOpenDialog()
                    onCategoryRequested: category => category === 3 ? DialogsProvider.openNetDialog() : DialogsProvider.simpleOpenDialog()
                }
                property string heading: item ? item.heading : qsTr("Videos")
                property string locationTitle: item && item.breadcrumbs.length ? item.breadcrumbs[item.breadcrumbs.length - 1].label : qsTr("Videos")
            }
        }
        queueContent: Component {
            RedesignQueuePanel {
                tab: rootPlayer.queueTab
                onTabChanged: rootPlayer.queueTab = tab
                scaleFactor: view.scaleFactor; lightTheme: view.lightTheme; accentColor: view.accentColor
                onCloseRequested: view.queueOpen = false
                queueContent: Component { RedesignQueue {
                scaleFactor: view.scaleFactor; lightTheme: view.lightTheme; accentColor: view.accentColor
                queueModel: PlaylistListModel { id: queueModel; playlist: MainPlaylistController.playlist }
                itemCount: queueModel.count
                currentIndex: queueModel.currentIndex
                totalDurationText: summaryDuration(queueModel.duration)
                sortChoices: MainPlaylistController.sortKeyTitleList
                sortKey: MainPlaylistController.sortKey
                sortDescending: MainPlaylistController.sortOrder === PlaylistController.SORT_ORDER_DESC
                random: MainPlaylistController.random
                repeating: MainPlaylistController.repeatMode !== PlaylistController.PLAYBACK_REPEAT_NONE
                onCloseRequested: view.queueOpen = false
                onAddRequested: DialogsProvider.simpleOpenDialog(false)
                onSaveRequested: DialogsProvider.savePlayingToPlaylist()
                onClearRequested: MainPlaylistController.clear()
                onShuffleRequested: MainPlaylistController.toggleRandom()
                onRepeatRequested: MainPlaylistController.toggleRepeatMode()
                onSortRequested: (key, descending) => MainPlaylistController.sort(key, descending ? PlaylistController.SORT_ORDER_DESC : PlaylistController.SORT_ORDER_ASC)
                onPlayRequested: index => MainPlaylistController.goTo(index, true)
                onRemoveRequested: index => queueModel.removeItems([index])
                onMoveRequested: (from, to) => queueModel.moveItemsPre([from], to)
                onLibraryDropRequested: source => source.libraryView.enqueueRequested(source.mediaIndex)
                } }
            }
        }
        settingsContent: Component {
            RedesignSettings {
                preferenceStore: playerPreferences
                Component.onCompleted: playerPreferences.refresh()
                scaleFactor: view.scaleFactor; lightTheme: view.lightTheme; accentColor: view.accentColor
                page: view.settingsPage
                showStatistics: view.showStatistics
                showSubtitleTimeline: view.showSubtitleTimeline
                subtitleTimelineState: view.subtitleTimelineState
                sleepTimerMinutes: sleepTimer.minutes
                onStatisticsRequested: enabled => view.showStatistics = enabled
                onPageRequested: page => view.settingsPage = page
                onCloseRequested: view.settingsPage = ""
                onSleepTimerRequested: minutes => sleepTimer.start(minutes)
            }
        }
    }

    RedesignTrackPopup {
        id: tracksPopup
        videoBackdropContent: view.videoBackdropContent
        parent: view
        placementArea: view
        scaleFactor: view.scaleFactor; lightTheme: view.lightTheme; accentColor: view.accentColor
        videoTracks: Player.videoTracks
        audioTracks: Player.audioTracks
        subtitleTracks: Player.subtitleTracks
        audioDevices: Player.audioDevices
        onSelectionRequested: (model, index, selected) => model.setData(model.index(index, 0), selected, Qt.CheckStateRole)
        onDisableRequested: model => {
            for (let i = 0; i < model.count; ++i)
                model.setData(model.index(i, 0), false, Qt.CheckStateRole)
        }
        canAddTracks: Player.isStarted
        onAddTracksRequested: page => page === "audio" ? DialogsProvider.loadAudioFile() : DialogsProvider.loadSubtitlesFile()
        onEditTracksRequested: page => page === "audio" ? DialogsProvider.loadAudioFile() : DialogsProvider.loadSubtitlesFile()
        onPreferencesRequested: page => view.settingsPage = page
    }

    Loader {
        id: recentMenuModel
        active: MainCtx.mediaLibraryAvailable && mediaMenu.recentFilesEnabled
        source: active ? "qrc:///qt/qml/VLC/Player/RedesignRecentMenuModel.qml" : ""
    }
    RedesignShortcuts {
        id: shortcutEditor
        parent: view
        scaleFactor: view.scaleFactor; lightTheme: view.lightTheme; accentColor: view.accentColor
        onSaved: playerPreferences.discard()
    }
    RedesignMenu {
        id: mediaMenu
        parent: view
        scaleFactor: view.scaleFactor; lightTheme: view.lightTheme; accentColor: view.accentColor
        recentModel: recentMenuModel.item
        recentFilesAvailable: MainCtx.mediaLibraryAvailable
        recentFilesEnabled: { playerPreferences.revision; return !!playerPreferences.value("save-recentplay") }
        profiles: { playerPreferences.revision; return playerPreferences.playerPresets }
        selectedProfile: { playerPreferences.revision; return playerPreferences.selectedPlayerPreset }
        onRecentRequested: mediaId => { if (recentMenuModel.item) recentMenuModel.item.playMedia(mediaId) }
        onClearRecentRequested: if (recentMenuModel.item) recentMenuModel.item.clearHistory()
        onProfileRequested: profileId => playerPreferences.selectPlayerPreset(profileId)
        onActionRequested: action => {
            switch (action) {
            case "file": DialogsProvider.simpleOpenDialog(); break
            case "directory": DialogsProvider.PLOpenDir(); break
            case "disc": DialogsProvider.openDiscDialog(); break
            case "network": DialogsProvider.openNetDialog(); break
            case "capture": DialogsProvider.openCaptureDialog(); break
            case "convert": DialogsProvider.openAndTranscodingDialogs(); break
            case "customize": DialogsProvider.showToolbarEditorDialog(); break
            case "shortcuts": shortcutEditor.open(); break
            case "settings": DialogsProvider.prefsDialog(); break
            case "about": DialogsProvider.aboutDialog(); break
            }
        }
    }
    // VideoSurface continues to provide VLC's native context menu and hotkeys.
    QmlAudioContextMenu { id: audioContextMenu; ctx: MainCtx }
    TapHandler {
        enabled: !MainCtx.hasEmbededVideo
        acceptedButtons: Qt.RightButton
        onTapped: point => audioContextMenu.popup(point.globalPosition)
    }
    Connections {
        target: MainCtx
        function onAskShow() { view.revealControls() }
        function onMainInterfaceModesChanged() {
            if (!MainCtx.minimalView && !MainCtx.playerView && Player.isStarted) { view.libraryOpen = true; view.libraryExpanded = true }
        }
    }
    Connections {
        target: Player
        function onPlaybackRestoreQueried() { rootPlayer.resumeAvailable = Player.canRestorePlayback }
    }
    Dialogs {
        z: 10
        bgContent: rootPlayer
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: view.theme.dp(54) }
    }
    Widgets.FloatingNotification {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: view.theme.dp(20); bottomMargin: view.theme.dp(74) }
    }
}
