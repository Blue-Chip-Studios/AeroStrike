--!strict
--[[
    ShopClient: opens the Shop, prompts Roblox purchases (client-side prompt;
    the server grants in MonetizationServer), loads live icons/prices from
    MarketplaceService, tracks owned passes, logs shop funnel analytics and
    shows the one-time Starter Ace offer.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local MonetizationConfig = require(ReplicatedStorage.Config.MonetizationConfig)
local Fusion = require(ReplicatedStorage.Packages.fusion)

local LocalPlayer = Players.LocalPlayer
local Shop = ModuleUtil.New({})
local LMGui, Input, Flight
local oReq, oAnalytics

local function loadInfo()
	local info = {}
	for k, p in pairs(MonetizationConfig.Passes) do
		local ok, r = pcall(MarketplaceService.GetProductInfo, MarketplaceService, p.Id, Enum.InfoType.GamePass)
		info[k] = { Icon = if ok and r.IconImageAssetId then "rbxassetid://" .. r.IconImageAssetId else "", Price = if ok and r.PriceInRobux then r.PriceInRobux else p.Price }
	end
	for k, p in pairs(MonetizationConfig.Products) do
		local ok, r = pcall(MarketplaceService.GetProductInfo, MarketplaceService, p.Id, Enum.InfoType.Product)
		info[k] = { Icon = if ok and r.IconImageAssetId then "rbxassetid://" .. r.IconImageAssetId else "", Price = if ok and r.PriceInRobux then r.PriceInRobux else p.Price }
	end
	Store.Values.tShopInfo:set(info)
end

function Shop.Open(self)
	if Fusion.peek(Store.Values.bShopOpen) then return end
	Store.Values.bShopOpen:set(true)
	Input:SetFlightMouseLock(false)
	LMGui:Mount("Shop", { Controller = self })
	oAnalytics:FireServer({ e = "shop_shop_open" })
end

function Shop.Close(self)
	if not Fusion.peek(Store.Values.bShopOpen) then return end
	Store.Values.bShopOpen:set(false)
	LMGui:Unmount("Shop")
	if Flight.Phase == "Flying" then Input:SetFlightMouseLock(true) end
end

function Shop.Buy(self, sKey: string)
	local pass = MonetizationConfig.Passes[sKey]
	local prod = MonetizationConfig.Products[sKey]
	oAnalytics:FireServer({ e = "shop_product_view", d = { sku = sKey } })
	oReq:FireServer({ a = "Prompted", key = sKey })
	if pass then
		if Fusion.peek(Store.Values.tPasses)[sKey] then return end
		MarketplaceService:PromptGamePassPurchase(LocalPlayer, pass.Id)
	elseif prod then
		MarketplaceService:PromptProductPurchase(LocalPlayer, prod.Id)
	end
end

function Shop.DismissOffer(self)
	Store.Values.bStarterOffer:set(false)
end

function Shop.StartAsync(self)
	LMGui = require(ReplicatedStorage.BCDKClient.LMGui)
	Input = require(script.Parent.InputController)
	Flight = require(script.Parent.FlightController)
	oReq = Remote:GetEvent("MonRequest")
	oAnalytics = Remote:GetEvent("AnalyticsUI")
	task.spawn(loadInfo)
	Remote:GetEvent("MonEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Passes" then
			Store.Values.tPasses:set(t.passes or {})
		elseif t.a == "Granted" then
			local name = (MonetizationConfig.Passes[t.key] or MonetizationConfig.Products[t.key] or {}).Name or t.key
			Store.Values.sLaunchResult:set(string.upper(name) .. " UNLOCKED!")
			task.delay(2, function() Store.Values.sLaunchResult:set("") end)
			if t.key == "StarterAce" then Store.Values.bStarterOffer:set(false) end
		elseif t.a == "OfferStarter" then
			Store.Values.bStarterOffer:set(true)
		end
	end)
end

return Shop
