extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok and not failures.has(title):failures.append(title);printerr(title)
func make(n:int=5)->MazeRun:return MazeRun.new(MazeLevel.new(n),"en",{"tier":0,"source":"he","mode":"mixed"})
func separated(r:MazeRun,title:String)->void:
	var bodies:=r.ground_bodies()
	for i in bodies.size():
		for j in range(i+1,bodies.size()):check(bodies[i].at.distance_to(bodies[j].at)>=bodies[i].radius+bodies[j].radius+.02,title)
func _initialize()->void:call_deferred("test")
func test()->void:
	var r:=make();r.bots.resize(1);var b:Dictionary=r.bots[0];b.at=Vector3(1.4,0,0);r.at=Vector3(-1,0,0)
	for i in 100:r.at=r.move_ground(r.at,Vector3(.2,0,0),"hero");separated(r,"Player cannot pass through visitor")
	check(r.at.x<.55,"Solid visitor stops direct input")
	var stopped:=r.at
	for i in 40:r.at=r.move_ground(r.at,Vector3(.1,0,0),"hero")
	check(r.at==stopped,"Sustained contact has no jitter or push")
	for i in 20:r.at=r.move_ground(r.at,Vector3(0,0,.1),"hero")
	for i in 35:r.at=r.move_ground(r.at,Vector3(.1,0,0),"hero")
	check(r.at.x>b.at.x,"Player can walk around a visitor")
	r.at=Vector3(-1.4,0,0);b.at=Vector3(1.4,0,0)
	for i in 160:
		r.at=r.move_ground(r.at,Vector3(.025,0,0),"hero");b.at=r.move_ground(b.at,Vector3(-.025,0,0),"bot0",true);separated(r,"NPC and player crossing remain solid")
	check(b.at.x<-.6,"Visitor steers past the player")
	r.at=Vector3(-1.4,0,0);b.at=Vector3(1.4,0,0);r.adventure.helper.state="offer";r.adventure.helper.at=Vector3(0,0,0)
	for i in 120:
		r.at=r.move_ground(r.at,Vector3(.05,0,0),"hero");b.at=r.move_ground(b.at,Vector3(-.05,0,0),"bot0",true);separated(r,"Dog uses same collision rule")
	var race:=make(7)
	check(race.level.race,"Race fixture")
	for i in 30:race.at=race.move_ground(race.at,Vector3(.1,0,0),"hero");separated(race,"Race fox is solid")
	var old:=make();old.bots[0].at=old.at;var pos:=old.at;old.settle_loaded_bodies();separated(old,"Legacy overlap migrates safely");check(old.at==pos,"Migration preserves child position")
	for n in [1,5,7,10,13,20,30,50,75,100]:
		var fresh:=make(n);fresh.settle_loaded_bodies();separated(fresh,"Fresh spawn separation level "+str(n))
	var idle:=make();idle.bots.clear()
	for i in 2400:idle.step(.05,Vector2.ZERO)
	check(idle.adventure.helper.state=="rest","Reading at entrance for two minutes never summons helper")
	check(idle.adventure.helper.name=="Lumi","Helper identity is magical dog")
	var help:=make();help.bots.clear();help.age=54;help.adventure.helper.effort=25.0;help.adventure.helper.active_total=30.0;help.adventure.step_helper(.01)
	check(help.adventure.helper.state=="rest","No help before initial grace period")
	help.age=56;help.adventure.step_helper(.01);check(help.adventure.helper.state=="appear","Sustained activity without progress summons helper")
	for i in 1000:
		help.adventure.step_helper(.02);separated(help,"Helper approach never overlaps player")
		if help.adventure.helper.state=="offer":break
	check(help.adventure.helper.state=="offer","Helper reaches child with offer")
	for i in 50:help.adventure.step_helper(.02)
	check(help.adventure.helper.state=="offer","Helper does not accept own offer automatically")
	var toward:Vector3=(help.adventure.helper.at-help.at).normalized()
	help.at=help.move_ground(help.at,toward*.5,"hero");help.adventure.step_helper(.02)
	check(help.adventure.helper.state=="lead","Moving toward paw wave accepts help")
	help.adventure.helper.state="leave";help.adventure.helper.path=[]
	for i in 3000:
		help.adventure.step_helper(.02)
		if help.adventure.helper.state=="rest":break
	check(help.adventure.helper.state=="rest","Dog leaves rather than standing permanently")
	var model:=MazeArt.magical_dog();root.add_child(model)
	check(model.get_meta("quadruped",false),"Dog has four-footed rig")
	MazeArt.social(model,0,Vector3.ZERO,.02,"wave")
	check(model.get_node("Rig/ArmR").rotation.x<-.5,"Offer visibly waves front paw")
	var visitor:=MazeArt.human("Pip");root.add_child(visitor)
	MazeArt.social(visitor,0,Vector3(.1,0,0),.02,"play");var phase:float=visitor.get_meta("gait_phase")
	for i in 50:MazeArt.social(visitor,float(i)*.02,Vector3.ZERO,.02,"play")
	check(visitor.get_meta("gait_phase")==phase,"Standing visitor does not march in place")
	check(float(visitor.get_meta("gait_blend"))<.01,"Walking animation settles to breathing at rest")
	check(visitor.has_node("Rig/ArmR/Joint/Water") and visitor.has_node("Rig/LegL/Joint"),"Hands and feet remain attached to articulated limbs")
	model.queue_free();visitor.queue_free()
	var result:={"passed":failures.is_empty(),"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute("res://qa-output")
	FileAccess.open("res://qa-output/actors-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("ACTOR CHECKS ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
