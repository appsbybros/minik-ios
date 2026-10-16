extends Node3D
var adventure_copy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://adventure-copy.json"))
var word_tray:HBoxContainer
var word_scroll:ScrollContainer
var tray_key:=""
var lesson_textures:Dictionary={}
var wall_letters:Array=[]
var friend_model:Node3D
var friend_badge:Label3D
var carrier_model:Node3D
var flare_models:Array[Node3D]=[]
var flare_light:OmniLight3D
var stage:MazeLevel
var run:MazeRun
var profile:MazeProfile
var words:=MazeWords.new()
var text:=MazeText.new()
var scene:Node3D
var hero:Node3D
var fox:Node3D
var bot_models:Array[Node3D]=[]
var pickup_models:Dictionary={}
var letter_models:Array[Node3D]=[]
var gate_models:Dictionary={}
var gate_text:Dictionary={}
var learning_revision:=-1
var shot_models:Array[Node3D]=[]
var camera:Camera3D
var ui:Control
var hud:Control
var menu:Control
var home_scroll:ScrollContainer
var home_more:Button
var joystick:MazeJoystick
var score_label:Label
var word_label:Label
var health_label:Label
var message_label:Label
var map_panel:Control
var map_drawing:Control
var question_row:HBoxContainer
var question_label:Label
var throw_button:Button
var map_button:Button
var paused:=true
var finished_shown:=false
var time:=0.0
var message_until:=0.0
var shown_gate:=-2
var qa:=false
var qa_level:=1
var test_mode:=false
var normal_profile:MazeProfile
var test_tools:=false
var swaying:Array[Dictionary]=[]
var swipe:=MazeSwipe.new()
var sky_material:ProceduralSkyMaterial
var theme_colors:=[Color("7258b1"),Color("e87ead"),Color("53b6cf"),Color("90a0e3"),Color("58a587"),Color("c69c55"),Color("d37568"),Color("2a80bd"),Color("76a451"),Color("c658a4")]
var sounds:Dictionary={}
var audio:AudioStreamPlayer
var rival_audio:=AudioStreamPlayer.new()
var rival_laughs:=0
var music:=preload("res://menu_music.gd").new()
var session_live:=false
var saved_at:=0.0
var map_caption:Label
var branding_texture:ImageTexture
var portrait_texture:ImageTexture
var primary_language:="en"
var platform:Object
var pending_action:Callable
var online_box:VBoxContainer
var effects:Array[Dictionary]=[]
var splash_marks:Array[Node3D]=[]
var qa_stamp:=-1
var journey:MazeJourney
var home_actions:VBoxContainer
var onboarding_mode:="child"
var onboarding_subjects:Array=[]
var onboarding_first:=false
var onboarding_language:="en"
var glue_model:MeshInstance3D
const FREE_LEVELS:=12
const PLATFORM_COPY:=["Learning settings","Report a concern","For a grown-up","More Minik apps","Remove ads","Restore purchases","Privacy policy","Privacy choices","Purchase unavailable. Please try again later.","Share your best scores","Choose 1–3 letters or numbers. Only this alias and your level bests are shared. Do not use your real name.","Use 1–3 letters or numbers.","Share","Cancel","Close"]

func _ready()->void:
	Engine.max_fps=60
	qa=OS.get_cmdline_user_args().has("--qa")
	primary_language=OS.get_locale_language()
	if Engine.has_singleton("MazeServices"):primary_language=Engine.get_singleton("MazeServices").primary_language()
	profile=MazeProfile.new("user://qa-progress.json" if qa else "user://progress.json",primary_language)
	var primary:=primary_language
	if not MazeWords.NAMES.has(profile.data.learning):profile.data.learning="en"
	text.language=str(profile.data.ui)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--locale="):text.language=arg.split("=")[1]
		if arg.begins_with("--level="):qa_level=int(arg.split("=")[1])
	if qa:
		profile.data.ui=text.language
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--mode="):profile.data.game_mode=arg.split("=")[1]
		profile.data.question_language="he" if text.language=="he" else "en"
	if Engine.has_singleton("MazeServices"):
		platform=Engine.get_singleton("MazeServices")
		test_tools=platform.test_tools_available() and not (qa and OS.get_cmdline_user_args().has("--store-capture"))
		platform.connect("test_level_selected",start_test_level)
		platform.connect("learning_settings",learning_settings)
		platform.connect("grown_up",parent_screen)
		platform.connect("ownership_changed",func(_owned):if menu!=null and menu.name=="UnlockScreen":unlock_screen())
		platform.connect("break_finished",func():if pending_action.is_valid():var action:=pending_action;pending_action=Callable();action.call())
		platform.connect("records_changed",online_records_received)
		configure_platform()
	var env:=WorldEnvironment.new();env.name="WorldLighting"
	var e:=Environment.new()
	e.background_mode=Environment.BG_SKY
	var sky:=Sky.new();sky_material=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("5d69b4");sky_material.sky_horizon_color=Color("edcce2");sky_material.ground_horizon_color=Color("bddde9");sky_material.ground_bottom_color=Color("718bb0")
	sky.sky_material=sky_material;e.sky=sky
	e.background_color=Color("a3d8f0")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color("dae7ff")
	e.ambient_light_energy=.3
	e.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.environment=e
	add_child(env)
	var sun:=DirectionalLight3D.new();sun.name="Sun"
	sun.rotation_degrees=Vector3(-52,-32,0)
	sun.light_color=Color("fff3d7")
	sun.light_energy=.6
	sun.shadow_enabled=true
	sun.light_angular_distance=3.0
	sun.directional_shadow_max_distance=42
	add_child(sun)
	camera=Camera3D.new()
	camera.fov=51
	camera.far=180
	add_child(camera)
	audio=AudioStreamPlayer.new()
	audio.volume_db=-12
	add_child(audio)
	rival_audio.stream=AudioStreamWAV.load_from_file("res://audio/rival-chirpy-laugh.wav");rival_audio.volume_db=-18;add_child(rival_audio)
	make_sounds()
	add_child(music)
	var layer:=CanvasLayer.new()
	add_child(layer)
	ui=Control.new();ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=Theme.new();ui.theme.default_font=MazeSkyUI.font()
	ui.layout_direction=Control.LAYOUT_DIRECTION_RTL if text.rtl() else Control.LAYOUT_DIRECTION_LTR
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	get_viewport().size_changed.connect(layout)
	var fixture:Dictionary={}
	# Debug QA entry only; normal player saves never read controlled test fixtures.
	if qa and FileAccess.file_exists("user://qa-actor-fixture.bin"):
		var value=FileAccess.open("user://qa-actor-fixture.bin",FileAccess.READ).get_var()
		if value is Dictionary:fixture=value
	load_level(int(fixture.get("number",qa_level if qa else int(profile.data.unlocked))),fixture,qa)
	apply_quality()
	if not qa or OS.get_cmdline_user_args().has("--home"):
		home()
		if not profile.data.mode_chosen and not qa:mode_screen(true)
	if qa:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screen="):
				match arg.split("=")[1]:
					"mode":mode_screen(true)
					"parent":parent_screen()
					"settings":settings()
					"unlock":unlock_screen()
					"map":map_panel.show()

