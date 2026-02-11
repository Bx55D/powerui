<# 
Responsive PowerShell TUI w/ Live Search + Low-Flicker Diff Renderer (pure PowerShell)
Keys:
  - Type to search
  - Backspace deletes
  - Up/Down to move
  - Enter selects
  - Ctrl+L clears search
  - Esc quits
#>

Set-StrictMode -Version Latest

# ---------- Helpers ----------
function Clamp([int]$v, [int]$min, [int]$max) {
    if ($v -lt $min) { return $min }
    if ($v -gt $max) { return $max }
    return $v
}
function Safe([string]$s) { if ($null -eq $s) { "" } else { $s } }
function PadOrTrim([string]$s, [int]$w) {
    $s = Safe $s
    if ($w -le 0) { return "" }
    if ($s.Length -gt $w) { return $s.Substring(0, $w) }
    return $s.PadRight($w)
}

# Faster single-line write (no Clear(), no full repaint)
function WriteLineAt([int]$y, [string]$text, [ConsoleColor]$fg, [ConsoleColor]$bg) {
    if ($y -lt 0 -or $y -ge [Console]::WindowHeight) { return }
    $oldFg = [Console]::ForegroundColor
    $oldBg = [Console]::BackgroundColor
    [Console]::ForegroundColor = $fg
    [Console]::BackgroundColor = $bg
    try {
        [Console]::SetCursorPosition(0, $y)
        [Console]::Write($text)
    } catch {
        # ignore transient resize/cursor exceptions
    } finally {
        [Console]::ForegroundColor = $oldFg
        [Console]::BackgroundColor = $oldBg
    }
}

function Matches([string]$text, [string]$query) {
    if ([string]::IsNullOrWhiteSpace($query)) { return $true }
    return ($text -like "*$query*") # case-insensitive by default
}

# ---------- App State ----------
$Title  = "PowerShell Responsive TUI"
$Status = "Type to search. Ctrl+L clears."
$AllItems = @(
    "Dashboard",
    "Processes",
    "Services",
    "Network",
    "Disk",
    "Logs",
    "Settings",
    "About",
    "Exit"
)

$Query = ""
$Selected = 0
$Scroll = 0

$LastW = [Console]::WindowWidth
$LastH = [Console]::WindowHeight

# Diff buffer (previous frame)
[string[]]$LastFrame = @()

# ---------- Layout ----------
function Get-Layout {
    $w = [Console]::WindowWidth
    $h = [Console]::WindowHeight

    $searchY = 2
    $listTop = 4
    $listBottom = $h - 3
    $listH = [Math]::Max(0, $listBottom - $listTop + 1)

    [pscustomobject]@{
        W = $w
        H = $h
        HeaderY = 0
        Divider1Y = 1
        SearchY = $searchY
        Divider2Y = 3
        ListTop = $listTop
        ListH = $listH
        StatusY = $h - 2
        FooterY = $h - 1
    }
}

# ---------- Frame Builder ----------
# Build arrays of "runs" per line so we can colorize without repainting the whole screen.
# Each line is a list of segments: @{ Text="..."; Fg=...; Bg=... }
function New-Segment([string]$text, [ConsoleColor]$fg, [ConsoleColor]$bg) {
    [pscustomobject]@{ Text=$text; Fg=$fg; Bg=$bg }
}

