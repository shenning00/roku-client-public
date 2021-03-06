'*
'* A grid screen backed by XML from a PMS.
'*

Function createGridScreen(viewController, gridStyle=invalid, nonMixGridStyle=invalid) As Object
    Debug("######## Creating Grid Screen ########")

    screen = CreateObject("roAssociativeArray")

    ' We allow the user to change between a mixed-aspect-grid (left focus) and
    ' other styles in the Advanced settings
    regGridStyle = RegRead("gridStyle", "preferences", "mixed-aspect-ratio")

    ' ignore the style request if "mixed-aspect-ratio" (left focus) is prefered
    if regGridStyle = "mixed-aspect-ratio" then
        gridStyle = regGridStyle
    else
        ' use the reg preference grid style -or- allow an override
        if nonMixGridStyle <> invalid then
            gridStyle = nonMixGridStyle
        else if gridStyle = invalid then
            gridStyle = regGridStyle
        end if

        ' backwards compatibility with mixed-aspect-ratio
        if gridStyle = "landscape" then
            gridStyle = "flat-16x9"
        else if gridStyle = "portrait" then
            gridStyle = "flat-portrait"
        else if gridStyle = "square" then
            gridStyle = "flat-square"
        end if

        ' update the focus border styles
        setGridTheme(gridStyle)
    end if

    ' allow us to hide rows if one doesn't choose a mixed-aspect-ration grid
    screen.isMixedAspect = (gridStyle = "mixed-aspect-ratio")

    initBaseScreen(screen, viewController)

    grid = CreateObject("roGridScreen")
    grid.SetMessagePort(screen.Port)

    grid.SetDisplayMode("photo-fit")
    grid.SetGridStyle(gridStyle)

    ' Required for remotes without a back button
    grid.SetUpBehaviorAtTopRow("exit")

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
    screen.ignoreRowNameForBreadcrumbs = false

    screen.OnDataLoaded = gridOnDataLoaded
    screen.InitializeRows = gridInitializeRows
    screen.SetVisibility = gridSetVisibility
    screen.SetFocusedItem = gridSetFocusedItem

    screen.UpdateThumbUrl = gridUpdateThumbUrl

    if GetGlobal("IsHD") then
        screen.rowSize = 5
    else
        screen.rowSize = 4
    end if

    return screen
End Function

'* Convenience method to create a grid screen with a loader for the specified item
Function createGridScreenForItem(item, viewController, style="square", nonMixStyle=invalid) As Object
    obj = createGridScreen(viewController, style, nonMixStyle)

    ' We need to validate the grid style if it's mixed. We cannot allow any
    ' other style than square, portrait or landscape as it reboots the roku.
    if obj.isMixedAspect = true and style <> "portrait" and style <> "square" and style <> "landscape" then style = "square"

    obj.Item = item

    container = createPlexContainerForUrl(item.server, item.sourceUrl, item.key)
    container.SeparateSearchItems = true

    ' If this is a library with support for filters, add a dummy item for the
    ' filter options to the search row.
    if item.Filters = "1" then
        filters = CreateObject("roAssociativeArray")
        filters.server = item.server
        filters.sourceUrl = FullUrl(item.server.serverUrl, item.sourceUrl, item.key)
        filters.ContentType = "filters"
        filters.Key = "_filters_"
        filters.Title = "Filters"
        filters.SectionType = item.ContentType
        filters.ShortDescriptionLine1 = "Filters"
        filters.Description = "Filter content in this section"
        filters.SDPosterURL = "file://pkg:/images/gear.png"
        filters.HDPosterURL = "file://pkg:/images/gear.png"
        filters.FilterOptions = createFilterOptions(item)

        container.FilterOptions = filters.FilterOptions
        container.search.Push(filters)

        style = filters.FilterOptions.GetSelectedType().gridStyle
    end if

    obj.Loader = createPaginatedLoader(container, 8, 75, obj.Item, style)
    obj.Loader.Listener = obj

    ' Don't play theme music on top of grid screens on the older Roku models.
    ' It's not worth the DestroyAndRecreate headache.
    if item.theme <> invalid AND GetGlobal("rokuVersionArr", [0])[0] >= 4 AND NOT AudioPlayer().IsPlaying AND RegRead("theme_music", "preferences", "loop") <> "disabled" then
        AudioPlayer().PlayThemeMusic(item)
        obj.Cleanup = baseStopAudioPlayer
    end if

    return obj
