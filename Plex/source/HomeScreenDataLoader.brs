'*
'* DataLoader implementation for the home screen.
'*

Function createHomeScreenDataLoader(listener)
    loader = CreateObject("roAssociativeArray")
    initDataLoader(loader)

    loader.ScreenID = listener.ScreenID
    loader.Listener = listener
    listener.Loader = loader

    loader.LoadMoreContent = homeLoadMoreContent
    loader.GetNames = homeGetNames
    loader.GetLoadStatus = homeGetLoadStatus
    loader.GetPendingRequestCount = loaderGetPendingRequestCount
    loader.RefreshData = homeRefreshData
    loader.OnUrlEvent = homeOnUrlEvent
    loader.OnServerDiscovered = homeOnServerDiscovered
    loader.OnMyPlexChange = homeOnMyPlexChange
    loader.OnServersChange = homeOnServersChange
    loader.OnFoundConnection = homeOnFoundConnection
    loader.UpdatePendingRequestsForConnectionTesting = homeUpdatePendingRequestsForConnectionTesting

    loader.SetupRows = homeSetupRows
    loader.CreateRow = homeCreateRow
    loader.CreateServerRequests = homeCreateServerRequests
    loader.CreateMyPlexRequests = homeCreateMyPlexRequests
    loader.CreatePlaylistRequests = homeCreatePlaylistRequests
    loader.CreateAllPlaylistRequests = homeCreateAllPlaylistRequests
    loader.AddOrStartRequest = homeAddOrStartRequest

    loader.contentArray = []
    loader.RowNames = []
    loader.styles = []
    loader.RowIndexes = {}
    loader.FirstLoad = true
    loader.FirstServer = true
    loader.reinitializeGrid = false

    loader.lastMachineID = RegRead("lastMachineID")
    loader.lastSectionKey = RegRead("lastSectionKey")

    loader.OnTimerExpired = homeOnTimerExpired

    ' Create a static item for prefs and put it in the Misc row.
    prefs = CreateObject("roAssociativeArray")
    prefs.sourceUrl = ""
    prefs.ContentType = "prefs"
    prefs.Key = "globalprefs"
    prefs.Title = "Preferences"
    prefs.ShortDescriptionLine1 = "Preferences"
    prefs.SDPosterURL = "file://pkg:/images/gear.png"
    prefs.HDPosterURL = "file://pkg:/images/gear.png"
    loader.prefsItem = prefs

    ' Create an item for Now Playing in the Misc row that will be shown while
    ' the audio player is active.
    nowPlaying = CreateObject("roAssociativeArray")
    nowPlaying.sourceUrl = ""
    nowPlaying.ContentType = "audio"
    nowPlaying.Key = "nowplaying"
    nowPlaying.Title = "Now Playing"
    nowPlaying.ShortDescriptionLine1 = "Now Playing"
    nowPlaying.SDPosterURL = "file://pkg:/images/section-music.png"
    nowPlaying.HDPosterURL = "file://pkg:/images/section-music.png"
    nowPlaying.CurIndex = invalid
    loader.nowPlayingItem = nowPlaying

    loader.SetupRows()

    ' Kick off an asynchronous GDM discover.
    if RegRead("autodiscover", "preferences", "1") = "1" then
        loader.GDM = createGDMDiscovery(GetViewController().GlobalMessagePort, loader)
        if loader.GDM = invalid then
            Debug("Failed to create GDM discovery object")
        else
            loader.UpdatePendingRequestsForConnectionTesting(true, true)
            timer = createTimer()
            timer.Name = "GDMRequests"
            timer.SetDuration(5000)
            GetViewController().AddTimer(timer, loader)
        end if
    end if

    return loader
End Function

