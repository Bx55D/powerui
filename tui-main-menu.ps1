function Clamp([int]$v, [int]$min, [int]$max){
    if ($v -lt $min){ return $min }
    if ($v -gt $max){ return $max }
    return $v
}

function New-Buffer([int]$w, [int]$h) {
    # Our virtual screen has a minimum to keep layout reasonable
    $w = [Math]::Max($w, 100)
    $h = [Math]::Max($h, 50)

    $buf = New-Object char[] (($w + 1) * $h)

    for ($y = 0; $y -lt $h; $y++){
        $line_start = $y * ($w + 1)
        for ($x = 0; $x -lt $w; $x++){
            $buf[$line_start + $x] = " "
        }
        $buf[$line_start + $w] = "`n"
    }

    ,$buf  # -NoEnumerate equivalent
}

function Clear-Buffer([char[]]$buf){
    for ($i = 0; $i -lt $buf.Length; $i++){
        if ($buf[$i] -ne "`n") { $buf[$i] = ' ' }
    }
}

function Put-Text([char[]]$buf, [int]$bufW, [int]$bufH, [int]$x, [int]$y, [string]$text){
    if ($null -eq $text -or $text.Length -eq 0) { return }

    # Completely outside vertically
    if ($y -lt 0 -or $y -ge $bufH) { return }

    # Clamp X so we never compute negative or row-overflowing indices
    if ($x -lt 0) { $x = 0 }
    if ($x -ge $bufW) { return }

    $stride = $bufW + 1
    $i = ($y * $stride) + $x
    $rowEndExclusive = ($y * $stride) + $bufW  # don't write into newline slot

    foreach ($ch in $text.ToCharArray()){
        if ($i -ge $rowEndExclusive) { break }
        $buf[$i] = $ch
        $i++
    }
}

function Render-MenuItems([char[]]$screen_buffer, [int]$bufW, [int]$bufH, $menu_items, [int]$selected_index) {
    # Choose a box size that ALWAYS fits in the buffer
    $desiredWidth = [int]($bufW * 0.6)
    $width = Clamp $desiredWidth 30 $bufW
    $desiredHeight = ($menu_items.Count * 3) + 2
    $height = Clamp $desiredHeight 6 $bufH

    $tl = '┌'; $bl = '└'; $tr = '┐'; $br = '┘'; $v = '│'; $h = '─'

    $padX = [int](($bufW - $width) / 2)
    $padY = [int](($bufH - $height) / 2)
    if ($padX -lt 0) { $padX = 0 }
    if ($padY -lt 0) { $padY = 0 }

    $title = "Sentinel Analytics Change Control Manager"
    $titleX = [int](($bufW - $title.Length) / 2)
    $titleY = $padY - 2
    Put-Text $screen_buffer $bufW $bufH $titleX $titleY $title

    Put-Text $screen_buffer $bufW $bufH $padX $padY ($tl + ($h * ($width - 2)) + $tr)

    # We can only display as many items as fit
    $maxVisibleItems = [Math]::Max(0, [int](($height - 2) / 3))
    $visibleCount = [Math]::Min($menu_items.Count, $maxVisibleItems)

    for ($i = 0; $i -lt $visibleCount; $i++){
        $rowTop = $padY + ($i * 3) + 1

        $itemText = [string]$menu_items[$i]
        # Trim item if too long for box
        $maxItemLen = [Math]::Max(0, $width - 3)
        if ($itemText.Length -gt $maxItemLen){
            $itemText = $itemText.Substring(0, $maxItemLen)
        }

        if ($i -eq $selected_index){
            Put-Text $screen_buffer $bufW $bufH $padX $rowTop     ($v + "`e[97;44m" + (' ' * ($width - 2)) + "`e[0m" + $v)
            Put-Text $screen_buffer $bufW $bufH $padX ($rowTop+1) ($v + "`e[97;44m " + $itemText + (' ' * ($width - $itemText.Length - 3)) + "`e[0m" + $v)
            Put-Text $screen_buffer $bufW $bufH $padX ($rowTop+2) ($v + "`e[97;44m" + (' ' * ($width - 2)) + "`e[0m" + $v)
        } else {
            Put-Text $screen_buffer $bufW $bufH $padX $rowTop     ($v + (' ' * ($width - 2)) + $v)
            Put-Text $screen_buffer $bufW $bufH $padX ($rowTop+1) ($v + " " + $itemText + (' ' * ($width - $itemText.Length - 3)) + $v)
            Put-Text $screen_buffer $bufW $bufH $padX ($rowTop+2) ($v + (' ' * ($width - 2)) + $v)
        }
    }

    Put-Text $screen_buffer $bufW $bufH $padX ($padY + $height - 1) ($bl + ($h * ($width - 2)) + $br)
}

# --- main ---
$w = [Console]::WindowWidth
$h = [Console]::WindowHeight - 1

$buf = New-Buffer $w $h
$bufW = [Math]::Max($w, 100)
$bufH = [Math]::Max($h, 50)

$selected_index = 0
$menu_items = @("Stage Analytic", "Checkout Analytic", "Restore Analytic from Version Control", "Quit")

while ($true){
    $winW = [Console]::WindowWidth
    $winH = [Console]::WindowHeight - 1

    $newBufW = [Math]::Max($winW, 100)
    $newBufH = [Math]::Max($winH, 50)

    if ($newBufW -eq $bufW -and $newBufH -eq $bufH){
        Clear-Buffer $buf
    } else {
        $buf = New-Buffer $winW $winH
        $bufW = $newBufW
        $bufH = $newBufH
        # Keep selection in range after any resize/menu change
        $selected_index = Clamp $selected_index 0 ([Math]::Max(0, $menu_items.Count - 1))
    }

    while ([Console]::KeyAvailable){
        $key = [Console]::ReadKey($true)
        switch ($key.Key){
            'UpArrow'   { if ($selected_index -gt 0) { $selected_index-- } }
            'DownArrow' { if ($selected_index -lt $menu_items.Count - 1) { $selected_index++ } }
            'Enter'     { return ($selected_index + 1) }
        }
    }

    Render-MenuItems $buf $bufW $bufH $menu_items $selected_index

    try {
        [Console]::Write("`e[?25l")            # Hide cursor
        [Console]::SetCursorPosition(0, 0)

        $buf_string = [string]::new($buf)

        # Only trim if needed, and never compute a negative length
        $maxLen = ($bufW + 1) * $bufH
        if ($buf_string.Length -gt $maxLen){
            $buf_string = $buf_string.Substring(0, $maxLen)
        }

        [Console]::Write($buf_string)
    } catch {
        # If the host errors during a live resize, just continue next frame
    }

    Start-Sleep -Milliseconds 16
}
