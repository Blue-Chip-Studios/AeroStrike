# AeroStrike marketing-art toolkit for Blender 5.x (exec'd into the MCP session).
# Builds isolated scenes from the game's EXPORT_* models (copies, so the export
# collections/materials are never touched) with a glossy, saturated "thumbnail" look.
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix, Euler

ART = r"C:\Users\santa\AppData\Local\Temp\claude\8c16af714d52f437\b60c6abe-85f0-4d2e-a5c2-4467fb741722\scratchpad\art"
FONT_BLACK = r"C:\Windows\Fonts\ariblk.ttf"
FONT_IMPACT = r"C:\Windows\Fonts\impact.ttf"

# ---------------------------------------------------------------- scene / render
def new_scene(name, w=1920, h=1080, samples=160, transparent=False):
    # never delete the scene that's on screen (that crashes Blender): park the window first
    sc = bpy.data.scenes.new(name + "_new")
    bpy.context.window.scene = sc
    old = bpy.data.scenes.get(name)
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.scenes.remove(old)
    sc.name = name
    bpy.ops.outliner.orphans_purge(do_recursive=True) if False else None
    r = sc.render
    r.engine = 'CYCLES'
    r.resolution_x, r.resolution_y, r.resolution_percentage = w, h, 100
    r.film_transparent = transparent
    r.image_settings.file_format = 'PNG'
    r.image_settings.color_mode = 'RGBA' if transparent else 'RGB'
    cy = sc.cycles
    cy.device = 'GPU'
    cy.samples = samples
    cy.use_denoising = True
    cy.max_bounces = 8
    try:
        p = bpy.context.preferences.addons['cycles'].preferences
        p.compute_device_type = 'HIP'
        p.refresh_devices()
        for d in p.devices:
            d.use = (d.type == 'HIP')
    except Exception:
        pass
    vs = sc.view_settings
    try:
        vs.view_transform = 'Standard'
        vs.look = 'Medium High Contrast'
    except Exception:
        try: vs.view_transform = 'Filmic'; vs.look = 'High Contrast'
        except Exception: pass
    vs.exposure = -0.2
    world = bpy.data.worlds.new(name + "_World")
    sc.world = world
    return sc

def link(o, sc=None):
    (sc or bpy.context.scene).collection.objects.link(o)
    return o

# ---------------------------------------------------------------- materials
def mat(name, color=(1, 1, 1), metal=0.0, rough=0.4, coat=0.0, emit=None, emit_str=0.0, alpha=1.0, transmission=0.0, ior=1.45, sss=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    def s(k, v):
        if k in b.inputs: b.inputs[k].default_value = v
    s("Base Color", (*color, 1)); s("Metallic", metal); s("Roughness", rough)
    s("Coat Weight", coat); s("Coat Roughness", 0.05)
    s("Transmission Weight", transmission); s("IOR", ior)
    s("Subsurface Weight", sss)
    if emit is not None:
        s("Emission Color", (*emit, 1)); s("Emission Strength", emit_str)
    if alpha < 1.0:
        s("Alpha", alpha)
    return m

def emission_mat(name, color, strength):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission"); e.inputs[0].default_value = (*color, 1); e.inputs[1].default_value = strength
    o = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(e.outputs[0], o.inputs[0])
    return m

def hexc(h):
    h = h.lstrip('#'); c = tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)  # sRGB -> linear

