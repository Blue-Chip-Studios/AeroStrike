# Creates AeroStrike's badges via Open Cloud (legacy badges API).
# Reads ROBLOX_API_KEY from .env inside this script only (never printed). The key needs the
# "legacy-universe.badge:manage-and-spend-robux" permission for this experience.
#
# NEVER SPENDS ROBUX: every request sends expectedCost=0, so once today's free quota (5 per
# experience per UTC day) is used up Roblox refuses instead of charging. Re-run on later days
# and it carries on from where it stopped (badges already in Tools/badges.json are skipped).
#
# Output: Tools/badges.json (key -> id). Paste the ids into Config/BadgeConfig.luau (or ask Claude).
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$universe = 10777495043
$envLine = Get-Content (Join-Path $Root '.env') | Where-Object { $_ -match '^\s*ROBLOX_API_KEY\s*=' } | Select-Object -First 1
$key = ($envLine -split '=', 2)[1].Trim()
$icons = Join-Path $Root 'Assets\Icons\Badges\upload'
# most-earned first, so the free daily quota goes where most players will see it
$items = @(
  @{ k='Welcome';      name='Wheels Up';          desc='Launch off the carrier for the first time.' },
  @{ k='FirstKill';    name='Splash One';         desc='Shoot down your first enemy pilot.' },
  @{ k='MachOne';      name='Sound Barrier';      desc='Break Mach 1.' },
  @{ k='CarrierTrap';  name='Trapped';            desc='Catch the wire: land back on the carrier.' },
  @{ k='Ace';          name='Ace';                desc='Reach a 5-kill streak and wear the Ace Bounty.' },
  @{ k='MultiKill';    name='Triple Splash';      desc='Score three kills in one chain.' },
  @{ k='Fortress';     name='Fortress Breaker';   desc='Help bring down the Flying Fortress.' },
  @{ k='Viper';        name='Viper Pilot';        desc='Unlock the Viper IX.' },
  @{ k='BountyHunter'; name='Bounty Hunter';      desc='Shoot down an Ace and claim the bounty.' },
  @{ k='Rhino';        name='Rhino Pilot';        desc='Unlock the Rhino HX.' },
  @{ k='Mako';         name='Mako Pilot';         desc='Unlock the Mako SR-9.' },
  @{ k='Wraith';       name='Ghost in the Sky';   desc='Unlock the Wraith-X.' },
  @{ k='TopAce';       name='Top Ace';            desc='Finish in the daily Top Aces top 10.' },
  @{ k='Mastery';      name='Master Aviator';     desc='Reach mastery level 10 with any jet.' }
)
$jsonPath = Join-Path $Root 'Tools\badges.json'
$out = [ordered]@{}
if (Test-Path $jsonPath) { (Get-Content $jsonPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $out[$_.Name] = $_.Value } }
foreach ($it in $items) {
  if ($out.Contains($it.k)) { "SKIP $($it.k) (already $($out[$it.k]))"; continue }
  $img = Join-Path $icons ('badge_' + $it.k + '.jpg')
  $resp = & curl.exe -s --max-time 120 -X POST "https://apis.roblox.com/legacy-badges/v1/universes/$universe/badges" -H "x-api-key: $key" `
    --form-string "name=$($it.name)" --form-string "description=$($it.desc)" `
    --form-string "paymentSourceType=2" --form-string "expectedCost=0" --form-string "isActive=true" `
    -F "files=@$img;type=image/jpeg"
  try { $j = $resp | ConvertFrom-Json } catch { $j = $null }
  if ($j -and $j.id) { $out[$it.k] = $j.id; "OK   $($it.k) -> $($j.id)" }
  else {
    "STOP $($it.k): $($resp.Substring(0, [Math]::Min(300, $resp.Length)))"
    if ($resp -match '"code"\s*:\s*18') { "     (free quota used up for today - run again tomorrow; nothing was charged)" }
    break
  }
  Start-Sleep -Milliseconds 600
}
$out | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 $jsonPath
Remove-Variable key
