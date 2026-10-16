class_name MazeRun
extends RefCounted

var level: MazeLevel
var at := Vector3.ZERO
var facing := Vector3.FORWARD
var age := 0.0
var hits := 0
var invulnerable := 0.0
var ammo := 0
var provisional := 0
var solved: Dictionary = {}
var mistakes: Dictionary = {}
var collected: Dictionary = {}
var repelled: Dictionary = {}
var bots: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var units: Array = []
var letters: Array[Dictionary] = []
var next_letter := 0
var hint_tokens := 0
var hint_left := 0.0
var state := "playing"
var events: Array[Dictionary] = []
var fox_at := Vector3.ZERO
var fox_index := 0
var fox_wait := 18.0
var fox_visited: Dictionary = {}
var fox_path: Array[Vector2i] = []
var fox_choices:Dictionary={}
var fox_detour:Array[Vector2i]=[]
var fox_detour_index:=0
var enemy_factor := 1.0
var throw_cooldown := 0.0
var attempt_id:=Crypto.new().generate_random_bytes(16).hex_encode()
var language_code:="en"
var periodic_hint_used:=0
var adventure:MazeAdventure
var glue_left:=0.0
var glue_anchor:=Vector3.ZERO
var glue_gate:=-1
var glue_cycle:=0
var gate_retry:Dictionary={}
var checkpoint_at:=Vector3.ZERO
var checkpoint_gate:=-1
var recovery_count:=0
var learning:Dictionary={}
var laugh_armed:=false
var laugh_after:=0.0

func _init(stage:MazeLevel,language:String="en",options:Dictionary={}) -> void:
	level=stage
	language_code=language
	at=stage.pos(Vector2i.ZERO)
	units=MazeWords.units(language,stage.number,float(stage.skills.get("words",-1)))
	if stage.number>=2:
		var used_cells:Dictionary={}
		for i in units.size():
			var index:=mini(stage.route.size()-2,1+int(float(i)*(stage.route.size()-3)/maxi(1,units.size()-1)))
			var cell:Vector2i=stage.route[index]
			var slot:=int(used_cells.get(cell,0));used_cells[cell]=slot+1
			# Distinct blocks even when a long localized word shares a short maze.
			# The final block precedes the exit, so finishing never steals the word.
			letters.append({"index":i,"unit":units[i],"at":stage.pos(cell)+Vector3(1.4-.9*(slot/3),0,(slot%3-1)*1.1)})
	for i in stage.bot_cells.size():
		var origin:=stage.pos(stage.bot_cells[i])
		bots.append({"id":i,"name":["Flare","Kyra","June","Gaya"][i%4],"at":origin,"home":origin,"away":0.0,"throw":6.0+i*2,"target":origin,"think":0.0,"tag_wait":0.0,"windup":0.0,"aim":Vector3.ZERO})
	fox_at=at+fox_lane(0) if stage.generation>=5 else at+Vector3(1.1,0,0)
	fox_visited[Vector2i.ZERO]=true
	fox_path=[Vector2i.ZERO]
	if stage.generation>=5:fox_wait=0.0
	if stage.generation>=4:adventure=MazeAdventure.new(self,options)
	learning=MazeLearning.new_state(options) if stage.generation>=5 else {};MazeLearning.capture(self)
	settle_loaded_bodies()

func emit(kind:String,data:Dictionary={}) -> void:
	data["kind"]=kind
	events.append(data)
	if events.size()>50:
		events.pop_front()

