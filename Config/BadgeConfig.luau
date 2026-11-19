--!strict
--[[
    BadgeConfig: Roblox badges. Id = 0 means "not created yet": BadgeServer skips it.
    Create the badges in the Creator Dashboard (Monetization > Badges, or Engagement > Badges)
    with the icons in Assets/Icons/Badges/, then paste each badge id here.
]]

export type Badge = { Id: number, Name: string, Desc: string }

local Badges: { [string]: Badge } = {
	Welcome = { Id = 827574388586209, Name = "Wheels Up", Desc = "Launch off the carrier for the first time." },
	FirstKill = { Id = 2106010100222346, Name = "Splash One", Desc = "Shoot down your first enemy pilot." },
	MachOne = { Id = 3315996126439503, Name = "Sound Barrier", Desc = "Break Mach 1." },
	CarrierTrap = { Id = 2713946695104913, Name = "Trapped", Desc = "Catch the wire: land back on the carrier." },
	MultiKill = { Id = 0, Name = "Triple Splash", Desc = "Score three kills in one chain." },
	Ace = { Id = 3078115105520892, Name = "Ace", Desc = "Reach a 5-kill streak and wear the Ace Bounty." },
	BountyHunter = { Id = 0, Name = "Bounty Hunter", Desc = "Shoot down an Ace and claim the bounty." },
	Fortress = { Id = 0, Name = "Fortress Breaker", Desc = "Help bring down the Flying Fortress." },
	Viper = { Id = 0, Name = "Viper Pilot", Desc = "Unlock the Viper IX." },
	Rhino = { Id = 0, Name = "Rhino Pilot", Desc = "Unlock the Rhino HX." },
	Mako = { Id = 0, Name = "Mako Pilot", Desc = "Unlock the Mako SR-9." },
	Wraith = { Id = 0, Name = "Ghost in the Sky", Desc = "Unlock the Wraith-X." },
	Mastery = { Id = 0, Name = "Master Aviator", Desc = "Reach mastery level 10 with any jet." },
	TopAce = { Id = 0, Name = "Top Ace", Desc = "Finish in the daily Top Aces top 10." },
}

-- jet id -> badge key, awarded when the jet is unlocked
local JetBadges = { ViperIX = "Viper", RhinoHX = "Rhino", MakoSR9 = "Mako", WraithX = "Wraith" }

return { Badges = Badges, JetBadges = JetBadges }