End Function

Function gridInitializeRows(clear=true)
    m.Loader.UpdateFilters(false)
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
            ' we need a placehoder for mixed-aspect-ratio grids
            if m.isMixedAspect = true then
                placeholder = m.Loader.GetPlaceholder(row, true)
            else
                placeholder = invalid
            end if

            if placeholder <> invalid then
                m.contentArray[row] = [placeholder]
                m.Screen.SetContentList(row, m.contentArray[row])
            else
                Debug("Hiding row " + tostr(row) + " in InitializeRows")
                m.SetVisibility(row, false)
            end if
        end if
    end for

    return true
End Function

Function showGridScreen() As Integer
    if m.Facade = invalid then
        m.Facade = CreateObject("roGridScreen")
        m.Facade.Show()
    end if

    if m.Loader.FilterOptions <> invalid AND NOT m.Loader.FilterOptions.IsInitialized() then
        m.Loader.FilterOptions.FetchValues(m)
        return 0
    end if

    totalTimer = createTimer()

    if NOT m.InitializeRows() then return -1

    m.Screen.Show()
    m.Facade.Close()
    m.Facade = invalid

    ' Only two rows and five items per row are visible on the screen, so
    ' don't load much more than we need to before initially showing the
    ' grid. Once we start the event loop we can load the rest of the
    ' content.
    '
    ' Caveat: Load all rows on the homeScreen to fix hiding/showing any
    '         rows the user has toggled in the preferences.

    maxRow = m.contentArray.Count() - 1
    home = GetViewController().home
    if maxRow > 1 and (home <> invalid and home.screenid <> m.screenid) then maxRow = 1

    for row = 0 to maxRow
        Debug("Loading beginning of row " + tostr(row))
        m.Loader.LoadMoreContent(row, 0)
    end for

    totalTimer.PrintElapsedTime("Total initial grid load")

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

            item = invalid
            if context <> invalid then item = context[index]
            if item <> invalid then
                if item.ContentType = "series" OR m.ignoreRowNameForBreadcrumbs then
                    breadcrumbs = [item.Title]
                else if item.ContentType = "section" then
                    breadcrumbs = [item.server.name, item.Title]
                else
                    breadcrumbs = [m.Loader.GetNames()[msg.GetIndex()], item.Title]
                end if

                child = m.ViewController.CreateScreenForItem(context, index, breadcrumbs, false)

                if child <> invalid then
                    m.Facade = CreateObject("roGridScreen")
                    m.Facade.Show()
                    child.Show()
                    child = invalid
                end if
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
                arr = m.Loader.GetContextAndIndexForItem(m.selectedRow, m.focusedIndex)
                if arr = invalid then
                    context = m.contentArray[m.selectedRow]
                    index = m.focusedIndex
                else
                    context = arr[0]
                    index = arr[1]
                end if
 
                if context <> invalid then
                    m.Facade = CreateObject("roGridScreen")
                    m.Facade.Show()
                    m.ViewController.CreatePlayerForItem(context, index)
                end if
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
    if row < 0 OR row >= m.contentArray.Count() then return

    Debug("Loaded " + tostr(count) + " elements in row " + tostr(row) + ", now have " + tostr(data.Count()))

    m.contentArray[row] = data

    ' Don't bother showing empty rows
    if data.Count() = 0 then
        if m.Screen <> invalid AND m.Loader.GetLoadStatus(row) = 2 then
            ' non mixed-aspect-ratio? then we HIDE it!
            if m.isMixedAspect = false then
                m.SetVisibility(row, false)
                m.Screen.SetContentList(row, data)
            else
                placeholder = m.Loader.GetPlaceholder(row, true)
                if placeholder = invalid then
                    ' CAUTION: This cannot be safely undone on a mixed-aspect-ratio grid!
                    ' * Hiding rows cannot be safley DONE 100% of the time either. For now,
                    ' we cannot hide anything on the grid.

                    rowName = m.loader.names[row]
                    dummy = CreateObject("roAssociativeArray")
                    dummy.Key = invalid
                    dummy.ThumbUrl = invalid
                    dummy.ThumbProcessed = ""
                    dummy.paragraphs = []
                    dummy.paragraphs.Push("If you'll never use this row '" + rowName + "', you can reorder it under Preferences -> Section Display")
                    dummy.Title = rowName + " is Empty"
                    dummy.header = dummy.Title
                    placeholder = dummy
                end if

                m.UpdateThumbUrl(placeholder, row)
                m.contentArray[row] = [placeholder]
                m.Screen.SetContentList(row, m.contentArray[row])
            end if
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
        m.UpdateThumbUrl(data[i], row)
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
        ' close any facades even though we are ignoring the rest.
        if m.Facade <> invalid then
            m.Facade.Close()
            m.Facade = invalid
        end if
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

    if m.Facade <> invalid then
        m.Facade.Close()
        m.Facade = invalid
    end if
