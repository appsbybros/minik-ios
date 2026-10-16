class_name MazeReferenceAgent
extends RefCounted

# Test-only controller. It uses the public movement, question and throw APIs;
# it never edits health, positions, gate completion, pickups or score.
static func play(stage:MazeLevel,language:String="en",speed:float=1.0,words:bool=false,enemy_factor:float=1.0,reading:float=0.0,dodge:bool=false)->Dictionary:
	var run:=MazeRun.new(stage,language)
	run.enemy_factor=enemy_factor
	var waypoints:Array[Vector3]=[]
	for c in stage.route:
		waypoints.append(stage.pos(c))
		for pickup in stage.pickups:
			if pickup.cell==c and pickup.kind=="water":
				waypoints.append(stage.pos(c)+pickup.offset);waypoints.append(stage.pos(c))
		if words:
			for letter in run.letters:
				if stage.cell_for(letter.at)==c:waypoints.append(letter.at)
			waypoints.append(stage.pos(c))
	var index:=0
	var frames:=0
	var last_throw:=-100.0
	var reading_id:=-1
	var read_until:=0.0
	var hit_trace:Array=[]
	var previous_hits:=0
	while run.state=="playing" and frames<40000:
		frames+=1
		var gate:=run.nearby_gate()
		if not gate.is_empty():
			if reading_id!=int(gate.id):reading_id=gate.id;read_until=run.age+reading
			if run.age>=read_until:run.answer(gate.id,gate.answer)
		var target:Vector3=waypoints[mini(index,waypoints.size()-1)]
		if run.at.distance_to(target)<.16:index+=1
		var dir:=(target-run.at).normalized()
		for bot in run.bots:
			if bot.away<=0 and run.at.distance_to(bot.at)<8 and run.ammo>0 and run.age-last_throw>1 and run.clear_line(run.at,bot.at):
				var aim:Vector3=bot.at-run.at
				run.step(1.0/60,Vector2(aim.x,aim.z).normalized()*.01)
				run.throw_water();last_throw=run.age
		if run.age-last_throw<.65 or (not gate.is_empty() and run.age<read_until):run.step(1.0/60,Vector2.ZERO)
		elif index<waypoints.size():run.step(1.0/60,(avoid_balloon(run,Vector2(dir.x,dir.z)*speed,speed) if dodge else Vector2(dir.x,dir.z)*speed))
		else:run.step(1.0/60,Vector2.ZERO)
		if run.hits>previous_hits:
			hit_trace.append({"seconds":run.age,"position":[run.at.x,run.at.z],"ammo":run.ammo});previous_hits=run.hits
	return {"level":stage.number,"seed":stage.seed_value,"state":run.state,"seconds":run.age,"hits":run.hits,"score":run.provisional,"frames":frames,"gateCount":stage.gates.size(),"timerMargin":stage.timer-run.age if stage.timer>0 else -1,"language":language,"speed":speed,"enemyFactor":enemy_factor,"readingSeconds":reading,"wordUnits":run.units.size(),"lettersCollected":run.next_letter,"collectWords":words,"hitTrace":hit_trace,"dodging":dodge}

# A player can sidestep a visibly approaching balloon. Keep this controller on
# public movement APIs: no teleport, health changes or projectile suppression.
static func avoid_balloon(run:MazeRun,desired:Vector2,speed:float)->Vector2:
	for shot in run.shots:
		if not shot.enemy or shot.life<=0:continue
		var offset:=Vector2(shot.at.x-run.at.x,shot.at.z-run.at.z)
		var velocity:=Vector2(shot.dir.x,shot.dir.z)*float(shot.speed)-desired*3.3
		var closest:=clampf(-offset.dot(velocity)/maxf(.001,velocity.length_squared()),0,.8)
		if closest<=0 or (offset+velocity*closest).length()>.9:continue
		var side:=Vector2(-shot.dir.z,shot.dir.x).normalized()*speed
		var choices:Array[Vector2]=[side,-side]
		if (-side).dot(desired)>side.dot(desired):choices.reverse()
		for candidate in choices:
			var end:=run.at+Vector3(candidate.x,0,candidate.y)*3.3*.4
			if run.level.can_move(end,run.solved) and run.clear_line(run.at,end):return candidate
	return desired
