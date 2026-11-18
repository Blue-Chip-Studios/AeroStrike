# Lists AeroStrike developer products (name, id, price). Key read from .env, never printed.
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$envLine = Get-Content (Join-Path $Root '.env') | Where-Object { $_ -match '^\s*ROBLOX_API_KEY\s*=' } | Select-Object -First 1
$key = ($envLine -split '=', 2)[1].Trim()
$r = & curl.exe -s "https://apis.roblox.com/developer-products/v2/universes/10777495043/developer-products/creator?pageSize=50" -H "x-api-key: $key"
Remove-Variable key
try { ($r | ConvertFrom-Json).developerProducts | ForEach-Object { "{0} | {1} | {2}" -f $_.name, $_.productId, $_.priceInformation.defaultPriceInRobux } } catch { $r.Substring(0, [Math]::Min(400, $r.Length)) }
