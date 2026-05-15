#requires -Version 7.0

param(
	[string]$Path = (Join-Path $PSScriptRoot "closure-reasons.json"),
	[int]$MaxResults = 10
)

Set-StrictMode -Version Latest

function Get-PropertyValue
{
	param(
		[object]$Object,
		[string[]]$Names
	)

	foreach ($name in $Names)
	{
		$prop = $Object.PSObject.Properties |
			Where-Object { $_.Name -ieq $name } |
			Select-Object -First 1

		if ($null -ne $prop)
		{
			return $prop.Value
		}
	}

	return $null
}

function Get-ShortText
{
	param(
		[string]$Text,
		[int]$MaxLength = 100
	)

	if ([string]::IsNullOrWhiteSpace($Text))
	{
		return ""
	}

	$singleLine = ($Text -replace "\s+", " ").Trim()

	if ($singleLine.Length -le $MaxLength)
	{
		return $singleLine
	}

	return $singleLine.Substring(0, $MaxLength - 3) + "..."
}

function Import-ClosureReasons
{
	param(
		[string]$JsonPath
	)

	if (-not (Test-Path -LiteralPath $JsonPath))
	{
		throw "JSON file not found: $JsonPath"
	}

	$json = Get-Content -LiteralPath $JsonPath -Raw
	$data = $json | ConvertFrom-Json

	if ($null -ne (Get-PropertyValue -Object $data -Names @("closures", "reasons", "items")))
	{
		$rawItems = Get-PropertyValue -Object $data -Names @("closures", "reasons", "items")
	} else
	{
		$rawItems = $data
	}

	$items = foreach ($item in @($rawItems))
	{
		if ($item -is [string])
		{
			$body = $item
			$title = Get-ShortText -Text $body -MaxLength 80

			[pscustomobject]@{
				Title      = $title
				Category   = ""
				Tags       = ""
				Body       = $body
				SearchBlob = $body.ToLowerInvariant()
			}

			continue
		}

		$body = Get-PropertyValue -Object $item -Names @(
			"reason",
			"body",
			"template",
			"text",
			"closure"
		)

		if ([string]::IsNullOrWhiteSpace([string]$body))
		{
			continue
		}

		$title = Get-PropertyValue -Object $item -Names @(
			"title",
			"name",
			"id",
			"summary"
		)

		if ([string]::IsNullOrWhiteSpace([string]$title))
		{
			$title = Get-ShortText -Text ([string]$body) -MaxLength 80
		}

		$category = Get-PropertyValue -Object $item -Names @("category", "type")
		$tagsRaw = Get-PropertyValue -Object $item -Names @("tags")

		if ($null -eq $tagsRaw)
		{
			$tags = ""
		} elseif ($tagsRaw -is [array])
		{
			$tags = ($tagsRaw | ForEach-Object { [string]$_ }) -join ", "
		} else
		{
			$tags = [string]$tagsRaw
		}

		$searchBlob = (@(
				[string]$title,
				[string]$category,
				[string]$tags,
				[string]$body
			) -join "`n").ToLowerInvariant()

		[pscustomobject]@{
			Title      = [string]$title
			Category   = [string]$category
			Tags       = [string]$tags
			Body       = [string]$body
			SearchBlob = $searchBlob
		}
	}

	return @($items)
}

function Search-ClosureReasons
{
	param(
		[array]$Items,
		[string]$Query
	)

	if ([string]::IsNullOrWhiteSpace($Query))
	{
		return $Items
	}

	$terms = @(
		$Query.ToLowerInvariant() -split "\s+" |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
	)

	return @(
		foreach ($item in $Items)
		{
			$matched = $true

			foreach ($term in $terms)
			{
				if (-not $item.SearchBlob.Contains($term))
				{
					$matched = $false
					break
				}
			}

			if ($matched)
			{
				$item
			}
		}
	)
}

function Show-SearchScreen
{
	param(
		[string]$Query,
		[array]$Matches,
		[int]$SelectedIndex,
		[int]$MaxResults
	)

	Clear-Host

	Write-Host "SIEM Closure Reason Picker" -ForegroundColor Cyan
	Write-Host "Type to search. Use Up/Down to navigate. Enter selects. Esc exits. Ctrl+U clears search." -ForegroundColor DarkGray
	Write-Host ""
	Write-Host "Search: $Query" -ForegroundColor Yellow
	Write-Host ""

	if ($Matches.Count -eq 0)
	{
		Write-Host "No matching closure reasons found." -ForegroundColor Red
		return
	}

	$visibleCount = [Math]::Min($MaxResults, $Matches.Count)
	$halfWindow = [Math]::Floor($visibleCount / 2)

	$startIndex = $SelectedIndex - $halfWindow

	if ($startIndex -lt 0)
	{
		$startIndex = 0
	}

	if ($startIndex -gt ($Matches.Count - $visibleCount))
	{
		$startIndex = [Math]::Max(0, $Matches.Count - $visibleCount)
	}

	$endIndex = [Math]::Min($Matches.Count - 1, $startIndex + $visibleCount - 1)

	for ($i = $startIndex; $i -le $endIndex; $i++)
	{
		$item = $Matches[$i]
		$title = Get-ShortText -Text $item.Title -MaxLength 90
		$prefix = "{0,3}. " -f ($i + 1)

		if ($i -eq $SelectedIndex)
		{
			Write-Host "▶ $prefix$title" -ForegroundColor Black -BackgroundColor Cyan
		} else
		{
			Write-Host "  $prefix$title"
		}

		$meta = @()

		if (-not [string]::IsNullOrWhiteSpace($item.Category))
		{
			$meta += $item.Category
		}

		if (-not [string]::IsNullOrWhiteSpace($item.Tags))
		{
			$meta += "tags: $($item.Tags)"
		}

		if ($meta.Count -gt 0)
		{
			Write-Host "      $($meta -join ' | ')" -ForegroundColor DarkGray
		}
	}

	Write-Host ""
	Write-Host "$($Matches.Count) match(es)" -ForegroundColor DarkGray
}

