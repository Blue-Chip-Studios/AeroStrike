--!strict
--[[
    AudioConfig: every sound (ElevenLabs-generated, uploaded to the group).
    Source files live in Assets/Audio/ (v2/ = de-whistled / synthesised
    replacements). Region = PlaybackRegion seconds. Keep loops warm: no
    narrow tones above ~1.5 kHz and never pitch warnings up in code.
]]

export type SoundDef = { Id: number, Volume: number?, Looped: boolean?, Speed: number?, Region: { number }?, Length: number?, MinDist: number?, MaxDist: number? }

local Sounds: { [string]: SoundDef } = {
	-- engine / thrust
	EngineCruise = { Id = 71137084083300, Volume = 0.35, Looped = true, Region = { 1, 28 } },
	Afterburner = { Id = 94190121325361, Volume = 0, Looped = true },
	AfterburnerIgnite = { Id = 70478704151069, Volume = 0.9, Length = 3 },
	SubRumble = { Id = 73721274702290, Volume = 0, Looped = true, Region = { 1, 28 } },
	WindRush = { Id = 107073339103440, Volume = 0, Looped = true, Region = { 1, 19 } },
	Catapult = { Id = 117926544522786, Volume = 1, Length = 6 },
	SonicBoom = { Id = 98651655728623, Volume = 1, Length = 8 },
	Flyby = { Id = 92497960686008, Volume = 1, Length = 5, MinDist = 60, MaxDist = 900 },

	-- weapons
	Cannon = { Id = 104450152227652, Volume = 0.85, Looped = true, Region = { 0.05, 2.9 } },
	CannonSpindown = { Id = 117026329760492, Volume = 0.55, Region = { 0, 2.5 } },
	MissileLaunch = { Id = 70728325937485, Volume = 0.9, Length = 4.5 },
	MissileThump = { Id = 108279360914003, Volume = 1, Length = 2.5 },
	Flares = { Id = 103369936686883, Volume = 0.9, Length = 3.5 },
	HitTicks = { Id = 78625431563881, Volume = 0.8, Length = 1.3 },
	Explosion = { Id = 132866311359837, Volume = 1, Length = 7, MinDist = 80, MaxDist = 2500 },

	-- hunter / prey language
	LockSeek = { Id = 104220956615053, Volume = 0.4, Looped = true },
	LockTone = { Id = 138588817473642, Volume = 0.4, Looped = true },
	MissileWarning = { Id = 74658418992258, Volume = 0.8, Looped = true },
	MissileWarningFast = { Id = 130928057701176, Volume = 0.8, Looped = true },
	LockedWarning = { Id = 118206181133532, Volume = 0.45, Looped = true },
	PullUp = { Id = 90731817931499, Volume = 0.55, Looped = true },

	-- tension layer
	TensionDrone = { Id = 106139770557782, Volume = 0, Looped = true, Region = { 1, 29 } },
	Heartbeat = { Id = 130316256998756, Volume = 0, Looped = true },
	GBreath = { Id = 136775446821196, Volume = 0, Looped = true },
	AirframeGroan = { Id = 89938237523069, Volume = 0.6, Length = 6 },
	EvadeWhoosh = { Id = 105225371038575, Volume = 0.9, Length = 2 },

	-- rewards
	Reward = { Id = 96247104118139, Volume = 0.6, Length = 2.6 },
	KillStinger = { Id = 111154763801301, Volume = 0.8, Length = 3 },

	-- radio voice ("Jerry B. - Military Commander", ElevenLabs v4)
	VO_MissileBreak = { Id = 106601564379782, Volume = 1, Length = 3.2 },
	VO_FoxTwo = { Id = 83580624894506, Volume = 0.9, Length = 2.2 },
	VO_SplashOne = { Id = 137084005682984, Volume = 1, Length = 2.6 },
	VO_EnemyLock = { Id = 133379536970488, Volume = 0.9, Length = 3 },
	VO_MissileDefeated = { Id = 80776064163153, Volume = 0.9, Length = 3.2 },
	VO_CatapultArmed = { Id = 119282332237658, Volume = 0.9, Length = 3 },
}

return {
	Sounds = Sounds,
	SonicBoomKmh = 860,
	MissileDangerRange = 1500, -- studs; warning tempo/heartbeat scale inside this
	VOCooldown = { VO_MissileBreak = 6, VO_FoxTwo = 4, VO_SplashOne = 3, VO_EnemyLock = 10, VO_MissileDefeated = 10, VO_CatapultArmed = 30 },
}
