// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

C.Dialog {
    id: root
    popupType: C.Popup.Item
    property real scaleFactor: 1
    property bool lightTheme: false
    property color accentColor: "#d37918"
    property Component videoBackdropContent
    readonly property RedesignTheme theme: RedesignTheme { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor }
    property bool subtitles: true
    property var context: ({})
    property var rows: []
    property var sources: []
    property var drafts: ({})
    property var selectedRows: ({})
    property string anchorFile: ""
    property string targetFolder: ""
    property string sourceFolder: ""
    property int sourceIndex: 0
    property bool providerHasCustomKey: false
    property bool providerHasConsumerKey: false
    property bool providerConfigured: false
    property bool searching: false
    property int searchRequestId: 0
    property string searchTitle: ""
    property string searchLanguage: ""
    property var preferredSearchLanguages: []
    property bool manualSearchLanguage: false
    onPreferredSearchLanguagesChanged: refreshSearchLanguage()
    onOnlineLanguagesChanged: Qt.callLater(refreshSearchLanguage)
    readonly property var searchLanguageChoices: [{code:"",text:qsTr("All languages")}].concat(onlineLanguages)
    property var sourceMappings: ({})
    property var sourceKinds: ({})
    property var onlineSources: []
    property var linkSources: []
    property string linkText: ""
    property var onlineLanguages: [{code:"en",text:qsTr("English")},{code:"es",text:qsTr("Spanish")},{code:"ja",text:qsTr("Japanese")},{code:"de",text:qsTr("German")},{code:"nl",text:qsTr("Dutch")},{code:"fr",text:qsTr("French")}]
    property bool cancelableSave: false
    readonly property bool onlineMode: subtitles && sourceIndex === 1
    readonly property bool linkMode: subtitles && sourceIndex === 2
    readonly property var activeSources: onlineMode ? onlineSources : linkMode ? linkSources : sources
    readonly property var sourceChoices: subtitles ? [qsTr("From Computer"),qsTr("From OpenSubtitles"),qsTr("From Link")] : [qsTr("From Computer")]
    onSourceIndexChanged: Qt.callLater(() => sourceChoice.currentIndex = root.sourceIndex)
    property int scopeIndex: 0
    onScopeIndexChanged: Qt.callLater(() => scopeChoice.currentIndex = root.scopeIndex)
    property int requestId: 0
    property int sourceRequestId: 0
    property bool loading: false
    property bool loadingSources: false
    property bool matchSavedSources: false
    property bool matching: false
    property int matchRequestId: 0
    property bool loadingDrop: false
    property int dropRequestId: 0
    property bool saving: false
    property string errorMessage: ""
    property string folderRuleBaseline: ""
    property string folderRuleDefinition: ""
    property bool folderRuleLoaded: false
    property bool folderRuleTouched: false
    property bool folderRuleAutomatic: true
    property bool removeFolderRule: false
    property var pendingFolderRule: ({})
    readonly property var folderRuleTarget: scopeIndex === 1
        ? {folder:targetFolder,source:sourceFolder,urls:rows.map(row => row.url),remove:removeFolderRule} : pendingFolderRule
    readonly property bool folderRuleNeedsPreparation: !!folderRuleTarget.folder
        && (folderRuleTarget.urls || []).some(url => tracks(url).some(track => /^(?:opensubtitles|subtitlelink):/.test(String(track))))
    readonly property bool folderRuleChanged: !!folderRuleTarget.folder
        && ((folderRuleTarget.remove && folderRuleBaseline.length > 0) || folderRuleNeedsPreparation || folderRuleDefinition !== folderRuleBaseline)
    readonly property bool fileMode: scopeIndex === 0
    readonly property var scopes: [
        {text: qsTr("To This File"), enabled: anchorFile.length > 0},
        {text: qsTr("To Folder"), enabled: targetFolder.length > 0},
        {text: qsTr("To Playlist"), enabled: !!context.key || (context.urls || []).length > 0}
    ]
    readonly property var changedRows: Object.keys(drafts).map(url => drafts[url]).filter(row => !same(row.initialTracks, row.tracks) || (row.inheritedRule && row.manual))
    readonly property var visibleSources: {
        const result = activeSources.slice()
        const seen = result.map(item => item.url)
        for (const row of rows) for (const url of (drafts[row.url]?.initialTracks || []).concat(tracks(row.url)))
            if (sourceKind(url) === sourceIndex && !seen.includes(url)) { seen.push(url); result.push({url: url, name: fileName(url)}) }
        return result
    }
    signal searchRequested(string query, string language, int request)
    signal searchCanceled()
    signal languagesRequested()
    signal setupRequested(string key)
    signal apiKeyHelpRequested()
    signal removeSetupRequested()
    signal linksRequested(var urls)
    signal rowsRequested(var target, bool subtitles, int request)
    signal sourcesRequested(url folder, bool subtitles, int request)
    signal matchRequested(var media, var tracks, bool includeSaved, int request)
    signal matchingCanceled()
    signal droppedSourcesRequested(var urls, bool subtitles, int request, string target)
    signal filesRequested(string target)
    signal folderRequested()
    signal saveRequested(var rows, bool subtitles, int request)
    signal saved(var rows, bool subtitles)
    title: subtitles ? qsTr("Add Subtitles") : qsTr("Add Audio Tracks")
    anchors.centerIn: parent
    width: Math.min(theme.dp(1048), parent ? parent.width - theme.dp(32) : theme.dp(1048))
    height: Math.min(theme.dp(800), parent ? parent.height - theme.dp(32) : theme.dp(800))
    padding: 0; modal: true; dim: true; focus: true
    closePolicy: saving && !cancelableSave ? C.Popup.NoAutoClose : C.Popup.CloseOnEscape
    background: RedesignDialogSurface {
        theme: root.theme
        fill: root.theme.lightTheme ? root.theme.panel : "#0e0e0e"
        videoBackdropContent: root.videoBackdropContent
    }
    C.Overlay.modal: Rectangle { color: "#80000000" }

    function fileName(url) {
        const name = String(url).split("/").pop()
        try { return decodeURIComponent(name) } catch (error) { return name }
    }
    function sourceKind(url) {
        if (String(url).startsWith("subtitlelink:") || linkSources.some(item => item.url === url)) return 2
        if (String(url).startsWith("opensubtitles:") || onlineSources.some(item => item.url === url)) return 1
        return sourceKinds[url] || 0
    }
    function parentFolder(url) { return String(url).startsWith("file:") ? String(url).substring(0, String(url).lastIndexOf("/") + 1) : "" }
    function same(a, b) { return [...new Set(a || [])].sort().join("\n") === [...new Set(b || [])].sort().join("\n") }
    function tracks(url) { return drafts[url] ? drafts[url].tracks : [] }
    function refreshSearchLanguage() {
        let language = searchLanguage
        if (!manualSearchLanguage)
            language = preferredSearchLanguages.find(code => onlineLanguages.some(item => item.code === code)) || ""
        else if (!searchLanguageChoices.some(item => item.code === language)) language = ""
        const changed = language !== searchLanguage
        searchLanguage = language
        if (changed && visible && onlineMode) requestSearch()
    }
    function begin(target, subtitleMode) {
        if (visible || saving) return false
        context = target; subtitles = subtitleMode
        sourceIndex = 0; onlineSources = []; linkSources = []; linkText = ""; sourceMappings = ({}); sourceKinds = ({}); searchTitle = ""; manualSearchLanguage = false; searching = false; cancelableSave = false
        refreshSearchLanguage()
        rows = []; sources = []; drafts = ({}); selectedRows = ({}); errorMessage = ""
        folderRuleBaseline = ""; folderRuleLoaded = false; folderRuleTouched = false; folderRuleAutomatic = true; removeFolderRule = false; pendingFolderRule = ({})
        anchorFile = target.scope === "folder" || target.scope === "playlist" ? "" : String(target.url || "")
        targetFolder = target.scope === "folder" ? String(target.folder || target.url || "") : parentFolder(anchorFile)
        sourceFolder = targetFolder
        scopeIndex = target.scope === "folder" ? 1 : ["playlist", "queue"].includes(target.scope) ? 2 : 0
        open(); requestRows()
        return true
    }
    function cancelMatching() { ++matchRequestId; matching = false; matchingCanceled() }
    function requestRows() {
        ++dropRequestId; loadingDrop = false
        cancelMatching()
        ++requestId; loading = true; errorMessage = ""; selectedRows = ({})
        const target = scopeIndex === 0 ? {scope: "file", url: anchorFile}
            : scopeIndex === 1 ? {scope: "folder", folder: targetFolder}
            : context.key ? {scope: "playlist", key: context.key} : {scope: "queue", urls: context.urls || []}
        target.runtimeUrl = context.runtimeUrl
        target.runtimeTracks = context.runtimeTracks
        rowsRequested(target, subtitles, requestId)
    }
    function loadRows(request, result) {
        if (!visible || request !== requestId) return
        loading = false
        if (!result.success) { rows = []; errorMessage = result.error || qsTr("VLC cannot read these files. Try again."); return }
        rows = result.rows || []
        if (scopeIndex === 1) {
            folderRuleBaseline = result.folderRule || ""
            folderRuleAutomatic = result.automaticMatching !== false
            if (!folderRuleLoaded && !folderRuleTouched && result.sourceFolder) sourceFolder = result.sourceFolder
            folderRuleLoaded = true
            if (result.ruleError) errorMessage = result.ruleError
        }
        const next = Object.assign({}, drafts)
        for (const row of rows) if (!next[row.url] || (!next[row.url].manual && same(next[row.url].initialTracks, next[row.url].tracks))) next[row.url] = {
            url: row.url, baseline: Array.from(row.baseline || []),
            initialTracks: Array.from(row.initialTracks || row.baseline || []),
            tracks: Array.from(row.initialTracks || row.baseline || []),
            explicitSelection: !!row.explicitSelection, inheritedRule: !!row.inheritedRule, manual: false
        }
        drafts = next
        if (!anchorFile && rows.length) anchorFile = rows[0].url
        if (!targetFolder) targetFolder = parentFolder(anchorFile)
        if (!sourceFolder && targetFolder) sourceFolder = targetFolder
        if (!searchTitle && anchorFile) searchTitle = fileName(anchorFile).replace(/\.[^.]+$/, "").replace(/[._]/g, " ")
        if (onlineMode) requestSearch()
        else if (linkMode) performMatching()
        else if (sourceFolder) requestSources()
        else performMatching()
    }
    function requestSources(includeSaved = false) {
        ++dropRequestId; loadingDrop = false
        cancelMatching()
        matchSavedSources = includeSaved
        ++sourceRequestId; loadingSources = true
        sourcesRequested(sourceFolder, subtitles, sourceRequestId)
    }
    function loadSources(request, result) {
        if (!visible || request !== sourceRequestId) return
        loadingSources = false
        if (!result.success) { errorMessage = result.error || qsTr("VLC cannot read this folder. Try again."); return }
        sources = result.sources || []; performMatching(matchSavedSources)
    }
    function performMatching(includeSaved = false) {
        cancelMatching()
        if (!fileMode && !loading && !loadingSources) {
            matching = true
            matchRequested(rows.map(row => row.url), activeSources.map(source => source.url), includeSaved, matchRequestId)
        }
    }
    function loadMatches(request, matches, includeSaved = false) {
        if (!visible || request !== matchRequestId) return
        matching = false
        applyMatches(matches, includeSaved)
    }
    function applyMatches(matches, includeSaved = false) {
        const next = Object.assign({}, drafts)
        for (const row of rows) {
            const draft = next[row.url]
            if (draft && !draft.manual && ((!draft.explicitSelection && !draft.inheritedRule) || includeSaved)) {
                const selection = [...new Set(draft.initialTracks.concat(matches[row.url] || []))]
                if (includeSaved && !same(draft.tracks, selection)
                    && ((folderRuleTarget.urls || []).includes(row.url) || parentFolder(row.url) === targetFolder)) folderRuleTouched = true
                next[row.url] = Object.assign({}, draft, {tracks: selection})
            }
        }
        drafts = next
    }
    function selectSource(index) {
        if (saving || loadingDrop || index === sourceIndex || index < 0 || index >= sourceChoices.length) return
        searchDebounce.stop(); ++searchRequestId; searching = false; searchCanceled(); cancelMatching()
        ++sourceRequestId; loadingSources = false; errorMessage = ""; sourceIndex = index
        if (onlineMode) { languagesRequested(); requestSearch() }
        else if (linkMode) performMatching()
        else if (sourceFolder) requestSources()
    }
    function requestSearch() {
        searchDebounce.stop()
        if (!visible || !onlineMode || !providerConfigured || saving || loading || loadingDrop) return
        cancelMatching(); ++searchRequestId; searching = true; errorMessage = ""
        searchRequested(searchTitle, searchLanguage, searchRequestId)
    }
    function loadSearch(request, result) {
        if (!visible || request !== searchRequestId || !onlineMode) return
        searching = false
        if (!result.success) { onlineSources = []; errorMessage = result.error || qsTr("VLC could not search for subtitles. Try again."); return }
        onlineSources = (result.sources || []).map(item => Object.assign({}, item, {url: sourceMappings[item.url] || item.url})); performMatching(true)
    }
    function resolveSources(mapping) {
        const kinds = Object.assign({}, sourceKinds)
        for (const url of Object.keys(mapping || {})) kinds[mapping[url]] = sourceKind(url)
        sourceKinds = kinds
        sourceMappings = Object.assign({}, sourceMappings, mapping || {})
        onlineSources = onlineSources.map(item => Object.assign({}, item, {url: sourceMappings[item.url] || item.url}))
        linkSources = linkSources.map(item => sourceMappings[item.url]
            ? Object.assign({}, item, {url: sourceMappings[item.url], name: fileName(sourceMappings[item.url])}) : item)
        const next = Object.assign({}, drafts)
        for (const url of Object.keys(next)) next[url] = Object.assign({}, next[url], {
            tracks: [...new Set(next[url].tracks.map(track => sourceMappings[track] || track))]
        })
        drafts = next
    }
    function finishSetup(success, error = "") {
        if (success) {
            providerSetup.close()
            if (providerConfigured) { languagesRequested(); requestSearch() }
            else { searching = false; onlineSources = [] }
        }
        else providerSetup.errorMessage = error || qsTr("VLC could not save the API key. Check it and try again.")
    }
    function setTracks(url, selection) {
        const draft = drafts[url]
        if (!draft || saving) return
        if ((folderRuleTarget.urls || []).includes(url) || parentFolder(url) === targetFolder) folderRuleTouched = true
        drafts = Object.assign({}, drafts, {[url]: Object.assign({}, draft, {tracks: [...new Set(selection)], manual: true})})
        errorMessage = ""
    }
    function toggle(url, track) {
        const selected = tracks(url)
        setTracks(url, selected.includes(track) ? selected.filter(item => item !== track) : selected.concat([track]))
    }
    function addFiles(files, target) {
        addSources(files.map(value => ({url: String(value), name: fileName(value)})), target)
    }
    function addSources(items, target) {
        if (!items.length) return
        const local = sources.slice(), linked = linkSources.slice()
        for (const item of items) {
            const next = item.kind === "link" || String(item.url).startsWith("subtitlelink:") ? linked : local
            if (!next.some(source => source.url === item.url)) next.push(item)
        }
        sources = local; linkSources = linked
        const url = target || (fileMode ? anchorFile : "")
        if (url) setTracks(url, tracks(url).concat(items.map(item => item.url)))
        else performMatching(true)
    }
    function addLink() {
        if (saving || loading || loadingDrop || !linkText.trim()) return
        linksRequested([linkText.trim()])
    }
    function loadLinkedSources(result) {
        if (!visible || !linkMode) return
        if (result.success) { addSources(result.sources || [], ""); linkText = "" }
        errorMessage = result.error || ""
    }
    function dropUrls(drop) {
        return drop.hasUrls ? drop.urls : subtitles && drop.hasText ? drop.text.split(/\r?\n/).map(value => value.trim()).filter(value => value.length) : []
    }
    function dropSources(urls, target = "") {

        if (!visible || saving || loading || loadingDrop) return false
        if (!urls.length) { errorMessage = qsTr("VLC could not read these files. Try again."); return false }
        const values = Array.from(urls, value => String(value))
        if (subtitles && values.every(url => /^https?:/i.test(url))) selectSource(2)
        else selectSource(0)
        cancelMatching(); ++sourceRequestId; loadingSources = false
        ++dropRequestId; loadingDrop = true; errorMessage = ""
        droppedSourcesRequested(values, subtitles, dropRequestId, target)
        return true
    }
    function loadDroppedSources(request, result, target = "") {

        if (!visible || request !== dropRequestId) return
        loadingDrop = false
        if (result.success) {
            if (result.folder) { sourceFolder = String(result.folder); folderRuleTouched = true }
            addSources(result.sources || [], target)
        }
        errorMessage = result.error || ""
    }
    function selectScope(index) {
        if (index === scopeIndex || !scopes[index].enabled || saving || loadingDrop) return
        if (scopeIndex === 1) pendingFolderRule = folderRuleChanged ? folderRuleTarget : ({})
        scopeIndex = index; picker.close(); requestRows()
    }
    function chooseRow(url) { picker.targetUrl = url; picker.open() }
    function submit() {
        if (saving || loading || loadingSources || loadingDrop || matching || (!changedRows.length && !folderRuleChanged)) return
        searchDebounce.stop(); ++searchRequestId; searching = false; searchCanceled()
        saving = true; picker.close(); errorMessage = ""
        saveRequested(changedRows, subtitles, requestId)
    }
    function finish(request, result) {
        if (!visible || request !== requestId) return
        saving = false
        const completed = result.saved || []
        const next = Object.assign({}, drafts)
        for (const row of completed) if (next[row.url]) next[row.url] = Object.assign({}, next[row.url], {baseline: Array.from(row.tracks), initialTracks: Array.from(row.tracks), tracks: Array.from(row.tracks), explicitSelection: true, inheritedRule: false, manual: false})
        drafts = next
        if (result.folderRuleSaved) { folderRuleBaseline = result.folderRule || ""; pendingFolderRule = ({}); folderRuleTouched = false; removeFolderRule = false }
        if (completed.length) saved(completed, subtitles)
        if (result.success) accept()
        else errorMessage = (result.error || qsTr("VLC cannot save these tracks. Try again."))
            + (completed.length ? "\n" + qsTr("VLC kept the changes that it saved. Try Save again for the other files.") : "")
    }
    onClosed: { ++searchRequestId; searching = false; searchDebounce.stop(); searchCanceled(); providerSetup.close(); linkText = ""; linkSources = []; onlineSources = []; sourceMappings = ({}); sourceKinds = ({}); pendingFolderRule = ({}); removeFolderRule = false; folderRuleBaseline = ""; folderRuleLoaded = false; folderRuleTouched = false; saving = false; cancelableSave = false; ++dropRequestId; loadingDrop = false; cancelMatching(); ++requestId; ++sourceRequestId; picker.close(); rows = []; sources = []; drafts = ({}); selectedRows = ({}) }
    Timer { id: searchDebounce; interval: 600; onTriggered: root.requestSearch() }
    Shortcut { sequence: "Ctrl+O"; enabled: root.visible && !root.saving; onActivated: { root.selectSource(0); root.filesRequested("") } }
    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; enabled: root.visible && !root.saving; onActivated: root.submit() }

    header: Item {
        implicitHeight: root.theme.dp(96)
        Rectangle {
            anchors.fill: parent; radius: root.theme.dp(14); color: root.theme.field
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height / 2; color: parent.color }
        }
        Text {
            x: root.theme.dp(20); y: root.theme.dp(16)
            text: root.title; color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
        }
        RedesignButton {
            objectName: "trackAssignmentClose"
            anchors.right: parent.right; anchors.rightMargin: root.theme.dp(8); y: root.theme.dp(6)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            iconName: "close"; text: qsTr("Close"); enabled: !root.saving || root.cancelableSave; onClicked: root.reject()
        }
        RowLayout {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: root.theme.dp(9); anchors.rightMargin: root.theme.dp(9); anchors.bottomMargin: root.theme.dp(9)
            spacing: root.theme.dp(10)
            RedesignComboBox {
                id: scopeChoice
                objectName: "trackAssignmentScope"
                Layout.preferredWidth: Math.min(root.theme.dp(200), root.width * 0.23); Layout.preferredHeight: root.theme.dp(34)
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                model: root.scopes; textRole: "text"; restrictChoices: true
                currentIndex: root.scopeIndex; enabled: !root.loading && !root.loadingDrop && !root.saving
                onModelChanged: Qt.callLater(() => scopeChoice.currentIndex = root.scopeIndex)
                background: Rectangle { color: root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                onActivated: index => root.selectScope(index)
            }
            RedesignComboBox {
                id: sourceChoice
                objectName: "trackAssignmentFiles"
                Layout.preferredWidth: Math.min(root.theme.dp(200), root.width * 0.23); Layout.preferredHeight: root.theme.dp(34)
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                model: root.sourceChoices; currentIndex: root.sourceIndex
                enabled: !root.loading && !root.loadingDrop && !root.saving
                background: Rectangle { color: root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                onModelChanged: Qt.callLater(() => sourceChoice.currentIndex = root.sourceIndex)
                onActivated: index => root.selectSource(index)
            }
            RedesignButton {
                objectName: "trackAssignmentFolder"
                visible: root.sourceIndex === 0
                Layout.fillWidth: true; Layout.preferredHeight: root.theme.dp(34)
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                iconName: "folder"; text: root.sourceFolder || qsTr("Select track folder"); leftAligned: true
                enabled: !root.saving && !root.loadingDrop
                background: Rectangle { color: root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                contentItem: RowLayout {
                    spacing: root.theme.dp(12)
                    RedesignIcon { sourceSize: Qt.size(root.theme.dp(40), root.theme.dp(40)); Layout.leftMargin: root.theme.dp(10); Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20); name: "folder"; color: root.theme.foreground }
                    Text { Layout.fillWidth: true; Layout.rightMargin: root.theme.dp(12); text: root.sourceFolder ? decodeURIComponent(root.sourceFolder.replace(/^file:\/\//, "")) : qsTr("Select track folder"); elide: Text.ElideMiddle; font.pixelSize: root.theme.dp(14); color: root.theme.foreground }
                }
                onClicked: root.folderRequested()
            }
            C.TextField {
                objectName: "trackAssignmentSearch"
                visible: root.onlineMode
                Layout.fillWidth: true; Layout.preferredHeight: root.theme.dp(34)
                enabled: root.providerConfigured && !root.saving
                text: root.searchTitle; placeholderText: qsTr("Search subtitles")
                leftPadding: root.theme.dp(40); rightPadding: root.theme.dp(10)
                color: root.theme.foreground; placeholderTextColor: root.theme.foreground
                font.pixelSize: root.theme.dp(14); selectByMouse: true
                Accessible.name: qsTr("Search subtitles")
                background: Rectangle { color: root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                RedesignButton {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: root.theme.dp(34); implicitHeight: root.theme.dp(34)
                    scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                    iconName: "search"; iconSize: root.theme.dp(20); text: qsTr("Search subtitles")
                    onClicked: root.requestSearch()
                }
                onTextEdited: { root.searchTitle = text; searchDebounce.restart() }
                onAccepted: root.requestSearch()
            }
            RedesignComboBox {
                id: languageChoice
                objectName: "trackAssignmentLanguage"
                visible: root.onlineMode
                Layout.preferredWidth: Math.min(root.theme.dp(200), root.width * 0.20); Layout.preferredHeight: root.theme.dp(34)
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                model: root.searchLanguageChoices; textRole: "text"
                enabled: root.providerConfigured && !root.saving
                function syncLanguage() { currentIndex = root.searchLanguageChoices.findIndex(item => item.code === root.searchLanguage) }
                Connections { target: root; function onSearchLanguageChanged() { languageChoice.syncLanguage() } }
                onModelChanged: Qt.callLater(syncLanguage)
                Component.onCompleted: syncLanguage()
                onActivated: index => { root.manualSearchLanguage = true; root.searchLanguage = root.searchLanguageChoices[index].code; root.requestSearch() }
                background: Rectangle { color: root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
            }
            C.TextField {
                objectName: "trackAssignmentLink"
                visible: root.linkMode
                Layout.fillWidth: true; Layout.preferredHeight: root.theme.dp(34)
                text: root.linkText; placeholderText: qsTr("Paste a direct subtitle file link")
                enabled: !root.saving && !root.loadingDrop
                leftPadding: root.theme.dp(40); rightPadding: root.theme.dp(10)
                color: root.theme.foreground; placeholderTextColor: root.theme.foreground
                font.pixelSize: root.theme.dp(14); selectByMouse: true
                Accessible.name: placeholderText
                background: Rectangle { color: root.theme.panel; radius: root.theme.dp(4); border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                RedesignIcon { anchors.left: parent.left; anchors.leftMargin: root.theme.dp(10); anchors.verticalCenter: parent.verticalCenter; width: root.theme.dp(20); height: width; name: "link"; color: root.theme.foreground }
                onTextEdited: root.linkText = text
                onAccepted: root.addLink()
            }
            RedesignButton {
                objectName: "trackAssignmentAddLink"
                visible: root.linkMode
                Layout.preferredWidth: root.theme.dp(60); Layout.preferredHeight: root.theme.dp(34)
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                caption: qsTr("Add"); text: caption; enabled: !root.saving && !root.loadingDrop && root.linkText.trim().length > 0
                onClicked: root.addLink()
            }

        }
    }
    contentItem: Item {
        DropArea {
            id: fileDrop
            objectName: "trackAssignmentDropArea"
            anchors.fill: parent
            enabled: root.visible && !root.saving && !root.loading && !root.loadingDrop
            onEntered: drag => drag.accepted = drag.hasUrls || (root.subtitles && drag.hasText)
            onDropped: drop => {
                drop.accepted = false
                if (root.dropSources(root.dropUrls(drop))) drop.accept(Qt.CopyAction)
            }
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: root.theme.dp(12); z: 4
            visible: fileDrop.containsDrag
            color: Qt.alpha(root.theme.field, root.theme.floatingOpacity); radius: root.theme.dp(8)
            border.color: root.theme.accent; border.width: root.theme.dp(2)
            Text {
                anchors.centerIn: parent; width: parent.width - root.theme.dp(40); wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: root.subtitles ? qsTr("Drop subtitle files, folders or links here") : qsTr("Drop audio files or folders here")
                color: root.theme.foreground; font.pixelSize: root.theme.dp(18)
            }
        }
        C.ScrollView {
            anchors.fill: parent; anchors.topMargin: root.theme.dp(20); anchors.leftMargin: root.theme.dp(20); anchors.rightMargin: root.theme.dp(20)
            clip: true; contentWidth: availableWidth
            C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff
            ListView {
                id: list
                objectName: "trackAssignmentList"
                model: root.loading ? [] : root.fileMode ? root.visibleSources : root.rows
                spacing: root.theme.dp(4)
                delegate: C.ItemDelegate {
                    id: entry
                    required property var modelData
                    required property int index
                    objectName: "trackAssignmentRow_" + index
                    width: ListView.view.width; height: root.theme.dp(36)
                    enabled: !root.saving; padding: root.theme.dp(10)
                    highlighted: root.fileMode && root.tracks(root.anchorFile).includes(modelData.url)
                    Accessible.name: modelData.name
                    background: Rectangle { radius: root.theme.dp(5); color: entry.highlighted ? root.theme.field : entry.hovered ? root.theme.hover : "transparent"; border.color: entry.visualFocus || rowDrop.containsDrag ? root.theme.accent : "transparent" }
                    DropArea {
                        id: rowDrop
                        objectName: "trackAssignmentRowDrop_" + entry.index
                        anchors.fill: parent
                        enabled: !root.fileMode && !root.saving && !root.loadingDrop
                        onEntered: drag => drag.accepted = drag.hasUrls || (root.subtitles && drag.hasText)
                        onDropped: drop => {
                            drop.accepted = false
                            if (root.dropSources(root.dropUrls(drop), entry.modelData.url)) drop.accept(Qt.CopyAction)
                        }
                    }
                    onClicked: root.fileMode ? root.toggle(root.anchorFile, modelData.url) : root.chooseRow(modelData.url)
                    contentItem: RowLayout {
                        spacing: root.theme.dp(18)
                        C.CheckBox {
                            visible: !root.fileMode
                            Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(24)
                            checked: !!root.selectedRows[entry.modelData.url]
                            Accessible.name: qsTr("Select %1").arg(entry.modelData.name)
                            onToggled: root.selectedRows = Object.assign({}, root.selectedRows, {[entry.modelData.url]: checked})
                            indicator: Rectangle { x: root.theme.dp(2); y: (parent.height - height) / 2; width: root.theme.dp(16); height: width; radius: root.theme.dp(2); color: "transparent"; border.color: parent.visualFocus ? root.theme.accent : root.theme.foreground
                                RedesignIcon { sourceSize: Qt.size(root.theme.dp(40), root.theme.dp(40)); anchors.fill: parent; anchors.margins: root.theme.dp(1); name: "check"; color: root.theme.accent; visible: parent.parent.checked }
                            }
                            contentItem: Item {}
                        }
                        RedesignIcon { sourceSize: Qt.size(root.theme.dp(40), root.theme.dp(40)); visible: root.fileMode; Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20); name: root.subtitles ? "subtitle-file" : "audio-file"; color: root.theme.foreground }
                        Text {
                            Layout.fillWidth: root.fileMode; Layout.preferredWidth: root.fileMode ? -1 : root.theme.dp(160)
                            text: entry.modelData.name; font.pixelSize: root.theme.dp(14); color: root.theme.foreground; elide: Text.ElideMiddle
                        }
                        Item {
                            visible: !root.fileMode; Layout.fillWidth: true; Layout.preferredWidth: root.theme.dp(280); Layout.preferredHeight: root.theme.dp(1)
                            Row { anchors.fill: parent; spacing: root.theme.dp(8); clip: true
                                Repeater { model: Math.ceil(parent.width / root.theme.dp(16)); Rectangle { width: root.theme.dp(8); height: root.theme.dp(1); color: root.theme.border } }
                            }
                        }
                        RedesignButton {
                            visible: !root.fileMode
                            objectName: "trackAssignmentChoose_" + entry.index
                            Layout.fillWidth: true; Layout.preferredWidth: root.theme.dp(460); Layout.preferredHeight: root.theme.dp(32)
                            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                            iconName: root.subtitles ? "subtitle-file" : "audio-file"; leftAligned: true
                            text: qsTr("Select tracks for %1").arg(entry.modelData.name)
                            contentItem: RowLayout {
                                spacing: root.theme.dp(12)
                                RedesignIcon { sourceSize: Qt.size(root.theme.dp(40), root.theme.dp(40)); Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20); name: root.subtitles ? "subtitle-file" : "audio-file"; color: root.theme.foreground }
                                Text { Layout.fillWidth: true; text: root.tracks(entry.modelData.url).length ? root.tracks(entry.modelData.url).map(url => root.fileName(url)).join(", ") : qsTr("Select tracks"); elide: Text.ElideMiddle; color: root.theme.foreground; font.pixelSize: root.theme.dp(14) }
                            }
                            onClicked: root.chooseRow(entry.modelData.url)
                        }
                        RedesignIcon { sourceSize: Qt.size(root.theme.dp(40), root.theme.dp(40)); visible: entry.highlighted; Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20); name: "check"; color: root.theme.accent }
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent; width: parent.width - root.theme.dp(40); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            visible: !(root.onlineMode && !root.providerConfigured) && (root.loading || root.loadingSources || root.loadingDrop || root.matching || root.searching || (!list.count && !root.errorMessage))
            text: root.searching ? qsTr("Searching subtitles…") : root.matching ? qsTr("Matching tracks…") : root.loading || root.loadingSources || root.loadingDrop ? qsTr("Loading files…") : root.onlineMode ? qsTr("No subtitles found. Try another title or language.") : root.linkMode ? qsTr("Paste a direct subtitle file link, then select Add.") : root.fileMode ? qsTr("Select a folder or choose track files from your computer.") : qsTr("There are no media files here.")
            color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
        }        Column {
            anchors.centerIn: parent; width: Math.max(0, parent.width - root.theme.dp(60))
            spacing: root.theme.dp(16); visible: root.onlineMode && !root.providerConfigured
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: qsTr("OpenSubtitles is not set up. Add an API key to use this source.")
                color: root.theme.foreground; font.pixelSize: root.theme.dp(14)
            }
            RedesignButton {
                objectName: "trackAssignmentSetup"
                anchors.horizontalCenter: parent.horizontalCenter
                scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
                caption: qsTr("Set up OpenSubtitles"); text: caption; onClicked: providerSetup.open()
            }
        }

    }
    footer: Item {
        implicitHeight: root.theme.dp(72) + (error.visible ? error.implicitHeight + root.theme.dp(12) : 0)
        Text {
            id: error
            objectName: "trackAssignmentError"
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: root.theme.dp(20); anchors.topMargin: root.theme.dp(4)
            visible: text.length > 0
            text: root.errorMessage || (root.scopeIndex === 1
                ? root.removeFolderRule ? qsTr("VLC will remove the saved folder matches.")
                : !root.folderRuleAutomatic ? qsTr("Automatic matching is off in Settings. These choices apply to the current files.")
                : root.folderRuleDefinition.length || root.folderRuleNeedsPreparation ? qsTr("VLC will use these matches for new files in this folder.")
                : qsTr("VLC will save these choices for the current files.")
                : root.folderRuleChanged ? qsTr("VLC will also save the folder matches.") : "")
            wrapMode: Text.WordWrap
            font.pixelSize: root.theme.dp(14); color: root.errorMessage.length ? root.theme.danger : root.theme.foreground
            Accessible.role: root.errorMessage.length ? Accessible.AlertMessage : Accessible.StaticText
        }
        RedesignButton {
            objectName: "trackAssignmentCancel"
            x: root.theme.dp(20); anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(20)
            implicitWidth: root.theme.dp(100); implicitHeight: root.theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("Cancel"); text: caption; enabled: !root.saving || root.cancelableSave; onClicked: root.reject()
            background: Rectangle { radius: root.theme.dp(5); color: parent.hovered ? root.theme.hover : root.theme.background; border.color: parent.visualFocus ? root.theme.accent : "transparent" }
        }
        RedesignButton {
            objectName: "trackAssignmentProviderSettings"
            x: root.theme.dp(132); anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(20)
            visible: root.onlineMode && root.providerConfigured && root.width > root.theme.dp(600)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: qsTr("OpenSubtitles setup"); text: caption; enabled: !root.saving; onClicked: providerSetup.open()
        }
        RedesignButton {
            objectName: "trackAssignmentClearSelected"
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(20)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            visible: !root.fileMode && Object.values(root.selectedRows).some(value => value)
            iconName: "remove"; caption: root.width >= root.theme.dp(640) ? qsTr("Clear selected tracks") : ""
            text: qsTr("Clear selected tracks"); enabled: !root.saving
            onClicked: { for (const url of Object.keys(root.selectedRows)) if (root.selectedRows[url]) root.setTracks(url, []) }
        }
        RedesignButton {
            objectName: "trackAssignmentRemoveFolderRule"
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(20)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            visible: root.scopeIndex === 1 && (root.folderRuleBaseline.length > 0 || root.removeFolderRule)
                && !Object.values(root.selectedRows).some(value => value)
            iconName: root.removeFolderRule ? "refresh" : "remove"
            caption: root.width >= root.theme.dp(640) ? text : ""
            text: root.removeFolderRule ? qsTr("Keep folder matches") : qsTr("Remove folder matches")
            enabled: !root.saving; onClicked: { root.removeFolderRule = !root.removeFolderRule; root.folderRuleTouched = true }
        }
        RedesignButton {
            objectName: "trackAssignmentSave"
            anchors.right: parent.right; anchors.rightMargin: root.theme.dp(20); anchors.bottom: parent.bottom; anchors.bottomMargin: root.theme.dp(20)
            implicitWidth: root.theme.dp(100); implicitHeight: root.theme.dp(32)
            scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
            caption: root.saving ? qsTr("Saving…") : qsTr("Save"); text: caption
            enabled: !root.saving && !root.loading && !root.loadingSources && !root.loadingDrop && !root.matching && (root.changedRows.length > 0 || root.folderRuleChanged)
            foreground: root.theme.accent
            background: Rectangle { radius: root.theme.dp(5); color: root.theme.progress; border.color: parent.visualFocus ? root.theme.accent : "transparent"; opacity: parent.enabled ? 1 : 0.4 }
            onClicked: root.submit()
        }
    }
    RedesignSubtitleProviderSetup {
        id: providerSetup
        objectName: "trackAssignmentProviderSetup"
        scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor
        hasCustomKey: root.providerHasCustomKey; hasConsumerKey: root.providerHasConsumerKey
        busy: root.saving
        onSaveRequested: key => root.setupRequested(key)
        onRemoveRequested: root.removeSetupRequested()
        onHelpRequested: root.apiKeyHelpRequested()
    }
    C.Popup {
        id: picker
        property string targetUrl: ""
        objectName: "trackAssignmentPicker"
        anchors.centerIn: parent
        width: Math.min(root.theme.dp(640), root.width - root.theme.dp(40))
        height: Math.min(root.theme.dp(460), root.height - root.theme.dp(80))
        padding: root.theme.dp(12); modal: true; focus: true
        background: Rectangle { color: root.theme.panel; radius: root.theme.dp(8); border.color: root.theme.border }
        contentItem: ColumnLayout {
            spacing: root.theme.dp(10)
            Text { Layout.fillWidth: true; text: root.fileName(picker.targetUrl); elide: Text.ElideMiddle; color: root.theme.bright; font.pixelSize: root.theme.dp(14) }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: root.visibleSources
                DropArea {
                    objectName: "trackAssignmentPickerDropArea"
                    anchors.fill: parent
                    enabled: picker.visible && !root.saving && !root.loadingDrop
                    onEntered: drag => drag.accepted = drag.hasUrls || (root.subtitles && drag.hasText)
                    onDropped: drop => {
                        drop.accepted = false
                        if (root.dropSources(root.dropUrls(drop), picker.targetUrl)) drop.accept(Qt.CopyAction)
                    }
                }
                C.ScrollBar.vertical: C.ScrollBar {}
                delegate: C.ItemDelegate {
                    required property var modelData
                    width: ListView.view.width; height: root.theme.dp(36)
                    text: modelData.name; highlighted: root.tracks(picker.targetUrl).includes(modelData.url)
                    onClicked: root.toggle(picker.targetUrl, modelData.url)
                    background: Rectangle { radius: root.theme.dp(4); color: parent.highlighted ? root.theme.field : parent.hovered ? root.theme.hover : "transparent"; border.color: parent.visualFocus ? root.theme.accent : "transparent" }
                    contentItem: RowLayout {
                        Text { Layout.fillWidth: true; text: parent.parent.text; elide: Text.ElideMiddle; color: root.theme.foreground; font.pixelSize: root.theme.dp(14) }
                        RedesignIcon { sourceSize: Qt.size(root.theme.dp(40), root.theme.dp(40)); Layout.preferredWidth: root.theme.dp(20); Layout.preferredHeight: root.theme.dp(20); name: "check"; color: root.theme.accent; visible: parent.parent.highlighted }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                RedesignButton { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; caption: qsTr("Choose files…"); text: caption; onClicked: root.filesRequested(picker.targetUrl) }
                RedesignButton { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; caption: qsTr("Clear"); text: caption; onClicked: root.setTracks(picker.targetUrl, []) }
                Item { Layout.fillWidth: true }
                RedesignButton { scaleFactor: root.scaleFactor; lightTheme: root.lightTheme; accentColor: root.accentColor; caption: qsTr("Done"); text: caption; onClicked: picker.close() }
            }
        }
    }
}
