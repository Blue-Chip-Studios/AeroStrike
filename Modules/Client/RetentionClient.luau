--!strict
--[[
    RetentionClient: the client half of RetentionServer.
      - playtime gift countdown chip (Store.sGiftLine / nGiftFrac), counted locally between
        server syncs, paused while dead on the relaunch screen (like the server)
      - daily Top Aces position line on the progress card (Store.sBoardLine)
      - favourite / notification prompts, held until a calm moment (deck, relaunch screen or
        landed) so they never pop up mid-dogfight; dropped if no calm moment within 10 min
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local RetentionConfig = require(ReplicatedStorage.Config.RetentionConfig)

local Retention = ModuleUtil.New({})
local Flight: any

local tGift: any = nil -- last server sync { t, next, at, cash, total }
local sLast, nFracLast = "", -1
local nDeadSince: number? = nil
local tPending: { what: string, until_: number }? = nil

local function activeNow(): boolean
	if Flight.Phase ~= "Dead" then nDeadSince = nil; return true end
	nDeadSince = nDeadSince or os.clock()
	return os.clock() - nDeadSince < RetentionConfig.Playtime.DeadGrace
end

local nLocal = 0 -- active seconds counted locally since the last sync
local function updateGift(dt: number)
	if not tGift then return end
	if not tGift.at then
		if sLast ~= "done" then sLast = "done"; Store.Values.sGiftLine:set("ALL GIFTS CLAIMED ✓"); Store.Values.nGiftFrac:set(1) end
		return
	end
	if activeNow() then nLocal += dt end
	local t = tGift.t + nLocal
	local left = math.max(0, tGift.at - t)
	local prevAt = 0
	local gifts = RetentionConfig.Playtime.Gifts
	if tGift.next > 1 and gifts[tGift.next - 1] then prevAt = gifts[tGift.next - 1].At * 60 end
	-- only push to the Store when the text / bar visibly changes (not every frame)
	local frac = math.floor(math.clamp((t - prevAt) / math.max(1, tGift.at - prevAt), 0, 1) * 200) / 200
	if frac ~= nFracLast then nFracLast = frac; Store.Values.nGiftFrac:set(frac) end
	local paused = Flight.Phase == "Dead" and not activeNow()
	local s = string.format("%sGIFT %d:%02d  +%d", if paused then "❚❚ " else "🎁 ", math.floor(left / 60), math.floor(left % 60), tGift.cash or 0)
	if s ~= sLast then sLast = s; Store.Values.sGiftLine:set(s) end
end

local oReq: any = nil
-- tell the server we're really playing (any input in the last 30 s), every 15 s
local nLastInput = os.clock()
local function watchInput()
	local UIS = game:GetService("UserInputService")
	local function bump(inp: InputObject)
		local t = inp.UserInputType
		if t ~= Enum.UserInputType.MouseMovement or UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then nLastInput = os.clock() end
	end
	UIS.InputBegan:Connect(bump)
	UIS.InputChanged:Connect(bump)
	task.spawn(function()
		while true do
			if os.clock() - nLastInput < 30 and oReq then oReq:FireServer({ a = "Active" }) end
			task.wait(15)
		end
	end)
end

local function showPrompt(what: string)
	if oReq then oReq:FireServer({ a = "PromptShown", what = what }) end
	if what == "Favorite" then
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
	elseif what == "Notify" then
		task.spawn(function()
			local ok, can = pcall(ExperienceNotificationService.CanPromptOptInAsync, ExperienceNotificationService)
			if ok and can then pcall(ExperienceNotificationService.PromptOptIn, ExperienceNotificationService) end
		end)
	end
end

local function calm(phase: string): boolean
	return phase == "Deck" or phase == "Dead" or phase == "Ground"
end

local function tryPending()
	if not tPending then return end
	if os.clock() > tPending.until_ then tPending = nil; return end
	if calm(Flight.Phase) then
		local what = tPending.what
		tPending = nil
		task.delay(1.2, function() showPrompt(what) end) -- let the moment's toast land first
	end
end

function Retention.StartAsync(self)
	Flight = require(script.Parent.FlightController)
	oReq = Remote:GetEvent("RetentionRequest")
	watchInput()
	Remote:GetEvent("RetentionEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Gift" then
			tGift = t
			nLocal = 0
		elseif t.a == "Board" then
			if t.me then
				Store.Values.sBoardLine:set(string.format("TOP ACES TODAY: #%d", t.me))
			elseif (t.top or 0) > 0 then
				Store.Values.sBoardLine:set(string.format("TOP ACES TODAY: %d KILLS TO BEAT FOR #1", t.top))
			else
				Store.Values.sBoardLine:set("TOP ACES TODAY: THE BOARD IS EMPTY - TAKE #1")
			end
		elseif t.a == "Prompt" and typeof(t.what) == "string" then
			tPending = { what = t.what, until_ = os.clock() + 600 }
			tryPending()
		end
	end)
	Flight.Changed:Connect(function() tryPending() end)
	RunService.Heartbeat:Connect(function(dt: number) updateGift(dt) end)
	-- QA: Studio-only attribute QA_Prompt = "Favorite" | "Notify" shows that prompt immediately
	if RunService:IsStudio() then
		local lp = game:GetService("Players").LocalPlayer
		lp:GetAttributeChangedSignal("QA_Prompt"):Connect(function()
			local w = lp:GetAttribute("QA_Prompt")
			if typeof(w) == "string" then showPrompt(w) end
		end)
	end
end

return Retention
