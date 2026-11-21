--!strict
--[[
    MetricsClient: tells MetricsServer the player's device class once per session and reports
    client script errors (deduplicated, capped) so live problems show up in the metrics report.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)

local MetricsClient = ModuleUtil.New({})

local function device(): string
	if GuiService:IsTenFootInterface() then return "Gamepad" end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return "Touch" end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then return "Gamepad" end
	return "KBM"
end

function MetricsClient.StartAsync(self)
	local oEvent = Remote:GetEvent("MetricsReport")
	task.delay(5, function()
		oEvent:FireServer({ a = "Device", d = device() })
	end)
	-- PERFORMANCE: time from joining until your jet is on the catapult, then 90 s of frame-rate
	-- sampling (average fps, share of seconds under 30 fps), memory and graphics setting.
	-- 24% of new players left within a minute: this tells us whether slow phones are why.
	task.spawn(function()
		local lp = Players.LocalPlayer
		local jets = workspace:WaitForChild("Jets", 60)
		local t0 = os.clock()
		while jets and not jets:FindFirstChild(tostring(lp.UserId)) and os.clock() - t0 < 120 do task.wait(0.25) end
		local loaded = time() -- seconds since this client started the game
		local frames, acc, secs, total, low = 0, 0, 0, 0, 0
		local conn = RunService.RenderStepped:Connect(function(dt)
			frames += 1
			acc += dt
			if acc >= 1 then
				secs += 1
				total += frames
				if frames < 30 then low += 1 end
				frames, acc = 0, acc - 1
			end
		end)
		task.wait(90)
		conn:Disconnect()
		local quality = "?"
		pcall(function() quality = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Name end)
		local mem = 0
		pcall(function() mem = Stats:GetTotalMemoryUsageMb() end)
		oEvent:FireServer({ a = "Perf", load = loaded, fps = if secs > 0 then total / secs else 0, low = if secs > 0 then low / secs else 0, mem = mem, q = quality })
	end)

	local tSent: { [string]: boolean } = {}
	local nSent = 0
	ScriptContext.Error:Connect(function(msg: string)
		local key = string.sub(msg, 1, 120)
		if tSent[key] or nSent >= 8 then return end
		tSent[key] = true
		nSent += 1
		oEvent:FireServer({ a = "Error", m = key })
	end)
end

return MetricsClient