func step(delta:float,direction:Vector2) -> void:
	if state!="playing":
		return
	var previous_at:=at;var previous_fox:=fox_at
	var dt:=clampf(delta,0,.05)
	age+=dt
	for g in level.gates:
		if at.distance_to(level.pos(g.a))<9:MazeLearning.mark_seen(self,int(g.id))
	glue_left=maxf(0,glue_left-dt)
	if adventure!=null and adventure.carrier.state=="carry":direction=Vector2.ZERO
	invulnerable=maxf(0,invulnerable-dt)
	throw_cooldown=maxf(0,throw_cooldown-dt)
	hint_left=maxf(0,hint_left-dt)
	if level.timer>0 and age>=level.timer:
		fail("time")
		return
	# Crossing a marked arm is the answer on exploration levels. The same
	# threshold applies to all arms; merely looking at a fork reveals nothing.
	for g in level.gates:
		if not g.get("walk_choice",false) or solved.has(g.id):continue
		var arms:=level.branches(g)
		for i in arms.size():
			var forward:=(level.pos(arms[i])-level.pos(g.a)).normalized()
			var local:=at-level.pos(g.a)
			if local.dot(forward)>2.05 and local.dot(forward)<3.1 and absf(local.cross(forward).y)<1.8 and Vector3(direction.x,0,direction.y).dot(forward)>.1:
				if i==0:answer(g.id,g.answer)
				elif level.generation>=5:wrong_branch(g)
				elif not mistakes.has(g.id):mistakes[g.id]=true;emit("try_again")
	if state!="playing":return
	var move:=Vector3(direction.x,0,direction.y).limit_length()*3.3*dt
	if glue_left>0:move*=.12
	if move.length()>.0001:
		facing=move.normalized()
		at=move_ground(at,move,"hero")
		if glue_left>0:at=glue_anchor+(at-glue_anchor).limit_length(.32)
	if adventure!=null:adventure.observe_input(dt,direction)
	for p in level.pickups:
		if not collected.has(p.id) and at.distance_to(level.pos(p.cell)+p.offset)<.8:
			collected[p.id]=true
			match p.kind:
				"balloon": provisional+=1
				"water": ammo+=3
				"map": hint_left=maxf(hint_left,clampf(30-level.number*.28,2,30))
			emit(p.kind,{"at":at})
	for l in (letters if adventure==null else []):
		if l.index<next_letter: continue
		if at.distance_to(l.at)<.72:
			if l.index==next_letter:
				next_letter+=1
				emit("letter")
				if next_letter==units.size():
					provisional+=units.size()+6
					hint_tokens+=1
					emit("word")
			elif not collected.has("reject%d"%l.index) or age-float(collected["reject%d"%l.index])>2:
				collected["reject%d"%l.index]=age
				emit("next_letter",{"unit":units[next_letter]})
	if adventure!=null:adventure.collect_letters();adventure.tick(dt)
	if state!="playing":return
	step_bots(dt)
	if state!="playing":return
	step_shots(dt)
	if state!="playing":return
	if level.race:
		step_fox(dt)
		check_overtake(previous_at,previous_fox)
	if state!="playing":return
	for exit_cell in level.exits:
		if at.distance_to(level.pos(exit_cell))<1.1 and solved.size()==level.gates.size():
			state="won"
			if explorer_mode():
				for g in level.gates:provisional+=1 if mistakes.has(g.id) else 2
			provisional+=15+2*level.number
			emit("won",{"points":provisional})
			return

func nearby_gate()->Dictionary:
	for g in level.gates:
		if (not solved.has(g.id) or explorer_mode()) and (at.distance_to(level.pos(g.a))<4.8 if g.get("walk_choice",false) else at.distance_to((level.pos(g.a)+level.pos(g.b))/2)<4):
			return g
	return {}

func answer(id:int,value:int)->bool:
	if state!="playing" or solved.has(id): return false
	var g:=nearby_gate()
	if g.is_empty() or g.id!=id: return false
	if adventure!=null and g.get("lesson","")=="wall" and not adventure.complete:return false
	MazeLearning.record(self,g,value==g.answer)
	if value==g.answer:
		solved[id]=true
		checkpoint_at=level.pos(g.b);checkpoint_gate=id
		# Navigation feedback must not identify the correct exit at the threshold.
		# Gate points are banked when the whole navigation level is completed.
		if not explorer_mode():
			provisional+=1 if mistakes.has(id) else 2
			emit("correct")
		return true
	mistakes[id]=true
	emit("try_again")
	return false

func hit()->void:
	if state!="playing" or invulnerable>0: return
	hits+=1
	invulnerable=2.2
	emit("hit")
	if hits>=3:fail("hits")

func fail(reason:String)->void:
	if state!="playing": return
	state="lost"
	emit("lost",{"reason":reason})