Sub homeSetupRows()
    m.contentArray = []
    m.RowNames = []
    m.styles = []
    m.RowIndexes = {}

    rows = [
        { title: "Channels", key: "channels", style: "square", visibility_key: "row_visibility_channels" },
        { title: "Library Sections", key: "sections", style: "square", visibility_key: "row_visibility_sections" },
        { title: "On Deck", key: "on_deck", style: "portrait", visibility_key: "row_visibility_ondeck" },
        { title: "Recently Added", key: "recently_added", style: "portrait", visibility_key: "row_visibility_recentlyadded" },
        { title: "Queue", key: "queue", style: "landscape", visibility_key: "playlist_view_queue" },
        { title: "Recommendations", key: "recommendations", style: "landscape", visibility_key: "playlist_view_recommendations" },
        { title: "Shared Library Sections", key: "shared_sections", style: "square", visibility_key: "row_visibility_shared_sections" },
        { title: "Miscellaneous", key: "misc", style: "square" }
    ]
    ReorderItemsByKeyPriority(rows, RegRead("home_row_order", "preferences", ""))

    for each row in rows
        visibility = ""
        if row.visibility_key <> invalid then
            visibility = RegRead(row.visibility_key, "preferences", "")
        end if

        if visibility <> "hidden" then
            m.RowIndexes[row.key] = m.CreateRow(row.title, row.style)
        else
            m.RowIndexes[row.key] = -1
        end if
    next

    m.contentArray[m.RowIndexes["misc"]].content.Push(m.prefsItem)

    ' Kick off myPlex requests if we're signed in.
    if MyPlexManager().IsSignedIn then
        m.CreateMyPlexRequests(false)
        m.UpdatePendingRequestsForConnectionTesting(true, true)
        m.UpdatePendingRequestsForConnectionTesting(false, true)
    end if

    ' Kick off requests for servers we already know about.
    configuredServers = PlexMediaServers()
    Debug("Setting up home screen content, server count: " + tostr(configuredServers.Count()))
    for each server in configuredServers
        server.TestConnections(m)
        m.UpdatePendingRequestsForConnectionTesting(server.owned, true)
    next
End Sub

Function homeCreateRow(name, style) As Integer
    index = m.RowNames.Count()

    status = CreateObject("roAssociativeArray")
    status.content = []
    status.loadStatus = 0
    status.toLoad = CreateObject("roList")
    status.pendingRequests = 0
    status.refreshContent = invalid
    status.loadedServers = {}

    m.contentArray.Push(status)
    m.RowNames.Push(name)
    m.styles.Push(style)

    return index
End Function

Sub homeCreateServerRequests(server As Object, startRequests As Boolean)
    ' Request sections
    sections = CreateObject("roAssociativeArray")
    sections.server = server
    sections.key = "/library/sections"

    if server.owned then
        m.AddOrStartRequest(sections, m.RowIndexes["sections"], startRequests)
    else
        m.AddOrStartRequest(sections, m.RowIndexes["shared_sections"], startRequests)
        return
    end if

    ' Request recently used channels
    if m.RowIndexes["channels"] >= 0 then
        channels = CreateObject("roAssociativeArray")
        channels.server = server
        channels.key = "/channels/recentlyViewed"

        allChannels = CreateObject("roAssociativeArray")
        allChannels.Title = "More Channels"
        if AreMultipleValidatedServers() then
            allChannels.ShortDescriptionLine2 = "All channels on " + server.name
        else
            allChannels.ShortDescriptionLine2 = "All channels"
        end if
        allChannels.Description = allChannels.ShortDescriptionLine2
        allChannels.server = server
        allChannels.sourceUrl = ""
        allChannels.Key = "/channels/all"
        allChannels.ThumbUrl = invalid
        allChannels.ThumbProcessed = ""
        channels.item = allChannels
        m.AddOrStartRequest(channels, m.RowIndexes["channels"], startRequests)
    end if

    ' Request global on deck
    if m.RowIndexes["on_deck"] >= 0 then
        onDeck = CreateObject("roAssociativeArray")
        onDeck.server = server
        onDeck.key = "/library/onDeck"
        onDeck.requestType = "media"
        m.AddOrStartRequest(onDeck, m.RowIndexes["on_deck"], startRequests)
    end if

    ' Request recently added
    if m.RowIndexes["recently_added"] >= 0 then
        recents = CreateObject("roAssociativeArray")
        recents.server = server
        recents.key = "/library/recentlyAdded"
        recents.requestType = "media"
        m.AddOrStartRequest(recents, m.RowIndexes["recently_added"], startRequests)
    end if
End Sub

