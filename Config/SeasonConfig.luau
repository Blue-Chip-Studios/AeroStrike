--!strict
--[[
    SeasonConfig: the free season track (all XP you earn fills it), smoke-trail cosmetics,
    redeemable codes, and the group / invite rewards. Bump Season.Id for a new season: every
    profile's season progress resets (trails you earned stay yours).
]]

export type Trail = { Name: string, Colors: { Color3 }, Glow: number? }

local Trails: { [string]: Trail } = {
	Crimson = { Name = "Crimson Smoke", Colors = { Color3.fromRGB(230, 40, 40) } },
	Sky = { Name = "Sky Blue", Colors = { Color3.fromRGB(80, 170, 255) } },
	Emerald = { Name = "Emerald", Colors = { Color3.fromRGB(60, 220, 120) } },
	Solar = { Name = "Solar Flare", Colors = { Color3.fromRGB(255, 150, 30) }, Glow = 0.6 },
	Violet = { Name = "Violet", Colors = { Color3.fromRGB(170, 90, 255) } },
	Arctic = { Name = "Arctic", Colors = { Color3.fromRGB(235, 250, 255), Color3.fromRGB(150, 220, 255) }, Glow = 0.4 },
	Inferno = { Name = "Inferno", Colors = { Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 70, 20) }, Glow = 0.7 },
	Spectrum = { Name = "Spectrum", Colors = { Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 200, 40), Color3.fromRGB(60, 220, 120), Color3.fromRGB(60, 140, 255), Color3.fromRGB(190, 80, 255) }, Glow = 0.5 },
	Phoenix = { Name = "Phoenix", Colors = { Color3.fromRGB(255, 220, 110), Color3.fromRGB(255, 120, 20), Color3.fromRGB(220, 30, 15) }, Glow = 0.85 }, -- Robux (PhoenixTrail / AcePack)
	BlueChip = { Name = "Blue Chip Squadron", Colors = { Color3.fromRGB(30, 110, 255), Color3.fromRGB(255, 255, 255) }, Glow = 0.5 }, -- group reward
	-- Season Premium exclusives
	Chrome = { Name = "Chrome", Colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 150, 165), Color3.fromRGB(255, 255, 255) }, Glow = 0.8 },
	Afterglow = { Name = "Afterglow", Colors = { Color3.fromRGB(255, 80, 200), Color3.fromRGB(80, 220, 255) }, Glow = 0.9 },
	Phantom = { Name = "Phantom", Colors = { Color3.fromRGB(20, 20, 26), Color3.fromRGB(120, 40, 200) }, Glow = 0.3 },
}

-- 20 tiers; each needs XPPerTier more XP. Reward = Cash or a Trail.
local Tiers = {
	{ Cash = 250 }, { Trail = "Crimson" }, { Cash = 400 }, { Trail = "Sky" }, { Cash = 600 },
	{ Trail = "Emerald" }, { Cash = 800 }, { Trail = "Solar" }, { Cash = 1000 }, { Trail = "Violet" },
	{ Cash = 1200 }, { Cash = 1400 }, { Cash = 1600 }, { Trail = "Arctic" }, { Cash = 1800 },
	{ Cash = 2000 }, { Trail = "Inferno" }, { Cash = 2500 }, { Cash = 3000 }, { Trail = "Spectrum" },
}

return {
	Season = {
		Id = 1,
		Name = "SEASON 1 · RED TALON RISING",
		EndsAt = os.time({ year = 2027, month = 1, day = 31, hour = 0 }),
		XPPerTier = 450,
		Tiers = Tiers,
	},
	Trails = Trails,
	Codes = { -- UPPERCASE; Expires = os.time or nil
		LAUNCH = { Cash = 1000, Expires = os.time({ year = 2027, month = 3, day = 1, hour = 0 }) },
		ACEPILOT = { Cash = 500 },
		MACHONE = { Cash = 750 },
		SKYFIRE = { Cash = 500, Expires = os.time({ year = 2027, month = 1, day = 31, hour = 0 }) }, -- launch window code drop
	},
	-- Season Premium (game pass): cosmetics and a faster track only, no combat power
	Premium = { XPMult = 1.25, TierCashMult = 2, Trails = { "Chrome", "Afterglow", "Phantom" } },
	GroupId = 144483796, -- Blue Chip Games
	GroupReward = { Cash = 1000, Trail = "BlueChip" },
	Invite = { ReferrerCash = 500, NewPilotCash = 500, MaxReferrals = 10 },
}