func load_level(number:int,saved:Dictionary={},start_playing:bool=true)->void:
	if start_playing and not can_play(number):unlock_screen();return
	if scene!=null:scene.queue_free()
	scene=Node3D.new()
	add_child(scene)
	var mastery:Dictionary=saved.get("skills",profile.data.skills).duplicate();mastery["explorer_mode"]=profile.data.game_mode=="explorer"
	stage=MazeLevel.new(number,mastery,int(saved.get("layout_version",1)) if not saved.is_empty() else 6)
	swipe.reset();swaying.clear()
	run=MazeRun.new(stage,str(saved.get("language",profile.data.learning)),saved.get("adventure",{}).get("settings",MazeLessons.options(profile.data)))
	run.enemy_factor=.85+float(profile.data.skills.enemies)*.25
	if not saved.is_empty():run.restore(saved)
	session_live=start_playing;saved_at=run.age
	if start_playing:profile.data.played=true;profile.save()
	pickup_models.clear();letter_models.clear();gate_models.clear();gate_text.clear();learning_revision=-1;bot_models.clear();shot_models.clear()
	effects.clear();splash_marks.clear()
	var color:Color=theme_colors[stage.theme]
	sky_material.sky_top_color=color.darkened(.25)
	sky_material.sky_horizon_color=color.lightened(.7)
	sky_material.ground_horizon_color=color.lightened(.5)
	var floor_color:Color=[Color("829bb6"),Color("c39fba"),Color("5caeae"),Color("9baec8"),Color("7da889"),Color("c4ad77"),Color("c9a58b"),Color("71a6b9"),Color("a8b778"),Color("b7a4cb")][stage.theme]
	var bound:=float(stage.size)*MazeLevel.CELL
	MazeArt.box(scene,Vector3((bound-6)/2,-.6,(bound-6)/2),Vector3(bound+2,1.2,bound+2),color.darkened(.22))
	for c in stage.cells:
		var p:=stage.pos(c)
		var tile:=MazeArt.box(scene,p+Vector3(0,-.08,0),Vector3(5.96,.2,5.96),Color("6b9eae"))
		tile.material_override=MazeArt.ground_material(floor_color if (c.x+c.y)%2==0 else floor_color.lightened(.1))
		for side in [-1,1]:
			MazeArt.box(scene,p+Vector3(side*2.65,.04,0),Vector3(.07,.025,5.3),Color("dfc9a1"))
			MazeArt.box(scene,p+Vector3(0,.04,side*2.65),Vector3(5.3,.025,.07),Color("dfc9a1"))
		for d in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
			if d==Vector2i.RIGHT and c.x<stage.size-1:continue
			if d==Vector2i.DOWN and c.y<stage.size-1:continue
			if stage.connected(c,c+d):continue
			var at:=p+Vector3(d.x*3,.75,d.y*3)
			var size:=Vector3(.38,1.5,6.35) if d.x!=0 else Vector3(6.35,1.5,.38)
			MazeArt.box(scene,at,size,color)
			MazeArt.box(scene,at+Vector3(0,.79,0),Vector3(size.x+.12,.13,size.z+.12),color.lightened(.32))
			if (c.x+c.y)%3==0:
					MazeArt.ball(scene,at+Vector3(0,.97,0),Vector3(.26,.26,.26),Color("ffdf89"),MazeArt.mat(Color("f6c755"),.6))
		if (c.x*3+c.y)%5==0:MazeArt.decoration(scene,p+Vector3(-2.2,0,-2.2),stage.theme%6)
		if (c.x*3+c.y)%4==0:
			add_balloon(scene,p+Vector3(2.7,1.6,2.7),(c.x+c.y*stage.size+stage.number)%11,false,1.7)
	# The islands and trees are actual meshes beyond the collision boundary.
	for i in 20:
		var angle:=i*TAU/20
		var p:=Vector3((bound-6)/2+cos(angle)*(bound*.75),-.1,(bound-6)/2+sin(angle)*(bound*.75))
		if p.z<0:continue # Decorative crowns must not sit between the camera and the maze.
		MazeArt.ball(scene,p-Vector3(0,1.2,0),Vector3(7,2.5,5),Color("c3e8f3"))
		MazeArt.box(scene,p+Vector3(0,.45,0),Vector3(.16,.9,.16),Color("d3af70"))
		add_balloon(scene,p+Vector3(0,.9,0),i+stage.number,false,3.6)

	for g in stage.gates:
		var group:=Node3D.new();scene.add_child(group);gate_models[g.id]=group
		var arms:=stage.branches(g);var values:=stage.branch_values(g)
		# Identical arches, posts, number plaques and spacing for EVERY answer.
		# The common arithmetic prompt belongs to the junction, not one route.
		var prompt:=label3d(str(g.get("display_prompt",g.prompt+" = ?")),group,stage.pos(g.a)+Vector3(0,.065,0),30)
		prompt.billboard=BaseMaterial3D.BILLBOARD_DISABLED;prompt.rotation=Vector3(-PI/2,PI,0);prompt.pixel_size=.014;prompt.width=330;prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;prompt.outline_size=5;prompt.pixel_size=minf(.014,4.5/maxf(38,ceilf(prompt.text.length()/24.0)*38))
		prompt.text_direction=TextServer.DIRECTION_LTR if g.get("lesson","math")=="math" else TextServer.DIRECTION_AUTO
		gate_text[g.id]={"prompt":prompt,"answers":[],"picture":null}
		if not str(g.get("picture","")).is_empty():
			var picture:=Sprite3D.new();picture.texture=learning_texture(g.picture);picture.pixel_size=1.8/maxi(1,picture.texture.get_height());picture.position=stage.pos(g.a)+Vector3(0,.08,1.3);picture.rotation=Vector3(-PI/2,PI,0);picture.billboard=BaseMaterial3D.BILLBOARD_DISABLED;group.add_child(picture);gate_text[g.id].picture=picture
		for i in arms.size():
			var root:=Node3D.new();group.add_child(root)
			root.position=(stage.pos(g.a)+stage.pos(arms[i]))/2
			root.rotation.y=PI/2 if g.a.x!=arms[i].x else 0
			for side in [-1,1]:
				MazeArt.box(root,Vector3(side*2.15,1.1,0),Vector3(.28,2.2,.35),Color("f4c56a"))
				MazeArt.ball(root,Vector3(side*2.15,2.35,0),Vector3(.45,.45,.45),Color("fff3bb"))
			MazeArt.box(root,Vector3(0,2.3,0),Vector3(4.5,.26,.35),Color("e8b25b"))
			var answer_sign:=label3d(str(g.display_prompt) if g.get("lesson","")=="wall" else MazeLessons.answer_text(g,int(values[i])),root,Vector3(0,3.0,0),30)
			gate_text[g.id].answers.append(answer_sign)
			answer_sign.text_direction=TextServer.DIRECTION_AUTO;answer_sign.width=210;answer_sign.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;answer_sign.pixel_size=minf(.018,1.5/maxf(36,ceilf(answer_sign.text.length()/12.0)*36))
			if not g.get("walk_choice",false):
				var door:=MazeArt.box(root,Vector3(0,1,0),Vector3(4,1.9,.12),color.lightened(.35));door.name="Door"
	for p in stage.pickups:
		var root:Node3D
		if p.kind in ["balloon","water"]:root=MazeArt.balloon(scene,stage.pos(p.cell)+p.offset,true) if p.kind=="water" else add_balloon(scene,stage.pos(p.cell)+p.offset,int(str(p.id).hash())%11,false,1.0)
		else:
			root=Node3D.new();scene.add_child(root);root.position=stage.pos(p.cell)+p.offset
			MazeArt.box(root,Vector3(0,.6,0),Vector3(.7,.07,.55),Color("ffe6a4"))
			label3d("✧",root,Vector3(0,1,0),40)
		pickup_models[p.id]=root
	for l in run.letters:
		var root:=Node3D.new();scene.add_child(root);root.position=l.at
		MazeArt.box(root,Vector3(0,.58,0),Vector3(.7,.7,.7),Color.from_hsv(float(l.index)/run.units.size(),.4,.96))
		label3d(str(l.unit),root,Vector3(0,1.2,0),54)
		letter_models.append(root)
	for c in stage.exits:
		var root:=Node3D.new();scene.add_child(root);root.position=stage.pos(c)
		for side in [-1,1]:MazeArt.cone(root,Vector3(side*1.2,1.2,0),.32,2.4,Color("ffdc77"))
		var ring:=TorusMesh.new();ring.inner_radius=1.0;ring.outer_radius=1.23;ring.rings=24;ring.ring_segments=12
		var arch:=MeshInstance3D.new();arch.mesh=ring;arch.material_override=MazeArt.mat(Color("f9dc82"),.7);arch.position.y=1.3;arch.rotation.x=PI/2;root.add_child(arch)
		for i in 2:
			add_balloon(root,Vector3(-1.85 if i==0 else 1.85,2.3,.15),(stage.number+i*2)%6,true,2.0)
	hero=MazeArt.character();scene.add_child(hero)
	for i in 3:
		var mark:=Node3D.new();hero.get_node("Rig").add_child(mark);mark.position=Vector3((i-1)*.13,.65+i*.1,-.245)
		for j in 5:MazeArt.ball(mark,Vector3(cos(j*TAU/5)*.06,sin(j*TAU/5)*.06,0),Vector3(.12,.12,.04),[Color("2fc5ff"),Color("f06dbe"),Color("bb8cff")][i])
		splash_marks.append(mark)
	for b in run.bots:
		var model:=MazeArt.character(str(b.name));scene.add_child(model);bot_models.append(model)
	fox=MazeArt.character("Explorer Fox");scene.add_child(fox);fox.visible=stage.race
	glue_model=MazeArt.ball(scene,Vector3.ZERO,Vector3(2.2,.12,2.2),Color("fc70c2"));glue_model.visible=false
	setup_adventure_models()
	MazeArt.batch_static(scene)
	camera.position=run.at+Vector3(0,10,-8)
	camera.look_at(run.at+Vector3(0,0,2))
	finished_shown=false;paused=false;shown_gate=-2
	make_hud()
	if number==1:message(text.t("Drag anywhere in the maze to move, or use the circle."),12)
	elif number==3:message(text.t("Follow the answer into its path. You can always turn back."),12)
	elif stage.race:message(text.t("Race to the exit! The fox can choose wrong answers too. Think before following!"),10)
	if start_playing and saved.is_empty():adventure_intro()

func label3d(value:String,parent:Node3D,at:Vector3,font_size:int)->Label3D:
	var label:=Label3D.new();label.text=value;label.position=at;label.font_size=font_size;label.pixel_size=.018
	label.modulate=Color("183754");label.outline_modulate=Color("fff7e8");label.outline_size=9
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=false
	parent.add_child(label);return label

