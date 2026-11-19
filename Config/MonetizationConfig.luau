--!strict
--[[
    MonetizationConfig: every Robux product (created via Open Cloud; see
    Tools/CreateProducts.ps1 and Tools/products.json). Prices are set on
    Roblox; the R$ values here are for display fallbacks only.

    Design rule (DECISIONS #10): advantage, not immunity.
]]

return {
	Passes = {
		SeasonPremium = { Id = 2094309905, Name = "Season 1 Premium", Price = 399, Order = 0 }, -- cosmetics + faster season track (no combat power)
		WraithX = { Id = 2092347121, Name = "Wraith-X Stealth Ace", Price = 799, Order = 1 },
		MultiLock = { Id = 2093211054, Name = "Multi-Lock Missiles", Price = 499, Order = 2 },
		DoubleCash = { Id = 2092701119, Name = "2x Cash", Price = 399, Order = 3 },
		Afterburner = { Id = 2094585103, Name = "Afterburner Pass", Price = 349, Order = 4 },
		GSuitPro = { Id = 2094219115, Name = "G-Suit Pro", Price = 299, Order = 5 },
		VIP = { Id = 2093127154, Name = "VIP Pilot", Price = 249, Order = 6 },
		FlarePod = { Id = 2094537074, Name = "Extra Flare Pod", Price = 199, Order = 7 },
	},
	Products = {
		ReviveHere = { Id = 3733440715, Name = "Revive Here", Price = 25, Order = 0, Hidden = true, Grant = { Revive = true } }, -- death screen impulse buy
		StarterAce = { Id = 3733032938, Name = "Starter Ace Bundle", Price = 99, OneTime = true, Order = 1,
			Grant = { Jet = "ViperIX", Cash = 5000 } },
		CashS = { Id = 3733032949, Name = "Cash Crate S", Price = 75, Order = 2, Grant = { Cash = 5000 } },
		CashM = { Id = 3733032958, Name = "Cash Crate M", Price = 299, Order = 3, Grant = { Cash = 25000 } },
		CashL = { Id = 3733033145, Name = "Cash Crate XL", Price = 899, Order = 4, Grant = { Cash = 100000 } },
		Rearm = { Id = 3733032971, Name = "Instant Rearm", Price = 25, Order = 5, Grant = { Rearm = true } },
		BountyShield = { Id = 3733032978, Name = "Bounty Shield", Price = 49, Order = 6, Grant = { BountyShield = true } },
	},
	StarterOfferAfterDeaths = 3, -- offer the starter bundle after the 3rd shoot-down (once per session)
	ReviveWindow = 12, -- seconds after a shoot-down the REVIVE HERE offer stays up
	ReviveMinFlight = 20, -- only offered if the sortie lasted this long (not for catapult mishaps)
	ReviveFallbackCash = 2500, -- if the window closed before the receipt arrived
}
