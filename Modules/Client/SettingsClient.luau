--!strict
--[[
    SettingsClient: opens the Settings screen and applies the saved settings (profile key
    "Settings", replicated through the HangarReplica) to input and camera whenever they change.
    Changes are sent to the server (SettingsRequest), which validates and saves them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Fusion = require(ReplicatedStorage.Packages.fusion)
local peek = Fusion.peek

local Settings = ModuleUtil.New({})
local LMGui, Input, Cam, Flight
local oReq

local CAMERAS = { "Chase", "Close", "Nose" }

local function current(): { [string]: any }
	return table.clone(((peek(Store.Values.tHangar) :: any).Settings) or {})
end

local function apply(s: { [string]: any })
	Input.State.Sensitivity = s.Sensitivity or 1
	Input.State.InvertY = s.InvertY == true
	Cam.Mode = s.Camera or "Chase"
	Cam.KillCamOn = s.KillCam ~= false
	Input.State.TouchMode = if s.TouchSteer == "Stick" then "Stick" else "Swipe"
end

local function send(s: { [string]: any })
	apply(s) -- feel it immediately; the replica echo confirms
	oReq:FireServer(s)
end

function Settings.Open(self)
	if peek(Store.Values.bSettingsOpen) then return end
	Store.Values.bSettingsOpen:set(true)
	Input:SetFlightMouseLock(false)
	LMGui:Mount("Settings", { Controller = self })
end

function Settings.Close(self)
	if not peek(Store.Values.bSettingsOpen) then return end
	Store.Values.bSettingsOpen:set(false)
	LMGui:Unmount("Settings")
	GuiService.SelectedObject = nil
end

function Settings.Nudge(self, key: string, d: number)
	local s = current()
	s[key] = math.clamp(math.floor(((s[key] or 1) + d) * 10 + 0.5) / 10, 0.3, 2.5)
	send(s)
end

function Settings.Toggle(self, key: string)
	local s = current()
	if key == "KillCam" then s.KillCam = s.KillCam == false else s[key] = not s[key] end
	send(s)
end

function Settings.ToggleTouchSteer(self)
	local s = current()
	s.TouchSteer = if s.TouchSteer == "Stick" then "Swipe" else "Stick"
	send(s)
end

function Settings.CycleCamera(self)
	local s = current()
	local i = table.find(CAMERAS, s.Camera or "Chase") or 1
	s.Camera = CAMERAS[i % #CAMERAS + 1]
	send(s)
end

function Settings.StartAsync(self)
	LMGui = require(ReplicatedStorage.BCDKClient.LMGui)
	Input = require(script.Parent.InputController)
	Cam = require(script.Parent.CameraController)
	Flight = require(script.Parent.FlightController)
	oReq = Remote:GetEvent("SettingsRequest")
	local scope = Fusion.scoped(Fusion)
	scope:Observer(Store.Values.tHangar):onChange(function() apply(current()) end)
	apply(current())
	Flight.Changed:Connect(function(p: string)
		if p == "Catapult" or p == "Flying" then self:Close() end
	end)
end

return Settings
