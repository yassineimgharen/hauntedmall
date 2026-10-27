-- Per-player token bucket. Used by Net.handle to cap how often each remote can be fired.

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(ratePerSecond: number, burst: number)
	local self = setmetatable({
		_rate = ratePerSecond,
		_burst = burst,
		_buckets = {} :: { [Player]: { tokens: number, last: number } },
	}, RateLimiter)

	Players.PlayerRemoving:Connect(function(player)
		self._buckets[player] = nil
	end)

	return self
end

function RateLimiter:allow(player: Player): boolean
	local now = os.clock()
	local bucket = self._buckets[player]
	if not bucket then
		bucket = { tokens = self._burst, last = now }
		self._buckets[player] = bucket
	end

	bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.last) * self._rate)
	bucket.last = now

	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

return RateLimiter