func _physics_process(dt:float)->void:
	if is_instance_valid(home_more) and is_instance_valid(home_scroll):
		var bar:=home_scroll.get_v_scroll_bar()
		var more:=bar.value+bar.page<bar.max_value-2
		home_more.modulate.a=1.0 if more else 0.0;home_more.disabled=not more
		home_more.mouse_filter=Control.MOUSE_FILTER_STOP if more else Control.MOUSE_FILTER_IGNORE
	time+=dt
	if paused or not profile.data.sound or not music.foreground or not music.focused:rival_audio.stop()
	music.update_music(dt,paused and menu!=null,bool(profile.data.sound),pending_action.is_valid())
	if run==null:return
	var direction:=Vector2.ZERO
	if not paused:
		if joystick!=null:direction=joystick.vector if joystick.vector.length()>.01 else swipe.vector
		if (Input.is_physical_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_LEFT)) or (Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_A)):direction.x-=1
		if (Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_RIGHT)) or (Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_D)):direction.x+=1
		if (Input.is_physical_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_UP)) or (Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_W)):direction.y-=1
		if (Input.is_physical_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_DOWN)) or (Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_S)):direction.y+=1
		var right:=camera.global_basis.x
		var back:=camera.global_basis.z;back.y=0;back=back.normalized()
		var movement:=right*direction.x+back*direction.y
		direction=Vector2(movement.x,movement.z)
		for g in stage.gates:
			if run.at.distance_to(stage.pos(g.a))<18 and camera.is_position_in_frustum(stage.pos(g.a)+Vector3(0,1,0)):MazeLearning.mark_seen(run,int(g.id))
		run.step(dt,direction)
		if not run.learning.is_empty() and int(run.learning.revision)!=learning_revision:
			learning_revision=int(run.learning.revision);refresh_question_art()
			if session_live:profile.checkpoint(run)
		if session_live and run.age-saved_at>=3:
			profile.checkpoint(run);saved_at=run.age
	hero.position=run.adventure.hero_position() if run.adventure!=null else run.at
	if direction.length()>.1:hero.rotation.y=lerp_angle(hero.rotation.y,atan2(direction.x,direction.y),1-exp(-dt*12))
	MazeArt.animate(hero,time,direction.length()>.1,run.state=="won")
	if run.hits>0:hero.scale=Vector3.ONE*(1+sin(time*14)*.025 if run.invulnerable>0 else 1)
	for i in splash_marks.size():splash_marks[i].visible=i<run.hits
	for i in run.bots.size():
		var b:Dictionary=run.bots[i];var model:=bot_models[i]
		var before:=model.position;model.position=b.at;model.visible=true if run.adventure!=null else b.away<=0
		var movement:Vector3=b.at-before
		if movement.length()>.001:model.rotation.y=lerp_angle(model.rotation.y,atan2(movement.x,movement.z),1-exp(-dt*6))
		if run.adventure!=null and b.mood in ["throw","laugh"]:
			var look:Vector3=run.at-b.at;model.rotation.y=lerp_angle(model.rotation.y,atan2(look.x,look.z),1-exp(-dt*8))
		if run.adventure!=null:MazeArt.social(model,time+float(i),movement,dt,str(b.mood),float(b.windup))
		else:MazeArt.animate(model,time,movement.length()>.001)
	if stage.race:
		var difference:=run.fox_at-fox.position
		fox.position=run.fox_at
		if difference.length()>.001:fox.rotation.y=atan2(difference.x,difference.z)
		MazeArt.animate(fox,time,run.fox_wait<=0)
	for id in pickup_models:
		var model:Node3D=pickup_models[id];model.visible=not run.collected.has(id)
		model.position.y=sin(time*2+float(str(id).hash()%11))*.12
	for i in letter_models.size():
		letter_models[i].visible=not run.letters[i].picked if run.adventure!=null else i>=run.next_letter
		letter_models[i].rotation.y=sin(time*.8+i)*.1
	for id in gate_models:
		for arch in gate_models[id].get_children():
			if arch.has_node("Door"):
				var door:=arch.get_node("Door") as Node3D
				door.scale.y=lerpf(door.scale.y,.02 if run.solved.has(id) else 1.0,1-exp(-dt*5))
	for item in swaying:
		# Pivot at the tied end. Individual phase/strength creates a gentle breeze.
		var pivot:Node3D=item.pivot
		var breeze:=sin(time*.85+item.phase)*.065+sin(time*1.37+item.phase)*.023
		pivot.rotation.z=breeze*(.45 if profile.data.comfort else 1.0)
		pivot.rotation.x=cos(time*.63+item.phase)*.035
	while shot_models.size()<run.shots.size():
		var model:=Node3D.new();scene.add_child(model);MazeArt.ball(model,Vector3.ZERO,Vector3(.3,.36,.3),Color("47c2ee"));shot_models.append(model)
	for i in shot_models.size():
		shot_models[i].visible=i<run.shots.size()
		if i<run.shots.size():shot_models[i].position=run.shots[i].at+Vector3(0,sin(clampf((2.0 if not run.shots[i].enemy else 6.0)-run.shots[i].life,0,1)*PI)*.45,0)
	for effect in effects:
		effect.life-=dt
		effect.node.position+=effect.velocity*dt
		effect.velocity.y-=dt*2.3
		effect.node.scale=Vector3.ONE*clampf(effect.life,.02,1)
		if effect.life<=0:effect.node.queue_free()
	effects=effects.filter(func(effect):return effect.life>0)
	if not paused or menu==null:
		camera.keep_aspect=Camera3D.KEEP_WIDTH if get_viewport().get_visible_rect().size.x<get_viewport().get_visible_rect().size.y else Camera3D.KEEP_HEIGHT
		var offset:=Vector3(0,10,-8)
		if get_viewport().get_visible_rect().size.x<get_viewport().get_visible_rect().size.y:offset=Vector3(0,12,-8)
		var target:=hero.position+offset
		camera.position=camera.position.lerp(target,1-exp(-dt*(8 if profile.data.comfort else 5)))
		camera.look_at(hero.position+Vector3(0,0,4))
	if is_instance_valid(glue_model):
		glue_model.visible=run.glue_left>0;glue_model.position=run.glue_anchor+Vector3(0,.08,0);glue_model.scale=Vector3(2.2+sin(time*5)*.13,.12,2.2+cos(time*4)*.13)
		if glue_model.visible:glue_model.material_override=MazeArt.mat(Color.from_hsv(fmod(run.glue_cycle*.23,.99),.62,.98))
	animate_adventure(dt)
	update_hud()
	while not run.events.is_empty():
		var event:Dictionary=run.events.pop_front()
		play_sound(str(event.kind))
		match event.kind:
			"balloon","water","letter":burst(run.at+Vector3(0,.9,0),8,Color("ffda85"))
			"splash":burst(event.get("at",run.at)+Vector3(0,.9,0),14,Color("55cfff"))
			"won":burst(run.at+Vector3(0,2,0),36,Color("ffdf77"))
			"letter_wrong":message(lesson_copy("That letter is red. Tap it in your tray to put it back."),6)
			"letter_removed":message(lesson_copy("Try another letter. You can collect this one again."),3)
			"flare_reward":message(lesson_copy("Your word earned a flare! Find more glowing flares along the path."),6)
			"flare":message(lesson_copy("More light!"),3)
			"friend_coming":message(lesson_copy(str(event.name))+": "+lesson_copy("I'm coming to help!"),5)
			"friend_follow":message(lesson_copy(str(event.name))+": "+lesson_copy("Come with me!"),8)
			"friend_gift":message(lesson_copy(str(event.name))+": "+lesson_copy("A gift for you!")+" "+lesson_copy(str(event.gift)),5)
			"friend_gate":message(lesson_copy("Here is the next gate. You can do it!"),5)
			"rescue":message(lesson_copy("Friends are coming. Follow their wave to a clear path!"),8)
			"carrier_warning":message(lesson_copy("Balloon Minik! Run away or tap your balloon to splash him."),6)
			"carrier_ride":message(lesson_copy("Up we go! Your letters and points are safe."),4)
			"carrier_drop":message(lesson_copy("Back on the path. Keep exploring!"),4)
			"next_letter":message(text.t("Find {0} next",str(event.unit)))
			"word":message(text.t("A word! You earned a map peek."),5)
			"try_again":message(text.t("Not quite. Try the other answer."))
			"warning":message(text.t("Look out — water balloon!"),2)
			"correct":message("✓ "+text.t("Keep exploring!"),2)
			"hit":animate_lost_heart();message(text.t("Health")+": "+str(3-run.hits)+" / 3")
			"glued":message(text.t("Sticky gate! The glue melts in 5 seconds."),5)
	if run.state!="playing" and not finished_shown:
		finished_shown=true
		var difference:=profile.finish(run)
		get_tree().create_timer(.9).timeout.connect(func():result(difference))
	if (qa or test_mode) and int(time*10)!=qa_stamp:qa_stamp=int(time*10);write_qa()

func style(color:Color,border:Color=Color("b2dfff"))->StyleBox:
	return MazeSkyUI.surface(MazeSkyUI.palette(color))
func label(value:String,font_size:int=26)->Label:
	var l:=Label.new();l.text=value;l.add_theme_color_override("font_color",Color("233b5c"));l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_font_override("font",MazeSkyUI.font(font_size>=28))
	l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return l
func button(value:String,action:Callable,color:Color=Color("a6dcff"))->Button:
	var b:=Button.new();b.text=value;b.custom_minimum_size=Vector2(0,72);b.add_theme_font_size_override("font_size",28)
	b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	MazeSkyUI.dress(b,MazeSkyUI.PINK if color==MazeSkyUI.PINK else MazeSkyUI.palette(color))
	b.pressed.connect(action);b.focus_mode=Control.FOCUS_ALL
	return b
func panel_box(parent:Control)->VBoxContainer:
	var panel:=PanelContainer.new();panel.name="Surface";panel.add_theme_stylebox_override("panel",MazeSkyUI.surface(MazeSkyUI.BLUE,false,true));parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll:=ScrollContainer.new();panel.add_child(scroll)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",18);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(box)
	return box
func menu_section(parent:VBoxContainer,title:String,expanded:bool,color:Color)->VBoxContainer:
	var frame:=PanelContainer.new();frame.mouse_filter=Control.MOUSE_FILTER_PASS;frame.add_theme_stylebox_override("panel",MazeSkyUI.surface(color.lightened(.65)));parent.add_child(frame)
	var column:=VBoxContainer.new();frame.add_child(column)
	var header_margin:=MarginContainer.new();header_margin.add_theme_constant_override("margin_left",4);header_margin.add_theme_constant_override("margin_right",4);column.add_child(header_margin)
	var header:=HBoxContainer.new();header_margin.add_child(header)
	var caption:=label(text.t(title),24);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT;caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;caption.add_theme_color_override("font_color",MazeSkyUI.INK);caption.size_flags_vertical=Control.SIZE_SHRINK_CENTER;header.add_child(caption)
	var content:=VBoxContainer.new();content.add_theme_constant_override("separation",10);content.visible=expanded
	var toggle:=Button.new();MazeSkyUI.compact(toggle);toggle.text="−" if expanded else "+";toggle.custom_minimum_size=Vector2(48,48);toggle.add_theme_font_size_override("font_size",28);toggle.size_flags_vertical=Control.SIZE_SHRINK_CENTER;header.add_child(toggle)
	toggle.pressed.connect(func():content.visible=not content.visible;toggle.text="−" if content.visible else "+")
	column.add_child(content);return content

func clear_menu()->void:
	home_scroll=null;home_more=null
	if menu!=null:menu.queue_free();menu=null
func screen()->VBoxContainer:
	clear_menu();paused=true
	menu=Control.new();ui.add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MazeSkyUI.backdrop(menu)
	var container:=Control.new();container.name="Card";menu.add_child(container)
	var box:=panel_box(container)
	layout()
	return box
func home()->void:
	if session_live and run.state=="playing":profile.checkpoint(run)
	var box:=screen();menu.name="HomeScreen"
	box.add_child(label("מיניק במבוך" if text.language=="he" else "MINIK MAZE",36))
	journey=MazeJourney.new();journey.name="Journey";journey.current=int(profile.data.unlocked);journey.bests=profile.data.bests;journey.custom_minimum_size=Vector2(0,230);box.add_child(journey)
	journey.selected.connect(func(id):clear_menu();load_level(id))
	journey.expanded.connect(func():journey_screen())
	home_actions=VBoxContainer.new();home_actions.add_theme_constant_override("separation",12);box.add_child(home_actions)
	home_actions.add_child(button(text.t("Continue adventure" if profile.data.played else "Explore"),continue_adventure,MazeSkyUI.PINK))
	home_actions.add_child(button(text.t("Help"),help_screen,MazeSkyUI.BLUE))
	var adult:=button(text.t("For a grown-up"),func():
		if platform!=null:platform.parent_menu()
		else:parent_screen(),MazeSkyUI.GOLD)
	home_actions.add_child(adult)
	box.add_child(label(text.t("First 12 levels free. One purchase unlocks the full adventure. No ads."),18))
	box.add_child(label(lesson_copy("Questions and answers were created with AI. AI can make mistakes."),16))
	layout()
func continue_adventure()->void:
	var saved:=profile.active_run()
	if not saved.is_empty() and int(saved.get("layout_version",0)) in [5,6]:
		clear_menu();load_level(int(saved.number),saved)
	else:clear_menu();load_level(int(profile.data.unlocked))

func levels()->void:
	journey_screen()
func journey_screen(first:int=0)->void:
	var box:=screen();menu.name="JourneyScreen";box.add_child(label(text.t("Levels"),34))
	var view:=MazeJourney.new();view.current=int(profile.data.unlocked);view.bests=profile.data.bests;view.first=first;view.custom_minimum_size.y=310;box.add_child(view)
	view.selected.connect(func(id):clear_menu();load_level(id))
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",18);box.add_child(row)
	var start:=maxi(1,view.current-1) if first==0 else first
	var previous:=button("‹",func():journey_screen(maxi(1,start-7)));previous.disabled=start<=1;row.add_child(previous)
	var next:=button("›",func():journey_screen(mini(99,start+7)));next.disabled=start+8>100;row.add_child(next)
	box.add_child(button(text.t("Back"),home,MazeSkyUI.PINK))

