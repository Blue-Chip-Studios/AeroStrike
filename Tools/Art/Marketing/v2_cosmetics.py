# Store icons for the cosmetic products (Hornet Paint, Phoenix Trail, Ace Pack). Square 512.
# Globals expected: ART_DIR, SAMPLES, PCT, KIND ("hornet" | "phoenix" | "pack"), OUT
import bpy, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())
exec(open(ART_DIR + r"\thumbkit2.py", encoding="utf-8").read())

PAINTS2["Hornet"] = dict(body='#ffc21a', accent='#141418', intake='#141418', panel=0.05)
PAINTS2["Nightshade"] = dict(body='#3a1460', accent='#7dff5a', intake='#1a0a2c', panel=0.05)

def fire_trail(sc, points, radius=0.9, name="Phoenix", strength=2.6):
    """Glowing red -> orange -> gold ribbon tube (emissive, fades towards the end)."""
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'
    sp = cu.splines.new('BEZIER'); sp.bezier_points.add(len(points) - 1)
    n = len(points)
    for i, p in enumerate(points):
        bp = sp.bezier_points[i]; bp.co = p; bp.handle_left_type = bp.handle_right_type = 'AUTO'
        bp.radius = 0.35 + (i / max(1, n - 1)) * 2.2
    cu.bevel_depth = radius; cu.bevel_resolution = 6; cu.resolution_u = 32; cu.use_fill_caps = True
    o = bpy.data.objects.new(name, cu); link(o, sc)
    m = bpy.data.materials.new(name + "M"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    # 0 at the exhaust -> 1 at the far end (distance along the trail, in world space)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dist = nt.nodes.new("ShaderNodeVectorMath"); dist.operation = 'DISTANCE'
    dist.inputs[1].default_value = tuple(points[0])
    nt.links.new(geo.outputs["Position"], dist.inputs[0])
    span = max((Vector(points[-1]) - Vector(points[0])).length, 1.0)
    norm = nt.nodes.new("ShaderNodeMapRange"); norm.inputs[1].default_value = 0.0; norm.inputs[2].default_value = span
    nt.links.new(dist.outputs["Value"], norm.inputs[0])
    sep = nt.nodes.new("ShaderNodeCombineXYZ"); nt.links.new(norm.outputs[0], sep.inputs[0])
    sep = type("S", (), {"outputs": [norm.outputs[0]]})()
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position = 0.0; e[0].color = (*hexc('#ffd86a'), 1)
    e[1].position = 1.0; e[1].color = (*hexc('#c0100a'), 1)
    e.new(0.22).color = (*hexc('#ff9a14'), 1)
    e.new(0.5).color = (*hexc('#ff3c10'), 1)
    nt.links.new(sep.outputs[0], ramp.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs[1].default_value = strength
    nt.links.new(ramp.outputs[0], em.inputs[0])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    fade = nt.nodes.new("ShaderNodeMapRange"); fade.inputs[1].default_value = 0.7; fade.inputs[2].default_value = 1.0
    nt.links.new(sep.outputs[0], fade.inputs[0])
    lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs[0].default_value = 0.35
    mx = nt.nodes.new("ShaderNodeMath"); mx.operation = 'MAXIMUM'
    nt.links.new(fade.outputs[0], mx.inputs[0]); nt.links.new(lw.outputs["Fresnel"], mx.inputs[1])
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(mx.outputs[0], mix.inputs[0]); nt.links.new(em.outputs[0], mix.inputs[1]); nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    cu.materials.append(m)
    o.visible_shadow = False
    return o

sc = scene2("ICON_" + KIND, 512, 512, samples=SAMPLES)
sc.render.resolution_percentage = PCT
# store icons: punchy colours (Standard + high contrast) on a dusk sky so paint and fire pop
sc.view_settings.view_transform = 'Standard'
try: sc.view_settings.look = 'Medium High Contrast'
except Exception: pass
sc.view_settings.exposure = -0.4
cam = camera(sc, (0, 0, 0), (0, 100, 0), lens=42)
sky2(sc, sun_elev=1.5, sun_rot=-35.0, strength=0.55, altitude=1500, aerosol=2.0, ozone=4.0, sun_strength=3.0, sun_color='#ffa060')
cloud_sea(sc, z_bottom=-420, thickness=260, coverage=0.55, density=0.03, seed=7.0)

def hero(jet, paint, loc, rot, name):
    j = jet2(jet, sc, paint, name)
    j.location = loc
    j.rotation_euler = Euler(tuple(math.radians(a) for a in rot), "XYZ")
    flame2(j, (0.72, 14.8, 0.3), length=8, radius=0.5); flame2(j, (-0.72, 14.8, 0.3), length=8, radius=0.5)
    bpy.context.view_layer.update()
    return j

def tail_trail(j, name, bend=Vector((0, 0, 0)), length=120):
    """Fire trail leaving the jet's exhaust and curving away behind it."""
    mw = j.matrix_world
    start = mw @ Vector((0, 17, 0.3))
    back = (mw.to_3x3() @ Vector((0, 1, 0))).normalized()
    pts = [start + back * (length * f) + bend * (f * f) for f in (0, 0.12, 0.35, 0.65, 1.0)]
    return fire_trail(sc, pts, radius=0.8, name=name)

if KIND == "hornet":
    hero("EXPORT_Jet_MakoSR9", "Hornet", (2.5, 40, 1.5), (-12, -36, -34), "Hornet")
    area(sc, (-20, 8, 16), (0, 33, 0), energy=26000, size=30, color='#dfe8ff', name="Fill")
    area(sc, (22, 55, 22), (0, 33, 0), energy=30000, size=20, color='#ffb070', name="Rim")
elif KIND == "phoenix":
    j = hero("EXPORT_Jet_MakoSR9", "Mako", (-2, 50, 7), (-8, -30, -32), "PhoenixJet")
    tail_trail(j, "Phoenix", bend=Vector((10, 0, -12)), length=48)
    area(sc, (-20, 8, 16), (-6, 40, 6), energy=18000, size=30, color='#dfe8ff', name="Fill")
    pl = bpy.data.lights.new("FireGlow", 'POINT'); pl.energy = 40000; pl.color = hexc('#ff7a2a'); pl.shadow_soft_size = 8
    lo = bpy.data.objects.new("FireGlow", pl); lo.location = j.matrix_world @ Vector((0, 30, 0)); link(lo, sc)
else:  # pack
    a = hero("EXPORT_Jet_MakoSR9", "Hornet", (-3, 46, 7), (-10, -30, -26), "PackHornet")
    b = hero("EXPORT_Jet_MakoSR9", "Nightshade", (7, 54, -7), (-8, -32, -30), "PackNight")
    tail_trail(a, "PackTrailA", bend=Vector((8, 0, -10)), length=40)
    tail_trail(b, "PackTrailB", bend=Vector((8, 0, -10)), length=40)
    area(sc, (-20, 8, 16), (0, 48, 0), energy=26000, size=30, color='#dfe8ff', name="Fill")
    area(sc, (22, 70, 22), (0, 48, 0), energy=30000, size=20, color='#ffb070', name="Rim")
render(sc, ART_DIR + OUT)
