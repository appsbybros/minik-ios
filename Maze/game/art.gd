class_name MazeArt
extends RefCounted

static var materials:Dictionary={}
static var sphere:SphereMesh
static var cube:ArrayMesh

static func mat(color:Color,metal:float=0.0,rough:float=.28)->ShaderMaterial:
	var key:=str(color)+str(metal)+str(rough)
	if materials.has(key): return materials[key]
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 paint : source_color;
uniform float metal = 0.0;
uniform float rough = 0.35;
uniform vec4 glow : source_color = vec4(0.0);
void fragment(){NORMAL=normalize(NORMAL);ALBEDO=paint.rgb;METALLIC=metal;ROUGHNESS=rough;EMISSION=glow.rgb;}
"""
	var m:=ShaderMaterial.new();m.shader=shader;m.set_shader_parameter("paint",color);m.set_shader_parameter("metal",metal);m.set_shader_parameter("rough",rough)
	materials[key]=m
	return m

static func ball(parent:Node3D,at:Vector3,scale_value:Vector3,color:Color,material:Material=null)->MeshInstance3D:
	if sphere==null:
		sphere=SphereMesh.new()
		sphere.radius=.5
		sphere.height=1
		sphere.radial_segments=20
		sphere.rings=12
	var node:=MeshInstance3D.new()
	node.mesh=sphere
	node.material_override=material if material!=null else mat(color)
	node.position=at
	node.scale=scale_value
	parent.add_child(node)
	return node

static func box(parent:Node3D,at:Vector3,size:Vector3,color:Color)->MeshInstance3D:
	if cube==null:
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for normal in [Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]:
			var u:Vector3=Vector3.UP if absf(normal.x)>.5 else Vector3.RIGHT
			# Godot front faces use clockwise winding; normals point outwards.
			var v:Vector3=u.cross(normal)
			for x in 4:
				for y in 4:
					for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
						var point:Vector3=normal*.5+u*((x+corner.x)/4-.5)+v*((y+corner.y)/4-.5)
						var inner:=point.clamp(Vector3.ONE*-.43,Vector3.ONE*.43)
						var n:Vector3=(point-inner).normalized()
						surface.set_normal(n)
						surface.add_vertex(inner+n*.07)
		cube=surface.commit()
	var node:=MeshInstance3D.new()
	node.mesh=cube
	node.material_override=mat(color)
	node.position=at
	node.scale=size
	parent.add_child(node)
	return node

static func cone(parent:Node3D,at:Vector3,radius:float,height:float,color:Color)->MeshInstance3D:
	var mesh:=CylinderMesh.new()
	mesh.top_radius=0
	mesh.bottom_radius=radius
	mesh.height=height
	mesh.radial_segments=20
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=mat(color,.2)
	node.position=at
	parent.add_child(node)
	return node

static func rainbow()->ShaderMaterial:
	if materials.has("rainbow"): return materials.rainbow
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 local;
void vertex(){local=VERTEX;}
void fragment(){
NORMAL=normalize(NORMAL);
float hue=local.x*0.45+local.y*0.85+0.45;
vec3 rainbow=0.55+0.45*cos(6.28318*(hue+vec3(0.,0.33,0.67)));
ALBEDO=rainbow;ROUGHNESS=0.31;METALLIC=0.08;RIM=0.5;
}"""
	var material:=ShaderMaterial.new()
	material.shader=shader
	materials.rainbow=material
	return material

