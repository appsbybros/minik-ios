extends SceneTree
func _initialize()->void:
	var entries:=[]
	for number in range(1,101):
		var level:=MazeLevel.new(number);var manifest:=level.manifest()
		manifest.version=1;manifest.spawn=[0,0];manifest.cellSize=MazeLevel.CELL
		manifest.words={};manifest.pickups=[];manifest.bots=[]
		for language in MazeWords.BANKS:
			var run:=MazeRun.new(level,language)
			manifest.words[language]={"units":run.units,"optional":true,"cells":run.letters.map(func(l):var c:=level.cell_for(l.at);return [c.x,c.y])}
		for p in level.pickups:manifest.pickups.append({"id":p.id,"kind":p.kind,"cell":[p.cell.x,p.cell.y],"offset":[p.offset.x,p.offset.z]})
		var sample:=MazeRun.new(level,"en")
		for b in sample.bots:var c:=level.cell_for(b.at);manifest.bots.append({"id":b.id,"name":b.name,"spawn":[c.x,c.y],"repelledSeconds":8,"tagCooldown":5})
		var balloons:=level.pickups.filter(func(p):return p.kind=="balloon").size()
		manifest.scoreUpperBound=15+2*number+2*level.gates.size()+balloons+2*sample.bots.size()+(sample.units.size()+6 if number>=2 else 0)
		manifest.map={"manual":true,"periodicSeconds":180,"activationWindow":10,"hintSeconds":5}
		entries.append(manifest)
	var f:=FileAccess.open("res://qa-output/level_manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(entries,"  "));f.close()
	print("Exported 100 full level manifests");quit()
