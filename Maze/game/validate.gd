extends SceneTree
# Regression suite for existing generation-3 saved adventures.
# New generation-4 adventures: validate_adventure.gd + validate_journeys.gd.
var failures:Array[String]=[]
var reports:Array=[]
func check(condition:bool,label:String)->void:
	if not condition:failures.append(label);printerr(label)
func _initialize()->void:
	call_deferred("validate")
func validate()->void:
	check(MazeWords.eligible("he_IL")==["en","he","es","fr"],"Only four study languages")
	check(MazeWords.eligible("en_US").has("he"),"Hebrew study is available in every interface language")
	for language in MazeWords.BANKS:
		for word in MazeWords.BANKS[language]:check(not word.is_empty() and word.all(func(unit):return not str(unit).is_empty()),"Word units: "+language)
	var manifests:=[]
	for number in range(1,101):
		var stage:=MazeLevel.new(number,{},3)
		manifests.append(stage.manifest())
		check(stage.path(Vector2i.ZERO,stage.exits[0]).size()>1,"Reachable exit "+str(number))
		var blocked:={}
		for g in stage.gates:blocked[g.key]=true
		for exit_cell in stage.exits:
			check(stage.path(Vector2i.ZERO,exit_cell,blocked).is_empty(),"No gate bypass "+str(number))
		for g in stage.gates:
			var only:={g.key:true}
			for exit_cell in stage.exits:check(stage.path(Vector2i.ZERO,exit_cell,only).is_empty(),"Every fork required %d/%d"%[number,g.id])
		var run:=MazeRun.new(stage,"en")
		var waypoints:Array[Vector3]=[]
		for c in stage.route:
			waypoints.append(stage.pos(c))
			for pickup in stage.pickups:
				if pickup.cell==c and pickup.kind=="water":waypoints.append(stage.pos(c)+pickup.offset);waypoints.append(stage.pos(c))
		var index:=0
		var frames:=0
		var last_throw:=-100.0
		while run.state=="playing" and frames<36000:
			frames+=1
			var g:=run.nearby_gate()
			if not g.is_empty():run.answer(g.id,g.answer)
			var target:Vector3=waypoints[mini(index,waypoints.size()-1)]
			if run.at.distance_to(target)<.18:index+=1
			var dir:=(target-run.at).normalized()
			for bot in run.bots:
				if bot.away<=0 and run.at.distance_to(bot.at)<8 and run.ammo>0 and run.age-last_throw>1 and run.clear_line(run.at,bot.at):
					var aim:Vector3=bot.at-run.at
					run.step(1.0/60,Vector2(aim.x,aim.z).normalized()*.01)
					run.throw_water();last_throw=run.age
			# Walking along a side of a corridor leaves room to dodge slow projectiles.
			if run.age-last_throw<.65:run.step(1.0/60,Vector2.ZERO)
			elif index<waypoints.size():run.step(1.0/60,Vector2(dir.x,dir.z))
			else:run.step(1.0/60,Vector2.ZERO)
		check(run.state=="won","Dynamic stage %d: %s at %s hits=%d time=%.1f"%[number,run.state,run.at,run.hits,run.age])
		reports.append({"level":number,"seed":stage.seed_value,"state":run.state,"seconds":run.age,"hits":run.hits,"score":run.provisional,"frames":frames,"gateCount":stage.gates.size(),"timerMargin":stage.timer-run.age if stage.timer>0 else -1})
	# Reward events and receipt persistence are covered by validate_state.gd.
	var hit_run:=MazeRun.new(MazeLevel.new(5,{},3))
	hit_run.hit();hit_run.hit();check(hit_run.hits==1,"Contact invulnerability prevents duplicate hit")
	for i in 140:hit_run.step(1.0/60,Vector2.ZERO)
	hit_run.hit();check(hit_run.hits==2,"Second timed hit")
	var out:="res://qa-output"
	DirAccess.make_dir_recursive_absolute(out)
	var f:=FileAccess.open(out+"/level_validation_100.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"scenarios":reports},"  "));f.close()
	f=FileAccess.open(out+"/level_manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(manifests,"  "));f.close()
	print("MAZE VALIDATION: ",reports.size()," dynamic runs; failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
