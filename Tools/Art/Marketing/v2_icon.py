# Game icon v2 (square): hero jet banking over the sunset cloud sea, kill behind it (no avatar, no text)
import bpy, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
exec(open(ART_DIR + r"\thumbkit2.py", encoding="utf-8").read())
sc = scene2("V2_Icon", 1024, 1024, samples=SAMPLES)
sc.render.resolution_percentage = PCT
cam = camera(sc, (0, 0, 0), (0, 100, -4), lens=40, roll=math.radians(-8))
sky2(sc, sun_elev=SUN_ELEV, sun_rot=SUN_ROT, strength=1.0, altitude=1500, aerosol=2.0, ozone=3.0, sun_strength=5.0)
cloud_sea(sc, z_bottom=-460, thickness=300, coverage=0.6, density=0.03, seed=31.0)
ocean2(sc, z=-1600)
H = Vector((-1.5, 46, 1.5))
hero = jet2("EXPORT_Jet_MakoSR9", sc, "Mako", "Hero")
hero.location = H
hero.rotation_euler = Euler((math.radians(-14), math.radians(-40), math.radians(-38)), "XYZ")
flame2(hero, (0.72, 14.8, 0.3), length=10, radius=0.6); flame2(hero, (-0.72, 14.8, 0.3), length=10, radius=0.6)
area(sc, (-25, 10, 20), H, energy=14000, size=30, color='#b8ccff', name="Fill")
area(sc, (25, 70, 25), H, energy=30000, size=20, color='#ffb070', name="Rim")
fireball2(sc, (-60, 190, 34), size=14, name="Boom", seed=4)
contrail(sc, [Vector((-58, 186, 32)), Vector((-30, 130, 20)), Vector((-12, 80, 8)), Vector((-4, 62, 4))], radius=0.5, name="Kill", alpha=0.7, grow=2.5)
render(sc, ART_DIR + OUT)
