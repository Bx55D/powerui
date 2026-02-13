[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$message,

    $user_input = $false
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
    $stride = $w + 1
    $i = ($y * $stride) + $x
    $max = ($y+1) * $stride - 1
    foreach ($ch in $text.ToCharArray()){
        if ($i -ge $max){ break }
        $buf[$i++] = $ch
    }
}

function Render-MessageBox([char[]]$screen_buffer, $selected_index) {
    $windowWidth = [Console]::WindowWidth
    $windowHeight = [Console]::WindowHeight    
    
    $width = [int](Clamp ([int]([Console]::WindowWidth * 0.6)) 30 300)
    $height = 16

    $tl = '┌'; $bl = '└'; $tr = '┐'; $br = '┘'; $v = '│'; $h = '─'

    $padX = [int](([Console]::WindowWidth-$width)/2)
    $padY = [int](([Console]::WindowHeight-$height)/2)

    Put-Text $screen_buffer $padX $padY ($tl + ($h*($width-2)) + $tr)

    for ($i = 1; $i -lt $height; $i++){
        Put-Text $screen_buffer $padX ($padY+$i) ($v + (' '*($width-2)) + $v)
    }

    Put-Text $screen_buffer $padX ($padY+$height) ($bl + ($h*($width-2)) + $br)

    $textPadX = [int](([Console]::WindowWidth-$message.Length)/2)

    Put-Text $screen_buffer $textPadX ([int]([Console]::WindowHeight/2)) $message

    if ($user_input){
        $prompt_affirm_string = if ($selected_index -eq 0){ "[Yes]" } else { "Yes" }
        $prompt_negative_string = if ($selected_index -eq 1){ "[No]" } else { "No" }

        $option_spacing = ([int]($width/3))

        Put-Text $screen_buffer ($padX + ([int]($width/3)) - 3) ($padY + $height - 3) ($prompt_affirm_string + (" "*$option_spacing) + $prompt_negative_string)
    }
}


$esc = [char]27
$w = [Console]::WindowWidth
$h = [Console]::WindowHeight-1

$buf = New-Buffer $w $h

$selected_index = 0

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
            'LeftArrow' {
                if ($selected_index -gt 0){
                    $selected_index-=1
                }
            }
            'RightArrow' {
                if ($selected_index -lt 1){
                    $selected_index+=1
                }
            }
            'Enter' {
                return $selected_index
            }
        }
    }

    # Render-Search $stdin_buffer $buf
    Render-MessageBox $buf $selected_index

    
    [Console]::Write("`e[?25l") # Hide Cursor

    [Console]::SetCursorPosition(0, 0)
    [Console]::Write([string]::new($buf))

    Start-Sleep -Milliseconds 16
}
