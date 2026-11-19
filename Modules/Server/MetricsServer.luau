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

    Detail (mechanics + funnel):
        tt_<event>/ttn_<event>     seconds from join to an event's first occurrence (new players): sum / count
        nd_<dev>_<event>           new-player funnel split by device
        m_<key>, mn_<key>          mechanics counters (all / new players): gun_shots, gun_hits, msl_fired, msl_unguided,
                                   msl_hit, msl_incoming, msl_taken, flare_used, flare_saved, sortie, sortie_secs
        sl_<bucket>, sln_<bucket>  sortie length (time alive) buckets; sk_<0|1|2|3p> kills per sortie
        death:<cause>, deathn:<cause>, death_rb:<band>:<cause>, killed_by:<AI|Player>:<weapon>, killedn_by:...
        kill:<weapon>, kill_t:<Player|AI>, sortie_jet:<jet>, kill_jet:<jet>, death_jet:<jet>
        earn:<rewardKey> (cash) / earn_n:<rewardKey>, cash_in:<sku>, cash_out:<sku>, rank_up:<r>, tt_rank<r>
        jet_unlock:<jet>, jet_unlock_mins:<jet>:<bucket>
        quit_phase:<phase>, quitn_phase:<phase>, quit_after_death, quitn_step:<last funnel step>,
        rank_end:<r>, rank_endn:<r>, sm_<minute>, smn_<minute> (session-length survival, capped at 60)
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
local DIMS = { "sku", "cause", "jet", "mission", "step", "reason", "at", "id", "where", "n", "moment", "tier", "weapon", "paint" }
local RETURN_DAYS = { 1, 2, 3, 7, 14 }

local Metrics = ModuleUtil.New({})

local oStore: DataStore? = nil
local nShard = 0
local tDay: { [number]: { [string]: number } } = {} -- [day] = counters
local tCohort: { [number]: { [string]: number } } = {} -- [cohortDay] = counters
type Sess = { start: number, new: boolean, cohort: number, seen: { [string]: boolean }, paid: boolean, errs: number,
	dev: string?, sortieAt: number?, sortieKills: number, sortieJet: string?, lastDeath: number?, step: string, stepN: number, rank0: number }
local tSess: { [Player]: Sess } = {}
-- funnel order for "where did new players stop" (ftue steps then session steps)
local FUNNEL = { "session_loaded", "ftue_spawned_on_catapult", "ftue_launched", "ftue_guns", "ftue_lock_and_fire", "ftue_first_upgrade",
	"ftue_go_live", "session_first_kill", "ftue_first_kill_or_mission", "session_first_bank", "session_first_upgrade" }
local FUNNEL_IDX: { [string]: number } = {}
for i, e in ipairs(FUNNEL) do FUNNEL_IDX[e] = i end
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

local function rankOf(p: Player): number
	local ls = p:FindFirstChild("leaderstats")
	local r = ls and ls:FindFirstChild("Rank")
	return if r and (r :: any).Value then tonumber((r :: any).Value) or 0 else 0
end

local function band(r: number): string
	if r <= 2 then return "r1_2" elseif r <= 5 then return "r3_5" elseif r <= 10 then return "r6_10" end
	return "r11p"
end

local function sbucket(secs: number): string
	if secs < 15 then return "lt15" elseif secs < 30 then return "15_30" elseif secs < 60 then return "30_60"
	elseif secs < 120 then return "1_2m" elseif secs < 240 then return "2_4m" elseif secs < 480 then return "4_8m" end
	return "8mp"
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
		local fi = FUNNEL_IDX[sEvent]
		if fi and fi > s.stepN then s.stepN = fi; s.step = sEvent end
		if s.new then
			add(tDay, d, "n_" .. sEvent)
			add(tDay, d, "tt_" .. sEvent, math.min(3600, math.floor(os.clock() - s.start)))
			add(tDay, d, "ttn_" .. sEvent)
			if s.dev and (string.sub(sEvent, 1, 5) == "ftue_" or string.sub(sEvent, 1, 8) == "session_") then
				add(tDay, d, `nd_{s.dev}_{sEvent}`)
			end
		end
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

-- Mechanics counters from gameplay code (high-frequency things like gun shots never go to AnalyticsService).
function Metrics.Mech(self, p: Player?, key: string, n: number?)
	local d = today()
	add(tDay, d, "m_" .. key, n or 1)
	local s = p and tSess[p]
	if s and s.new then add(tDay, d, "mn_" .. key, n or 1) end
end

