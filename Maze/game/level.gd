class_name MazeLevel
extends RefCounted

const CELL := 6.0
const THEMES := ["Starlight Garden", "Candy Canopy", "Crystal Bay", "Cloud Kingdom", "Lantern Forest", "Golden Festival", "Coral Sunset", "Ocean Adventure", "Apple Orchard", "Rainbow Carnival"]
var generation := 6
var number: int
var seed_value: int
var size: int
var links: Dictionary = {}
var cells: Array[Vector2i] = []
var route: Array[Vector2i] = []
var gates: Array[Dictionary] = []
var exits: Array[Vector2i] = []
var pickups: Array[Dictionary] = []
var bot_cells: Array[Vector2i] = []
var timer := 0.0
var race := false
var theme := 0
var rng := RandomNumberGenerator.new()
var skills:Dictionary={}

func key(a: Vector2i, b: Vector2i) -> String:
	var aa := a.y * size + a.x
	var bb := b.y * size + b.x
	return "%d:%d" % [mini(aa, bb), maxi(aa, bb)]

func pos(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0, c.y * CELL)

func around(c: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var p: Vector2i = c + d
		if p.x >= 0 and p.y >= 0 and p.x < size and p.y < size:
			result.append(p)
	return result

func connected(a: Vector2i, b: Vector2i) -> bool:
	return links.has(key(a, b))

func path(a: Vector2i, b: Vector2i, blocked: Dictionary = {}) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [a]
	var previous: Dictionary = {a: a}
	var cursor := 0
	while cursor < queue.size():
		var c := queue[cursor]
		cursor += 1
		if c == b:
			break
		for p in around(c):
			if connected(c,p) and not blocked.has(key(c,p)) and not previous.has(p):
				previous[p] = c
				queue.append(p)
	var result: Array[Vector2i] = []
	if not previous.has(b):
		return result
	var at := b
	while at != a:
		result.push_front(at)
		at = previous[at]
	result.push_front(a)
	return result

func _init(id: int = 1, mastery:Dictionary={},layout_version:int=6) -> void:
	generation=layout_version
	skills=mastery.duplicate()
	number = clampi(id,1,100)
	seed_value = 10102026 + number * 7919
	rng.seed = seed_value
	size = 4 + mini(6, (number - 1) / 15)
	if generation>=2 and number>=3:size=maxi(5,size)
	if generation>=3 and number>=3:size=maxi(size,6 if number<=9 else 7 if number<=29 else 8)
	if generation>=5:size=maxi(size,7 if skills.get("explorer_mode",false) else 6)
	if generation>=6 and skills.get("explorer_mode",false):size=maxi(size,9)
	theme = (number - 1) / 10
	race = not skills.get("explorer_mode",false) if generation>=5 else number % 7 == 0
	for y in size:
		for x in size:
			cells.append(Vector2i(x,y))
	if generation==1:
		var stack: Array[Vector2i] = [Vector2i.ZERO]
		var visited: Dictionary = {Vector2i.ZERO: true}
		while not stack.is_empty():
			var at:Vector2i = stack.back()
			var choices: Array[Vector2i] = []
			for p in around(at):
				if not visited.has(p):
					choices.append(p)
			if choices.is_empty():
				stack.pop_back()
			else:
				var next := choices[rng.randi_range(0, choices.size()-1)]
				links[key(at,next)] = true
				visited[next] = true
				stack.append(next)
		# A distant exit with a bounded path: hard levels add decisions, not miles of walking.
		var target := Vector2i(size-1,size-1)
		var desired := 5 + number / 5
		var best_distance := 9999
		for c in cells:
			var candidate := path(Vector2i.ZERO,c)
			var cost := absi(candidate.size()-desired) + (0 if c.x+c.y>size else size)
			if cost < best_distance:
				best_distance = cost
				target = c
		route = path(Vector2i.ZERO,target)
		exits.append(target)
		var count := mini(route.size()-2, 1 + (number+4)/10)
		count = clampi(count,1,6)
		var blocked := {}
		for i in count:
			var index := clampi(1 + int(float(i+1)*(route.size()-2)/(count+1)),1,route.size()-1)
			var a := route[index-1]
			var b := route[index]
			var sum_max := mini(30, 3 + number/3)
			if not skills.is_empty():sum_max=maxi(3,roundi(sum_max*lerpf(.75,1.05,float(skills.get("math",0.0)))))
			var aa := rng.randi_range(1,sum_max)
			var bb := rng.randi_range(1,mini(sum_max,12))
			var subtract := number>16 and rng.randf()<.35
			if subtract and aa<bb:
				var swap := aa
				aa=bb
				bb=swap
			var answer := aa-bb if subtract else aa+bb
			var choices: Array[int] = [answer,answer+1+rng.randi_range(0,2)]
			if rng.randf()<.5:
				choices.reverse()
			gates.append({"id":i,"a":a,"b":b,"key":key(a,b),"prompt":"%d %s %d"%[aa,"−" if subtract else "+",bb],"answer":answer,"choices":choices})
			blocked[key(a,b)]=true
		# Add alternate paths only within each gated region, so loops cannot bypass learning gates.
		var regions := {}
		var region := 0
		for c in cells:
			if regions.has(c):
				continue
			var q: Array[Vector2i] = [c]
			regions[c]=region
			var head := 0
			while head<q.size():
				var at := q[head]
				head+=1
				for p in around(at):
					if connected(at,p) and not blocked.has(key(at,p)) and not regions.has(p):
						regions[p]=region
						q.append(p)
			region+=1
		for c in cells:
			for p in around(c):
				var loop_rate:=.11+number*.001
				if not skills.is_empty():loop_rate+=lerpf(.05,-.03,float(skills.get("maze",0.0)))
				if regions[c]==regions[p] and rng.randf()<loop_rate:
					links[key(c,p)]=true
		route=path(Vector2i.ZERO,target)
		for gate in gates:
			var alternatives:Array[Vector2i]=[]
			for neighbor in around(gate.a):
				if neighbor!=gate.b and regions[neighbor]==regions[gate.a]:alternatives.append(neighbor)
			alternatives.sort_custom(func(a,b):return int(route.has(a))<int(route.has(b)))
			if not alternatives.is_empty():
				gate["wrong_to"]=alternatives[0]
				links[key(gate.a,alternatives[0])]=true
			else:
				# Closely spaced gates may have no side room. The already travelled
				# corridor is the safe wrong turn; never point a sign at its own cell.
				var previous:=maxi(0,route.find(gate.a)-1)
				gate["wrong_to"]=route[previous]
		if number%4==0:
			for c in cells:
				if c!=target and not route.has(c) and regions[c]==regions[target] and c.distance_to(target)>1:
					exits.append(c)
					break
	else:
		build_forks()
	var places: Array[Vector2i] = route.duplicate()
	for i in mini(6,2+number/15):
		var c := places[mini(places.size()-1,1+i*maxi(1,places.size()/7))]
		pickups.append({"id":"balloon%d"%i,"kind":"balloon","cell":c,"offset":Vector3(-1.25,0,.8)})
	if number>=4:
		for i in 3:
			pickups.append({"id":"water%d"%i,"kind":"water","cell":places[mini(1+i*3,places.size()-1)],"offset":Vector3(1.25,0,-.8)})
	if number%3==0:
		for i in 1+(number/3)%3:
			pickups.append({"id":"map%d"%i,"kind":"map","cell":places[mini(2+i*2,places.size()-1)],"offset":Vector3(1.4,0,1.1)})
	if number>=5:
		for i in mini(4,1+number/25):
			var bot_cell:=places[mini(3+i*3,places.size()-1)]
			if not bot_cells.has(bot_cell):bot_cells.append(bot_cell)
	if number%10==0:
		timer=route.size()*CELL/2.5 + gates.size()*18 + 60

func gate_between(a:Vector2i,b:Vector2i) -> Dictionary:
	for g in gates:
		if g.key==key(a,b):
			return g
	return {}

func cell_for(p:Vector3)->Vector2i:
	return Vector2i(roundi(p.x/CELL),roundi(p.z/CELL))

func can_move(p:Vector3, solved:Dictionary)->bool:
	var c := cell_for(p)
	if not cells.has(c):
		return false
	var local := p-pos(c)
	var radius := .38
	for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var near:float = local.x*d.x+local.z*d.y
		if near > CELL/2-.3-radius:
			if not connected(c,c+d):
				return false
			var g:=gate_between(c,c+d)
			# In the two guided introductions both matching curtains are solid
			# until the arithmetic is answered. Exploration arches have no curtain.
			if generation>=2 and generation<5 and number<=2 and g.is_empty():
				for guided in gates:
					if key(c,c+d)==key(guided.a,guided.wrong_to):g=guided;break
			if not g.is_empty() and not solved.has(g.id):
				return false
	return true

func manifest()->Dictionary:
	var edges:=[]
	for c in cells:
		for p in around(c):
			if connected(c,p) and c.y*size+c.x<p.y*size+p.x:
				edges.append([c.x,c.y,p.x,p.y])
	var qs:=[]
	for g in gates:
		qs.append({"id":g.id,"from":[g.a.x,g.a.y],"to":[g.b.x,g.b.y],"wrongBranch":[g.get("wrong_to",g.a).x,g.get("wrong_to",g.a).y],"prompt":g.prompt,"answer":g.answer,"choices":g.choices})
	return {"level":number,"seed":seed_value,"theme":THEMES[theme],"size":size,"edges":edges,"questions":qs,"exits":exits.map(func(c):return [c.x,c.y]),"timer":timer,"race":race,"route":route.map(func(c):return [c.x,c.y]),"finishPoints":15+2*number}

# Growing-tree layouts have branching corridors from the beginning. Every answer
# fork is a real tree junction, and a wrong arm extends at least two cells before
# it ends. We never use the already-travelled entrance as a pretend wrong choice.
func build_forks()->void:
	var wanted:=clampi(1+(number+4)/10,1,6)
	var desired:=8+number/5
	if generation>=3 and number>=3:
		wanted=2 if number==3 else 3 if number<=5 else 4 if number<=9 else 5 if number<=19 else 6
		desired=13+(number-3)*2 if number<=9 else mini(38,24+(number-10)/4)
	if generation>=5:
		wanted=maxi(wanted,3 if skills.get("explorer_mode",false) else 2)
		desired=maxi(desired,22 if skills.get("explorer_mode",false) else 15)
	var chosen_route:Array[Vector2i]=[]
	var chosen_forks:Array[Dictionary]=[]
	var chosen_links:Dictionary={}
	var best_cost:=100000
	for attempt in 80:
		links.clear();branch_depth_cache.clear()
		var frontier:Array[Vector2i]=[Vector2i.ZERO]
		var visited:Dictionary={Vector2i.ZERO:true}
		while not frontier.is_empty():
			var slot:=rng.randi_range(0,frontier.size()-1) if rng.randf()<.65 else frontier.size()-1
			var at:=frontier[slot]
			var options:Array[Vector2i]=[]
			for other in around(at):
				if not visited.has(other):options.append(other)
			if options.is_empty():frontier.remove_at(slot);continue
			var next:=options[rng.randi_range(0,options.size()-1)]
			links[key(at,next)]=true;visited[next]=true;frontier.append(next)
		# This is a tree: one rooted traversal gives the same unique path to
		# every candidate exit. Do not repeat a whole BFS for each of them.
		var rooted:Dictionary={}
		if generation>=6:
			rooted[Vector2i.ZERO]=Vector2i.ZERO
			var queue:Array[Vector2i]=[Vector2i.ZERO];var head:=0
			while head<queue.size():
				var cell:=queue[head];head+=1
				for next in around(cell):
					if connected(cell,next) and not rooted.has(next):rooted[next]=cell;queue.append(next)
		for target in cells:
			var candidate:Array[Vector2i]=[]
			if generation>=6:
				var cursor:Vector2i=target
				while cursor!=Vector2i.ZERO:candidate.push_front(cursor);cursor=rooted[cursor]
				candidate.push_front(Vector2i.ZERO)
			else:candidate=path(Vector2i.ZERO,target)
			if candidate.size()<(12 if generation>=6 and skills.get("explorer_mode",false) else 6):continue
			var forks:Array[Dictionary]=[]
			for i in range(1,candidate.size()-2):
				var at:=candidate[i]
				var arms:Array[Vector2i]=[]
				for next in around(at):
					if not connected(at,next) or candidate.has(next):continue
					if generation>=6 and skills.get("explorer_mode",false):
						if branch_depth(at,next)>=5:arms.append(next)
					else:
						for c in around(next):
							if c!=at and connected(next,c):arms.append(next);break
				if not arms.is_empty():forks.append({"index":i,"arms":arms})
			if forks.is_empty():continue
			var cost:=absi(candidate.size()-desired)+maxi(0,wanted-forks.size())*14
			if cost<best_cost:
				best_cost=cost;chosen_route=candidate;chosen_forks=forks;chosen_links=links.duplicate()
		if best_cost<=1:break
	assert(not chosen_forks.is_empty(),"Every generated maze needs a real answer fork")
	links=chosen_links;branch_depth_cache.clear();route=chosen_route;exits=[route.back()];gates.clear()
	var count:=mini(wanted,chosen_forks.size())
	for i in count:
		var fork:=chosen_forks[int(float(i)*chosen_forks.size()/count)]
		var index:int=fork.index
		var sum_max:=mini(30,3+number/3)
		if not skills.is_empty():sum_max=maxi(3,roundi(sum_max*lerpf(.75,1.05,float(skills.get("math",0.0)))))
		var aa:=rng.randi_range(1,sum_max);var bb:=rng.randi_range(1,mini(sum_max,12))
		var subtract:=number>16 and rng.randf()<.35
		if subtract and aa<bb:var swap:=aa;aa=bb;bb=swap
		var answer:=aa-bb if subtract else aa+bb
		var arms:Array=[route[index+1]];arms.append_array(fork.arms.slice(0,2 if number>=(6 if generation>=3 else 21) else 1))
		var choices:Array[int]=[answer]
		for j in range(1,arms.size()):choices.append(answer+j*(1+rng.randi_range(0,1)))
		if choices.size()==3 and choices[1]==choices[2]:choices[2]+=1
		if generation>=3 and number>=3:
			# Neither the smallest value nor its screen position reveals the answer.
			choices=[answer]
			for j in range(1,arms.size()):
				var value:=maxi(0,answer+rng.randi_range(-3,3))
				while choices.has(value):value=maxi(0,answer+rng.randi_range(-4,4))
				choices.append(value)
		var ordered:=choices.duplicate()
		# Button order is independent of the correct route and of path geometry.
		if rng.randf()<.5:ordered.reverse()
		gates.append({"id":i,"a":route[index],"b":route[index+1],"key":key(route[index],route[index+1]),"prompt":"%d %s %d"%[aa,"−" if subtract else "+",bb],"answer":answer,"choices":ordered,"wrong_to":arms[1],"arms":arms,"values":choices,"walk_choice":generation>=5 or number>=3})

func branches(g:Dictionary)->Array:
	if g.has("arms"):return g.arms
	return [g.b,g.get("wrong_to",g.a)]

func branch_values(g:Dictionary)->Array:
	if g.has("values"):return g.values
	var result:Array=[g.answer]
	for v in g.choices:
		if v!=g.answer:result.append(v)
	return result

# Minimum distance to ANY leaf in this wrong arm, not just the longest path.
# Memoized per generated tree so every possible exit can be assessed cheaply.
var branch_depth_cache:Dictionary={}
func branch_depth(previous:Vector2i,at:Vector2i)->int:
	var id:="%d,%d>%d,%d"%[previous.x,previous.y,at.x,at.y]
	if branch_depth_cache.has(id):return int(branch_depth_cache[id])
	var shortest:=100000
	for next in around(at):
		if next!=previous and connected(at,next):shortest=mini(shortest,branch_depth(at,next))
	var depth:=1 if shortest==100000 else shortest+1
	branch_depth_cache[id]=depth
	return depth
