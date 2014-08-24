
'* This logic reflects that in the PosterScreen.SetListStyle
'* Not using the standard sizes appears to slow navigation down
Function ImageSizes(viewGroup, contentType) As Object
	'* arced-square size
	sdWidth = "223"
	sdHeight = "200"
	hdWidth = "300"
	hdHeight = "300"
	if viewGroup = "movie" OR viewGroup = "show" OR viewGroup = "season" OR viewGroup = "episode" then
	'* arced-portrait sizes
		sdWidth = "158"
		sdHeight = "204"
		hdWidth = "214"
		hdHeight = "306"
	elseif contentType = "episode" AND viewGroup = "episode" then
		'* flat-episodic sizes
		sdWidth = "166"
		sdHeight = "112"
		hdWidth = "224"
		hdHeight = "168"
	elseif viewGroup = "Details" then
		'* arced-square sizes
		sdWidth = "223"
		sdHeight = "200"
		hdWidth = "300"
		hdHeight = "300"

	endif
	sizes = CreateObject("roAssociativeArray")
	sizes.sdWidth = sdWidth
	sizes.sdHeight = sdHeight
	sizes.hdWidth = hdWidth
	sizes.hdHeight = hdHeight
	return sizes
End Function

Function ImageSizesGrid(style)
    sizes = CreateObject("roAssociativeArray")

    sizes.hdWidth = "192"
    sizes.sdWidth = "140"

    if style = "square" then
        sizes.sdHeight = "126"
        sizes.hdHeight = "192"
    else if style = "landscape" then
        sizes.sdHeight = "94"
        sizes.hdHeight = "144"
    else
        sizes.sdHeight = "180"
        sizes.hdHeight = "274"
    end if

    return sizes
End Function

Function createBaseMetadata(container, item, thumb=invalid) As Object
    metadata = CreateObject("roAssociativeArray")

    server = container.server
    if item@machineIdentifier <> invalid then
        server = GetPlexMediaServer(item@machineIdentifier)
    end if

    metadata.Title = firstOf(item@title, item@name, "")

    ' There is a *massive* performance problem on grid views if the description
    ' isn't truncated.
    metadata.Description = truncateString(item@summary, 250, invalid)
    metadata.ShortDescriptionLine1 = metadata.Title
    metadata.ShortDescriptionLine2 = truncateString(item@summary, 250, invalid)
    metadata.Type = item@type
    metadata.Key = item@key
    metadata.Settings = item@settings
    metadata.NodeName = item.GetName()

    metadata.viewGroup = container.ViewGroup

    metadata.sourceTitle = item@sourceTitle

    if container.xml@mixedParents = "1" then
        parentTitle = firstOf(item@parentTitle, container.xml@parentTitle, "")
        if parentTitle <> "" then
            metadata.Title = parentTitle + ": " + metadata.Title
        end if
    end if

    sizes = ImageSizes(container.ViewGroup, item@type)


    if thumb = invalid then
        thumb = firstOf(item@thumb, item@parentThumb, item@grandparentThumb, container.xml@thumb, item@composite)
    end if

    if thumb <> invalid AND thumb <> "" AND server <> invalid then
        metadata.ThumbUrl = thumb
        metadata.ThumbProcessed = ""
        metadata.SDPosterURL = server.TranscodedImage(container.sourceUrl, thumb, sizes.sdWidth, sizes.sdHeight)
        metadata.HDPosterURL = server.TranscodedImage(container.sourceUrl, thumb, sizes.hdWidth, sizes.hdHeight)
    else
        metadata.ThumbUrl = invalid
        ' try to use a more appropriately sized blank thumb image
        if instr(1, firstof(container.xml@identifier,""), "com.plexapp.plugins") = 0 then
            metadata.ThumbProcessed = "portrait"
        else
            metadata.ThumbProcessed = "square"
        end if
        metadata.SDPosterURL = "file://pkg:/images/BlankPoster_" + metadata.ThumbProcessed + ".png"
        metadata.HDPosterURL = "file://pkg:/images/BlankPoster_" + metadata.ThumbProcessed + ".png"
    end if

    metadata.sourceUrl = container.sourceUrl
    metadata.server = server

    if item@userRating <> invalid then
        metadata.UserRating =  int(val(item@userRating)*10)
    endif

    metadata.HasDetails = false
    metadata.ParseDetails = baseParseDetails
    metadata.Refresh = baseMetadataRefresh

    return metadata
End Function

Function baseParseDetails()
    m.HasDetails = true
    return m
End Function

Sub baseMetadataRefresh(detailed=false)
End Sub

Function newSearchMetadata(container, item) As Object
    metadata = createBaseMetadata(container, item)

    metadata.type = "search"
    metadata.ContentType = "search"
    metadata.search = true
    metadata.prompt = item@prompt

    if metadata.SDPosterURL = invalid OR Left(metadata.SDPosterURL, 4) = "file" OR instr(1, metadata.SDPosterURL, "%2F%3A%2Fresources%2F") > 0 then
        metadata.SDPosterURL = "file://pkg:/images/search.png"
        metadata.HDPosterURL = "file://pkg:/images/search.png"
    end if

    ' Special handling for search items inside channels, which may actually be
    ' text input objects. There's no good way to tell. :[
    if metadata.key.Left(1) = "/" then
        ' If the item isn't for a search service and doesn't start with "Search",
        ' we'll try using a keyboard screen. Anything else sounds like an honest
        ' to goodness search and will get a search screen.
        if instr(1, metadata.key, "/serviceSearch") <= 0 AND metadata.prompt <> invalid AND metadata.prompt.Left(6) <> "Search" then
            metadata.ContentType = "keyboard"
        end if
    end if

    return metadata
End Function

Function newSettingMetadata(container, item) As Object
    metadata = CreateObject("roAssociativeArray")

    metadata.ContentType = "setting"
    metadata.setting = true

    metadata.type = firstOf(item@type, "text")
    metadata.default = firstOf(item@default, "")
    metadata.value = firstOf(item@value, "")
    metadata.label = firstOf(item@label, "")
    metadata.id = firstOf(item@id, "")
    metadata.hidden = (item@option = "hidden")
    metadata.secure = (item@secure = "true")

    if metadata.value = "" then
        metadata.value = metadata.default
    end if

    if metadata.type = "enum" then
        re = CreateObject("roRegex", "\|", "")
        metadata.values = re.Split(item@values)
    end if

    metadata.GetValueString = settingGetValueString

    return metadata
End Function

Function settingGetValueString() As String
    if m.type = "enum" then
        value = m.values[m.value.toint()]
    else
        value = m.value
    end if

    if m.hidden OR m.secure then
        re = CreateObject("roRegex", ".", "i")
        value = re.ReplaceAll(value, "\*")
    end if

    return value
End Function