# ---------------------------------------------------------------- sky / world
def sunset_world(sc, top='#3a1f78', mid='#ff5fa2', low='#ffb04a', strength=1.0, sun_dir=(0.0, 1.0, 0.08)):
    w = sc.world; w.use_nodes = True
    nt = w.node_tree; nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    # use the view direction (Generated == direction for world) Z for the gradient
    mr = nt.nodes.new("ShaderNodeMapRange"); mr.inputs[1].default_value = -0.05; mr.inputs[2].default_value = 0.6
    nt.links.new(sep.outputs[2], mr.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0; ramp.color_ramp.elements[0].color = (*hexc(low), 1)
    ramp.color_ramp.elements[1].position = 1.0; ramp.color_ramp.elements[1].color = (*hexc(top), 1)
    e = ramp.color_ramp.elements.new(0.32); e.color = (*hexc(mid), 1)
    nt.links.new(mr.outputs[0], ramp.inputs[0])
    bg = nt.nodes.new("ShaderNodeBackground"); bg.inputs[1].default_value = strength
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    out = nt.nodes.new("ShaderNodeOutputWorld"); nt.links.new(bg.outputs[0], out.inputs[0])

def sun(sc, rot=(math.radians(80), 0, math.radians(200)), energy=4.0, color='#ffd6a0', angle=2.0):
    d = bpy.data.lights.new("Sun", 'SUN'); d.energy = energy; d.color = hexc(color); d.angle = math.radians(angle)
    o = bpy.data.objects.new("Sun", d); o.rotation_euler = rot; link(o, sc); return o

def area(sc, loc, target, energy=2000, size=10, color='#ffffff', name="Area"):
    d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.size = size; d.color = hexc(color)
    o = bpy.data.objects.new(name, d); o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    link(o, sc); return o

def backdrop(sc, cam, dist=1500, top='#2a1a6e', mid='#ff4f9a', low='#ffb347', sun_uv=(0.72, 0.30), sun_size=0.08, clouds=True, horizon=0.3, mid_at=0.55):
    """Huge emissive card behind everything: painted sunset gradient + soft noise clouds + sun disc."""
    bpy.ops.mesh.primitive_plane_add(size=2)
    o = bpy.context.active_object
    for cc in list(o.users_collection): cc.objects.unlink(o)
    sc.collection.objects.link(o)
    o.name = "Backdrop"; me = o.data
    camf = cam.matrix_world
    fwd = -(camf.to_3x3() @ Vector((0, 0, 1)))
    o.location = camf.translation + fwd * dist
    o.rotation_euler = cam.matrix_world.to_euler()
    halfw = dist * 18.0 / cam.data.lens * 1.02
    aspect = sc.render.resolution_y / sc.render.resolution_x
    o.scale = (halfw, halfw * aspect, 1)  # fills the frame exactly: UV v = 0 bottom .. 1 top
    m = bpy.data.materials.new("BackdropMat"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["UV"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = horizon; ramp.color_ramp.elements[0].color = (*hexc(low), 1)
    ramp.color_ramp.elements[1].position = 1.0; ramp.color_ramp.elements[1].color = (*hexc(top), 1)
    ramp.color_ramp.elements.new(mid_at).color = (*hexc(mid), 1)
    ramp.color_ramp.elements.new(max(0.0, horizon - 0.06)).color = (*hexc('#fff0b0'), 1)
    nt.links.new(sep.outputs[1], ramp.inputs[0])
    col = ramp.outputs[0]
    if clouds:
        noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 3.2; noise.inputs["Detail"].default_value = 8; noise.inputs["Roughness"].default_value = 0.55
        mapn = nt.nodes.new("ShaderNodeMapping"); mapn.inputs["Scale"].default_value = (1.0, 2.6, 1.0)
        nt.links.new(tc.outputs["UV"], mapn.inputs[0]); nt.links.new(mapn.outputs[0], noise.inputs[0])
        cr = nt.nodes.new("ShaderNodeValToRGB")
        cr.color_ramp.elements[0].position = 0.52; cr.color_ramp.elements[0].color = (0, 0, 0, 1)
        cr.color_ramp.elements[1].position = 0.72; cr.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(noise.outputs[0], cr.inputs[0])
        # clouds only in a band (fade near top and bottom)
        band = nt.nodes.new("ShaderNodeFloatCurve")
        cv = band.mapping.curves[0]; cv.points[0].location = (0, 0); cv.points[1].location = (1, 0)
        cv.points.new(0.25, 0.0); cv.points.new(0.45, 1.0); cv.points.new(0.8, 0.6)
        band.mapping.update()
        nt.links.new(sep.outputs[1], band.inputs[1])
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'
        nt.links.new(cr.outputs[0], mul.inputs[0]); nt.links.new(band.outputs[0], mul.inputs[1])
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'
        nt.links.new(mul.outputs[0], mix.inputs[0]); nt.links.new(col, mix.inputs[6]); mix.inputs[7].default_value = (*hexc('#fff0f6'), 1)
        col = mix.outputs[2]
    # sun disc
    d = nt.nodes.new("ShaderNodeVectorMath"); d.operation = 'DISTANCE'
    d.inputs[1].default_value = (sun_uv[0], sun_uv[1], 0)
    nt.links.new(tc.outputs["UV"], d.inputs[0])
    sr = nt.nodes.new("ShaderNodeMapRange"); sr.inputs[1].default_value = sun_size; sr.inputs[2].default_value = sun_size * 0.6
    sr.inputs[3].default_value = 0.0; sr.inputs[4].default_value = 1.0
    nt.links.new(d.outputs["Value"], sr.inputs[0])
    glow = nt.nodes.new("ShaderNodeMapRange"); glow.inputs[1].default_value = sun_size * 5; glow.inputs[2].default_value = 0.0
    nt.links.new(d.outputs["Value"], glow.inputs[0])
    gmul = nt.nodes.new("ShaderNodeMath"); gmul.operation = 'POWER'; gmul.inputs[1].default_value = 2.0
    nt.links.new(glow.outputs[0], gmul.inputs[0])
    tot = nt.nodes.new("ShaderNodeMath"); tot.operation = 'ADD'
    nt.links.new(sr.outputs[0], tot.inputs[0])
    gsc = nt.nodes.new("ShaderNodeMath"); gsc.operation = 'MULTIPLY'; gsc.inputs[1].default_value = 0.6
    nt.links.new(gmul.outputs[0], gsc.inputs[0]); nt.links.new(gsc.outputs[0], tot.inputs[1])
    sm = nt.nodes.new("ShaderNodeMix"); sm.data_type = 'RGBA'; sm.clamp_factor = True
    nt.links.new(tot.outputs[0], sm.inputs[0]); nt.links.new(col, sm.inputs[6]); sm.inputs[7].default_value = (*hexc('#fff3c4'), 1)
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs[1].default_value = 1.0
    nt.links.new(sm.outputs[2], em.inputs[0])
    out = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(em.outputs[0], out.inputs[0])
    me.materials.append(m)
    o.visible_shadow = False
    return o

def ocean(sc, z=0.0, size=80000, color='#0b3a66', rough=0.06, spec=0.5):
    me = bpy.data.meshes.new("Ocean")
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("Ocean", me); o.location.z = z; link(o, sc)
    m = mat("OceanMat", hexc(color), metal=0.0, rough=rough, coat=0.0)
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    if "Specular IOR Level" in b.inputs: b.inputs["Specular IOR Level"].default_value = spec
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 0.04; noise.inputs["Detail"].default_value = 6
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25
    nt.links.new(noise.outputs[0], bump.inputs["Height"]); nt.links.new(bump.outputs[0], b.inputs["Normal"])
    me.materials.append(m)
    return o

# ---------------------------------------------------------------- game models
PAINTS = {
    "Gunmetal": dict(body='#5d6b7c', accent='#ffb020', intake='#a8b2bd'),
    "Mako": dict(body='#46566b', accent='#ffb020', intake='#b4bcc6'),
    "Shark": dict(body='#8a98a8', accent='#ff3a3a', intake='#e6eaee'),
    "Night": dict(body='#1e2128', accent='#ff3c3c', intake='#30343c'),
    "Talon": dict(body='#2a2b31', accent='#d7a642', intake='#3a3c44'),
    "Viper": dict(body='#4d5c6e', accent='#ffb020', intake='#a9b3bd'),
    "Rhino": dict(body='#5e6654', accent='#ffb020', intake='#8a907e'),
    "Wraith": dict(body='#22252d', accent='#ffc450', intake='#2b2e36'),
}

def _part_of(o):
    n = o.name.split('.')[0]
    return n

def copy_model(export_coll, sc, paint="Gunmetal", name="Jet", glow_strength=40.0):
    """Copy an EXPORT_* collection's meshes into sc under an empty, with thumbnail materials."""
    src = bpy.data.collections[export_coll]
    p = PAINTS.get(paint, PAINTS["Gunmetal"])
    mats = {
        "Body": mat(name + "_Body", hexc(p["body"]), metal=0.25, rough=0.3, coat=0.5),
        "Accents": mat(name + "_Acc", hexc(p['accent']), metal=0.2, rough=0.25, coat=1.0),
        "Intakes": mat(name + "_Int", hexc(p['intake']), metal=0.4, rough=0.3, coat=0.6),
        "Trim": mat(name + "_Trim", hexc('#1b1e23'), metal=0.8, rough=0.35),
        "Canopy": mat(name + "_Can", hexc('#3a2a10'), metal=0.9, rough=0.04, coat=1.0),
        "Glow": emission_mat(name + "_Glow", hexc('#ff8a2a'), glow_strength),
        "Missiles": mat(name + "_Msl", hexc('#e6e8ea'), metal=0.2, rough=0.3),
        "Markings": mat(name + "_Mark", hexc(p['accent']), metal=0.2, rough=0.3, coat=0.8),
        "Hull": mat(name + "_Hull", hexc('#5a6470'), metal=0.3, rough=0.45),
        "Deck": mat(name + "_Deck", hexc('#3b4047'), metal=0.1, rough=0.7),
        "Boot": mat(name + "_Boot", hexc('#7a2a2a'), metal=0.1, rough=0.6),
        "Island": mat(name + "_Isl", hexc('#6a737e'), metal=0.2, rough=0.5),
        "Amber": mat(name + "_Amb", hexc('#ffb020'), metal=0.1, rough=0.4, emit=hexc('#ffb020'), emit_str=1.5),
        "Band": mat(name + "_Band", hexc('#ffb020'), metal=0.2, rough=0.3),
        "Seeker": mat(name + "_Seek", hexc('#1b1e23'), metal=0.6, rough=0.2),
    }
    root = bpy.data.objects.new(name, None); link(root, sc)
    for o in src.objects:
        if o.type != 'MESH':
            continue
        c = o.copy(); c.data = o.data.copy(); c.name = name + "_" + _part_of(o)
        link(c, sc); c.parent = root
        c.data.materials.clear()
        c.data.materials.append(mats.get(_part_of(o), mats["Body"]))
        for poly in c.data.polygons: poly.use_smooth = _part_of(o) in ("Canopy",)
    return root

def flame(parent, local_pos, length=7.0, radius=0.55, strength=60):
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=radius, radius2=0.02, depth=length)
    c = bpy.context.active_object
    for cc in list(c.users_collection): cc.objects.unlink(c)
    bpy.context.scene.collection.objects.link(c)
    c.name = parent.name + "_Flame"
    c.parent = parent
    c.rotation_euler = (math.radians(-90), 0, 0)  # cone axis -> +Y (tail)
    c.location = Vector(local_pos) + Vector((0, length / 2, 0))
    m = bpy.data.materials.new(parent.name + "_FlameMat"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs[0].default_value = (*hexc('#ff9a3c'), 1); em.inputs[1].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs[0].default_value = 0.35
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lw.outputs["Facing"], mix.inputs[0]); nt.links.new(em.outputs[0], mix.inputs[1]); nt.links.new(tr.outputs[0], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(mix.outputs[0], out.inputs[0])
    c.data.materials.append(m)
    c.visible_shadow = False
    pl = bpy.data.lights.new(parent.name + "_AB", 'POINT'); pl.energy = 4000; pl.color = hexc('#ff8a3a'); pl.shadow_soft_size = 1.0
    lo = bpy.data.objects.new(parent.name + "_AB", pl); lo.parent = parent; lo.location = Vector(local_pos) + Vector((0, 3, 0)); link(lo)
    return c

def smoke_trail(sc, points, radius=1.2, name="Trail", color='#ffffff', alpha=0.85, taper_end=3.0):
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'
    sp = cu.splines.new('BEZIER'); sp.bezier_points.add(len(points) - 1)
    for i, p in enumerate(points):
        bp = sp.bezier_points[i]; bp.co = p; bp.handle_left_type = bp.handle_right_type = 'AUTO'
        bp.radius = 0.25 + (i / max(1, len(points) - 1)) * taper_end
    cu.bevel_depth = radius; cu.bevel_resolution = 6; cu.resolution_u = 24
    o = bpy.data.objects.new(name, cu); link(o, sc)
    m = bpy.data.materials.new(name + "Mat"); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*hexc(color), 1); b.inputs["Roughness"].default_value = 1.0
    if "Subsurface Weight" in b.inputs: b.inputs["Subsurface Weight"].default_value = 0.3
    b.inputs["Alpha"].default_value = alpha
    lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs[0].default_value = 0.5
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], inv.inputs[1])
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = alpha * 1.4
    nt.links.new(inv.outputs[0], mul.inputs[0]); nt.links.new(mul.outputs[0], b.inputs["Alpha"])
    cu.materials.append(m)
    o.visible_shadow = False
    return o

