--[[
    BuildIsland (Studio tool, run via the command bar / MCP in Edit mode).
    Writes the Kestrel Archipelago into workspace.Terrain from the shared
    IslandShape height field, in row bands so Studio stays responsive:

        require(path.to.BuildIsland)(bandIndex, bandCount)

    Ball-filled surface (stylised, soft and chunky) over a block-filled core.
    Re-runnable: each band clears its own area first.
]]

return function(band: number, bands: number)
	local IslandShape = require(game.ReplicatedStorage.Shared.IslandShape)
	local T = workspace.Terrain
	local STEP = 20
	local R = 17
	local rx, rz = IslandShape.Radii.X + 300, IslandShape.Radii.Y + 300
	local z0 = -rz + (2 * rz) * (band - 1) / bands
	local z1 = -rz + (2 * rz) * band / bands
	local cols = 0
	for z = z0, z1, STEP do
		for x = -rx, rx, STEP do
			local h = IslandShape.Height(x, z)
			if h > -6 then
				local mat = IslandShape.Material(x, z, h)
				local core = h - R * 0.6
				if core > -14 then
					T:FillBlock(CFrame.new(x, (core + -14) / 2, z), Vector3.new(STEP, core + 14, STEP), mat)
				end
				T:FillBall(Vector3.new(x, h - R * 0.55, z), R, mat)
				cols += 1
			end
		end
		task.wait()
	end
	return cols
end
