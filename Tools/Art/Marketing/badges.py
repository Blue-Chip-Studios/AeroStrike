# Badge icons: gold-rimmed enamel medallions with a 3D emblem (512x512, transparent)
import bpy, bmesh, math
from mathutils import Vector, Euler
exec(open(ART_DIR + r"\thumbkit.py", encoding="utf-8").read())

COLORS = {"flight": '#1f5ae0', "combat": '#d0222f', "jets": '#6a2bd1', "event": '#ef7a12', "honor": '#1b1f2e'}

def base_scene(key):
    sc = new_scene("BADGE_" + key, 512, 512, samples=SAMPLES, transparent=True)
    w = sc.world; w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg: bg.inputs[0].default_value = (0.35, 0.35, 0.4, 1); bg.inputs[1].default_value = 0.6
    cam = bpy.data.cameras.new("BCam"); cam.type = 'ORTHO'; cam.ortho_scale = 21.5
    co = bpy.data.objects.new("BCam", cam); co.location = (0, 0, 40); link(co, sc); sc.camera = co
    co.rotation_euler = (Vector((0, 0, 0)) - co.location).to_track_quat('-Z', 'Y').to_euler()
    area(sc, (-14, -10, 30), (0, 0, 0), energy=9000, size=14, color='#ffffff', name="BKey")
    area(sc, (16, 12, 18), (0, 0, 0), energy=4000, size=14, color='#ffd7a0', name="BRim")
    return sc

def medallion(sc, color):
    gold = mat("Gold", hexc('#ffc23a'), metal=1.0, rough=0.22, coat=0.6)
    enamel = mat("Enamel", hexc(color), metal=0.1, rough=0.2, coat=1.0)
    ring2 = mat("Ring2", hexc('#fff1c2'), metal=1.0, rough=0.15)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=9.4, depth=0.8, location=(0, 0, 0))
    d = bpy.context.active_object
    for cc in list(d.users_collection): cc.objects.unlink(d)
    sc.collection.objects.link(d); d.data.materials.append(enamel)
    bv = d.modifiers.new("B", 'BEVEL'); bv.width = 0.25; bv.segments = 4
    # subtle radial sheen: noise bump on the enamel
    for name, R, r, z, m in (("Rim", 9.6, 0.75, 0.25, gold), ("Inner", 8.1, 0.14, 0.45, ring2)):
        bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=128, minor_segments=24, location=(0, 0, z))
        t = bpy.context.active_object
        for cc in list(t.users_collection): cc.objects.unlink(t)
        sc.collection.objects.link(t); t.data.materials.append(m)
        for p in t.data.polygons: p.use_smooth = True
    for p in d.data.polygons: p.use_smooth = False
    # ray burst behind the emblem
    burst = mat("Burst", hexc('#ffffff'), rough=0.4, alpha=0.09)
    for i in range(16):
        bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0.42))
        b = bpy.context.active_object
        for cc in list(b.users_collection): cc.objects.unlink(b)
        sc.collection.objects.link(b)
        me = b.data
        for v in me.vertices:
            v.co.x *= 0.9 if v.co.y > 0 else 0.05
            v.co.y = (v.co.y + 0.5) * 7.6
        b.rotation_euler = (0, 0, i * math.tau / 16)
        b.data.materials.append(burst)

def star(sc, r1=4.2, r2=1.8, depth=0.9, z=1.6, color='#ffd23a', name="Star"):
    bm = bmesh.new()
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        rr = r1 if i % 2 == 0 else r2
        pts.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, 0)))
    f = bm.faces.new(pts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]: v.co.z += depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = (0, 0, z); link(o, sc)
    bv = o.modifiers.new("B", 'BEVEL'); bv.width = 0.25; bv.segments = 3
    me.materials.append(mat(name + "M", hexc(color), metal=0.9, rough=0.2, coat=0.6))
    return o

def jet_emblem(sc, export, paint, scale=0.42, rot=135, z=2.5, flames=None):
    j = copy_model(export, sc, paint, "J_" + export)
    j.scale = (scale,) * 3
    j.rotation_euler = (0, 0, math.radians(rot))
    j.location = (0, 0, z)
    for f in (flames or []):
        flame(j, f, length=7, radius=0.55, strength=60)
    return j

def crosshair(sc, color='#ffffff'):
    m = mat("XH", hexc(color), metal=0.2, rough=0.3, coat=0.8, emit=hexc(color), emit_str=0.6)
    bpy.ops.mesh.primitive_torus_add(major_radius=5.2, minor_radius=0.35, major_segments=96, minor_segments=16, location=(0, 0, 1.4))
    t = bpy.context.active_object
    for cc in list(t.users_collection): cc.objects.unlink(t)
    sc.collection.objects.link(t); t.data.materials.append(m)
    for (x, y, sx, sy) in ((0, 5.2, 0.5, 2.6), (0, -5.2, 0.5, 2.6), (5.2, 0, 2.6, 0.5), (-5.2, 0, 2.6, 0.5)):
        _box("XB", (sx, sy, 0.6), (x, y, 1.4), m, 0.1)

