extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);printerr(title)
func make(number:int,lang:String="en",tier_value:int=0)->MazeRun:
	return MazeRun.new(MazeLevel.new(number,{},4),lang,{"tier":tier_value,"source":"en" if lang!="en" else "he","mode":"mixed"})
func take(run:MazeRun,id:int)->void:
	run.at=run.letters[id].at;run.adventure.collect_letters()
func collect_word(run:MazeRun,reverse:bool=false)->void:
	var desired:Array=run.units.duplicate()
	if reverse:desired.reverse()
	for token in desired:
		for l in run.letters:
			if l.unit==token and not l.picked:
				l.returned=false;l.cooldown=0.0;take(run,l.index);break
func _initialize()->void:call_deferred("validate")
func validate()->void:
	for lang in MazeWords.NAMES:
		for tier_value in range(4):
			var run:=make(8,lang,tier_value)
			check(run.letters.size()>=run.units.size(),"All word units are available "+lang)
			var wrong:=-1
			for l in run.letters:
				if not run.units.has(l.unit):wrong=l.index;break
			if wrong>=0:
				take(run,wrong);check(run.adventure.tray.has(wrong),"Wrong letter is collectable "+lang)
				check(not run.adventure.tray_valid()[0],"Wrong letter is visibly invalid "+lang)
				if tier_value>0:run.adventure.remove_letter(0)
			collect_word(run,tier_value==0)
			if tier_value==0 and wrong>=0:
				check(not run.adventure.complete,"Wrong extra prevents green word")
				run.adventure.remove_letter(run.adventure.tray.find(wrong))
			check(run.adventure.complete,"Word completes, including duplicate units "+lang+str(tier_value))
			check(run.adventure.flash_left==30,"First night flare is the word reward")
			var points:=run.provisional;run.adventure.collect_letters();run.adventure.evaluate_word()
			check(run.provisional==points,"Word reward pays once")
			var snapshot:=run.snapshot();var restored:=make(8,lang,tier_value)
			check(restored.restore(snapshot),"Adventure snapshot restores "+lang)
			check(var_to_bytes(restored.snapshot())==var_to_bytes(snapshot),"Adventure snapshot preserves tray, actors and light")
			for l in run.letters:
				check(run.level.can_move(l.at,run.solved),"Pickup fits within a corridor")
	var ordered:=make(3,"he",1)
	var last:=str(ordered.units.back())
	for l in ordered.letters:
		if l.unit==last:take(ordered,l.index);break
	check(not ordered.adventure.tray_valid()[0],"Out-of-order correct letter is red")
	var id:=int(ordered.adventure.tray[0]);ordered.adventure.remove_letter(0);ordered.age+=3;ordered.adventure.collect_letters()
	check(not ordered.adventure.tray.has(id),"Removed letter waits until child walks away")
	ordered.at+=Vector3(1.5,0,0);ordered.adventure.collect_letters();collect_word(ordered)
	check(ordered.adventure.complete,"A corrected ordered word completes")
	var wall:=make(4)
	check(wall.adventure.kind=="wall" and not wall.level.race and wall.level.timer==0,"Word wall has no timed/rival conflict")
	var gate:Dictionary=wall.level.gates.back();wall.at=wall.level.pos(gate.a)
	# Earlier gates are fixture setup; test the word lock itself at the final wall.
	for g in wall.level.gates:
		if g.id!=gate.id:wall.solved[g.id]=true
	check(not wall.answer(gate.id,gate.answer),"Wall requires collected word")
	collect_word(wall,true);wall.at=wall.level.pos(gate.a)
	check(wall.answer(gate.id,gate.answer),"Collected word can open wall")
	var ride:=make(13);ride.solved.clear()
	var gate_index:=ride.level.route.find(ride.level.gates[0].a)
	ride.at=ride.level.pos(ride.level.route[maxi(0,gate_index-1)])
	for i in range(4):
		ride.adventure.carrier.state="approach";ride.adventure.carrier.at=ride.at+Vector3(0,1.4,0);ride.adventure.carrier.time=0.0
		ride.adventure.step_carrier(.01)
		check(ride.adventure.carrier.state=="carry","Carrier contact starts visible ride")
		var drop_index:=ride.level.route.find(ride.level.cell_for(ride.adventure.carrier.to))
		check(drop_index<=gate_index,"Carrier cannot skip unopened gate")
		var snap:=ride.snapshot();var resumed:=make(13);check(resumed.restore(snap),"Mid-flight pause restores")
		ride.adventure.step_carrier(4.1);check(ride.level.can_move(ride.at,ride.solved),"Carrier drops on legal ground")
	var bot_run:=make(6)
	var bot:Dictionary=bot_run.bots[0];var before:Vector3=bot.at
	bot_run.adventure.splash_bot(bot,false);bot_run.adventure.step_bots(.016)
	check(bot.at.distance_to(before)<.1 and bot.away>0 and bot.mood=="wet","Splash retreats continuously, no teleport")
	var profile:=MazeProfile.new("user://adventure-check-profile.json","en")
	profile.data.receipts=[];profile.data.word_auto=true;profile.data.word_levels={};profile.data.learning="en"
	var clean:=make(3);collect_word(clean,true);clean.state="won";profile.finish(clean)
	check(MazeLessons.tier(profile.data)==1,"Clean word advances next adventure")
	profile.finish(clean);check(MazeLessons.tier(profile.data)==1,"Duplicate result cannot advance difficulty")
	profile.data.word_auto=false;profile.data.word_tier=2;check(MazeLessons.tier(profile.data)==2,"Manual difficulty wins over automatic")
	for generation in [1,2,3]:
		var legacy:=MazeRun.new(MazeLevel.new(3,{},generation));var snap:=legacy.snapshot();var copy:=MazeRun.new(MazeLevel.new(3,{},generation))
		check(copy.restore(snap) and copy.adventure==null,"Legacy save retains original rules "+str(generation))
	var result:={"passed":failures.is_empty(),"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute("res://qa-output")
	FileAccess.open("res://qa-output/adventure-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("ADVENTURE CHECKS ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
