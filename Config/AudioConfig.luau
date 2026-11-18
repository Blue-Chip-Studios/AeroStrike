--!strict
--[[
    AudioConfig: every sound (ElevenLabs-generated, uploaded to the group).
    Source files live in Assets/Audio/. Region = PlaybackRegion seconds.
]]

export type SoundDef = { Id: number, Volume: number?, Looped: boolean?, Speed: number?, Region: { number }?, Length: number?, MinDist: number?, MaxDist: number? }

local Sounds: { [string]: SoundDef } = {
	-- engine / thrust
	EngineCruise = { Id = 129488943101631, Volume = 0.35, Looped = true, Region = { 1, 28 } },
	Afterburner = { Id = 132320742027687, Volume = 0, Looped = true, Region = { 1, 14 } },
	AfterburnerIgnite = { Id = 70478704151069, Volume = 0.9, Length = 3 },
	SubRumble = { Id = 73721274702290, Volume = 0, Looped = true, Region = { 1, 28 } },
	WindRush = { Id = 111304521239929, Volume = 0, Looped = true, Region = { 1, 19 } },
	Catapult = { Id = 117926544522786, Volume = 1, Length = 6 },
	SonicBoom = { Id = 98651655728623, Volume = 1, Length = 8 },
	Flyby = { Id = 92497960686008, Volume = 1, Length = 5, MinDist = 60, MaxDist = 900 },

	-- weapons
	Cannon = { Id = 111613763593210, Volume = 0.85, Looped = true, Region = { 0.05, 2.9 } },
	CannonSpindown = { Id = 89765310708000, Volume = 0.55, Region = { 0, 2.5 } },
	MissileLaunch = { Id = 88526319730197, Volume = 0.9, Length = 6 },
	MissileThump = { Id = 108279360914003, Volume = 1, Length = 2.5 },
	Flares = { Id = 124116277062949, Volume = 0.85, Length = 4 },
	HitTicks = { Id = 134309584977331, Volume = 0.7, Region = { 0, 1.2 } },
	Explosion = { Id = 132866311359837, Volume = 1, Length = 7, MinDist = 80, MaxDist = 2500 },

	-- hunter / prey language
	LockSeek = { Id = 104220956615053, Volume = 0.4, Looped = true },
	LockTone = { Id = 97516115545192, Volume = 0.45, Looped = true },
	MissileWarning = { Id = 119554254223618, Volume = 0.8, Looped = true },
	LockedWarning = { Id = 119554254223618, Volume = 0.45, Looped = true, Speed = 0.55 },

	-- tension layer
	TensionDrone = { Id = 106139770557782, Volume = 0, Looped = true, Region = { 1, 29 } },
	Heartbeat = { Id = 130316256998756, Volume = 0, Looped = true },
	GBreath = { Id = 136775446821196, Volume = 0, Looped = true },
	AirframeGroan = { Id = 89938237523069, Volume = 0.6, Length = 6 },
	EvadeWhoosh = { Id = 134387687428123, Volume = 0.9, Length = 2 },

	-- rewards
	Reward = { Id = 82518676180691, Volume = 0.6, Length = 3 },
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
