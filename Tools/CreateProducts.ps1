# Creates AeroStrike's game passes and developer products via Open Cloud.
# Reads ROBLOX_API_KEY from .env inside this script only (never printed).
# Output: Tools/products.json  (key -> { kind, id })
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$universe = 10777495043
$envLine = Get-Content (Join-Path $Root '.env') | Where-Object { $_ -match '^\s*ROBLOX_API_KEY\s*=' } | Select-Object -First 1
$key = ($envLine -split '=', 2)[1].Trim()
$icons = Join-Path $Root 'Assets\Icons'
$items = @(
  @{ k='WraithX';     kind='pass';    name='Wraith-X Stealth Ace'; price=799; desc='Unlock the Wraith-X stealth fighter: top speed 1,250 km/h and Low Observable (enemies take 40% longer to lock you).' },
  @{ k='MultiLock';   kind='pass';    name='Multi-Lock Missiles';  price=499; desc='Lock up to 4 targets at once with +25% missile tracking. Every missile can still be dodged with flares.' },
  @{ k='Afterburner'; kind='pass';    name='Afterburner Pass';     price=349; desc='Afterburner burns 60% less fuel and fuel rings refill twice as fast.' },
  @{ k='GSuitPro';    kind='pass';    name='G-Suit Pro';           price=299; desc='+3G before the vignette kicks in and no G-blackout.' },
  @{ k='FlarePod';    kind='pass';    name='Extra Flare Pod';      price=199; desc='+4 flares on every jet you fly.' },
  @{ k='DoubleCash';  kind='pass';    name='2x Cash';              price=399; desc='Double Cash from every kill, mission and reward. Forever.' },
  @{ k='VIP';         kind='pass';    name='VIP Pilot';            price=249; desc='Gold name tag, exclusive gold contrail and +10% Ace XP.' },
  @{ k='StarterAce';  kind='product'; name='Starter Ace Bundle';   price=99;  desc='Viper IX unlock + 5,000 Cash + Rookie Ace paint. One per pilot.' },
  @{ k='CashS';       kind='product'; name='Cash Crate S';         price=75;  desc='5,000 Cash.' },
  @{ k='CashM';       kind='product'; name='Cash Crate M';         price=299; desc='25,000 Cash.' },
  @{ k='CashL';       kind='product'; name='Cash Crate L';         price=899; desc='100,000 Cash.' },
  @{ k='Rearm';       kind='product'; name='Instant Rearm';        price=25;  desc='Refill missiles, flares and fuel mid-air.' },
  @{ k='BountyShield';kind='product'; name='Bounty Shield';        price=49;  desc='Keep 100% of your Sortie Cash the next time you are shot down.' }
)
$out = [ordered]@{}
foreach ($it in $items) {
  $url = if ($it.kind -eq 'pass') { "https://apis.roblox.com/game-passes/v1/universes/$universe/game-passes" } else { "https://apis.roblox.com/developer-products/v2/universes/$universe/developer-products" }
  $img = Join-Path $icons ($it.k + '.png')
  $resp = & curl.exe -s -X POST $url -H "x-api-key: $key" `
    --form-string "name=$($it.name)" --form-string "description=$($it.desc)" `
    --form-string "price=$($it.price)" --form-string "isForSale=true" `
    -F "imageFile=@$img;type=image/png"
  try { $j = $resp | ConvertFrom-Json } catch { $j = $null }
  $id = if ($j) { if ($j.gamePassId) { $j.gamePassId } elseif ($j.productId) { $j.productId } elseif ($j.id) { $j.id } else { $null } } else { $null }
  if ($id) { $out[$it.k] = @{ kind = $it.kind; id = $id; price = $it.price }; "OK   $($it.k) -> $id" }
  else { "FAIL $($it.k): $($resp.Substring(0, [Math]::Min(300, $resp.Length)))" }
  Start-Sleep -Milliseconds 400
}
$out | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 (Join-Path $Root 'Tools\products.json')
Remove-Variable key