function Resolve-TemplateVariables
{
	param(
		[string]$Template
	)

	$pattern = "{{\s*([A-Za-z_][A-Za-z0-9_]*)\s*}}"

	$variables = @(
		[regex]::Matches($Template, $pattern) |
			ForEach-Object { $_.Groups[1].Value } |
			Select-Object -Unique
	)

	if ($variables.Count -eq 0)
	{
		return $Template
	}

	Write-Host ""
	Write-Host "Template variables found:" -ForegroundColor Cyan

	$values = @{}

	foreach ($variable in $variables)
	{
		$values[$variable] = Read-Host "Enter value for '$variable'"
	}

	return [regex]::Replace(
		$Template,
		$pattern,
		[System.Text.RegularExpressions.MatchEvaluator]{
			param([System.Text.RegularExpressions.Match]$match)

			$name = $match.Groups[1].Value

			if ($values.ContainsKey($name))
			{
				return [string]$values[$name]
			}

			return $match.Value
		}
	)
}

function Copy-TextToClipboard
{
	param(
		[string]$Text
	)

	try
	{
		Set-Clipboard -Value $Text -ErrorAction Stop
		return $true
	} catch
	{
		# Continue to fallbacks below
	}

	try
	{
		if ($IsWindows)
		{
			$clip = Get-Command "clip.exe" -ErrorAction SilentlyContinue
			if ($clip)
			{
				$Text | & $clip.Source
				return $true
			}
		}

		if ($IsMacOS)
		{
			$pbcopy = Get-Command "pbcopy" -ErrorAction SilentlyContinue
			if ($pbcopy)
			{
				$Text | & $pbcopy.Source
				return $true
			}
		}

		if ($IsLinux)
		{
			$wlCopy = Get-Command "wl-copy" -ErrorAction SilentlyContinue
			if ($wlCopy)
			{
				$Text | & $wlCopy.Source
				return $true
			}

			$xclip = Get-Command "xclip" -ErrorAction SilentlyContinue
			if ($xclip)
			{
				$Text | & $xclip.Source -selection clipboard
				return $true
			}

			$xsel = Get-Command "xsel" -ErrorAction SilentlyContinue
			if ($xsel)
			{
				$Text | & $xsel.Source --clipboard --input
				return $true
			}
		}
	} catch
	{
		return $false
	}

	return $false
}

try
{
	$closureReasons = Import-ClosureReasons -JsonPath $Path
} catch
{
	Write-Error $_
	exit 1
}

if ($closureReasons.Count -eq 0)
{
	Write-Error "No closure reasons were loaded from: $Path"
	exit 1
}

$query = ""
$selectedIndex = 0
$selectedReason = $null

while ($null -eq $selectedReason)
{
	$matches = @(Search-ClosureReasons -Items $closureReasons -Query $query)

	if ($matches.Count -eq 0)
	{
		$selectedIndex = 0
	} elseif ($selectedIndex -ge $matches.Count)
	{
		$selectedIndex = $matches.Count - 1
	}

	Show-SearchScreen -Query $query -Matches $matches -SelectedIndex $selectedIndex -MaxResults $MaxResults

	$key = [Console]::ReadKey($true)

	if (($key.Modifiers -band [ConsoleModifiers]::Control) -and $key.Key -eq [ConsoleKey]::U)
	{
		$query = ""
		$selectedIndex = 0
		continue
	}

	switch ($key.Key)
	{
		"Escape"
		{
			Clear-Host
			Write-Host "No closure reason selected."
			exit 0
		}

		"Backspace"
		{
			if ($query.Length -gt 0)
			{
				$query = $query.Substring(0, $query.Length - 1)
				$selectedIndex = 0
			}
		}

		"UpArrow"
		{
			if ($matches.Count -gt 0)
			{
				if ($selectedIndex -le 0)
				{
					$selectedIndex = $matches.Count - 1
				} else
				{
					$selectedIndex--
				}
			}
		}

		"DownArrow"
		{
			if ($matches.Count -gt 0)
			{
				if ($selectedIndex -ge ($matches.Count - 1))
				{
					$selectedIndex = 0
				} else
				{
					$selectedIndex++
				}
			}
		}

		"Enter"
		{
			if ($matches.Count -gt 0)
			{
				$selectedReason = $matches[$selectedIndex]
			}
		}

		default
		{
			if (-not [char]::IsControl($key.KeyChar))
			{
				$query += $key.KeyChar
				$selectedIndex = 0
			}
		}
	}
}

Clear-Host

Write-Host "Selected:" -ForegroundColor Cyan
Write-Host $selectedReason.Title -ForegroundColor Yellow

$finalReason = Resolve-TemplateVariables -Template $selectedReason.Body
$copied = Copy-TextToClipboard -Text $finalReason

Write-Host ""
Write-Host "Closure reason:" -ForegroundColor Cyan
Write-Host ""
Write-Host $finalReason
Write-Host ""

if ($copied)
{
	Write-Host "Copied to clipboard." -ForegroundColor Green
} else
{
	Write-Host "Could not copy to clipboard, so the closure reason has been displayed above." -ForegroundColor Yellow
}