def fireball(sc, loc, size=12.0, name="Boom", seed=1):
    random.seed(seed)
    root = bpy.data.objects.new(name, None); root.location = loc; link(root, sc)
    fire = bpy.data.materials.new(name + "Fire"); fire.use_nodes = True
    nt = fire.node_tree; nt.nodes.clear()
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 3.5; noise.inputs["Detail"].default_value = 8
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.38; els[0].color = (*hexc('#8a1200'), 1); els[1].position = 0.7; els[1].color = (*hexc('#ffe27a'), 1)
    els.new(0.5).color = (*hexc('#ff7a12'), 1)
    nt.links.new(noise.outputs[0], ramp.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs[1].default_value = 9
    nt.links.new(ramp.outputs[0], em.inputs[0])
    out = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(em.outputs[0], out.inputs[0])
    smoke = mat(name + "Smoke", hexc('#2b2626'), rough=1.0)
    for i in range(9):
        r = size * random.uniform(0.35, 0.6)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=r)
        s = bpy.context.active_object
        for cc in list(s.users_collection): cc.objects.unlink(s)
        sc.collection.objects.link(s)
        s.name = f"{name}_F{i}"; s.parent = root
        s.location = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.6, 1))) * size * 0.45
        d = s.modifiers.new("Disp", 'DISPLACE'); tx = bpy.data.textures.new(f"{name}T{i}", 'CLOUDS'); tx.noise_scale = r * 0.6; d.texture = tx; d.strength = r * 0.35
        s.data.materials.append(fire if i < 6 else smoke)
        for p in s.data.polygons: p.use_smooth = True
        s.visible_shadow = False
    pl = bpy.data.lights.new(name + "L", 'POINT'); pl.energy = 400000; pl.color = hexc('#ff8a30'); pl.shadow_soft_size = size * 0.5
    lo = bpy.data.objects.new(name + "L", pl); lo.parent = root; link(lo, sc)
    return root