func throw_water()->bool:
	if state!="playing" or ammo<=0 or throw_cooldown>0: return false
	ammo-=1
	throw_cooldown=.6
	var dir:=facing
	var closest:=12.0
	for b in bots:
		var distance:=at.distance_to(b.at)
		if b.away<=0 and distance<closest and facing.dot((b.at-at).normalized())>.1 and clear_line(at,b.at):
			closest=distance
			dir=(b.at-at).normalized()
	if adventure!=null and adventure.carrier.state=="approach":
		var flyer:Vector3=adventure.carrier.at;flyer.y=0
		if at.distance_to(flyer)<closest and clear_line(at,flyer):dir=(flyer-at).normalized()
	shots.append({"at":at+Vector3(0,.65,0),"dir":dir,"speed":7.0,"life":2.0,"enemy":false})
	emit("throw")
	return true

func step_shots(dt:float)->void:
	for s in shots:
		s.life-=dt
		s.at+=s.dir*s.speed*dt
		var ground:Vector3=s.at
		ground.y=0
		if not level.can_move(ground,solved):
			s.life=0
			continue
		if s.enemy:
			if ground.distance_to(at)<.65:
				hit()
				s.life=0
		else:
			if adventure!=null and adventure.carrier.state=="approach":
				var flyer:Vector3=adventure.carrier.at;flyer.y=0
				if ground.distance_to(flyer)<1.0:adventure.carrier_hit();s.life=0
			for b in bots:
				if b.away<=0 and ground.distance_to(b.at)<.9:
					if adventure!=null:
						adventure.splash_bot(b,s.get("friendly",false));s.life=0;continue
					b.away=8.0
					s.life=0
					if not repelled.has(b.id):
						repelled[b.id]=true
						provisional+=2
					emit("splash",{"at":b.at})
	shots=shots.filter(func(s):return s.life>0)

func step_bots(dt:float)->void:
	if adventure!=null:adventure.step_bots(dt);return
	for b in bots:
		b.away=maxf(0,b.away-dt)
		if b.away>0: continue
		b.tag_wait=maxf(0,b.tag_wait-dt)
		if b.windup>0:
			b.windup=maxf(0,b.windup-dt)
			if b.windup==0:
				shots.append({"at":b.at+Vector3(0,.6,0),"dir":b.aim,"speed":(1.3+level.number*.017)*enemy_factor,"life":6.0,"enemy":true})
			continue
		b.think-=dt
		if b.think<=0:
			b.think=1.5
			var c:=level.cell_for(b.at)
			var target_cell:=level.cell_for(at)
			var possible:Array[Vector2i]=[]
			for p in level.around(c):
				if level.connected(c,p) and (level.gate_between(c,p).is_empty() or solved.has(level.gate_between(c,p).id)):
					possible.append(p)
			if not possible.is_empty():
				# Local perception, no teleporting through walls or permanent blockade.
				var choose:=possible[(int(age/1.5)+int(b.id))%possible.size()]
				if level.number>25 and b.at.distance_to(at)<10:
					for p in possible:
						if p.distance_to(target_cell)<choose.distance_to(target_cell): choose=p
				b.target=level.pos(choose)+Vector3(sin(age+float(b.id))*1.2,0,0)
		var speed:float=clampf(.5+level.number*.015,.5,2.0)*enemy_factor
		var next:Vector3=b.at.move_toward(b.target,speed*dt)
		b.at=move_ground(b.at,next-b.at,"bot%d"%b.id,true)
		if b.at.distance_to(at)<.78 and b.tag_wait<=0:
			hit()
			# After a tag, the bot gives the player space. A narrow bend must not
			# become three immediate contacts with the same pursuer.
			b.tag_wait=5.0
			b.throw=maxf(b.throw,3.0)
		b.throw-=dt
		if b.throw<=0:
			b.throw=maxf(3.5,10-level.number*.05)
			if b.at.distance_to(at)<11 and b.at.distance_to(at)>2 and clear_line(b.at,at):
				# Aim is fixed before release, giving an observable opportunity to
				# sidestep; later levels shorten neither this cue nor invulnerability.
				b.aim=(at-b.at).normalized()
				b.windup=.85
				emit("warning")

func clear_line(a:Vector3,b:Vector3)->bool:
	var count:=maxi(1,ceili(a.distance_to(b)/.25))
	for i in range(1,count):
		if not level.can_move(a.lerp(b,float(i)/count),solved):return false
	return true

