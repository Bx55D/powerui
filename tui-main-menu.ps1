function Clamp([int]$v, [int]$min, [int]$max){
    if ($v -lt $min){ return $min }
    if ($v -gt $max){ return $max }
    return $v
}

function New-Buffer([int]$w, [int]$h) {
    $w = [Math]::Max($w, 1)
    $h = [Math]::Max($h, 1)

    $buf = New-Object char[] (($w + 1) * $h)

    for ($y = 0; $y -lt $h; $y++){
        $line_start = $y * ($w + 1)
        for ($x = 0; $x -lt $w; $x++){
            $buf[$line_start + $x] = " "
        }
        $buf[$line_start + $w] = "`n"
    }
    ,$buf
}

function Clear-Buffer([char[]]$buf){
    for ($i = 0; $i -lt $buf.Length; $i++){
        if ($buf[$i] -ne "`n") { $buf[$i] = ' ' }
    }
}

function Put-Text([char[]]$buf, [int]$bufW, [int]$bufH, [int]$x, [int]$y, [string]$text){
    if ([string]::IsNullOrEmpty($text)) { return }
    if ($y -lt 0 -or $y -ge $bufH) { return }

    if ($x -lt 0) { $x = 0 }
    if ($x -ge $bufW) { return }

    $stride = $bufW + 1
    $i = ($y * $stride) + $x
    $rowEndExclusive = ($y * $stride) + $bufW  # don't overwrite newline

    foreach ($ch in $text.ToCharArray()){
        if ($i -ge $rowEndExclusive) { break }
        $buf[$i] = $ch
        $i++
    }
}

function Fit-Text([string]$s, [int]$maxLen){
    if ($maxLen -le 0) { return "" }
    if ([string]::IsNullOrEmpty($s)) { return "" }
    if ($s.Length -le $maxLen) { return $s }
    if ($maxLen -le 1) { return $s.Substring(0, $maxLen) }
    return $s.Substring(0, $maxLen - 1) + "…"
}

