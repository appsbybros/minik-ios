extends SceneTree
func _initialize()->void:call_deferred("make")
func make()->void:
	var r:=MazeRun.new(MazeLevel.new(5),"en",{"tier":0,"source":"he","mode":"mixed"})
	r.bots.resize(1);r.bots[0].at=Vector3(1.55,0,0);r.bots[0].home=Vector3(1.55,0,0);r.bots[0].target=r.bots[0].at;r.bots[0].rest=8.0;r.bots[0].throw=18.0
	r.adventure.helper.state="offer";r.adventure.helper.at=Vector3(-1.7,0,0);r.adventure.helper["entrance"]=Vector3(-1.7,0,1.6);r.adventure.helper["offered_at"]=r.at;r.adventure.helper["offer_distance"]=1.7;r.adventure.helper.wait=0.0
	FileAccess.open("res://qa-output/contact-fixture.bin",FileAccess.WRITE).store_var(r.snapshot())
	print("Contact fixture saved (explicit QA state, not normal play).");quit()
