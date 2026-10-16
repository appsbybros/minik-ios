extends SceneTree
var failures:Array=[]
var checks:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);printerr(message)
func _initialize()->void:call_deferred("validate")
func make_run(subjects:Array=["math"],mode:String="child",progress:Dictionary={},manual:Dictionary={},automatic:bool=true)->MazeRun:
	return MazeRun.new(MazeLevel.new(55,{"explorer_mode":mode=="explorer"}),"en",{"question_version":1,"question_auto":automatic,"question_progress":progress,"question_manual_levels":manual,"game_mode":mode,"subjects":subjects,"source":"en","question_language":"en"})
func choose(r:MazeRun,index:int,correct:bool)->void:
	var g:Dictionary=r.level.gates[index];r.at=r.level.pos(g.a)
	if correct:r.answer(g.id,g.answer)
	else:r.wrong_branch(g);r.glue_left=0
func validate()->void:
	var script=load("res://world.gd");check(script!=null,"World parses")
	var r:=make_run();var g0:Dictionary=r.level.gates[0];var seen:Dictionary=r.level.gates[2].duplicate(true)
	MazeLearning.mark_seen(r,int(seen.id));choose(r,0,true)
	check(int(r.learning.progress["child:en:math"].level)==1,"One correct answer does not increase")
	choose(r,1,true)
	check(int(r.learning.progress["child:en:math"].level)==2,"Two correct answers increase")
	check(r.level.gates[2]==seen,"Already seen question and answer text remain fixed")
	check(int(r.level.gates[3].difficulty)==2,"Unseen gate updates immediately")
	var saved:=r.snapshot();var resumed:=MazeRun.new(MazeLevel.new(55,r.level.skills),"en",r.adventure.settings)
	check(resumed.restore(saved),"Adaptive resume accepted")
	check(resumed.learning==r.learning and resumed.level.gates==r.level.gates,"Resume retains exact questions, streaks and seen gates")
	var before:=r.learning.duplicate(true);r.solved.erase(g0.id);choose(r,0,true)
	check(r.learning==before,"Same gate cannot farm mastery")
	var down:=make_run(["math"],"child",{"child:en:math":{"level":3,"right":0,"wrong":0}})
	choose(down,0,false);choose(down,0,true)
	check(int(down.learning.progress["child:en:math"].wrong)==1,"Correct retry does not cancel first-attempt mistake")
	choose(down,1,false)
	check(int(down.learning.progress["child:en:math"].level)==2,"Two first-attempt mistakes decrease difficulty")
	var mixed:=make_run(["math","he"])
	for g in mixed.level.gates:
		MazeLearning.record(mixed,g,g.subject=="math")
	check(int(mixed.learning.progress["child:en:math"].level)>1 and int(mixed.learning.progress["child:en:he"].level)==1,"Subjects adapt independently and lower bound holds")
	var manual:=make_run(["math"],"child",{}, {"child:en:math":5},false)
	for g in manual.level.gates:MazeLearning.record(manual,g,true)
	check(manual.learning.progress.is_empty() and int(manual.level.gates[0].difficulty)==5,"Manual difficulty stays fixed")
	check(str(manual.level.gates[0].display_prompt).contains("×"),"Manual level five produces multiplication")
	var topology:=manual.level.links.duplicate(true) if "links" in manual.level else {}
	for subject in MazeWords.STUDY_CODES:
		for difficulty in range(1,5):
			var sample:=make_run([subject],"child",{}, {"child:en:"+subject:difficulty},false)
			for g in sample.level.gates:
				check(g.subject==subject and g.lesson!="math" and g.display_choices.size()==sample.level.branches(g).size(),"Language-only remains language-only %s %d"%[subject,difficulty])
	for subject in MazeCurriculum.SUBJECTS:
		var options:={"game_mode":"explorer","question_language":"en"}
		for difficulty in range(1,MazeLearning.maximum(options,subject)+1):
			var sample:=make_run([subject],"explorer",{}, {"explorer:en:"+subject:difficulty},false)
			for g in sample.level.gates:
				var matches:Array=MazeCurriculum.questions(options,subject).filter(func(q):return q.id==g.question_id)
				check(matches.size()==1 and int(matches[0].level)==difficulty,"Question bank respects authored difficulty %s %d"%[subject,difficulty])
	var nav:=make_run(["science"],"explorer");choose(nav,0,false)
	check(nav.events.is_empty() and nav.hits==0,"Navigation adaptation reveals no wrong-answer feedback")
	var legacy:=MazeRun.new(MazeLevel.new(3),"en",{"game_mode":"child","subjects":["math"]})
	var restored:=MazeRun.new(MazeLevel.new(3),"en",legacy.adventure.settings)
	check(restored.restore(legacy.snapshot()) and restored.learning.is_empty(),"Legacy saves retain their original questions")
	# The world's fallback options come from today's profile even for an old
	# save without an adventure settings block. Old gates must stay legacy.
	var modern:=MazeProfile.new("user://learning-legacy-defaults.json")
	for generation in [1,2,3,4]:
		var old_run:=MazeRun.new(MazeLevel.new(3,{},generation),"en",MazeLessons.options(modern.data))
		check(old_run.learning.is_empty(),"Legacy generation has no new question controller %d"%generation)
		var gate:Dictionary=old_run.level.gates[0];old_run.at=(old_run.level.pos(gate.a)+old_run.level.pos(gate.b))/2
		check(old_run.answer(gate.id,gate.answer),"Old gate can still be answered %d"%generation)
		var old_copy:=MazeRun.new(MazeLevel.new(3,{},generation),"en",MazeLessons.options(modern.data))
		check(old_copy.restore(old_run.snapshot()),"Old save restores with modern profile fallback %d"%generation)
	var profile:=MazeProfile.new("user://learning-test.json");profile.data.question_progress={};profile.checkpoint(r)
	var loaded:=MazeProfile.new("user://learning-test.json")
	check(loaded.data.question_progress==r.learning.progress,"Progress persists between app launches")
	var repeat:=make_run(["math"],"child",loaded.data.question_progress)
	check(int(repeat.level.gates[0].difficulty)==2,"Retry uses retained question mastery")
	var output:={"passed":failures.is_empty(),"checks":checks,"failures":failures}
	FileAccess.open("res://qa-output/learning-validation.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print(JSON.stringify(output));quit(0 if failures.is_empty() else 1)