def trophy(sc):
    g = mat("Trophy", hexc('#ffc23a'), metal=1.0, rough=0.18, coat=0.5)
    prof = [(0, -4.6), (3.0, -4.6), (3.0, -3.8), (1.0, -3.4), (0.6, -1.0), (1.2, -0.2), (3.6, 1.0), (3.9, 4.4), (3.5, 4.4), (0, 1.6)]
    bm = bmesh.new()
    rings = []
    N = 48
    for (r, h) in prof:
        rings.append([bm.verts.new((math.cos(t * math.tau / N) * r, h, math.sin(t * math.tau / N) * r)) for t in range(N)])
    for a, b in zip(rings, rings[1:]):
        for i in range(N):
            j = (i + 1) % N
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Cup"); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("Cup", me); o.location = (0, -0.2, 2.0); link(o, sc)
    for p in me.polygons: p.use_smooth = True
    me.materials.append(g)
    for side in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(major_radius=1.3, minor_radius=0.32, location=(side * 4.0, 2.4, 2.0))
        h = bpy.context.active_object
        for cc in list(h.users_collection): cc.objects.unlink(h)
        sc.collection.objects.link(h); h.data.materials.append(g)
    star(sc, r1=1.2, r2=0.5, depth=0.4, z=6.2, color='#ffffff', name="CupStar").location = (0, 1.8, 6.2)

def mach_cone(sc):
    m = mat("Cone", hexc('#ffffff'), rough=0.3, alpha=0.35, transmission=0.0)
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=4.6, radius2=0.0, depth=6.5, end_fill_type='NOTHING')
    c = bpy.context.active_object
    for cc in list(c.users_collection): cc.objects.unlink(c)
    sc.collection.objects.link(c)
    d = Vector((0.7071, 0.7071, 0.0))  # nose direction (jets point up-right)
    c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    c.location = Vector((0, 0, 2.6)) + d * 1.4
    c.data.materials.append(m)
    for p in c.data.polygons: p.use_smooth = True

BADGES = {
    "Welcome": ("flight", lambda sc: jet_emblem(sc, "EXPORT_SparrowT2", "Gunmetal", flames=[(0, 13.5, 0.3)])),
    "FirstKill": ("combat", lambda sc: (jet_emblem(sc, "EXPORT_FX_Missile", "Gunmetal", scale=3.4, rot=135, z=2.2), fireball(sc, (3.9, 3.9, 3.0), size=2.6, name="FK", seed=2))),
    "MachOne": ("flight", lambda sc: (jet_emblem(sc, "EXPORT_Jet_MakoSR9", "Mako", scale=0.4), mach_cone(sc))),
    "CarrierTrap": ("flight", lambda sc: jet_emblem(sc, "EXPORT_Carrier", "Gunmetal", scale=0.055, rot=140, z=1.0)),
    "MultiKill": ("combat", lambda sc: [fireball(sc, p, size=2.6, name=f"MK{i}", seed=i + 3) for i, p in enumerate(((-3.4, -2.0, 2.5), (0, 2.6, 2.5), (3.4, -2.0, 2.5)))]),
    "Ace": ("honor", lambda sc: star(sc, r1=5.2, r2=2.2)),
    "BountyHunter": ("combat", lambda sc: (crosshair(sc), star(sc, r1=2.6, r2=1.1, depth=0.6, z=1.8))),
    "Fortress": ("event", lambda sc: jet_emblem(sc, "EXPORT_NPC_TalonBomber", "Talon", scale=0.3, rot=135, z=2.0)),
    "Viper": ("jets", lambda sc: jet_emblem(sc, "EXPORT_ViperIX", "Viper", flames=[(0, 14.6, 0.35)])),
    "Rhino": ("jets", lambda sc: jet_emblem(sc, "EXPORT_Jet_RhinoHX", "Rhino", scale=0.38)),
    "Mako": ("jets", lambda sc: jet_emblem(sc, "EXPORT_Jet_MakoSR9", "Mako", scale=0.38, flames=[(0.72, 14.8, 0.3), (-0.72, 14.8, 0.3)])),
    "Wraith": ("jets", lambda sc: jet_emblem(sc, "EXPORT_Jet_WraithX", "Wraith", scale=0.4)),
    "Mastery": ("honor", lambda sc: (star(sc, r1=5.0, r2=2.1, color='#ffd23a'), jet_emblem(sc, "EXPORT_Jet_MakoSR9", "Mako", scale=0.2, rot=135, z=3.6))),
    "TopAce": ("honor", lambda sc: trophy(sc)),
}

done = []
for key in (ONLY or list(BADGES.keys())):
    cat, build = BADGES[key]
    sc = base_scene(key)
    medallion(sc, COLORS[cat])
    build(sc)
    # scene-scale point lights (fireballs, afterburners) are far too hot on a coin
    for o in sc.objects:
        if o.type == 'LIGHT' and o.data.type == 'POINT':
            o.data.energy = 60 if o.name.endswith("_AB") else 250
    render(sc, ART_DIR + "\\badge_" + key + ".png")
    done.append(key)
