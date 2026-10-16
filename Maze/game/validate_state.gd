extends SceneTree
# Regression suite for existing generation-3 saved adventures.
# New generation-4 adventures: validate_adventure.gd + validate_journeys.gd.
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,what:String)->void:
	checks+=1
	if not ok:failures.append(what);printerr(what)
func _initialize()->void:call_deferred("validate")
func validate()->void:
	var stage:=MazeLevel.new(20,{},3)
	var run:=MazeRun.new(stage)
	# Exercise actual reward events; positions are fixture setup, not path evidence.
	for gate in stage.gates:
		run.at=stage.pos(gate.a)
		var before:=run.provisional
		check(not run.answer(gate.id,gate.answer+100),"Wrong answer rejected")
		check(run.answer(gate.id,gate.answer),"Correct after mistake accepted")
		check(run.provisional==before+1,"Mistake-adjusted reward")
		check(not run.answer(gate.id,gate.answer),"Repeated answer rejected")
	for letter in run.letters:
		run.at=letter.at;run.step(.001,Vector2.ZERO)
	check(run.next_letter==run.units.size(),"Ordered word completes")
	check(run.hint_tokens==1,"Exactly one word token")
	var prior:=run.provisional
	run.at=stage.pos(stage.exits[0]);run.step(.001,Vector2.ZERO)
	check(run.state=="won" and run.provisional==prior+55,"Completion formula uses actual exit")
	var profile:=MazeProfile.new("user://state-validation.json")
	profile.data.bests={};profile.data.receipts=[];profile.data.attempts=0;profile.data.skills={"math":0.0,"words":0.0,"maze":0.0,"enemies":0.0}
	var reward:=profile.finish(run)
	var skills:Dictionary=profile.data.skills.duplicate()
	check(profile.finish(run)==0 and profile.data.attempts==1 and profile.data.skills==skills,"Duplicate receipt cannot train mastery or count attempts")
	var replay:=MazeRun.new(stage);replay.state="won";replay.provisional=reward+3
	check(profile.finish(replay)==3,"New attempt only banks best-score improvement")
	var failed:=MazeRun.new(stage);failed.state="lost";failed.provisional=300
	check(profile.finish(failed)==0 and profile.total()==reward+3,"Failure keeps earlier score")
	profile.data.unlocked=100
	var active:=MazeRun.new(MazeLevel.new(40,{"math":.3,"words":.4,"maze":.2,"enemies":.5},3),"hi")
	for i in 65:active.step(1.0/60,Vector2.ZERO)
	active.hit();active.ammo=4;active.throw_water()
	profile.checkpoint(active)
	var reread:=MazeProfile.new("user://state-validation.json")
	var saved:=reread.active_run()
	check(not saved.is_empty(),"Atomic saved attempt reloads")
	var resumed:=MazeRun.new(MazeLevel.new(saved.number,saved.skills,saved.layout_version),saved.language)
	check(resumed.restore(saved),"Typed snapshot restores")
	check(var_to_bytes(active.snapshot())==var_to_bytes(resumed.snapshot()),"Resume preserves all gameplay and reward state")
	for i in 120:active.step(1.0/60,Vector2(.4,.2));resumed.step(1.0/60,Vector2(.4,.2))
	check(var_to_bytes(active.snapshot())==var_to_bytes(resumed.snapshot()),"Resumed simulation remains deterministic")
	var hint:=MazeRun.new(MazeLevel.new(3,{},3))
	hint.age=180.5;hint.use_hint();check(hint.hint_left==5,"Periodic hint offered")
	hint.hint_left=1;hint.use_hint();check(hint.hint_left==1,"Periodic hint cannot be extended by repeated taps")
	hint.age=360.5;hint.use_hint();check(hint.hint_left==5,"Next periodic hint available")
	var wrong:=MazeRun.new(MazeLevel.new(3,{},3))
	wrong.at=wrong.letters.back().at;wrong.step(.001,Vector2.ZERO)
	check(wrong.next_letter==0 and wrong.letters.size()==wrong.units.size(),"Wrong next unit remains in world")
	for mastery in [0.0,1.0]:
		for number in range(1,101):
			var variant:=MazeLevel.new(number,{"math":mastery,"words":mastery,"maze":mastery,"enemies":mastery},3)
			for gate in variant.gates:
				for exit_cell in variant.exits:check(variant.path(Vector2i.ZERO,exit_cell,{gate.key:true}).is_empty(),"Adaptive gate cannot be bypassed %d"%number)
			for lang in MazeWords.BANKS:check(MazeWords.units(lang,number,mastery).size()==MazeWords.units(lang,number).size(),"Adaptive vocabulary preserves scoring count")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures}
	var f:=FileAccess.open("res://qa-output/state-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("STATE VALIDATION ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