func step_fox(dt:float)->void:
	if level.generation>=5:
		step_competitive_fox(dt)
		return
	fox_wait-=dt
	if fox_wait>0: return
	# Fox explores the same graph, with local Manhattan guidance and backtracking.
	# It reads each fork for several seconds; it cannot hurt the player or teleport.
	var c:Vector2i=fox_path.back()
	var target:=level.pos(c)+Vector3(1.1,0,0)
	fox_at=move_ground(fox_at,fox_at.move_toward(target,(1.35+level.number*.003)*dt)-fox_at,"fox",true,true)
	if fox_at.distance_to(target)>.1: return
	if level.exits.has(c):
		fail("race")
		return
	var options:Array[Vector2i]=[]
	for p in level.around(c):
		if level.connected(c,p) and not fox_visited.has(p): options.append(p)
	if options.is_empty():
		if fox_path.size()>1: fox_path.pop_back()
		else: fox_wait=2
		return
	options.sort_custom(func(a,b):return a.distance_to(level.exits[0])<b.distance_to(level.exits[0]))
	if level.generation>=5 and level.number<35 and options.size()>1:
		if posmod(c.x*7+c.y*11+fox_visited.size(),100)>level.number*2:options.reverse()
	var next:=options[0]
	fox_visited[next]=true
	fox_path.append(next)
	fox_wait=7 if not level.gate_between(c,next).is_empty() else .7

func step_competitive_fox(dt:float)->void:
	fox_wait=maxf(0,fox_wait-dt)
	if fox_wait>0 or fox_index>=level.route.size()-1:return
	# A short, independent exploration detour is followed back on foot. It does
	# not read the player's selected answer, warp, or change simulation speed.
	if fox_detour_index<fox_detour.size():
		var cell:Vector2i=fox_detour[fox_detour_index]
		var previous:Vector2i=level.route[fox_index] if fox_detour_index==0 else fox_detour[fox_detour_index-1]
		var lane:=Vector3(0,0,1.5) if cell.x!=previous.x else Vector3(-1.5,0,0)
		if fox_detour_index==fox_detour.size()-1:lane=fox_lane(fox_index)
		var target:=level.pos(cell)+lane
		fox_at=move_ground(fox_at,fox_at.move_toward(target,fox_pace()*dt)-fox_at,"fox",true,true)
		if fox_reached(target):
			fox_detour_index+=1;fox_visited[cell]=true
			if fox_detour_index==fox_detour.size()/2:fox_wait=.8
		return
	var current:Vector2i=level.route[fox_index]
	var gate:=level.gate_between(current,level.route[fox_index+1])
	if not gate.is_empty() and not fox_choices.has(gate.id):
		var arms:=level.branches(gate)
		# Per-attempt choices survive save/resume, but are not the same answer key
		# on every replay. Roughly 40% of first choices are exploratory mistakes.
		var roll:=(attempt_id+":"+str(gate.id)).sha256_text().left(8).hex_to_int()%100
		var choice:=0 if roll<60 or arms.size()<2 else 1+roll%(arms.size()-1)
		fox_choices[gate.id]=choice;fox_wait=2.5
		if choice>0:
			var outward:Array[Vector2i]=[current,arms[choice]]
			for i in (2 if level.number<30 else 3):
				var options:Array[Vector2i]=[]
				for next in level.around(outward.back()):
					if level.connected(outward.back(),next) and not outward.has(next):options.append(next)
				if options.is_empty():break
				outward.append(options[roll%options.size()])
			fox_detour.clear();fox_detour_index=0
			fox_detour.append_array(outward.slice(1))
			for i in range(outward.size()-2,-1,-1):fox_detour.append(outward[i])
		return
	var next:Vector2i=level.route[fox_index+1]
	var target:=level.pos(next)+fox_lane(fox_index)
	fox_at=move_ground(fox_at,fox_at.move_toward(target,fox_pace()*dt)-fox_at,"fox",true,true)
	if not fox_reached(target):return
	fox_index+=1;fox_visited[next]=true;fox_path.append(next)
	if level.exits.has(next):fail("race")

# Reaching a corridor waypoint does not require standing on somebody else's
# exact footprint. Continue from nearby when another character occupies it;
# every following step still goes through the same solid-body collision check.
func fox_reached(target:Vector3)->bool:
	if fox_at.distance_to(target)<.12:return true
	if fox_at.distance_to(target)>1.0:return false
	for body in ground_bodies():
		if body.id!="fox" and target.distance_to(body.at)<.43+float(body.radius)+.025:return true
	return false

