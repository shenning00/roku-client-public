'* Displays the content in a poster screen. Can be any content type.

Function createPosterScreen(item, viewController) As Object
    obj = CreateObject("roAssociativeArray")
    initBaseScreen(obj, viewController)

    screen = CreateObject("roPosterScreen")
    screen.SetMessagePort(obj.Port)

    ' Standard properties for all our screen types
    obj.Item = item
    obj.Screen = screen

    obj.Show = showPosterScreen
    obj.ShowList = posterShowContentList
    obj.HandleMessage = posterHandleMessage
    obj.SetListStyle = posterSetListStyle
    obj.Activate = posterActivate

    obj.UseDefaultStyles = true
    obj.ListStyle = invalid
    obj.ListDisplayMode = invalid
    obj.FilterMode = invalid
    obj.Facade = invalid

    obj.OnDataLoaded = posterOnDataLoaded
    obj.GetBlankThumbUrl = posterGetBlankThumbUrl

    obj.contentArray = []
    obj.focusedList = 0
    obj.names = []
    obj.rowVisibility = invalid

    if item.theme <> invalid AND NOT AudioPlayer().IsPlaying AND RegRead("theme_music", "preferences", "loop") <> "disabled" then
        AudioPlayer().PlayThemeMusic(item)
        obj.Cleanup = baseStopAudioPlayer
    end if

    return obj
End Function

Function showPosterScreen() As Integer
    ' Show a facade immediately to get the background 'retrieving' instead of
    ' using a one line dialog.
    m.Facade = CreateObject("roPosterScreen")
    m.Facade.Show()

    content = m.Item
    server = content.server

    container = createPlexContainerForUrl(server, content.sourceUrl, content.key)

    if container.IsError then
        dialog = createBaseDialog()
        dialog.Title = "Content Unavailable"
        dialog.Text = "An error occurred while trying to load this content, make sure the server is running."
        dialog.Facade = m.Facade
        dialog.Show()
        m.closeOnActivate = true
        m.Facade = invalid
        return 0
    end if

    if m.FilterMode = invalid then m.FilterMode = container.ViewGroup = "secondary"
    if m.FilterMode then
        m.names = container.GetNames()
        keys = container.GetKeys()
    else
        m.names = []
        keys = []
    end if

    m.FilterMode = m.names.Count() > 0

    if m.FilterMode then
        m.Loader = createPaginatedLoader(container, 25, 25)
        m.Loader.Listener = m

        m.Screen.SetListNames(m.names)
        m.Screen.SetFocusedList(0)

        for index = 0 to keys.Count() - 1
            status = CreateObject("roAssociativeArray")
            status.listStyle = invalid
            status.listDisplayMode = invalid
            status.focusedIndex = 0
            status.content = []
            status.lastUpdatedSize = 0
            m.contentArray[index] = status
        next

        m.Loader.LoadMoreContent(0, 0)
    else
        ' We already grabbed the full list, no need to bother with loading
        ' in chunks.

        status = CreateObject("roAssociativeArray")
        status.content = container.GetMetadata()

        m.Loader = createDummyLoader()

        if container.Count() > 0 then
            contentType = container.GetMetadata()[0].ContentType
        else
            contentType = invalid
        end if

        if m.UseDefaultStyles then
            aa = getDefaultListStyle(container.ViewGroup, contentType)
            status.listStyle = aa.style
            status.listDisplayMode = aa.display
        else
            status.listStyle = m.ListStyle
            status.listDisplayMode = m.ListDisplayMode
        end if

        status.focusedIndex = 0
        status.lastUpdatedSize = status.content.Count()

        m.contentArray[0] = status
    end if

    m.DialogShown = (container.DialogShown = true)

    m.focusedList = 0
    m.ShowList(0)
    if m.Facade <> invalid then m.Facade.Close()

    return 0
End Function

Function posterHandleMessage(msg) As Boolean
    handled = false

    if type(msg) = "roPosterScreenEvent" then
        handled = true

        '* Focus change on the filter bar causes content change
        if msg.isListFocused() then
            m.focusedList = msg.GetIndex()
            m.ShowList(m.focusedList)
            m.Loader.LoadMoreContent(m.focusedList, 0)
        else if msg.isListItemSelected() then
            index = msg.GetIndex()

            selected = invalid
            if m.contentArray[m.focusedList] <> invalid and m.contentArray[m.focusedList].content <> invalid then 
                content = m.contentArray[m.focusedList].content
                selected = content[index]
            end if

            if selected <> invalid then
                contentType = selected.ContentType

                Debug("Content type in poster screen: " + tostr(contentType))

                if contentType = "series" OR NOT m.FilterMode then
                    breadcrumbs = [selected.Title]
                else
                    breadcrumbs = [m.names[m.focusedList], selected.Title]
                end if

                m.ViewController.CreateScreenForItem(content, index, breadcrumbs)
            end if
        else if msg.isScreenClosed() then
            m.ViewController.PopScreen(m)
        else if msg.isListItemFocused() then
            ' We don't immediately update the screen's content list when
            ' we get more data because the poster screen doesn't perform
            ' as well as the grid screen (which has an actual method for
            ' refreshing part of the list). Instead, if the user has
            ' focused toward the end of the list, update the content.

            status = m.contentArray[m.focusedList]
            if status <> invalid then status.focusedIndex = msg.GetIndex()

            if status <> invalid and status.focusedIndex + 10 > status.lastUpdatedSize AND status.content.Count() > status.lastUpdatedSize then
                m.Screen.SetContentList(status.content)
                status.lastUpdatedSize = status.content.Count()
            end if
        else if msg.isRemoteKeyPressed() then
            if msg.GetIndex() = 13 then
                Debug("Playing item directly from poster screen")
                status = m.contentArray[m.focusedList]
                m.ViewController.CreatePlayerForItem(status.content, status.focusedIndex)
            end if
        end if
    end If

    return handled