Sub homeCreateMyPlexRequests(startRequests As Boolean)
    myPlex = MyPlexManager()

    if NOT myPlex.IsSignedIn then return

    ' Find any servers linked through myPlex
    httpRequest = myPlex.CreateRequest("", "/pms/servers?includeLite=1")
    context = CreateObject("roAssociativeArray")
    context.requestType = "servers"
    GetViewController().StartRequest(httpRequest, m, context)

    ' Queue and recommendations requests
    m.CreateAllPlaylistRequests(startRequests)

    ' Instead of requesting /pms/system/library/sections we'll just request sections
    ' from any online shared servers directly.
End Sub

Sub homeCreateAllPlaylistRequests(startRequests As Boolean)
    if NOT MyPlexManager().IsSignedIn then return

    m.CreatePlaylistRequests("queue", "All Queued Items", "All queued items, including already watched items", m.RowIndexes["queue"], startRequests)
    m.CreatePlaylistRequests("recommendations", "All Recommended Items", "All recommended items, including already watched items", m.RowIndexes["recommendations"], startRequests)
End Sub

Sub homeCreatePlaylistRequests(name, title, description, row, startRequests)
    if row < 0 then return
    view = RegRead("playlist_view_" + name, "preferences", "unwatched")

    ' Unwatched recommended items
    currentItems = CreateObject("roAssociativeArray")
    currentItems.server = MyPlexManager()
    currentItems.requestType = "playlist"
    currentItems.key = "/pms/playlists/" + name + "/" + view

    ' A dummy item to pull up the varieties (e.g. all and watched)
    allItems = CreateObject("roAssociativeArray")
    allItems.Title = title
    allItems.Description = description
    allItems.ShortDescriptionLine2 = allItems.Description
    allItems.server = currentItems.server
    allItems.sourceUrl = ""
    allItems.Key = "/pms/playlists/" + name
    allItems.ThumbUrl = invalid
    allItems.ThumbProcessed = ""
    allItems.ContentType = "playlists"
    currentItems.item = allItems
    currentItems.emptyItem = allItems

    m.AddOrStartRequest(currentItems, row, startRequests)
End Sub

Sub homeAddOrStartRequest(request As Object, row As Integer, startRequests As Boolean)
    if row < 0 OR row >= m.contentArray.Count() then return

    status = m.contentArray[row]

    if startRequests then
        httpRequest = request.server.CreateRequest("", request.Key, true, request.connectionUrl)
        request.row = row
        request.requestType = firstOf(request.requestType, "row")

        if GetViewController().StartRequest(httpRequest, m, request) then
            status.pendingRequests = status.pendingRequests + 1
        end if
    else
        status.toLoad.AddTail(request)
    end if
End Sub

Function IsMyPlexServer(item) As Boolean
    return (item.server <> invalid AND NOT item.server.IsConfigured)
End Function

Function AlwaysTrue(item) As Boolean
    return true
End Function

Function IsInvalidServer(item) As Boolean
    server = item.server
    if server <> invalid AND server.IsConfigured AND server.machineID <> invalid then
        return (GetPlexMediaServer(server.machineID) = invalid)
    else if item.key = "globalsearch"
        return (GetPrimaryServer() = invalid)
    else
        return false
    end if
End Function

