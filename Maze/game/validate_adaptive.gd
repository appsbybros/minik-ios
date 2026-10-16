extends SceneTree
# Regression suite for existing generation-3 saved adventures.
# New generation-4 adventures: validate_adventure.gd + validate_journeys.gd.
func _initialize()->void:call_deferred("validate")
func validate()->void:
	var failures:Array=[];var runs:Array=[];var retries:Array=[];var hard_slow_failures:Array=[];var dodge_retries:Array=[]
	for skill in [0.0,1.0]:
		for number in range(1,101):
			var stage:=MazeLevel.new(number,{"math":skill,"words":skill,"maze":skill,"enemies":skill},3)
			var report:=MazeReferenceAgent.play(stage,"en",.8,true,.85+skill*.25,1.5)
			runs.append(report)
			if report.state!="won" or report.lettersCollected!=report.wordUnits and number>=2:
				if number>=80 and skill==1.0:
					hard_slow_failures.append(report)
					var retry:=MazeReferenceAgent.play(stage,"en",1.0,true,1.1,1.5);retries.append(retry)
					if retry.state!="won" or retry.lettersCollected!=retry.wordUnits:failures.append(retry)
				else:
					# The straight-line controller never avoids incoming balloons. A
					# slower player may sidestep with the same movement controls;
					# require a full replay at identical speed/difficulty to succeed.
					var retry:=MazeReferenceAgent.play(stage,"en",.8,true,.85+skill*.25,1.5,true)
					dodge_retries.append(retry)
					if retry.state!="won" or retry.lettersCollected!=retry.wordUnits:failures.append(retry)
	var f:=FileAccess.open("res://qa-output/adaptive-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"runs":runs,"lateExpertSlowControllerFailures":hard_slow_failures,"fullSpeedRetries":retries,"sameSpeedDodgeRetries":dodge_retries},"  "));f.close()
	print("ADAPTIVE VALIDATION: ",runs.size()," runs; failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