func settings()->void:
	var box:=screen();box.add_child(label(text.t("Settings"),32))
	for pair in [["sound","Sound"],["comfort","Gentle camera"],["large_controls","Large controls"]]:
		var toggle:=CheckButton.new();toggle.text=text.t(pair[1]);toggle.button_pressed=bool(profile.data[pair[0]]);toggle.custom_minimum_size.y=60;toggle.add_theme_color_override("font_color",Color("263b59"));toggle.add_theme_font_size_override("font_size",24)
		for key in ["font_pressed_color","font_hover_pressed_color","font_hover_color","font_focus_color"]:toggle.add_theme_color_override(key,Color("263b59"))
		MazeSkyUI.toggle(toggle)
		toggle.toggled.connect(func(on):profile.data[pair[0]]=on;profile.save();layout());box.add_child(toggle)
		box.add_child(label(text.t({"sound":"Music and game sound effects.","comfort":"Steadier camera tracking and less decorative motion.","large_controls":"Enlarges the movement circle and in-game Map and Back buttons."}[pair[0]]),20))
	for pair in [["ui","Interface language"]]:
		box.add_child(label(text.t(pair[1]),23))
		var select:=OptionButton.new();select.custom_minimum_size.y=60;select.add_theme_font_size_override("font_size",24)
		style_select(select)
		var choices:Array=MazeWords.NAMES.keys()
		for lang in choices:select.add_item(MazeWords.NAMES[lang])
		select.select(maxi(0,choices.find(profile.data[pair[0]])))
		select.item_selected.connect(func(index):profile.data[pair[0]]=choices[index];profile.save();text.language=str(profile.data.ui);ui.layout_direction=Control.LAYOUT_DIRECTION_RTL if text.rtl() else Control.LAYOUT_DIRECTION_LTR;configure_platform();settings())
		box.add_child(select)
	box.add_child(label(text.t("Graphics"),23))
	var quality:=OptionButton.new();quality.custom_minimum_size.y=60;quality.add_theme_font_size_override("font_size",24)
	style_select(quality)
	for title in ["Battery friendly","Balanced","High quality"]:quality.add_item(text.t(title))
	var modes:=["battery","balanced","high"];quality.select(maxi(0,modes.find(profile.data.quality)))
	quality.item_selected.connect(func(index):profile.data.quality=modes[index];profile.save();apply_quality());box.add_child(quality)
	box.add_child(label(text.t("Battery friendly: fewer effects. High quality: smoother edges and shadows."),20))
	box.add_child(button(text.t("Back"),parent_screen))
func style_select(select:OptionButton)->void:
	MazeSkyUI.dress(select)
	var popup:=select.get_popup();popup.add_theme_stylebox_override("panel",MazeSkyUI.surface(MazeSkyUI.BLUE,false,true))
	popup.add_theme_font_override("font",MazeSkyUI.font(true));popup.add_theme_font_size_override("font_size",25)
	popup.add_theme_constant_override("v_separation",18)
	popup.add_theme_color_override("font_color",MazeSkyUI.INK);popup.add_theme_color_override("font_hover_color",MazeSkyUI.INK)
	popup.add_theme_stylebox_override("hover",MazeSkyUI.surface(MazeSkyUI.GOLD))

func apply_quality()->void:
	var quality:String=str(profile.data.quality)
	Engine.max_fps=45 if quality=="battery" else 60
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED if quality=="battery" else (Viewport.MSAA_4X if quality=="high" else Viewport.MSAA_2X)
	(get_node("Sun") as DirectionalLight3D).shadow_enabled=quality!="battery"

func records()->void:
	var box:=screen();box.add_child(label(text.t("Offline personal records"),30));box.add_child(label(text.t("Total")+"  "+str(profile.total()),36))
	menu.name="RecordsScreen"
	# iOS (Maze/README.md): the online records stay on Android; the iOS services have no load_records.
	if platform!=null and not test_mode and platform.has_method("load_records"):
		box.add_child(button(text.t("Online records"),func():platform.load_records();online_records_received("{\"loading\":true}")))
		box.add_child(button(text.t("Share your best scores"),func():platform.publish_records(JSON.stringify(profile.data.bests))))
		box.add_child(button(text.t("Remove my online record"),func():platform.remove_online_record()))
		box.add_child(button(text.t("Report a concern"),func():platform.report_concern()))
		online_box=VBoxContainer.new();box.add_child(online_box)
	if profile.data.bests.is_empty():box.add_child(label(text.t("Finish a level to save your best score.")))
	for id in range(1,101):
		if profile.data.bests.has(str(id)):box.add_child(label(text.t("Level")+" "+str(id)+"   ·   "+str(profile.data.bests[str(id)]),24))
	box.add_child(button(text.t("Back"),parent_screen))
func help_screen()->void:
	var box:=screen();box.add_child(label(text.t("Help"),32))
	box.add_child(label(text.t("Explore the maze. Read the question on each square and walk through the answer you choose."),25))
	box.add_child(label(text.t("A wrong answer traps you in colorful glue for 5 seconds and costs one life. The rival keeps exploring!" if profile.data.game_mode=="child" else "Find your own route. Wrong answers lead to dead ends; turn around and try another path."),25))
	box.add_child(label(text.t("Try again starts this level from the beginning. In a race, both players restart together."),25))
	box.add_child(label(lesson_copy("Drag the circle to move. When it becomes a balloon, tap its centre to throw."),25))
	box.add_child(label(lesson_copy("Lumi is a magical dog. Walk towards his wave to accept help, or go your own way."),25))
	box.add_child(button(text.t("Back"),home))

func pause_screen()->void:
	swipe.reset()
	if session_live:profile.checkpoint(run)
	var box:=screen();box.add_child(label(text.t("Adventure menu"),36));box.add_child(button(text.t("Help"),gate_help));box.add_child(button(text.t("Resume"),func():clear_menu();paused=false));box.add_child(button(text.t("Try again"),func():clear_menu();load_level(stage.number)));box.add_child(button(text.t("Home"),home))
	if test_tools:box.add_child(button(test_copy("Test another level","בדיקת שלב אחר"),func():platform.choose_test_level(stage.number,text.language)))
	if test_mode:box.add_child(button(test_copy("Return to normal play","חזרה למשחק הרגיל"),leave_test_mode))
func result(difference:int)->void:
	var box:=screen();var won:=run.state=="won"
	box.add_child(label(text.t("Adventure complete!" if won else "Let's try another path!"),34))
	if won:
		box.add_child(label(str(run.provisional)+" ★",48));box.add_child(label(text.t("Points banked")+" +"+str(difference),25))
		box.add_child(button(text.t("Next adventure"),func():after_break(func():clear_menu();load_level(mini(100,stage.number+1))),Color("ffda80")))
	else:
		box.add_child(label(text.t("No points lost from earlier levels."),24))
		box.add_child(label(text.t("Try again starts this level from the beginning. In a race, both players restart together."),24))
	box.add_child(button(text.t("Try again"),func():after_break(func():clear_menu();load_level(stage.number))));box.add_child(button(text.t("Home"),func():after_break(home)))

func configure_platform()->void:
	if platform==null:return
	var copy:Dictionary={}
	for key in PLATFORM_COPY:copy[key]=lesson_copy(key) if key=="Learning settings" else text.t(key)
	platform.configure(text.language,JSON.stringify(copy))

func burst(at:Vector3,count:int,color:Color)->void:
	if profile.data.comfort:count=mini(count,5)
	for i in count:
		var node:=Node3D.new();scene.add_child(node);node.position=at
		MazeArt.ball(node,Vector3.ZERO,Vector3(.08,.1,.06),color if i%3 else Color("ed84c7"))
		var angle:=i*TAU/count
		effects.append({"node":node,"velocity":Vector3(cos(angle)*1.4,1.3+float(i%4)*.4,sin(angle)*1.4),"life":1.2})

func after_break(action:Callable)->void:
	if pending_action.is_valid():return
	if platform==null or test_mode or qa:action.call();return
	pending_action=action
	platform.result_break(run.attempt_id,run.age)

func online_records_received(raw:String)->void:
	if menu==null or menu.name!="RecordsScreen" or not is_instance_valid(online_box):return
	for child in online_box.get_children():child.queue_free()
	var payload=JSON.parse_string(raw)
	if not payload is Dictionary:return
	if payload.get("loading",false):online_box.add_child(label(text.t("Loading…")));return
	if payload.get("error",false):online_box.add_child(label(text.t("Offline. Your personal records are safe.")));return
	var rows:Array=payload.get("rows",[])
	if rows.is_empty():online_box.add_child(label(text.t("No scores yet.")))
	for i in rows.size():online_box.add_child(label("%d.  %s   ·   %d"%[i+1,str(rows[i].alias),int(rows[i].total)],24))

func make_hud()->void:
	if hud!=null:hud.queue_free()
	hud=Control.new();hud.layout_direction=Control.LAYOUT_DIRECTION_LTR;hud.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.add_child(hud)
	var top:=PanelContainer.new();top.name="Top";top.add_theme_stylebox_override("panel",style(Color(.97,.99,1,.92)));hud.add_child(top)
	var row:=HBoxContainer.new();row.layout_direction=ui.layout_direction;row.add_theme_constant_override("separation",12);top.add_child(row)
	var pause:=button("→" if text.rtl() else "←",pause_screen,MazeSkyUI.PINK);pause.name="Back";pause.custom_minimum_size=Vector2(76,76);row.add_child(pause)
	score_label=label("",28);score_label.autowrap_mode=TextServer.AUTOWRAP_OFF;score_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(score_label)
	health_label=label("",28);health_label.autowrap_mode=TextServer.AUTOWRAP_OFF;health_label.custom_minimum_size.x=110;row.add_child(health_label)
	word_label=label("",26);word_label.name="Word";word_label.add_theme_stylebox_override("normal",style(Color(.98,.98,1,.95)));hud.add_child(word_label)
	word_scroll=ScrollContainer.new();word_scroll.name="WordTray";word_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;hud.add_child(word_scroll)
	word_tray=HBoxContainer.new();word_tray.add_theme_constant_override("separation",8);word_scroll.add_child(word_tray);tray_key=""
	message_label=label("",24);message_label.name="Message";message_label.add_theme_stylebox_override("normal",style(Color(.98,.96,.87,.96)));hud.add_child(message_label)
	joystick=MazeJoystick.new();joystick.name="Joystick";joystick.throw_requested.connect(func():run.throw_water());hud.add_child(joystick)
	throw_button=button(text.t("Throw"),func():run.throw_water(),Color("8be1f1"));throw_button.name="Throw";throw_button.visible=false;hud.add_child(throw_button)
	map_button=button(text.t("Map"),toggle_map,MazeSkyUI.BLUE);map_button.name="MapButton";hud.add_child(map_button)
	var q:=VBoxContainer.new();q.name="Question";q.add_theme_constant_override("separation",18);hud.add_child(q)
	question_label=label("",32);q.add_child(question_label)
	question_label.text_direction=Control.TEXT_DIRECTION_LTR
	question_label.add_theme_stylebox_override("normal",style(Color(.98,.96,.87,.96)))
	question_row=HBoxContainer.new();question_row.alignment=BoxContainer.ALIGNMENT_CENTER;question_row.add_theme_constant_override("separation",20);q.add_child(question_row)
	q.minimum_size_changed.connect(layout_question)
	map_panel=PanelContainer.new();map_panel.name="MapPanel";map_panel.visible=false;map_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var glass:=StyleBoxFlat.new();glass.bg_color=Color(.88,.96,1,.30);glass.set_corner_radius_all(20);glass.set_content_margin_all(14);glass.border_color=Color(1,1,1,.4);glass.set_border_width_all(1);map_panel.add_theme_stylebox_override("panel",glass);hud.add_child(map_panel)
	var map_box:=VBoxContainer.new();map_box.mouse_filter=Control.MOUSE_FILTER_IGNORE;map_panel.add_child(map_box)
	var heading:=HBoxContainer.new();heading.mouse_filter=Control.MOUSE_FILTER_IGNORE;map_box.add_child(heading)
	var title:=label(text.t("Map"),28);title.autowrap_mode=TextServer.AUTOWRAP_OFF;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.mouse_filter=Control.MOUSE_FILTER_IGNORE;heading.add_child(title)
	var close:=TextureButton.new();close.name="CloseMap";close.texture_normal=ImageTexture.create_from_image(Image.load_from_file("res://art/ui/minik_close_button.webp"));close.ignore_texture_size=true;close.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED;close.custom_minimum_size=Vector2(52,52);close.pressed.connect(func():map_panel.visible=false);heading.add_child(close)
	map_drawing=Control.new();map_drawing.mouse_filter=Control.MOUSE_FILTER_IGNORE;map_drawing.custom_minimum_size=Vector2(240,210);map_drawing.draw.connect(draw_map);map_box.add_child(map_drawing)
	map_caption=label("",22);map_caption.visible=false;map_box.add_child(map_caption)
	layout()