static func ground_material(color:Color)->ShaderMaterial:
	var key:="ground"+str(color)
	if materials.has(key):return materials[key]
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode diffuse_burley;
uniform vec4 stone_color : source_color;
varying vec3 local_position;
void vertex(){local_position=VERTEX;}
void fragment(){
 NORMAL=normalize(NORMAL);
 float grain=0.994+0.006*sin(local_position.x*63.0+sin(local_position.z*47.0)*2.0);
 ALBEDO=stone_color.rgb*grain;
 ROUGHNESS=0.76; SPECULAR=0.16;
}"""
	var material:=ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("stone_color",color)
	materials[key]=material
	return material

static func character(kind:String="Minik")->Node3D:
	if kind in ["Flare","Kyra","June","Gaya","Mia","Pip","Nori","Toby","Lulu"]:return human(kind)
	var root:=Node3D.new()
	root.name=kind
	var rig:=Node3D.new()
	rig.name="Rig"
	root.add_child(rig)
	var fox:=kind=="Explorer Fox"
	var colors:Dictionary={"Flare":Color("fc7544"),"Kyra":Color("ad74ec"),"June":Color("69bcdf"),"Gaya":Color("ebaf75")}
	var base:Color=Color("ff922b") if fox else colors.get(kind,Color("4de1e8"))
	var coat:Material=rainbow() if kind=="Minik" else mat(base)
	ball(rig,Vector3(0,.55,0),Vector3(.6,.75,.5),base,coat)
	ball(rig,Vector3(0,.57,.21),Vector3(.38,.48,.11),Color("fff8ef"))
	var head:=Node3D.new()
	head.name="Head"
	head.position=Vector3(0,1.12,.06)
	rig.add_child(head)
	ball(head,Vector3.ZERO,Vector3(.85,.73,.67),base,coat)
	for side in [-1,1]:
		var ear:=cone(head,Vector3(side*.29,.38,0),.22,.5,base)
		ear.rotation.z=-side*.2
		var inside:=cone(head,Vector3(side*.29,.39,.07),.14,.33,Color("ff87b6"))
		inside.rotation.z=-side*.2
		ball(head,Vector3(side*.14,-.16,.29),Vector3(.32,.25,.18),Color("fffaf3"))
		if kind=="Minik":
			ball(head,Vector3(side*.2,.045,.31),Vector3(.4,.3,.1),Color("132b46"))
			ball(head,Vector3(side*.2,.04,.356),Vector3(.32,.23,.028),Color("173d5a"),mat(Color("163451"),.55,.13))
			ball(head,Vector3(side*.2-.06,.1,.38),Vector3(.07,.055,.013),Color("b6edff"))
		else:
			ball(head,Vector3(side*.18,.07,.3),Vector3(.25,.32,.11),Color.WHITE)
			ball(head,Vector3(side*.18,.04,.357),Vector3(.14,.22,.04),Color("422517"))
			ball(head,Vector3(side*.18-.035,.105,.385),Vector3(.05,.065,.015),Color.WHITE)
		var arm:=Node3D.new()
		arm.name="ArmL" if side<0 else "ArmR"
		arm.position=Vector3(side*.33,.79,0)
		rig.add_child(arm)
		ball(arm,Vector3(side*.015,-.16,0),Vector3(.23,.43,.24),base,coat)
		ball(arm,Vector3(side*.02,-.35,.035),Vector3(.23,.19,.25),Color("fff9ee"))
		var leg:=Node3D.new()
		leg.name="LegL" if side<0 else "LegR"
		leg.position=Vector3(side*.18,.3,0)
		rig.add_child(leg)
		ball(leg,Vector3(0,-.08,0),Vector3(.26,.31,.26),base,coat)
		ball(leg,Vector3(0,-.21,.09),Vector3(.29,.18,.38),Color("573245") if fox else Color("fbf6ff"))
	ball(head,Vector3(0,-.14,.39),Vector3(.115,.095,.07),Color("603039") if fox else Color("f85494"))
	ball(head,Vector3(0,-.28,.298),Vector3(.13,.075,.05),Color("8c385f"))
	if kind=="Minik":
		box(head,Vector3(0,.06,.345),Vector3(.14,.06,.05),Color("14283f"))
		var horn:=cone(head,Vector3(0,.53,.13),.115,.55,Color.WHITE)
		horn.material_override=rainbow()
	if fox:
		ball(head,Vector3(0,.26,-.01),Vector3(1.05,.13,.82),Color("946337"))
		ball(head,Vector3(0,.4,-.03),Vector3(.65,.32,.57),Color("b98d52"))
		ball(head,Vector3(0,.34,.34),Vector3(.18,.18,.04),Color("ffdb73"),mat(Color("efc365"),.55))
		var scarf:=cone(rig,Vector3(0,.89,.2),.24,.32,Color("329d61"))
		scarf.rotation.z=PI
		box(rig,Vector3(0,.63,-.29),Vector3(.39,.45,.15),Color("916135"))
	var tail:=Node3D.new()
	tail.name="Tail"
	tail.position=Vector3(0,.43,-.23)
	rig.add_child(tail)
	for i in 7:
		var t:=float(i)/6
		var tail_color:=Color.from_hsv(.1+t*.7,.7,1) if kind in ["Minik","Explorer Fox"] else base.lightened(t*.2)
		var diameter:=.17+sin(t*PI)*(.28 if fox else .1)
		ball(tail,Vector3(sin(t*2)*.28,t*.68,-t*.62),Vector3(diameter,diameter*1.3,diameter),Color.WHITE if fox and i>4 else tail_color)
	return root

static func human(kind:String)->Node3D:
	var root:=Node3D.new();root.name=kind;root.set_meta("jointed",true)
	var rig:=Node3D.new();rig.name="Rig";root.add_child(rig)
	var visitor:=["Pip","Nori","Toby","Lulu"].has(kind)
	var index:=maxi(0,["Pip","Nori","Toby","Lulu"].find(kind))
	var skin:Color=[Color("e8ad84"),Color("bc835f"),Color("d3a078"),Color("b77959")][index]
	var hair:Color=[Color("a56839"),Color("343c54"),Color("624832"),Color("4d2d46")][index]
	var shirt:Color=[Color("ffbc57"),Color("66d5c4"),Color("77bfff"),Color("f5a4c9")][index]
	if not visitor:
		hair={"Flare":Color("4554bb"),"Kyra":Color("4946a8"),"June":Color("b34836"),"Gaya":Color("532873")}.get(kind,hair)
		shirt={"Flare":Color("bbef42"),"Kyra":Color("66d3ff"),"June":Color("ee65da"),"Gaya":Color("c2ee32")}.get(kind,shirt)
	var navy:=Color("345575")
	ball(rig,Vector3(0,.92,0),Vector3(.56,.56,.36),shirt)
	ball(rig,Vector3(0,.63,0),Vector3(.49,.29,.36),navy)
	ball(rig,Vector3(0,1.21,0),Vector3(.17,.19,.18),skin)
	ball(rig,Vector3(.1,.96,.181),Vector3(.12,.12,.025),Color("fff3cf"))
	for side in [-1,1]:
		var arm:=Node3D.new();arm.name="ArmL" if side<0 else "ArmR";arm.position=Vector3(side*.31,1.1,0);rig.add_child(arm)
		ball(arm,Vector3(side*.015,-.07,0),Vector3(.24,.24,.25),shirt)
		ball(arm,Vector3(0,-.2,0),Vector3(.17,.25,.18),skin)
		var elbow:=Node3D.new();elbow.name="Joint";elbow.position=Vector3(0,-.3,0);arm.add_child(elbow)
		ball(elbow,Vector3(0,-.12,0),Vector3(.16,.29,.17),skin)
		ball(elbow,Vector3(0,-.27,.035),Vector3(.19,.18,.18),skin)
		var leg:=Node3D.new();leg.name="LegL" if side<0 else "LegR";leg.position=Vector3(side*.16,.61,0);rig.add_child(leg)
		ball(leg,Vector3(0,-.095,0),Vector3(.255,.27,.29),navy)
		ball(leg,Vector3(0,-.21,0),Vector3(.205,.17,.21),skin)
		var knee:=Node3D.new();knee.name="Joint";knee.position.y=-.27;leg.add_child(knee)
		ball(knee,Vector3(0,-.12,0),Vector3(.175,.28,.19),skin)
		ball(knee,Vector3(0,-.235,.005),Vector3(.19,.14,.22),Color("fff8e5"))
		ball(knee,Vector3(0,-.28,.075),Vector3(.27,.15,.4),shirt.lightened(.1))
		box(knee,Vector3(0,-.335,.07),Vector3(.27,.035,.39),Color("fff8e5"))
	var head:=Node3D.new();head.name="Head";head.position=Vector3(0,1.48,0);rig.add_child(head)
	ball(head,Vector3.ZERO,Vector3(.59,.65,.53),skin)
	ball(head,Vector3(0,.2,-.035),Vector3(.64,.37,.56),hair)
	ball(head,Vector3(0,-.06,.27),Vector3(.11,.12,.1),skin.lightened(.1))
	var mouth:=ball(head,Vector3(0,-.18,.245),Vector3(.18,.045,.045),Color("874d4b"));mouth.name="Mouth"
	for side in [-1,1]:
		ball(head,Vector3(side*.3,0,0),Vector3(.1,.17,.1),skin)
		ball(head,Vector3(side*.135,.04,.242),Vector3(.155,.15,.045),Color.WHITE)
		ball(head,Vector3(side*.135,.03,.269),Vector3(.085,.115,.025),Color("324b5b"))
		ball(head,Vector3(side*.115,.063,.285),Vector3(.027,.034,.014),Color.WHITE)
		var brow:=ball(head,Vector3(side*.135,.163,.238),Vector3(.18,.045,.045),hair);brow.rotation.z=side*.12
	var tail:=Node3D.new();tail.name="Tail";rig.add_child(tail)
	if kind in ["Lulu","Kyra","June","Gaya"]:
		for side in [-1,1]:
			for i in 3:ball(head,Vector3(side*(.26+i*.025),-.08-i*.12,-.19),Vector3(.2,.3,.2),hair.lightened(i*.05))
	else:
		for i in 4:
			var tuft:=ball(head,Vector3(-.2+i*.12,.31+sin(i)*.035,-.03),Vector3(.2,.24,.26),hair.lightened(i*.04));tuft.rotation.z=-.35
	var held:=ball(rig.get_node("ArmR/Joint"),Vector3(.04,-.3,.13),Vector3(.24,.3,.24),Color("22bdee"));held.name="Water";held.visible=false
	batch_rig(root)
	return root

static func magical_dog()->Node3D:
	var root:=Node3D.new();root.name="Lumi";root.set_meta("quadruped",true)
	var rig:=Node3D.new();rig.name="Rig";root.add_child(rig)
	var cream:=Color("fff0cd");var gold:=Color("eebf6b");var teal:=Color("55d2d0")
	ball(rig,Vector3(0,.7,-.05),Vector3(.66,.65,1.1),cream)
	ball(rig,Vector3(0,.75,.25),Vector3(.6,.68,.6),cream.lightened(.2))
	for side in [-1,1]:
		for front in [false,true]:
			var limb:=Node3D.new();limb.name=("Arm" if front else "Leg")+("L" if side<0 else "R")
			limb.position=Vector3(side*.25,.55,.34 if front else -.4);rig.add_child(limb)
			ball(limb,Vector3(0,-.14,0),Vector3(.23,.38,.24),cream)
			var joint:=Node3D.new();joint.name="Joint";joint.position.y=-.25;limb.add_child(joint)
			ball(joint,Vector3(0,-.12,.025),Vector3(.19,.27,.2),cream)
			ball(joint,Vector3(0,-.23,.11),Vector3(.3,.18,.37),Color("fff8e7"))
			for toe in [-1,0,1]:ball(joint,Vector3(toe*.075,-.225,.27),Vector3(.045,.06,.04),gold)
	var head:=Node3D.new();head.name="Head";head.position=Vector3(0,1.07,.44);rig.add_child(head)
	ball(head,Vector3.ZERO,Vector3(.76,.67,.65),cream)
	ball(head,Vector3(0,-.15,.3),Vector3(.57,.34,.4),Color("fff9eb"))
	ball(head,Vector3(0,-.08,.52),Vector3(.22,.16,.13),Color("294863"))
	ball(head,Vector3(-.055,-.04,.578),Vector3(.065,.033,.018),Color("d3efff"))
	ball(head,Vector3(0,-.27,.44),Vector3(.24,.07,.06),Color("7f5150"))
	ball(head,Vector3(0,-.315,.44),Vector3(.12,.12,.08),Color("f18eaa"))
	for side in [-1,1]:
		var ear:=Node3D.new();ear.name="EarL" if side<0 else "EarR";ear.position=Vector3(side*.36,.19,-.02);head.add_child(ear)
		ball(ear,Vector3(side*.07,-.28,-.01),Vector3(.3,.7,.28),gold)
		ball(ear,Vector3(side*.07,-.44,.015),Vector3(.22,.23,.2),teal)
		ball(head,Vector3(side*.215,.03,.274),Vector3(.22,.27,.08),Color.WHITE)
		ball(head,Vector3(side*.208,.025,.318),Vector3(.135,.19,.04),Color("326698"))
		ball(head,Vector3(side*.202,.018,.339),Vector3(.065,.13,.025),Color("172b48"))
		ball(head,Vector3(side*.18,.075,.351),Vector3(.053,.065,.012),Color.WHITE)
		var brow:=ball(head,Vector3(side*.21,.21,.27),Vector3(.23,.055,.055),gold);brow.rotation.z=side*.15
	var collar:=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=.24;ring.outer_radius=.3;ring.rings=20;ring.ring_segments=8;collar.mesh=ring;collar.material_override=mat(teal,.35);collar.position=Vector3(0,.9,.38);rig.add_child(collar)
	var star:=Node3D.new();star.name="Star";star.position=Vector3(0,.78,.62);rig.add_child(star)
	var glow:=mat(Color("ffe18b"),.45).duplicate() as ShaderMaterial;glow.set_shader_parameter("glow",Color("5b3510"))
	ball(star,Vector3.ZERO,Vector3(.15,.15,.06),Color("ffe18b"),glow)
	for i in 5:
		var angle:=i*TAU/5;var point:=cone(star,Vector3(sin(angle)*.11,cos(angle)*.11,0),.065,.16,Color("ffe18b"));point.rotation.z=-angle;point.material_override=glow
	var tail:=Node3D.new();tail.name="Tail";tail.position=Vector3(0,.78,-.52);rig.add_child(tail)
	for i in 5:ball(tail,Vector3(0,float(i)*.13,-float(i)*.09),Vector3(.19,.25,.2),teal if i==4 else cream)
	var aura:=Node3D.new();aura.name="Aura";root.add_child(aura)
	for i in 7:
		var mote:=ball(aura,Vector3(cos(i*TAU/7)*.78,.2+float(i%3)*.3,sin(i*TAU/7)*.78),Vector3.ONE*.055,Color("fff1b2"),glow);mote.name="Mote%d"%i
	batch_rig(root)
	return root

static func animate(model:Node3D,time:float,moving:bool,celebrate:bool=false)->void:
	var rig:=model.get_node("Rig") as Node3D
	var swing:=sin(time*11)*.6 if moving else sin(time*2)*.045
	for name in ["ArmL","ArmR","LegL","LegR"]:
		var limb:=rig.get_node(name) as Node3D
		limb.rotation.x=swing*(1 if name in ["ArmL","LegR"] else -1)
		limb.rotation.z=(-1 if name=="ArmR" else 1)*2.3 if celebrate and name.begins_with("Arm") else 0
	rig.position.y=absf(sin(time*(7 if celebrate else 11)))*(.3 if celebrate else (.045 if moving else 0))
	(rig.get_node("Tail") as Node3D).rotation.y=sin(time*3)*.22
	(rig.get_node("Head") as Node3D).rotation.z=sin(time*2)*.035

static func balloon(parent:Node3D,at:Vector3,water:bool=false)->Node3D:
	var root:=Node3D.new()
	parent.add_child(root)
	root.position=at
	var color:=Color("26b7f6") if water else Color("f43171")
	ball(root,Vector3(0,.85,0),Vector3(.55,.67,.55),color,mat(color,.15,.16))
	cone(root,Vector3(0,.49,0),.08,.11,color)
	var cord:=box(root,Vector3(.03,.28,0),Vector3(.018,.39,.018),Color("eec16b"))
	cord.rotation.z=.13
	return root

static func batch_static(parent:Node3D)->void:
	# Preserve exact geometry/materials while reducing hundreds of mobile draw calls.
	var groups:Dictionary={}
	for child in parent.get_children():
		if child is MeshInstance3D and child.name not in ["Mouth","Water"]:
			var key:="%d/%d"%[child.mesh.get_instance_id(),child.material_override.get_instance_id()]
			if not groups.has(key):groups[key]=[]
			groups[key].append(child)
	for group in groups.values():
		if group.size()<3:continue
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=group[0].mesh;multi.instance_count=group.size()
		var node:=MultiMeshInstance3D.new();node.multimesh=multi;node.material_override=group[0].material_override;parent.add_child(node)
		for i in group.size():multi.set_instance_transform(i,group[i].transform);group[i].queue_free()

static func decoration(parent:Node3D,at:Vector3,theme:int)->void:
	match theme:
		0,5:
			box(parent,at+Vector3(0,.35,0),Vector3(.32,.7,.32),Color("a87035"))
			var lantern:=ball(parent,at+Vector3(0,.85,0),Vector3(.5,.65,.5),Color("ffe193"))
			var glow:=mat(Color("ffe193"),.25).duplicate() as ShaderMaterial;glow.set_shader_parameter("glow",Color("594219"));lantern.material_override=glow
			cone(parent,at+Vector3(0,1.25,0),.36,.25,Color("bf833c"))
		1:
			box(parent,at+Vector3(0,.32,0),Vector3(.16,.65,.16),Color("fff0d4"))
			ball(parent,at+Vector3(0,.65,0),Vector3(.9,.34,.9),Color("f292b7"))
			for i in 3:ball(parent,at+Vector3(cos(i*TAU/3)*.23,.8,sin(i*TAU/3)*.23),Vector3(.13,.05,.13),Color("fff6d9"))
		2:
			for i in 3:
				var shard:=cone(parent,at+Vector3((i-1)*.24,.5,0),.2,.7+i*.25,Color("72ddec"));shard.rotation.z=(i-1)*.2
		3:
			for i in 3:ball(parent,at+Vector3((i-1)*.32,.3,0),Vector3(.7,.5,.6),Color("ecedff"))
		4:
			box(parent,at+Vector3(0,.4,0),Vector3(.15,.8,.15),Color("97634e"))
			for i in 3:cone(parent,at+Vector3(0,.65+i*.28,0),.55-i*.13,.6,Color("6aae87"))

static func social(model:Node3D,time:float,displacement:Vector3,dt:float,mood:String,windup:float=0.0)->void:
	var speed:=displacement.length()/maxf(dt,.001)
	var blend:float=lerpf(float(model.get_meta("gait_blend",0.0)),clampf(speed/1.2,0,1),1-exp(-dt*9))
	var phase:float=float(model.get_meta("gait_phase",0.0))+displacement.length()*TAU/1.35
	model.set_meta("gait_blend",blend);model.set_meta("gait_phase",phase)
	var rig:=model.get_node("Rig") as Node3D;var head:=rig.get_node("Head") as Node3D
	var dog:bool=model.get_meta("quadruped",false)
	for name in ["ArmL","ArmR","LegL","LegR"]:
		var limb:=rig.get_node(name) as Node3D;var arm:bool=name.begins_with("Arm")
		var p:float=phase+(0 if name in ["ArmL","LegR"] else PI)
		limb.rotation=Vector3(sin(p)*(.38 if dog else .3)*blend,0,0)
		if not dog and arm:limb.rotation.z=.09 if name=="ArmL" else -.09
		if limb.has_node("Joint"):
			var joint:=limb.get_node("Joint") as Node3D
			joint.rotation.x=(.14+maxf(0,-sin(p))*.4*blend) if arm and not dog else maxf(0,-sin(p))*.62*blend
			if joint.has_node("Water"):joint.get_node("Water").visible=mood=="throw"
	rig.position.y=absf(sin(phase))*.025*blend+sin(time*2)*.009*(1-blend)
	rig.rotation=Vector3(-.03*blend,0,sin(phase)*.025*blend)
	head.rotation=Vector3(sin(time*1.7)*.035,sin(time*.65)*.09*(1-blend),sin(time*1.3)*.025)
	var right:=rig.get_node("ArmR") as Node3D;var left:=rig.get_node("ArmL") as Node3D
	if dog:
		(rig.get_node("Tail") as Node3D).rotation.z=sin(time*(9 if mood=="wave" else 5))*.45
		for ear_name in ["EarL","EarR"]:
			var ear:=head.get_node(ear_name) as Node3D;ear.rotation.x=sin(phase+.5)*.16*blend;ear.rotation.z=sin(time*2)*.045
		if mood=="wave" and blend<.25:right.rotation.x=-.9;right.rotation.z=-.22+sin(time*4)*.18;head.rotation.z=.14
		var aura:=model.get_node("Aura") as Node3D;aura.rotation.y=time*.55
		for i in aura.get_child_count():aura.get_child(i).position.y=.25+float(i%3)*.3+sin(time*2+i)*.07
	else:
		if head.has_node("Mouth"):
			var mouth:=head.get_node("Mouth") as Node3D;mouth.scale.y=.045*(1.7+sin(time*10)*.5) if mood=="laugh" else .045
		match mood:
			"throw":
				var t:=clampf(1.0-windup/1.15,0,1);right.rotation.x=lerpf(-2.0,-.3,smoothstep(.65,1,t));right.rotation.z=-.25;right.get_node("Joint").rotation.x=-.45
			"wet":
				left.rotation.z=.35+sin(time*6)*.08;right.rotation.z=-.35-sin(time*6)*.08;head.rotation.x=.18
			"laugh":
				head.rotation.x=-.1;left.rotation.x=-.4;right.rotation.x=-.3


static func batch_rig(node:Node3D)->void:
	# Keep every moving joint and expressive mesh, batch only rigid decorations.
	for child in node.get_children():
		if child is Node3D and not child is MeshInstance3D and child.name!="Aura":batch_rig(child)
	batch_static(node)
