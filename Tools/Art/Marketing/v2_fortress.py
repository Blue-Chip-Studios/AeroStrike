# Thumbnail v2-3: FLYING FORTRESS boss at sunset above the clouds (no avatar)
import bpy, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
exec(open(ART_DIR + r"\thumbkit2.py", encoding="utf-8").read())
sc = scene2("V2_Fortress", 1920, 1080, samples=SAMPLES)
sc.render.resolution_percentage = PCT
cam = camera(sc, (0, 0, 0), (0, 100, 14), lens=32, roll=math.radians(5))
sky2(sc, sun_elev=SUN_ELEV, sun_rot=SUN_ROT, strength=1.0, altitude=1200, aerosol=2.0, ozone=3.0, sun_strength=5.0, sun_color='#ffb070')
cloud_sea(sc, z_bottom=-520, thickness=320, coverage=0.62, density=0.03, seed=23.0)
ocean2(sc, z=-1600)

B = Vector((95, 340, 88))
boss = jet2("EXPORT_NPC_TalonBomber", sc, "Talon", "Fortress", glow=60)
boss.location = B; boss.scale = (3.2, 3.2, 3.2)
boss.rotation_euler = Euler((math.radians(8), math.radians(-14), math.radians(-155)), 'XYZ')
area(sc, (-80, 220, 60), B, energy=200000, size=80, color='#c8d8ff', name="BossFill")
fireball2(sc, B + Vector((-30, -10, -6)), size=14, name="Hit1", seed=5)
fireball2(sc, B + Vector((34, 12, 8)), size=10, name="Hit2", seed=9)
contrail(sc, [B + Vector((-30, -10, -6)), B + Vector((-60, 30, -30)), B + Vector((-90, 90, -70))], radius=1.2, name="BossSmoke", alpha=0.25, grow=5.0, color='#6a6460')

j1 = jet2("EXPORT_Jet_MakoSR9", sc, "Mako", "P1")
J1 = Vector((4, 58, 4))
j1.location = J1
j1.rotation_euler = Euler((math.radians(-22), math.radians(34), math.radians(160)), 'XYZ')
flame2(j1, (0.72, 14.8, 0.3), length=9, radius=0.55); flame2(j1, (-0.72, 14.8, 0.3), length=9, radius=0.55)
area(sc, (-20, 20, 25), J1, energy=30000, size=25, color='#c8d8ff', name="P1Fill")
j2 = jet2("EXPORT_Jet_WraithX", sc, "Wraith", "P2")
J2 = Vector((-36, 110, 22))
j2.location = J2
j2.rotation_euler = Euler((math.radians(-16), math.radians(-34), math.radians(-168)), 'XYZ')
flame2(j2, (1.25, 14.5, 0.4), length=8, radius=0.5); flame2(j2, (-1.25, 14.5, 0.4), length=8, radius=0.5)
for i, off in enumerate([(-6, 0, 0), (0, 0, 3), (8, 0, -2)]):
    tracer(sc, J1 + Vector((0, -12, 1)), B + Vector(off) + Vector((-20, 0, -4)), n=6, name=f"Tr{i}")
contrail(sc, [J2 + Vector((0, -6, 0)), J2 + Vector((10, 60, 20)), B + Vector((-4, -40, -2))][::-1], radius=0.5, name="M1", alpha=0.8, grow=2.2)
render(sc, ART_DIR + OUT)
