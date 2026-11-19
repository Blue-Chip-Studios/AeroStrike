--!strict
--[[
    RetentionServer: session-length and come-back levers (RetentionConfig).

    PLAYTIME GIFTS: active seconds this session (not counting time sitting on the relaunch
      screen) pay gifts at 3 / 7 / 12 / 20 / 30 minutes, automatically, with a toast.
    SCOREBOARD: leaderstats "Kills" (this session: players + AI pilots) and "Rank".
    TOP ACES: daily / weekly kill boards on OrderedDataStores (batched writes, periodic reads;
      falls back to this server's session counts when datastores are unavailable, e.g. Studio).
      Shown on a board on the carrier deck and as your daily position on the progress card.
    PROMPTS: after a high point (first kill, multi-kill, Fortress payout, rank up, season tier,
      mastery level) the client is told to ask for a favourite or notifications opt-in; it shows
      the prompt at the next calm moment (deck / relaunch screen / landed), never mid-dogfight.

    S->C RetentionEvent { a = "Gift", t, next, at, cash, total } | { a = "Board", daily, weekly, me }
                        | { a = "Prompt", what = "Favorite" | "Notify" }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local RetentionConfig = require(ReplicatedStorage.Config.RetentionConfig)
local XPConfig = require(ReplicatedStorage.Config.XPConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)

local Retention = ModuleUtil.New({})
local oEvent = Remote:GetEvent("RetentionEvent")
local Economy: any, Analytics: any, Flight: any

local P = RetentionConfig.Playtime
local B = RetentionConfig.Boards
local PR = RetentionConfig.Prompts

-------------------------------------------------------------------------------- playtime gifts
local tActive: { [Player]: number } = {}
local tNext: { [Player]: number } = {}
local tJoined: { [Player]: number } = {}

local function syncGift(p: Player)
	local g = P.Gifts[tNext[p] or 1]
	oEvent:FireClient(p, { a = "Gift", t = tActive[p] or 0, next = tNext[p] or 1, total = #P.Gifts,
		at = if g then g.At * 60 else nil, cash = if g then g.Cash else nil })
end

local function isActive(p: Player): boolean
	local s = Flight:GetSortie(p)
	if not s then return false end
	if s.Phase ~= "Dead" then return true end
	return os.clock() - (s.DeadAt or 0) < P.DeadGrace
end

local function tickGifts()
	for _, p in ipairs(Players:GetPlayers()) do
		if tActive[p] and isActive(p) then
			tActive[p] += 1
			local i = tNext[p]
			local g = P.Gifts[i]
			if g and tActive[p] >= g.At * 60 then
				tNext[p] = i + 1
				Economy:Reward(p, "PlaytimeGift", { Bank = true, Cash = g.Cash, Label = `{g.Label}: +{g.Cash}` })
				Analytics:Log(p, "playtime_gift", { n = i, minutes = g.At })
				syncGift(p)
			elseif tActive[p] % 15 == 0 then
				syncGift(p)
			end
		end
	end
end

-------------------------------------------------------------------------------- scoreboard
local tKills: { [Player]: number } = {}

local function leaderstats(p: Player)
	local f = Instance.new("Folder")
	f.Name = "leaderstats"
	local k = Instance.new("IntValue")
	k.Name = "Kills"
	k.Parent = f
	local r = Instance.new("IntValue")
	r.Name = "Rank"
	r.Value = XPConfig.fXPToLevel(mProfile:GetAsync(p, "XP") or 0)
	r.Parent = f
	f.Parent = p
end

local function setStat(p: Player, name: string, v: number)
	local f = p:FindFirstChild("leaderstats")
	local iv = f and f:FindFirstChild(name)
	if iv and iv:IsA("IntValue") then iv.Value = v end
end

-------------------------------------------------------------------------------- top aces boards
local function dayKey(): number return math.floor(os.time() / 86400) end
local function weekKey(): number return math.floor((os.time() / 86400 + 3) / 7) end -- weeks start Monday (UTC)

local tPending: { [number]: number } = {} -- userId -> unflushed score
local tSession: { [number]: { Name: string, Score: number } } = {} -- this server's totals (fallback)
local tNames: { [number]: string } = {}
local tBoard = { daily = {}, weekly = {} }
local bStoreOk = true

local function store(kind: "D" | "W"): OrderedDataStore?
	if not bStoreOk then return nil end
	local ok, ds = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, `TopAces_{kind}_{if kind == "D" then dayKey() else weekKey()}`)
	return if ok then ds else nil
end

local function score(p: Player, n: number)
	if n <= 0 then return end
	tPending[p.UserId] = (tPending[p.UserId] or 0) + n
	local s = tSession[p.UserId] or { Name = p.DisplayName, Score = 0 }
	s.Score += n
	tSession[p.UserId] = s
	tNames[p.UserId] = p.DisplayName
end

local function flush()
	local batch = tPending
	tPending = {}
	for uid, n in pairs(batch) do
		for _, kind in ipairs({ "D", "W" } :: { "D" | "W" }) do
			local ds = store(kind)
			if ds then
				local ok, err = pcall(ds.IncrementAsync, ds, tostring(uid), n)
				if not ok then
					if string.find(tostring(err), "StudioAccessToApisNotAllowed") or string.find(tostring(err), "403") then bStoreOk = false end
				end
			end
		end
	end
end

local function nameOf(uid: number): string
	if tNames[uid] then return tNames[uid] end
	local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, uid)
	tNames[uid] = if ok and n then n else "Pilot"
	return tNames[uid]
end

local function read(kind: "D" | "W"): { { Id: number, Name: string, Score: number } }
	local out = {}
	local ds = store(kind)
	if ds then
		local ok, pages = pcall(ds.GetSortedAsync, ds, false, B.Size)
		if ok and pages then
			for _, e in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(e.key) or 0
				table.insert(out, { Id = uid, Name = nameOf(uid), Score = e.value })
			end
			return out
		end
	end
	-- fallback: this server's session scores
	for uid, s in pairs(tSession) do table.insert(out, { Id = uid, Name = s.Name, Score = s.Score }) end
	table.sort(out, function(a, b) return a.Score > b.Score end)
	while #out > B.Size do table.remove(out) end
	return out
end

local oBoardGui: SurfaceGui? = nil

local function drawBoard()
	if not oBoardGui then return end
	local list = oBoardGui:FindFirstChild("List") :: Frame?
	if not list then return end
	for i = 1, B.Size do
		local row = list:FindFirstChild("R" .. i) :: TextLabel?
		local e = tBoard.daily[i]
		if row then row.Text = if e then string.format("%2d   %-18s %4d", i, string.sub(e.Name, 1, 18), e.Score) else string.format("%2d   —", i) end
	end
	local wk = oBoardGui:FindFirstChild("Week") :: TextLabel?
	local w = tBoard.weekly[1]
	if wk then wk.Text = if w then `WEEK LEADER: {string.upper(w.Name)} · {w.Score}` else "WEEK LEADER: —" end
end

local function buildBoard()
	local W = 30
	local H = 18
	local cfg = MapConfig.Carrier
	local localPos = Vector3.new(-35, cfg.DeckY + 15, -100)
	local facing = Vector3.new(0, cfg.DeckY + 6, -40)
	local cf = cfg.CFrame * CFrame.lookAt(localPos, facing)
	local part = Instance.new("Part")
	part.Name = "TopAcesBoard"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.new(W, H, 0.4)
	part.CFrame = cf
	part.Color = Color3.fromRGB(16, 22, 29)
	part.Material = Enum.Material.SmoothPlastic
	local post = part:Clone()
	post.Name = "Post"
	local postH = localPos.Y - H / 2 - cfg.DeckY
	post.Size = Vector3.new(0.8, postH, 0.8)
	post.CFrame = cfg.CFrame * CFrame.new(localPos.X, cfg.DeckY + postH / 2, localPos.Z)
	post.Color = Color3.fromRGB(60, 66, 74)
	post.Parent = part

	local g = Instance.new("SurfaceGui")
	g.Name = "Gui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Brightness = 1.6
	g.MaxDistance = 900
	local function label(name: string, y: number, h: number, size: number, color: Color3, text: string, font: Enum.Font?): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.new(0, 30, 0, y)
		t.Size = UDim2.new(1, -60, 0, h)
		t.Font = font or Enum.Font.GothamBold
		t.TextSize = size
		t.TextColor3 = color
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Text = text
		return t
	end
	label("Title", 14, 80, 68, Color3.fromRGB(255, 194, 61), "TOP ACES · TODAY").Parent = g
	label("Week", 94, 44, 34, Color3.fromRGB(92, 255, 143), "WEEK LEADER: —").Parent = g
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.new(0, 0, 0, 150)
	list.Size = UDim2.new(1, 0, 1, -160)
	list.Parent = g
	for i = 1, B.Size do
		local r = label("R" .. i, (i - 1) * 55, 54, 46, if i <= 3 then Color3.fromRGB(240, 244, 248) else Color3.fromRGB(170, 180, 190), "", Enum.Font.RobotoMono)
		r.Parent = list
	end
	g.Parent = part
	part.Parent = workspace:FindFirstChild("Map") or workspace
	oBoardGui = g
end

local function refreshBoards()
	tBoard.daily = read("D")
	tBoard.weekly = read("W")
	drawBoard()
	for i, e in ipairs(tBoard.daily) do
		local p = Players:GetPlayerByUserId(e.Id)
		if p and e.Score > 0 then
			local okB, Badge = pcall(require, ServerStorage.ServerModules:FindFirstChild("BadgeServer") :: any)
			if okB and Badge and Badge.Award then Badge:Award(p, "TopAce") end
			Analytics:Log(p, "board_top10", { pos = i })
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local me = nil
		for i, e in ipairs(tBoard.daily) do if e.Id == p.UserId then me = i end end
		oEvent:FireClient(p, { a = "Board", me = me, top = (tBoard.daily[1] and tBoard.daily[1].Score) or 0 })
	end
end

-------------------------------------------------------------------------------- prompts
local tPrompted: { [Player]: boolean } = {}

local function moment(p: Player, kind: string)
	if not PR.Moments[kind] or tPrompted[p] or not p.Parent then return end
	if os.clock() - (tJoined[p] or os.clock()) < PR.MinSessionMins * 60 then return end
	local pr = mProfile:GetAsync(p, "Prompts") or {}
	local now = os.time()
	local cd = PR.CooldownDays * 86400
	local what = nil
	if now - (pr.Fav or 0) > cd then what = "Favorite" elseif now - (pr.Notif or 0) > cd then what = "Notify" end
	if not what then return end
	tPrompted[p] = true
	Economy:SetProfileKey(p, "Prompts", function(v)
		v = v or {}
		if what == "Favorite" then v.Fav = now else v.Notif = now end
		return v
	end)
	oEvent:FireClient(p, { a = "Prompt", what = what })
	Analytics:Log(p, if what == "Favorite" then "prompt_favorite" else "prompt_notify", { moment = kind })
end

-- Studio QA hooks (DebugServer)
function Retention.QASetActive(self, p: Player, secs: number)
	tActive[p] = secs
	syncGift(p)
end
function Retention.QAMoment(self, p: Player, kind: string): string
	tJoined[p] = os.clock() - PR.MinSessionMins * 60 - 1
	tPrompted[p] = nil
	moment(p, kind)
	return if tPrompted[p] then "prompted" else "skipped (cooldown)"
end

-------------------------------------------------------------------------------- lifecycle
function Retention.StartAsync(self)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	Flight = require(ServerStorage.ServerModules.FlightServer)
	local Combat = require(ServerStorage.ServerModules.CombatServer)
	local MasteryS = require(ServerStorage.ServerModules.MasteryServer)

	Combat.OnKill.Event:Connect(function(killer: Player?, victim: Model)
		if not killer or victim:GetAttribute("Friendly") then return end
		local isPlayer = victim:GetAttribute("OwnerUserId") ~= nil
		local isBot = victim:GetAttribute("NpcKind") == "BotPilot"
		if not isPlayer and not isBot then return end
		tKills[killer] = (tKills[killer] or 0) + 1
		setStat(killer, "Kills", tKills[killer])
		score(killer, if isPlayer then B.KillWeight else B.BotWeight)
		if tKills[killer] == 1 then moment(killer, "FirstKill") end
	end)
	Economy.OnRankUp.Event:Connect(function(p: Player, r: number)
		setStat(p, "Rank", r)
		moment(p, "RankUp")
	end)
	Economy.OnMultiKill.Event:Connect(function(p: Player, n: number) if n >= 2 then moment(p, "MultiKill") end end)
	Economy.OnReward.Event:Connect(function(p: Player, key: string)
		if key == "FortressShare" then moment(p, "BossPayout") elseif key == "SeasonTier" then moment(p, "SeasonTier") end
	end)
	MasteryS.OnLevel.Event:Connect(function(p: Player) moment(p, "Mastery") end)

	buildBoard()
	task.spawn(function() while true do task.wait(1); tickGifts() end end)
	task.spawn(function() while true do task.wait(B.FlushSecs); flush() end end)
	task.spawn(function()
		task.wait(5)
		while true do refreshBoards(); task.wait(B.RefreshSecs) end
	end)
	game:BindToClose(function() flush() end)
end

function Retention.InitProfileAsync(self, p: Player)
	tActive[p], tNext[p], tKills[p], tJoined[p] = 0, 1, 0, os.clock()
	tNames[p.UserId] = p.DisplayName
	leaderstats(p)
	task.delay(3, function() if p.Parent then syncGift(p) end end)
end

function Retention.PlayerRemoving(self, p: Player)
	tActive[p], tNext[p], tKills[p], tJoined[p], tPrompted[p] = nil, nil, nil, nil, nil
end

return Retention