-- Economy flows (AnalyticsServer.Economy)
function Metrics.Econ(self, p: Player, sFlow: string, nAmount: number, sTx: string, sSku: string?)
	local key = clean(sSku or sTx, 24)
	add(tDay, today(), (if sFlow == "Source" then "cash_in:" else "cash_out:") .. key, math.floor(nAmount))
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
			sess.dev = t.d
			add(tDay, today(), "dev_" .. t.d)
			if sess.new then
				add(tDay, today(), "devn_" .. t.d)
				for ev in pairs(sess.seen) do
					if string.sub(ev, 1, 5) == "ftue_" or string.sub(ev, 1, 8) == "session_" then add(tDay, today(), `nd_{t.d}_{ev}`) end
				end
			end
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

	-- gameplay hooks (other modules start in parallel; wait a beat so their events exist)
	task.defer(function()
		local SM = game:GetService("ServerStorage").ServerModules
		local okF, Flight = pcall(require, SM.FlightServer)
		local okC, Combat = pcall(require, SM.CombatServer)
		local okE, Economy = pcall(require, SM.EconomyServer)
		local function ownerOf(m: Model): Player?
			for _, pl in ipairs(Players:GetPlayers()) do
				local so = okF and Flight:GetSortie(pl)
				if so and so.Jet == m then return pl end
			end
			return nil
		end
		if okF then
			Flight.OnLaunched.Event:Connect(function(p: Player)
				local s = tSess[p]
				if not s then return end
				local so = Flight:GetSortie(p)
				s.sortieAt = os.clock(); s.sortieKills = 0
				local jid = so and so.Jet and so.Jet:GetAttribute("JetId")
				s.sortieJet = if typeof(jid) == "string" then jid else nil
				Metrics:Mech(p, "sortie")
				if s.sortieJet then add(tDay, today(), "sortie_jet:" .. s.sortieJet) end
			end)
			Flight.OnJetDestroyed.Event:Connect(function(p: Player, sCause: string)
				local s = tSess[p]
				if not s or sCause == "reset" then return end
				local d = today()
				local cause = clean((string.gsub(sCause, ":", "_")), 30)
				add(tDay, d, "death:" .. cause)
				add(tDay, d, `death_rb:{band(rankOf(p))}:{cause}`)
				if s.new then add(tDay, d, "deathn:" .. cause) end
				if s.sortieJet then add(tDay, d, "death_jet:" .. s.sortieJet) end
				if s.sortieAt then
					local alive = os.clock() - s.sortieAt
					add(tDay, d, "sl_" .. sbucket(alive)); Metrics:Mech(p, "sortie_secs", math.floor(alive))
					if s.new then add(tDay, d, "sln_" .. sbucket(alive)) end
					local k = s.sortieKills
					local kb = if k >= 3 then "3p" else tostring(k)
					add(tDay, d, "sk_" .. kb)
					if s.new then add(tDay, d, "skn_" .. kb) end
				end
				s.sortieAt = nil
				s.lastDeath = os.clock()
			end)
		end
		if okC then
			Combat.OnKill.Event:Connect(function(attacker: Player?, victim: Model, weapon: string)
				local d = today()
				local w = clean(tostring(weapon or "?"), 20)
				local vp = ownerOf(victim)
				if attacker then
					add(tDay, d, "kill:" .. w)
					add(tDay, d, "kill_t:" .. (if vp then "Player" else "AI"))
					local s = tSess[attacker]
					if s then
						s.sortieKills += 1
						if s.sortieJet then add(tDay, d, "kill_jet:" .. s.sortieJet) end
					end
				end
				if vp and tSess[vp] then
					local src = if attacker then "Player" else "AI"
					add(tDay, d, `killed_by:{src}:{w}`)
					if tSess[vp].new then add(tDay, d, `killedn_by:{src}:{w}`) end
				end
			end)
		end
		if okE then
			Economy.OnReward.Event:Connect(function(p: Player, key: string, cash: number?)
				local k = clean(tostring(key), 24)
				add(tDay, today(), "earn:" .. k, math.floor(tonumber(cash) or 0))
				add(tDay, today(), "earn_n:" .. k)
			end)
			Economy.OnRankUp.Event:Connect(function(p: Player, r: number)
				add(tDay, today(), "rank_up:" .. tostring(r))
				local s = tSess[p]
				if s and s.new then
					add(tDay, today(), "tt_rank" .. tostring(r), math.floor(os.clock() - s.start)); add(tDay, today(), "ttn_rank" .. tostring(r))
				end
			end)
			Economy.OnJetUnlocked.Event:Connect(function(p: Player, jet: string)
				add(tDay, today(), "jet_unlock:" .. tostring(jet))
				local s = tSess[p]
				if s then add(tDay, today(), `jet_unlock_mins:{jet}:{bucket(os.clock() - s.start)}`) end
			end)
		end
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
	add(tDay, d, "ver:" .. tostring(game.PlaceVersion)) -- which published version this server runs
	local sess: Sess = { start = os.clock(), new = cohort == d, cohort = cohort, seen = {}, paid = false, errs = 0,
		sortieKills = 0, step = "none", stepN = 0, rank0 = rankOf(p) }
	tSess[p] = sess
	for _, ev in ipairs(tPending[p] or {}) do
		if not sess.seen[ev] then
			sess.seen[ev] = true
			add(tDay, d, "u_" .. ev)
			local fi = FUNNEL_IDX[ev]
			if fi and fi > sess.stepN then sess.stepN = fi; sess.step = ev end
			if sess.new then add(tDay, d, "n_" .. ev); add(tDay, d, "tt_" .. ev, 0); add(tDay, d, "ttn_" .. ev) end
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
	local mins = math.min(60, math.floor(secs / 60))
	add(tDay, d, "sm_" .. mins)
	if s.new then add(tDay, d, "smn_" .. mins) end
	if s.dev then add(tDay, d, "sess_secs_dev:" .. s.dev, math.floor(secs)); add(tDay, d, "sess_n_dev:" .. s.dev) end
	-- where and how they left
	local phase = "Menu"
	local okF, Flight = pcall(require, game:GetService("ServerStorage").ServerModules.FlightServer)
	local so = okF and Flight.GetSortie and Flight:GetSortie(p)
	if so and so.Phase then phase = tostring(so.Phase) end
	add(tDay, d, "quit_phase:" .. phase)
	if s.new then add(tDay, d, "quitn_phase:" .. phase); add(tDay, d, "quitn_step:" .. s.step) end
	if s.lastDeath and os.clock() - s.lastDeath < 25 then
		add(tDay, d, "quit_after_death")
		if s.new then add(tDay, d, "quitn_after_death") end
	end
	local r = rankOf(p)
	add(tDay, d, "rank_end:" .. r)
	if s.new then add(tDay, d, "rank_endn:" .. r) end
end

return Metrics
