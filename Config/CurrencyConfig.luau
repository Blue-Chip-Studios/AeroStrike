--[[
    CurrencyConfig (BCDK SMCurrency / LMCurrency)
    Cash is the only soft currency. Sortie Cash (unbanked) is session state
    owned by EconomyServer, not a saved currency.
]]

local eCurrency = {
	Cash = 1,
}

return {
	eCurrency = eCurrency,
	eCurrencyProfiles = {
		[eCurrency.Cash] = { sKey = "Cash", nDefaultAmount = 0 },
	},
}