# ---------------------------------------------------------------- blocky avatar
def _box(name, size, loc, material, bevel=0.08, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1)
    b = bpy.context.active_object
    for cc in list(b.users_collection): cc.objects.unlink(b)
    bpy.context.scene.collection.objects.link(b)
    b.name = name; b.scale = size; b.location = loc
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    m = b.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = 4; m.limit_method = 'NONE'
    b.data.materials.append(material)
    for p in b.data.polygons: p.use_smooth = True
    if parent: b.parent = parent
    return b

def face_material(name, face_png, skin):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.45
    img = bpy.data.images.load(os.path.join(ART, face_png), check_existing=True)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tex.extension = 'CLIP'
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    # project from the front (-Y) onto the head: use object coords X,Z
    mp.inputs["Location"].default_value = (0.5, 0.5, 0); mp.inputs["Scale"].default_value = (0.9, 0.9, 1)
    sx = nt.nodes.new("ShaderNodeSeparateXYZ"); cx = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(tc.outputs["Object"], sx.inputs[0])
    nt.links.new(sx.outputs[0], cx.inputs[0]); nt.links.new(sx.outputs[2], cx.inputs[1])
    nt.links.new(cx.outputs[0], mp.inputs[0]); nt.links.new(mp.outputs[0], tex.inputs[0])
    # only on the front face
    front = nt.nodes.new("ShaderNodeMath"); front.operation = 'LESS_THAN'; front.inputs[1].default_value = -0.2
    nn = nt.nodes.new("ShaderNodeSeparateXYZ"); geo = nt.nodes.new("ShaderNodeNewGeometry")
    vt = nt.nodes.new("ShaderNodeVectorTransform"); vt.convert_from = 'WORLD'; vt.convert_to = 'OBJECT'; vt.vector_type = 'NORMAL'
    nt.links.new(geo.outputs["Normal"], vt.inputs[0]); nt.links.new(vt.outputs[0], nn.inputs[0]); nt.links.new(nn.outputs[1], front.inputs[0])
    amul = nt.nodes.new("ShaderNodeMath"); amul.operation = 'MULTIPLY'
    nt.links.new(tex.outputs["Alpha"], amul.inputs[0]); nt.links.new(front.outputs[0], amul.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'
    mix.inputs[6].default_value = (*hexc(skin), 1)
    nt.links.new(amul.outputs[0], mix.inputs[0]); nt.links.new(tex.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    return m

def avatar(sc, name, loc, rot_z=0.0, shirt='#3d5a3a', pants='#2a2e33', skin='#f2c48f', face="face_grin.png",
           pose="cheer", helmet=True, helmet_color='#e8e8e8', visor='#ffb020', scale=1.0, accent=None):
    """Blocky Roblox-style pilot. Units: head 1.2, torso 2x2x1, limbs 1x2x1 (classic proportions)."""
    root = bpy.data.objects.new(name, None); root.location = loc; root.rotation_euler = (0, 0, rot_z); root.scale = (scale,) * 3
    link(root, sc)
    ms = mat(name + "Shirt", hexc(shirt), rough=0.6, coat=0.2)
    mp = mat(name + "Pants", hexc(pants), rough=0.7)
    mk = mat(name + "Skin", hexc(skin), rough=0.45, sss=0.05)
    _box(name + "_Torso", (2.0, 1.0, 2.0), (0, 0, 3.0), ms, 0.12, root)
    _box(name + "_LegL", (0.98, 1.0, 2.0), (-0.5, 0, 1.0), mp, 0.1, root)
    _box(name + "_LegR", (0.98, 1.0, 2.0), (0.5, 0, 1.0), mp, 0.1, root)
    if accent:
        ma = mat(name + "Acc", hexc(accent), metal=0.3, rough=0.35, coat=0.6)
        _box(name + "_Belt", (2.04, 1.04, 0.22), (0, 0, 2.1), ma, 0.05, root)
        _box(name + "_Patch", (0.5, 0.06, 0.5), (0.45, -0.52, 3.4), ma, 0.03, root)
    # arms pivot at the shoulders
    poses = {"cheer": (math.radians(160), math.radians(160)), "wave": (math.radians(160), math.radians(8)),
             "point": (math.radians(90), math.radians(10)), "idle": (math.radians(6), math.radians(6)),
             "thumbs": (math.radians(70), math.radians(8))}
    rl, rr = poses.get(pose, poses["idle"])
    for side, ang in ((-1, rl), (1, rr)):
        piv = bpy.data.objects.new(f"{name}_Sh{side}", None); piv.location = (side * 1.5, 0, 3.75); piv.parent = root; link(piv, sc)
        _box(f"{name}_Arm{side}", (0.98, 1.0, 2.0), (0, 0, -0.75), ms, 0.1, piv)
        _box(f"{name}_Hand{side}", (0.96, 0.98, 0.5), (0, 0, -1.55), mk, 0.12, piv)
        piv.rotation_euler = (0, -side * ang, 0)  # raise outward / up (arm hangs along -Z)
    # head (plain skin) + face decal on the front
    _box(name + "_Head", (1.25, 1.2, 1.2), (0, 0, 4.62), mk, 0.3, root)
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    fd = bpy.context.active_object
    for cc in list(fd.users_collection): cc.objects.unlink(fd)
    sc.collection.objects.link(fd)
    fd.name = name + "_Face"; fd.parent = root
    fd.location = (0, -0.612, 4.52); fd.rotation_euler = (math.radians(90), 0, 0); fd.scale = (1.5, 1.5, 1.5)
    fm = bpy.data.materials.new(name + "FaceMat"); fm.use_nodes = True
    fnt = fm.node_tree; fb = fnt.nodes["Principled BSDF"]; fb.inputs["Roughness"].default_value = 0.5
    ftx = fnt.nodes.new("ShaderNodeTexImage"); ftx.image = bpy.data.images.load(os.path.join(ART, face), check_existing=True)
    fnt.links.new(ftx.outputs["Color"], fb.inputs["Base Color"]); fnt.links.new(ftx.outputs["Alpha"], fb.inputs["Alpha"])
    fd.data.materials.append(fm)
    if helmet:
        mh = mat(name + "Helm", hexc(helmet_color), metal=0.1, rough=0.25, coat=1.0)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=0.86)
        h = bpy.context.active_object
        for cc in list(h.users_collection): cc.objects.unlink(h)
        sc.collection.objects.link(h)
        h.name = name + "_Helmet"; h.parent = root; h.location = (0, 0.1, 5.0); h.scale = (0.98, 0.98, 0.85)
        bm = bmesh.new(); bm.from_mesh(h.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.02], context='VERTS'); bm.to_mesh(h.data); bm.free()
        h.modifiers.new("Solid", 'SOLIDIFY').thickness = 0.08
        h.data.materials.append(mh)
        for p in h.data.polygons: p.use_smooth = True
        mv = mat(name + "Visor", hexc(visor), metal=0.9, rough=0.05, coat=1.0)
        _box(name + "_Visor", (1.28, 0.14, 0.26), (0, -0.62, 5.42), mv, 0.06, root).rotation_euler = (math.radians(-28), 0, 0)
    return root

