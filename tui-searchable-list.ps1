# User Input
while ([Console]::KeyAvailable){
    $key = [Console]::ReadKey($true)

    $searchChanged = $false

    switch ($key.Key){
        'Backspace' {
            if ($stdin_buffer.Length -gt 0){
                $stdin_buffer = $stdin_buffer.Substring(0, $stdin_buffer.Length-1)
                $searchChanged = $true
            }
        }

        'UpArrow' {
            if ($selected_index -gt 0){
                $selected_index--
            } elseif ($scroll_offset -gt 0){
                $scroll_offset--
            }
        }

        'DownArrow' {
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
            if (-not [char]::IsControl($key.KeyChar)){
                $stdin_buffer += $key.KeyChar
                $searchChanged = $true
            }
        }
    }

    if ($searchChanged){
        $pattern = [WildcardPattern]::Escape($stdin_buffer)
        $filteredResults = @( $searchResults | Where-Object { $_.display_name -like "*$pattern*" } )
        $scroll_offset = 0
        $selected_index = 0
    }

    # After any key, clamp to current list/window
    $count = if ($filteredResults) { $filteredResults.Count } else { 0 }
    $visible = [Math]::Min($results_panel_height, $count)

    if ($visible -lt 1) { $scroll_offset = 0; $selected_index = 0 }
    else {
        $scroll_offset = [Math]::Max(0, [Math]::Min($scroll_offset, [Math]::Max(0, $count - $visible)))
        $selected_index = [Math]::Max(0, [Math]::Min($selected_index, $visible - 1))
    }
}
