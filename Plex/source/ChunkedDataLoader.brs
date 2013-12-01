'*
'* Loads data from a section in pages, distributing the results across rows of
'* a fixed size.
'*

Function createChunkedLoader(item, rowSize)
    loader = CreateObject("roAssociativeArray")
    initDataLoader(loader)

    loader.server = item.server
    loader.sourceUrl = item.sourceUrl
    loader.key = item.key + "/all"
    loader.rowSize = rowSize

    loader.masterContent = []
    loader.rowContent = []

    loader.LoadMoreContent = chunkedLoadMoreContent
    loader.GetLoadStatus = chunkedGetLoadStatus
    loader.GetPendingRequestCount = chunkedGetPendingRequestCount
    loader.RefreshData = chunkedRefreshData

    loader.StartRequest = chunkedStartRequest
    loader.OnUrlEvent = chunkedOnUrlEvent

    loader.totalSize = 0
    loader.loadedSize = 0
    loader.hasStartedLoading = false

    ' Make a blocking request to figure out the total item count and initialize
    ' our arrays.
    request = loader.server.CreateRequest(loader.sourceUrl, loader.key)
    request.AddHeader("X-Plex-Container-Start", "0")
    request.AddHeader("X-Plex-Container-Size", "0")
    response = GetToStringWithTimeout(request, 60)
    xml = CreateObject("roXMLElement")
    if xml.parse(response) then
        loader.totalSize = firstOf(xml@totalSize, "0").toInt()
    end if

    if loader.totalSize > 0 then
        numRows% = ((loader.totalSize - 1) / rowSize) + 1
        loader.names.Push("Misc")
        loader.rowContent[0] = []

        for i = 0 to numRows% - 1
            loader.names.Push(tostr(i * rowSize + 1) + " - " + tostr((i + 1) * rowSize))
            loader.rowContent[i + 1] = []
        next
    end if

    ' Make a blocking request to load the container in order to populate the
    ' first row with things like On Deck and Search.
    container = createPlexContainerForUrl(item.server, item.sourceUrl, item.key)
    container.SeparateSearchItems = true
    ' TODO(schuyler): Add a dummy item to load filters

    if m.MiscShortcutKeys = invalid then
        m.MiscShortcutKeys = CreateObject("roAssociativeArray")
        m.MiscShortcutKeys["onDeck"] = true
        m.MiscShortcutKeys["folder"] = true
    end if

    for each node in container.GetMetadata()
        if m.MiscShortcutKeys.DoesExist(node.key) then
            loader.rowContent[0].Push(node)
        end if
    next

    loader.rowContent[0].Append(container.GetSearch())

    return loader
End Function

Function chunkedLoadMoreContent(focusedIndex, extraRows=0) As Boolean
    if NOT m.hasStartedLoading then
        m.StartRequest()
        m.hasStartedLoading = true

        if m.Listener <> invalid then
            m.Listener.OnDataLoaded(0, m.rowContent[0], 0, m.rowContent[0].Count(), true)
        end if
    end if

    return true
End Function

Function chunkedGetLoadStatus(row) As Integer
    if m.rowContent[row].Count() > 0 then
        return 2
    else
        return 0
    end if
End Function

Function chunkedGetPendingRequestCount() As Integer
    if m.loadedSize >= m.totalSize then
        return 0
    else
        return 1
    end if
End Function

Sub chunkedRefreshData()
    ' TODO(schuyler)
End Sub

Sub chunkedStartRequest()
    if m.loadedSize >= m.totalSize then return

    ' If we're loading the first row, try to just load the visible content.
    ' Otherwise, load a large chunk.
    if m.loadedSize = 0 then
        chunkSize = m.rowSize * 3
    else
        chunkSize = m.rowSize * 8
    end if

    request = CreateObject("roAssociativeArray")
    httpRequest = m.server.CreateRequest(m.sourceUrl, m.key)
    httpRequest.AddHeader("X-Plex-Container-Start", tostr(m.loadedSize))
    httpRequest.AddHeader("X-Plex-Container-Size", tostr(chunkSize))
    request.offset = m.loadedSize

    ' Associate the request with our listener's screen ID, so that any pending
    ' requests are canceled when the screen is popped.
    m.ScreenID = m.Listener.ScreenID

    GetViewController().StartRequest(httpRequest, m, request)
End Sub

Sub chunkedOnUrlEvent(msg, requestContext)
    url = requestContext.Request.GetURL()

    if msg.GetResponseCode() <> 200 then
        Debug("Got a " + tostr(msg.GetResponseCode()) + " response from " + tostr(url) + " - " + tostr(msg.GetFailureReason()))
        return
    end if

    xml = CreateObject("roXMLElement")
    xml.Parse(msg.GetString())

    response = CreateObject("roAssociativeArray")
    response.xml = xml
    response.server = m.server
    response.sourceUrl = url
    container = createPlexContainerForXml(response)

    if response.xml@totalSize <> invalid then
        totalSize = strtoi(response.xml@totalSize)
    else
        totalSize = container.Count()
    end if

    if totalSize <> m.totalSize then
        Debug("Container's total size no longer matches expected value: " + tostr(totalSize) + " vs. " + tostr(m.totalSize))
    end if

    if totalSize > 0 then
        startItem = firstOf(response.xml@offset, msg.GetResponseHeaders()["X-Plex-Container-Start"], tostr(requestContext.offset)).toInt()
        countLoaded = container.Count()
        Debug("Received paginated response for index " + tostr(startItem) + " of list with length " + tostr(countLoaded))
        items = container.GetMetadata()
        firstRowNum% = (startItem / m.rowSize) + 1
        lastRowNum% = firstRowNum%
        for i = 0 to countLoaded - 1
            m.masterContent[startItem + i] = items[i]
            rowNum% = ((startItem + i) / m.rowSize) + 1
            rowIndex% = (startItem + i) MOD m.rowSize
            m.rowContent[rowNum%][rowIndex%] = items[i]
            lastRowNum% = rowNum%
        next

        m.loadedSize = m.masterContent.Count()
        m.StartRequest()

        if m.Listener <> invalid then
            for i = firstRowNum% to lastRowNum%
                m.Listener.OnDataLoaded(i, m.rowContent[i], 0, m.rowContent[i].Count(), true)
            next
        end if
    end if
End Sub