# ---------------------------------------------------------------- logo
def text_obj(sc, body, font, size, extrude, bevel, material, loc, offset=0.0, name="Txt", align='LEFT', italic_shear=0.18):
    cu = bpy.data.curves.new(name, 'FONT'); cu.body = body
    cu.font = bpy.data.fonts.load(font, check_existing=True)
    cu.size = size; cu.extrude = extrude; cu.bevel_depth = bevel; cu.bevel_resolution = 3; cu.offset = offset
    cu.align_x = align; cu.align_y = 'CENTER'; cu.shear = italic_shear; cu.space_character = 0.96
    o = bpy.data.objects.new(name, cu); o.location = loc; link(o, sc)
    cu.materials.append(material)
    return o

def chrome_mat(name="Chrome"):
    m = mat(name, (0.95, 0.96, 1.0), metal=0.75, rough=0.12, coat=1.0)
    # vertical gradient tint: white top -> steel bottom, gives the "chrome title" read even with a flat env
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.38; ramp.color_ramp.elements[0].color = (*hexc('#7f8fa6'), 1)
    ramp.color_ramp.elements[1].position = 0.62; ramp.color_ramp.elements[1].color = (*hexc('#ffffff'), 1)
    ramp.color_ramp.elements.new(0.5).color = (*hexc('#c9d3e2'), 1)
    nt.links.new(sep.outputs[1], ramp.inputs[0]); nt.links.new(ramp.outputs[0], b.inputs["Base Color"])
    nt.links.new(ramp.outputs[0], b.inputs["Emission Color"]); b.inputs["Emission Strength"].default_value = 0.35
    return m

