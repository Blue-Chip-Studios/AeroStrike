# Thumbnail v2-1: DOGFIGHT above a golden cloud sea (no avatar, physical sky)
import bpy, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
exec(open(ART_DIR + r"\thumbkit2.py", encoding="utf-8").read())
sc = scene2("V2_Dogfight", 1920, 1080, samples=SAMPLES)
sc.render.resolution_percentage = PCT
cam = camera(sc, (0, 0, 0), (0, 100, -2), lens=35, roll=math.radians(-7))
sunobj, to_sun = sky2(sc, sun_elev=SUN_ELEV, sun_rot=SUN_ROT, strength=1.0, altitude=1500, aerosol=1.5, ozone=3.0, sun_strength=5.0)
cloud_sea(sc, z_bottom=-560, thickness=300, coverage=0.6, density=0.03, seed=11.0)
# towering cumulus on the horizon for depth
# cloud_puff(sc, (2600, 7000, -200), radius=900, density=0.02, seed=2, name="Tower1", squash=0.8)
# cloud_puff(sc, (-3800, 9000, -300), radius=1200, density=0.02, seed=5, name="Tower2", squash=0.7)
ocean2(sc, z=-1600)

# hero: banking hard across the frame, afterburners lit
hero = jet2("EXPORT_Jet_MakoSR9", sc, "Mako", "Hero")
hero.location = (8.5, 46, -3.0)
hero.rotation_euler = Euler((math.radians(-10), math.radians(-48), math.radians(-28)), "XYZ")
flame2(hero, (0.72, 14.8, 0.3), length=9, radius=0.55); flame2(hero, (-0.72, 14.8, 0.3), length=9, radius=0.55)
area(sc, (-30, 5, 15), (8.5, 46, -3), energy=12000, size=30, color='#b8ccff', name="Fill")
area(sc, (30, 70, 30), (8.5, 46, -3), energy=30000, size=20, color='#ffb070', name="Rim")
# wingtip vapour
# contrail(sc, [(20.5, 54.5, 9.5), (24, 62, 11), (30, 74, 12.5), (40, 92, 14)], radius=0.25, name="Vap1", alpha=0.6, grow=2.0)

# missile streaking from the hero towards the enemy
EN = Vector((-46, 230, 30))
M = Vector((-24, 150, 18))
msl = copy_model("EXPORT_FX_Missile", sc, "Gunmetal", "Msl")
msl.location = M; msl.scale = (2.2, 2.2, 2.2)
msl.rotation_euler = (EN - M).to_track_quat('-Y', 'Z').to_euler()
flame2(msl, (0, 1.4, 0), length=3.5, radius=0.28, strength=60, light=3000)
contrail(sc, [(2, 52, -2), (-4, 80, 4), (-12, 110, 10), (-20, 138, 16), (-23.5, 148, 17.8)][::-1], radius=0.45, name="MslTrail", alpha=0.9, grow=2.2)

# enemy breaking hard and popping flares
en = jet2("EXPORT_ViperIX", sc, "Night", "Enemy")
en.location = EN
en.rotation_euler = Euler((math.radians(-10), math.radians(60), math.radians(140)), 'XYZ')
flame2(en, (0, 14.6, 0.35), length=7, radius=0.6)
fl = emission_mat("Flare", hexc('#fff0c0'), 80)
for i, off in enumerate([(-6, 14, -4), (-10, 20, -9), (-3, 18, -12), (-14, 26, -16), (-8, 28, -20)]):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.7 - i * 0.06)
    s = bpy.context.active_object
    for cc in list(s.users_collection): cc.objects.unlink(s)
    sc.collection.objects.link(s)
    s.location = EN + Vector(off); s.data.materials.append(fl); s.visible_shadow = False
    contrail(sc, [EN + Vector((0, 8, 0)), EN + Vector(off)], radius=0.3, name=f"FlTr{i}", alpha=0.45, grow=1.5)

# a kill in the distance
fireball2(sc, (120, 520, 40), size=16, name="Boom1", seed=3)
render(sc, ART_DIR + OUT)
