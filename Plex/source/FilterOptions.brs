Function createFilterOptions(section)
    obj = CreateObject("roAssociativeArray")

    obj.Section = section

    if m.MetadataTypesBySectionType = invalid then
        m.MetadataTypesBySectionType = {}
        m.MetadataTypesBySectionType["movie"] = [{title: "Movie", EnumValue: "1", gridStyle: "portrait"}]
        m.MetadataTypesBySectionType["show"] = [{title: "Show", EnumValue: "2", gridStyle: "portrait"}, {title: "Episode", EnumValue: "4", gridStyle: "portrait"}]
        m.MetadataTypesBySectionType["artist"] = [{title: "Artist", EnumValue: "8", gridStyle: "square"}, {title: "Album", EnumValue: "9", gridStyle: "square"}]
        m.MetadataTypesBySectionType["photo"] = [{title: "Photo", EnumValue: "13", gridStyle: "square"}]
    end if

    obj.types = firstOf(m.MetadataTypesBySectionType[section.type], [])
    obj.currentTypeIndex = 0

    obj.filtersArr = invalid
    obj.currentFilters = {}

    obj.sortsArr = invalid
    obj.currentSorts = {}

    obj.GetTypes = foGetTypes
    obj.GetSelectedType = foGetSelectedType
    obj.SetSelectedType = foSetSelectedType

    obj.InitFilters = foInitFilters
    obj.GetFilters = foGetFilters
    obj.GetFiltersLabel = foGetFiltersLabel
    obj.GetCurrentFilters = foGetCurrentFilters
    obj.SetFilter = foSetFilter

    obj.InitSorts = foInitSorts
    obj.GetSorts = foGetSorts
    obj.GetSortsLabel = foGetSortsLabel
    obj.GetCurrentSorts = foGetCurrentSorts
    obj.SetSort = foSetSort

    obj.Reset = foReset
    obj.GetUrl = foGetUrl

    obj.FetchValues = foFetchValues
    obj.FetchFilterValues = foFetchFilterValues
    obj.OnUrlEvent = foOnUrlEvent
    obj.IsInitialized = foIsInitialized
    obj.InitializeOptionsFromString = foInitializeOptionsFromString
    obj.IsActive = foIsActive

    obj.cacheKey = tostr(section.server.machineID) + "!" + tostr(section.key)

    ' Look for previous filter values for this section
    if RegRead("remember_last_filter", "preferences", "1") = "1" then
        obj.InitializeOptionsFromString(RegRead(obj.cacheKey + "!type", "filters"), RegRead(obj.cacheKey + "!sort", "filters"), RegRead(obj.cacheKey + "!filters", "filters"))
    end if

    return obj
End Function

Sub foInitializeOptionsFromString(typeStr, sortStr, filtersStr)
    if typeStr <> invalid then
        for i = 0 to m.types.Count() - 1
            if m.types[i].EnumValue = typeStr then
                m.currentTypeIndex = i
                exit for
            end if
        end for
    end if

    if sortStr <> invalid then
        av = sortStr.tokenize(":")
        if av.count() = 2 then
            m.SetSort(av.GetHead(), (av.GetTail() = "asc"))
        end if
    end if

    if filtersStr <> invalid then
        args = filtersStr.tokenize("&")
        for each arg in args
            av = arg.tokenize("=")
            key = UrlUnescape(av.GetHead())
            serializedValues = av.GetTail().tokenize(",")
            values = []
            for each serializedVal in serializedValues
                av = serializedVal.tokenize("!")
                values.Push({key: av.GetHead(), title: UrlUnescape(av.GetTail())})
            end for
            m.SetFilter(key, values)
        end for
    end if
End Sub

