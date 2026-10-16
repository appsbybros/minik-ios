extends SceneTree
var failures:Array=[]
var rows:Array=[]
func _initialize()->void:call_deferred("test")
func test()->void:
	for n in range(1,101):
		var level:=MazeLevel.new(n)
		var r:=MazeRun.new(level,"en",{"tier":(n/12)%4,"source":"he","mode":"mixed"})
		r.attempt_id="journey-%d"%n
		var goals:Array=[]
		for p in level.pickups:
			if p.kind=="water" and level.route.find(p.cell)<=2:goals.append(level.pos(p.cell)+p.offset)
		# Ordered letter goals require real backtracking, not fixture teleportation.
		var used:Array=[]
		for unit in r.units:
			for l in r.letters:
				if l.unit==unit and not used.has(l.index):goals.append(l.at);used.append(l.index);break
		goals.append(level.pos(level.exits[0]))
		var frames:=0;var index:=0;var path:Array=[];var last_cell:=Vector2i(-1,-1);var last_throw:=-10.0
		while r.state=="playing" and frames<54000:
			frames+=1
			if index>=goals.size():break
			var target:Vector3=goals[index]
			if r.at.distance_to(target)<.19:index+=1;path.clear();continue
			var c:=level.cell_for(r.at)
			if path.is_empty() or c!=last_cell:
				path.clear();last_cell=c
				var cells:=level.path(c,level.cell_for(target))
				# Follow centre lines before turning: never cut through a wall corner.
				if cells.size()>1:
					var center:=level.pos(c);var next:=level.pos(cells[1]);var axis:=next-center
					if absf(axis.x)>.1 and absf(r.at.z-center.z)>.12:path.append(center)
					elif absf(axis.z)>.1 and absf(r.at.x-center.x)>.12:path.append(center)
					path.append(next)
				else:path.append(target)
			var g:=r.nearby_gate()
			if not g.is_empty() and not g.get("walk_choice",false):r.answer(g.id,g.answer)
			if not path.is_empty() and r.at.distance_to(path[0])<.14:path.pop_front()
			if path.is_empty():continue
			var delta:Vector3=path[0]-r.at
			var dir:=Vector2(delta.x,delta.z).normalized()
			if r.ammo>0 and r.age-last_throw>1:
				for b in r.bots:
					if b.away<=0 and b.at.distance_to(r.at)<8 and r.clear_line(r.at,b.at):
						var aim:Vector3=(b.at-r.at).normalized();r.step(1.0/60,Vector2(aim.x,aim.z)*.01);r.throw_water();last_throw=r.age;break
			r.step(1.0/60,MazeReferenceAgent.avoid_balloon(r,dir,1.0))
		var row:={"level":n,"kind":r.adventure.kind,"tier":r.adventure.tier,"state":r.state,"seconds":r.age,"hits":r.hits,"wordComplete":r.adventure.complete,"letters":r.next_letter,"solved":r.solved.size(),"gates":level.gates.size(),"at":[r.at.x,r.at.z],"goal":index,"frames":frames}
		rows.append(row)
		if r.state!="won":failures.append(row);printerr(JSON.stringify(row))
	var report:={"passed":failures.is_empty(),"failures":failures,"journeys":rows}
	var file:=FileAccess.open("res://qa-output/adventure-journeys.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("ADVENTURE JOURNEYS ",rows.size()," failures=",failures.size());quit(0 if failures.is_empty() else 1)