function Render-Menu([char[]]$buf, [int]$w, [int]$h, $menu_items, [int]$selected_index){

    # thresholds for layout changes
    $minWForBox = 28
    $minHForBox = 10

    # super tiny: just show a hint
    if ($w -lt 16 -or $h -lt 3){
        Put-Text $buf $w $h 0 0 (Fit-Text "Window too small" $w)
        return
    }

    $title = "Sentinel Analytics Change Control Manager"

    # Decide layout mode based on actual window size
    $useBox = ($w -ge $minWForBox -and $h -ge $minHForBox)

    if (-not $useBox){
        # Compact, responsive list (no box, single-line highlight)
        Put-Text $buf $w $h 0 0 (Fit-Text $title $w)

        $startY = 2
        $visible = [Math]::Max(1, $h - $startY)
        $count = [Math]::Min($menu_items.Count, $visible)

        for ($i=0; $i -lt $count; $i++){
            $line = "  " + [string]$menu_items[$i]
            $line = Fit-Text $line $w

            if ($i -eq $selected_index){
                # highlight full line width
                $pad = ' ' * [Math]::Max(0, $w - ($line.Length))
                Put-Text $buf $w $h 0 ($startY + $i) ("`e[97;44m" + $line + $pad + "`e[0m")
            } else {
                Put-Text $buf $w $h 0 ($startY + $i) $line
            }
        }

        # Footer hint if there are more items than visible
        if ($menu_items.Count -gt $count -and $h -ge 2){
            Put-Text $buf $w $h 0 ($h-1) (Fit-Text "Resize to see more…" $w)
        }
        return
    }

    # --- Box layout (roomy) ---
    $tl='┌'; $tr='┐'; $bl='└'; $br='┘'; $v='│'; $hh='─'

    # Box width: 60% but capped to window with margins
    $width = Clamp ([int]($w * 0.6)) 28 ($w - 2)

    # Compute height based on spacing, but ensure it fits
    $itemStride = 3
    $desiredHeight = ($menu_items.Count * $itemStride) + 2
    $height = Clamp $desiredHeight 8 ($h - 2)

    # If height is constrained, reduce spacing (more responsive)
    if ($height -lt $desiredHeight){
        $itemStride = 2
        $desiredHeight = ($menu_items.Count * $itemStride) + 2
        $height = Clamp $desiredHeight 8 ($h - 2)

        if ($height -lt $desiredHeight){
            $itemStride = 1
            $desiredHeight = ($menu_items.Count * $itemStride) + 2
            $height = Clamp $desiredHeight 6 ($h - 2)
        }
    }

    $padX = [int](($w - $width) / 2)
    $padY = [int](($h - $height) / 2)
    if ($padX -lt 0) { $padX = 0 }
    if ($padY -lt 0) { $padY = 0 }

    # title (only if we have room above)
    $titleY = $padY - 2
    if ($titleY -ge 0){
        $titleX = [int](($w - $title.Length) / 2)
        Put-Text $buf $w $h $titleX $titleY (Fit-Text $title $w)
    }

    Put-Text $buf $w $h $padX $padY ($tl + ($hh * ($width - 2)) + $tr)

    $maxVisibleItems = [Math]::Max(1, [int](($height - 2) / $itemStride))
    $visibleCount = [Math]::Min($menu_items.Count, $maxVisibleItems)

    for ($i=0; $i -lt $visibleCount; $i++){
        $rowY = $padY + 1 + ($i * $itemStride)

        $itemText = Fit-Text ([string]$menu_items[$i]) ([Math]::Max(0, $width - 3))

        if ($i -eq $selected_index){
            if ($itemStride -ge 2){
                Put-Text $buf $w $h $padX $rowY     ($v + "`e[97;44m" + (' ' * ($width - 2)) + "`e[0m" + $v)
                Put-Text $buf $w $h $padX ($rowY+1) ($v + "`e[97;44m " + $itemText + (' ' * ($width - $itemText.Length - 3)) + "`e[0m" + $v)
                if ($itemStride -ge 3){
                    Put-Text $buf $w $h $padX ($rowY+2) ($v + "`e[97;44m" + (' ' * ($width - 2)) + "`e[0m" + $v)
                }
            } else {
                $line = $v + " " + $itemText + (' ' * ($width - $itemText.Length - 3)) + $v
                Put-Text $buf $w $h $padX $rowY ("`e[97;44m" + $line + "`e[0m")
            }
        } else {
            if ($itemStride -ge 2){
                Put-Text $buf $w $h $padX $rowY     ($v + (' ' * ($width - 2)) + $v)
                Put-Text $buf $w $h $padX ($rowY+1) ($v + " " + $itemText + (' ' * ($width - $itemText.Length - 3)) + $v)
                if ($itemStride -ge 3){
                    Put-Text $buf $w $h $padX ($rowY+2) ($v + (' ' * ($width - 2)) + $v)
                }
            } else {
                Put-Text $buf $w $h $padX $rowY ($v + " " + $itemText + (' ' * ($width - $itemText.Length - 3)) + $v)
            }
        }
    }

    Put-Text $buf $w $h $padX ($padY + $height - 1) ($bl + ($hh * ($width - 2)) + $br)

    # If we couldn't show everything, hint at bottom (inside box if possible)
    if ($visibleCount -lt $menu_items.Count){
        $hint = Fit-Text "… more items (resize taller)" ([Math]::Max(0, $width - 4))
        Put-Text $buf $w $h ($padX + 2) ($padY + $height - 2) $hint
    }
}

# --- main ---
$selected_index = 0
$menu_items = @("Stage Analytic", "Checkout Analytic", "Restore Analytic from Version Control", "Quit")

$w = [Console]::WindowWidth
$h = [Math]::Max(1, [Console]::WindowHeight - 1)
$buf = New-Buffer $w $h

while ($true){
    $newW = [Console]::WindowWidth
    $newH = [Math]::Max(1, [Console]::WindowHeight - 1)

    if ($newW -ne $w -or $newH -ne $h){
        $w = $newW
        $h = $newH
        $buf = New-Buffer $w $h
    } else {
        Clear-Buffer $buf
    }

    # keep selection valid
    $selected_index = Clamp $selected_index 0 ([Math]::Max(0, $menu_items.Count - 1))

    while ([Console]::KeyAvailable){
        $key = [Console]::ReadKey($true)
        switch ($key.Key){
            'UpArrow'   { if ($selected_index -gt 0) { $selected_index-- } }
            'DownArrow' { if ($selected_index -lt $menu_items.Count - 1) { $selected_index++ } }
            'Enter'     { return ($selected_index + 1) }
        }
    }

    Render-Menu $buf $w $h $menu_items $selected_index

    try {
        [Console]::Write("`e[?25l")            # Hide cursor
        [Console]::SetCursorPosition(0, 0)

        $bufString = [string]::new($buf)
        $maxLen = ($w + 1) * $h
        if ($bufString.Length -gt $maxLen){
            $bufString = $bufString.Substring(0, $maxLen)
        }

        [Console]::Write($bufString)
    } catch {
        # Resize races can throw; ignore and redraw next frame
    }

    Start-Sleep -Milliseconds 16
}
