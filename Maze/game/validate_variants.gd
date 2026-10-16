extends SceneTree
# Regression suite for existing generation-3 saved adventures.
# New generation-4 adventures: validate_adventure.gd + validate_journeys.gd.
var errors:Array[String]=[]
func check(ok:bool,reason:String)->void:
	if not ok:errors.append(reason);printerr(reason)
func _initialize()->void:call_deferred("validate")
func validate()->void:
	var results:Array=[]
	for number in range(1,101):
		var stage:=MazeLevel.new(number,{},3)
		var solved:={}
		for g in stage.gates:solved[g.id]=true
		for lang in MazeWords.BANKS:
			var sample:=MazeRun.new(stage,lang)
			for i in sample.letters.size():
				var letter:Dictionary=sample.letters[i]
				check(stage.can_move(letter.at,solved),"Letter behind wall: %d %s %d"%[number,lang,i])
				for j in range(i):check(letter.at.distance_to(sample.letters[j].at)>.85,"Overlapping letters: %d %s %d/%d"%[number,lang,i,j])
		var scenario:=MazeReferenceAgent.play(stage,"en",1.0,true,1.0,.8)
		results.append(scenario)
		check(scenario.state=="won","Word/reference stage %d %s hits%d"%[number,scenario.state,scenario.hits])
		if number>=2:check(scenario.lettersCollected==scenario.wordUnits,"Incomplete optional word in reference %d"%number)
		# A young learner may need extra reading time and move at 70% of maximum.
		if number<=20:
			var slow:=MazeReferenceAgent.play(stage,"en",.7,true,.85,2.5)
			results.append(slow)
			check(slow.state=="won","Slower early learner %d %s"%[number,slow.state])
	var f:=FileAccess.open("res://qa-output/variant_validation.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":errors.is_empty(),"failures":errors,"runs":results},"  "));f.close()
	print("MAZE VARIANTS: ",results.size()," runs; failures=",errors.size())
	quit(0 if errors.is_empty() else 1)
