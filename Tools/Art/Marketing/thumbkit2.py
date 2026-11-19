# AeroStrike marketing kit v2 (Blender 5.x): physical sky, volumetric cloud sea, PBR jets, AgX.
# Exec'd after thumbkit.py (reuses copy_model / flame / fireball / camera / render / mat / hexc).
import bpy, bmesh, math, random
from mathutils import Vector, Euler

def scene2(name, w=1920, h=1080, samples=256):
    sc = new_scene(name, w, h, samples=samples)
    vs = sc.view_settings
    try:
        vs.view_transform = 'AgX'; vs.look = 'AgX - Punchy'
    except Exception:
        try: vs.look = 'Punchy'
        except Exception: pass
    vs.exposure = 0.0
    sc.cycles.max_bounces = 12
    sc.cycles.volume_bounces = 2
    sc.cycles.transparent_max_bounces = 16
    try: sc.cycles.volume_step_rate = 2.0
    except Exception: pass
    return sc

def sky2(sc, sun_elev=7.0, sun_rot=200.0, strength=1.0, altitude=2500.0, air=1.0, aerosol=1.2, ozone=1.0, sun_disc=True, sun_strength=4.0, sun_color='#ffd2a0'):
    """Physical sky + a matching sun lamp. sun_rot: degrees, compass heading the sun sits at (0 = +Y)."""
    w = sc.world; w.use_nodes = True
    nt = w.node_tree; nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_disc = sun_disc
    sky.sun_size = math.radians(1.2)
    sky.sun_intensity = 0.6
    sky.sun_elevation = math.radians(sun_elev)
    # sky sun_rotation 0 points along +Y? Blender: rotation around Z, 0 = +X. Convert our heading.
    sky.sun_rotation = math.radians(90.0 - sun_rot)
    sky.altitude = altitude
    sky.air_density = air; sky.aerosol_density = aerosol; sky.ozone_density = ozone
    bg = nt.nodes.new("ShaderNodeBackground"); bg.inputs[1].default_value = strength
    nt.links.new(sky.outputs[0], bg.inputs[0])
    out = nt.nodes.new("ShaderNodeOutputWorld"); nt.links.new(bg.outputs[0], out.inputs[0])
    # sun lamp pointing from the same direction
    d = bpy.data.lights.new("Sun", 'SUN'); d.energy = sun_strength; d.color = hexc(sun_color); d.angle = math.radians(1.5)
    o = bpy.data.objects.new("Sun", d); link(o, sc)
    el, az = math.radians(sun_elev), math.radians(sun_rot)
    to_sun = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
    o.rotation_euler = (-to_sun).to_track_quat('-Z', 'Y').to_euler()
    o.visible_glossy = False if not sun_disc else True
    return o, to_sun

