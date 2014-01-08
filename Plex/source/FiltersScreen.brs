'*** Main Filtering Options Screen ***

Function createFiltersScreen(item, viewController) As Object
    obj = CreateObject("roAssociativeArray")
    initBaseScreen(obj, viewController)

    screen = CreateObject("roListScreen")
    screen.SetMessagePort(obj.Port)
    screen.SetHeader(item.Title)

    ' Standard properties for all our screen types
    obj.Item = item
    obj.Screen = screen

    obj.FilterOptions = item.FilterOptions

    obj.Show = showFiltersScreen
    obj.HandleMessage = filtersMainHandleMessage
    obj.OnUserInput = filtersOnUserInput

    obj.SetSelectedType = filtersSetSelectedType

    lsInitBaseListScreen(obj)

    return obj
End Function

Sub showFiltersScreen()
    if m.FilterOptions.IsInitialized() then
        if m.contentArray.Count() > 0 then
            m.AppendValue(m.TypeIndex + 1, m.FilterOptions.GetFiltersLabel())
            m.AppendValue(m.TypeIndex + 2, m.FilterOptions.GetSortsLabel())
        else
            if m.FilterOptions.GetTypes().Count() > 1 then
                m.TypeIndex = 0
                m.AddItem({title: "Type"}, "type", m.FilterOptions.GetSelectedType().title)
            else
                m.TypeIndex = -1
            end if

            m.AddItem({title: "Filters"}, "filters", m.FilterOptions.GetFiltersLabel())
            m.AddItem({title: "Sort"}, "sorts", m.FilterOptions.GetSortsLabel())
            m.AddItem({title: "Reset"}, "reset")
            m.AddItem({title: "Close"}, "close")

            m.Screen.Show()
        end if

        if m.Facade <> invalid then m.Facade.Close()
    else
        m.Facade = CreateObject("roListScreen")
        m.Facade.Show()
        m.FilterOptions.FetchValues(m)
    end if
End Sub

Function filtersMainHandleMessage(msg) As Boolean
    handled = false

    if type(msg) = "roListScreenEvent" then
        handled = true

        if msg.isScreenClosed() then
            m.ViewController.PopScreen(m)
        else if msg.isListItemSelected() then
            command = m.GetSelectedCommand(msg.GetIndex())
            m.Command = command
            m.currentIndex = msg.GetIndex()
            if command = "type" then
                screen = m.ViewController.CreateEnumInputScreen(m.FilterOptions.GetTypes(), m.FilterOptions.GetSelectedType().EnumValue, "Media Type", [], false)
                screen.Listener = m
                screen.Show()
            else if command = "filters" then
                screen = createFilterFiltersScreen(m.FilterOptions, m.ViewController)
                screen.Listener = m
                m.ViewController.InitializeOtherScreen(screen, ["Filters"])
                screen.Show()
            else if command = "sorts" then
                screen = createFilterSortsScreen(m.FilterOptions, m.ViewController)
                screen.Listener = m
                m.ViewController.InitializeOtherScreen(screen, ["Sort"])
                screen.Show()
            else if command = "reset" then
                m.SetSelectedType(0, "")
                m.FilterOptions.Reset()
                if m.TypeIndex >= 0 then
                    m.AppendValue(m.TypeIndex, m.FilterOptions.GetSelectedType().title)
                end if
                m.AppendValue(m.TypeIndex + 1, m.FilterOptions.GetFiltersLabel())
                m.AppendValue(m.TypeIndex + 2, m.FilterOptions.GetSortsLabel())
            else
                m.Screen.Close()
            end if
        end if
    end if

    return handled
End Function

Sub filtersOnUserInput(value, screen)

    if m.Command = "type" then
        m.SetSelectedType(screen.SelectedIndex, screen.SelectedLabel)
    else
        m.AppendValue(m.currentIndex, value)
    end if
End Sub

