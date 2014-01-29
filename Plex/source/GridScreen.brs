'*
'* A grid screen backed by XML from a PMS.
'*

Function createGridScreen(viewController) As Object
    Debug("######## Creating Grid Screen ########")

    screen = CreateObject("roAssociativeArray")

    initBaseScreen(screen, viewController)

    grid = CreateObject("roGridScreen")
    grid.SetMessagePort(screen.Port)

    grid.SetDisplayMode("photo-fit")
    grid.SetGridStyle("mixed-aspect-ratio")

    ' Standard properties for all our Screen types
    screen.Screen = grid
    screen.DestroyAndRecreate = gridDestroyAndRecreate
    screen.Show = showGridScreen
    screen.HandleMessage = gridHandleMessage
    screen.Activate = gridActivate
    screen.OnTimerExpired = gridOnTimerExpired

    screen.timer = createTimer()
    screen.selectedRow = 0
    screen.focusedIndex = 0
    screen.contentArray = []
    screen.lastUpdatedSize = []
    screen.rowVisibility = []
    screen.hasData = false
    screen.hasBeenFocused = false
    screen.ignoreNextFocus = false
    screen.recreating = false
    screen.filtered = false
    screen.ignoreRowNameForBreadcrumbs = false

    screen.OnDataLoaded = gridOnDataLoaded
    screen.InitializeRows = gridInitializeRows
    screen.SetVisibility = gridSetVisibility
    screen.SetFocusedItem = gridSetFocusedItem

    return screen
End Function

'* Convenience method to create a grid screen with a loader for the specified item
Function createGridScreenForItem(item, viewController, style="square") As Object
    obj = createGridScreen(viewController)

    obj.Item = item

    if RegRead("enable_filtered_browsing", "preferences", "1") = "1" AND NOT (item.ContentType = "section" AND item.Filters = invalid) then
        if GetGlobal("IsHD") then
            rowSize = 5
        else
            rowSize = 4
        end if

        obj.Loader = createChunkedLoader(item, rowSize)
        obj.Loader.Listener = obj
        obj.filtered = (item.Filters = "1")
        obj.ignoreRowNameForBreadcrumbs = true
    else
        container = createPlexContainerForUrl(item.server, item.sourceUrl, item.key)
        container.SeparateSearchItems = true
        obj.Loader = createPaginatedLoader(container, 8, 75)
        obj.Loader.styles = [style]
        obj.Loader.Listener = obj
    end if

    ' Don't play theme music on top of grid screens on the older Roku models.
    ' It's not worth the DestroyAndRecreate headache.
    if item.theme <> invalid AND GetGlobal("rokuVersionArr", [0])[0] >= 4 AND NOT AudioPlayer().IsPlaying AND RegRead("theme_music", "preferences", "loop") <> "disabled" then
        AudioPlayer().PlayThemeMusic(item)
        obj.Cleanup = baseStopAudioPlayer
    end if

    return obj
End Function

Function gridInitializeRows(clear=true)
    names = m.Loader.GetNames()
    styles = m.Loader.GetRowStyles()
    if clear then m.contentArray.Clear()

    if names.Count() = 0 then
        Debug("Nothing to load for grid")
        dialog = createBaseDialog()
        dialog.Facade = m.Facade
        dialog.Title = "Section Empty"
        dialog.Text = "This section doesn't contain any items."
        dialog.Show()

        m.popOnActivate = true
        return false
    end if

    lastStyle = "square"
    rowStyles = []
    for i = 0 to names.Count() - 1
        if i < styles.Count() then lastStyle = styles[i]
        rowStyles.Push(lastStyle)
    end for

    m.Screen.SetupLists(names.Count())
    m.Screen.SetListNames(names)
    m.Screen.SetListPosterStyles(rowStyles)
    m.rowStyles = rowStyles
    m.rowVisibility = []

    ' If we already "loaded" an empty row, we need to set the list visibility now
    ' that we've setup the lists.
    for row = 0 to names.Count() - 1
        m.rowVisibility[row] = true
        if m.contentArray[row] = invalid then m.contentArray[row] = []
        m.lastUpdatedSize[row] = m.contentArray[row].Count()
        m.Screen.SetContentList(row, m.contentArray[row])
        if m.lastUpdatedSize[row] = 0 AND m.Loader.GetLoadStatus(row) = 2 then
            Debug("Hiding row " + tostr(row) + " in InitializeRows")
            m.SetVisibility(row, false)
        end if
    end for

    if m.filtered AND RegRead("filter_help_shown", "misc") <> invalid then
        m.SetFocusedItem(1, 0)
    end if

    return true