End Function

Sub posterOnDataLoaded(row As Integer, data As Object, startItem as Integer, count As Integer, finished As Boolean)
    status = m.contentArray[row]
    status.content = data

    ' If this was the first content we loaded, set up the styles
    if startItem = 0 AND count > 0 then
        if m.UseDefaultStyles then
            if data.Count() > 0 then
                aa = getDefaultListStyle(data[0].ViewGroup, data[0].contentType)
                status.listStyle = aa.style
                status.listDisplayMode = aa.display
            end if
        else
            status.listStyle = m.ListStyle
            status.listDisplayMode = m.ListDisplayMode
        end if
    end if

    if row = m.focusedList AND (finished OR startItem = 0 OR status.focusedIndex + 10 > status.lastUpdatedSize) then
        if m.ViewController.IsActiveScreen(m) then
            m.ShowList(row)
            status.lastUpdatedSize = startItem + count
        else
            status.lastUpdatedSize = 0
        end if
    end if

    ' Continue loading this row
    m.Loader.LoadMoreContent(row, 0)
End Sub

Sub posterActivate(priorScreen)
    if m.ignoreOnActivate = true then
        m.ignoreOnActivate = false
        return
    else if m.popOnActivate then
        m.ViewController.PopScreen(m)
        return
    else if m.closeOnActivate then
        if m.Screen <> invalid then
            m.Screen.Close()
        else
            m.ViewController.PopScreen(m)
        end if
        return
    end if

    status = m.contentArray[m.focusedList]
    if status = invalid or status.lastUpdatedSize = invalid or status.content = invalid then return

    'SAH - still need some work here for 'shuffle'
    if status.lastUpdatedSize <> status.content.Count() or status.forcusedIndex <> priorScreen.CurIndex then
        status.focusedIndex = priorScreen.CurIndex
        m.ShowList(m.focusedList)
        status.lastUpdatedSize = status.content.Count()
    end if
End Sub

Sub posterShowContentList(index)
    status = m.contentArray[index]
    if status = invalid then return
    m.Screen.SetContentList(status.content)

    if status.listStyle <> invalid then
        m.Screen.SetListStyle(status.listStyle)
    end if
    if status.listDisplayMode <> invalid then
        m.Screen.SetListDisplayMode(status.listDisplayMode)
    end if

    ' Check the load status on a filtered row. If it's empty, we whould show an
    ' empty placeholder to remove the "retrieving" screen.
    if m.FilterMode and status.content.count() = 0 and status.lastUpdatedSize = 0 AND m.Loader.GetLoadStatus(m.focusedList) = 2 then
        posterUrl = m.getBlankThumbUrl()
        placeholder = CreateObject("roAssociativeArray")
        placeholder.Key = invalid
        placeholder.SDPosterUrl = posterUrl
        placeholder.HDPosterUrl = posterUrl
        placeholder.shortdescriptionline1 = "Empty"
        m.Screen.SetContentList([placeholder])
    end if

    Debug("Showing screen with " + tostr(status.content.Count()) + " elements")
    Debug("List style is " + tostr(status.listStyle) + ", " + tostr(status.listDisplayMode))

    if status.content.Count() = 0 AND NOT m.FilterMode then
        if m.DialogShown then
            m.Screen.Show()
            m.Facade.Close()
            m.Facade = invalid
            m.Screen.Close()
        else
            dialog = createBaseDialog()
            dialog.Facade = m.Facade
            dialog.Title = "No items to display"
            dialog.Text = "This directory appears to be empty."
            dialog.Show()
            m.Facade = invalid
            m.closeOnActivate = true
        end if
    else
        m.Screen.Show()
        m.Screen.SetFocusedListItem(status.focusedIndex)
    end if
End Sub

Function getDefaultListStyle(viewGroup, contentType) As Object
    aa = CreateObject("roAssociativeArray")
    aa.style = "arced-square"
    aa.display = "scale-to-fit"

    if viewGroup = "episode" AND contentType = "episode" then
        aa.style = "flat-episodic"
        aa.display = "zoom-to-fill"
    else if viewGroup = "movie" OR viewGroup = "show" OR viewGroup = "season" OR viewGroup = "episode" then
        aa.style = "arced-portrait"
    end if

    return aa
End Function

Sub posterSetListStyle(style, displayMode)
    m.ListStyle = style
    m.ListDisplayMode = displayMode
    m.UseDefaultStyles = false
End Sub

Sub posterGetBlankThumbUrl() as String

    blankStyle = "square" ' default is square
    if NOT(m.UseDefaultStyles = true) then
        if m.ListStyle = "flat-episodic" then
            blankStyle = "landscape"
        else if m.ListStyle = "arced-portrait" then
            blankStyle = "portrait"
        end if
    end if
    thumbUrl = "file://pkg:/images/BlankPoster_" + blankStyle + ".png"

    return thumbUrl
End Sub
