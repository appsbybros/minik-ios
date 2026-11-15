extends SceneTree

var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		push_error(message);quit(1)
		assert(ok,message)

func _initialize()->void:
	call_deferred("verify")

func verify()->void:
	var w=load("res://main.tscn").instantiate()
	root.add_child(w)
	await process_frame
	w.home()
	w.profile.data.mode_chosen=true
	w.profile.data.played=false
	w.profile.data.quick_intro_seen=false
	w.continue_adventure()
	check(w.menu.name=="QuickIntroOffer","A first adventure offers optional practice")
	w.profile.data.unlocked=8
	w.profile.data.bests={"1":32}
	w.profile.data.receipts=["existing-receipt"]
	w.profile.data.active="existing-saved-adventure"
	w.session_live=false
	var original=w.profile
	var before:Dictionary=original.data.duplicate(true)
	w.start_quick_intro()
	await process_frame
	check(w.profile!=original and not w.session_live,"Practice cannot checkpoint normal progress")
	check(not w.stage.race and w.stage.timer==0 and w.run.bots.is_empty(),"Practice is unpressured")
	check(w.run.ammo==0 and w.run.letters.is_empty(),"Movement starts with a plain circle and no removed letter tasks")
	check(w.quick_intro.step_index==0,"Movement is first")
	w.toggle_map();w.close_map()
	check(w.quick_intro.step_index==0,"Opening map early cannot skip movement")
	w.throw_water()
	check(w.quick_intro.step_index==0,"Throwing early cannot skip gates")
	var g:Dictionary=w.stage.gates[0]
	check(w.lesson_prompt({"lesson":"math","prompt":"8 + 7","display_prompt":"1 + 2 = ?"})=="1 + 2 = ?","Math HUD uses the same adapted question as the floor")
	var target:Vector3=w.stage.pos(g.a)
	for i in 500:
		var delta:Vector3=target-w.run.at
		if delta.length()<.05:break
		w.run.step(.025,Vector2(delta.x,delta.z).normalized())
		w.quick_intro.observe(w.run)
	check(w.quick_intro.step_index==1,"Real walking advances the movement task")
	check(w.run.at.distance_to(target)<.1,"The practice question is reachable")
	var exit:Vector3=w.stage.pos(g.b)
	for i in 500:
		var delta:Vector3=exit-w.run.at
		if not w.run.solved.is_empty():break
		w.run.step(.025,Vector2(delta.x,delta.z).normalized())
		w.quick_intro.observe(w.run)
	check(w.quick_intro.step_index==2 and w.run.solved.has(g.id),"Walking through the correct gate advances task two")
	check(w.run.ammo>=3,"Balloons remain available even after early throws")
	w.run.throw_cooldown=0
	w.throw_water()
	check(w.quick_intro.step_index==3 and not w.run.shots.is_empty(),"A real throw advances task three")
	w.toggle_map()
	check(w.quick_intro.step_index==3 and w.map_panel.visible,"Map stays open to read before completion")
	w.close_map()
	check(w.quick_intro.step_index==4 and w.menu.name=="QuickIntroComplete","Closing the inspected map finishes")
	check(original.data.quick_intro_complete,"Completion is remembered")
	w.leave_quick_intro(false)
	await process_frame
	check(w.profile==original and w.quick_intro==null,"Normal profile is restored")
	for key in before:
		if key in ["quick_intro_seen","quick_intro_complete"]:continue
		check(w.profile.data[key]==before[key],"Practice altered normal field: "+key)
	w.start_quick_intro();w.pause_screen()
	check(w.menu.name=="QuickIntroPause" and w.paused,"Practice has a resumable pause")
	w.home()
	await process_frame
	check(w.quick_intro==null and w.profile==original,"Back from practice cannot save it as a normal game")
	for lang in ["en","he","es","fr","nl","hi","ar"]:
		w.text.language=lang
		for key in ["Quick practice","Start practice","Send feedback",MazeQuickIntro.new().instruction()]:
			check(w.text.translations[lang].has(key),"Missing intro translation: "+lang+" "+key)
	var report:={"passed":true,"assertions":checks,"scope":"Real run mechanics and world navigation; device touch is checked separately"}
	DirAccess.make_dir_recursive_absolute("res://qa-output")
	FileAccess.open("res://qa-output/intro-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	w.queue_free()
	await process_frame
	quit()