Sub filtersSetSelectedType(index, label)
    if m.FilterOptions.SetSelectedType(index) then
        m.AppendValue(m.TypeIndex, label)

        m.Facade = CreateObject("roOneLineDialog")
        m.Facade.SetTitle("Please wait...")
        m.Facade.ShowBusyAnimation()
        m.Facade.Show()
        m.FilterOptions.FetchValues(m)
    end if
End Sub


'*** Filters Screen ***

Function createFilterFiltersScreen(filterOptions, viewController) As Object
    obj = CreateObject("roAssociativeArray")
    initBaseScreen(obj, viewController)

    screen = CreateObject("roListScreen")
    screen.SetMessagePort(obj.Port)
    screen.SetHeader("Filters")

    ' Standard properties
    obj.Item = invalid
    obj.Screen = screen

    obj.FilterOptions = filterOptions

    obj.Show = showFilterFiltersScreen
    obj.HandleMessage = filterFiltersHandleMessage
    obj.OnUserInput = filtersOnUserInput

    lsInitBaseListScreen(obj)

    return obj
End Function

Sub showFilterFiltersScreen()
    currentFilters = m.FilterOptions.GetCurrentFilters()

    for each obj in m.FilterOptions.GetFilters()
        if currentFilters.DoesExist(obj.key) then
            m.AddItem(obj, obj.key, JoinArray(currentFilters[obj.key], ", ", "origtitle", "title"))
        else
            m.AddItem(obj, obj.key)
        end if
    end for

    m.AddItem({title: "Close"}, "close")

    m.Screen.Show()
End Sub

Function filterFiltersHandleMessage(msg) As Boolean
    handled = false

    if type(msg) = "roListScreenEvent" then
        handled = true

        if msg.isScreenClosed() then
            if m.Listener <> invalid then
                m.Listener.OnUserInput(m.FilterOptions.GetFiltersLabel(), m)
            end if
            m.ViewController.PopScreen(m)
        else if msg.isListItemSelected() then
            m.currentIndex = msg.GetIndex()
            command = m.GetSelectedCommand(m.currentIndex)
            if command = "close" then
                m.Screen.Close()
            else
                filter = m.FilterOptions.filtersHash[command]
                if filter = invalid then
                    Debug("Unrecognized command: " + command)
                    m.Screen.Close()
                else
                    screen = createFilterValuesScreen(m.FilterOptions, filter, m.ViewController)
                    screen.Listener = m
                    m.ViewController.InitializeOtherScreen(screen, [firstOf(filter.OrigTitle, filter.Title)])
                    screen.Show()
                end if
            end if
        end if
    end if

    return handled
End Function


'*** Filter Values Screen ***

Function createFilterValuesScreen(filterOptions, item, viewController) As Object
    obj = CreateObject("roAssociativeArray")
    initBaseScreen(obj, viewController)

    screen = CreateObject("roListScreen")
    screen.SetMessagePort(obj.Port)
    screen.SetHeader(firstOf(item.OrigTitle, item.Title))

    ' Standard properties
    obj.Item = item
    obj.Screen = screen

    obj.FilterOptions = filterOptions

    obj.Show = showFilterValuesScreen
    obj.HandleMessage = filterValuesHandleMessage
    obj.LabelForFilterValue = filterValuesLabelForFilterValue

    obj.selectedValues = {}

    lsInitBaseListScreen(obj)

    return obj
End Function

Function filterValuesLabelForFilterValue(selected)
    if m.Item.filterType <> "boolean" AND selected = true then
        return "X"
    else
        return invalid
    end if
End Function

Sub showFilterValuesScreen()
    if m.Item.values <> invalid then
        currentValues = m.FilterOptions.GetCurrentFilters()[m.Item.key]
        for each obj in currentValues
            m.selectedValues[obj.key] = true
        end for

        m.optionsByKey = {}
        for each obj in m.Item.values
            m.optionsByKey[obj.key] = obj
            m.AddItem(obj, obj.key, m.LabelForFilterValue(m.selectedValues.DoesExist(obj.key)))
        end for

        m.AddItem({title: "Close"}, "close")

        m.Screen.Show()
        if m.Facade <> invalid then m.Facade.Close()
    else
        m.Facade = CreateObject("roListScreen")
        m.Facade.Show()
        m.FilterOptions.FetchFilterValues(m.Item, m)
    end if
