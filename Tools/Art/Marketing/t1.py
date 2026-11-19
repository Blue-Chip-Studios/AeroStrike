# Thumbnail 1: DOGFIGHT
import bpy, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
sc = new_scene("THUMB_Dogfight", 1920, 1080, samples=SAMPLES)
sc.render.resolution_percentage = PCT
cam = camera(sc, (0, 0, 0), (0, 100, 9), lens=38)
sunset_world(sc, strength=0.8)
sun(sc, rot=(math.radians(72), 0, math.radians(150)), energy=4.0)
area(sc, (-20, 10, 25), (9, 40, -4), energy=30000, size=20, color='#fff1e6', name="Key")
area(sc, (40, 80, 10), (9, 40, -4), energy=50000, size=25, color='#ff8a3a', name="Rim")
area(sc, (0, 10, -25), (9, 40, -4), energy=12000, size=30, color='#6a7cff', name="Fill")
backdrop(sc, cam, dist=4000, top='#2a3fd0', mid='#c24bd6', low='#ffa23c', sun_uv=(0.80, 0.40), sun_size=0.05, horizon=0.30, mid_at=0.6)
ocean(sc, z=-180, color='#06284e')

hero = copy_model("EXPORT_Jet_MakoSR9", sc, "Mako", "Hero")
hero.location = (8.0, 52, -1.0)
hero.rotation_euler = Euler((math.radians(-14), math.radians(-38), math.radians(-32)), "XYZ")
flame(hero, (0.72, 14.8, 0.3), length=9, radius=0.5); flame(hero, (-0.72, 14.8, 0.3), length=9, radius=0.5)

en = copy_model("EXPORT_ViperIX", sc, "Night", "Enemy")
en.location = (-34, 175, 34)
en.rotation_euler = Euler((math.radians(-4), math.radians(-40), math.radians(110)), 'XYZ')
flame(en, (0, 14.6, 0.35), length=8, radius=0.6)

msl = copy_model("EXPORT_FX_Missile", sc, "Gunmetal", "Msl")
msl.location = (-22, 145, 27); msl.scale = (2.6, 2.6, 2.6)
msl.rotation_euler = (Vector((-34, 175, 34)) - Vector((-22, 145, 27))).to_track_quat('-Y', 'Z').to_euler()
flame(msl, (0, 1.2, 0), length=3, radius=0.25, strength=80)
smoke_trail(sc, [(3, 44, -4), (-3, 75, 4), (-12, 110, 14), (-20, 140, 25)], radius=0.9, name="MslTrail", alpha=0.95, taper_end=2.2)

fireball(sc, (95, 420, 70), size=30, name="Boom1", seed=3)

pilot = avatar(sc, "Pilot", (-5.0, 16, -5.5), rot_z=math.radians(-26), scale=1.0, shirt='#ff4800', pants='#2b2f38', skin='#e9b27c',
               face="face_grin.png", pose="cheer", helmet=True, helmet_color='#f2f2f2', visor='#ff9a2a', accent='#ffb020')
area(sc, (0, 6, 3), (-5, 16, -2), energy=5000, size=8, color='#fff4ea', name="PilotKey")
lg, w = logo(sc, (-6.0, 30, 8.4), (math.radians(84), 0, 0), scale=0.62)
render(sc, ART_DIR + OUT)
