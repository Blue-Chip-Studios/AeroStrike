# Thumbnail 3: FLYING FORTRESS (boss event)
import bpy, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
sc = new_scene("THUMB_Fortress", 1920, 1080, samples=SAMPLES)
sc.render.resolution_percentage = PCT
cam = camera(sc, (0, 0, 0), (0, 100, 22), lens=32)
sunset_world(sc, strength=0.7)
sun(sc, rot=(math.radians(75), 0, math.radians(130)), energy=3.0, color='#ffbb88')
backdrop(sc, cam, dist=4000, top='#141a6a', mid='#a234c8', low='#ff5a2a', sun_uv=(0.12, 0.30), sun_size=0.045, horizon=0.24, mid_at=0.58)
ocean(sc, z=-24, color='#0b2f6e', rough=0.22, spec=0.22)

boss = copy_model("EXPORT_NPC_TalonBomber", sc, "Talon", "Fortress", glow_strength=60)
boss.location = (26, 270, 88)
boss.scale = (2.6, 2.6, 2.6)
boss.rotation_euler = Euler((math.radians(10), math.radians(-12), math.radians(-150)), 'XYZ')
area(sc, (-60, 200, 40), (8, 270, 92), energy=160000, size=60, color='#ffb070', name="BossKey")
area(sc, (90, 330, 150), (8, 270, 92), energy=90000, size=60, color='#b06aff', name="BossRim")

# hits on the boss
fireball(sc, (-2, 268, 84), size=15, name="Hit1", seed=5)
fireball(sc, (52, 285, 100), size=10, name="Hit2", seed=9)

# player jets diving in
j1 = copy_model("EXPORT_Jet_MakoSR9", sc, "Mako", "P1")
j1.location = (16, 62, 8)
j1.rotation_euler = Euler((math.radians(-24), math.radians(28), math.radians(150)), 'XYZ')
flame(j1, (0.72, 14.8, 0.3), length=8, radius=0.5); flame(j1, (-0.72, 14.8, 0.3), length=8, radius=0.5)
j2 = copy_model("EXPORT_Jet_WraithX", sc, "Wraith", "P2")
j2.location = (-30, 92, 20)
j2.rotation_euler = Euler((math.radians(-20), math.radians(-30), math.radians(-160)), 'XYZ')
flame(j2, (1.25, 14.5, 0.4), length=7, radius=0.45); flame(j2, (-1.25, 14.5, 0.4), length=7, radius=0.45)

# tracers (glowing streaks) from P1 to the boss
tr = emission_mat("Tracer", hexc('#ffd84a'), 40)
for i, (a, b) in enumerate([((14, 58, 9), (-20, 262, 86)), ((15, 60, 9.5), (-10, 265, 88)), ((13, 59, 8.5), (-28, 260, 85))]):
    d = Vector(b) - Vector(a)
    for k in range(5):
        p0 = Vector(a) + d * (0.18 * k + 0.05)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.18, depth=6)
        c = bpy.context.active_object
        for cc in list(c.users_collection): cc.objects.unlink(c)
        sc.collection.objects.link(c)
        c.location = p0; c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        c.data.materials.append(tr); c.visible_shadow = False
# missile trails from P2
smoke_trail(sc, [(-28, 96, 21), (-24, 150, 45), (-14, 210, 70), (-4, 262, 84)], radius=0.8, name="T1", alpha=0.9, taper_end=2.4)
smoke_trail(sc, [(-26, 95, 20), (-10, 160, 52), (20, 230, 82), (48, 280, 98)], radius=0.8, name="T2", alpha=0.9, taper_end=2.4)

pilot = avatar(sc, "Pilot", (-6.0, 15, -3.6), rot_z=math.radians(-24), shirt='#2e7bff', pants='#1d2433', skin='#e9b27c',
               face="face_grin.png", pose="cheer", helmet=True, helmet_color='#f2f2f2', visor='#2ad1ff', accent='#ffb020')
area(sc, (-2, 6, 4), (-6, 15, -3), energy=5000, size=8, color='#fff4ea', name="PilotKey")
area(sc, (-6, 22, 18), (-8, 30, 13.6), energy=2500, size=6, color='#ffffff', name="LogoKey")
lg, w = logo(sc, (-8.2, 30, 13.6), (math.radians(78), 0, 0), scale=0.5)
render(sc, ART_DIR + OUT)
