extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func _initialize()->void:
	var r:=MazeRun.new(MazeLevel.new(3),"en",{"game_mode":"child","subjects":["math"]})
	var a:=r.level.pos(r.level.route[1]);var axis:=(r.level.pos(r.level.route[2])-a).normalized();var side:=Vector3(-axis.z,0,axis.x)*1.1
	r.age=10;r.at=a+axis*3;r.fox_at=a+axis*1+side
	r.check_overtake(r.at,r.fox_at);check(r.laugh_armed and r.events.is_empty(),"Being behind arms, without sound")
	r.fox_at=a+axis*4+side;r.check_overtake(r.at,r.fox_at-axis*.05)
	check(r.events.size()==1 and r.events[0].kind=="rival_laugh","Passing produces one laugh")
	for i in 100:r.check_overtake(r.at,r.fox_at)
	check(r.events.size()==1,"Staying ahead never repeats")
	r.fox_at=a+axis+side;r.check_overtake(r.at,r.fox_at);r.fox_at=a+axis*4+side;r.check_overtake(r.at,r.fox_at-axis*.05)
	check(r.events.size()==1,"Rapid recrossing respects cooldown")
	r.age=17;r.fox_at=a+axis+side;r.check_overtake(r.at,r.fox_at);r.fox_at=a+axis*4+side;r.check_overtake(r.at,r.fox_at-axis*.05)
	check(r.events.size()==2,"A later genuine overtake laughs again")
	r.age=25;r.fox_at=a+axis+side;r.check_overtake(r.at,r.fox_at);r.fox_at=a+axis*4+side;r.check_overtake(r.at+Vector3(5,0,0),r.fox_at)
	check(r.events.size()==2 and not r.laugh_armed,"Teleport does not count")
	var copy:=MazeRun.new(MazeLevel.new(3),"en",r.adventure.settings)
	check(copy.restore(r.snapshot()) and copy.laugh_after==r.laugh_after and copy.laugh_armed==r.laugh_armed,"Cooldown and armed state survive resume")
	var old:=r.snapshot();old.erase("laugh_after");old.erase("laugh_armed")
	check(copy.restore(old),"Old saves without sound fields still load")
	r.level.race=false;r.laugh_armed=true;r.check_overtake(r.at,r.fox_at);check(r.events.size()==2,"No-rival mode stays silent")
	var stream:=AudioStreamWAV.load_from_file("res://audio/rival-chirpy-laugh.wav")
	check(stream!=null and stream.get_length()>1 and stream.get_length()<1.5,"Short sound loads through Android's loose-resource path")
	var result:={"passed":failures.is_empty(),"checks":checks,"failures":failures}
	FileAccess.open("res://qa-output/laugh-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
