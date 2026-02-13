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

    Write-Output $buf -NoEnumerate
}

function Put-Text([char[]]$buf, [int]$x, [int]$y, [string]$text){
    $w = [Math]::Max([Console]::WindowWidth, 100)
    $stride = $w + 1
    $i = ($y * $stride) + $x
    $max = ($y+1) * $stride - 1
    foreach ($ch in $text.ToCharArray()){
        if ($i -ge $max){ break }
        $buf[$i++] = $ch
    }
}

function Render-MenuItems([char[]]$screen_buffer, $menu_items, $selected_index) {
    $windowWidth = [Math]::Max([Console]::WindowWidth, 100)
    $windowHeight = [Math]::Max([Console]::WindowHeight, 50)

    $w = [Math]::Max($window, 100)
    $h = [Math]::Max($h, 50)

    
    
    $width = [int](Clamp ([int]([Console]::WindowWidth * 0.6)) 30 300)
    $height = ($menu_items.Count*3)+2

    $tl = '┌'; $bl = '└'; $tr = '┐'; $br = '┘'; $v = '│'; $h = '─'

    $padX = [int](($windowWidth-$width)/2)
    $padY = [int](($windowHeight-$height)/2)

    $title = "Sentinel Analytics Change Control Manager"
    Put-Text $screen_buffer ([int](($windowWidth-$title.Length)/2)) ([int]($padY-2)) $title
    Put-Text $screen_buffer $padX $padY ($tl + ($h*($width-2)) + $tr)

    for ($i = 0; $i -lt $menu_items.Count; $i++){
        if ($i -eq [Math]::Min($selected_index, $height-1)){
            Put-Text $screen_buffer $padX ($padY+($i*3)+1) ($v + "`e[97;44m" + (' '*($width-2)) + "`e[0m" + $v)
            Put-Text $screen_buffer $padX ($padY+($i*3)+2) ($v + "`e[97;44m" + ' ' + $menu_items[$i] + (' '*($width-($menu_items[$i].Length)-3)) + "`e[0m" + $v)
            Put-Text $screen_buffer $padX ($padY+($i*3)+3) ($v + "`e[97;44m" + (' '*($width-2)) + "`e[0m" + $v)
        } else {
            Put-Text $screen_buffer $padX ($padY+($i*3)+1) ($v + (' '*($width-2)) + $v)
            Put-Text $screen_buffer $padX ($padY+($i*3)+2) ($v + ' ' + $menu_items[$i] + (' '*($width-($menu_items[$i].Length)-3)) + $v)
            Put-Text $screen_buffer $padX ($padY+($i*3)+3) ($v + (' '*($width-2)) + $v)
        }
    }

    Put-Text $screen_buffer $padX ($padY+$height-1) ($bl + ($h*($width-2)) + $br)
}


$esc = [char]27
$w = [Console]::WindowWidth
$h = [Console]::WindowHeight-1

$buf = New-Buffer $w $h

$selected_index = 0

$menu_items = @("Stage Analytic", "Checkout Analytic", "Restore Analytic from Version Control", "Quit")


while ($true){
    $windowWidth = [Math]::Max([Console]::WindowWidth, 100)
    $windowHeight = [Math]::Max([Console]::WindowWidth, 50)
    if ($w -eq $windowWidth -and $h -eq $windowWidth-1){
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
            'UpArrow' {
                if ($selected_index -gt 0){
                    $selected_index-=1
                }
            }
            'DownArrow' {
                if ($selected_index -lt $menu_items.Count-1){
                    $selected_index+=1
                }
            }
            'Enter' {
                return $selected_index+1
            }
        }
    }

    # Render-Search $stdin_buffer $buf
    Render-MenuItems $buf $menu_items $selected_index

    
    [Console]::Write("`e[?25l") # Hide Cursor

    [Console]::SetCursorPosition(0, 0)

    $buf_string = [string]::new($buf)
    $scaled_buffer_size = (($w + 1) * $h)
    if ($buf_string.Length -gt $scaled_buffer_size){
       # Trim To Size
       $buf_string = $buf_string.Substring(0, $scaled_buffer_size-1)
    }

    
    [Console]::Write($buf_string)

    Start-Sleep -Milliseconds 16
}
