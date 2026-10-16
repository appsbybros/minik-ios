extends SceneTree
var failures:Array=[]
var checks:=0
var rows:Array=[]
func check(ok:bool,what:String)->void:
	checks+=1
	if not ok:failures.append(what);printerr(what)
func _initialize()->void:call_deferred("validate")
func validate()->void:
	for layout in [5,6]:
		for mode in ["child","explorer"]:
			var r:=MazeRun.new(MazeLevel.new(3,{"explorer_mode":mode=="explorer"},layout),"he",{"game_mode":mode,"subjects":["math"] if mode=="child" else ["science"]})
			var g:Dictionary=r.level.gates[0];r.at=r.level.pos(g.a);r.answer(g.id,g.answer)
			r.hits=2;r.invulnerable=0;r.age=25;r.hit()
			check(r.state=="lost","Third hit ends attempt %s gen%d"%[mode,layout])
			var before:=r.snapshot()
			for i in 100:r.step(.05,Vector2.ONE)
			check(r.snapshot()==before,"Whole simulation freezes after loss %s gen%d"%[mode,layout])
			var profile:=MazeProfile.new("user://retry-test.json");profile.data.bests={"1":42};profile.data.receipts=[];profile.data.active="old"
			check(profile.finish(r)==0 and profile.total()==42 and profile.data.active.is_empty(),"No lost-run points banked or failed checkpoint resumed")
			var retry:=MazeRun.new(MazeLevel.new(3,r.level.skills),r.language_code,r.adventure.settings)
			check(retry.at==Vector3.ZERO and retry.fox_index==0 and retry.fox_wait==0 and retry.age==0 and retry.hits==0 and retry.solved.is_empty() and retry.collected.is_empty() and retry.shots.is_empty(),"Clean synchronized restart %s"%mode)
			check(retry.attempt_id!=r.attempt_id,"Retry has a distinct scoring receipt")
	# Occupied turn waypoints formerly deadlocked level 17 (and level 87).
	# Keep the player solid and idle; the rival must continue around them.
	var blocked:=MazeRun.new(MazeLevel.new(17),"en",{"game_mode":"child","subjects":["math"]})
	blocked.bots.clear();blocked.fox_index=3;blocked.attempt_id="occupied-waypoint"
	var waypoint:=blocked.level.pos(blocked.level.route[4])+blocked.fox_lane(3)
	blocked.at=waypoint+Vector3(0,0,-.45);blocked.fox_at=waypoint+Vector3(0,0,.45)
	var start:=blocked.fox_at
	for i in 240:
		var last:=blocked.fox_at;blocked.step(1.0/60,Vector2.ZERO)
		check(blocked.fox_at.distance_to(blocked.at)>=.88,"Occupied waypoint keeps solid footprints")
		check(blocked.fox_at.distance_to(last)<=blocked.fox_pace()/60+.001,"Occupied waypoint never teleports the rival")
	check(blocked.fox_index>3 and blocked.fox_at.distance_to(start)>3,"Rival passes occupied waypoint and keeps running")
	# Independent breadth-first measurement of the first dead end, not the
	# generator's own cached depth helper.
	for n in [1,2,3,5,10,30,55,99,100]:
		var l:=MazeLevel.new(n,{"explorer_mode":true})
		check(not l.race,"Navigation mode has no answer-leading opponent %d"%n)
		for g in l.gates:
			for arm in l.branches(g).slice(1):
				var queue:Array=[{"cell":arm,"depth":1}];var seen:Dictionary={g.a:true,arm:true};var nearest:=1000
				while not queue.is_empty():
					var item:Dictionary=queue.pop_front();var degree:=0
					for next in l.around(item.cell):
						if l.connected(item.cell,next):
							degree+=1
							if not seen.has(next):seen[next]=true;queue.append({"cell":next,"depth":item.depth+1})
					if degree==1:nearest=mini(nearest,item.depth)
				check(nearest>=5,"Wrong branch needs at least five corridors %d"%n)
				check(not seen.has(l.exits[0]),"Wrong branch cannot bypass the answer %d"%n)
	# Per-fork choices must vary, survive restoration mid-detour, and always
	# return along legal ground movement. An idle human is deliberate here.
	var wrong:=0;var right:=0;var mixed:=0
	for n in range(1,101):
		var r:=MazeRun.new(MazeLevel.new(n),"en",{"game_mode":"child","subjects":["math"]})
		r.bots.clear();r.attempt_id="retry-rival-%d"%n
		var replay:MazeRun=null;var checked_restore:=false;var last:=r.fox_at
		for i in 6500:
			r.step(.05,Vector2.ZERO)
			check(r.fox_at.distance_to(last)<=r.fox_pace()*.05+.001,"No rival warp at level %d"%n);last=r.fox_at
			if not checked_restore and r.fox_detour_index>0 and r.fox_detour_index<r.fox_detour.size():
				var saved:=r.snapshot();replay=MazeRun.new(MazeLevel.new(n),"en",r.adventure.settings)
				check(replay.restore(saved),"Restore rival during wrong-path return %d"%n)
				check(replay.snapshot()==saved,"Rival plan survives restoration %d"%n)
				for tick in 12:
					r.step(.05,Vector2.ZERO);replay.step(.05,Vector2.ZERO)
				check(replay.snapshot()==r.snapshot(),"Restored rival continues identically %d"%n)
				last=r.fox_at;checked_restore=true
			if r.state!="playing":break
		var correct:=r.fox_choices.values().count(0);var incorrect:=r.fox_choices.size()-correct
		right+=correct;wrong+=incorrect
		if correct>0 and incorrect>0:mixed+=1
		check(r.state=="lost" and r.events.any(func(e):return e.kind=="lost" and e.get("reason")=="race"),"Rival reaches exit without getting stranded %d"%n)
		rows.append({"level":n,"seconds":r.age,"choices":r.fox_choices,"detourRestored":checked_restore,"state":r.state})
	check(wrong>100 and right>100 and mixed>35,"Rival choices are varied rather than an answer key")
	var report:={"checks":checks,"failures":failures,"passed":failures.is_empty(),"rivalRuns":rows,"wrongChoices":wrong,"rightChoices":right,"mixedRuns":mixed}
	FileAccess.open("res://qa-output/retry-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RETRY ",checks," checks; failures=",failures.size()," right=",right," wrong=",wrong," mixed=",mixed)
	quit(0 if failures.is_empty() else 1)