End Function

Function showGridScreen() As Integer
    m.Facade = CreateObject("roGridScreen")
    m.Facade.Show()

    totalTimer = createTimer()

    if NOT m.InitializeRows() then return -1

    m.Screen.Show()
    m.Facade.Close()
    m.Facade = invalid

    ' Only two rows and five items per row are visible on the screen, so
    ' don't load much more than we need to before initially showing the
    ' grid. Once we start the event loop we can load the rest of the
    ' content.

    maxRow = m.contentArray.Count() - 1
    if maxRow > 1 then maxRow = 1

    for row = 0 to maxRow
        Debug("Loading beginning of row " + tostr(row))
        m.Loader.LoadMoreContent(row, 0)
    end for

    totalTimer.PrintElapsedTime("Total initial grid load")

    if m.filtered AND RegRead("filter_help_shown", "misc") = invalid then
        m.ignoreOnActivate = true
        m.ViewController.ShowFilterHelp()
    end if

    return 0
End Function

Function gridHandleMessage(msg) As Boolean
    handled = false

    if type(msg) = "roGridScreenEvent" then
        handled = true
        if msg.isListItemSelected() then
            arr = m.Loader.GetContextAndIndexForItem(msg.GetIndex(), msg.GetData())
            if arr = invalid then
                context = m.contentArray[msg.GetIndex()]
                index = msg.GetData()
            else
                context = arr[0]
                index = arr[1]
            end if

            item = context[index]
            if item <> invalid then
                if item.ContentType = "series" OR m.ignoreRowNameForBreadcrumbs then
                    breadcrumbs = [item.Title]
                else if item.ContentType = "section" then
                    breadcrumbs = [item.server.name, item.Title]
                else
                    breadcrumbs = [m.Loader.GetNames()[msg.GetIndex()], item.Title]
                end if

                m.Facade = CreateObject("roGridScreen")
                m.Facade.Show()

                m.ViewController.CreateScreenForItem(context, index, breadcrumbs)
            end if
        else if msg.isListItemFocused() then
            ' If the user is getting close to the limit of what we've
            ' preloaded, make sure we kick off another update.

            ' Sanity check the focused coordinates, Roku loves to send bogus values
            if msg.GetIndex() < 0 OR msg.GetIndex() >= m.contentArray.Count() then
                Debug("Ignoring grid ListItemFocused event for bogus row: " + tostr(msg.GetIndex()))
            else
                m.Screen.SetDescriptionVisible(true)
                m.selectedRow = msg.GetIndex()
                m.focusedIndex = msg.GetData()

                if m.ignoreNextFocus then
                    m.ignoreNextFocus = false
                else
                    m.hasBeenFocused = true
                end if

                lastUpdatedSize = m.lastUpdatedSize[m.selectedRow]
                if m.focusedIndex + 10 > lastUpdatedSize AND m.contentArray[m.selectedRow].Count() > lastUpdatedSize then
                    data = m.contentArray[m.selectedRow]
                    m.Screen.SetContentListSubset(m.selectedRow, data, lastUpdatedSize, data.Count() - lastUpdatedSize)
                    m.lastUpdatedSize[m.selectedRow] = data.Count()
                end if

                m.Loader.LoadMoreContent(m.selectedRow, 2)
            end if
        else if msg.isRemoteKeyPressed() then
            if msg.GetIndex() = 13 then
                Debug("Playing item directly from grid")
                context = m.contentArray[m.selectedRow]
                m.ViewController.CreatePlayerForItem(context, m.focusedIndex)
            end if
        else if msg.isScreenClosed() then
            if m.recreating then
                Debug("Ignoring grid screen close, we should be recreating")
                m.recreating = false
            else
                m.ViewController.PopScreen(m)
            end if
        end if
    end if

    return handled
