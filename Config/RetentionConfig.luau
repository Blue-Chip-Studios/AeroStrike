--!strict
--[[
    RetentionConfig: session-length and come-back levers.
      Playtime  - free gifts at minutes into the session (only active time counts: not while
                  dead on the relaunch screen), granted automatically with a toast.
      Boards    - daily / weekly Top Aces (player kills + AI pilot kills) on OrderedDataStores,
                  shown on a board on the carrier deck and as your rank on the progress card.
      Prompts   - after a high point, ask to favourite the game / turn on notifications
                  (at most once per CooldownDays each, never in the first MinSessionMins).
]]

return {
	Playtime = {
		-- At = active minutes into this session
		Gifts = {
			{ At = 3, Cash = 150, Label = "3-MINUTE GIFT" },
			{ At = 7, Cash = 300, Label = "7-MINUTE GIFT" },
			{ At = 12, Cash = 500, Label = "12-MINUTE GIFT" },
			{ At = 20, Cash = 800, Label = "20-MINUTE GIFT" },
			{ At = 30, Cash = 1200, Label = "30-MINUTE GIFT" },
		},
		DeadGrace = 20, -- seconds on the relaunch screen that still count as active
		InputGrace = 40, -- a second only counts if the player gave real input within this many seconds
	},
	Boards = {
		Size = 10,
		RefreshSecs = 90, -- read the top 10
		FlushSecs = 45, -- write batched kill increments
		KillWeight = 1, -- per player kill
		BotWeight = 1, -- per AI pilot kill (bots fill quiet servers)
		NpcWeight = 0, -- drones / bombers don't count
	},
	Prompts = {
		MinSessionMins = 2, -- was 4: 77% of sessions ended before minute 5, so almost nobody saw them
		CooldownDays = 3,
		-- "Enjoying AeroStrike? Give it a thumbs up": a plain on-screen reminder (no reward: Roblox forbids paying
		-- for likes). Only at big high points, only once a player has flown a while, at most once a week.
		-- The game page showed 4 likes / 5 dislikes and ads converted only 14% of clicks into plays.
		LikeCooldownDays = 7,
		LikeMinSessionMins = 5,
		LikeMoments = { MultiKill = true, BossPayout = true, RankUp = true, SeasonTier = true, Mastery = true },
		InviteCooldownDays = 1, -- "invite a friend, you both get +500" (SeasonConfig.Invite pays it when they join)
		-- moments that trigger a prompt (server -> client "Moment")
		Moments = { FirstKill = true, MultiKill = true, BossPayout = true, RankUp = true, SeasonTier = true, Mastery = true },
	},
}