function Build-Frame {
    param(
        [string]$title,
        [string]$status,
        [string[]]$filteredItems,
        [int]$selected,
        [int]$scroll,
        [string]$query
    )

    $layout = Get-Layout
    $w = $layout.W
    $h = $layout.H

    # Prepare output: one list per row (segments)
    $rows = New-Object 'System.Collections.Generic.List[object]' $h
    for ($i = 0; $i -lt $h; $i++) { $rows.Add(@()) }

    # Header
    $hdr = " $title "
    $right = " {0}x{1} " -f $w, $h
    $fill = [Math]::Max(0, $w - $hdr.Length - $right.Length)
    $line = PadOrTrim ($hdr + (" " * $fill) + $right) $w
    $rows[$layout.HeaderY] = @( New-Segment $line ([ConsoleColor]::Black) ([ConsoleColor]::White) )

    # Dividers
    $div = PadOrTrim ("-" * $w) $w
    $rows[$layout.Divider1Y] = @( New-Segment $div ([ConsoleColor]::DarkGray) ([ConsoleColor]::Black) )
    $rows[$layout.Divider2Y] = @( New-Segment $div ([ConsoleColor]::DarkGray) ([ConsoleColor]::Black) )

    # Search bar
    $prompt = " Search: "
    $visibleQueryWidth = [Math]::Max(0, $w - $prompt.Length - 1)
    $q = Safe $query
    $qShown = if ($q.Length -gt $visibleQueryWidth) { $q.Substring($q.Length - $visibleQueryWidth) } else { $q }
    $searchLine = PadOrTrim ($prompt + $qShown) $w
    $rows[$layout.SearchY] = @( New-Segment $searchLine ([ConsoleColor]::Black) ([ConsoleColor]::Gray) )

    # List
    $listH = $layout.ListH
    $count = $filteredItems.Count
    $maxIndex = [Math]::Max(0, $count - 1)
    $selected = Clamp $selected 0 $maxIndex

    if ($listH -gt 0) {
        if ($selected -lt $scroll) { $scroll = $selected }
        if ($selected -ge ($scroll + $listH)) { $scroll = $selected - $listH + 1 }
        $scroll = Clamp $scroll 0 ([Math]::Max(0, $count - $listH))

        for ($row = 0; $row -lt $listH; $row++) {
            $idx = $scroll + $row
            $y = $layout.ListTop + $row

            if ($idx -lt $count) {
                $prefix = if ($idx -eq $selected) { "▶ " } else { "  " }
                $txt = PadOrTrim ($prefix + $filteredItems[$idx]) $w

                if ($idx -eq $selected) {
                    $rows[$y] = @( New-Segment $txt ([ConsoleColor]::White) ([ConsoleColor]::DarkBlue) )
                } else {
                    $rows[$y] = @( New-Segment $txt ([ConsoleColor]::Gray) ([ConsoleColor]::Black) )
                }
            } else {
                $rows[$y] = @( New-Segment (PadOrTrim "" $w) ([ConsoleColor]::Gray) ([ConsoleColor]::Black) )
            }
        }
    }

    # Status + footer
    $statusLine = PadOrTrim (" " + (Safe $status)) $w
    $rows[$layout.StatusY] = @( New-Segment $statusLine ([ConsoleColor]::Black) ([ConsoleColor]::Gray) )

    $help = " Type to search | ↑/↓ Navigate | Enter Select | Ctrl+L Clear | Esc Quit "
    $rows[$layout.FooterY] = @( New-Segment (PadOrTrim $help $w) ([ConsoleColor]::Black) ([ConsoleColor]::DarkGray) )

    [pscustomobject]@{
        Rows = $rows
        Selected = $selected
        Scroll = $scroll
        W = $w
        H = $h
    }
}

# ---------- Diff Renderer ----------
function Render-FrameDiff {
    param(
        $frame,
        [ref]$lastFrameText
    )
    $h = $frame.H
    $w = $frame.W

    # Flatten each row's segments into a single string for diffing,
    # but still keep segments for colored output when changed.
    $newText = New-Object string[] $h

    for ($y = 0; $y -lt $h; $y++) {
        $segments = $frame.Rows[$y]
        $sb = New-Object System.Text.StringBuilder
        foreach ($seg in $segments) { [void]$sb.Append($seg.Text) }
        $line = PadOrTrim $sb.ToString() $w
        $newText[$y] = $line
    }

    $oldText = $lastFrameText.Value
    $needFull = $false

    # If size changed, old buffer mismatch -> redraw everything
    if ($null -eq $oldText -or $oldText.Count -ne $h) { $needFull = $true }

    for ($y = 0; $y -lt $h; $y++) {
        $changed = $needFull -or ($oldText[$y] -ne $newText[$y])
        if (-not $changed) { continue }

        # Redraw this row with its segments (preserves colors).
        # (We assume our segments already add up to <= width.)
        try { [Console]::SetCursorPosition(0, $y) } catch { continue }

        foreach ($seg in $frame.Rows[$y]) {
            $oldFg = [Console]::ForegroundColor
            $oldBg = [Console]::BackgroundColor
            [Console]::ForegroundColor = $seg.Fg
            [Console]::BackgroundColor = $seg.Bg
            try { [Console]::Write($seg.Text) } catch { break }
            finally { [Console]::ForegroundColor = $oldFg; [Console]::BackgroundColor = $oldBg }
        }

        # Ensure the line is fully filled (in case segments shorter than width)
        $remaining = $w - ($newText[$y].Length)
        if ($remaining -gt 0) {
            WriteLineAt $y (PadOrTrim $newText[$y] $w) ([ConsoleColor]::Gray) ([ConsoleColor]::Black)
        }
    }

    $lastFrameText.Value = $newText
}