End Sub

Function filterValuesHandleMessage(msg) As Boolean
    handled = false

    if type(msg) = "roListScreenEvent" then
        handled = true

        if msg.isScreenClosed() then
            values = []
            for each key in m.selectedValues
                values.Push(m.optionsByKey[key])
            end for
            m.FilterOptions.SetFilter(m.Item.key, values)
            if m.Listener <> invalid then
                m.Listener.OnUserInput(JoinArray(values, ", ", "origtitle", "title"), m)
            end if

            m.ViewController.PopScreen(m)
        else if msg.isListItemSelected() then
            command = m.GetSelectedCommand(msg.GetIndex())
            if command = "close" then
                m.Screen.Close()
            else if m.Item.filterType = "boolean" then
                if command = "1" then
                    m.selectedValues[command] = true
                else
                    m.selectedValues.Clear()
                end if
                m.Screen.Close()
            else if m.selectedValues.DoesExist(command) then
                m.AppendValue(msg.GetIndex(), m.LabelForFilterValue(false))
                m.selectedValues.Delete(command)
            else
                m.AppendValue(msg.GetIndex(), m.LabelForFilterValue(true))
                m.selectedValues[command] = true
            end if
        end if
    end if

    return handled
End Function


'*** Sorts Screen ***

Function createFilterSortsScreen(filterOptions, viewController) As Object
    obj = CreateObject("roAssociativeArray")
    initBaseScreen(obj, viewController)

    screen = CreateObject("roListScreen")
    screen.SetMessagePort(obj.Port)
    screen.SetHeader("Sorting")

    ' Standard properties
    obj.Item = invalid
    obj.Screen = screen

    obj.FilterOptions = filterOptions

    obj.Show = showFilterSortsScreen
    obj.HandleMessage = filterSortsHandleMessage

    lsInitBaseListScreen(obj)

    return obj
End Function

Function LabelForSortDirection(ascending)
    if ascending = true then
        return "ascending"
    else
        return "descending"
    end if
End Function

Sub showFilterSortsScreen()
    currentSort = m.FilterOptions.GetCurrentSorts()

    for each obj in m.FilterOptions.GetSorts()
        if currentSort.DoesExist(obj.key) then
            m.selectedIndex = m.contentArray.Count()
            m.ascending = currentSort[obj.key]
            m.AddItem(obj, obj.key, LabelForSortDirection(m.ascending))
        else
            m.AddItem(obj, obj.key)
        end if
    end for

    m.AddItem({title: "Close"}, "close")

    if m.selectedIndex = invalid then
        m.selectedIndex = m.contentArray.Count() - 1
        m.ascending = true
    else
        m.Screen.SetFocusedListItem(m.selectedIndex)
    end if

    m.Screen.Show()
End Sub

Function filterSortsHandleMessage(msg) As Boolean
    handled = false

    if type(msg) = "roListScreenEvent" then
        handled = true

        if msg.isScreenClosed() then
            if m.Listener <> invalid then
                m.Listener.OnUserInput(m.FilterOptions.GetSortsLabel(), m)
            end if
            m.ViewController.PopScreen(m)
        else if msg.isListItemSelected() then
            command = m.GetSelectedCommand(msg.GetIndex())
            if command = "close" then
                m.Screen.Close()
            else
                if msg.GetIndex() = m.selectedIndex then
                    m.ascending = NOT m.ascending
                else
                    m.AppendValue(m.selectedIndex, invalid)
                    m.selectedIndex = msg.GetIndex()
                    m.ascending = true
                end if

                m.FilterOptions.SetSort(command, m.ascending)
                m.AppendValue(m.selectedIndex, LabelForSortDirection(m.ascending))
            end if
        end if
    end if

    return handled
End Function
