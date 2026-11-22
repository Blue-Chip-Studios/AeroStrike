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

-- Canyon Run gates: client-local rings (Blender ring model), aligned with the canyon
local tGateRings: { Model } = {}
local tGates: { Vector3 } = {}
local nGateNext = 1
local function clearGates()
	for _, r in ipairs(tGateRings) do r:Destroy() end
	table.clear(tGateRings)
	table.clear(tGates)
end
local function buildGates(gates: { Vector3 })
	clearGates()
	local ct = ReplicatedStorage:FindFirstChild("ClientTemplates")
	local tmpl = ct and ct:FindFirstChild("Ring") :: Model?
	for i, g in ipairs(gates) do
		tGates[i] = g
		if tmpl then
			local nxt = gates[i + 1] or (g + (g - gates[i - 1]))
			local r = tmpl:Clone()
			r:ScaleTo(1.6)
			r:PivotTo(CFrame.lookAt(g, Vector3.new(nxt.X, g.Y, nxt.Z)))
			for _, d in ipairs(r:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Glow" then d.Color = Color3.fromRGB(255, 150, 60) end
			end
			r.Parent = Workspace
			tGateRings[i] = r
		end
	end
	nGateNext = 1
end

function MissionClient.StartAsync(self)
	Remote:GetEvent("MissionEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Gate" then
			nGateNext = t.next
			local passed = tGateRings[t.next - 1]
			if passed then passed:Destroy() end
			self.Objective = tGates[t.next]
			Store.Values.sLaunchResult:set(string.format("GATE %d/%d  ·  %.1fs", t.next - 1, t.total, t.time or 0))
			task.delay(0.8, function() Store.Values.sLaunchResult:set("") end)
			return
		elseif t.a == "CanyonDone" then
			Store.Values.sLaunchResult:set(string.format("%s  %.1fs", if t.gold then "GOLD TIME!" else "CANYON CLEARED", t.time))
			task.delay(2.5, function() Store.Values.sLaunchResult:set("") end)
			-- rebuild the gates so the pilot can go again
			local copy = table.clone(tGates)
			buildGates(copy)
			self.Objective = tGates[1]
			return
		end
		if t.a == "Start" then
			if t.gates then buildGates(t.gates) else clearGates() end
			self.Objective = t.pos
			Store.Values.sObjective:set(`{t.name}  ·  {t.left} LEFT`)
			Store.Values.sLaunchResult:set(t.name .. " INBOUND")
			task.delay(2.2, function() Store.Values.sLaunchResult:set("") end)
		elseif t.a == "Update" then
			if t.pos and #tGates == 0 then self.Objective = t.pos end
			local cur = Store.Values.sObjective
			local Fusion = require(ReplicatedStorage.Packages.fusion)
			local name = string.match(Fusion.peek(cur) or "", "^(.-)  ·") or "MISSION"
			Store.Values.sObjective:set(`{name}  ·  {t.left} LEFT`)
		elseif t.a == "End" then
			clearGates()
			self.Objective = nil
			Store.Values.sObjective:set("")
			if t.success then
				Store.Values.sLaunchResult:set("MISSION COMPLETE")
				task.delay(2, function() Store.Values.sLaunchResult:set("") end)
			end
		end
	end)
	local sDistLast = ""
	RunService.RenderStepped:Connect(function()
		local target = self.Override or self.Objective
		if not target then
			Store.Values.tObjectiveScreen:set(Vector2.new(-1000, -1000))
			if sDistLast ~= "" then sDistLast = ""; Store.Values.sObjectiveDist:set("") end
			return
		end
		Store.Values.tObjectiveScreen:set(edgeClamp(Workspace.CurrentCamera, target))
		-- distance under the marker (missions got 0.23 joins per session: make them easy to find)
		local cam = Workspace.CurrentCamera
		local d = (target - cam.CFrame.Position).Magnitude
		local s = if d >= 1000 then string.format("%.1f KM", d / 1000) else string.format("%d M", math.floor(d / 10) * 10)
		if s ~= sDistLast then sDistLast = s; Store.Values.sObjectiveDist:set(s) end
	end)
end

return MissionClient