Sub foFetchValues(screen)
    m.filtersArr = invalid
    m.sortsArr = invalid

    ' Associate the requests with the screen's ID, so that any pending requests
    ' are canceled when the screen is popped.
    m.ScreenID = screen.ScreenID
    m.WaitingScreen = screen

    sourceUrl = FullUrl(m.Section.server.serverUrl, m.Section.sourceUrl, m.Section.key)

    httpRequest = m.Section.server.CreateRequest(sourceUrl, "filters?type=" + m.GetSelectedType().EnumValue)
    context = CreateObject("roAssociativeArray")
    context.requestType = "filters"
    GetViewController().StartRequest(httpRequest, m, context)

    httpRequest = m.Section.server.CreateRequest(sourceUrl, "sorts?type=" + m.GetSelectedType().EnumValue)
    context = CreateObject("roAssociativeArray")
    context.requestType = "sorts"
    GetViewController().StartRequest(httpRequest, m, context)
End Sub

Sub foFetchFilterValues(filter, screen)
    ' Associate the requests with the screen's ID, so that any pending requests
    ' are canceled when the screen is popped.
    m.ScreenID = screen.ScreenID
    m.WaitingScreen = screen

    httpRequest = m.Section.server.CreateRequest("", filter.url + "?type=" + m.GetSelectedType().EnumValue)
    context = CreateObject("roAssociativeArray")
    context.requestType = "filter"
    context.filter = filter
    GetViewController().StartRequest(httpRequest, m, context)
End Sub

Sub foOnUrlEvent(msg, requestContext)
    url = requestContext.Request.GetURL()

    if msg.GetResponseCode() <> 200 then
        Debug("Got a " + tostr(msg.GetResponseCode()) + " response from " + tostr(url) + " - " + tostr(msg.GetFailureReason()))
        ' TODO(schuyler): Show some sort of dialog and handle this
        return
    end if

    xml = CreateObject("roXMLElement")
    xml.Parse(msg.GetString())

    if requestContext.requestType = "filters" then
        nodes = xml.GetChildElements()
        filters = []
        for each node in nodes
            filter = {}
            filter.key = firstOf(node@filter, "")
            filter.filterType = firstOf(node@filterType, "string")
            filter.url = node@key
            filter.title = firstOf(node@title, "")

            if filter.filterType = "boolean" then
                filter.values = [{key: "1", title: "On"}, {key: "", title: "Off"}]
            end if

            filters.Push(filter)
        end for

        m.InitFilters(filters)
    else if requestContext.requestType = "sorts" then
        nodes = xml.GetChildElements()
        sorts = []
        for each node in nodes
            sort = {}
            sort.key = firstOf(node@key, "")
            sort.title = firstOf(node@title, "")
            sort.defaultDir = node@default
            sorts.Push(sort)
        end for

        m.InitSorts(sorts)
    else if requestContext.requestType = "filter" then
        nodes = xml.GetChildElements()
        values = []
        for each node in nodes
            value = {}
            value.key = firstOf(node@key, "")
            value.title = firstOf(node@title, "")
            values.Push(value)
        end for

        requestContext.filter.values = values
    end if

    if m.IsInitialized() AND m.WaitingScreen <> invalid then
        m.WaitingScreen.Show()
        m.WaitingScreen = invalid
    end if
End Sub

Function foIsInitialized() As Boolean
    return (m.filtersArr <> invalid AND m.sortsArr <> invalid)
End Function

Sub foInitFilters(filtersArr)
    m.filtersArr = filtersArr
    m.filtersHash = {}
    for each filter in m.filtersArr
        m.filtersHash[filter.key] = filter
    end for
End Sub

Sub foInitSorts(sortsArr)
    m.sortsArr = sortsArr
    m.sortsHash = {}
    for each sort in m.sortsArr
        m.sortsHash[sort.key] = sort
    end for
End Sub

Function foGetTypes()
    return m.types
End Function

Function foGetSelectedType()
    return m.types[m.currentTypeIndex]
End Function

Function foSetSelectedType(selectedIndex)
    if m.currentTypeIndex <> selectedIndex then
        m.currentTypeIndex = selectedIndex
        m.currentFilters.Clear()
        m.currentSorts.Clear()
        return true
    else
        return false
    end if
End Function

Function foGetFilters()
    return m.filtersArr
End Function

