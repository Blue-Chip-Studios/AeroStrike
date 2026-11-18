--!strict
--[[
    MissionClient: live mission banner + objective marker. The marker clamps
    to the screen edge when the objective is behind/off-screen, so players
    always know where to fly ("what should I do next?").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)

local MissionClient = ModuleUtil.New({
	Objective = nil :: Vector3?,
	Override = nil :: Vector3?, -- FTUE can point the marker somewhere else
})

local function edgeClamp(cam: Camera, world: Vector3): Vector2
	local vp = cam.ViewportSize
	local sp, onScreen = cam:WorldToViewportPoint(world)
	local p = Vector2.new(sp.X, sp.Y)
	if onScreen and sp.Z > 0 then return p end
	-- behind or off-screen: project direction onto the screen edge
	local rel = cam.CFrame:PointToObjectSpace(world)
	local dir = Vector2.new(rel.X, -rel.Y)
	if dir.Magnitude < 1e-3 then dir = Vector2.new(0, 1) end
	dir = dir.Unit
	local c = vp / 2
	local m = 60
	local tx = if dir.X ~= 0 then (c.X - m) / math.abs(dir.X) else math.huge
	local ty = if dir.Y ~= 0 then (c.Y - m) / math.abs(dir.Y) else math.huge
	return c + dir * math.min(tx, ty)
end

function MissionClient.StartAsync(self)
	Remote:GetEvent("MissionEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Start" then
			self.Objective = t.pos
			Store.Values.sObjective:set(`{t.name}  ·  {t.left} LEFT`)
			Store.Values.sLaunchResult:set(t.name .. " INBOUND")
			task.delay(2.2, function() Store.Values.sLaunchResult:set("") end)
		elseif t.a == "Update" then
			if t.pos then self.Objective = t.pos end
			local cur = Store.Values.sObjective
			local Fusion = require(ReplicatedStorage.Packages.fusion)
			local name = string.match(Fusion.peek(cur) or "", "^(.-)  ·") or "MISSION"
			Store.Values.sObjective:set(`{name}  ·  {t.left} LEFT`)
		elseif t.a == "End" then
			self.Objective = nil
			Store.Values.sObjective:set("")
			if t.success then
				Store.Values.sLaunchResult:set("MISSION COMPLETE")
				task.delay(2, function() Store.Values.sLaunchResult:set("") end)
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		local target = self.Override or self.Objective
		if not target then
			Store.Values.tObjectiveScreen:set(Vector2.new(-1000, -1000))
			return
		end
		Store.Values.tObjectiveScreen:set(edgeClamp(Workspace.CurrentCamera, target))
	end)
end

return MissionClient