func update_hud()->void:
	if hud==null:return
	hud.visible=menu==null
	score_label.text=(test_copy("TEST · ","בדיקה · ") if test_mode else "")+text.t("Level")+" "+str(stage.number)+"   ★ "+str(run.provisional)+( "   ◷ "+str(ceili(stage.timer-run.age)) if stage.timer>0 else "")
	health_label.text=text.t("Health")+"\n"+"♥".repeat(maxi(0,3-run.hits))+"♡".repeat(mini(3,run.hits))
	if run.glue_left>0:health_label.text+="  "+str(ceili(run.glue_left))+"s"
	var built:="".join(run.units.slice(0,run.next_letter))
	word_label.text=built+"  ·  "+"".join(run.units) if stage.number>=2 and not run.units.is_empty() else ""
	if run.adventure!=null:
		word_scroll.visible=not run.letters.is_empty()
		word_label.text=(lesson_copy("Your word")+": "+"".join(run.units)) if not run.letters.is_empty() else ""
		if run.adventure.kind=="night":word_label.text+="   ✦ "+str(ceili(run.adventure.flash_left))+" s"
		word_label.add_theme_color_override("font_color",Color("167148") if run.adventure.complete else Color("233b5c"));update_word_tray()
	joystick.set_ammo(run.ammo)
	throw_button.text=text.t("Throw")+"  "+str(run.ammo);throw_button.disabled=run.ammo==0
	map_button.text=text.t("Map")
	map_button.modulate=Color.WHITE
	map_caption.text=(str(ceili(run.hint_left))+" s") if run.hint_left>0 else (text.t("Hint")+" × "+str(run.hint_tokens))
	message_label.visible=time<message_until
	layout_learning_hud()
	var g:=run.nearby_gate()
	var id: int=int(g.get("id",-1))
	if id!=shown_gate:
		shown_gate=id
		for child in question_row.get_children():question_row.remove_child(child);child.queue_free()
		question_label.visible=not g.is_empty()
		question_label.text="" if g.is_empty() else lesson_prompt(g)
		question_label.text_direction=Control.TEXT_DIRECTION_LTR if g.get("lesson","math")=="math" else Control.TEXT_DIRECTION_AUTO
		if not g.is_empty() and g.get("lesson","")=="wall":
			question_row.add_child(button(lesson_copy("Open the word wall"),open_word_wall,Color("b8d9ff")))
		elif not g.is_empty() and not g.get("walk_choice",false):
			for answer_value in g.choices:
				var value:int=answer_value
				var b:=button(MazeLessons.answer_text(g,value),func():run.answer(id,value),Color("ffdf8d"));b.custom_minimum_size=Vector2(110,72);question_row.add_child(b)
		question_row.visible=question_row.get_child_count()>0
		layout_question()
	if map_panel.visible:map_drawing.queue_redraw()
func toggle_map()->void:
	map_panel.visible=not map_panel.visible
	if map_panel.visible:call_deferred("layout")
func draw_map()->void:
	var rect:=Rect2(Vector2(14,14),map_drawing.size-Vector2(28,28))
	var extent:=maxf(1,(stage.size-1)*MazeLevel.CELL)
	# Camera looks toward +Z, so screen-right is world -X. Never mirror by locale.
	var point:=func(p:Vector3)->Vector2:return rect.position+Vector2(1.0-p.x/extent,1.0-p.z/extent)*rect.size
	for c in stage.cells:
		for n in stage.around(c):
			if stage.connected(c,n):map_drawing.draw_line(point.call(stage.pos(c)),point.call(stage.pos(n)),Color(.12,.3,.46,.75),4,true)
	for g in stage.gates:map_drawing.draw_circle(point.call(stage.pos(g.a)),4,Color("54baff") if run.solved.has(g.id) and not run.explorer_mode() else Color("ffd654"))
	for c in stage.exits:map_drawing.draw_circle(point.call(stage.pos(c)),7,Color("60df92"))
	map_drawing.draw_circle(point.call(run.at),9,Color("ee458c"));map_drawing.draw_circle(point.call(run.at),4,Color.WHITE)

func message(value:String,duration:float=3)->void:
	if message_label!=null:message_label.text=value
	message_until=time+duration
func layout()->void:
	var size:=get_viewport().get_visible_rect().size
	if menu!=null:
		var card:=menu.get_node("Card") as Control
		var w:=minf(size.x-40,740);var h:=minf(size.y-50,940)
		card.position=(size-Vector2(w,h))/2;card.size=Vector2(w,h)
		if menu.name=="HomeScreen":
			card.size=Vector2(minf(size.x-32,850),size.y-32);card.position=(size-card.size)/2
			if is_instance_valid(journey):journey.custom_minimum_size.y=clampf(minf(minf(size.x-72,810)*.47,size.y-540),150,380)
			if is_instance_valid(home_actions):
				for action in home_actions.get_children():action.custom_minimum_size.y=clampf((size.y-410-journey.custom_minimum_size.y)/3,72,120)
			# Fit the welcome card to its contents on tall phones; keep the sky visible.
			var action_height:=clampf((size.y-410-journey.custom_minimum_size.y)/3,72,120)
			card.size.y=minf(size.y-32,journey.custom_minimum_size.y+action_height*3+300)
			card.position=(size-card.size)/2
	if hud==null:return
	var top:=hud.get_node("Top") as Control;top.position=Vector2(18,24);top.size=Vector2(size.x-36,105)
	layout_learning_hud()
	var control_size:=210.0 if profile.data.large_controls else 160.0
	joystick.position=Vector2(25,size.y-control_size-25);joystick.size=Vector2.ONE*control_size
	throw_button.size=Vector2(maxf(155,throw_button.get_combined_minimum_size().x),78)
	throw_button.position=Vector2(size.x-25-throw_button.size.x,size.y-25-throw_button.size.y)
	map_button.size=Vector2(maxf(throw_button.size.x,190 if profile.data.large_controls else 155),84 if profile.data.large_controls else 66)
	var back:=hud.get_node("Top").get_child(0).get_node("Back") as Button;back.custom_minimum_size=Vector2.ONE*(96 if profile.data.large_controls else 76)
	map_button.position=Vector2(size.x-25-map_button.size.x,size.y-25-map_button.size.y)
	layout_question()
	map_panel.size=Vector2(minf(320,size.x-48),300);map_panel.position=Vector2(size.x-map_panel.size.x-24,(size.y-map_panel.size.y)/2)
func layout_learning_hud()->void:
	if word_label==null:return
	var size:=get_viewport().get_visible_rect().size
	var top:=hud.get_node("Top") as Control
	top.size.y=maxf(105,top.get_combined_minimum_size().y)
	var y:=top.position.y+top.size.y+16
	var tray_height:=maxf(76,word_tray.get_combined_minimum_size().y+4)
	word_label.visible=not word_label.text.is_empty()
	word_label.size.x=440 if size.x>1000 else size.x-60
	word_label.size.y=maxf(60,word_label.get_combined_minimum_size().y)
	word_label.position=Vector2(30,y)
	if size.x>1000:
		word_scroll.position=Vector2(495,y);word_scroll.size=Vector2(size.x-525,tray_height)
		y+=maxf(word_label.size.y if word_label.visible else 0,tray_height if word_scroll.visible else 0)+16
	else:
		if word_label.visible:y+=word_label.size.y+16
		word_scroll.position=Vector2(30,y);word_scroll.size=Vector2(size.x-60,tray_height)
		if word_scroll.visible:y+=tray_height+16
	message_label.position=Vector2(40,y);message_label.size=Vector2(size.x-80,maxf(65,message_label.get_combined_minimum_size().y))
func layout_question()->void:
	if hud==null or question_label==null or question_row==null:return
	var q:=hud.get_node("Question") as Control
	q.visible=question_label.visible
	if not q.visible:return
	var view_size:=get_viewport().get_visible_rect().size
	var gap:=24.0
	var left:=joystick.position.x+joystick.size.x+gap
	var right:=map_button.position.x-gap
	var font:=question_label.get_theme_font("font")
	var natural_width:=font.get_string_size(question_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,question_label.get_theme_font_size("font_size")).x+48
	var answer_width:=question_row.get_combined_minimum_size().x if question_row.visible else 0.0
	var wanted:=maxf(180,maxf(natural_width,answer_width))
	var fits:=wanted<=right-left
	# Short prompts hug their content. Long prompts wrap in a separate row
	# above BOTH control groups, with the same clear margin on every side.
	var width:=wanted if fits else minf(maxf(wanted,300),minf(560,view_size.x-50))
	q.size=Vector2(width,q.get_combined_minimum_size().y)
	var controls_top:=minf(joystick.position.y,map_button.position.y)
	var y:=view_size.y-25-q.size.y if fits else controls_top-gap-q.size.y
	q.position=Vector2((left+right-width)/2 if fits else (view_size.x-width)/2,y)

func _input(event:InputEvent)->void:
	if event is InputEventScreenDrag:swipe.drag(event.index,event.position)
	elif event is InputEventScreenTouch and not event.pressed:swipe.end(event.index)
	elif event is InputEventMouseMotion:swipe.drag(-2,event.position)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:swipe.end(-2)

func _unhandled_input(event:InputEvent)->void:
	if not paused and menu==null and run.state=="playing":
		# Unhandled playfield presses include the character itself. HUD controls
		# keep their own events; screen-space direction matches the control pad.
		if event is InputEventScreenTouch and event.pressed:swipe.begin(event.index,event.position,joystick.size.x*.32)
		elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:swipe.begin(-2,event.position,joystick.size.x*.32)
	if event is InputEventKey and event.pressed:
		if event.physical_keycode==KEY_SPACE and not paused:run.throw_water()
		if event.physical_keycode==KEY_ESCAPE:pause_screen() if not paused else home()
func _notification(what:int)->void:
	if what==NOTIFICATION_APPLICATION_PAUSED and run!=null and not paused:pause_screen()