Function homeLoadMoreContent(focusedIndex, extraRows=0)
    myPlex = MyPlexManager()
    if m.FirstLoad then
        m.FirstLoad = false
        if NOT myPlex.IsSignedIn then
            m.Listener.OnDataLoaded(m.RowIndexes["queue"], [], 0, 0, true)
            m.Listener.OnDataLoaded(m.RowIndexes["recommendations"], [], 0, 0, true)
            m.Listener.OnDataLoaded(m.RowIndexes["shared_sections"], [], 0, 0, true)
        end if

        m.Listener.hasBeenFocused = false
        m.Listener.ignoreNextFocus = true

        if m.RowIndexes["sections"] >= 0 then
            if type(m.Listener.Screen) = "roGridScreen" then
                m.Listener.SetFocusedItem(m.RowIndexes["sections"], 0)
            else
                m.Listener.Screen.SetFocusedListItem(m.RowIndexes["sections"])
            end if
        end if
    end if

    status = invalid
    extraRowsAlreadyLoaded = true
    for i = 0 to extraRows
        index = focusedIndex + i
        if index >= m.contentArray.Count() then
            exit for
        else if m.contentArray[index].loadStatus = 0 OR m.contentArray[index].toLoad.Count() > 0 then
            if status = invalid then
                status = m.contentArray[index]
                loadingRow = index
            else
                extraRowsAlreadyLoaded = false
                exit for
            end if
        end if
    end for

    if status = invalid then return true

    ' If we have something to load, kick off all the requests asynchronously
    ' now. Otherwise return according to whether or not additional rows have
    ' requests that need to be kicked off. As a special case, if there's
    ' nothing to load and no pending requests, we must be in a row with static
    ' content, tell the screen it's been loaded.

    if status.toLoad.Count() > 0 then
        status.loadStatus = 1

        origCount = status.pendingRequests
        for each toLoad in status.toLoad
            m.AddOrStartRequest(toLoad, loadingRow, true)
        next
        numRequests = status.pendingRequests - origCount

        status.toLoad.Clear()

        Debug("Successfully kicked off " + tostr(numRequests) + " requests for row " + tostr(loadingRow) + ", pending requests now: " + tostr(status.pendingRequests))
    else if status.pendingRequests > 0 then
        status.loadStatus = 1
        Debug("No additional requests to kick off for row " + tostr(loadingRow) + ", pending request count: " + tostr(status.pendingRequests))
    else
        ' Special case, if we try loading the Misc row and have no servers,
        ' this is probably a first run scenario, try to be helpful.
        if loadingRow = m.RowIndexes["misc"] AND RegRead("serverList", "servers") = invalid AND NOT myPlex.IsSignedIn then
            if RegRead("autodiscover", "preferences", "1") = "1" then
                if m.GdmTimer = invalid then
                    ' Give GDM discovery a chance...
                    m.LoadingFacade = CreateObject("roOneLineDialog")
                    m.LoadingFacade.SetTitle("Looking for Plex Media Servers...")
                    m.LoadingFacade.ShowBusyAnimation()
                    m.LoadingFacade.Show()

                    m.GdmTimer = createTimer()
                    m.GdmTimer.Name = "GDM"
                    m.GdmTimer.SetDuration(5000)
                    GetViewController().AddTimer(m.GdmTimer, m)
                end if
            else
                ' Slightly strange, GDM disabled but no servers configured
                Debug("No servers, no GDM, and no myPlex...")
                m.Listener.SetFocusedItem(loadingRow, 0)
                GetViewController().ShowHelpScreen()
                status.loadStatus = 2
                m.Listener.OnDataLoaded(loadingRow, status.content, 0, status.content.Count(), true)
            end if
        else
            status.loadStatus = 2
            m.Listener.OnDataLoaded(loadingRow, status.content, 0, status.content.Count(), true)
        end if
    end if

    return extraRowsAlreadyLoaded
End Function