def cloud_sea(sc, z_bottom=-420.0, thickness=260.0, size=60000.0, coverage=0.5, density=0.035, scale=1.0, seed=0.0, tint='#ffffff', name="Clouds"):
    """A big flat volume box filled with puffy fBm clouds (flat-ish bottoms, rounded tops)."""
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    for cc in list(o.users_collection): cc.objects.unlink(o)
    sc.collection.objects.link(o)
    o.name = name; o.scale = (size, size, thickness); o.location = (0, 0, z_bottom + thickness / 2)
    m = bpy.data.materials.new(name + "Mat"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (*hexc(tint), 1)
    vol.inputs["Anisotropy"].default_value = 0.55
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    geo = nt.nodes.new("ShaderNodeTexCoord")
    # world-space position (independent of the huge object scale)
    pos = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(pos.outputs["Position"], sep.inputs[0])
    # height 0..1 through the slab
    h = nt.nodes.new("ShaderNodeMapRange"); h.inputs[1].default_value = z_bottom; h.inputs[2].default_value = z_bottom + thickness
    nt.links.new(sep.outputs[2], h.inputs[0])
    # stretched horizontal coords for big cloud masses + warped detail
    mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (1.0 / (900 * scale), 1.0 / (900 * scale), 1.0 / (520 * scale))
    mp.inputs["Location"].default_value = (seed, seed * 0.7, 0)
    nt.links.new(pos.outputs["Position"], mp.inputs[0])
    big = nt.nodes.new("ShaderNodeTexNoise"); big.inputs["Scale"].default_value = 1.0; big.inputs["Detail"].default_value = 3; big.inputs["Roughness"].default_value = 0.5
    nt.links.new(mp.outputs[0], big.inputs[0])
    mp2 = nt.nodes.new("ShaderNodeMapping"); mp2.inputs["Scale"].default_value = (1.0 / (140 * scale), 1.0 / (140 * scale), 1.0 / (110 * scale))
    nt.links.new(pos.outputs["Position"], mp2.inputs[0])
    det = nt.nodes.new("ShaderNodeTexNoise"); det.inputs["Scale"].default_value = 1.0; det.inputs["Detail"].default_value = 8; det.inputs["Roughness"].default_value = 0.6
    det.inputs["Distortion"].default_value = 0.4
    nt.links.new(mp2.outputs[0], det.inputs[0])
    # combine: big masses dominate, detail erodes edges
    mix = nt.nodes.new("ShaderNodeMath"); mix.operation = 'MULTIPLY_ADD'
    nt.links.new(det.outputs[0], mix.inputs[0]); mix.inputs[1].default_value = 0.35
    nt.links.new(big.outputs[0], mix.inputs[2])
    # height profile: flat bottom, rounded top -> threshold rises with height
    prof = nt.nodes.new("ShaderNodeFloatCurve")
    cv = prof.mapping.curves[0]
    cv.points[0].location = (0.0, 0.0); cv.points[1].location = (1.0, 0.0)
    cv.points.new(0.08, 1.0); cv.points.new(0.35, 0.9); cv.points.new(0.75, 0.45)
    prof.mapping.update()
    nt.links.new(h.outputs[0], prof.inputs[1])
    # density = smoothstep(threshold) where threshold = 1 - coverage*profile
    thr = nt.nodes.new("ShaderNodeMath"); thr.operation = 'MULTIPLY'; thr.inputs[1].default_value = coverage * 0.5
    nt.links.new(prof.outputs[0], thr.inputs[0])
    t0 = nt.nodes.new("ShaderNodeMath"); t0.operation = 'SUBTRACT'; t0.inputs[0].default_value = 0.98
    nt.links.new(thr.outputs[0], t0.inputs[1])
    diff = nt.nodes.new("ShaderNodeMath"); diff.operation = 'SUBTRACT'
    nt.links.new(mix.outputs[0], diff.inputs[0]); nt.links.new(t0.outputs[0], diff.inputs[1])
    sm = nt.nodes.new("ShaderNodeMapRange"); sm.interpolation_type = 'SMOOTHSTEP'
    sm.inputs[1].default_value = 0.0; sm.inputs[2].default_value = 0.06
    nt.links.new(diff.outputs[0], sm.inputs[0])
    dens = nt.nodes.new("ShaderNodeMath"); dens.operation = 'MULTIPLY'; dens.inputs[1].default_value = density
    nt.links.new(sm.outputs[0], dens.inputs[0])
    nt.links.new(dens.outputs[0], vol.inputs["Density"])
    o.data.materials.append(m)
    o.visible_shadow = True
    return o

def cloud_puff(sc, loc, radius=120.0, density=0.05, seed=1, name="Puff", squash=0.6):
    """A single cumulus volume (displaced sphere density) for foreground / framing clouds."""
    bpy.ops.mesh.primitive_cube_add(size=2)
    o = bpy.context.active_object
    for cc in list(o.users_collection): cc.objects.unlink(o)
    sc.collection.objects.link(o)
    o.name = name; o.location = loc; o.scale = (radius * 1.6, radius * 1.6, radius * 1.6 * squash)
    m = bpy.data.materials.new(name + "Mat"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled"); vol.inputs["Anisotropy"].default_value = 0.5
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ln = nt.nodes.new("ShaderNodeVectorMath"); ln.operation = 'LENGTH'
    nt.links.new(tc.outputs["Object"], ln.inputs[0]); LV = ln.outputs["Value"]
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 2.2; noise.inputs["Detail"].default_value = 8; noise.inputs["Roughness"].default_value = 0.62
    noise.noise_dimensions = "4D"; noise.inputs["W"].default_value = seed
    nt.links.new(tc.outputs["Object"], noise.inputs[0])
    sub = nt.nodes.new("ShaderNodeMath"); sub.operation = 'MULTIPLY_ADD'
    nt.links.new(noise.outputs[0], sub.inputs[0]); sub.inputs[1].default_value = 0.7; sub.inputs[2].default_value = 0.0
    edge = nt.nodes.new("ShaderNodeMath"); edge.operation = 'SUBTRACT'
    nt.links.new(sub.outputs[0], edge.inputs[0]); nt.links.new(LV, edge.inputs[1])
    # flatten the bottom
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Object"], sep.inputs[0])
    flat = nt.nodes.new("ShaderNodeMapRange"); flat.inputs[1].default_value = -0.35; flat.inputs[2].default_value = -0.15
    nt.links.new(sep.outputs[2], flat.inputs[0])
    sm = nt.nodes.new("ShaderNodeMapRange"); sm.interpolation_type = 'SMOOTHSTEP'; sm.inputs[1].default_value = -0.25; sm.inputs[2].default_value = -0.1
    nt.links.new(edge.outputs[0], sm.inputs[0])
    m1 = nt.nodes.new("ShaderNodeMath"); m1.operation = 'MULTIPLY'
    nt.links.new(sm.outputs[0], m1.inputs[0]); nt.links.new(flat.outputs[0], m1.inputs[1])
    m2 = nt.nodes.new("ShaderNodeMath"); m2.operation = 'MULTIPLY'; m2.inputs[1].default_value = density
    nt.links.new(m1.outputs[0], m2.inputs[0]); nt.links.new(m2.outputs[0], vol.inputs["Density"])
    o.data.materials.append(m)
    return o

def ocean2(sc, z=-900.0, size=200000.0, color='#06223f'):
    me = bpy.data.meshes.new("Ocean")
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("Ocean", me); o.location.z = z; link(o, sc)
    m = mat("OceanMat", hexc(color), rough=0.08)
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 0.02; noise.inputs["Detail"].default_value = 10
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.15
    tc = nt.nodes.new("ShaderNodeTexCoord"); nt.links.new(tc.outputs["Object"], noise.inputs[0])
    nt.links.new(noise.outputs[0], bump.inputs["Height"]); nt.links.new(bump.outputs[0], b.inputs["Normal"])
    me.materials.append(m)
    return o

# ------------------------------------------------------------- jet beautify
PAINTS2 = {
    "Mako":   dict(body='#2a313a', accent='#ff9d1a', intake='#2a3038', panel=0.06),
    "Viper":  dict(body='#46525f', accent='#ff9d1a', intake='#2a3038', panel=0.06),
    "Night":  dict(body='#22262e', accent='#e8332a', intake='#15181d', panel=0.05),
    "Wraith": dict(body='#2a2e36', accent='#ffc24a', intake='#14161a', panel=0.04),
    "Talon":  dict(body='#3a3d44', accent='#e8332a', intake='#1d1f24', panel=0.05),
    "Rhino":  dict(body='#5e6656', accent='#ff9d1a', intake='#2a3028', panel=0.06),
    "Navy":   dict(body='#6b7684', accent='#ffb020', intake='#2a3038', panel=0.05),
}

def paint_mat(name, base, rough=0.32, coat=0.6, metal=0.35, panel=0.06):
    m = mat(name, hexc(base), metal=metal, rough=rough, coat=coat)
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    # subtle panel / grime variation so surfaces aren't flat plastic
    vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 0.9; vor.feature = 'DISTANCE_TO_EDGE'
    nt.links.new(tc.outputs["Object"], vor.inputs[0])
    ln = nt.nodes.new("ShaderNodeMapRange"); ln.inputs[1].default_value = 0.0; ln.inputs[2].default_value = 0.015
    nt.links.new(vor.outputs["Distance"], ln.inputs[0])
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 2.5; noise.inputs["Detail"].default_value = 6
    nt.links.new(tc.outputs["Object"], noise.inputs[0])
    var = nt.nodes.new("ShaderNodeMapRange"); var.inputs[3].default_value = 1.0 - panel; var.inputs[4].default_value = 1.0 + panel
    nt.links.new(noise.outputs[0], var.inputs[0])
    lines = nt.nodes.new("ShaderNodeMapRange"); lines.inputs[3].default_value = 0.72; lines.inputs[4].default_value = 1.0
    nt.links.new(ln.outputs[0], lines.inputs[0])
    k = nt.nodes.new("ShaderNodeMath"); k.operation = 'MULTIPLY'
    nt.links.new(var.outputs[0], k.inputs[0]); nt.links.new(lines.outputs[0], k.inputs[1])
    tint = nt.nodes.new("ShaderNodeMix"); tint.data_type = 'RGBA'; tint.blend_type = 'MULTIPLY'; tint.inputs[0].default_value = 1.0
    tint.inputs[6].default_value = (*hexc(base), 1)
    comb = nt.nodes.new("ShaderNodeCombineColor"); nt.links.new(k.outputs[0], comb.inputs[0]); nt.links.new(k.outputs[0], comb.inputs[1]); nt.links.new(k.outputs[0], comb.inputs[2])
    nt.links.new(comb.outputs[0], tint.inputs[7])
    nt.links.new(tint.outputs[2], b.inputs["Base Color"])
    rr = nt.nodes.new("ShaderNodeMapRange"); rr.inputs[3].default_value = rough * 0.75; rr.inputs[4].default_value = rough * 1.35
    nt.links.new(noise.outputs[0], rr.inputs[0]); nt.links.new(rr.outputs[0], b.inputs["Roughness"])
    return m

def jet2(export_coll, sc, paint="Mako", name="Jet", glow=30.0):
    root = copy_model(export_coll, sc, "Gunmetal", name, glow_strength=glow)
    p = PAINTS2.get(paint, PAINTS2["Mako"])
    mats = {
        "Body": paint_mat(name + "_B2", p["body"], rough=0.5, coat=0.12, metal=0.05, panel=p["panel"]),
        "Accents": paint_mat(name + "_A2", p["accent"], rough=0.28, coat=0.9, metal=0.2, panel=0.03),
        "Markings": paint_mat(name + "_M2", p["accent"], rough=0.28, coat=0.9, metal=0.2, panel=0.03),
        "Intakes": paint_mat(name + "_I2", p["intake"], rough=0.45, coat=0.2, metal=0.5, panel=0.04),
        "Trim": mat(name + "_T2", hexc('#15171b'), metal=0.85, rough=0.38),
        "Canopy": mat(name + "_C2", hexc('#2b1c08'), metal=0.95, rough=0.03, coat=1.0),
        "Hull": paint_mat(name + "_H2", '#4a525d', rough=0.55, coat=0.1, metal=0.1, panel=0.08),
        "Deck": paint_mat(name + "_D2", '#2c3036', rough=0.75, coat=0.0, metal=0.0, panel=0.1),
    }
    for c in root.children:
        if c.type != 'MESH':
            continue
        part = c.name[len(name) + 1:].split(".")[0]
        if part in mats:
            c.data.materials.clear(); c.data.materials.append(mats[part])
        # smooth by angle keeps hard edges crisp and curved surfaces smooth
        for poly in c.data.polygons: poly.use_smooth = True
        try:
            with bpy.context.temp_override(active_object=c, selected_editable_objects=[c], selected_objects=[c], object=c):
                bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        except Exception:
            pass
        bv = c.modifiers.new("Bevel", 'BEVEL'); bv.width = 0.035; bv.segments = 2; bv.limit_method = 'ANGLE'; bv.angle_limit = math.radians(35)
        bv.harden_normals = False
    return root

def flame2(parent, local_pos, length=8.0, radius=0.55, strength=90, light=6000):
    """Afterburner: hot white core inside an orange-blue plume, with shock diamonds."""
    out = []
    for i, (ln, rad, col, st, fac) in enumerate([
            (length, radius, '#ff8a2a', strength, 0.25),
            (length * 0.55, radius * 0.55, '#fff2d0', strength * 2.2, 0.5)]):
        bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=rad, radius2=0.02, depth=ln)
        c = bpy.context.active_object
        for cc in list(c.users_collection): cc.objects.unlink(c)
        bpy.context.scene.collection.objects.link(c)
        c.name = f"{parent.name}_Fl{i}"; c.parent = parent
        c.rotation_euler = (math.radians(-90), 0, 0)
        c.location = Vector(local_pos) + Vector((0, ln / 2, 0))
        m = bpy.data.materials.new(c.name + "M"); m.use_nodes = True
        nt = m.node_tree; nt.nodes.clear()
        em = nt.nodes.new("ShaderNodeEmission"); em.inputs[0].default_value = (*hexc(col), 1); em.inputs[1].default_value = st
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs[0].default_value = fac
        # fade towards the tip using object Z along the cone
        tc = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Generated"], sep.inputs[0])
        f = nt.nodes.new("ShaderNodeMath"); f.operation = 'MULTIPLY'
        nt.links.new(lw.outputs["Facing"], f.inputs[0])
        pw = nt.nodes.new("ShaderNodeMath"); pw.operation = 'POWER'; pw.inputs[1].default_value = 0.7
        nt.links.new(sep.outputs[2], pw.inputs[0]); nt.links.new(pw.outputs[0], f.inputs[1])
        inv = nt.nodes.new("ShaderNodeMath"); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0; nt.links.new(f.outputs[0], inv.inputs[1])
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(inv.outputs[0], mix.inputs[0]); nt.links.new(em.outputs[0], mix.inputs[1]); nt.links.new(tr.outputs[0], mix.inputs[2])
        o = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(mix.outputs[0], o.inputs[0])
        c.data.materials.append(m); c.visible_shadow = False
        out.append(c)
    pl = bpy.data.lights.new(parent.name + "_AB", 'POINT'); pl.energy = light; pl.color = hexc('#ff8a3a'); pl.shadow_soft_size = 1.0
    lo = bpy.data.objects.new(parent.name + "_AB", pl); lo.parent = parent; lo.location = Vector(local_pos) + Vector((0, 2.5, 0)); link(lo)
    return out

def contrail(sc, points, radius=0.5, name="Contrail", alpha=0.7, grow=4.0, color='#ffffff'):
    """Soft volumetric-looking smoke tube (emission-free, scatters light), widening with age."""
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'
    sp = cu.splines.new('BEZIER'); sp.bezier_points.add(len(points) - 1)
    n = len(points)
    for i, p in enumerate(points):
        bp = sp.bezier_points[i]; bp.co = p; bp.handle_left_type = bp.handle_right_type = 'AUTO'
        bp.radius = 0.3 + (i / max(1, n - 1)) ** 1.3 * grow
    cu.bevel_depth = radius; cu.bevel_resolution = 8; cu.resolution_u = 32; cu.use_fill_caps = True
    o = bpy.data.objects.new(name, cu); link(o, sc)
    m = bpy.data.materials.new(name + "M"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled"); vol.inputs["Color"].default_value = (*hexc(color), 1); vol.inputs["Anisotropy"].default_value = 0.3
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 0.6; noise.inputs["Detail"].default_value = 6
    nt.links.new(tc.outputs["Object"], noise.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange"); mr.inputs[1].default_value = 0.35; mr.inputs[2].default_value = 0.6; mr.inputs[4].default_value = alpha
    nt.links.new(noise.outputs[0], mr.inputs[0]); nt.links.new(mr.outputs[0], vol.inputs["Density"])
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    cu.materials.append(m)
    o.visible_shadow = False
    return o

def fireball2(sc, loc, size=14.0, name="Boom", seed=1, light=250000):
    """Volumetric explosion: emissive fire core + dark smoke shell."""
    random.seed(seed)
    root = bpy.data.objects.new(name, None); root.location = loc; link(root, sc)
    def blob(i, r, pos, fire):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r)
        s = bpy.context.active_object
        for cc in list(s.users_collection): cc.objects.unlink(s)
        sc.collection.objects.link(s)
        s.name = f"{name}_{'F' if fire else 'S'}{i}"; s.parent = root; s.location = pos
        m = bpy.data.materials.new(s.name + "M"); m.use_nodes = True
        nt = m.node_tree; nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        vol = nt.nodes.new("ShaderNodeVolumePrincipled")
        tc = nt.nodes.new("ShaderNodeTexCoord")
        ln = nt.nodes.new("ShaderNodeVectorMath"); ln.operation = 'LENGTH'; nt.links.new(tc.outputs["Object"], ln.inputs[0]); LV = ln.outputs["Value"]
        noise = nt.nodes.new("ShaderNodeTexNoise"); noise.noise_dimensions = '4D'; noise.inputs["W"].default_value = seed * 3 + i
        noise.inputs["Scale"].default_value = 2.5 / r; noise.inputs["Detail"].default_value = 8; noise.inputs["Roughness"].default_value = 0.6
        nt.links.new(tc.outputs["Object"], noise.inputs[0])
        nrm = nt.nodes.new("ShaderNodeMath"); nrm.operation = 'DIVIDE'; nrm.inputs[1].default_value = r
        nt.links.new(LV, nrm.inputs[0])
        e = nt.nodes.new("ShaderNodeMath"); e.operation = 'MULTIPLY_ADD'; e.inputs[1].default_value = 1.5; e.inputs[2].default_value = 0.05
        nt.links.new(noise.outputs[0], e.inputs[0])
        d = nt.nodes.new("ShaderNodeMath"); d.operation = 'SUBTRACT'
        nt.links.new(e.outputs[0], d.inputs[0]); nt.links.new(nrm.outputs[0], d.inputs[1])
        sm = nt.nodes.new("ShaderNodeMapRange"); sm.interpolation_type = 'SMOOTHSTEP'; sm.inputs[1].default_value = 0.0; sm.inputs[2].default_value = 0.4
        nt.links.new(d.outputs[0], sm.inputs[0])
        dens = nt.nodes.new("ShaderNodeMath"); dens.operation = 'MULTIPLY'; dens.inputs[1].default_value = (3.0 if fire else 1.2) / r
        nt.links.new(sm.outputs[0], dens.inputs[0]); nt.links.new(dens.outputs[0], vol.inputs["Density"])
        if fire:
            vol.inputs["Color"].default_value = (*hexc('#3a1a0a'), 1)
            ramp = nt.nodes.new("ShaderNodeValToRGB"); els = ramp.color_ramp.elements
            els[0].position = 0.0; els[0].color = (*hexc('#a01800'), 1); els[1].position = 1.0; els[1].color = (*hexc('#fff0b0'), 1)
            els.new(0.45).color = (*hexc('#ff6a0a'), 1); els.new(0.75).color = (*hexc('#ffc040'), 1)
            nt.links.new(sm.outputs[0], ramp.inputs[0])
            nt.links.new(ramp.outputs[0], vol.inputs["Emission Color"])
            st = nt.nodes.new("ShaderNodeMath"); st.operation = 'MULTIPLY'; st.inputs[1].default_value = 22.0
            nt.links.new(sm.outputs[0], st.inputs[0]); nt.links.new(st.outputs[0], vol.inputs["Emission Strength"])
        else:
            vol.inputs["Color"].default_value = (*hexc('#2a2622'), 1)
        nt.links.new(vol.outputs[0], out.inputs["Volume"])
        s.data.materials.append(m); s.visible_shadow = False
    for i in range(4):
        r = size * random.uniform(0.6, 0.9)
        blob(i, r * 1.25, Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(0.2, 1.2))) * size * 0.75, False)
    for i in range(9):
        r = size * random.uniform(0.4, 0.75)
        blob(i, r, Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.6, 0.6))) * size * 0.5, True)
    pl = bpy.data.lights.new(name + "L", 'POINT'); pl.energy = light; pl.color = hexc('#ff8a30'); pl.shadow_soft_size = size * 0.6
    lo = bpy.data.objects.new(name + "L", pl); lo.parent = root; link(lo, sc)
    return root

