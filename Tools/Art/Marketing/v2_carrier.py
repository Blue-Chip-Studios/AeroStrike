# Thumbnail v2-2: LAUNCH - jet climbing out from the carrier toward the sunset (no avatar)
import bpy, math, random
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
exec(open(ART_DIR + r"\thumbkit2.py", encoding="utf-8").read())
sc = scene2("V2_Carrier", 1920, 1080, samples=SAMPLES)
sc.render.resolution_percentage = PCT
# carrier sails toward -Y (bow at -Y); camera chases the jet from behind-above, looking out over the bow
JET = Vector((10, 8, 84))
cam = camera(sc, (38, 75, 100), (-6, -260, 34), lens=28, roll=math.radians(-5))
sky2(sc, sun_elev=SUN_ELEV, sun_rot=SUN_ROT, strength=1.0, altitude=200, aerosol=1.5, ozone=3.0, sun_strength=5.0)
ocean_waves(sc, z=0.0, size=500, repeat=6, wave_scale=1.4)
ocean2(sc, z=-1.0, size=200000, color='#06223a')
# cloud_sea(sc, z_bottom=1400, thickness=300, coverage=0.5, density=0.01, seed=4.0, name="HighClouds")

car = jet2("EXPORT_Carrier", sc, "Navy", "Carrier")
car.location = (0, 0, 0)
# white wake behind the carrier
wk = mat("Wake", hexc('#e8eef2'), rough=0.6)
bpy.ops.mesh.primitive_plane_add(size=1)
w = bpy.context.active_object
for cc in list(w.users_collection): cc.objects.unlink(w)
sc.collection.objects.link(w)
w.scale = (40, 700, 1); w.location = (-10, 480, 0.6); w.data.materials.append(wk)
wm = wk.node_tree; wb = wm.nodes["Principled BSDF"]
nz = wm.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 6; nz.inputs["Detail"].default_value = 10
tcw = wm.nodes.new("ShaderNodeTexCoord"); wm.links.new(tcw.outputs["UV"], nz.inputs[0])
gx = wm.nodes.new("ShaderNodeSeparateXYZ"); wm.links.new(tcw.outputs["UV"], gx.inputs[0])
edge = wm.nodes.new("ShaderNodeMath"); edge.operation = 'PINGPONG'; edge.inputs[1].default_value = 0.5
wm.links.new(gx.outputs[0], edge.inputs[0])
em = wm.nodes.new("ShaderNodeMath"); em.operation = 'MULTIPLY'; wm.links.new(edge.outputs[0], em.inputs[0]); wm.links.new(nz.outputs[0], em.inputs[1])
th = wm.nodes.new("ShaderNodeMapRange"); th.inputs[1].default_value = 0.12; th.inputs[2].default_value = 0.3
wm.links.new(em.outputs[0], th.inputs[0]); wm.links.new(th.outputs[0], wb.inputs["Alpha"])

jet = jet2("EXPORT_Jet_MakoSR9", sc, "Mako", "LaunchJet")
jet.location = JET
jet.rotation_euler = Euler((math.radians(16), math.radians(-24), math.radians(-4)), 'XYZ')
flame2(jet, (0.72, 14.8, 0.3), length=10, radius=0.6, light=9000); flame2(jet, (-0.72, 14.8, 0.3), length=10, radius=0.6, light=9000)
area(sc, (40, -170, 110), JET, energy=30000, size=30, color='#c8d8ff', name="JetFill")
# contrail(sc, [JET + Vector((0, 22, -4)), JET + Vector((-2, 50, -26)), Vector((-7, -40, 34)), Vector((-8, -10, 30))], radius=0.7, name="Climb", alpha=0.45, grow=3.0)
# wingman already climbing ahead
wing = jet2("EXPORT_ViperIX", sc, "Viper", "Wing")
wing.location = (-40, -200, 120)
dd = jet2("EXPORT_NPC_Destroyer", sc, "Navy", "Escort"); dd.location = (-190, -640, 0)
wing.rotation_euler = Euler((math.radians(18), math.radians(30), math.radians(8)), 'XYZ')
flame2(wing, (0, 14.6, 0.35), length=8, radius=0.6)
# next jet on the catapult, burners lit, steam off the track
DECK = 26.2
cj = jet2("EXPORT_ViperIX", sc, "Viper", "CatJet")
CJ = Vector((-8.5, -96, DECK + 2.6)); cj.location = CJ
flame2(cj, (0, 14.6, 0.35), length=7, radius=0.65, light=8000)
area(sc, (20, -60, DECK + 25), CJ, energy=15000, size=20, color='#c8d8ff', name="CatFill")
random.seed(7)
for i in range(6):
    p = CJ + Vector((random.uniform(-2.0, 2.0), 18 + i * 5.0, -1.6))
    cloud_puff(sc, p, radius=2.4 + i * 0.5, density=0.25, seed=i + 1, name=f"Steam{i}", squash=0.5)
render(sc, ART_DIR + OUT)
