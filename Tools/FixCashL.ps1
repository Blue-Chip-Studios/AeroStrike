param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$envLine = Get-Content (Join-Path $Root '.env') | Where-Object { $_ -match '^\s*ROBLOX_API_KEY\s*=' } | Select-Object -First 1
$key = ($envLine -split '=', 2)[1].Trim()
$img = Join-Path $Root 'Assets\Icons\CashL.png'
$r = & curl.exe -s -w "`nHTTP %{http_code}" -X POST "https://apis.roblox.com/developer-products/v2/universes/10777495043/developer-products" -H "x-api-key: $key" --form-string "name=Cash Crate XL" --form-string "description=100,000 Cash." --form-string "price=899" --form-string "isForSale=true" -F "imageFile=@$img;type=image/png"
Remove-Variable key
$r
