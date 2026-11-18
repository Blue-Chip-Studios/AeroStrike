# Temporary art tracker

Anything here is a stand-in that must be replaced before launch.

| Item | Where | Replace with |
| --- | --- | --- |
| Jet/ship materials are flat colours (no UVs or baked maps yet) | All Blender models, `JetConfig` / `MapConfig` / `NpcConfig` paints | UV-unwrap in Blender, bake panel-line normal + AO + metalness/roughness, use `SurfaceAppearance` (brief: metallic PBR jet bodies) |
| Missiles are untextured parts | `CombatServer` / `VfxController` proxy | Blender missile mesh (IR + multi-lock variants) |
| Flares are neon balls + default smoke texture | `VfxController.flares` | Stylised flare sprite and flipbook smoke |
| Explosions use built-in fire/smoke textures | `VfxController.explosion` | Stylised explosion flipbook + shockwave ring |
| Touch buttons and panels use rounded frames, not the chamfer 9-slice | `Gui/Components.luau` | Chamfer 9-slice images from the design system |
| Ocean edge visible past ±6 km | Terrain | Extend the water ring and fog the horizon |
| Island terrain is procedural (`Tools/BuildIsland.luau`) with Blender props; no hand-sculpted landmarks yet | Map | Hand-sculpt the volcano summit and canyon mouth; add a lava-glow decal pass |
| Ship sinking has no fire/smoke trail or water splash yet | `NpcServer.Remove` (ship branch) | Burning-deck flipbook, smoke column and a foam ring at the waterline |
| Canyon gate rings are one Blender ring scaled 1.6x | `MissionClient.buildGates` | Dedicated gate mesh with a numbered panel and a pass-through flash |
| Audio uses take 1 of each ElevenLabs generation | `Config/AudioConfig.luau`, flow "AeroStrike SFX v1" | Audition all 4 takes per sound in the ElevenLabs flow and swap ids for the best; consider true seamless loops for engine/drone |
