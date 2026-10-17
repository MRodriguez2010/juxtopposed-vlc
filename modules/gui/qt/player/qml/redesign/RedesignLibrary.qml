// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls.Basic as C
import VLC.MainInterface
import VLC.MediaLibrary
import VLC.Player
import VLC.Dialogs

RedesignLibraryView {
    id: root
    readonly property var emptyParentId: MediaLib.deserializeMlItemIdFromString("")
    property var selectedPlaylist
    property string playlistEditKey: ""
    onSelectedPlaylistChanged: { playlistEditKey = ""; playlistEditMessage = "" }
    playlistOpen: !!selectedPlaylist
    playlistKey: selectedPlaylist ? selectedPlaylist.toString() : ""
    playlistEditing: !!selectedPlaylist && playlistEditKey === playlistKey && sortState.selection.id === "original" && !searchText.length && !grid
    playlistBusy: playlistMedia.transactionPending
    onGridChanged: if (grid) playlistEditKey = ""
    addLabel: selectedPlaylist ? qsTr("Add files") : category === 4 ? qsTr("Create playlist") : category === 3 ? qsTr("Add Network Stream") : qsTr("Add")
    onPlaylistEditRequested: {
        if (playlistEditing) playlistEditKey = ""
        else { sortState.select("original"); searchText = ""; grid = false; playlistEditKey = playlistKey }
    }
    onPlaylistMoveRequested: (from, to, id) => playlistMedia.editItem(from, to, false, id, selectedPlaylist)
    onPlaylistRemoveRequested: (row, id) => playlistMedia.editItem(row, row, true, id, selectedPlaylist)
    onPlaylistFilesDropped: urls => playlistMedia.appendFiles(urls.map(url => String(url)))
    property var selectedCollection
    property string homeSection: ""
    property string currentFolder: ""
    onCurrentFolderChanged: folderArtwork.clear()
    property var registeredFolders: []
    readonly property var folderTrail: folderPath.trail(currentFolder, registeredFolders)
    property string musicSection: ""
    property string selectedName: ""
    property var backStack: []
    property var forwardStack: []
    pins: pinStore.entries
    readonly property var currentPinTarget: {
        if (currentFolder) return pinTarget("folder", currentFolder, nameFromUrl(currentFolder), category, "folder", "", "")
        if (selectedPlaylist) return pinTarget("playlist", selectedPlaylist.toString(), selectedName, 4, "playlist", "", "")
        if (selectedCollection) return pinTarget("collection", selectedCollection.toString(), selectedName, 2, musicSection === "Artists" ? "artist" : "music", "", musicSection)
        if (musicSection) return pinTarget("section", musicSection, qsTr(musicSection), 2, "music", "", "")
        if (homeSection) return pinTarget("home", homeSection, homeTitles[homeSection], 0, homeSections.find(section => section.key === homeSection).icon, "", "")
        return null
    }
    locationPinTarget: currentPinTarget
    locationPinned: pinStore.contains(currentPinTarget)
    selectedPinId: locationPinned ? pinStore.identity(currentPinTarget) : ""
    menuForItem: (index, section) => {
        const target = targetForItem(index, section || homeSection)
        if (!target) return null
        if (selectedPlaylist && !section) { target.playlistRow = index; target.playlistKey = playlistKey }
        if (target.kind === "playlist") {
            return new Promise(resolve => MediaLib.playlistState(MediaLib.deserializeMlItemIdFromString(target.key), state => {
                target.favorite = state.favorite; target.count = state.count
                resolve(state.success ? {target: target, entries: playlistMenuEntries(target)} : null)
            }))
        }
        if (["file", "media"].includes(target.kind)) {
            return new Promise(resolve => MediaLib.mediaState(Qt.resolvedUrl(target.url || target.key), false, state => {
                target.played = state.played; target.favorite = state.favorite
                resolve(state.success ? {target: target, entries: mediaMenuEntries(target)} : null)
            }))
        }
        if (target.kind === "folder") return {target: target, entries: [
            {action: "open", label: qsTr("Open"), icon: "folder", accent: true},
            {action: "queue", label: qsTr("Add to Queue"), icon: "queue", accent: true},
            {action: "pin", label: pinStore.contains(target) ? qsTr("Remove from sidebar") : qsTr("Add to sidebar"), icon: "sidebar"},
            {action: "subtitle-tracks", label: qsTr("Edit Subtitle Tracks"), icon: "subtitles", accent: true},
            {action: "audio-tracks", label: qsTr("Edit Audio Tracks"), icon: "audio", accent: true},
            {action: "resync", label: qsTr("Resync"), icon: "refresh-two-tone", accent: true},
            {action: "folder-info", label: qsTr("Info"), icon: "info-two-tone", accent: true}
        ]}
        const navigate = ["folder", "section", "home"].includes(target.kind)
        return {target: target, entries: [
            {action: navigate ? "open" : "play", label: navigate ? qsTr("Open") : qsTr("Play"), icon: "play-outline"},
            {action: "pin", label: pinStore.contains(target) ? qsTr("Remove from sidebar") : qsTr("Add to sidebar"), icon: pinStore.contains(target) ? "favorite-active" : "favorite", accent: true}
        ].concat(["section", "home"].includes(target.kind) ? [] : [{action: "queue", label: qsTr("Add to queue"), icon: "queue"}])
            .concat(["file", "media", "collection", "playlist"].includes(target.kind) ? [{action: "add-playlist", label: qsTr("Add to Playlist"), icon: "playlist"}] : [])
            .concat(playlistEditing && !section ? [
                {action: "earlier", label: qsTr("Move earlier"), icon: "sort", enabled: index > 0 && !playlistBusy},
                {action: "later", label: qsTr("Move later"), icon: "sort", enabled: index < itemCount - 1 && !playlistBusy},
                {action: "remove-entry", label: qsTr("Remove from playlist"), icon: "remove", enabled: !playlistBusy}
            ] : [])}
    }
    onItemActionRequested: (target, action) => {
        if (action === "folder-info" && target.kind === "folder") {
            folderInfo.begin(folderTools.requestInfo(Qt.resolvedUrl(target.key)))
        } else if (action === "resync" && target.kind === "folder") {
            MediaLib.resyncFolder(Qt.resolvedUrl(target.key), result => {
                if (!result.success) DialogsProvider.messageDialog(result.error, qsTr("VLC Media Player"))
            })
            if (folderLoader.item) { folderArtwork.clear(); folderLoader.item.refresh() }
        } else if (action === "favorite" && target.kind === "playlist") {
            MediaLib.setPlaylistFavorite(MediaLib.deserializeMlItemIdFromString(target.key), !target.favorite, result => {
                if (!result.success) DialogsProvider.messageDialog(result.error, qsTr("VLC Media Player"))
            })
        } else if (action === "shuffle" && target.kind === "playlist") {
            MediaLib.shuffleAndPlay(MediaLib.deserializeMlItemIdFromString(target.key))
        } else if (action === "export" && target.kind === "playlist") {
            DialogsProvider.exportLibraryPlaylistDialog(MediaLib.deserializeMlItemIdFromString(target.key), target.name)
        } else if (action === "properties" && target.kind === "playlist") {
            const request = playlistProperties.begin(target.key)
            if (request >= 0) MediaLib.playlistState(MediaLib.deserializeMlItemIdFromString(target.key), result => playlistProperties.load(request, result))
        } else if (action === "watched" || action === "favorite") {
            MediaLib.setMediaState(Qt.resolvedUrl(target.url || target.key), action === "watched" ? "played" : "favorite",
                action === "watched" ? !target.played : !target.favorite, result => {
                    if (!result.success) DialogsProvider.messageDialog(result.error, qsTr("VLC Media Player"))
                })
        } else if (action === "stream" || action === "convert") DialogsProvider.streamingDialog([Qt.resolvedUrl(target.url || target.key)], action === "convert")
        else if (action === "subtitle-tracks" || action === "audio-tracks") {
            if (target.kind === "playlist") {
                DialogsProvider.showTrackAssignments({scope: "playlist", key: target.key}, action === "subtitle-tracks")
            } else if (target.kind === "folder") {
                DialogsProvider.showTrackAssignments({scope: "folder", folder: target.key}, action === "subtitle-tracks")
            } else DialogsProvider.showTrackAssignments({scope: "file", url: target.url || target.key,
                key: target.playlistKey || ""}, action === "subtitle-tracks")
        }
        else if (action === "explorer") Qt.openUrlExternally(folderPath.parentFolder(target.url || target.key))
        else if (action === "source") {
            const url = target.url || target.key
            if (url.startsWith("file:")) openFolder(folderPath.parentFolder(url), target.category)
            else Qt.openUrlExternally(url)
        } else if (action === "properties") {
            MediaLib.mediaState(Qt.resolvedUrl(target.url || target.key), true, result => {
                if (result.success) DialogsProvider.mediaInfoDialog(MediaLib.deserializeMlItemIdFromString(result.id))
                else DialogsProvider.messageDialog(result.error, qsTr("VLC Media Player"))
            })
        } else if (["earlier", "later", "remove-entry"].includes(action)) {
            if (!playlistEditing || target.playlistKey !== playlistKey) return
            const id = MediaLib.deserializeMlItemIdFromString(target.key)
            playlistMedia.editItem(target.playlistRow, target.playlistRow + (action === "earlier" ? -1 : action === "later" ? 1 : 0), action === "remove-entry", id, selectedPlaylist)
        } else if (action === "pin") pinStore.toggle(target)
        else if (action === "add-playlist") DialogsProvider.playlistsDialog([target.kind === "file" ? Qt.resolvedUrl(target.key) : MediaLib.deserializeMlItemIdFromString(target.key)])
        else if (action === "queue") enqueueTarget(target)
        else if (action === "open") openTarget(target)
        else playTarget(target)
    }
    onPinLocationRequested: if (currentPinTarget) pinStore.toggle(currentPinTarget)
    onPinActivated: target => openTarget(target)
    onPinRemoved: target => pinStore.remove(target)
    onPinEnqueueRequested: target => enqueueTarget(target)
    settingsContext: MainCtx
    sortScope: homeSection ? "home/" + homeSection : currentFolder ? "folder/" + (category === 2 ? "audio" : "video")
        : selectedPlaylist ? "playlist-media" : selectedCollection ? "audio-tracks"
        : category === 2 ? "music/" + musicSection : "category/" + category
    sortFields: {
        if (homeSectionsVisible || category === 2 && !musicSection && !currentFolder) return []
        if (currentFolder) return ["title", "insertion", "uri"]
        if (homeSection === "folders" || category === 1) return ["title", "uri"]
        if (homeSection === "playlists" || homeSection === "artists") return ["title"]
        if (homeSection === "watching") return ["played", "insertion", "title", "uri"]
        if (category === 3) return ["insertion", "uri"]
        if (category === 4 && !selectedPlaylist) return ["insertion", "title"]
        if (category === 2 && !selectedCollection && musicSection !== "Songs")
            return musicSection === "Albums" ? ["title", "main_artist"] : ["title"]
        return ["played", "insertion", "title", "main_artist", "album_title", "track_number", "uri", "disc_number"]
    }
    extraSortOptions: ["folders", "playlists", "artists"].includes(homeSection)
        ? [{id: "frequency", field: "frequency", descending: true, label: homeSection === "artists" ? qsTr("Most played first") : qsTr("Most visited first")}]
        : selectedPlaylist ? [{id: "original", field: "", descending: false, label: qsTr("Playlist order")}] : []
    defaultSortChoice: extraSortOptions.length ? extraSortOptions[0].id
        : ["watching", "listening"].includes(homeSection) || category === 3 || category === 5 ? "newest" : "title-asc"
    readonly property string mediaSortField: sortField === "frequency" ? ""
        : sortField === "insertion" && (["watching", "listening"].includes(homeSection) || category === 3 || category === 5) ? ""
        : sortField === "title" && (homeSection === "artists" || category === 2 && !selectedCollection && ["Artists", "Genres"].includes(musicSection)) ? "name" : sortField
    readonly property int mediaSortOrder: descending ? Qt.DescendingOrder : Qt.AscendingOrder
    readonly property var homeModels: ({watching: recentVideo, listening: recentAudio, folders: frequentFolders, playlists: frequentPlaylists, artists: playedArtists})
    readonly property var homeTitles: ({watching: qsTr("Continue Watching"), listening: qsTr("Listen Again"), folders: qsTr("Frequently Visited Folders"), playlists: qsTr("Frequently Visited Playlists"), artists: qsTr("Frequently Listened Artists")})
    homeSectionsVisible: category === 0 && !homeSection
    homeSections: [
        {key: "watching", title: homeTitles.watching, model: recentVideo, icon: "video", emptyText: qsTr("No videos in your history.")},
        {key: "listening", title: homeTitles.listening, model: recentAudio, icon: "music", emptyText: qsTr("No music in your history.")},
        {key: "folders", title: homeTitles.folders, model: frequentFolders, icon: "folder", emptyText: qsTr("Open a library folder to see it here.")},
        {key: "playlists", title: homeTitles.playlists, model: frequentPlaylists, icon: "playlist", emptyText: qsTr("Open a playlist to see it here.")},
        {key: "artists", title: homeTitles.artists, model: playedArtists, icon: "artist", emptyText: qsTr("Play music to see artists here.")}
    ]
    itemCount: homeSectionsVisible ? recentVideo.maximumCount + recentAudio.maximumCount + frequentFolders.count + frequentPlaylists.count + playedArtists.maximumCount : currentFolder ? (folderLoader.item ? folderLoader.item.count : 0) : activeModel && activeModel.count !== undefined ? activeModel.count : libraryMediaCount
    readonly property var activeModel: homeSection ? homeModels[homeSection] : currentFolder ? folderLoader.item : selectedPlaylist ? playlistMedia : selectedCollection ? collectionTracks : category === 4 ? playlists : category === 2 ? (musicSection === "" ? musicCategories : musicSection === "Albums" ? albums : musicSection === "Artists" ? artists : musicSection === "Genres" ? genres : music) : category === 3 ? streams : category === 0 || category === 5 ? recent : folderEntries
    mediaModel: activeModel
    breadcrumbs: {
        const result = [{label: [qsTr("Home"), qsTr("Videos"), qsTr("Music"), qsTr("Network streams"), qsTr("Playlists"), qsTr("Recent files")][category], kind: "category"}]
        if (homeSection) result.push({label: homeTitles[homeSection], kind: "home"})
        if (musicSection) result.push({label: qsTr(musicSection), kind: "music"})
        if (currentFolder) {
            for (const url of folderTrail) result.push({label: nameFromUrl(url), kind: "folder", url: url})
        } else if (selectedName) result.push({label: selectedName, kind: "selection"})
        return result
    }
    heading: breadcrumbs.map(entry => entry.label).join(" › ")
    canGoBack: backStack.length > 0
    canGoForward: forwardStack.length > 0
    defaultItemIcon: homeSection === "artists" ? "artist" : homeSection === "listening" ? "music" : category === 4 && !selectedPlaylist ? "playlist" : category === 2 ? "music" : "video"
    showingFolders: category === 1 && !currentFolder || homeSection === "folders"
    showAddRow: category > 0 && category < 5 && !selectedCollection && (category !== 1 || !currentFolder || (folderLoader.item && folderLoader.item.directoryCount > 0))
    canEnqueue: !(category === 2 && musicSection === "")
    emptyText: homeSection ? homeSections.find(section => section.key === homeSection).emptyText : selectedPlaylist ? qsTr("This playlist is empty.") : category === 4 ? qsTr("Create a playlist to collect your favorite media.") : category === 3 ? qsTr("Open a network stream to add it here.") : qsTr("Add a folder to your library to see your media here.")

    RedesignLibraryPath { id: folderPath }
    function playlistMenuEntries(target) {
        return [
            {action: "play", label: qsTr("Play"), icon: "play-outline", accent: true, enabled: target.count > 0},
            {action: "favorite", label: target.favorite ? qsTr("Remove from Favorites") : qsTr("Favorite"), icon: target.favorite ? "favorite-active" : "favorite", accent: true},
            {action: "shuffle", label: qsTr("Shuffle"), icon: "shuffle", accent: true, enabled: target.count > 0},
            {action: "export", label: qsTr("Export Playlist"), icon: "save", accent: true},
            {action: "queue", label: qsTr("Add to Queue"), icon: "queue", accent: true, enabled: target.count > 0},
            {action: "subtitle-tracks", label: qsTr("Add Subtitle Tracks"), icon: "subtitles-two-tone", accent: true, enabled: target.count > 0},
            {action: "audio-tracks", label: qsTr("Add Audio Tracks"), icon: "audio-two-tone", accent: true, enabled: target.count > 0},
            {action: "properties", label: qsTr("Properties & Metadata"), icon: "info-two-tone", accent: true}
        ]
    }
    function mediaMenuEntries(target) {
        return [
            {action: "play", label: qsTr("Play"), icon: "play-outline", accent: true},
            {action: "watched", label: target.played ? qsTr("Mark as Unwatched") : qsTr("Mark as Watched"), icon: "watched", accent: true},
            {action: "favorite", label: target.favorite ? qsTr("Remove from Favorites") : qsTr("Favorite"), icon: target.favorite ? "favorite-active" : "favorite", accent: true},
            {action: "stream", label: qsTr("Stream"), icon: "stream", accent: true},
            {action: "convert", label: qsTr("Convert"), icon: "convert", accent: true},
            {action: "queue", label: qsTr("Add to Queue"), icon: "queue", accent: true},
            {action: "add-playlist", label: qsTr("Add to Playlist"), icon: "playlist", accent: true}
        ].concat(target.kind === "file" ? [{action: "explorer", label: qsTr("Show in File Explorer"), icon: "folder", accent: true}] : [])
            .concat([{action: "source", label: qsTr("Go to Source"), icon: "source", accent: true},
                {action: "subtitle-tracks", label: qsTr("Add Subtitle Tracks"), icon: "subtitles-two-tone", accent: true},
                {action: "audio-tracks", label: qsTr("Add Audio Tracks"), icon: "audio-two-tone", accent: true},
                {action: "properties", label: qsTr("Properties & Metadata"), icon: "info-two-tone", accent: true},
                {action: "pin", label: pinStore.contains(target) ? qsTr("Remove from sidebar") : qsTr("Add to sidebar"), icon: "sidebar"}])
            .concat(playlistEditing && target.playlistKey === playlistKey ? [
                {action: "earlier", label: qsTr("Move earlier"), icon: "sort", enabled: target.playlistRow > 0 && !playlistBusy},
                {action: "later", label: qsTr("Move later"), icon: "sort", enabled: target.playlistRow < itemCount - 1 && !playlistBusy},
                {action: "remove-entry", label: qsTr("Remove from playlist"), icon: "remove", enabled: !playlistBusy}
            ] : [])
    }
    RedesignLibraryPins { id: pinStore; ctx: MainCtx }
    function pinTarget(kind, key, name, category, icon, artwork, section) {
        return pinStore.normalize({kind: kind, key: key, name: name, category: category, icon: icon, artwork: artwork ? artwork.toString() : "", section: section})
    }
    function mediaTarget(item, defaultCategory) {
        const category = item.isVideo === false ? 2 : item.isVideo === true ? 1 : defaultCategory
        const url = (item.mrl || item.url || "").toString()
        const local = url.startsWith("file:")
        const target = pinTarget(local ? "file" : "media", local ? folderPath.location(url) : item.id.toString(),
            item.title || item.name || nameFromUrl(url), category, category === 3 ? "network" : category === 2 ? "music" : "video",
            item.thumbnail || item.small_cover || item.cover || "", "")
        target.url = url
        return target
    }
    function targetForItem(index, section) {
        if (section) {
            const item = homeItem(section, index)
            if (section === "folders") return pinTarget("folder", folderPath.location(item.key), item.name, 1, "folder", "", "")
            if (section === "playlists") return pinTarget("playlist", item.key, item.name, 4, "playlist", "", "")
            if (section === "artists") return pinTarget("collection", item.id.toString(), item.name, 2, "artist", item.small_cover || item.cover || "", "Artists")
            return mediaTarget(item, section === "listening" ? 2 : 1)
        }
        if (currentFolder) {
            const folder = folderLoader.item
            if (!folder) return null
            const url = folder.get(index, "fileUrl")
            if (!url) return null
            const isDirectory = folder.get(index, "fileIsDir")
            return pinTarget(isDirectory ? "folder" : "file", folderPath.location(url), folder.get(index, "fileName"), category, isDirectory ? "folder" : category === 2 ? "music" : "video", isDirectory ? "" : folder.get(index, "thumbnail"), "")
        }
        if (category === 1) {
            const item = folderEntries.get(index)
            return item ? pinTarget("folder", folderPath.location(item.fileUrl), item.fileName, 1, "folder", "", "") : null
        }
        if (category === 2 && !musicSection) {
            const section = ["Songs", "Albums", "Artists", "Genres"][index]
            return section ? pinTarget("section", section, qsTr(section), 2, "music", "", "") : null
        }
        const item = activeModel.getDataAt(index)
        if (!item || !item.id) return null
        const name = item.title || item.name || nameFromUrl(item.url || "")
        const artwork = item.thumbnail || item.small_cover || item.cover || ""
        if (category === 4 && !selectedPlaylist) return pinTarget("playlist", item.id.toString(), name, 4, "playlist", artwork, "")
        if (category === 2 && !selectedCollection && musicSection !== "Songs")
            return pinTarget("collection", item.id.toString(), name, 2, musicSection === "Artists" ? "artist" : "music", artwork, musicSection)
        return mediaTarget(item, category)
    }
    function resetLocation(newCategory) {
        category = newCategory
        homeSection = ""; selectedPlaylist = undefined; selectedCollection = undefined
        currentFolder = ""; musicSection = ""; selectedName = ""; searchText = ""
    }
    function openTarget(target) {
        if (target.kind === "folder") { openFolder(target.key, target.category); return }
        if (["media", "file"].includes(target.kind)) { playTarget(target); return }
        remember()
        resetLocation(target.category)
        if (target.kind === "playlist") {
            selectedPlaylist = MediaLib.deserializeMlItemIdFromString(target.key); selectedName = target.name
            visits.record("playlists", target.key, target.name)
        } else if (target.kind === "collection") {
            musicSection = target.section; selectedCollection = MediaLib.deserializeMlItemIdFromString(target.key); selectedName = target.name
        } else if (target.kind === "section") musicSection = target.key
        else if (target.kind === "home") homeSection = target.key
    }
    function enqueueTarget(target) {
        if (["folder", "file"].includes(target.kind)) MediaLib.addToPlaylist(Qt.resolvedUrl(target.key))
        else if (!["section", "home"].includes(target.kind)) MediaLib.addToPlaylist(MediaLib.deserializeMlItemIdFromString(target.key))
    }
    function playTarget(target) {
        if (target.kind === "file") MediaLib.addAndPlay(Qt.resolvedUrl(target.key))
        else MediaLib.addAndPlay(MediaLib.deserializeMlItemIdFromString(target.key))
    }
    function snapshot() { return { category: category, homeSection: homeSection, playlist: selectedPlaylist, collection: selectedCollection, folder: currentFolder, musicSection: musicSection, name: selectedName, search: searchText } }
    function remember() { backStack = [...backStack, snapshot()]; forwardStack = [] }
    function restore(state) { category = state.category; homeSection = state.homeSection || ""; selectedPlaylist = state.playlist; selectedCollection = state.collection; currentFolder = state.folder; musicSection = state.musicSection; selectedName = state.name; searchText = state.search; if (currentFolder) visits.record("folders", currentFolder, nameFromUrl(currentFolder)); else if (selectedPlaylist) visits.record("playlists", selectedPlaylist.toString(), selectedName) }
    function openFolder(url, mediaCategory) {
        remember()
        currentFolder = folderPath.location(url)
        category = mediaCategory === 1 || mediaCategory === 2 ? mediaCategory : category === 2 ? 2 : 1
        homeSection = ""
        selectedPlaylist = undefined; selectedCollection = undefined; musicSection = ""
        selectedName = nameFromUrl(url)
        visits.record("folders", currentFolder, selectedName)
        searchText = ""
    }
    function openArtistByName(name) {
        remember()
        category = 2; homeSection = ""; selectedPlaylist = undefined; selectedCollection = undefined
        currentFolder = ""; musicSection = "Artists"; selectedName = ""; searchText = name
    }
    onBreadcrumbActivated: index => {
        if (index < 0 || index >= breadcrumbs.length - 1) return
        const entry = breadcrumbs[index]
        if (entry.kind === "category") categoryRequested(category)
        else if (entry.kind === "folder") openFolder(entry.url)
        else if (entry.kind === "music") {
            remember(); selectedCollection = undefined; selectedName = ""; searchText = ""
        }
    }
    onCategoryRequested: newCategory => { remember(); resetLocation(newCategory) }
    onBackRequested: { const stack = backStack.slice(); const state = stack.pop(); forwardStack = [...forwardStack, snapshot()]; backStack = stack; restore(state) }
    onForwardRequested: { const stack = forwardStack.slice(); const state = stack.pop(); backStack = [...backStack, snapshot()]; forwardStack = stack; restore(state) }
    onActivated: index => {
        if (homeSection) { openHomeItem(homeSection, index); return }
        if (currentFolder) {
            const url = folderLoader.item.get(index, "fileUrl")
            if (folderLoader.item.get(index, "fileIsDir")) openFolder(url)
            else MediaLib.addAndPlay(url)
        } else if (category === 1) {
            openFolder(folderEntries.get(index).fileUrl)
        } else if (category === 2 && musicSection === "") {
            remember(); musicSection = ["Songs", "Albums", "Artists", "Genres"][index]
        } else {
            const item = activeModel.getDataAt(index)
            if (category === 4 && !selectedPlaylist) { remember(); selectedPlaylist = item.id; selectedName = item.name; searchText = ""; visits.record("playlists", item.id.toString(), item.name) }
            else if (category === 2 && musicSection !== "Songs" && !selectedCollection) { remember(); selectedCollection = item.id; selectedName = item.title || item.name; searchText = "" }
            else MediaLib.addAndPlay(item.id)
        }
    }
    onEnqueueRequested: index => {
        if (homeSection) { enqueueHomeItem(homeSection, index); return }
        if (currentFolder) MediaLib.addToPlaylist(folderLoader.item.get(index, "fileUrl"))
        else if (category === 1) MediaLib.addToPlaylist(folderEntries.get(index).fileUrl)
        else MediaLib.addToPlaylist(activeModel.getDataAt(index).id)
    }
    onAddRequested: {
        if (selectedPlaylist) playlistMedia.appendFiles(DialogsProvider.selectPlaylistFiles())
        else if (category === 3) DialogsProvider.openNetDialog()
        else { const folder = DialogsProvider.selectLibraryFolder(); if (folder.toString().length > 0) libraryFolders.add(folder) }
    }
    onFilesRequested: {
        const files = currentFolder ? DialogsProvider.selectLibraryFiles(Qt.resolvedUrl(currentFolder)) : DialogsProvider.selectLibraryFiles()
        if (!files.length) return
        const selectedCategory = category
        MediaLib.addLibraryFiles(files, result => {
            if (result.folders.length) openFolder(result.folders[0], selectedCategory)
            if (!result.success) DialogsProvider.messageDialog(result.error, qsTr("VLC Media Player"))
        })
    }
    onFolderRequested: {
        const folder = currentFolder ? DialogsProvider.selectLibraryFolder(Qt.resolvedUrl(currentFolder)) : DialogsProvider.selectLibraryFolder()
        if (!folder.toString().length) return
        libraryFolders.add(folder)
        openFolder(folder, category)
    }
    onPreferencesRequested: DialogsProvider.prefsPageDialog("library")
    onNewPlaylistRequested: createPlaylist.begin()

    function homeItem(section, index) {
        const model = homeModels[section]
        if (section === "folders" || section === "playlists") {
            const item = model.get(index)
            return {key: item.key, name: item.name}
        }
        return model.getDataAt(index)
    }
    function openHomeItem(section, index) {
        const item = homeItem(section, index)
        if (section === "folders") { openFolder(item.key); return }
        if (section === "playlists" || section === "artists") {
            remember()
            homeSection = ""; currentFolder = ""; musicSection = ""; searchText = ""
            selectedPlaylist = undefined; selectedCollection = undefined
            if (section === "playlists") {
                category = 4; selectedPlaylist = MediaLib.deserializeMlItemIdFromString(item.key); selectedName = item.name
                visits.record("playlists", item.key, item.name)
            } else {
                category = 2; musicSection = "Artists"; selectedCollection = item.id; selectedName = item.name
            }
        } else MediaLib.addAndPlay(item.id)
    }
    function enqueueHomeItem(section, index) {
        const item = homeItem(section, index)
        MediaLib.addToPlaylist(section === "folders" ? item.key : section === "playlists" ? MediaLib.deserializeMlItemIdFromString(item.key) : item.id)
    }
    onHomeActivated: (section, index) => openHomeItem(section, index)
    onHomeEnqueueRequested: (section, index) => enqueueHomeItem(section, index)
    onHomeSectionRequested: section => { remember(); homeSection = section; searchText = "" }
    function refreshVisits() {
        if (!frequentFolders || !frequentPlaylists || !visits) return
        frequentFolders.clear(); frequentPlaylists.clear()
        for (const kind of ["folders", "playlists"]) {
            const items = visits.ranked(kind, searchText)
            if (homeSection === kind && sortField !== "frequency")
                items.sort((a, b) => compareEntries(a, b))
            for (const item of items)
                (kind === "folders" ? frequentFolders : frequentPlaylists).append({key: item.key, name: item.name, iconName: kind === "folders" ? "folder" : "playlist"})
        }
    }
    function compareEntries(a, b) {
        const av = sortField === "uri" ? a.key : a.name.toLocaleLowerCase()
        const bv = sortField === "uri" ? b.key : b.name.toLocaleLowerCase()
        const order = av < bv ? -1 : av > bv ? 1 : 0
        return order ? (descending ? -order : order) : a.key < b.key ? -1 : a.key > b.key ? 1 : 0
    }
    function refreshFolders() {
        if (!libraryFolders || !folderEntries) return
        const rows = []
        const roots = []
        for (let i = 0; i < libraryFolders.rowCount(); ++i) {
            const url = libraryFolders.data(libraryFolders.index(i, 0), MLFolderModel.MRL).toString()
            roots.push(url)
            const name = nameFromUrl(url)
            if (name.toLocaleLowerCase().includes(searchText.toLocaleLowerCase())) rows.push({key: url, name: name})
        }
        rows.sort((a, b) => compareEntries(a, b))
        registeredFolders = roots
        folderEntries.clear()
        for (const row of rows) folderEntries.append({fileUrl: row.key, fileName: row.name, fileIsDir: true})
    }
    onSearchTextChanged: { if (searchText.length) playlistEditKey = ""; refreshVisits(); refreshFolders() }
    onHomeSectionChanged: refreshVisits()
    Connections {
        target: root.sortState
        function onSelectionChanged() {
            if (root.sortState.selection.id !== "original") root.playlistEditKey = ""
            root.refreshVisits(); root.refreshFolders()
        }
    }
    RedesignLibraryVisits { id: visits; ctx: MainCtx; onEntriesChanged: root.refreshVisits() }
    ListModel { id: frequentFolders }
    ListModel { id: frequentPlaylists }
    MLRecentVideoModel { id: recentVideo; ml: MediaLib; sortCriteria: root.homeSection === "watching" ? root.mediaSortField : ""; sortOrder: root.homeSection === "watching" ? root.mediaSortOrder : Qt.DescendingOrder; limit: root.homeSectionsVisible ? (root.expanded ? 6 : 3) : 0; searchPattern: root.searchText }
    MLRecentAudioModel { id: recentAudio; ml: MediaLib; sortCriteria: root.homeSection === "listening" ? root.mediaSortField : ""; sortOrder: root.homeSection === "listening" ? root.mediaSortOrder : Qt.DescendingOrder; limit: root.homeSectionsVisible ? (root.expanded ? 6 : 3) : 0; searchPattern: root.searchText }
    MLPlayedArtistModel { id: playedArtists; ml: MediaLib; sortCriteria: root.homeSection === "artists" ? root.mediaSortField : ""; sortOrder: root.mediaSortOrder; limit: root.homeSectionsVisible ? (root.expanded ? 6 : 3) : 0; searchPattern: root.searchText }

    MLFileArtwork {
        id: folderArtwork
        ctx: MainCtx
        onArtworkChanged: (url, artwork) => {
            if (folderLoader.item) folderLoader.item.setArtwork(url, artwork)
            if (!artwork) return
            const key = folderPath.location(url)
            const pin = pinStore.entries.find(entry => entry.kind === "file" && entry.key === key)
            if (pin && pin.artwork !== artwork) pinStore.add(Object.assign({}, pin, {artwork: artwork}))
        }
    }
    Loader {
        id: folderLoader
        active: root.currentFolder.length > 0
        sourceComponent: RedesignFolderModel {
            folder: root.currentFolder
            nameFilters: DialogsProvider.mediaNameFilters(root.category === 2)
            sortReversed: root.descending
            sortCriteria: root.sortField
            searchPattern: root.searchText
            onArtworkRequested: url => folderArtwork.request(url, root.category !== 2)
        }
    }
    ListModel {
        id: musicCategories
        ListElement { title: QT_TR_NOOP("Songs"); iconName: "library-songs" }
        ListElement { title: QT_TR_NOOP("Albums"); iconName: "library-album" }
        ListElement { title: QT_TR_NOOP("Artists"); iconName: "library-artist" }
        ListElement { title: QT_TR_NOOP("Genres"); iconName: "library-genre" }
    }
    MLAudioModel { id: music; ml: MediaLib; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    MLAlbumModel { id: albums; ml: MediaLib; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    MLArtistModel { id: artists; ml: MediaLib; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    MLGenreModel { id: genres; ml: MediaLib; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    MLAudioModel { id: collectionTracks; ml: MediaLib; parentId: root.selectedCollection || root.emptyParentId; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    MLRecentMediaModel { id: recent; ml: MediaLib; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder; searchPattern: root.searchText }
    MLPlaylistListModel { id: playlists; ml: MediaLib; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    RedesignPlaylistProperties {
        id: playlistProperties
        parent: C.Overlay.overlay
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        onCoverRequested: {
            const image = DialogsProvider.selectPlaylistCover()
            if (image.toString().length) cover = image
        }
        onSaveRequested: (key, name, cover, request) => MediaLib.savePlaylistDetails(
            MediaLib.deserializeMlItemIdFromString(key), name, cover, result => playlistProperties.finish(request, result))
    }
    RedesignFolderModel {
        id: folderTools
        onInfoReady: (serial, info) => folderInfo.load(serial, info)
    }
    RedesignFolderInfo {
        id: folderInfo
        parent: C.Overlay.overlay
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
    }
    Binding {
        target: MainCtx; property: "useGlobalShortcuts"; value: false
        when: playlistProperties.visible || folderInfo.visible; restoreMode: Binding.RestoreBindingOrValue
    }
    Connections {
        target: MediaLib
        function onPlaylistDetailsChanged(id, name, cover) {
            const key = id.toString()
            if (root.selectedPlaylist && root.selectedPlaylist.toString() === key) root.selectedName = name
            const pin = pinStore.entries.find(entry => entry.kind === "playlist" && entry.key === key)
            if (pin) pinStore.add(Object.assign({}, pin, {name: name, artwork: cover.toString()}))
            visits.rename("playlists", key, name)
            root.refreshVisits()
        }
    }
    MLPlaylistModel { id: playlistMedia; ml: MediaLib; parentId: root.selectedPlaylist || root.emptyParentId; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    Connections {
        target: playlistMedia
        function onItemsEdited(playlist, success, error) { if (root.selectedPlaylist && root.playlistKey === playlist.toString()) root.playlistEditMessage = success ? "" : error }
    }
    MLUrlModel { id: streams; ml: MediaLib; searchPattern: root.searchText; sortCriteria: root.mediaSortField; sortOrder: root.mediaSortOrder }
    MLFolderModel { id: libraryFolders; ctx: MainCtx }
    ListModel { id: folderEntries }
    Connections {
        target: libraryFolders
        function onModelReset() { root.refreshFolders() }
        function onOperationFailed(operation, url) {
            if (operation === MLFolderModel.Add)
                DialogsProvider.messageDialog(qsTr("VLC could not add this folder: %1").arg(url.toString()), qsTr("VLC Media Player"))
        }
    }
    RedesignPlaylistDialog {
        id: createPlaylist
        videoBackdropContent: root.videoBackdropContent
        parent: C.Overlay.overlay
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        onFilesRequested: addFiles(DialogsProvider.selectPlaylistFiles())
        onCoverRequested: { const image = DialogsProvider.selectPlaylistCover(); if (image.toString().length) cover = image }
        onSaveRequested: (name, urls, cover) => playlists.createWithFiles(name, urls, cover)
    }
    Binding {
        target: MainCtx; property: "useGlobalShortcuts"; value: false
        when: createPlaylist.visible; restoreMode: Binding.RestoreBindingOrValue
    }
    Connections {
        target: playlists
        function onPlaylistCreated(success, id, error) {
            const name = createPlaylist.playlistName.trim()
            createPlaylist.finish(success, error)
            if (success) root.openTarget(root.pinTarget("playlist", id.toString(), name, 4, "playlist", "", ""))
        }
    }
}
