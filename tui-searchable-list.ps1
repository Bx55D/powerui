[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [object[]]$list_items
)

function Clamp([int]$v, [int]$min, [int]$max){
    if ($v -lt $min){ return $min }
    if ($v -gt $max){ return $max }
    return $v
}

function New-Buffer([int]$w, [int]$h) {
    # Buffer includes a newline char at the end of each row: stride = w + 1
    $buf = New-Object char[] (($w + 1) * $h)

    for ($y = 0; $y -lt $h; $y++){
        $line_start = $y * ($w + 1)
        for ($x = 0; $x -lt $w; $x++){
            $buf[$line_start + $x] = ' '
        }
        $buf[$line_start + $w] = "`n"
    }

    Write-Output $buf -NoEnumerate
}

function Clear-Buffer([char[]]$buf){
    for ($i = 0; $i -lt $buf.Length; $i++){
        if ($buf[$i] -ne "`n") { $buf[$i] = ' ' }
    }
}

function Put-Text(
    [char[]]$buf,
    [int]$bufW,
    [int]$bufH,
    [int]$x,
    [int]$y,
    [string]$text
){
    if ($null -eq $text) { return }
    if ($x -lt 0 -or $y -lt 0) { return }
    if ($y -ge $bufH) { return }
    if ($x -ge $bufW) { return }

    $stride = $bufW + 1
    $rowStart = $y * $stride

    $i = $rowStart + $x
    # Max write index is end-of-row (exclusive of newline)
    $rowEnd = $rowStart + $bufW

    foreach ($ch in $text.ToCharArray()){
        if ($i -ge $rowEnd) { break }
        if ($i -ge $buf.Length) { break }
        $buf[$i] = $ch
        $i++
    }
}

function Render-Search ($stdin_buffer, [char[]]$screen_buffer, [int]$bufW, [int]$bufH) {
    $height = 3

    # Ensure the box actually fits the screen
    $maxBoxW = [Math]::Max(4, $bufW)                 # at least 4 chars for corners + interior
    $width = [int](Clamp ([int]($bufW * 0.6)) 10 ($maxBoxW))
    $width = [Math]::Min($width, $bufW)              # never exceed buffer width
    $width = [Math]::Max(4, $width)

    $tl = '┌'; $bl = '└'; $tr = '┐'; $br = '┘'; $v = '│'; $h = '─'

    $padX = [int](($bufW - $width) / 2)
    $padX = [Math]::Max(0, $padX)
    $padY = 2

    # If too short to render, just bail
    if ($padY + $height - 1 -ge $bufH) { return }

    $innerW = [Math]::Max(0, $width - 2)
    Put-Text $screen_buffer $bufW $bufH $padX $padY ($tl + ($h * $innerW) + $tr)

    # Clamp input line to available space
    $inputVisible = $stdin_buffer
    if ($inputVisible.Length -gt $innerW) {
        # show tail end like a normal prompt
        $inputVisible = $inputVisible.Substring($inputVisible.Length - $innerW)
    }

    for ($i = 1; $i -lt $height-1; $i++){
        $spaces = [Math]::Max(0, $innerW - $inputVisible.Length)
        Put-Text $screen_buffer $bufW $bufH $padX ($padY+$i) ($v + $inputVisible + (' ' * $spaces) + $v)
    }

    Put-Text $screen_buffer $bufW $bufH $padX ($padY+$height-1) ($bl + ($h * $innerW) + $br)
}

function Render-SearchResults(
    [char[]]$screen_buffer,
    [int]$bufW,
    [int]$bufH,
    [int]$height,
    $results,
    [int]$scroll_offset,
    [int]$selected_index
) {
    if ($height -lt 1) { return }

    $maxBoxW = [Math]::Max(4, $bufW)
    $width = [int](Clamp ([int]($bufW * 0.6)) 10 ($maxBoxW))
    $width = [Math]::Min($width, $bufW)
    $width = [Math]::Max(4, $width)

    $tl = '┌'; $bl = '└'; $tr = '┐'; $br = '┘'; $v = '│'; $h = '─'

    $padX = [int](($bufW - $width) / 2)
    $padX = [Math]::Max(0, $padX)
    $padY = 7

    # Total box height is height + 2 (top + bottom)
    if ($padY + $height + 1 -ge $bufH) { return }

    $innerW = [Math]::Max(0, $width - 2)
    Put-Text $screen_buffer $bufW $bufH $padX $padY ($tl + ($h * $innerW) + $tr)

    for ($i = 0; $i -lt $height; $i++){
        $idx = $scroll_offset + $i
        $name = ""

        if ($results -and $idx -ge 0 -and $idx -lt $results.Count -and $null -ne $results[$idx]) {
            $name = [string]$results[$idx].display_name
        }

        if ($name.Length -gt $innerW) { $name = $name.Substring(0, $innerW) }
        $spaces = [Math]::Max(0, $innerW - $name.Length)

        if ($i -eq $selected_index){
            Put-Text $screen_buffer $bufW $bufH $padX ($padY+$i+1) ($v + "`e[97;44m" + $name + (' ' * $spaces) + "`e[0m" + $v)
        } else {
            Put-Text $screen_buffer $bufW $bufH $padX ($padY+$i+1) ($v + $name + (' ' * $spaces) + $v)
        }
    }

    Put-Text $screen_buffer $bufW $bufH $padX ($padY+$height+1) ($bl + ($h * $innerW) + $br)
}

