extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,reason:String)->void:
	if not ok:failures.append(reason);printerr(reason)
func _initialize()->void:call_deferred("validate")
func validate()->void:
	var rows:Array=[]
	var lower:=0;var higher:=0;var early_three:=0
	for n in range(1,101):
		var old:=MazeLevel.new(n,{},2);var level:=MazeLevel.new(n,{},3)
		var minimum:=1 if n<=2 else 2 if n==3 else 3 if n<=5 else 4 if n<=9 else 5 if n<=19 else 6
		check(level.gates.size()>=minimum,"Enough meaningful answer forks %d: %d"%[n,level.gates.size()])
		if n<=2:check(level.manifest()==old.manifest(),"Preserve introduction %d"%n)
		else:check(level.route.size()>=12,"Exploration begins after teaching levels %d"%n)
		for g in level.gates:
			for choice in g.choices:
				if choice<g.answer:lower+=1
				if choice>g.answer:higher+=1
			if n>=6 and n<=15 and g.arms.size()==3:early_three+=1
		rows.append({"level":n,"oldRoute":old.route.size(),"newRoute":level.route.size(),"oldForks":old.gates.size(),"newForks":level.gates.size(),"threeWay":level.gates.filter(func(g):return g.arms.size()==3).size(),"grid":level.size})
	check(lower>100 and higher>100,"Wrong values vary above and below answer")
	check(early_three>0,"Three-way choices occur in early exploration")
	for n in [3,7,10,30,100]:
		var old:=MazeRun.new(MazeLevel.new(n,{},2));old.step(.05,Vector2.ZERO)
		var saved:=old.snapshot();var restored:=MazeRun.new(MazeLevel.new(n,saved.skills,saved.layout_version))
		check(restored.restore(saved) and restored.at==old.at and restored.level.links==old.level.links,"Version-two active run restored unchanged %d"%n)
	var report:={"passed":failures.is_empty(),"failures":failures,"levels":rows,"lowerWrongValues":lower,"higherWrongValues":higher,"earlyThreeWayForks":early_three}
	var f:=FileAccess.open("res://qa-output/progression-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("PROGRESSION ",JSON.stringify({"passed":failures.is_empty(),"failures":failures,"earlyThreeWayForks":early_three}));quit(0 if failures.is_empty() else 1)