Sub homeOnUrlEvent(msg, requestContext)
    ' If this was a myPlex servers request, decrement the pending requests count
    ' regardless of status code.
    if requestContext.requestType = "servers" then
        m.UpdatePendingRequestsForConnectionTesting(true, false)
        m.UpdatePendingRequestsForConnectionTesting(false, false)
    end if

    status = invalid
    if requestContext.row <> invalid then
        status = m.contentArray[requestContext.row]
        status.pendingRequests = status.pendingRequests - 1
    end if

    url = tostr(requestContext.Request.GetUrl())
    server = requestContext.server

    if msg.GetResponseCode() <> 200 then
        Debug("Got a " + tostr(msg.GetResponseCode()) + " response from " + url + " - " + tostr(msg.GetFailureReason()))

        if status <> invalid AND status.pendingRequests = 0 then
            status.loadStatus = 2
            if status.refreshContent <> invalid then
                status.content = status.refreshContent
                status.refreshContent = invalid
            end if
            m.Listener.OnDataLoaded(requestContext.row, status.content, 0, status.content.Count(), true)
        end if

        return
    else
        Debug("Got a 200 response from " + url + " (type " + tostr(requestContext.requestType) + ", row " + tostr(requestContext.row) + ")")
    end if

    xml = CreateObject("roXMLElement")
    xml.Parse(msg.GetString())

    if requestContext.requestType = "row" then
        countLoaded = 0
        content = firstOf(status.refreshContent, status.content)
        startItem = content.Count()

        server.IsAvailable = true
        machineId = tostr(server.MachineID)

        if status.loadedServers.DoesExist(machineID) then
            Debug("Ignoring content for server that was already loaded: " + machineID)
            items = []
            requestContext.item = invalid
            requestContext.emptyItem = invalid
        else
            status.loadedServers[machineID] = "1"
            response = CreateObject("roAssociativeArray")
            response.xml = xml
            response.server = server
            response.sourceUrl = url
            container = createPlexContainerForXml(response)
            items = container.GetMetadata()

            if AreMultipleValidatedServers() then
                serverStr = " on " + server.name
            else
                serverStr = ""
            end if
        end if

        for each item in items
            add = true

            ' A little weird, but sections will only have owned="1" on the
            ' myPlex request, so we ignore them here since we should have
            ' also requested them from the server directly.
            if item.Owned = "1" then
                add = false
            else if item.MachineID <> invalid then
                existingServer = GetPlexMediaServer(item.MachineID)
                if existingServer <> invalid then
                    Debug("Found a server for the section: " + tostr(item.Title) + " on " + tostr(existingServer.name))
                    item.server = existingServer
                    serverStr = " on " + existingServer.name
                else
                    Debug("Found a shared section for an unknown server: " + tostr(item.MachineID))
                    add = false
                end if
            end if

            if NOT add then
            else if item.Type = "channel" then
                channelType = Mid(item.key, 2, 5)
                if channelType = "music" then
                    item.ShortDescriptionLine2 = "Music channel" + serverStr
                else if channelType = "photo" then
                    item.ShortDescriptionLine2 = "Photo channel" + serverStr
                else if channelType = "video" then
                    item.ShortDescriptionLine2 = "Video channel" + serverStr
                else
                    Debug("Skipping unsupported channel type: " + tostr(channelType))
                    add = false
                end if
            else if item.Type = "movie" then
                item.ShortDescriptionLine2 = "Movie section" + serverStr
            else if item.Type = "show" then
                item.ShortDescriptionLine2 = "TV section" + serverStr
            else if item.Type = "artist" then
                item.ShortDescriptionLine2 = "Music section" + serverStr
            else if item.Type = "photo" then
                item.ShortDescriptionLine2 = "Photo section" + serverStr
            else
                Debug("Skipping unsupported section type: " + tostr(item.Type))
                add = false
            end if

            if add then
                item.Description = item.ShortDescriptionLine2

                content.Push(item)
                countLoaded = countLoaded + 1
            end if
        next

        if requestContext.item <> invalid AND countLoaded > 0 then
            countLoaded = countLoaded + 1
            content.Push(requestContext.item)
        else if requestContext.emptyItem <> invalid AND countLoaded = 0 then
            countLoaded = countLoaded + 1
            content.Push(requestContext.emptyItem)
        end if

        if status.toLoad.Count() = 0 AND status.pendingRequests = 0 then
            status.loadStatus = 2
        end if

        if status.refreshContent <> invalid then
            if status.toLoad.Count() = 0 AND status.pendingRequests = 0 then
                status.content = status.refreshContent
                status.refreshContent = invalid
                m.Listener.OnDataLoaded(requestContext.row, status.content, 0, status.content.Count(), true)
            end if
        else
            m.Listener.OnDataLoaded(requestContext.row, status.content, startItem, countLoaded, true)
        end if

        if NOT(m.Listener.firstSectionFocused = true) AND server.machineID = m.lastMachineID and (requestContext.row = m.RowIndexes["sections"] or requestContext.row = m.RowIndexes["shared_sections"]) then
            m.Listener.firstSectionFocused = true
            Debug("Trying to focus last used section")
            for i = 0 to status.content.Count() - 1
                if status.content[i].key = m.lastSectionKey then
                    m.Listener.SetFocusedItem(requestContext.row, i)
                    exit for
                end if
            next
        end if
    else if requestContext.requestType = "media" then
        countLoaded = 0
        content = firstOf(status.refreshContent, status.content)
        startItem = content.Count()

        server.IsAvailable = true
        machineId = tostr(server.MachineID)

        if status.loadedServers.DoesExist(machineID) then
            Debug("Ignoring content for server that was already loaded: " + machineID)
            items = []
            requestContext.item = invalid
            requestContext.emptyItem = invalid
        else
            status.loadedServers[machineID] = "1"
            response = CreateObject("roAssociativeArray")
            response.xml = xml
            response.server = server
            response.sourceUrl = url
            container = createPlexContainerForXml(response)
            items = container.GetMetadata()
        end if

        for each item in items
            content.Push(item)
            countLoaded = countLoaded + 1
        next

        if status.toLoad.Count() = 0 AND status.pendingRequests = 0 then
            status.loadStatus = 2
        end if

        if status.refreshContent <> invalid then
            if status.toLoad.Count() = 0 AND status.pendingRequests = 0 then
                status.content = status.refreshContent
                status.refreshContent = invalid
                m.Listener.OnDataLoaded(requestContext.row, status.content, 0, status.content.Count(), true)
            end if
        else
            m.Listener.OnDataLoaded(requestContext.row, status.content, startItem, countLoaded, true)
        end if
    else if requestContext.requestType = "playlist" then
        response = CreateObject("roAssociativeArray")
        response.xml = xml
        response.server = server
        response.sourceUrl = url
        container = createPlexContainerForXml(response)

        status.content = container.GetMetadata()

        if requestContext.item <> invalid AND status.content.Count() > 0 then
            status.content.Push(requestContext.item)
        else if requestContext.emptyItem <> invalid AND status.content.Count() = 0 then
            status.content.Push(requestContext.emptyItem)
        end if

        status.loadStatus = 2

        m.Listener.OnDataLoaded(requestContext.row, status.content, 0, status.content.Count(), true)
    else if requestContext.requestType = "servers" then
        for each serverElem in xml.Server
            ' If we already have a server for this machine ID then disregard
            existing = GetPlexMediaServer(serverElem@machineIdentifier)
            addr = firstOf(serverElem@scheme, "http") + "://" + serverElem@host + ":" + serverElem@port
            if addr = "http://:" then addr = ""

            if existing <> invalid AND (existing.IsAvailable OR existing.ServerUrl = addr) then
                Debug("Ignoring duplicate shared server: " + tostr(serverElem@machineIdentifier))
                existing.AccessToken = firstOf(serverElem@accessToken, MyPlexManager().AuthToken)
                RegWrite(existing.machineID, existing.AccessToken, "server_tokens")
            else
                if existing = invalid then
                    newServer = newPlexMediaServer(addr, serverElem@name, serverElem@machineIdentifier)
                else
                    newServer = existing
                    newServer.ServerUrl = addr
                end if

                newServer.AccessToken = firstOf(serverElem@accessToken, MyPlexManager().AuthToken)
                newServer.synced = (serverElem@synced = "1")
                RegWrite(newServer.machineID, newServer.AccessToken, "server_tokens")
                
                if serverElem@owned = "1" then
                    newServer.name = firstOf(serverElem@name, newServer.name)
                    newServer.owned = true
                    newServer.local = false
                else
                    newServer.name = firstOf(serverElem@name, newServer.name) + " (shared by " + serverElem@sourceTitle + ")"
                    newServer.owned = false
                end if

                ' If we got local addresses, kick off simultaneous requests for all
                ' of them. The first one back will win, so we should always use the
                ' most efficient connection.
                localAddresses = strTokenize(serverElem@localAddresses, ",")
                for each localAddress in localAddresses
                    newServer.AddConnection("http://" + localAddress + ":32400", true)
                next

                newServer.TestConnections(m)
                m.UpdatePendingRequestsForConnectionTesting(newServer.owned, true)

                Debug("Added myPlex server: " + tostr(newServer.name))
            end if
        next
    end if