End Function

Sub gridOnDataLoaded(row As Integer, data As Object, startItem As Integer, count As Integer, finished As Boolean)
    Debug("Loaded " + tostr(count) + " elements in row " + tostr(row) + ", now have " + tostr(data.Count()))

    m.contentArray[row] = data

    ' Don't bother showing empty rows
    if data.Count() = 0 then
        if m.Screen <> invalid AND m.Loader.GetLoadStatus(row) = 2 then
            ' CAUTION: This cannot be safely undone on a mixed-aspect-ratio grid!
            Debug("Hiding row " + tostr(row) + " in OnDataLoaded")
            m.SetVisibility(row, false)
            m.Screen.SetContentList(row, data)
        end if

        if NOT m.hasData then
            pendingRows = (m.Loader.GetPendingRequestCount() > 0)

            if NOT pendingRows then
                for i = 0 to m.contentArray.Count() - 1
                    if m.Loader.GetLoadStatus(i) < 2 then
                        pendingRows = true
                        exit for
                    end if
                next
            end if

            if NOT pendingRows then
                Debug("Nothing in any grid rows")

                ' If there's no data, show a helpful dialog. But if there's no
                ' data on a refresh, it's a bit of a mess. The dialog is only
                ' marginally helpful, and there's some sort of race condition
                ' with the fact that we reset the content list for the current
                ' row when the screen came back. That can hang the app for
                ' non-obvious reasons. Even without showing the dialog, closing
                ' the screen has a bit of an ugly flash.

                if m.Refreshing <> true then
                    dialog = createBaseDialog()
                    dialog.Title = "Section Empty"
                    dialog.Text = "This section doesn't contain any items."
                    dialog.Show()
                    m.closeOnActivate = true
                else
                    m.Screen.Close()
                end if

                return
            end if
        end if

        ' Load the next row though. This is particularly important if all of
        ' the initial rows are empty, we need to keep loading until we find a
        ' row with data.
        if row < m.contentArray.Count() - 1 then
            m.Loader.LoadMoreContent(row + 1, 0)
        end if

        return
    else if count > 0 AND m.Screen <> invalid then
        ' CAUTION: Making a previously hidden row visible on a
        ' mixed-aspect-ratio grid has been known to crash some (beta) firmware
        ' versions.
        m.SetVisibility(row, true)
    end if

    ' Update thumbs according to the row style they were loaded in
    for i = startItem to startItem + count - 1
        item = data[i]
        if item.ThumbProcessed <> invalid AND item.ThumbProcessed <> m.rowStyles[row] then
            item.ThumbProcessed = m.rowStyles[row]
            if item.ThumbUrl <> invalid AND item.server <> invalid then
                sizes = ImageSizesGrid(m.rowStyles[row])
                item.SDPosterURL = item.server.TranscodedImage(item.sourceUrl, item.ThumbUrl, sizes.sdWidth, sizes.sdHeight)
                item.HDPosterURL = item.server.TranscodedImage(item.sourceUrl, item.ThumbUrl, sizes.hdWidth, sizes.hdHeight)
            else if item.ThumbUrl = invalid
                item.SDPosterURL = "file://pkg:/images/BlankPoster_" + m.rowStyles[row] + ".png"
                item.HDPosterURL = "file://pkg:/images/BlankPoster_" + m.rowStyles[row] + ".png"
            end if
        end if
    end for

    m.hasData = true

    ' It seems like you should be able to do this, but you have to pass in
    ' the full content list, not some other array you want to use to update
    ' the content list.
    ' m.Screen.SetContentListSubset(rowIndex, content, startItem, content.Count())

    lastUpdatedSize = m.lastUpdatedSize[row]

    if finished then
        if m.Screen <> invalid then m.Screen.SetContentList(row, data)
        m.lastUpdatedSize[row] = data.Count()
    else if startItem < lastUpdatedSize then
        if m.Screen <> invalid then m.Screen.SetContentListSubset(row, data, startItem, count)
        m.lastUpdatedSize[row] = data.Count()
    else if startItem = 0 OR (m.selectedRow = row AND m.focusedIndex + 10 > lastUpdatedSize) then
        if m.Screen <> invalid then m.Screen.SetContentListSubset(row, data, lastUpdatedSize, data.Count() - lastUpdatedSize)
        m.lastUpdatedSize[row] = data.Count()
    end if

    ' Continue loading this row
    extraRows = 2 - (m.selectedRow - row)
    if extraRows >= 0 AND extraRows <= 2 then
        m.Loader.LoadMoreContent(row, extraRows)
    end if