# ---------- Actions ----------
function Handle-Selection([string]$item) {
    switch ($item) {
        "Dashboard" { return "Opened Dashboard (demo)." }
        "Processes" { 
            $p = Get-Process | Sort-Object CPU -Descending | Select-Object -First 1
            return "Top CPU: $($p.ProcessName) (CPU=$([Math]::Round($p.CPU,2)))"
        }
        "Services"  { 
            $s = Get-Service | Where-Object Status -eq Running | Select-Object -First 1
            return "Example running service: $($s.DisplayName)"
        }
        "About"     { return "Diff-rendered UI (less flicker), still pure PowerShell." }
        "Exit"      { return "__EXIT__" }
        default     { return "Selected: $item" }
    }
}

# ---------- Main Loop ----------
$oldCursorVisible = [Console]::CursorVisible
[Console]::CursorVisible = $false

try {
    # Avoid a visible flash on start: do one full size-appropriate clear
    try { [Console]::Clear() } catch { }

    while ($true) {
        # Build filtered list
        $filtered = @($AllItems | Where-Object { Matches $_ $Query })

        if ($filtered.Count -eq 0) {
            $Selected = 0
            $Scroll = 0
        } else {
            $Selected = Clamp $Selected 0 ($filtered.Count - 1)
        }

        # Detect resize
        $w = [Console]::WindowWidth
        $h = [Console]::WindowHeight
        $resized = ($w -ne $LastW -or $h -ne $LastH)
        if ($resized) {
            $LastW = $w
            $LastH = $h
            # Clear once on resize to avoid leftover artifacts outside new frame
            try { [Console]::Clear() } catch { }
            $LastFrame = @() # force full redraw next diff
        }

        # Build frame and diff-render it
        $frame = Build-Frame -title $Title -status $Status -filteredItems $filtered -selected $Selected -scroll $Scroll -query $Query
        $Selected = $frame.Selected
        $Scroll   = $frame.Scroll
        Render-FrameDiff -frame $frame -lastFrameText ([ref]$LastFrame)

        # Input
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                "UpArrow"   { $Selected--; continue }
                "DownArrow" { $Selected++; continue }
                "Escape"    { break }
                "Enter"     {
                    if ($filtered.Count -gt 0) {
                        $result = Handle-Selection $filtered[$Selected]
                        if ($result -eq "__EXIT__") { break }
                        $Status = $result
                    } else {
                        $Status = "No matches."
                    }
                    continue
                }
                "Backspace" {
                    if ($Query.Length -gt 0) {
                        $Query = $Query.Substring(0, $Query.Length - 1)
                        $Selected = 0
                        $Scroll = 0
                    }
                    continue
                }
            }

            if ($key.Modifiers -band [ConsoleModifiers]::Control -and $key.Key -eq "L") {
                $Query = ""
                $Selected = 0
                $Scroll = 0
                $Status = "Search cleared."
                continue
            }

            $ch = $key.KeyChar
            if ($ch -ne [char]0 -and -not [char]::IsControl($ch)) {
                $Query += $ch
                $Selected = 0
                $Scroll = 0
                continue
            }
        } else {
            Start-Sleep -Milliseconds 16
        }
    }
}
finally {
    try {
        [Console]::CursorVisible = $oldCursorVisible
        [Console]::ResetColor()
        [Console]::Clear()
    } catch { }
}

