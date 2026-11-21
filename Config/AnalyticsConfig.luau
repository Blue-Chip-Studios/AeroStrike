--!strict
--[[
    AnalyticsConfig: the typed event catalogue. AnalyticsServer refuses any
    event not listed here, so names stay consistent. Client may only send
    events flagged ClientAllowed (UI interactions), rate-limited.
]]

export type EventDef = { Kind: "Custom" | "Funnel" | "Onboarding", Funnel: string?, Step: number?, ClientAllowed: boolean? }

local Onboarding = {
	"spawned_on_catapult", "launched", "guns", "lock_and_fire", "first_upgrade", "go_live", "first_kill_or_mission",
}

local Session = { "join", "loaded", "spawned", "launched", "first_shot", "first_lock", "first_kill", "first_bank", "first_upgrade" }
local Shop = { "shop_open", "product_view", "purchase_prompt", "purchase_success" }

local Events: { [string]: EventDef } = {}
for i, name in ipairs(Onboarding) do Events["ftue_" .. name] = { Kind = "Onboarding", Step = i } end
for i, name in ipairs(Session) do Events["session_" .. name] = { Kind = "Funnel", Funnel = "Session", Step = i } end
for i, name in ipairs(Shop) do Events["shop_" .. name] = { Kind = "Funnel", Funnel = "Shop", Step = i, ClientAllowed = i <= 2 } end

for _, name in ipairs({
	"sortie_end", "missile_fired", "missile_hit", "missile_evaded", "ace_evade", "flare_used", "g_loc", "fuel_empty",
	"bounty_start", "bounty_claimed", "mission_join", "mission_complete", "squad_create", "squad_join",
	"perfect_launch", "crash", "bank", "purchase_failed", "purchase_cancelled", "ftue_skip", "ftue_abandon",
	"landing", "multi_kill", "sonic_boom", "boss_spawn", "boss_kill", "challenge_done", "season_tier", "code_redeemed", "invite_reward", "group_reward",
	"playtime_gift", "revive_free", "ftue_direct", "redeploy_air", "rookie_bandit", "mastery_level", "badge_awarded", "prompt_favorite", "prompt_notify", "board_top10", "paint_equip",
}) do
	Events[name] = { Kind = "Custom" }
end
-- UI interaction events the client may send
for _, name in ipairs({ "ui_hangar_open", "ui_button", "ui_settings_open", "ui_daily_open" }) do
	Events[name] = { Kind = "Custom", ClientAllowed = true }
end

return {
	Events = Events,
	ClientRateLimit = { Count = 20, Window = 10 }, -- max client events per window (seconds)
}