Function foGetFiltersLabel()
    label = ""
    first = true

    for each key in m.currentFilters
        if first then
            first = false
        else
            label = label + ", "
        end if
        obj = m.filtersHash[key]
        label = label + firstOf(obj.OrigTitle, obj.Title)
    end for

    if label = "" then label = "None"
    return label
End Function

Function foGetCurrentFilters()
    return m.currentFilters
End Function

Sub foSetFilter(key, values)
    if values = invalid OR values.Count() = 0 then
        m.currentFilters.Delete(key)
    else
        m.currentFilters[key] = values
    end if
End Sub

Function foGetSorts()
    return m.sortsArr
End Function

Function foGetSortsLabel()
    label = ""
    first = true

    for each key in m.currentSorts
        if first then
            first = false
        else
            label = label + ", "
        end if
        obj = m.sortsHash[key]
        label = label + firstOf(obj.OrigTitle, obj.Title)
    end for

    if label = "" then label = "Default"
    return label
End Function

Function foGetCurrentSorts()
    return m.currentSorts
End Function

Sub foSetSort(key, ascending)
    m.currentSorts.Clear()
    m.currentSorts[key] = ascending
End Sub

Sub foReset()
    m.currentTypeIndex = 0
    m.currentFilters.Clear()
    m.currentSorts.Clear()
    if RegRead("remember_last_filter", "preferences", "1") = "1" then
        RegDelete(m.cacheKey + "!sort", "filters")
        RegDelete(m.cacheKey + "!filters", "filters")
        RegDelete(m.cacheKey + "!type", "filters")
    end if
End Sub

Function foGetUrl()
    if NOT m.IsActive() then return invalid

    builder = NewHttp("all")

    ' Always add type, nice and easy
    builder.AddParam("type", m.GetSelectedType().EnumValue)

    ' For filters, we need to create the query string as well as a special
    ' value that will be written to the registry to remember the current filters.
    ' The latter requires both the key and title.
    filterRegArr = []
    for each key in m.currentFilters
        builder.AddParam(key, JoinArray(m.currentFilters[key], ",", "key"))

        titleAndVals = []
        for each obj in m.currentFilters[key]
            titleAndVals.Push(obj.key + "!" + HttpEncode(firstOf(obj.OrigTitle, obj.Title)))
        end for
        filterRegArr.Push(key + "=" + JoinArray(titleAndVals, ","))
    end for
    filterRegString = JoinArray(filterRegArr, "&")

    ' Add the sort key and direction if we have one.
    sortParam = invalid
    for each key in m.currentSorts
        if m.currentSorts[key] then
            sortParam = key + ":asc"
        else
            sortParam = key + ":desc"
        end if
    end for
    if sortParam <> invalid then builder.AddParam("sort", sortParam)

    ' Write the filters for this section to the registry for next time
    if RegRead("remember_last_filter", "preferences", "1") = "1" then
        RegWrite(m.cacheKey + "!type", m.GetSelectedType().EnumValue, "filters")

        if sortParam <> invalid then
            RegWrite(m.cacheKey + "!sort", sortParam, "filters")
        else
            RegDelete(m.cacheKey + "!sort", "filters")
        end if

        if filterRegString <> "" then
            RegWrite(m.cacheKey + "!filters", filterRegString, "filters")
        else
            RegDelete(m.cacheKey + "!filters", "filters")
        end if
    end if

    return builder.Http.GetUrl()
End Function

Function foIsActive()
    ' Reset the cursor in the hashes so we can see if they're empty. I know.
    m.currentFilters.Reset()
    m.currentSorts.Reset()

    isSortSet = m.currentSorts.IsNext()
    if isSortSet AND m.sortsHash <> invalid then
        sortKey = m.currentSorts.Next()
        sort = m.sortsHash[sortKey]
        if sort <> invalid AND sort.defaultDir <> invalid then
            isSortSet = ((sort.defaultDir = "asc") <> m.currentSorts[sortKey])
        else
            isSortSet = true
        end if
    end if

    return (m.currentTypeIndex <> 0 OR m.currentFilters.IsNext() OR isSortSet)
End Function