func refresh_question_art()->void:
	for g in stage.gates:
		if not gate_text.has(g.id):continue
		var nodes:Dictionary=gate_text[g.id];var prompt:Label3D=nodes.prompt
		prompt.text=str(g.display_prompt);prompt.text_direction=TextServer.DIRECTION_LTR if g.lesson=="math" else TextServer.DIRECTION_AUTO
		prompt.pixel_size=minf(.014,4.5/maxf(38,ceilf(prompt.text.length()/24.0)*38))
		var image_path:=str(g.get("picture",""))
		if not image_path.is_empty() and not is_instance_valid(nodes.picture):
			var picture:=Sprite3D.new();picture.position=stage.pos(g.a)+Vector3(0,.08,1.3);picture.rotation=Vector3(-PI/2,PI,0);picture.billboard=BaseMaterial3D.BILLBOARD_DISABLED;gate_models[g.id].add_child(picture);nodes.picture=picture
		if is_instance_valid(nodes.picture):
			nodes.picture.visible=not image_path.is_empty()
			if not image_path.is_empty():nodes.picture.texture=learning_texture(image_path);nodes.picture.pixel_size=1.8/maxi(1,nodes.picture.texture.get_height())
		var values:=stage.branch_values(g)
		for i in values.size():
			var sign:Label3D=nodes.answers[i];sign.text=MazeLessons.answer_text(g,int(values[i]));sign.pixel_size=minf(.018,1.5/maxf(36,ceilf(sign.text.length()/12.0)*36))
	shown_gate=-2

func make_sounds()->void:
	var types:=["balloon","water","letter","word","throw","splash","warning","correct","won","lost","hit","try_again"]
	for i in types.size():
		var bytes:=PackedByteArray();var duration:=.13 if i<3 else .3
		for frame in int(22050*duration):
			var t:=float(frame)/22050;var frequency:=330+i*48
			var tone:=sin(TAU*frequency*t+sin(t*20)*.4)*pow(1-t/duration,2)*.28
			var sample:=int(tone*32767)
			bytes.append(sample&255);bytes.append((sample>>8)&255)
		var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=22050;stream.data=bytes;sounds[types[i]]=stream
func play_sound(kind:String)->void:
	if kind=="rival_laugh" and profile.data.sound and not paused and music.foreground and music.focused:
		rival_audio.play();rival_laughs+=1
	if profile.data.sound and sounds.has(kind):audio.stream=sounds[kind];audio.play()
func write_qa()->void:
	var state:={"level":stage.number,"position":[run.at.x,run.at.z],"state":run.state,"points":run.provisional,"hits":run.hits,"solved":run.solved.size(),"fps":Engine.get_frames_per_second(),"locale":text.language,"size":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y]}
	state["music"]={"gain":music.gain,"paused":music.stream_paused,"position":music.get_playback_position(),"loaded":music.stream.get_length(),"foreground":music.foreground,"focused":music.focused,"gameActive":music.game.has_stream_playback(),"gameGain":music.game_gain,"gamePaused":music.game.stream_paused,"gamePosition":music.game.get_playback_position(),"gameLength":music.game.stream.get_length()}
	state["screen"]="game" if menu==null else menu.name;state["attempt"]=run.attempt_id;state["quality"]=profile.data.quality;state["primaryLanguage"]=primary_language;state["learningChoices"]=MazeWords.eligible(primary_language);state["age"]=run.age;state["paused"]=paused;state["ammo"]=run.ammo
	state["route"]=stage.route.map(func(c):var p:=stage.pos(c);return [p.x,p.z])
	state["rivalChoices"]=run.fox_choices;state["rivalDetourIndex"]=run.fox_detour_index;state["rivalDetourSize"]=run.fox_detour.size();state["race"]=stage.race;state["attemptId"]=run.attempt_id;state["rivalPosition"]=[run.fox_at.x,run.fox_at.z];state["rivalIndex"]=run.fox_index;state["rivalWait"]=run.fox_wait
	state["mapRect"]=[map_panel.position.x,map_panel.position.y,map_panel.size.x,map_panel.size.y];state["mode"]=profile.data.game_mode;state["glueLeft"]=run.glue_left;state["recoveries"]=run.recovery_count;state["checkpointGate"]=run.checkpoint_gate;state["mapVisible"]=map_panel.visible;state["subjects"]=run.adventure.settings.get("subjects",[]) if run.adventure!=null else []
	state["letters"]=run.letters.map(func(l):return [l.at.x,l.at.z]);state["nextLetter"]=run.next_letter
	state["right"]=[camera.global_basis.x.x,camera.global_basis.x.z]
	state["back"]=[camera.global_basis.z.normalized().x,camera.global_basis.z.normalized().z]
	var center:=joystick.global_position+joystick.size/2
	state["joystick"]=[center.x,center.y,joystick.size.x*.32]
	var gate:=run.nearby_gate();state["gate"]=gate.get("id",-1)
	state["correctButton"]=[]
	if not gate.is_empty():
		for child in question_row.get_children():
			if child is Button and child.text==str(gate.answer):var p:Vector2=child.global_position+child.size/2;state.correctButton=[p.x,p.y]
	state["buttons"]=qa_buttons(ui)
	state["rivalLaughsPlayed"]=rival_laughs;state["rivalLaughPlaying"]=rival_audio.playing;state["soundEnabled"]=profile.data.sound
	state["learning"]=run.learning;state["questionAuto"]=profile.data.question_auto;state["questionManualLevels"]=profile.data.question_manual_levels
	state["testMode"]=test_mode;state["profilePath"]=profile.path
	if run.adventure!=null:
		state["adventure"]={"kind":run.adventure.kind,"tier":run.adventure.tier,"complete":run.adventure.complete,"errors":run.adventure.letter_errors,"tray":run.adventure.tray,"target":run.units,"helperState":run.adventure.helper.state,"carrierState":run.adventure.carrier.state,"flare":run.adventure.flash_left,"letters":[]}
		for l in run.letters:state.adventure.letters.append({"id":l.index,"unit":l.unit,"at":[l.at.x,l.at.z],"picked":l.picked})
		state.adventure["helperAt"]=[run.adventure.helper.at.x,run.adventure.helper.at.z]
		state.adventure["helperTarget"]=[run.adventure.helper.target.x,run.adventure.helper.target.z]
		state.adventure["rescue"]=run.adventure.rescue
		state.adventure["helperVisible"]=friend_model.visible;state.adventure["helperName"]="Lumi"
		state.adventure["effort"]=run.adventure.helper.get("effort",0)
	state["bodies"]=run.ground_bodies().map(func(b):return {"id":b.id,"at":[b.at.x,b.at.z],"radius":b.radius})
	if run.adventure!=null:state.adventure["bots"]=run.bots.map(func(b):return {"at":[b.at.x,b.at.z],"mood":b.mood,"away":b.away})
	state["controlRects"]={}
	for control in [joystick,map_button,throw_button,hud.get_node("Question"),word_label,word_scroll,message_label]:
		if control.visible:
			var bounds:Rect2=control.get_global_rect()
			state["controlRects"][control.name]=[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]
	var top_rect:Rect2=(hud.get_node("Top") as Control).get_global_rect();state["topRect"]=[top_rect.position.x,top_rect.position.y,top_rect.size.x,top_rect.size.y]
	var projected:=camera.unproject_position(run.at+Vector3(0,.9,0));state["heroScreen"]=[projected.x,projected.y]
	state["swipe"]=[swipe.vector.x,swipe.vector.y];state["theme"]=stage.theme;state["layoutVersion"]=stage.generation
	state["gates"]=stage.gates.map(func(g):return {"id":g.id,"difficulty":g.get("difficulty",0),"subject":g.get("subject",""),"prompt":g.get("display_prompt",""),"choices":g.get("display_choices",{}),"from":[g.a.x*6,g.a.y*6],"arms":stage.branches(g).map(func(c):return [c.x*6,c.y*6]),"answer":g.answer,"values":stage.branch_values(g),"walkChoice":g.get("walk_choice",false)})
	state["balloonCount"]=swaying.size()
	var f:=FileAccess.open("user://qa-state.json.tmp",FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(state));f.close();DirAccess.rename_absolute("user://qa-state.json.tmp","user://qa-state.json")

func qa_buttons(node:Node)->Array:
	var found:Array=[]
	for child in node.get_children():
		if child is Button and child.is_visible_in_tree():
			var p:Vector2=child.global_position+child.size/2
			found.append({"text":child.text,"at":[p.x,p.y],"size":[child.size.x,child.size.y],"disabled":child.disabled})
		found.append_array(qa_buttons(child))
	return found

var balloon_textures:Dictionary={}
func add_balloon(parent:Node3D,anchor:Vector3,index:int,bouquet:bool,height:float)->Node3D:
	var names:=["blue","fuchsia","heart","rainbow","pearl","pink","rainbow","rose-gold","silver-gold","star","sunshine"]
	var path:="res://art/balloons/"+("finish-%d.png"%posmod(index,6) if bouquet else "balloon-%s.webp"%names[posmod(index,names.size())])
	if not balloon_textures.has(path):balloon_textures[path]=ImageTexture.create_from_image(Image.load_from_file(path))
	var root:=Node3D.new();parent.add_child(root);root.position=anchor
	var pivot:=Node3D.new();root.add_child(pivot)
	var image:=Sprite3D.new();image.texture=balloon_textures[path];image.pixel_size=height/image.texture.get_height();image.position.y=height*.5
	image.billboard=BaseMaterial3D.BILLBOARD_ENABLED;image.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	image.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD;image.alpha_scissor_threshold=.08;image.no_depth_test=false
	pivot.add_child(image)
	swaying.append({"pivot":pivot,"phase":float(swaying.size())*1.73})
	return root

# Temporary debug-only tools: separate profile, saves and rewards.
func test_copy(en:String,he:String)->String:
	return he if text.language=="he" else en

func start_test_level(number:int)->void:
	if not test_tools:return
	if not test_mode:
		if session_live and run.state=="playing":profile.checkpoint(run)
		normal_profile=profile
		profile=MazeProfile.new("user://manual-level-testing.json",primary_language)
		for key in ["ui","learning","sound","comfort","large_controls","quality","word_auto","word_tier","word_levels","question_auto","question_manual_levels","question_progress","game_mode","child_subjects","explorer_subjects","question_language","prompt_language","lesson_mode"]:profile.data[key]=normal_profile.data[key]
		test_mode=true
	clear_menu();load_level(clampi(number,1,100))

func leave_test_mode()->void:
	if not test_mode:return
	test_mode=false;session_live=false
	profile=normal_profile;normal_profile=null
	clear_menu();load_level(int(profile.data.unlocked),{},false);home()

func lesson_copy(key:String)->String:
	return str(adventure_copy.get(text.language,{}).get(key,key))
func lesson_prompt(g:Dictionary)->String:
	var kind:=str(g.get("lesson","math"))
	if kind=="knowledge":return str(g.display_prompt)
	if kind=="math":return g.prompt+" = ?"
	if kind=="wall":return lesson_copy("Build the word on the wall")+"\n"+g.display_prompt
	return lesson_copy("Choose the first letter" if kind in ["first_picture","first_word"] else "Choose the matching word")+" · "+lesson_copy(str(MazeWords.NAMES.get(g.get("answer_language",run.language_code),run.language_code)))+"\n"+str(g.get("display_prompt",""))
func request_learning_settings()->void:
	if platform!=null:platform.learning_settings_gate()
func learning_settings()->void:
	mode_screen(false)

