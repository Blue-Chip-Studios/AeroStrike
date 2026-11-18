--!strict
--[[
    SeasonClient: opens the Season screen (free tier track, smoke trails, codes, invites,
    group reward) and forwards actions to SeasonServer. Pauses the catapult while open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local GuiService = game:GetService("GuiService")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Fusion = require(ReplicatedStorage.Packages.fusion)

local LocalPlayer = Players.LocalPlayer
local SeasonC = ModuleUtil.New({})
local LMGui, Input, Flight
local oReq

local function msg(s: string)
	Store.Values.sSeasonMsg:set(s)
	task.delay(4, function()
		if Fusion.peek(Store.Values.sSeasonMsg) == s then Store.Values.sSeasonMsg:set("") end
	end)
end

function SeasonC.Open(self)
	if Fusion.peek(Store.Values.bSeasonOpen) then return end
	Store.Values.bSeasonOpen:set(true)
	Input:SetFlightMouseLock(false)
	LMGui:Mount("Season", { Controller = self })
end

function SeasonC.Close(self)
	if not Fusion.peek(Store.Values.bSeasonOpen) then return end
	Store.Values.bSeasonOpen:set(false)
	LMGui:Unmount("Season")
	GuiService.SelectedObject = nil
end

function SeasonC.Equip(self, id: string) oReq:FireServer({ a = "Equip", trail = id }) end
function SeasonC.Redeem(self, code: string) if code ~= "" then oReq:FireServer({ a = "Code", code = code }) end end
function SeasonC.CheckGroup(self) oReq:FireServer({ a = "CheckGroup" }) end
function SeasonC.Invite(self)
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, LocalPlayer)
	if ok and can then
		pcall(SocialService.PromptGameInvite, SocialService, LocalPlayer)
	else
		msg("Invites aren't available right now.")
	end
end

function SeasonC.StartAsync(self)
	LMGui = require(ReplicatedStorage.BCDKClient.LMGui)
	Input = require(script.Parent.InputController)
	Flight = require(script.Parent.FlightController)
	oReq = Remote:GetEvent("SeasonRequest")
	Remote:GetEvent("SeasonEvent"):OnClientEvent(function(t: any)
		if typeof(t) == "table" and t.a == "Msg" then msg(t.text) end
	end)
	Flight.Changed:Connect(function(p: string)
		if p == "Catapult" or p == "Flying" then self:Close() end
	end)
end

return SeasonC