# ---------------- MAIN ----------------

$w = [Console]::WindowWidth
$h = [Console]::WindowHeight - 1
if ($h -lt 1) { $h = 1 }

$buf = New-Buffer $w $h

$searchResults = $list_items

$stdin_buffer = ""
$selected_index = 0
$scroll_offset = 0
$filteredResults = $searchResults

while ($true){

    # Resize-safe refresh
    $newW = [Console]::WindowWidth
    $newH = [Console]::WindowHeight - 1
    if ($newH -lt 1) { $newH = 1 }

    if ($w -ne $newW -or $h -ne $newH){
        $w = $newW
        $h = $newH
        $buf = New-Buffer $w $h
    } else {
        Clear-Buffer $buf
    }

    # Compute panel height per-frame (so resize works immediately)
    $results_panel_height = [Math]::Max(1, $h - 12)

    # Clamp scroll/selection to current results
    $count = if ($filteredResults) { $filteredResults.Count } else { 0 }
    $visible = [Math]::Min($results_panel_height, $count)
    if ($visible -lt 1) { $selected_index = 0; $scroll_offset = 0 }
    else {
        $scroll_offset = [Math]::Max(0, [Math]::Min($scroll_offset, [Math]::Max(0, $count - $visible)))
        $selected_index = [Math]::Max(0, [Math]::Min($selected_index, $visible - 1))
    }

    # User Input
    while ([Console]::KeyAvailable){
        $key = [Console]::ReadKey($true)

        switch ($key.Key){
            'Backspace' {
                if ($stdin_buffer.Length -gt 0){
                    $stdin_buffer = $stdin_buffer.Substring(0, $stdin_buffer.Length-1)
                }
                $scroll_offset = 0; $selected_index = 0
            }

            'UpArrow' {
                if ($selected_index -gt 0){
                    $selected_index--
                } elseif ($scroll_offset -gt 0){
                    $scroll_offset--
                }
            }

            'DownArrow' {
                # Recompute visible/count inside input loop too
                $count = if ($filteredResults) { $filteredResults.Count } else { 0 }
                $visible = [Math]::Min($results_panel_height, $count)

                if ($visible -gt 0){
                    if ($selected_index -lt ($visible - 1)){
                        $selected_index++
                    } elseif (($scroll_offset + $visible) -lt $count){
                        $scroll_offset++
                    }
                }
            }

            'Enter' {
                $idx = $scroll_offset + $selected_index
                if ($filteredResults -and $idx -ge 0 -and $idx -lt $filteredResults.Count){
                    return $filteredResults[$idx].id
                }
                return $null
            }

            'Escape' { return $null }

            default {
                # Ignore control chars that can mess with layout
                if (-not [char]::IsControl($key.KeyChar)){
                    $stdin_buffer += $key.KeyChar
                    $scroll_offset = 0; $selected_index = 0
                }
            }
        }

        $pattern = [WildcardPattern]::Escape($stdin_buffer)
        $filteredResults = @( $searchResults | Where-Object { $_.display_name -like "*$pattern*" } )

        # After filtering, clamp again
        $count = $filteredResults.Count
        $visible = [Math]::Min($results_panel_height, $count)
        $scroll_offset = 0
        $selected_index = if ($visible -gt 0) { 0 } else { 0 }
    }

    Render-Search $stdin_buffer $buf $w $h
    Render-SearchResults $buf $w $h $results_panel_height $filteredResults $scroll_offset $selected_index

    [Console]::Write("`e[?25l") # Hide Cursor
    [Console]::SetCursorPosition(0, 0)
    [Console]::Write([string]::new($buf))

    Start-Sleep -Milliseconds 16
}
