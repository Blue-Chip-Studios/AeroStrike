--!strict
--[[
    FlightModel
    -----------
    Pure, deterministic arcade flight step shared by client (simulation) and
    server (validation bounds). No Instances, no side effects.

    "Aim to fly": the player supplies a world-space aim direction; the jet
    rotates its nose toward it at a speed-dependent turn rate and banks into
    the turn automatically. Optional manual roll for advanced pilots.
]]

local FlightConfig = require(script.Parent.Parent.Config.FlightConfig)

export type Stats = {
	MinSpeed: number, CruiseSpeed: number, MaxSpeed: number,
	Accel: number, TurnRate: number, CornerSpeed: number,
	RollRate: number, Fuel: number, FuelBurn: number, BoostBurn: number,
	GTolerance: number,
}

export type State = {
	CFrame: CFrame,
	Speed: number,
	Fuel: number,
	G: number,
	Bank: number,
	OverGTime: number,
	GLocTimer: number,
	FreeBoost: number,
	Stalled: boolean?,
	Strain: number?, -- 0..1 G strain (1 = G-LOC)
	Omega: number?, -- current turn rate (rad/s), ramps up with AngAccel
	Flameout: boolean?,
}

export type Input = {
	AimDir: Vector3, -- unit, world space
	Boost: boolean, -- afterburner
	Brake: boolean, -- legacy (unused; throttle replaces it)
	Throttle: number?, -- 0..1 set-and-hold throttle (military power at 1)
	Roll: number, -- -1..1 manual roll (0 = auto bank)
	Gear: boolean?, -- landing gear down (drag, speed limit)
}

local FlightModel = {}

function FlightModel.NewState(cf: CFrame, speed: number, fuel: number): State
	return { CFrame = cf, Speed = speed, Fuel = fuel, G = 1, Bank = 0, OverGTime = 0, GLocTimer = 0, FreeBoost = 0, Strain = 0, Omega = 0 }
end

-- Turn-rate multiplier from speed: peaks at the corner speed.
function FlightModel.TurnCurve(speed: number, s: Stats): number
	if speed <= s.CornerSpeed then
		local t = math.clamp((speed - s.MinSpeed) / math.max(s.CornerSpeed - s.MinSpeed, 1), 0, 1)
		return FlightConfig.TurnLowSpeedMult + (1 - FlightConfig.TurnLowSpeedMult) * t
	end
	local t = math.clamp((speed - s.CornerSpeed) / math.max(s.MaxSpeed - s.CornerSpeed, 1), 0, 1)
	return 1 - (1 - FlightConfig.TurnHighSpeedMult) * t
end

local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): (Vector3, number)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle < 1e-4 then return to, 0 end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-6 then axis = Vector3.yAxis end
	local step = math.min(angle, maxAngle)
	return (CFrame.fromAxisAngle(axis.Unit, step) * from).Unit, step
end