End Sub

Sub homeOnServerDiscovered(serverInfo)
    Debug("GDM discovery found server at " + tostr(serverInfo.Url))

    existing = GetPlexMediaServer(serverInfo.MachineID)
    if existing <> invalid then
        if existing.ServerUrl = serverInfo.Url then
            Debug("GDM discovery ignoring already configured server")
        else
            Debug("Found new address for " + serverInfo.Name + ": " + existing.ServerUrl + " -> " + serverInfo.Url)
            existing.Name = serverInfo.Name
            existing.ServerUrl = serverInfo.Url
            existing.owned = true
            existing.IsConfigured = true
            existing.local = true
            existing.AddConnection(serverInfo.Url, true)
            existing.TestConnections(m)
            UpdateServerAddress(existing)
            m.UpdatePendingRequestsForConnectionTesting(existing.owned, true)
        end if
    else
        AddServer(serverInfo.Name, serverInfo.Url, serverInfo.MachineID)
        server = newPlexMediaServer(serverInfo.Url, serverInfo.Name, serverInfo.MachineID)
        server.owned = true
        server.IsConfigured = true
        server.local = true
        PutPlexMediaServer(server)
        server.AddConnection(serverInfo.Url, true)
        server.TestConnections(m)
        m.UpdatePendingRequestsForConnectionTesting(server.owned, true)
    end if