End Sub

Sub gridOnTimerExpired(timer)
    if timer.Name = "Reactivate" AND m.ViewController.IsActiveScreen(m) then
        m.Activate(invalid)
    else if timer.Name = "gridRowVisibilityChange" then
        gridCloseRowVisibilityFacade(timer)
        m.timerRowVisibility = invalid
    end if
End Sub

Sub gridSetVisibility(row, visible)
    if m.rowVisibility[row] = visible then return

    Debug("gridSetVisibility:: row:" + tostr(row) + ", visible:" + tostr(visible) + ", isMixedAspect: " + tostr(m.isMixedAspect))

    ' Ignore the intrusive fix if rowStyles are invalid. It's also safe to
    ' change visibilty on a NON mixed-aspect-ratio grid
    if m.rowStyles = invalid or m.isMixedAspect = false then
        m.rowVisibility[row] = visible
        m.Screen.SetListVisible(row, visible)
        return
    end if

    if m.facadeRowVisibility = invalid then
        ' use the same type of facade in use to be less intrusive
        if type(m.facade) = "roGridScreen" then
            facade = CreateObject("roGridScreen")
        else
            facade = CreateObject("roOneLineDialog")
            facade.SetTitle("Please Wait")
        end if
        facade.Show()
        m.facadeRowVisibility = facade
    end if

    ' Prevent facade flashes. Use a timer to to keep the same
    ' facade displayed while we iterate through the rows.
    if m.timerRowVisibility = invalid then
        m.timerRowVisibility = createTimer()
        m.timerRowVisibility.Name = "gridRowVisibilityChange"
        m.timerRowVisibility.SetDuration(1500)
        m.ViewController.AddTimer(m.timerRowVisibility, m)
    end if

    Debug("gridSetVisibility:: Requested Row: " + tostr(row) + ", Selected Row: " + tostr(m.selectedrow))
    ' Try and focus the last selected and visible row before hiding the
    ' said row. Using 999 used to work, but that could cause an odd
    ' phantom/endless scroll that continued to the end of all rows. This
    ' will put the user back into the area they were in before hiding a row.

    ' mark row visibility before logic starts
    m.rowVisibility[row] = visible

    ' Focus another row if the current selection is the one we are hiding.
    '  First try to focus the Previous visable row
    '  Second: try to focus the Next visable row
    focusRow = invalid
    focusIndex = 0
    if m.selectedRow = row then
        ' try to focus on any valid/visable previous row
        for index = row to 0 step -1
            if m.rowVisibility[index] = true then
                focusRow = index
                exit for
            end if
        end for

        ' try to focus on any valid/visable next row if we didn't match a previous
        if focusRow = invalid then
            for index = row to m.rowVisibility.count()-1 step 1
                if m.rowVisibility[index] = true then
                    focusRow = index
                    exit for
                end if
            end for
        end if
    else if m.rowVisibility[m.selectedRow] = true then
        ' use the current selected row if visible
        focusRow = m.selectedRow
        focusIndex = m.focusedIndex
    end if

    ' fallback - invalid row but the Roku will figure it out (hack)
    if focusRow = invalid then focusRow = 999
    Debug("setting focus on row: " +tostr(focusRow) + ", index: " + tostr(focusIndex))
    m.Screen.SetFocusedListItem(focusRow, focusIndex)

    ' Give the screen time to focus a visable row before hiding
    ' anything lower may intermittently crash
    sleep(250)

    ' and set row visbility on the screen
    m.Screen.SetListVisible(row, visible)
    sleep(250)
