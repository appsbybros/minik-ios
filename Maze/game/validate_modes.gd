extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,why:String)->void:
 checks+=1
 if not ok:failures.append(why);printerr(why)
func _initialize()->void:call_deferred("validate")
func validate()->void:
 for mode in ["child","explorer"]:
  for n in range(1,101):
   var stage:=MazeLevel.new(n,{"explorer_mode":mode=="explorer"},6)
   var r:=MazeRun.new(stage,"en",{"game_mode":mode,"subjects":["math","en"] if mode=="child" else MazeCurriculum.SUBJECTS.keys(),"source":"he","question_language":"en"})
   check(stage.route.size()>=12,"Navigable nontrivial route %s %d"%[mode,n])
   check(stage.gates.size()>=2,"Several genuine forks %s %d"%[mode,n])
   check(r.letters.is_empty(),"No letter pickups %s %d"%[mode,n])
   check(stage.race==(mode=="child"),"Only child mode has a rival %d"%n)
   for g in stage.gates:
    if mode=="explorer":
     for arm in stage.branches(g).slice(1):check(stage.branch_depth(g.a,arm)>=5,"No short wrong-path leaf %d"%n)
    check(g.walk_choice,"Walk through answers %d"%n)
    check(stage.path(Vector2i.ZERO,stage.exits[0],{g.key:true}).is_empty(),"Cannot bypass required gate %d"%n)
    var answers:Array=stage.branch_values(g).map(func(v):return MazeLessons.answer_text(g,v))
    check(answers.size()==stage.branches(g).size() and answers.size()==Array(set_values(answers)).size(),"Unique displayed options %d"%n)
 var child:=MazeRun.new(MazeLevel.new(3,{},6),"en",{"game_mode":"child","subjects":["math"]})
 child.bots.clear();var g:Dictionary=child.level.gates[0]
 var direction:Vector3=(child.level.pos(g.arms[1])-child.level.pos(g.a)).normalized()
 child.at=child.level.pos(g.a)+direction*2.1;child.step(.05,Vector2(direction.x,direction.z))
 check(child.glue_left>4.9 and child.hits==1,"Wrong branch causes exactly one life and five seconds of glue")
 var anchor:=child.at;var fox:=child.fox_at
 for i in 40:child.step(.05,Vector2(direction.x,direction.z))
 check(child.at.distance_to(anchor)<.66,"Glue permits only small movement")
 check(child.hits==1,"Holding wrong direction cannot remove repeated lives")
 check(child.glue_left>2.8 and child.glue_left<3.1,"Glue uses active gameplay time")
 var saved:=child.snapshot();var restored:=MazeRun.new(MazeLevel.new(3,{},6),"en",child.adventure.settings)
 check(restored.restore(saved),"Restore a glued run")
 check(restored.glue_left==child.glue_left,"Glue survives restore without restarting penalty")
 for i in 70:child.step(.05,Vector2.ZERO)
 check(child.glue_left==0,"Glue releases after five seconds")
 check(child.fox_at.distance_to(fox)>.1,"Rival keeps moving during penalty")
 for level_number in [1,5,30,100]:
  var race:=MazeRun.new(MazeLevel.new(level_number,{},6),"en",{"game_mode":"child","subjects":["math"]})
  race.bots.clear();race.attempt_id="route-check-%d"%level_number
  check(race.fox_wait==0,"Rival starts with the child at level %d"%level_number)
  var start:=race.fox_at
  for i in 60:race.step(.05,Vector2.ZERO)
  check(race.fox_at.distance_to(start)>2,"Rival moves promptly at level %d"%level_number)
  for i in 6000:
   if race.state=="lost":break
   race.step(.05,Vector2.ZERO)
  check(race.state=="lost","Rival can finish the route without getting lost at level %d"%level_number)
 child.at=child.level.pos(g.a);child.answer(g.id,g.answer);var points:=child.provisional
 child.hits=2;child.invulnerable=0;child.hit()
 check(child.state=="lost" and child.hits==3,"All lives lost ends this attempt")
 var frozen:=child.fox_at
 for i in 100:child.step(.05,Vector2.ONE)
 check(child.fox_at==frozen,"Rival cannot continue after disqualification")
 var retry:=MazeRun.new(MazeLevel.new(child.level.number,child.level.skills),child.language_code,child.adventure.settings)
 check(retry.at==Vector3.ZERO and retry.fox_index==0 and retry.fox_wait==0,"Both racers restart together from the beginning")
 check(retry.solved.is_empty() and retry.hits==0 and retry.age==0 and retry.provisional==0,"Retry resets gates, lives, clock and provisional points")
 var explorer:=MazeRun.new(MazeLevel.new(1,{"explorer_mode":true},6),"en",{"game_mode":"explorer","subjects":["science"],"question_language":"he"})
 explorer.events.clear();explorer.at=explorer.level.pos(explorer.level.gates[0].a);explorer.wrong_branch(explorer.level.gates[0])
 check(explorer.events.is_empty(),"Wrong navigation answer has no immediate message or sound")
 check(explorer.glue_left==0 and explorer.hits==0,"Explorer wrong path has no child glue penalty")
 check(explorer.level.gates[0].lesson=="knowledge" and explorer.level.gates[0].display_prompt.contains("?"),"Explorer uses actual question corpus")
 var score:=explorer.provisional
 var eg:Dictionary=explorer.level.gates[0]
 explorer.answer(eg.id,eg.answer)
 check(explorer.events.is_empty() and explorer.provisional==score,"Correct navigation answer has no immediate score or sound clue")
 check(explorer.nearby_gate().get("id",-1)==eg.id,"Navigation prompt remains near either chosen gate")
 var profile:=MazeProfile.new("user://mode-validation.json");profile.data.bests={"56":30};profile.data.unlocked=57;profile.data.played=true;profile.data.game_mode="explorer";profile.reset_progress()
 check(profile.data.bests.is_empty() and profile.data.unlocked==1 and not profile.data.played and profile.data.game_mode=="explorer","Reset progression retains preferences")
 var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
 var f:=FileAccess.open("res://qa-output/modes-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 print("MODES ",JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func set_values(values:Array)->Array:
 var out:Array=[]
 for v in values:
  if not out.has(v):out.append(v)
 return out
