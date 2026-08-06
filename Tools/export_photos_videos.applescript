on run argv
    set exportPath to item 1 of argv
    set maxCount to 0
    if (count of argv) > 1 then
        set maxCount to (item 2 of argv) as integer
    end if
    set startIndex to 1
    if (count of argv) > 2 then
        set startIndex to (item 3 of argv) as integer
    end if

    set exportedCount to 0
    set videoIndex to 0
    tell application "Photos"
        set allItems to search for "video"
        repeat with mediaItem in allItems
            set itemName to filename of mediaItem
            if itemName ends with ".mov" or itemName ends with ".MOV" or itemName ends with ".mp4" or itemName ends with ".MP4" or itemName ends with ".m4v" or itemName ends with ".M4V" then
                set videoIndex to videoIndex + 1
                if videoIndex >= startIndex then
                    try
                        export {mediaItem} to POSIX file exportPath using originals true
                        set exportedCount to exportedCount + 1
                        if maxCount > 0 and exportedCount >= maxCount then exit repeat
                    end try
                end if
            end if
        end repeat
    end tell
    return exportedCount
end run