# Compare nearby progress along the same route, with hysteresis. No laugh at
# spawn, on a teleport, on a wrong-arm detour, or simply for staying ahead.
func route_progress(position:Vector3)->float:
	var best:=2.3;var progress:=-1.0
	for i in level.route.size()-1:
		var start:=level.pos(level.route[i]);var delta:=level.pos(level.route[i+1])-start
		var fraction:=clampf((position-start).dot(delta)/delta.length_squared(),0,1)
		var distance:=position.distance_to(start+delta*fraction)
		if distance<best:best=distance;progress=(i+fraction)*MazeLevel.CELL
	return progress
func check_overtake(previous_at:Vector3,previous_fox:Vector3)->void:
	if not level.race or state!="playing" or explorer_mode():return
	if at.distance_to(previous_at)>1 or fox_at.distance_to(previous_fox)>1 or fox_detour_index<fox_detour.size() or (adventure!=null and adventure.carrier.state=="carry"):
		laugh_armed=false;return
	if at.distance_to(fox_at)>5:return
	var human_progress:=route_progress(at);var rival_progress:=route_progress(fox_at)
	if human_progress<0 or rival_progress<0 or absf(human_progress-rival_progress)>5:return
	if rival_progress<human_progress-.8:laugh_armed=true
	elif laugh_armed and rival_progress>human_progress+.8:
		laugh_armed=false
		if age>=laugh_after and fox_at.distance_to(previous_fox)>.001:emit("rival_laugh");laugh_after=age+6

func fox_pace()->float:
	return 2.95+minf(level.number*.001,0.1)

func explorer_mode()->bool:
	return level.generation>=5 and level.skills.get("explorer_mode",false)

func fox_lane(index:int)->Vector3:
	if index>=level.route.size()-1:return Vector3(-1.5,0,0)
	return Vector3(0,0,1.5) if level.route[index+1].x!=level.route[index].x else Vector3(-1.5,0,0)

func use_hint()->void:
	if hint_tokens>0:
		hint_tokens-=1
		hint_left=12 if level.number<30 else (8 if level.number<70 else 5)
	elif periodic_hint_available():
		periodic_hint_used=int(age/180)
		hint_left=5

func periodic_hint_available()->bool:
	return age>=180 and fmod(age,180)<10 and periodic_hint_used<int(age/180)

func snapshot()->Dictionary:
	var result:={"schema":1,"layout_version":level.generation,"number":level.number,"skills":level.skills.duplicate(),"language":language_code}
	for key in ["attempt_id","at","facing","age","hits","invulnerable","ammo","provisional","solved","mistakes","collected","repelled","bots","shots","next_letter","hint_tokens","hint_left","state","fox_at","fox_index","fox_wait","fox_visited","fox_path","enemy_factor","throw_cooldown","periodic_hint_used"]:result[key]=get(key)
	if level.generation>=5:
		for field in ["glue_left","glue_anchor","glue_gate","glue_cycle","gate_retry","checkpoint_at","checkpoint_gate","recovery_count","fox_choices","fox_detour","fox_detour_index","laugh_armed","laugh_after"]:result[field]=get(field)
	if not learning.is_empty():result["learning"]=learning.duplicate(true)
	if adventure!=null:result["adventure"]=adventure.snapshot()
	return result

func restore(saved:Dictionary)->bool:
	if int(saved.get("layout_version",1))!=level.generation:return false
	if saved.get("schema")!=1 or saved.get("number")!=level.number or saved.get("state")!="playing":return false
	var fields:=snapshot()
	for key in fields:
		if key in ["schema","layout_version","number","skills","language","adventure","learning"]:continue
		if not saved.has(key) and key in ["fox_choices","fox_detour","fox_detour_index","laugh_armed","laugh_after"]:continue
		if not saved.has(key) or typeof(saved[key])!=typeof(fields[key]):return false
	if not saved.at.is_finite() or not is_finite(saved.age) or saved.age<0 or saved.hits<0 or saved.hits>2 or saved.ammo<0 or saved.provisional<0 or saved.provisional>400 or saved.next_letter<0 or saved.next_letter>units.size():return false
	if not level.can_move(saved.at,saved.solved):return false
	for key in fields:
		if key not in ["schema","layout_version","number","skills","language","adventure","learning"] and saved.has(key):set(key,saved[key])
	if adventure!=null and not adventure.restore(saved.get("adventure",{})):return false
	if not learning.is_empty():
		if not saved.get("learning") is Dictionary:return false
		learning=saved.learning.duplicate(true);MazeLearning.restore_questions(self)
	settle_loaded_bodies()
	events.clear()
	return true