End Sub

Function homeGetNames()
    return m.RowNames
End Function

Function homeGetLoadStatus(row)
    return m.contentArray[row].loadStatus
End Function

Sub homeRefreshData()
    ' The home screen is never empty, make sure we don't close ourself.
    m.Listener.hasData = true

    if m.reinitializeGrid then
        m.reinitializeGrid = false
        m.FirstLoad = true
        m.FirstServer = true

        ClearPlexMediaServers()
        m.SetupRows()
        m.Listener.InitializeRows()

        ' HomeScreen should re-load all rows. This will fix hiding, and
        ' showing rows depending on users preferences. The home screen has
        ' a limited number of rows, so it shouldn't cause any slowdowns.
        maxRow = m.contentArray.Count() - 1
        for row = 0 to maxRow
            m.LoadMoreContent(row, 0)
        end for
    else
        ' Refresh the queue
        m.CreateAllPlaylistRequests(true)

        ' Refresh things that may have changed as a result of our actions.
        for each name in ["channels", "on_deck"]
            row = m.RowIndexes[name]
            if row >= 0 then
                m.contentArray[row].refreshContent = []
                m.contentArray[row].loadedServers.Clear()
            end if
        next

        for each server in GetOwnedPlexMediaServers()
            m.CreateServerRequests(server, true)
        next
    end if

    ' Update the Now Playing item according to whether or not something is playing
    miscContent = m.contentArray[m.RowIndexes["misc"]].content
    if m.nowPlayingItem.CurIndex = invalid AND AudioPlayer().ContextScreenID <> invalid then
        m.nowPlayingItem.CurIndex = miscContent.Count()
        miscContent.Push(m.nowPlayingItem)
    else if m.nowPlayingItem.CurIndex <> invalid AND AudioPlayer().ContextScreenID = invalid then
        miscContent.Delete(m.nowPlayingItem.CurIndex)
        m.nowPlayingItem.CurIndex = invalid
    end if

    ' Clear any screensaver images, use the default.
    SaveImagesForScreenSaver(invalid, {})
End Sub

Sub homeOnMyPlexChange()
    Debug("myPlex status changed")
    m.reinitializeGrid = true
End Sub

Sub homeOnServersChange()
    m.reinitializeGrid = true
End Sub

