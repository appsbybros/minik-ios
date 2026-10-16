extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,what:String)->void:
	checks+=1
	if not ok:failures.append(what);printerr(what)
func _initialize()->void:call_deferred("validate")
func walk(run:MazeRun,target:Vector3)->void:
	for frame in 600:
		var delta:=target-run.at
		if delta.length()<.12:return
		run.step(1.0/60,Vector2(delta.x,delta.z).normalized())
func validate()->void:
	var three_way:=0
	for number in range(1,101):
		var level:=MazeLevel.new(number)
		check(level.theme==(number-1)/10,"Ten-level colour band %d"%number)
		check(not level.gates.is_empty(),"At least one fork %d"%number)
		for c in level.cells:check(not level.path(Vector2i.ZERO,c).is_empty(),"No isolated region %d"%number)
		for g in level.gates:
			check(g.arms.size()==g.choices.size(),"Every answer has the same kind of physical arch")
			if g.arms.size()==3:three_way+=1
			for wrong in g.arms.slice(1):
				check(not level.route.has(wrong),"Wrong choice is never the entrance or right path")
				var blocked:={level.key(g.a,wrong):true}
				check(level.path(wrong,level.exits[0],blocked).is_empty(),"Wrong branch cannot reconnect around the gate")
				var deeper:=false
				for c in level.around(wrong):
					if c!=g.a and level.connected(wrong,c):deeper=true
				check(deeper,"Wrong branch extends beyond the visible entrance")
			# Word walls use the explicit tile interface; their locked/complete
			# behavior is tested in validate_adventure. Physical forks use walking.
			if number>=3 and g.get("walk_choice",false):
				# Match navigation rules as well as its question settings. Leaving this
				# as child mode introduces glue and rescue timing into the fork fixture.
				level.skills["explorer_mode"]=true
				var run:=MazeRun.new(level,"en",{"game_mode":"explorer","subjects":["science"]});run.bots=[];level.race=false
				check(run.explorer_mode(),"Fork fixture uses consistent navigation settings")
				# Focused collision fixture: start at the fork with earlier questions solved.
				for previous in level.gates:
					if previous.id<g.id:run.solved[previous.id]=true
				run.at=level.pos(g.a)
				walk(run,level.pos(g.arms[1]))
				check(run.at.distance_to(level.pos(g.arms[1]))<.2 and not run.solved.has(g.id),"Can walk wrong arm %d/%d"%[number,g.id])
				walk(run,level.pos(g.a));check(run.at.distance_to(level.pos(g.a))<.2,"Can return without trapping the child %d/%d"%[number,g.id])
				walk(run,level.pos(g.b));check(run.solved.has(g.id) and run.at.distance_to(level.pos(g.b))<.2,"Walking correct arm answers through physics")
	check(three_way>0,"Advanced layouts include genuine three-choice forks")
	var old:=MazeRun.new(MazeLevel.new(12,{},1));old.step(.05,Vector2.ZERO)
	var save:=old.snapshot();save.erase("layout_version")
	var resumed:=MazeRun.new(MazeLevel.new(save.number,save.skills,int(save.get("layout_version",1))))
	check(resumed.restore(save) and resumed.at==old.at,"Pre-update active runs retain their original layout")
	var swipe:=MazeSwipe.new()
	for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		check(swipe.begin(2,Vector2(100,100),50),"Acquire pointer")
		swipe.drag(3,Vector2(999,999));check(swipe.vector==Vector2.ZERO,"Second finger cannot steal direction")
		swipe.drag(2,Vector2(100,100)+direction*100);check(swipe.vector.is_equal_approx(direction),"All four swipe directions clamp like joystick")
		swipe.end(3);check(swipe.pointer==2,"Other release does not stop owned pointer")
		swipe.end(2);check(swipe.vector==Vector2.ZERO and swipe.pointer==-1,"Owned release stops")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"threeChoiceForks":three_way}
	var f:=FileAccess.open("res://qa-output/fork-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("FORK VALIDATION ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
