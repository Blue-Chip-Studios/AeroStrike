# Temporary art tracker

Anything here is a stand-in that must be replaced before launch.

| Item | Where | Replace with |
| --- | --- | --- |
| Touch buttons and panels use rounded frames, not the chamfer 9-slice | `Gui/Components.luau` | Chamfer 9-slice images from the design system |
| Ocean edge visible past ±6 km | Terrain | Extend the water ring and fog the horizon |
| Island terrain is procedural (`Tools/BuildIsland.luau`) with Blender props; no hand-sculpted landmarks yet | Map | Hand-sculpt the volcano summit and canyon mouth; add a lava-glow decal pass |
| Ship sinking has no fire/smoke trail or water splash yet | `NpcServer.Remove` (ship branch) | Burning-deck flipbook, smoke column and a foam ring at the waterline |
| Canyon gate rings are one Blender ring scaled 1.6x | `MissionClient.buildGates` | Dedicated gate mesh with a numbered panel and a pass-through flash |
| Engine, sub-rumble, tension drone, G-breath, catapult, sonic boom, explosion and VO are still v1 takes (measured clean, no whistle) | `Config/AudioConfig.luau` | Optional: audition the other ElevenLabs takes for extra weight; the flyby keeps a realistic doppler whine (quiet, distance-attenuated) |
| AI aircraft (bomber, drone), carrier and ships are flat colours (jets + interceptors now have PBR skins) | NPC / carrier Blender models | Same UV + bake pipeline as the jets (panel-line skins); hull rust/weathering for ships |
