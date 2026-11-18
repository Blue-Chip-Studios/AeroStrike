--!strict
--[[
    DebugServer: Studio-only QA hooks (never created in live servers).
    ServerStorage.AS_Debug (BindableFunction):Invoke(cmd, ...) lets test
    tooling talk to the live module instances.
      "spawnAhead"(kind, dist)  spawn an NPC flying ahead of the first jet
      "state"()                 summary of jets, NPCs, mission, economy
      "damageSelf"(n)           damage the first jet (QA of death flow)
]]

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)

local Debug = ModuleUtil.New({})

function Debug.StartAsync(self)
	if not RunService:IsStudio() then return end
	local Npc = require(ServerStorage.ServerModules.NpcServer)
	local Combat = require(ServerStorage.ServerModules.CombatServer)
	local Mission = require(ServerStorage.ServerModules.MissionServer)
	local bf = Instance.new("BindableFunction")
	bf.Name = "AS_Debug"
	bf.OnInvoke = function(cmd: string, a: any, b: any)
		local jet = workspace.Jets:GetChildren()[1] :: Model?
		if cmd == "spawnAhead" and jet and jet.PrimaryPart then
			local cf = jet.PrimaryPart.CFrame
			local start = cf.Position + cf.LookVector * (b or 500)
			local m = Npc:Spawn(a or "Drone", CFrame.lookAt(start, start + cf.LookVector), {
				Route = { start + cf.LookVector * 4000, start + cf.LookVector * 8000 }, Tag = "Debug" })
			return m and m.Name
		elseif cmd == "damageSelf" and jet then
			Combat:Damage(jet, a or 200, nil, "Debug")
			return "ok"
		elseif cmd == "state" then
			local npcs = 0
			for _ in pairs(Npc.Active) do npcs += 1 end
			local cur = Mission.Current
			return {
				npcs = npcs,
				mission = cur and `{cur.Id} left={cur.Left}` or "none",
				jet = jet and { hp = jet:GetAttribute("Health"), msl = jet:GetAttribute("Missiles"), flr = jet:GetAttribute("Flares") } or "none",
			}
		end
		return "unknown"
	end
	bf.Parent = ServerStorage
end

return Debug
