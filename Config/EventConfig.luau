--!strict
--[[
    EventConfig: timed live events (times are UTC; Roblox servers run on UTC).
    EconomyServer multiplies cash rewards by CashMult while an event is live, and
    publishes the active event to clients (workspace attributes EventName / EventEnds)
    for the HUD banner. Add a row to schedule another event; nothing else to change.
]]

export type Event = { Id: string, Name: string, CashMult: number, Start: number, End: number }

local function utc(y: number, mo: number, d: number, h: number?, mi: number?): number
	-- os.time() reads the table as local time; on Roblox servers local time is UTC
	return os.time({ year = y, month = mo, day = d, hour = h or 0, min = mi or 0, sec = 0 })
end

local Events: { Event } = {
	-- last weekend of the launch ad window: a reason for lapsed players to come back
	{ Id = "DoubleCashWeekend1", Name = "DOUBLE CASH WEEKEND", CashMult = 2, Start = utc(2026, 11, 28), End = utc(2026, 11, 30, 23, 59) },
}

local function Active(now: number?): Event?
	local t = now or os.time()
	for _, e in ipairs(Events) do
		if t >= e.Start and t <= e.End then return e end
	end
	return nil
end

return {
	Events = Events,
	Active = Active,
}