func landscape_note(box:VBoxContainer)->void:
	if get_viewport().get_visible_rect().size.y>get_viewport().get_visible_rect().size.x:
		var notes:Dictionary={"en": "For a wider view, play in landscape.", "he": "לתצוגה רחבה יותר, שחקו במצב אופקי.", "ar": "لرؤية أوسع، العب بالوضع الأفقي.", "es": "Para una vista más amplia, juega en horizontal.", "fr": "Pour une vue plus large, jouez en paysage.", "nl": "Speel liggend voor een breder beeld.", "hi": "बड़े दृश्य के लिए लैंडस्केप में खेलें।"}
		box.add_child(label(str(notes.get(text.language,notes.en)),21))

func adventure_intro()->void:
	if run.adventure==null:return
	var box:=screen();menu.name="AdventureIntro"
	box.add_child(label(text.t("Level")+" "+str(stage.number),32))
	if not run.letters.is_empty():
		var picture:=TextureRect.new();picture.texture=learning_texture(MazeLessons.entries()[run.adventure.entry].image);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.custom_minimum_size=Vector2(100,105);box.add_child(picture)
		box.add_child(label(lesson_copy("Your word")+": "+"".join(run.units),30))
		box.add_child(label(lesson_copy("Collect these letters in any order. Extra letters do not belong." if run.adventure.tier==0 else "Collect letters in order. Tap a red letter in your tray to put it back."),23))
		box.add_child(label(lesson_copy("A green word earns a map hint." if run.adventure.kind!="night" else "Build your word in the bright area to earn your first flare. Collect more flares before the light runs out."),23))
	add_gate_explanation(box)
	var note:=""
	match run.adventure.kind:
		"wall":note="Collect your word, then tap its letters onto the word wall to open it."
		"translation":note="Read the word and walk into its matching translation." if run.adventure.settings.get("source","en")!=run.language_code else "Choose the matching word"
		"carrier":note="Balloon Minik may carry you! Run away or splash him. Most rides take you back; some help you forward."
		"rescue":note="Friends can help when visitors surround you. Walk towards the waving friend and follow them to a gate."
	if not note.is_empty():box.add_child(label(lesson_copy(note),23))
	box.add_child(label(lesson_copy("Drag the circle to move. When it becomes a balloon, tap its centre to throw."),23))
	landscape_note(box)
	box.add_child(button(lesson_copy("Let's explore!"),func():clear_menu();paused=false,MazeSkyUI.PINK))

func learning_texture(path:String)->ImageTexture:
	if not lesson_textures.has(path):lesson_textures[path]=ImageTexture.create_from_image(Image.load_from_file(path))
	return lesson_textures[path]
func update_word_tray()->void:
	if run.adventure==null:return
	var a:=run.adventure
	var key:=str(a.tray)+str(a.complete)
	if key==tray_key:return
	tray_key=key
	for child in word_tray.get_children():word_tray.remove_child(child);child.queue_free()
	word_tray.layout_direction=Control.LAYOUT_DIRECTION_RTL if run.language_code in ["he","ar"] else Control.LAYOUT_DIRECTION_LTR
	for item in a.tray_slots():
		var index:=int(item.slot)
		var tile:=button(str(item.text),func():run.adventure.remove_letter(index),Color("b9f4dc") if item.valid else Color("ffb8b3"))
		tile.custom_minimum_size=Vector2(72,68);tile.add_theme_font_size_override("font_size",26);tile.disabled=index<0 or a.complete
		for color in ["font_color","font_disabled_color","font_hover_color"]:tile.add_theme_color_override(color,Color("234d37") if item.valid else Color("992727"))
		tile.add_theme_stylebox_override("disabled",style(Color("b9f4dc") if a.complete else Color("e8f5ff")))
		word_tray.add_child(tile)

func open_word_wall()->void:
	var g:=run.nearby_gate()
	if g.is_empty() or g.get("lesson","")!="wall":return
	if not run.adventure.complete:message(lesson_copy("Find your letters first. Your word is shown above."),6);return
	wall_letters.clear();show_word_wall(int(g.id))
func show_word_wall(id:int)->void:
	var box:=screen();menu.name="WordWall"
	box.add_child(label(lesson_copy("Build the word on the wall"),30));box.add_child(label("".join(run.units),34))
	box.add_child(label(lesson_copy("Tap the letters in order. Tap a red letter above to remove it."),23))
	var chosen:=HBoxContainer.new();chosen.alignment=BoxContainer.ALIGNMENT_CENTER;chosen.layout_direction=Control.LAYOUT_DIRECTION_RTL if run.language_code in ["he","ar"] else Control.LAYOUT_DIRECTION_LTR;box.add_child(chosen)
	for i in wall_letters.size():
		var index:=i;var value:=str(run.units[int(wall_letters[i])]);var good:=value==str(run.units[i])
		var tile:=button(value,func():wall_letters.remove_at(index);show_word_wall(id),Color("b9f4dc") if good else Color("ffb8b3"));tile.custom_minimum_size=Vector2(45,52);chosen.add_child(tile)
	var pool:=GridContainer.new();pool.columns=5;pool.add_theme_constant_override("h_separation",10);pool.add_theme_constant_override("v_separation",10);box.add_child(pool)
	for i in range(run.units.size()-1,-1,-1):
		var index:=i;var tile:=button(str(run.units[i]),func():wall_letters.append(index);check_wall(id),Color("b8d9ff"));tile.disabled=wall_letters.has(i);pool.add_child(tile)
	box.add_child(button(text.t("Back"),func():clear_menu();paused=false))
func check_wall(id:int)->void:
	var built:Array=[]
	for index in wall_letters:built.append(run.units[int(index)])
	if built==run.units:
		clear_menu();paused=false;run.answer(id,int(stage.gates[id].answer));message(lesson_copy("Your word opened the wall!"),5)
	else:show_word_wall(id)

func setup_adventure_models()->void:
	if run.adventure==null:return
	friend_model=MazeArt.magical_dog();scene.add_child(friend_model);friend_model.visible=false
	friend_badge=label3d("",friend_model,Vector3(0,2.2,0),25)
	carrier_model=MazeArt.character();scene.add_child(carrier_model)
	# A pilot scarf distinguishes the visiting Minik from the player's Minik.
	MazeArt.box(carrier_model.get_node("Rig"),Vector3(0,.9,.17),Vector3(.55,.12,.18),Color("ff684e"))
	MazeArt.balloon(carrier_model,Vector3(0,2.1,0)).scale=Vector3.ONE*2.8
	MazeArt.box(carrier_model,Vector3(0,2.2,0),Vector3(.025,1.8,.025),Color("d2b98f"))
	carrier_model.visible=run.adventure.kind=="carrier"
	flare_models.clear()
	for flare in run.adventure.flares:
		var root:=Node3D.new();scene.add_child(root);root.position=flare.at
		MazeArt.box(root,Vector3(0,.3,0),Vector3(.14,.6,.14),Color("b2713b"))
		MazeArt.ball(root,Vector3(0,.75,0),Vector3(.45,.7,.45),Color("ffc63a"))
		label3d("✦",root,Vector3(0,1.35,0),40);flare_models.append(root)
	flare_light=OmniLight3D.new();flare_light.light_color=Color("ffd8a0");flare_light.omni_range=11;flare_light.shadow_enabled=false;scene.add_child(flare_light)
func animate_adventure(dt:float)->void:
	if run.adventure==null:return
	var a:=run.adventure
	var h:=a.helper;var delta:Vector3=h.at-friend_model.position;friend_model.position=h.at
	if delta.length()>.001:friend_model.rotation.y=lerp_angle(friend_model.rotation.y,atan2(delta.x,delta.z),1-exp(-dt*10))
	elif h.state in ["offer","lead"]:friend_model.look_at(Vector3(run.at.x,friend_model.position.y,run.at.z)+Vector3(.001,0,0),Vector3.UP,true)
	friend_model.visible=h.state!="rest"
	var scale_factor:=smoothstep(0,1,clampf(h.wait/1.2,0,1)) if h.state=="appear" else 1.0-smoothstep(0,1,clampf(h.wait/1.2,0,1)) if h.state=="depart" else 1.0
	friend_model.scale=Vector3.ONE*maxf(.01,scale_factor)
	MazeArt.social(friend_model,time,delta if h.state not in ["appear","rest"] else Vector3.ZERO,dt,"wave" if h.state in ["offer","lead"] else "play")
	friend_badge.text=lesson_copy("Come with me!") if h.state in ["offer","lead"] else lesson_copy("Lumi")
	carrier_model.position=a.carrier.at;carrier_model.visible=a.kind=="carrier"
	if carrier_model.visible:
		carrier_model.rotation.y=atan2(run.at.x-carrier_model.position.x,run.at.z-carrier_model.position.z)
		MazeArt.animate(carrier_model,time,false,a.carrier.state=="carry")
		if a.carrier.state=="carry":
			# Separate silhouettes, with the visitor's lowered hand meeting the
			# player's raised hand. Never stack two bodies through one another.
			carrier_model.position=hero.position+Vector3(.65,.75,0)
			carrier_model.rotation.y=0;hero.rotation.y=0
			carrier_model.get_node("Rig").position.y=0
			carrier_model.get_node("Rig/ArmL").rotation=Vector3.ZERO
			carrier_model.get_node("Rig/ArmR").rotation=Vector3(0,0,-2.8)
			hero.get_node("Rig/ArmR").rotation=Vector3(0,0,2.7)
	var dark:=a.darkness();var lit:=a.flash_left>0
	(get_node("Sun") as DirectionalLight3D).light_energy=lerpf(.6,.075,dark)
	(get_node("WorldLighting") as WorldEnvironment).environment.ambient_light_energy=lerpf(.3,.065,dark)
	flare_light.position=hero.position+Vector3(0,1.4,0);flare_light.light_energy=2.1 if lit else .3;flare_light.omni_range=11 if lit else 3
	for i in flare_models.size():flare_models[i].visible=not a.flares[i].taken

func add_gate_explanation(box:VBoxContainer)->void:
	var types:Array=[]
	for g in stage.gates:
		var kind:=str(g.get("lesson","math"))
		if not types.has(kind):types.append(kind)
	var language_name:=lesson_copy(str(MazeWords.NAMES.get(run.language_code,run.language_code)))
	var language_label:="\u2068"+language_name+"\u2069"
	if types.has("first_picture"):
		box.add_child(label(lesson_copy("Name the picture in {language}. Walk through the gate with its first letter.").replace("{language}",language_label),23))
	if types.has("first_word"):
		box.add_child(label(lesson_copy("Say the word in {language}. Walk through the gate with its first letter.").replace("{language}",language_label),23))
	if types.has("first_picture") or types.has("first_word"):
		var example:=0
		for i in MazeLessons.entries().size():
			if MazeLessons.entries()[i].id=="moon":example=i;break
		var picture:=TextureRect.new();picture.texture=learning_texture(MazeLessons.entries()[example].image);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.custom_minimum_size=Vector2(90,80);box.add_child(picture)
		var word:=MazeLessons.title(example,run.language_code);var initial:=str(MazeLessons.word(example,run.language_code)[0])
		box.add_child(label(lesson_copy("For example: {word} starts with {letter}.").replace("{word}","\u2068"+word+"\u2069").replace("{letter}","\u2068"+initial+"\u2069"),25))
	if types.has("translation"):
		box.add_child(label(lesson_copy("Choose the matching word in {language} and walk through its gate.").replace("{language}",language_label),23))

