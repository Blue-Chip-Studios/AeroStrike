# Thumbnail 2: CARRIER LAUNCH
import bpy, math, random
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
sc = new_scene("THUMB_Carrier", 1920, 1080, samples=SAMPLES)
sc.render.resolution_percentage = PCT
DECK = 26.2
cam = camera(sc, (-1.0, -124, DECK + 3.4), (-6.5, -78, DECK + 6.2), lens=30)
sunset_world(sc, strength=0.9)
sun(sc, rot=(math.radians(78), 0, math.radians(200)), energy=3.5, color='#ffc890')
backdrop(sc, cam, dist=4000, top='#2a3fd0', mid='#c24bd6', low='#ffa23c', sun_uv=(0.22, 0.40), sun_size=0.05, horizon=0.36, mid_at=0.64)
ocean(sc, z=0.0, color='#0a2f5a')

car = copy_model("EXPORT_Carrier", sc, "Gunmetal", "Carrier")
# drop the island mast for this shot (from the bow it reads as a big cross)
import bmesh as _bm
for c in car.children:
    if c.type == 'MESH':
        b = _bm.new(); b.from_mesh(c.data)
        kill = [v for v in b.verts if v.co.z > DECK + 30]
        if kill:
            _bm.ops.delete(b, geom=kill, context='VERTS'); b.to_mesh(c.data)
        b.free()

jet = copy_model("EXPORT_ViperIX", sc, "Viper", "LaunchJet")
jet.location = (-8.5, -90, DECK + 3.0)
flame(jet, (0, 14.6, 0.35), length=7, radius=0.62, strength=70)
# catapult steam along the track
random.seed(7)
steam = mat("Steam", hexc('#ffffff'), rough=1.0, sss=0.4, alpha=0.55)
for i in range(0):
    r = random.uniform(0.7, 1.5)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r)
    s = bpy.context.active_object
    for cc in list(s.users_collection): cc.objects.unlink(s)
    sc.collection.objects.link(s)
    s.location = (-9 + random.choice((-1, 1)) * random.uniform(2.5, 5.0), -94 - i * 1.4, DECK + random.uniform(0.0, 0.8))
    s.data.materials.append(steam)
    dm = s.modifiers.new("D", 'DISPLACE'); tx = bpy.data.textures.new(f"StT{i}", 'CLOUDS'); tx.noise_scale = r * 0.5; dm.texture = tx; dm.strength = r * 0.5
    s.scale = (1.4, 1.0, 0.7)
    for p in s.data.polygons: p.use_smooth = True
    s.visible_shadow = False
# deck crew
a1 = avatar(sc, "Pilot", (3.4, -104, DECK), rot_z=math.radians(-14), shirt='#ff4800', pants='#2b2f38', skin='#e9b27c',
            face="face_grin.png", pose="cheer", helmet=True, helmet_color='#f2f2f2', visor='#ff9a2a', accent='#ffb020')
a2 = avatar(sc, "Crew", (8.6, -98, DECK), rot_z=math.radians(-24), shirt='#ffd21a', pants='#2b2f38', skin='#8d5a3b',
            face="face_happy.png", pose="wave", helmet=True, helmet_color='#ffd21a', visor='#202020', accent='#ffffff')
a3 = avatar(sc, "Wing", (-1.5, -97, DECK), rot_z=math.radians(-6), shirt='#2e7bff', pants='#1d2433', skin='#f1c9a0',
            face="face_smile.png", pose="thumbs", helmet=True, helmet_color='#ffffff', visor='#2ad1ff', accent='#ffb020')
area(sc, (2, -118, DECK + 9), (4, -100, DECK + 3), energy=5000, size=12, color='#fff2e6', name="CrewKey")
area(sc, (-18, -102, DECK + 7), (-8.5, -90, DECK + 3), energy=14000, size=20, color='#ffd2a8', name="JetKey")
lg, w = logo(sc, (-5.6, -106, DECK + 9.0), (math.radians(86), 0, 0), scale=0.5)
render(sc, ART_DIR + OUT)
