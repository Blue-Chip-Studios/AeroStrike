--!strict
--[[
    EconomyClient: mirrors Cash (BCDK LMCurrency), Ace XP (LMXP), hangar
    profile data (HangarReplica) and Sortie Cash into the Store, and turns
    EconomyEvents into toasts. Exposes Economy.Hangar (replicated data) and
    Economy:Shop(request) for the hangar UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local XPConfig = require(ReplicatedStorage.Config.XPConfig)
local ReplicaClient = require(ReplicatedStorage.External.Replica.ReplicaClient)

local HangarChanged = Instance.new("BindableEvent")
local Economy = ModuleUtil.New({
	Hangar = {} :: { [string]: any },
	HangarChanged = HangarChanged.Event,
})

local oShop

local function setXP(nXP: number)
	local r = XPConfig.fXPToLevel(nXP)
	local a, b = XPConfig.fLevelToXP(r), XPConfig.fLevelToXP(r + 1)
	Store.Values.nRank:set(r)
	Store.Values.nRankProgress:set(if b > a then (nXP - a) / (b - a) else 1)
end

function Economy.Shop(self, t: { [string]: any }): { [string]: any }
	local ok, res = pcall(function() return oShop:InvokeServer(t) end)
	if ok and typeof(res) == "table" then return res end
	return { ok = false, err = "network" }
end

function Economy.StartAsync(self)
	oShop = Remote:GetFunction("Shop")
	local LMCurrency = require(ReplicatedStorage.BCDKClient.LMCurrency)
	local LMXP = require(ReplicatedStorage.BCDKClient.LMXP)
	local Vfx = require(script.Parent.VfxController)

	if LMCurrency.Current.Cash then Store.Values.nCash:set(LMCurrency.Current.Cash) end
	LMCurrency.CurrencyChanged:Connect(function(sKey: string, v: number)
		if sKey == "Cash" then Store.Values.nCash:set(v) end
	end)
	setXP(LMXP.Current)
	LMXP.Changed:Connect(setXP)

	local function deepCopy(t: any): any
		if typeof(t) ~= "table" then return t end
		local c = {}
		for k, v in pairs(t) do c[k] = deepCopy(v) end
		return c
	end
	ReplicaClient.OnNew("HangarReplica", function(oReplica: any)
		self.Hangar = oReplica.Data
		Store.Values.tHangar:set(deepCopy(oReplica.Data))
		HangarChanged:Fire()
		oReplica:OnChange(function()
			self.Hangar = oReplica.Data
			Store.Values.tHangar:set(deepCopy(oReplica.Data))
			HangarChanged:Fire()
		end)
	end)

	Remote:GetEvent("EconomyEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Sortie" then
			Store.Values.nSortieCash:set(t.v)
		elseif t.a == "Toast" then
			local s = t.text
			if t.cash and t.cash > 0 then s ..= `   +{t.cash}` end
			Vfx:Toast(s, Color3.fromRGB(255, 194, 61))
		elseif t.a == "Banked" then
			Store.Values.sLaunchResult:set(`BANKED +{t.v}`)
			task.delay(1.6, function() Store.Values.sLaunchResult:set("") end)
		elseif t.a == "RankUp" then
			Store.Values.sLaunchResult:set(`ACE RANK {t.rank}!`)
			task.delay(2, function() Store.Values.sLaunchResult:set("") end)
		end
	end)
end

return Economy
