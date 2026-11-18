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
| No island yet (open ocean only) | Map | Kestrel Archipelago: Blender rock/arch/pine kit + terrain (GDD §11) |
| No audio | All | ElevenLabs SFX/VO set (GDD §27) |
