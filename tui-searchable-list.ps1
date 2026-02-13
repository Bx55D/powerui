[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [object[]]$list_items
)

function Clamp([int]$v, [int]$min, [int]$max){
    if ($v -lt $min){
        return $min
    }

    if ($v -gt $max){
        return $max
    }

    return $v
}

function New-Buffer([int]$w, [int]$h) {
    $buf = New-Object char[] (($w + 1) * $h)

    for ($y = 0; $y -lt $h; $y++){
        $line_start = $y * ($w + 1)
        for ($x = 0; $x -lt $w; $x++){
        $buf[$line_start + $x] = " "
            
        }
        $buf[$line_start + $w] = "`n"
    }

    Write-Output $buf -NoEnumerate
}

function Put-Text([char[]]$buf, [int]$x, [int]$y, [string]$text){
    $w = [Console]::WindowWidth

    if ($x+($y*$w) -ge $buf.Count){
        return
    }
    
    $stride = $w + 1
    $i = ($y * $stride) + $x
    $max = ($y+1) * $stride - 1
    foreach ($ch in $text.ToCharArray()){
        if ($i -ge $max){ break }
        $buf[$i++] = $ch
    }
}

function Render-Search ($stdin_buffer, [char[]]$screen_buffer) {
    $height = 3
    $width = [int](Clamp ([int]([Console]::WindowWidth * 0.6)) 30 300)

    $tl = '┌'; $bl = '└'; $tr = '┐'; $br = '┘'; $v = '│'; $h = '─'

    $padX = [int](([Console]::WindowWidth-$width)/2)
    $padY = 2
    
    Put-Text $screen_buffer $padX $padY $($tl + ($h*($width-2)) + $tr)

    for ($i = 1; $i -lt $height-1; $i++){
        Put-Text $screen_buffer $padX ($padY+$i) ($v + $stdin_buffer + (' '*($width-($stdin_buffer.Length)-2)) + $v)
    }

    Put-Text $screen_buffer $padX ($padY+$height-1) ($bl + ($h*($width-2)) + $br)
}

function Render-SearchResults([char[]]$screen_buffer, $height, $results, $scroll_offset, $selected_index) {
    $windowWidth = [Console]::WindowWidth
    $windowHeight = [Console]::WindowHeight

    
    $width = [int](Clamp ([int]([Console]::WindowWidth * 0.6)) 30 300)

    $tl = '┌'; $bl = '└'; $tr = '┐'; $br = '┘'; $v = '│'; $h = '─'

    $padX = [int](([Console]::WindowWidth-$width)/2)
    $padY = 7

    Put-Text $screen_buffer $padX $padY ($tl + ($h*($width-2)) + $tr)

    for ($i = 0; $i -lt $results_panel_height; $i++){
        if ($results[($scroll_offset+$i)] -ne $null){
            $trimmed_result_name = $results[($scroll_offset+$i)].display_name.Substring(0, [Math]::Min($width - 2, $results[($scroll_offset+$i)].display_name.Length))
        } else {
            $trimmed_result_name = ""
        }
        if ($i -eq [Math]::Min($selected_index, $height-1)){
            Put-Text $screen_buffer $padX ($padY+$i+1) ($v + "`e[97;44m" + $trimmed_result_name + (' '*([Math]::Max(0,$width-($trimmed_result_name.Length)-2))) + "`e[0m" + $v)
        } else {
            Put-Text $screen_buffer $padX ($padY+$i+1) ($v + $trimmed_result_name + (' '*([Math]::Max(0, $width-($trimmed_result_name.Length)-2))) + $v)
        }
    }

    Put-Text $screen_buffer $padX ($padY+$results_panel_height+1) ($bl + ($h*($width-2)) + $br)
}


$esc = [char]27
$w = [Console]::WindowWidth
$h = [Console]::WindowHeight-1

$buf = New-Buffer $w $h

$searchResults = $list_items

$stdin_buffer = ""
$selected_index = 0
$scroll_offset = 0

$filteredResults = $searchResults

$results_panel_height = [Console]::WindowHeight-12

$trimmed_results_count = [Math]::Min($filteredResults.Count, $results_panel_height) #[Console]::WindowHeight-12)

$lastKeyPress = [DateTime]::UtcNow

while ($true){
    if ($w -eq [Console]::WindowWidth -and $h -eq [Console]::WindowHeight-1){
        # Clear Buffer
        for ($i = 0; $i -lt $buf.Length; $i++){
            if ($buf[$i] -ne "`n") { $buf[$i] = ' ' }
        }
    } else {
        # Resize
        $w = [Console]::WindowWidth
        $h = [Console]::WindowHeight-1
        $buf = New-Buffer $w $h
    }

    # User Input
    while ([Console]::KeyAvailable){
        $key = [Console]::ReadKey($true)
        
        switch ($key.Key){
            'Backspace' {$stdin_buffer = $stdin_buffer.Substring(0, [Math]::Max(0, $stdin_buffer.Length-1))}
            'UpArrow' {
                if ($selected_index -le ([int]($results_panel_height*0.3)) -and ($scroll_offset) -gt 0){
                    $scroll_offset -= 1
                } else {
                    $selected_index = [Math]::Max(0, $selected_index-1)
                }
            }
            'DownArrow' {
                if ($selected_index -ge ([int]($results_panel_height*0.6)) -and ($scroll_offset+$results_panel_height) -lt $filteredResults.Count){
                    $scroll_offset += 1
                } else {
                    if (($scroll_offs + $selected_index) -lt $trimmed_results_count-1){
                        $selected_index = $selected_index+1
                    }
                }
            }
            'Enter' {
                return $filteredResults[([int]($scroll_offset+$selected_index))].id
            }
            'Escape' {
                return $null
            }
            default { $scroll_offset = 0; $selected_index = 0; $stdin_buffer += $key.KeyChar }
        }
            
        $pattern = [WildcardPattern]::Escape($stdin_buffer)
        $filteredResults = @( $searchResults | Where-Object {$_.display_name -like "*$pattern*"} )
        $trimmed_results_count = [Math]::Min($filteredResults.Count, $results_panel_height) #[Console]::WindowHeight-12)
    }

    Render-Search $stdin_buffer $buf
    Render-SearchResults $buf $trimmed_results_count $filteredResults $scroll_offset $selected_index

    
    [Console]::Write("`e[?25l") # Hide Cursor

    [Console]::SetCursorPosition(0, 0)
    [Console]::Write([string]::new($buf))

    Start-Sleep -Milliseconds 16
}
