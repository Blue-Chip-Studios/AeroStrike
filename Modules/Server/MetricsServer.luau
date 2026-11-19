--!strict
--[[
    MetricsServer: our own aggregated game metrics, readable outside Roblox through Open Cloud
    (DataStore "AS_Metrics"), so live data can be pulled and analysed (Tools/metrics_report.py).
    Roblox's Creator Dashboard analytics stay the source for impressions / ads / platform numbers;
    this covers what happens inside the game, per UTC day.

    Each server buffers counters and merges them every FLUSH seconds with UpdateAsync into
        d<day>_s<shard>     daily counters
        c<cohortDay>_s<shard>  cohort counters (new players of that day and their returns)
    shard = hash(JobId) % SHARDS keeps any one key's write rate low. Keys starting "max_" merge by max.

    Daily counters (non-exhaustive):
        dau, new, returning, sessions, sess_secs, sess_new_n, sess_new_secs, sb_<bucket>, sbn_<bucket>,
        player_mins, server_mins, max_server_players, dev_<Touch|Gamepad|KBM>,
        robux, buys, buy_<sku>, payers (per session), e_<event>, e_<event>:<dim>,
        u_<event> (once per session), n_<event> (once per session, new players only), err_s:<msg>, err_c:<msg>
    Cohort counters: new, d1, d2, d3, d7, d14, payers, robux
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local MonetizationConfig = require(ReplicatedStorage.Config.MonetizationConfig)

local STORE = "AS_Metrics"
local SHARDS = 8
local FLUSH = 60
local DIMS = { "sku", "cause", "jet", "mission", "step", "reason" }
local RETURN_DAYS = { 1, 2, 3, 7, 14 }

local Metrics = ModuleUtil.New({})

local oStore: DataStore? = nil
local nShard = 0
local tDay: { [number]: { [string]: number } } = {} -- [day] = counters
local tCohort: { [number]: { [string]: number } } = {} -- [cohortDay] = counters
local tSess: { [Player]: { start: number, new: boolean, cohort: number, seen: { [string]: boolean }, paid: boolean, errs: number } } = {}
local oLimiter = ModuleUtil.RateLimiter(12, 60)
local tPending: { [Player]: { string } } = {} -- events seen before the profile loaded (replayed for u_/n_)

local function today(): number
	return math.floor(os.time() / 86400)
end

local function add(t: { [number]: { [string]: number } }, day: number, key: string, n: number?)
	local c = t[day]
	if not c then c = {}; t[day] = c end
	if string.sub(key, 1, 4) == "max_" then
		c[key] = math.max(c[key] or 0, n or 0)
	else
		c[key] = (c[key] or 0) + (n or 1)
	end
end

local function clean(s: string, len: number): string
	s = string.gsub(s, "%d+", "#")
	s = string.gsub(s, "[^%w%s%._:#%-]", "")
	return string.sub(s, 1, len)
end

local function bucket(secs: number): string
	local m = secs / 60
	if m < 1 then return "lt1" elseif m < 3 then return "1_3" elseif m < 5 then return "3_5"
	elseif m < 10 then return "5_10" elseif m < 20 then return "10_20" elseif m < 40 then return "20_40" end
	return "40p"
end

-- Called by AnalyticsServer for every logged event.
function Metrics.Count(self, p: Player, sEvent: string, tData: { [string]: any }?)
	local d = today()
	add(tDay, d, "e_" .. sEvent)
	if tData then
		for _, k in ipairs(DIMS) do
			local v = tData[k]
			if v ~= nil then add(tDay, d, `e_{sEvent}:{clean(tostring(v), 24)}`) end
		end
	end
	local s = tSess[p]
	if not s then
		local q = tPending[p]
		if not q then q = {}; tPending[p] = q end
		if #q < 20 then table.insert(q, sEvent) end
	end
	if s and not s.seen[sEvent] then
		s.seen[sEvent] = true
		add(tDay, d, "u_" .. sEvent)
		if s.new then add(tDay, d, "n_" .. sEvent) end
	end
	if sEvent == "shop_purchase_success" and tData and typeof(tData.sku) == "string" then
		local def = MonetizationConfig.Passes[tData.sku] or MonetizationConfig.Products[tData.sku]
		local price = (def and def.Price) or 0
		add(tDay, d, "robux", price); add(tDay, d, "buys"); add(tDay, d, "buy_" .. tData.sku)
		if s then
			add(tCohort, s.cohort, "robux", price)
			if not s.paid then
				s.paid = true
				add(tDay, d, "payers")
				add(tCohort, s.cohort, "payers")
			end
		end
	end
end

local function merge(key: string, delta: { [string]: number })
	if not oStore or next(delta) == nil then return true end
	local ok, err = pcall(function()
		(oStore :: DataStore):UpdateAsync(key, function(old: any)
			local t = if typeof(old) == "table" then old else {}
			for k, v in pairs(delta) do
				if string.sub(k, 1, 4) == "max_" then t[k] = math.max(t[k] or 0, v) else t[k] = (t[k] or 0) + v end
			end
			t._updated = os.time()
			return t
		end)
	end)
	if not ok then warn("[Metrics] flush failed", key, err) end
	return ok
end

local function flush()
	local d = today()
	-- per-minute load samples
	local n = #Players:GetPlayers()
	add(tDay, d, "server_mins"); add(tDay, d, "player_mins", n); add(tDay, d, "max_server_players", n)
	if not oStore then return end -- Studio: keep counting locally (Snapshot)
	local days, cohorts = tDay, tCohort
	tDay, tCohort = {}, {}
	for day, c in pairs(days) do
		if not merge(`d{day}_s{nShard}`, c) then
			for k, v in pairs(c) do add(tDay, day, k, v) end -- keep for the next try
		end
	end
	for day, c in pairs(cohorts) do
		if not merge(`c{day}_s{nShard}`, c) then
			for k, v in pairs(c) do add(tCohort, day, k, v) end
		end
	end
end

-- debug: current unflushed counters (Studio / AS_Debug)
function Metrics.Snapshot(self)
	local function strk(t)
		local o = {}
		for k, v in pairs(t) do o[tostring(k)] = v end
		return o
	end
	return { day = strk(tDay), cohort = strk(tCohort), shard = nShard }
end

function Metrics.StartAsync(self)
	local okS, s = pcall(function() return DataStoreService:GetDataStore(STORE) end)
	if okS and not RunService:IsStudio() then oStore = s end
	local h = 0
	for i = 1, #game.JobId do h = (h * 31 + string.byte(game.JobId, i)) % 1000003 end
	nShard = if game.JobId == "" then 0 else h % SHARDS

	ScriptContext.Error:Connect(function(msg: string)
		add(tDay, today(), "err_s:" .. clean(msg, 70))
	end)

	Remote:GetEvent("MetricsReport"):OnServerEvent(function(p: Player, t: any)
		if typeof(t) ~= "table" or not oLimiter:Check(p) then return end
		local sess = tSess[p]
		if not sess then return end
		if t.a == "Device" and (t.d == "Touch" or t.d == "Gamepad" or t.d == "KBM") and not sess.seen["_dev"] then
			sess.seen["_dev"] = true
			add(tDay, today(), "dev_" .. t.d)
			if sess.new then add(tDay, today(), "devn_" .. t.d) end
		elseif t.a == "Error" and typeof(t.m) == "string" and sess.errs < 8 then
			sess.errs += 1
			add(tDay, today(), "err_c:" .. clean(t.m, 70))
		end
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH)
			flush()
		end
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do Metrics:PlayerRemoving(p) end
		flush()
	end)
end

function Metrics.InitProfileAsync(self, p: Player, tProfile: any)
	local d = today()
	local data = tProfile and tProfile.Data
	if typeof(data) ~= "table" then return end
	local m = data.Meta
	if typeof(m) ~= "table" then m = {}; data.Meta = m end
	local isNew = (m.FirstDay or 0) == 0
	if isNew then m.FirstDay = d end
	local cohort = m.FirstDay
	local firstToday = (m.LastDay or 0) ~= d
	if firstToday then
		add(tDay, d, "dau")
		if isNew then
			add(tDay, d, "new"); add(tCohort, cohort, "new")
		else
			add(tDay, d, "returning")
			local age = d - cohort
			for _, k in ipairs(RETURN_DAYS) do
				if age == k then add(tCohort, cohort, "d" .. k) end
			end
		end
		m.DaysPlayed = (m.DaysPlayed or 0) + 1
	end
	m.LastDay = d
	m.Sessions = (m.Sessions or 0) + 1
	add(tDay, d, "sessions")
	local sess = { start = os.clock(), new = cohort == d, cohort = cohort, seen = {}, paid = false, errs = 0 }
	tSess[p] = sess
	for _, ev in ipairs(tPending[p] or {}) do
		if not sess.seen[ev] then
			sess.seen[ev] = true
			add(tDay, d, "u_" .. ev)
			if sess.new then add(tDay, d, "n_" .. ev) end
		end
	end
	tPending[p] = nil
end

function Metrics.PlayerRemoving(self, p: Player)
	tPending[p] = nil
	local s = tSess[p]
	if not s then return end
	tSess[p] = nil
	local secs = os.clock() - s.start
	local d = today()
	add(tDay, d, "sess_secs", math.floor(secs)); add(tDay, d, "sb_" .. bucket(secs))
	if s.new then
		add(tDay, d, "sess_new_n"); add(tDay, d, "sess_new_secs", math.floor(secs)); add(tDay, d, "sbn_" .. bucket(secs))
	end
end

return Metrics
