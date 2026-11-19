# Game icon (square)
import bpy, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
sc = new_scene("ICON", 1024, 1024, samples=SAMPLES)
sc.render.resolution_percentage = PCT
cam = camera(sc, (0, 0, 0), (0, 100, 13), lens=40)
sunset_world(sc, strength=0.9)
_s = sun(sc, rot=(math.radians(70), 0, math.radians(160)), energy=3.5); _s.visible_glossy = False
backdrop(sc, cam, dist=4000, top='#2a3fd0', mid='#c24bd6', low='#ffa23c', sun_uv=(0.12, 0.36), sun_size=0.045, horizon=0.24, mid_at=0.58)
ocean(sc, z=-30, color='#0b2f6e', rough=0.25, spec=0.12)

jet = copy_model("EXPORT_Jet_MakoSR9", sc, "Mako", "IconJet")
jet.location = (6.5, 52, 12.5)
jet.rotation_euler = Euler((math.radians(-10), math.radians(-34), math.radians(-58)), 'XYZ')
flame(jet, (0.72, 14.8, 0.3), length=9, radius=0.5); flame(jet, (-0.72, 14.8, 0.3), length=9, radius=0.5)
area(sc, (-15, 25, 25), (6.5, 52, 12.5), energy=30000, size=18, color='#fff1e6', name="JetKey")
area(sc, (34, 66, 34), (6.5, 52, 12.5), energy=25000, size=20, color='#ff8a3a', name="JetRim")
smoke_trail(sc, [(20, 68, 18), (36, 88, 23), (62, 118, 29)], radius=1.0, name="JetTrail", alpha=0.6, taper_end=2.5)
fireball(sc, (-44, 170, 44), size=11, name="IconBoom", seed=4)

p = avatar(sc, "IconPilot", (-0.6, 8.6, -4.25), rot_z=math.radians(-10), shirt='#ff4800', pants='#2b2f38', skin='#e9b27c',
           face="face_grin.png", pose="cheer", helmet=True, helmet_color='#f2f2f2', visor='#ff9a2a', accent='#ffb020', scale=1.0)
area(sc, (2, 2, 3), (-0.6, 8.6, 0), energy=2500, size=8, color='#fff4ea', name="PilotKey")
area(sc, (-7, 14, 2), (-0.6, 8.6, 0), energy=1800, size=8, color='#7aa8ff', name="PilotRim")
render(sc, ART_DIR + OUT)
