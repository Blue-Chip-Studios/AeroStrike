--!strict
--[[
    ModuleUtil
    ----------
    Wraps BCDK.CreateModule and fills every lifecycle hook the Loader calls
    with a no-op, so project modules only implement what they need (BCDK's
    template otherwise warns "not implemented" for each missing hook).
    Also: StripSuffix for Blender ".001" part names, and a tiny rate limiter.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BCDK = require(ReplicatedStorage.BCDKShared.BCDK)

local HOOKS = {
	"PreloadAsync", "StartAsync", "InitProfileAsync", "PlayerAdded",
	"PlayerRemoving", "ProfileReleased", "InitReplicaAsync",
}

local ModuleUtil = {}

function ModuleUtil.New<T>(t: T & {}): T
	local tt = t :: any
	for _, sHook in ipairs(HOOKS) do
		if tt[sHook] == nil then
			tt[sHook] = function() end
		end
	end
	return BCDK.CreateModule(tt) :: any
end

-- "Canopy.001" -> "Canopy"
function ModuleUtil.StripSuffix(s: string): string
	return (string.gsub(s, "%.%d+$", ""))
end

export type RateLimiter = { Check: (self: RateLimiter, key: any) -> boolean }

-- Allows `count` calls per `window` seconds per key.
function ModuleUtil.RateLimiter(count: number, window: number): RateLimiter
	local tBuckets: { [any]: { n: number, t: number } } = {}
	local rl = {}
	function rl.Check(_self, key: any): boolean
		local now = os.clock()
		local b = tBuckets[key]
		if not b or now - b.t > window then
			tBuckets[key] = { n = 1, t = now }
			return true
		end
		if b.n >= count then return false end
		b.n += 1
		return true
	end
	return rl :: any
end

return ModuleUtil
