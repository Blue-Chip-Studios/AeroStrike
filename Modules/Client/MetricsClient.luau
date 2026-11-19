--!strict
--[[
    MetricsClient: tells MetricsServer the player's device class once per session and reports
    client script errors (deduplicated, capped) so live problems show up in the metrics report.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

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