--[[
    Step the simulation. Returns the new state (mutates and returns `st`).
    gTolerance bonus (G-suit upgrades / pass) is folded into stats by caller.
]]
function FlightModel.Step(st: State, input: Input, s: Stats, dt: number): State
	local cf = st.CFrame
	local fwd = cf.LookVector

	-- clamp aim within MaxAimAngle of the nose so huge swipes stay sane
	local aim = input.AimDir
	if aim.Magnitude < 0.5 then aim = fwd end
	aim = aim.Unit
	local aimAngle = math.acos(math.clamp(fwd:Dot(aim), -1, 1))
	if aimAngle > FlightConfig.MaxAimAngle then
		aim = rotateToward(fwd, aim, FlightConfig.MaxAimAngle)
	end

	-- turn rate with speed curve and over-G stiffening
	local overG = math.clamp((st.G - s.GTolerance) / math.max(FlightConfig.GMax - s.GTolerance, 1), 0, 1)
	local glocMult = if st.GLocTimer > 0 then 0.35 else 1
	local rate = s.TurnRate * FlightModel.TurnCurve(st.Speed, s) * (1 - FlightConfig.GStiffen * overG) * glocMult
	-- roll-in: a hard turn only bites once the jet has banked into it
	local wantBank = math.abs(math.clamp(-(cf.RightVector:Dot(aim - fwd)) * FlightConfig.BankFactor * 3, -FlightConfig.MaxBank, FlightConfig.MaxBank))
	if wantBank > 0.35 then
		local banked = math.clamp(math.abs(st.Bank) / wantBank, 0, 1)
		rate *= FlightConfig.RollInMin + (1 - FlightConfig.RollInMin) * banked
	end
	-- stall: below the stall speed the controls go mushy and the nose drops;
	-- the stall speed rises when you pull G (accelerated stall)
	local stallSpeed = s.MinSpeed * FlightConfig.StallMult * (1 + FlightConfig.AccelStall * math.max(0, st.G - 1))
	st.Stalled = st.Speed < stallSpeed
	if st.Stalled then
		rate *= FlightConfig.StallAuthority
		aim = (aim + Vector3.new(0, -FlightConfig.StallNoseDrop, 0)).Unit
	end
	if st.GLocTimer > 0 then
		-- blacked out: hands off the stick, the jet flies on where it was pointing
		aim = fwd
	end
	-- turn-in lag: the turn rate builds up instead of snapping to full
	local wantAngle = math.acos(math.clamp(fwd:Dot(aim), -1, 1))
	local wantRate = math.min(rate, wantAngle / math.max(dt, 1e-3))
	local om = st.Omega or 0
	local acc = s.TurnRate * FlightConfig.AngAccel * dt
	om = if wantRate > om then math.min(wantRate, om + acc) else math.max(wantRate, om - acc * 2)
	st.Omega = om
	local newFwd, turned = rotateToward(fwd, aim, om * dt)
	local omega = turned / math.max(dt, 1e-3)

	-- auto-bank: roll into the turn based on lateral component of the turn
	local right = cf.RightVector
	local lateral = right:Dot(aim - fwd)
	local targetBank = math.clamp(-lateral * FlightConfig.BankFactor * 3, -FlightConfig.MaxBank, FlightConfig.MaxBank)
	if math.abs(input.Roll) > 0.05 then
		targetBank = st.Bank - input.Roll * s.RollRate * dt * 2
	end
	local bankLerp = math.clamp(dt * 4, 0, 1)
	st.Bank = st.Bank + (targetBank - st.Bank) * bankLerp
	if math.abs(input.Roll) > 0.05 then
		-- manual roll may go past MaxBank (barrel rolls); wrap it
		st.Bank = (st.Bank + math.pi) % (2 * math.pi) - math.pi
	end

	-- build orientation: look along newFwd, up = world up rotated by bank
	local flatUp = Vector3.yAxis
	if math.abs(newFwd:Dot(flatUp)) > 0.98 then flatUp = cf.UpVector end
	local base = CFrame.lookAt(Vector3.zero, newFwd, flatUp)
	local oriented = base * CFrame.Angles(0, 0, st.Bank)

	-- speed
	local hasFuel = st.Fuel > 0
	st.Flameout = not hasFuel
	local boosting = hasFuel and (input.Boost or st.FreeBoost > 0)
	local throttle = math.clamp(if input.Throttle ~= nil then input.Throttle else 0.75, 0, 1)
	if hasFuel then
		local milSpeed = s.CruiseSpeed * FlightConfig.MilPowerMult
		local idle = s.MinSpeed * FlightConfig.IdleSpeedMult
		local target = idle + (milSpeed - idle) * throttle
		if boosting then target = s.MaxSpeed end
		if input.Gear then target = math.min(target, s.CruiseSpeed * FlightConfig.GearSpeedMult) end
		local accel = s.Accel * (if boosting then 1.4 else 1)
		if st.Speed < target then
			st.Speed = math.min(target, st.Speed + accel * dt)
		else
			-- above the throttle's speed: drag bleeds it off gently (dives keep their energy);
			-- idle throttle opens the speedbrake
			local decel = if throttle < 0.08 and not boosting then accel * 0.8 else FlightConfig.OverspeedDrag
			st.Speed = math.max(target, st.Speed - decel * dt)
		end
	else
		-- flameout: no thrust at all; only diving keeps your airspeed up
		st.Speed -= FlightConfig.FlameoutDrag * dt
	end
	-- climbing costs speed, diving gains it (energy feel)
	local pitch = newFwd.Y
	if pitch > 0 then
		st.Speed -= pitch * FlightConfig.ClimbDrag * dt
	else
		st.Speed += -pitch * FlightConfig.DiveGain * dt
	end
	-- hard turns bleed energy: sustained high G slows you down (manage throttle/afterburner)
	st.Speed -= math.max(0, st.G - FlightConfig.BleedStartG) * FlightConfig.TurnBleed * dt
	st.Speed = math.clamp(st.Speed, s.MinSpeed * FlightConfig.FloorSpeedMult, s.MaxSpeed * 1.15)

	-- fuel
	local burn = if hasFuel then s.FuelBurn * (0.4 + 0.8 * throttle) + (if input.Boost and st.FreeBoost <= 0 then s.BoostBurn else 0) else 0
	st.Fuel = math.max(0, st.Fuel - burn * dt)
	st.FreeBoost = math.max(0, st.FreeBoost - dt)

	-- G-force (smoothed)
	local rawG = 1 + omega * st.Speed * FlightConfig.GScale
	st.G = st.G + (math.clamp(rawG, 0, FlightConfig.GMax) - st.G) * math.clamp(dt * 5, 0, 1)
	-- G strain: builds above tolerance (faster the harder you pull), drains below it
	local strain = st.Strain or 0
	if st.GLocTimer <= 0 then
		local over = (st.G - s.GTolerance) / math.max(FlightConfig.GMax - s.GTolerance, 1)
		if over > 0 then
			strain += over * FlightConfig.StrainRate * dt
		else
			strain -= FlightConfig.StrainRecover * dt
		end
		strain = math.clamp(strain, 0, 1)
		if strain >= 1 then
			st.GLocTimer = FlightConfig.GLocDuration
		end
	else
		st.GLocTimer = math.max(0, st.GLocTimer - dt)
		if st.GLocTimer <= 0 then strain = FlightConfig.GLocAfterStrain end
	end
	st.Strain = strain
	st.OverGTime = strain -- legacy field (HUD/camera read Strain now)

	-- integrate position
	local pos = cf.Position + newFwd * st.Speed * dt
	st.CFrame = CFrame.new(pos) * oriented.Rotation
	return st
end

return FlightModel
