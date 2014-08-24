
Function newPlaylistsMetadata(container, item) As Object
    playlists = createBaseMetadata(container, item)
    playlists.ContentType = item@type
    return playlists
End Function

