--!strict
--[[
    HangarClient: opens/closes the Hangar screen (LMGui), forwards actions to
    the server Shop remote via EconomyClient, shows result messages, logs UI
    analytics, and pauses the catapult auto-launch while the hangar is open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Fusion = require(ReplicatedStorage.Packages.fusion)

local Hangar = ModuleUtil.New({})
local LMGui, Economy, Input, Flight
local oAnalytics

local ERR = {
	cash = "Not enough Cash: fly a sortie and bank it!",
	rank = "Reach the required Ace Rank first.",
	owned = "You already own this jet.",
	notowned = "Buy this jet first.",
	max = "Already maxed out.",
	mastery = "Reach that mastery level with this jet first: fly it!",
	invalid = "Can't do that right now.",
	robux = "Unlock this jet in the Shop.",
	busy = "Slow down, pilot!",
	network = "Connection hiccup, try again.",
}

local function msg(s: string)
	Store.Values.sHangarMsg:set(s)
	task.delay(3, function()
		if Fusion.peek(Store.Values.sHangarMsg) == s then Store.Values.sHangarMsg:set("") end
	end)
end

local function result(r: any, okText: string)
	if r.ok then msg(okText) else msg(ERR[r.err] or "Can't do that right now.") end
end

function Hangar.Open(self)
	if Fusion.peek(Store.Values.bHangarOpen) then return end
	Store.Values.bHangarOpen:set(true)
	Input:SetFlightMouseLock(false)
	local h = Fusion.peek(Store.Values.tHangar)
	Store.Values.sHangarSelected:set(h.EquippedJet or "SparrowT2")
	LMGui:Mount("Hangar", { Controller = self, Gamepad = Input.LastDevice == "Gamepad" })
	oAnalytics:FireServer({ e = "ui_hangar_open" })
end

function Hangar.Close(self)
	if not Fusion.peek(Store.Values.bHangarOpen) then return end
	Store.Values.bHangarOpen:set(false)
	LMGui:Unmount("Hangar")
	GuiService.SelectedObject = nil
	if Flight.Phase == "Dead" then Flight:Relaunch() end
end

function Hangar.Buy(self, sJet: string)
	result(Economy:Shop({ a = "BuyJet", jet = sJet }), "Purchased! Tap EQUIP to fly it.")
end

function Hangar.Equip(self, sJet: string)
	result(Economy:Shop({ a = "Equip", jet = sJet }), "Equipped. Ready on the catapult.")
end

function Hangar.Paint(self, sJet: string, sPaint: string)
	result(Economy:Shop({ a = "Paint", jet = sJet, paint = sPaint }), "Paint applied.")
end

function Hangar.Upgrade(self, sJet: string, sTrack: string)
	result(Economy:Shop({ a = "Upgrade", jet = sJet, track = sTrack }), "Upgrade installed!")
end

-- one-tap upgrade from the death screen (feedback in the big centre banner, not the hangar line)
function Hangar.QuickUpgrade(self, sJet: string, sTrack: string, sLabel: string)
	local r = Economy:Shop({ a = "Upgrade", jet = sJet, track = sTrack })
	Store.Values.sLaunchResult:set(if r.ok then `{sLabel} UPGRADED!` else (ERR[r.err] or "Can't do that right now."))
	task.delay(1.8, function() Store.Values.sLaunchResult:set("") end)
	oAnalytics:FireServer({ e = "ui_button", d = { id = "quick_upgrade", sku = sTrack } })
end

function Hangar.StartAsync(self)
	LMGui = require(ReplicatedStorage.BCDKClient.LMGui)
	Economy = require(script.Parent.EconomyClient)
	Input = require(script.Parent.InputController)
	Flight = require(script.Parent.FlightController)
	oAnalytics = Remote:GetEvent("AnalyticsUI")
	-- close if we get launched out from under it
	Flight.Changed:Connect(function(p: string)
		if p == "Catapult" or p == "Flying" then self:Close() end
	end)
end

return Hangar
