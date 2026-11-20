--!strict
--[[
    FTUEConfig: the first 10 minutes (GDD §7). Played in the live map with a
    private, client-local training lane in front of the carrier's bow.
    Prompts are one line + one action; {KEY} tokens are swapped per device.
    Offsets are in carrier space (bow = -Z).
]]

export type Step = { Id: string, Prompt: { Touch: string, Pad: string, Mouse: string }, Skippable: boolean? }

local Steps: { Step } = {
	{ Id = "spawned_on_catapult", Prompt = { Touch = "Tap BOOST in the green zone to launch!", Pad = "Press RT in the green zone to launch!", Mouse = "Press W in the green zone to launch!" } },
	{ Id = "launched", Prompt = { Touch = "You're airborne, ace!", Pad = "You're airborne, ace!", Mouse = "You're airborne, ace!" } },
	{ Id = "guns", Prompt = { Touch = "Hold GUNS and shoot the orange drone (aim at the green pip)", Pad = "Hold RB and shoot the orange drone (aim at the green pip)", Mouse = "Hold left mouse and shoot the orange drone (aim at the green pip)" }, Skippable = true },
	{ Id = "lock_and_fire", Prompt = { Touch = "Keep the drone in the circle until LOCK, then tap MISSILE", Pad = "Keep the drone in the circle until LOCK, then press LB", Mouse = "Keep the drone in the circle until LOCK, then right-click" }, Skippable = true },
	{ Id = "first_upgrade", Prompt = { Touch = "Free upgrade: +1 Flare Pod!", Pad = "Free upgrade: +1 Flare Pod!", Mouse = "Free upgrade: +1 Flare Pod!" } },
	{ Id = "go_live", Prompt = { Touch = "You're cleared hot. Hunt the bombers!", Pad = "You're cleared hot. Hunt the bombers!", Mouse = "You're cleared hot. Hunt the bombers!" } },
	{ Id = "first_kill_or_mission", Prompt = { Touch = "", Pad = "", Mouse = "" } },
}

return {
	Steps = Steps,
	Rings = { -- carrier-space offsets: straight out ahead of the bow, climbing gently
		Vector3.new(9, 150, -700), -- on the natural climb-out line: an instant first win
		Vector3.new(70, 250, -1200), -- small turns teach steering
		Vector3.new(-50, 290, -1700),
	},
	RingRadius = 30, -- pass within this of a ring centre to count
	BoostHoldTime = 1.5,
	GunHitsNeeded = 3,
	GTarget = 5.5, -- G to hold for pull_g
	GHoldTime = 0.8,
	SkipAfterSeconds = 20,
	TrainingSamDelay = 1.5,
	TrainingSamDistance = 1100,
	TrainingShieldMax = 150, -- seconds of tutorial flight with the training shield (then the AI can engage)
	-- 50/50 TEST: new players get the tutorial ("Tutorial") or go straight into the fight with just-in-time
	-- tips only ("Direct"). Split by UserId so it's stable across sessions and the same in every module.
	-- MetricsServer reports both groups side by side; set Enabled = false to give everyone the tutorial.
	ABTest = { Enabled = true },
	VariantFor = function(userId: number): string
		return if userId % 2 == 0 then "Tutorial" else "Direct"
	end,
}
