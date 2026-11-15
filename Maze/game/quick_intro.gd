class_name MazeQuickIntro
extends RefCounted

# A disposable practice run uses the real movement, gates and throwing code.
# It never becomes a normal level attempt or awards progression.
var step_index:=0
var start_at:=Vector3.ZERO
var map_opened:=false

func prepare(run:MazeRun)->void:
	run.level.race=false
	run.level.timer=0
	run.level.exits.clear()
	run.bots.clear()
	run.adventure=null
	run.learning.clear()
	run.level.pickups.clear()
	run.units.clear()
	run.letters.clear()
	run.ammo=0
	var gate:Dictionary=run.level.gates[0]
	var index:=run.level.route.find(gate.a)
	run.at=run.level.pos(run.level.route[maxi(0,index-1)])
	start_at=run.at
	run.events.clear()

func observe(run:MazeRun)->bool:
	var previous:=step_index
	if step_index==0 and run.at.distance_to(start_at)>=1.4:step_index=1
	elif step_index==1 and not run.solved.is_empty():
		step_index=2
		run.ammo=maxi(3,run.ammo)
	# Repeated wrong choices are safe practice; the normal game is unchanged.
	if run.hits>0:run.hits=0
	return previous!=step_index

func thrown(success:bool)->bool:
	if step_index!=2 or not success:return false
	step_index=3
	return true

func map_changed(visible:bool)->bool:
	if step_index!=3:return false
	if visible:map_opened=true
	elif map_opened:step_index=4;return true
	return false

func instruction()->String:
	return [
		"Drag the circle, or swipe the maze, to move Minik. Try moving a little!",
		"Walk to the question on the floor. Then walk through the gate with the correct answer.",
		"Your movement circle is now a water balloon. Tap its centre once to throw!",
		"Open Map. The pink dot is you. Tap the X on the map when you are ready.",
		"You moved, chose a gate, threw a balloon and used the map. Ready to explore!"
	][step_index]