End Sub

Sub gridDestroyAndRecreate()
    ' Close our current grid and recreate it once we get back.
    ' Works around a weird glitch when certain screens (maybe just
    ' an audio player) are shown on top of grids.
    if m.Screen <> invalid then
        Debug("Destroying grid...")
        m.Screen.Close()
        m.Screen = invalid

        if m.ViewController.IsActiveScreen(m) then
            m.recreating = true

            timer = createTimer()
            timer.Name = "Reactivate"

            ' Pretty arbitrary, but too close to 0 won't work. This is obviously
            ' a hack, but we're working around an acknowledged bug that will
            ' never be fixed, so what can you do.
            timer.SetDuration(1500)

            m.ViewController.AddTimer(timer, m)
        end if
    end if
End Sub

Sub gridActivate(priorScreen)
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

    ' If our screen was destroyed by some child screen, recreate it now
    if m.Screen = invalid then
        Debug("Recreating grid...")
        m.Screen = CreateObject("roGridScreen")
        m.Screen.SetMessagePort(m.Port)
        m.Screen.SetDisplayMode("photo-fit")
        m.Screen.SetGridStyle("mixed-aspect-ratio")

        m.ViewController.UpdateScreenProperties(m)

        m.InitializeRows(false)
        m.SetFocusedItem(m.selectedRow, m.focusedIndex)

        m.Screen.Show()
    else
        ' Regardless, reset the current row in case the currently
        ' selected item had metadata changed that would affect its
        ' display in the grid.
        m.Screen.SetContentList(m.selectedRow, m.contentArray[m.selectedRow])
    end if

    m.HasData = false
    m.Refreshing = true
    m.Loader.RefreshData()

    if m.Facade <> invalid then m.Facade.Close()
End Sub

Sub gridOnTimerExpired(timer)
    if timer.Name = "Reactivate" AND m.ViewController.IsActiveScreen(m) then
        m.Activate(invalid)
    end if
End Sub

Sub gridSetVisibility(row, visible)
    if m.rowVisibility[row] = visible then return
    if visible
        Debug("Desperately wanted to make row " + tostr(row) + " visible, but too afraid to try")
    else
        Debug("Hiding row " + tostr(row))
        m.rowVisibility[row] = visible
        m.Screen.SetListVisible(row, visible)
    end if
End Sub

Sub gridSetFocusedItem(row, col)
    if m.rowVisibility[row] = true then
        Debug("Focusing " + tostr(row) + ", " + tostr(col))
        m.Screen.SetFocusedListItem(row, col)
    else
        Debug("Tried to focus hidden row (" + tostr(row) + "), too afraid to allow it")
    end if
End Sub