func gate_help()->void:
	var box:=screen();menu.name="GateHelp";box.add_child(label(text.t("Help"),32));add_gate_explanation(box);landscape_note(box)
	box.add_child(label(lesson_copy("Lumi is a magical dog. Walk towards his wave to accept help, or go your own way."),23))
	box.add_child(button(text.t("Resume"),func():clear_menu();paused=false))


func can_play(number:int)->bool:
	return number<=FREE_LEVELS or test_mode or qa or (platform!=null and platform.full_game_owned())
func unlock_screen()->void:
	var box:=screen();menu.name="UnlockScreen"
	box.add_child(label(text.t("Unlock the full adventure"),36))
	box.add_child(label(text.t("First 12 levels free. One purchase unlocks the full adventure. No ads."),25))
	box.add_child(label(text.t("Your progress stays safe. Free levels can always be replayed."),23))
	if platform!=null:
		if platform.full_game_owned():box.add_child(button(text.t("Continue adventure"),continue_adventure,MazeSkyUI.MINT))
		else:
			var price:=str(platform.unlock_price())
			box.add_child(button(text.t("Unlock the full adventure")+(" · "+price if not price.is_empty() else ""),func():platform.buy_full_game(),MazeSkyUI.MINT))
		box.add_child(button(text.t("Restore purchases"),func():platform.restore_full_game()))
	box.add_child(button(text.t("Back"),home))
func parent_screen()->void:
	var box:=screen();menu.name="ParentScreen";box.add_child(label(text.t("For a grown-up"),34))
	box.add_child(button(text.t("Adventure mode and subjects"),func():mode_screen(false)))
	box.add_child(button(text.t("Question difficulty"),func():question_settings()))
	box.add_child(button(text.t("Settings"),settings))
	box.add_child(button(text.t("Records"),records))
	box.add_child(button(text.t("Unlock the full adventure"),unlock_screen,MazeSkyUI.MINT))
	if platform!=null:
		box.add_child(button(text.t("Restore purchases"),func():platform.restore_full_game()))
		box.add_child(button(text.t("Privacy policy"),func():platform.show_privacy()))
		box.add_child(button(text.t("More Minik apps"),func():platform.more_apps()))
	box.add_child(button(text.t("Reset completed levels to 0"),confirm_reset,MazeSkyUI.PINK))
	if test_tools:box.add_child(button(test_copy("Test a level (1–100)","בדיקת שלב (1–100)"),func():platform.choose_test_level(stage.number,text.language)))
	if test_mode:box.add_child(button(test_copy("Return to normal play","חזרה למשחק הרגיל"),leave_test_mode))
	box.add_child(button(text.t("Back"),home,MazeSkyUI.PINK))
func question_settings(draft:Dictionary={})->void:
	if draft.is_empty():
		if run!=null and session_live and run.state=="playing":profile.checkpoint(run)
		draft={"question_auto":profile.data.question_auto,"question_manual_levels":profile.data.question_manual_levels.duplicate(true)}
	var box:=screen();menu.name="QuestionDifficulty";box.add_child(label(text.t("Question difficulty"),34))
	var toggle:=CheckButton.new();toggle.text=text.t("Adjust automatically");toggle.button_pressed=bool(draft.question_auto);toggle.custom_minimum_size.y=68;toggle.add_theme_font_size_override("font_size",25);MazeSkyUI.toggle(toggle)
	for color in ["font_color","font_pressed_color","font_hover_pressed_color","font_hover_color","font_focus_color"]:toggle.add_theme_color_override(color,MazeSkyUI.INK)
	toggle.toggled.connect(func(on):draft.question_auto=on;question_settings(draft));box.add_child(toggle)
	box.add_child(label(text.t("Two first-try correct answers make the next questions harder. Two first-try mistakes make them easier. Each subject adapts separately."),21))
	box.add_child(label(text.t("Questions already seen stay unchanged. Changes apply to questions you have not seen yet and your next attempt."),21))
	var options:=MazeLessons.options(profile.data);options.question_auto=true
	for subject in options.subjects:
		var code:=str(subject);var k:=MazeLearning.key(options,code)
		if not draft.question_manual_levels.has(k):draft.question_manual_levels[k]=MazeLearning.level_for(options,code)
		var title:=text.t(str(MazeCurriculum.SUBJECTS.get(code,"Math"))) if options.game_mode=="explorer" or code=="math" else lesson_copy(str(MazeWords.NAMES[code]))
		box.add_child(label(title,27))
		var selected:=MazeLearning.level_for(options,code) if draft.question_auto else clampi(int(draft.question_manual_levels[k]),1,MazeLearning.maximum(options,code))
		if draft.question_auto:
			box.add_child(label(text.t("Level {0}",str(selected))+" / "+str(MazeLearning.maximum(options,code)),24))
		else:
			var select:=OptionButton.new();select.custom_minimum_size.y=68;select.add_theme_font_size_override("font_size",25);style_select(select)
			for i in range(1,MazeLearning.maximum(options,code)+1):select.add_item(text.t("Level {0}",str(i)))
			select.select(selected-1);select.item_selected.connect(func(index):draft.question_manual_levels[k]=index+1;question_settings(draft));box.add_child(select)
		box.add_child(label(text.t("Example"),20))
		var example:=label(MazeLearning.example(options,code,selected),23)
		example.text_direction=Control.TEXT_DIRECTION_LTR if options.game_mode=="child" else Control.TEXT_DIRECTION_AUTO;box.add_child(example)
	box.add_child(button(text.t("Save"),func():
		profile.data.question_auto=draft.question_auto;profile.data.question_manual_levels=draft.question_manual_levels.duplicate(true)
		if run!=null and session_live and run.state=="playing":MazeLearning.apply_preferences(run,profile.data);refresh_question_art();profile.checkpoint(run)
		else:profile.save()
		parent_screen(),MazeSkyUI.MINT))
	box.add_child(button(text.t("Cancel"),parent_screen,MazeSkyUI.PINK))

func confirm_reset()->void:
	var box:=screen();box.add_child(label(text.t("Start the adventure again?"),34))
	box.add_child(label(text.t("This clears completed levels and local scores. Your purchase and settings stay safe."),25))
	box.add_child(button(text.t("Reset completed levels to 0"),func():profile.reset_progress();session_live=false;load_level(1,{},false);home(),MazeSkyUI.PINK))
	box.add_child(button(text.t("Cancel"),parent_screen))
func mode_screen(first:bool=false,keep:bool=false)->void:
	if not keep:
		onboarding_first=first;onboarding_mode=profile.data.game_mode;onboarding_language=profile.data.question_language
		onboarding_subjects=(profile.data.child_subjects if onboarding_mode=="child" else profile.data.explorer_subjects).duplicate()
	var box:=screen();menu.name="ModeScreen";box.add_child(label(text.t("Choose your adventure"),34))
	for mode in ["child","explorer"]:
		var selected:bool=onboarding_mode==mode
		var title:=text.t("For a child who loves to play and learn" if mode=="child" else "For those seeking a navigation adventure")
		var option:=VBoxContainer.new();option.add_theme_constant_override("separation",4);box.add_child(option)
		option.add_child(button(("✓ " if selected else "")+title,func():
			onboarding_mode=mode;onboarding_subjects=(profile.data.child_subjects if mode=="child" else profile.data.explorer_subjects).duplicate();mode_screen(onboarding_first,true),MazeSkyUI.MINT if selected else MazeSkyUI.BLUE))
		var detail:=label(text.t("Playful learning, colorful surprises, and a friendly rival." if mode=="child" else "Bigger mazes and longer questions. Less suitable for small children."),20)
		option.add_child(detail)
	box.add_child(label(text.t("You can always change this in For a grown-up."),21))
	if onboarding_mode=="explorer":
		box.add_child(label(text.t("Question language"),23))
		var lang:=OptionButton.new();style_select(lang);lang.add_item(lesson_copy("English"));lang.add_item(lesson_copy("עברית"));lang.select(1 if onboarding_language=="he" else 0)
		lang.item_selected.connect(func(i):onboarding_language="he" if i==1 else "en");box.add_child(lang)
	box.add_child(label(text.t("Learning subjects"),29))
	var available:Dictionary={"math":text.t("Math")}
	if onboarding_mode=="explorer":
		available={}
		for code in MazeCurriculum.SUBJECTS:available[code]=text.t(str(MazeCurriculum.SUBJECTS[code]))
	if onboarding_mode=="child":
		for code in MazeWords.STUDY_CODES:available[code]=lesson_copy(str(MazeWords.NAMES[code]))
	for group in [true,false]:
		box.add_child(label(text.t("Added · tap to remove" if group else "Available · tap to add"),24))
		var grid:=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",12);box.add_child(grid)
		for key in available:
			if onboarding_subjects.has(key)!=group:continue
			var k:String=key
			var choice:=button(("− " if group else "+ ")+str(available[k]),func():
				if onboarding_subjects.has(k):onboarding_subjects.erase(k)
				else:onboarding_subjects.append(k)
				mode_screen(onboarding_first,true),MazeSkyUI.MINT if group else MazeSkyUI.BLUE)
			choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choice.add_theme_font_size_override("font_size",25);grid.add_child(choice)
	var go:=button(text.t("Let's explore!" if onboarding_first else "Save"),save_mode,MazeSkyUI.PINK);go.disabled=onboarding_subjects.is_empty();box.add_child(go)
	if not onboarding_first:box.add_child(button(text.t("Cancel"),parent_screen))
func save_mode()->void:
	if onboarding_subjects.is_empty():return
	var previous:Array=profile.data.child_subjects if onboarding_mode=="child" else profile.data.explorer_subjects
	if profile.data.game_mode!=onboarding_mode or previous!=onboarding_subjects or profile.data.question_language!=onboarding_language:profile.data.active="";session_live=false
	profile.data.game_mode=onboarding_mode;profile.data.mode_chosen=true;profile.data.question_language=onboarding_language
	profile.data["child_subjects" if onboarding_mode=="child" else "explorer_subjects"]=onboarding_subjects.duplicate();profile.save()
	home() if onboarding_first else parent_screen()
func animate_lost_heart()->void:
	var heart:=label("♥",54);heart.add_theme_color_override("font_color",Color("ef397a"));ui.add_child(heart);heart.mouse_filter=Control.MOUSE_FILTER_IGNORE
	heart.position=health_label.global_position;heart.size=Vector2(64,64)
	var tween:=create_tween();tween.set_parallel(true);tween.tween_property(heart,"position",Vector2(get_viewport().get_visible_rect().size.x+80,heart.position.y+180),1.4).set_trans(Tween.TRANS_QUAD);tween.tween_property(heart,"modulate:a",0.0,1.4);tween.chain().tween_callback(heart.queue_free)
