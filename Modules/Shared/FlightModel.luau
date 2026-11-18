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
}

export type Input = {
	AimDir: Vector3, -- unit, world space
	Boost: boolean,
	Brake: boolean,
	Roll: number, -- -1..1 manual roll (0 = auto bank)
}

local FlightModel = {}

function FlightModel.NewState(cf: CFrame, speed: number, fuel: number): State
	return { CFrame = cf, Speed = speed, Fuel = fuel, G = 1, Bank = 0, OverGTime = 0, GLocTimer = 0, FreeBoost = 0 }
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
	local newFwd, turned = rotateToward(fwd, aim, rate * dt)
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
	local boosting = (input.Boost and hasFuel) or st.FreeBoost > 0
	local target = s.CruiseSpeed
	if boosting then target = s.MaxSpeed end
	if input.Brake then target = s.MinSpeed end
	if not hasFuel then target = math.min(target, s.MaxSpeed * FlightConfig.NoFuelSpeedCap) end
	local accel = s.Accel * (if boosting then 1.4 else 1)
	if st.Speed < target then
		st.Speed = math.min(target, st.Speed + accel * dt)
	else
		st.Speed = math.max(target, st.Speed - accel * 0.8 * dt)
	end
	-- climbing costs speed, diving gains it (energy feel)
	local pitch = newFwd.Y
	if pitch > 0 then
		st.Speed -= pitch * FlightConfig.ClimbDrag * dt
	else
		st.Speed += -pitch * FlightConfig.DiveGain * dt
	end
	st.Speed = math.clamp(st.Speed, s.MinSpeed, s.MaxSpeed * 1.15)

	-- fuel
	local burn = s.FuelBurn + (if input.Boost and st.FreeBoost <= 0 and hasFuel then s.BoostBurn else 0)
	st.Fuel = math.max(0, st.Fuel - burn * dt)
	st.FreeBoost = math.max(0, st.FreeBoost - dt)

	-- G-force (smoothed)
	local rawG = 1 + omega * st.Speed * FlightConfig.GScale
	st.G = st.G + (math.clamp(rawG, 0, FlightConfig.GMax) - st.G) * math.clamp(dt * 5, 0, 1)
	if st.G > FlightConfig.GLocThreshold and st.GLocTimer <= 0 then
		st.OverGTime += dt
		if st.OverGTime >= FlightConfig.GLocTime then
			st.GLocTimer = FlightConfig.GLocDuration
			st.OverGTime = 0
		end
	else
		st.OverGTime = math.max(0, st.OverGTime - dt)
	end
	st.GLocTimer = math.max(0, st.GLocTimer - dt)

	-- integrate position
	local pos = cf.Position + newFwd * st.Speed * dt
	st.CFrame = CFrame.new(pos) * oriented.Rotation
	return st
end

return FlightModel
