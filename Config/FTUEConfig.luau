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
	{ Id = "steer_rings", Prompt = { Touch = "Drag to steer. Fly through the green rings", Pad = "Left stick to steer. Fly through the green rings", Mouse = "Move the mouse to steer. Fly through the green rings" }, Skippable = true },
	{ Id = "afterburner", Prompt = { Touch = "Slide the THROTTLE up, then hold BOOST for afterburner (it burns fuel fast)", Pad = "Hold RT: throttle to 100%, keep holding for afterburner (it burns fuel fast)", Mouse = "Hold W: throttle to 100%, keep holding (or Shift) for afterburner. It burns fuel fast" }, Skippable = true },
	{ Id = "guns", Prompt = { Touch = "Hold GUNS and shoot the orange drone (aim at the green pip)", Pad = "Hold RB and shoot the orange drone (aim at the green pip)", Mouse = "Hold left mouse and shoot the orange drone (aim at the green pip)" }, Skippable = true },
	{ Id = "lock_and_fire", Prompt = { Touch = "Keep the drone in the circle until LOCK, then tap MISSILE", Pad = "Keep the drone in the circle until LOCK, then press LB", Mouse = "Keep the drone in the circle until LOCK, then right-click" }, Skippable = true },
	{ Id = "flare", Prompt = { Touch = "Incoming missile! Tap FLARE when it's close!", Pad = "Incoming missile! Press B when it's close!", Mouse = "Incoming missile! Press F when it's close!" }, Skippable = true },
	{ Id = "pull_g", Prompt = { Touch = "Pull a hard turn. Feel the G! Ease off before the strain bar fills or you'll black out", Pad = "Pull a hard turn. Feel the G! Ease off before the strain bar fills or you'll black out", Mouse = "Pull a hard turn. Feel the G! Ease off before the strain bar fills or you'll black out" }, Skippable = true },
	{ Id = "bank_it", Prompt = { Touch = "Fly low over the carrier deck to bank your cash", Pad = "Fly low over the carrier deck to bank your cash", Mouse = "Fly low over the carrier deck to bank your cash" }, Skippable = true },
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
}