def logo(sc, parent_loc, rot, scale=1.0, accent='#ff7a1a', accent2='#ffb020'):
    """AERO (chrome) + STRIKE (hot amber) with a thick dark outline and a gold rim, plus a jet streak."""
    root = bpy.data.objects.new("Logo", None); root.location = parent_loc; root.rotation_euler = rot; root.scale = (scale,) * 3; link(root, sc)
    chrome = chrome_mat("LogoChrome")
    hot = mat("LogoHot", hexc(accent), metal=0.3, rough=0.15, coat=1.0)
    hn = hot.node_tree; hb = hn.nodes["Principled BSDF"]
    htc = hn.nodes.new("ShaderNodeTexCoord"); hsep = hn.nodes.new("ShaderNodeSeparateXYZ"); hn.links.new(htc.outputs["Generated"], hsep.inputs[0])
    hr = hn.nodes.new("ShaderNodeValToRGB")
    hr.color_ramp.elements[0].position = 0.35; hr.color_ramp.elements[0].color = (*hexc('#e8240c'), 1)
    hr.color_ramp.elements[1].position = 0.7; hr.color_ramp.elements[1].color = (*hexc('#ffd23a'), 1)
    hn.links.new(hsep.outputs[1], hr.inputs[0]); hn.links.new(hr.outputs[0], hb.inputs["Base Color"])
    hn.links.new(hr.outputs[0], hb.inputs["Emission Color"]); hb.inputs["Emission Strength"].default_value = 0.45
    dark = mat("LogoDark", hexc('#0f1420'), metal=0.2, rough=0.4)
    gold = mat("LogoGold", hexc('#ffc54a'), metal=1.0, rough=0.2)
    a = text_obj(sc, "AERO", FONT_BLACK, 4.0, 0.35, 0.05, chrome, (0, 0, 0), name="LogoAero")
    s = text_obj(sc, "STRIKE", FONT_BLACK, 4.0, 0.35, 0.05, hot, (0, 0, 0), name="LogoStrike")
    bpy.context.view_layer.update()
    aw = a.dimensions.x
    s.location.x = aw + 0.35
    for t in (a, s): t.parent = root
    # outlines (offset text behind)
    for t, nm in ((a, "AeroOut"), (s, "StrikeOut")):
        o2 = text_obj(sc, t.data.body, FONT_BLACK, 4.0, 0.25, 0.0, dark, (t.location.x, 0.0, 0.0), offset=0.22, name=nm)
        o2.location.y = 0.55; o2.parent = root
        o3 = text_obj(sc, t.data.body, FONT_BLACK, 4.0, 0.12, 0.0, gold, (t.location.x, 0.0, 0.0), offset=0.32, name=nm + "Gold")
        o3.location.y = 0.9; o3.parent = root
    bpy.context.view_layer.update()
    total = s.location.x + s.dimensions.x
    # center the word on the root
    for c in root.children: c.location.x -= total / 2
    return root, total

# ---------------------------------------------------------------- camera
def camera(sc, loc, target, lens=50, name="Cam", roll=0.0):
    d = bpy.data.cameras.new(name); d.lens = lens; d.clip_end = 20000; d.clip_start = 0.5
    o = bpy.data.objects.new(name, d); o.location = loc
    q = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y')
    o.rotation_euler = q.to_euler()
    if roll: o.rotation_euler.rotate_axis('Z', roll)
    link(o, sc); sc.camera = o
    return o

def aim(obj, target, up='Z'):
    q = (Vector(target) - obj.location).to_track_quat('-Y', up)
    obj.rotation_euler = q.to_euler()

def render(sc, path):
    sc.render.filepath = path
    bpy.context.window.scene = sc
    bpy.ops.render.render(write_still=True, scene=sc.name)
    return path
