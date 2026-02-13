[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$message,

    [bool]$user_input = $false
)

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
    $rowEndExclusive = ($y * $stride) + $bufW
    $bufLen = $buf.Length

    foreach ($ch in $text.ToCharArray()){
        if ($i -lt 0 -or $i -ge $bufLen) { break }
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

function Wrap-Words([string]$text, [int]$maxWidth){
    $lines = New-Object System.Collections.Generic.List[string]
    if ($maxWidth -le 1){
        $lines.Add((Fit-Text $text $maxWidth))
        return $lines
    }

    $words = $text -split '\s+'
    $cur = ""

    foreach ($word in $words){
        if ($cur.Length -eq 0){
            $cur = $word
        } elseif (($cur.Length + 1 + $word.Length) -le $maxWidth){
            $cur = "$cur $word"
        } else {
            $lines.Add($cur)
            $cur = $word
        }
    }
    if ($cur.Length -gt 0){ $lines.Add($cur) }
    return $lines
}

# Overlays are drawn AFTER the buffer is written, so ANSI codes never affect layout
$script:Overlays = @()
function Add-Overlay([int]$x, [int]$y, [string]$text, [string]$ansi){
    $script:Overlays += [pscustomobject]@{ X=$x; Y=$y; Text=$text; Ansi=$ansi }
}

function Render-MessageBox([char[]]$buf, [int]$w, [int]$h, [int]$selected_index){
    $script:Overlays = @()

    if ($w -lt 12 -or $h -lt 3){
        Put-Text $buf $w $h 0 0 (Fit-Text "Too small" $w)
        return
    }

    $tl='┌'; $tr='┐'; $bl='└'; $br='┘'; $v='│'; $hh='─'

    $minWForBox = 24
    $minHForBox = if ($user_input) { 9 } else { 7 }
    $useBox = ($w -ge $minWForBox -and $h -ge $minHForBox)

    if (-not $useBox){
        # --- Compact mode ---
        Put-Text $buf $w $h 0 0 (Fit-Text "Message" $w)

        $reservedLines = if ($user_input) { 3 } else { 2 }
        $maxMsgLines = [Math]::Max(1, $h - $reservedLines)

        $wrapped = Wrap-Words $message $w
        $show = [Math]::Min($wrapped.Count, $maxMsgLines)

        for ($i=0; $i -lt $show; $i++){
            Put-Text $buf $w $h 0 (1 + $i) (Fit-Text $wrapped[$i] $w)
        }

        if ($user_input){
            $yesPlain = "[Yes]"
            $noPlain  = "[No]"
            $linePlain = "$yesPlain   $noPlain"
            $x = [int](($w - $linePlain.Length)/2)
            $y = $h-1

            Put-Text $buf $w $h $x $y $linePlain

            # Overlay highlight on the selected token only
            if ($selected_index -eq 0){
                Add-Overlay $x $y $yesPlain "`e[97;44m"
            } else {
                Add-Overlay ($x + $yesPlain.Length + 3) $y $noPlain "`e[97;44m"
            }
        } else {
            Put-Text $buf $w $h 0 ($h-1) (Fit-Text "Press Enter" $w)
        }
        return
    }

    # --- Box mode ---
    $width = Clamp ([int]($w * 0.7)) 24 ($w - 2)
    $innerMaxW = [Math]::Max(1, $width - 4)
    $wrapped = Wrap-Words $message $innerMaxW

    $extraLines = if ($user_input) { 6 } else { 5 }
    $minBoxHeight = if ($user_input) { 9 } else { 7 }
    $desiredHeight = $wrapped.Count + $extraLines
    $height = Clamp $desiredHeight $minBoxHeight ($h - 2)

    $padX = [int](($w - $width) / 2)
    $padY = [int](($h - $height) / 2)
    if ($padX -lt 0) { $padX = 0 }
    if ($padY -lt 0) { $padY = 0 }

    if ($padX + $width  -gt $w) { $width  = [Math]::Max(1, $w - $padX) }
    if ($padY + $height -gt $h) { $height = [Math]::Max(1, $h - $padY) }
    if ($width -lt 3 -or $height -lt 3){
        Put-Text $buf $w $h 0 0 (Fit-Text "Too small" $w)
        return
    }

    Put-Text $buf $w $h $padX $padY ($tl + ($hh * ($width - 2)) + $tr)
    for ($iy = 1; $iy -lt ($height - 1); $iy++){
        Put-Text $buf $w $h $padX ($padY + $iy) ($v + (' ' * ($width - 2)) + $v)
    }
    Put-Text $buf $w $h $padX ($padY + $height - 1) ($bl + ($hh * ($width - 2)) + $br)

    $title = "Message"
    $titleX = $padX + [int](($width - $title.Length) / 2)
    Put-Text $buf $w $h $titleX ($padY + 1) $title

    $msgStartY = $padY + 3
    $maxMsgLines = [Math]::Max(1, ($height - $extraLines))
    $showLines = [Math]::Min($wrapped.Count, $maxMsgLines)

    for ($i=0; $i -lt $showLines; $i++){
        $t = Fit-Text $wrapped[$i] $innerMaxW
        $x = $padX + 2 + [int](($innerMaxW - $t.Length) / 2)
        Put-Text $buf $w $h $x ($msgStartY + $i) $t
    }

    if ($user_input){
        # Draw plain button text into buffer so layout is correct
        $yesPlain = "[ Yes ]"
        $noPlain  = "[ No  ]"
        $btnLinePlain = "$yesPlain   $noPlain"

        $btnX = $padX + [int](($width - $btnLinePlain.Length) / 2)
        $btnY = $padY + $height - 3

        Put-Text $buf $w $h $btnX $btnY $btnLinePlain
        Put-Text $buf $w $h ($padX + 2) ($padY + $height - 2) (Fit-Text "←/→ choose, Enter confirm" ($width - 4))

        # Overlay highlight (ANSI) WITHOUT putting it in the buffer
        if ($selected_index -eq 0){
            Add-Overlay $btnX $btnY $yesPlain "`e[97;44m"
        } else {
            Add-Overlay ($btnX + $yesPlain.Length + 3) $btnY $noPlain "`e[97;44m"
        }
    } else {
        Put-Text $buf $w $h ($padX + 2) ($padY + $height - 2) (Fit-Text "Press Enter to continue" ($width - 4))
    }
}

# --- main ---
$selected_index = 0

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

    while ([Console]::KeyAvailable){
        $key = [Console]::ReadKey($true)
        switch ($key.Key){
            'LeftArrow'  { if ($user_input -and $selected_index -gt 0){ $selected_index-- } }
            'RightArrow' { if ($user_input -and $selected_index -lt 1){ $selected_index++ } }
            'Enter'      { return $selected_index }
            'Escape'     { if ($user_input) { return 1 } else { return 0 } }
            'Y'          { if ($user_input) { return 0 } }
            'N'          { if ($user_input) { return 1 } }
        }
    }

    Render-MessageBox $buf $w $h $selected_index

    try {
        [Console]::Write("`e[?25l")
        [Console]::SetCursorPosition(0, 0)

        # Write base frame (no ANSI in buffer)
        $s = [string]::new($buf)
        $maxLen = ($w + 1) * $h
        if ($s.Length -gt $maxLen){
            $s = $s.Substring(0, $maxLen)
        }
        [Console]::Write($s)

        # Overlay ANSI highlights (doesn't affect layout)
        foreach ($o in $script:Overlays){
            if ($o.Y -ge 0 -and $o.Y -lt $h -and $o.X -ge 0 -and $o.X -lt $w){
                [Console]::SetCursorPosition($o.X, $o.Y)
                [Console]::Write($o.Ansi + $o.Text + "`e[0m")
            }
        }
    } catch {
        # ignore resize races
    }

    Start-Sleep -Milliseconds 16
}