Sub homeOnTimerExpired(timer)
    if timer.Name = "GDM" then
        Debug("Done waiting for GDM")

        if m.LoadingFacade <> invalid then
            m.LoadingFacade.Close()
            m.LoadingFacade = invalid
        end if

        m.GdmTimer = invalid

        if RegRead("serverList", "servers") = invalid AND NOT MyPlexManager().IsSignedIn then
            Debug("No servers and no myPlex, appears to be a first run")
            GetViewController().ShowHelpScreen()
            status = m.contentArray[m.RowIndexes["misc"]]
            status.loadStatus = 2
            m.Listener.OnDataLoaded(m.RowIndexes["misc"], status.content, 0, status.content.Count(), true)
        end if
    else if timer.Name = "GDMRequests" then
        m.UpdatePendingRequestsForConnectionTesting(true, false)
    else if timer.Name = "HideServerRows" then
        Debug("Checking to see if we should hide any server rows")
        row_keys = ["channels", "sections", "on_deck", "recently_added", "shared_sections"]

        ' This is a total hack, but because of the mixed aspect grid's propensity
        ' to crash, we need to focus something else ASAP if we're going to hide
        ' the current row. If we wait until we naturally find the row in the
        ' loop, it's too late.
        focusedIndex = validint(m.Listener.selectedRow)
        focusedStatus = m.contentArray[focusedIndex]
        if focusedStatus.pendingRequests = 0 AND focusedStatus.content.Count() = 0 then
            Debug("Looks like we're going to hide the focused row, force loading misc")
            m.LoadMoreContent(m.RowIndexes["misc"], 0)
        end if

        for each row_key in row_keys
            index = m.RowIndexes[row_key]
            if index >= 0 then
                status = m.contentArray[index]
                if status.pendingRequests = 0 AND status.content.Count() = 0 then
                    status.loadStatus = 2
                    m.Listener.OnDataLoaded(index, status.content, 0, status.content.Count(), true)
                end if
            end if
        end for
    end if
End Sub

Sub homeOnFoundConnection(server, success)
    ' Decrement our pending request counts
    m.UpdatePendingRequestsForConnectionTesting(server.owned, false)

    if NOT success then return

    m.CreateServerRequests(server, true)

    ' Nothing else to do for shared servers
    if NOT server.owned then return

    status = m.contentArray[m.RowIndexes["misc"]]
    machineId = tostr(server.machineID)
    if NOT server.IsSecondary AND NOT status.loadedServers.DoesExist(machineID) then
        status.loadedServers[machineID] = "1"
        channelDir = CreateObject("roAssociativeArray")
        channelDir.server = server
        channelDir.sourceUrl = ""
        channelDir.key = "/system/appstore"
        channelDir.Title = "Channel Directory"
        if AreMultipleValidatedServers() then
            channelDir.ShortDescriptionLine2 = "Browse channels to install on " + server.name
        else
            channelDir.ShortDescriptionLine2 = "Browse channels to install"
        end if
        channelDir.Description = channelDir.ShortDescriptionLine2
        channelDir.SDPosterURL = "file://pkg:/images/more.png"
        channelDir.HDPosterURL = "file://pkg:/images/more.png"
        status.content.Push(channelDir)
    end if

    if m.FirstServer then
        m.FirstServer = false

        if m.LoadingFacade <> invalid then
            m.LoadingFacade.Close()
            m.LoadingFacade = invalid
            m.GdmTimer.Active = false
            m.GdmTimer = invalid
        end if

        ' Add universal search now that we have a server
        univSearch = CreateObject("roAssociativeArray")
        univSearch.sourceUrl = ""
        univSearch.ContentType = "search"
        univSearch.Key = "globalsearch"
        univSearch.Title = "Search"
        univSearch.Description = "Search for items across all your sections and channels"
        univSearch.ShortDescriptionLine2 = univSearch.Description
        univSearch.SDPosterURL = "file://pkg:/images/search.png"
        univSearch.HDPosterURL = "file://pkg:/images/search.png"
        status.content.Unshift(univSearch)
        m.Listener.OnDataLoaded(m.RowIndexes["misc"], status.content, 0, status.content.Count(), true)
    else
        m.Listener.OnDataLoaded(m.RowIndexes["misc"], status.content, status.content.Count() - 1, 1, true)
    end if
End Sub

Sub homeUpdatePendingRequestsForConnectionTesting(owned, increment)
    if increment then
        delta = 1
    else
        delta = -1
    end if

    if owned then
        row_keys = ["channels", "sections", "on_deck", "recently_added"]
    else
        row_keys = ["shared_sections"]
    end if

    timer = invalid

    for each row_key in row_keys
        row = m.RowIndexes[row_key]
        if row >= 0 then
            status = m.contentArray[row]
            status.pendingRequests = status.pendingRequests + delta
            if status.pendingRequests = 0 AND timer = invalid then
                timer = createTimer()
                timer.Name = "HideServerRows"
                timer.SetDuration(250)
                timer.Active = true
            end if
        end if
    end for

    if timer <> invalid then
        GetViewController().AddTimer(timer, m)
    end if
End Sub
