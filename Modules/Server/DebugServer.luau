--!strict
--[[
    DebugServer: Studio-only QA hooks (never created in live servers).
    ServerStorage.AS_Debug (BindableFunction):Invoke(cmd, ...) lets test
    tooling talk to the live module instances.
      "spawnAhead"(kind, dist)  spawn an NPC flying ahead of the first jet
      "state"()                 summary of jets, NPCs, mission, economy
      "damageSelf"(n)           damage the first jet (QA of death flow)
      "damageMission"(n)        damage current mission units as player 1
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
		elseif cmd == "missileAtMe" and jet and jet.PrimaryPart then
			-- QA of the threat/tension audio: a SAM from behind and below
			local cf = jet.PrimaryPart.CFrame
			local from = CFrame.lookAt(cf.Position - cf.LookVector * (a or 1400) + Vector3.new(0, -200, 0), cf.Position)
			jet:SetAttribute("Shield", false)
			Combat:FireMissileAt(nil, from, jet, 20)
			return "fired"
		elseif cmd == "ftueStep" then
			-- jump the first player's FTUE so step n is next (QA only)
			local p = game:GetService("Players"):GetPlayers()[1]
			local Economy = require(ServerStorage.ServerModules.EconomyServer)
			Economy:SetProfileKey(p, "FTUE", function(f) f.Step = (a or 1) - 1; f.Done = false; f.Skipped = false; return f end)
			require(ReplicatedStorage.BCDKShared.Remote):GetEvent("FTUEEvent"):FireClient(p, { a = "State", step = (a or 1) - 1, done = false })
			return "ok"
		elseif cmd == "mission" then
			Mission:ForceStart(a)
			return "started " .. tostring(a)
		elseif cmd == "giveCash" then
			local p = game:GetService("Players"):GetPlayers()[1]
			require(ServerStorage.BCDKServer.SMCurrency):Add(p, 1, a or 10000)
			require(ServerStorage.BCDKServer.SMXP):Add(p, b or 0)
			return "ok"
		elseif cmd == "damageMission" then
			-- damage every live unit of the current mission as the first player
			local cur = Mission.Current
			if not cur then return "no mission" end
			local p = game:GetService("Players"):GetPlayers()[1]
			local out = {}
			for unit in pairs(cur.Units) do
				if unit.Parent then
					local pp = unit.PrimaryPart
					table.insert(out, `{unit.Name}@{pp and math.floor(pp.Position.X) or "?"},{pp and math.floor(pp.Position.Z) or "?"} hp={unit:GetAttribute("Health")}`)
					Combat:Damage(unit, a or 100, p, "Debug")
				end
			end
			return table.concat(out, "; ")
		elseif cmd == "revive" then
			-- REVIVE HERE without the purchase (QA)
			local F = require(ServerStorage.ServerModules.FlightServer)
			return tostring(F:Revive(game:GetService("Players"):GetPlayers()[1]))
		elseif cmd == "damageNpc" then
			-- damage a named NPC as the first player (boss / bot QA)
			local m = workspace.NPC:FindFirstChild(tostring(a))
			if not m then return "no npc" end
			Combat:Damage(m, b or 100, game:GetService("Players"):GetPlayers()[1], "Cannon")
			return `hp={m:GetAttribute("Health")}`
		elseif cmd == "reward" then
			-- grant an Economy reward to the first player (XP feeds season + mastery), e.g. ("reward", "Kill", 20)
			local p = game:GetService("Players"):GetPlayers()[1]
			require(ServerStorage.ServerModules.EconomyServer):Reward(p, a or "Kill", { Bank = true, Mult = b or 1 })
			return "ok"
		elseif cmd == "playtime" then
			-- set the first player's active session seconds (gift ladder QA)
			local p = game:GetService("Players"):GetPlayers()[1]
			require(ServerStorage.ServerModules.RetentionServer):QASetActive(p, a or 0)
			return "ok"
		elseif cmd == "moment" then
			-- fire a prompt moment now, ignoring the session-time gate (prompt QA)
			local p = game:GetService("Players"):GetPlayers()[1]
			return require(ServerStorage.ServerModules.RetentionServer):QAMoment(p, a or "FirstKill")
		elseif cmd == "metrics" then
			-- unflushed MetricsServer counters (Studio never writes the DataStore)
			return game:GetService("HttpService"):JSONEncode(require(ServerStorage.ServerModules.MetricsServer):Snapshot())
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