End Sub

Sub gridSetFocusedItem(row, col)
    if m.rowVisibility[row] = true then
        ' Only allow focusing a non-zero index if there's enough content to
        ' fill the screen.
        if validint(m.lastUpdatedSize[row]) < m.rowSize then col = 0

        Debug("Focusing " + tostr(row) + ", " + tostr(col))
        m.Screen.SetFocusedListItem(row, col)
    else
        Debug("Tried to focus hidden row (" + tostr(row) + "), too afraid to allow it")
    end if
End Sub

sub gridCloseRowVisibilityFacade(timer)
    if timer.listener.facadeRowVisibility <> invalid then
        timer.listener.facadeRowVisibility.close()
        timer.listener.facadeRowVisibility = invalid
    end if
end sub

Sub gridUpdateThumbUrl(item, row)
    if m.rowStyles = invalid and m.rowStyle <> invalid then
        curRowStyle = m.rowStyle
    else
        curRowStyle = m.rowStyles[row]
    end if

    if item.ThumbProcessed <> invalid AND item.ThumbProcessed <> curRowStyle then
        item.ThumbProcessed = curRowStyle
        if item.ThumbUrl <> invalid AND item.server <> invalid then
            sizes = ImageSizesGrid(curRowStyle)
            item.SDPosterURL = item.server.TranscodedImage(item.sourceUrl, item.ThumbUrl, sizes.sdWidth, sizes.sdHeight)
            item.HDPosterURL = item.server.TranscodedImage(item.sourceUrl, item.ThumbUrl, sizes.hdWidth, sizes.hdHeight)
        else if item.ThumbUrl = invalid
            item.SDPosterURL = "file://pkg:/images/BlankPoster_" + curRowStyle + ".png"
            item.HDPosterURL = "file://pkg:/images/BlankPoster_" + curRowStyle + ".png"
        end if
    end if
End Sub

Sub setGridTheme(style as String)
    ' This has to be done before the CreateObject call. Once the grid has
    ' been created you can change its style, but you can't change its theme.

    app = CreateObject("roAppManager")
    if style = "mixed-aspect-ratio" then
        ' just in case someone runs this routine
        return
    else if style = "flat-square" then
        app.SetThemeAttribute("GridScreenFocusBorderHD", "pkg:/images/border-square-hd.png")
        app.SetThemeAttribute("GridScreenFocusBorderSD", "pkg:/images/border-square-sd.png")
    else if style = "flat-16x9" then
        app.SetThemeAttribute("GridScreenFocusBorderHD", "pkg:/images/border-episode-hd.png")
        app.SetThemeAttribute("GridScreenFocusBorderSD", "pkg:/images/border-episode-sd.png")
    else if style = "flat-movie" then
        app.SetThemeAttribute("GridScreenFocusBorderHD", "pkg:/images/border-movie-hd.png")
        app.SetThemeAttribute("GridScreenFocusBorderSD", "pkg:/images/border-movie-sd.png")
    else if style = "flat-portrait" then
        app.SetThemeAttribute("GridScreenFocusBorderHD", "pkg:/images/border-portrait-hd.png")
        app.SetThemeAttribute("GridScreenFocusBorderSD", "pkg:/images/border-portrait-sd.png")
    end if
    ' The actual focus border is set by the grid based on the style
    app.SetThemeAttribute("GridScreenBorderOffsetHD","(-9,-9)")
    app.SetThemeAttribute("GridScreenBorderOffsetSD","(-9,-9)")
End Sub