# Every ground character uses these same solid footprints. Rendered airborne
# Balloon Minik uses the explicit catch/carry interaction, not ground walking.
func ground_bodies()->Array:
	var bodies:Array=[]
	if adventure==null or adventure.carrier.state!="carry":bodies.append({"id":"hero","at":at,"radius":.43})
	for b in bots:
		if adventure!=null or b.away<=0:bodies.append({"id":"bot%d"%b.id,"at":b.at,"radius":.43})
	if level.race:bodies.append({"id":"fox","at":fox_at,"radius":.43})
	if adventure!=null and adventure.helper.state!="rest":bodies.append({"id":"guide","at":adventure.helper.at,"radius":.9})
	return bodies

func terrain_clear(point:Vector3,radius:float=.43,own_gates:bool=false)->bool:
	var gates:=solved
	if own_gates:
		gates=solved.duplicate()
		for g in level.gates:gates[g.id]=true
	if not level.can_move(point,gates):return false
	var extra:=maxf(0,radius-.38)
	for offset in [Vector3(extra,0,0),Vector3(-extra,0,0),Vector3(0,0,extra),Vector3(0,0,-extra)]:
		if not level.can_move(point+offset,gates):return false
	return true

func body_clear(point:Vector3,id:String,radius:float=.43,own_gates:bool=false)->bool:
	if not terrain_clear(point,radius,own_gates):return false
	for body in ground_bodies():
		if body.id!=id and point.distance_to(body.at)<radius+float(body.radius)+.025:return false
	return true

func move_ground(origin:Vector3,delta:Vector3,id:String,steer:bool=false,own_gates:bool=false)->Vector3:
	var radius:=.9 if id=="guide" else .43
	var result:=origin;var count:=maxi(1,ceili(delta.length()/.1));var step:=delta/count
	for i in count:
		if body_clear(result+step,id,radius,own_gates):result+=step;continue
		# The player slides along the obstacle only through their own input.
		# NPCs keep a stable passing side instead of alternating left/right.
		var candidates:Array=[Vector3(step.x,0,0),Vector3(0,0,step.z)]
		if steer:
			var side:=1.0 if id=="guide" or id=="fox" or int(id.trim_prefix("bot"))%2==0 else -1.0
			candidates=[]
			for angle in [35.0,65.0,90.0,-35.0,-65.0,-90.0]:candidates.append(step.rotated(Vector3.UP,deg_to_rad(angle*side)))
		for candidate in candidates:
			if candidate.length()>.00001 and body_clear(result+candidate,id,radius,own_gates):result+=candidate;break
	return result

func settle_loaded_bodies()->void:
	# Old saves predate solid characters. Resolve existing overlap once at load;
	# normal movement never teleports or pushes the player out of their position.
	for body in ground_bodies():
		if body.id=="hero" or body_clear(body.at,body.id,body.radius,body.id=="fox"):continue
		var found:=false
		for ring in range(1,21):
			for sector in 16:
				var candidate:Vector3=body.at+Vector3(cos(sector*TAU/16),0,sin(sector*TAU/16))*ring*.15
				if body_clear(candidate,body.id,body.radius,body.id=="fox"):
					if body.id=="guide":adventure.helper.at=candidate
					elif body.id=="fox":fox_at=candidate
					else:
						for b in bots:
							if body.id=="bot%d"%b.id:b.at=candidate
					found=true;break
			if found:break


func wrong_branch(g:Dictionary)->void:
	if glue_left>0 or age<float(gate_retry.get(g.id,0)):return
	MazeLearning.record(self,g,false)
	mistakes[g.id]=true;gate_retry[g.id]=age+8.0
	if explorer_mode():return
	glue_left=5.0;glue_anchor=at;glue_gate=int(g.id);glue_cycle+=1
	# The penalty always costs one life, even during balloon invulnerability.
	hits+=1;invulnerable=2.2;emit("hit");emit("glued")
	if hits>=3:fail("hits")