def ocean_waves(sc, z=0.0, size=400.0, repeat=12, color='#06263f', wave_scale=1.2, choppy=1.0, name="Sea"):
    """Real displaced ocean (Ocean modifier) for close-to-water shots, tiled out to the horizon area."""
    bpy.ops.mesh.primitive_plane_add(size=2)
    o = bpy.context.active_object
    for cc in list(o.users_collection): cc.objects.unlink(o)
    sc.collection.objects.link(o)
    o.name = name; o.location = (0, 0, z)
    md = o.modifiers.new("Ocean", 'OCEAN')
    md.geometry_mode = 'GENERATE'; md.spatial_size = int(size); md.resolution = 7
    md.repeat_x = repeat; md.repeat_y = repeat; md.wave_scale = wave_scale; md.choppiness = choppy
    md.wind_velocity = 14; md.wave_alignment = 0.3; md.use_normals = True
    o.location = (-size * repeat / 2, -size * repeat / 2, z)
    m = mat(name + "Mat", hexc(color), rough=0.1)
    b = m.node_tree.nodes["Principled BSDF"]
    if "Transmission Weight" in b.inputs: b.inputs["Transmission Weight"].default_value = 0.0
    if "Subsurface Weight" in b.inputs: b.inputs["Subsurface Weight"].default_value = 0.0
    o.data.materials.append(m)
    for p in o.data.polygons: p.use_smooth = True
    return o

def tracer(sc, a, b, n=6, length=7.0, radius=0.16, color='#ffd84a', strength=60, name="Tr"):
    tr = emission_mat(name + "M", hexc(color), strength)
    a, b = Vector(a), Vector(b); d = b - a
    for k in range(n):
        p0 = a + d * (k / n + 0.04)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=length)
        c = bpy.context.active_object
        for cc in list(c.users_collection): cc.objects.unlink(c)
        sc.collection.objects.link(c)
        c.name = f"{name}{k}"; c.location = p0; c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        c.data.materials.append(tr); c.visible_shadow = False
