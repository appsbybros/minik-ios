class_name MazeAdventure
extends RefCounted

var owner_ref:WeakRef
var run:MazeRun:
	get:return owner_ref.get_ref()
var settings:Dictionary
var tier:=0
var entry:=0
var kind:=""
var tray:Array=[]
var complete:=false
var letter_errors:=0
var flash_left:=0.0
var flares:Array=[]
var dark_index:=5
var last_progress:=0.0
var best_progress:=0
var last_solved:=0
var help_after:=55.0
var gift_count:=0
var helper:Dictionary={"state":"rest","at":Vector3(1.6,0,0),"name":"Lumi","wait":0.0,"target":Vector3.ZERO,"gift":"map","shot":0.0,"path":[],"effort":0.0,"active_total":0.0,"progress_signature":0}
var rescue:="waiting"
var rescue_time:=0.0
var carrier:Dictionary={"state":"rest","at":Vector3(-5,2,-5),"time":16.0,"visits":0,"from":Vector3.ZERO,"to":Vector3.ZERO,"flight":0.0}

func _init(owner:MazeRun,options:Dictionary={})->void:
	owner_ref=weakref(owner);settings=options.duplicate(true);tier=clampi(int(settings.get("tier",0)),0,3)
	entry=MazeLessons.choose(run.level.number,tier,run.language_code)
	kind=MazeLessons.special(run.level)
	if run.level.generation>=5 and kind=="wall":kind=""
	if kind=="wall" and settings.get("mode","mixed")=="math":kind=""
	helper.name="Lumi"
	run.units=MazeLessons.word(entry,run.language_code)
	MazeLessons.configure_gates(run.level,run.language_code,settings,kind,entry)
	run.letters.clear()
	var count:=run.units.size()
	var end:=run.level.route.size()-2
	if kind=="wall":end=maxi(1,run.level.route.find(run.level.gates.back().a)-1)
	if kind=="night":end=3;dark_index=5
	var extras:=maxi(0,7-count) if tier==0 else (2 if tier>=2 else 0)
	var tokens:Array=run.units.duplicate()
	var alphabet:=MazeLessons.alphabet(run.language_code)
	for i in extras:
		var start:=posmod(run.level.number+i*7,alphabet.size())
		for j in alphabet.size():
			var value=alphabet[(start+j)%alphabet.size()]
			if not run.units.has(value):tokens.append(value);break
	# Rotate/reverse actual pickup placement; correct collection order is not the
	# corridor order. A return trip is always possible before the final wall.
	var indices:Array=range(tokens.size())
	if tier==0:indices.reverse()
	elif run.level.number%2==0:indices.push_back(indices.pop_front())
	var occupied:Dictionary={}
	var offsets:=[Vector2(-1.4,-1.4),Vector2(1.4,1.4),Vector2(1.4,-1.4),Vector2(-1.4,1.4),Vector2(0,-1.4),Vector2(0,1.4),Vector2(-1.4,0),Vector2(1.4,0)]
	for i in indices.size():
		var id:=int(indices[i]);var cell_index:=1+int(float(i)*maxi(0,end-1)/maxi(1,indices.size()-1))
		var cell:Vector2i=run.level.route[mini(end,cell_index)]
		var slot:=int(occupied.get(cell,0));occupied[cell]=slot+1
		var offset:Vector2=offsets[slot%offsets.size()]
		run.letters.append({"index":i,"unit":tokens[id],"at":run.level.pos(cell)+Vector3(offset.x,0,offset.y),"picked":false,"cooldown":0.0,"returned":false})
	if run.level.number<2 or run.level.race or run.level.timer>0 or (tier>=2 and kind=="" and run.level.number%2==1):run.letters.clear()
	if kind=="night":
		for i in range(dark_index,run.level.route.size()-1,3):flares.append({"at":run.level.pos(run.level.route[i])+Vector3(-1.25,0,.8),"taken":false})
	if run.level.generation>=5:
		run.letters.clear();run.units=[];complete=true
		if kind=="night":flash_left=35.0
		MazeCurriculum.configure(run.level,settings)
	# Distinct playful visitors; familiar Minik friends are the helpful guides.
	if kind=="rescue":
		while run.bots.size()<6:
			var i:=run.bots.size();var p:=run.level.pos(run.level.route[mini(2+i,run.level.route.size()-2)])
			run.bots.append({"id":i,"name":"","at":p,"home":p,"away":0.0,"throw":8.0+i,"target":p,"think":0.0,"tag_wait":0.0,"windup":0.0,"aim":Vector3.ZERO})
	for b in run.bots:
		b.name=["Pip","Nori","Toby","Lulu"][int(b.id)%4]
		b["mood"]="play";b["path"]=[];b["laugh"]=0.0;b["rest"]=0.0

func tray_valid()->Array:
	var valid:Array=[];var used:Array=[]
	for i in tray.size():
		var token=run.letters[int(tray[i])].unit
		if tier==0:
			var slot:=-1
			for j in run.units.size():
				if run.units[j]==token and not used.has(j):slot=j;break
			valid.append(slot>=0)
			if slot>=0:used.append(slot)
		else:valid.append(i<run.units.size() and run.units[i]==token)
	return valid

func collect_letters()->void:
	if complete:return
	for l in run.letters:
		if l.picked:continue
		if l.returned:
			if run.at.distance_to(l.at)>.95:l.returned=false
			else:continue
		if float(l.cooldown)>run.age or run.at.distance_to(l.at)>=.72:continue
		if tray.size()>=run.units.size()+3:continue
		l.picked=true;tray.append(int(l.index))
		var valid:=tray_valid()
		if not valid.back():letter_errors+=1;run.emit("letter_wrong")
		else:run.emit("letter")
		evaluate_word()

func evaluate_word()->void:
	var valid:=tray_valid();run.next_letter=valid.count(true)
	if not complete and tray.size()==run.units.size() and not valid.has(false):
		complete=true;run.next_letter=run.units.size();run.provisional+=run.units.size()+6
		if kind=="night":flash_left=30.0;run.emit("flare_reward")
		else:run.hint_tokens+=1;run.emit("word")

func remove_letter(slot:int)->void:
	if complete or slot<0 or slot>=tray.size():return
	var id:=int(tray[slot]);tray.remove_at(slot)
	run.letters[id].picked=false;run.letters[id].cooldown=run.age+2.0;run.letters[id].returned=true
	evaluate_word();run.emit("letter_removed")

func tray_slots()->Array:
	var result:Array=[]
	if tier>0:
		var valid:=tray_valid()
		for i in tray.size():result.append({"text":run.letters[int(tray[i])].unit,"slot":i,"valid":valid[i]})
	else:
		var assigned:Array=[]
		for unit in run.units:
			var match_slot:=-1
			for i in tray.size():
				if not assigned.has(i) and run.letters[int(tray[i])].unit==unit:match_slot=i;break
			if match_slot>=0:assigned.append(match_slot)
			result.append({"text":unit if match_slot>=0 else "·","slot":match_slot,"valid":true})
		for i in tray.size():
			if not assigned.has(i):result.append({"text":run.letters[int(tray[i])].unit,"slot":i,"valid":false})
	while result.size()<run.units.size():result.append({"text":"·","slot":-1,"valid":true})
	return result

func progress_index()->int:
	return run.level.route.find(run.level.cell_for(run.at))
func darkness()->float:
	if kind!="night":return 0.0
	var center:Vector3=run.level.pos(run.level.route[2])
	return smoothstep(10.0,18.0,run.at.distance_to(center))
func hero_position()->Vector3:
	if carrier.state!="carry":return run.at
	var t:=clampf(float(carrier.flight)/4.0,0,1)
	return carrier.from.lerp(carrier.to,smoothstep(0,1,t))+Vector3(0,sin(t*PI)*4,0)

func tick(dt:float)->void:
	flash_left=maxf(0,flash_left-dt)
	for flare in flares:
		if not flare.taken and run.at.distance_to(flare.at)<.9:flare.taken=true;flash_left=minf(50,flash_left+25);run.emit("flare")
	var p:=progress_index()
	if p>best_progress or run.solved.size()>last_solved:
		best_progress=maxi(p,best_progress);last_solved=run.solved.size();last_progress=run.age;helper["effort"]=0.0
	step_helper(dt)
	if kind=="carrier":step_carrier(dt)

func open_path(from:Vector3,to:Vector3)->Array:
	var blocked:Dictionary={}
	for g in run.level.gates:
		if not run.solved.has(g.id):blocked[g.key]=true
	var cells=run.level.path(run.level.cell_for(from),run.level.cell_for(to),blocked)
	var result:Array=[]
	for c in cells:result.append(run.level.pos(c))
	if not result.is_empty() and result.back().distance_to(to)>.01:result.append(to)
	return result

func walk(actor:Dictionary,target:Vector3,speed:float,dt:float)->bool:
	var id:="bot%d"%actor.id if actor.has("id") else "guide"
	if actor.at.distance_to(target)<.22:actor.path=[];actor["velocity"]=Vector3.ZERO;return true
	if actor.path.is_empty():actor.path=open_path(actor.at,target)
	if actor.path.is_empty():actor["velocity"]=Vector3.ZERO;return false
	# Cut a corner only when the complete footprint fits along the shortcut.
	while actor.path.size()>1:
		var next:Vector3=actor.path[1];var clear:=true
		var steps:=maxi(1,ceili(actor.at.distance_to(next)/.15))
		for i in range(1,steps+1):
			if not run.terrain_clear(actor.at.lerp(next,float(i)/steps),.9 if id=="guide" else .43):clear=false;break
		if not clear:break
		actor.path.pop_front()
	var goal:Vector3=actor.path[0];var toward:Vector3=goal-actor.at
	var desired:Vector3=toward.normalized()*minf(speed,toward.length()/maxf(dt,.001))
	var velocity:Vector3=actor.get("velocity",Vector3.ZERO)
	velocity=velocity.lerp(desired,1-exp(-dt*5.5))
	var displacement:Vector3=(velocity*dt).limit_length(toward.length())
	var previous:Vector3=actor.at
	actor.at=run.move_ground(previous,displacement,id,true)
	actor["velocity"]=(actor.at-previous)/maxf(dt,.001)
	if actor.at.distance_to(goal)<.22:actor.path.pop_front()
	return actor.at.distance_to(target)<.22

func step_bots(dt:float)->void:
	for b in run.bots:
		b.tag_wait=maxf(0,b.tag_wait-dt);b.laugh=maxf(0,b.laugh-dt)
		if b.away>0:
			b.away=maxf(0,b.away-dt);b.mood="wet"
			walk(b,b.get("retreat",b.home),2.0,dt)
			if b.away<=0:b.mood="play";b.path=[];b.windup=0.0;b.throw=4.0;b["returning"]=true
			continue
		if b.get("returning",false):
			b.mood="play"
			if walk(b,b.home,1.4,dt):b.returning=false;b.path=[]
			continue
		if b.windup>0:
			b.mood="throw";b.windup=maxf(0,b.windup-dt)
			if b.windup<=0:
				run.shots.append({"at":b.at+Vector3(0,.9,0),"dir":b.aim,"speed":(1.3+run.level.number*.017)*run.enemy_factor,"life":6.0,"enemy":true})
				b.laugh=1.0
			continue
		b.mood="laugh" if b.laugh>0 else "play"
		var pressure:=kind=="rescue" and rescue in ["pressure","clearing"]
		if pressure and b.path.is_empty():
			b.target=run.at;b.path=open_path(b.at,run.at)
		b.rest=maxf(0,float(b.get("rest",0.0))-dt)
		if b.rest>0 and not pressure:continue
		if b.path.is_empty():
			var c:Vector2i=run.level.cell_for(b.at)
			var candidates:Array=[]
			for n in run.level.around(c):
				var gate:Dictionary=run.level.gate_between(c,n)
				if run.level.connected(c,n) and (gate.is_empty() or run.solved.has(gate.id)):candidates.append(n)
			if not candidates.is_empty():
				var next:Vector2i=candidates[posmod(int(run.age/3)+int(b.id),candidates.size())]
				if pressure:
					candidates.sort_custom(func(a,bcell):return run.level.pos(a).distance_to(run.at)<run.level.pos(bcell).distance_to(run.at));next=candidates[0]
				var lane:=Vector3(sin(float(b.id)*2.7+run.age*.13)*.7,0,cos(float(b.id)*1.9+run.age*.11)*.7)
				b.target=run.level.pos(next)+lane
				if not run.terrain_clear(b.target):b.target=run.level.pos(next)
				b.path=open_path(b.at,b.target)
		var speed:=clampf(.7+run.level.number*.012,.7,1.8)*run.enemy_factor
		if not pressure or b.at.distance_to(run.at)>2.2:
			if walk(b,b.target,speed,dt):b.rest=.35+fmod(float(b.id)*.37+run.age*.09,1.1);b.path=[]
		if b.at.distance_to(run.at)<1.0 and b.tag_wait<=0 and not pressure and carrier.state!="carry":
			# Playful visitors make space after a bump. Damage comes from visible,
			# avoidable water balloons, not an unavoidable body in a narrow corridor.
			b.tag_wait=6.0;b.laugh=1.0;b.away=4.0;b.path=[]
		b.throw-=dt
		if b.throw<=0:
			b.throw=maxf(4.5,11-run.level.number*.04)+float(int(b.id)%3)
			if not pressure and carrier.state!="carry" and b.at.distance_to(run.at)<10 and b.at.distance_to(run.at)>2 and run.clear_line(b.at,run.at):
				b.aim=(run.at-b.at).normalized();b.windup=1.15;run.emit("warning")

func splash_bot(bot:Dictionary,friendly:bool)->void:
	bot.away=14.0;bot.windup=0.0;bot.path=[];bot.mood="wet"
	# Retreat even when splashed at the original home position, then visibly
	# walk back. Do not disappear or reset position when the timeout expires.
	var retreat:Vector3=bot.home;var best:=0.0
	for cell in run.level.cells:
		var p:=run.level.pos(cell);var distance:=p.distance_to(run.at)
		if distance>best and distance<22 and not open_path(bot.at,p).is_empty():retreat=p;best=distance
	bot["retreat"]=retreat;bot["returning"]=false
	if not friendly and not run.repelled.has(bot.id):run.repelled[bot.id]=true;run.provisional+=2
	run.emit("splash",{"at":bot.at})

func next_gate_position()->Vector3:
	if kind=="night" and not complete:
		for l in run.letters:
			if not l.picked and run.units.has(l.unit):return l.at
	for g in run.level.gates:
		if not run.solved.has(g.id):return run.level.pos(g.a)
	return run.level.pos(run.level.exits[0])
func observe_input(dt:float,direction:Vector2)->void:
	# Looking around/reading at the entrance is not evidence of being stuck.
	if direction.length()>.15:
		helper["effort"]=float(helper.get("effort",0.0))+dt
		helper["active_total"]=float(helper.get("active_total",0.0))+dt
	var signature:=run.collected.size()+run.next_letter+run.solved.size()*10
	if signature!=int(helper.get("progress_signature",0)):
		helper.progress_signature=signature;helper.effort=0.0;last_progress=run.age

func invite(reason:String)->void:
	# A visible magical arrival from reachable open space; never inside a body.
	var best:=INF;var spot:Vector3=run.at;var found:=false
	for cell in run.level.cells:
		var p:Vector3=run.level.pos(cell)+Vector3(.9,0,.8)
		var distance:=p.distance_to(run.at)
		if distance<4 or distance>12 or not run.body_clear(p,"guide",.9):continue
		var path:=open_path(p,run.at)
		if path.is_empty():continue
		var score:=absf(distance-7)+path.size()*.1
		if score<best:best=score;spot=p;found=true
	if not found:help_after=run.age+10;return
	helper.state="appear";helper.at=spot;helper["entrance"]=spot;helper.path=[];helper.wait=0.0;helper.target=run.at;helper["velocity"]=Vector3.ZERO
	helper.gift="flare" if kind=="night" and complete else ("water" if run.ammo<3 else "map")
	helper["reason"]=reason;helper["effort"]=0.0
	run.emit("friend_coming",{"name":"Lumi"})

func step_helper(dt:float)->void:
	helper.wait+=dt;helper.shot=maxf(0,helper.shot-dt)
	if kind=="rescue" and rescue=="waiting" and best_progress>=3 and run.solved.size()>0 and run.ammo<=2:
		rescue="pressure";rescue_time=run.age;run.invulnerable=12.0;invite("rescue");run.emit("rescue")
	if helper.state=="rest":
		if run.age>=help_after and run.age>=55 and run.age-last_progress>=35 and float(helper.get("effort",0))>=18 and float(helper.get("active_total",0))>=22:
			invite("guide");help_after=run.age+80
		elif run.level.number>=5 and gift_count<1 and run.age>100 and best_progress>=3:
			invite("gift")
			if helper.state!="rest":gift_count+=1
		return
	if helper.state=="appear":
		if helper.wait>=1.2:helper.state="arrive";helper.wait=0.0
	elif helper.state=="arrive":
		if helper.at.distance_to(run.at)<2.7:
			helper.state="offer";helper.wait=0.0;helper.path=[];helper["offered_at"]=run.at;helper["offer_distance"]=helper.at.distance_to(run.at);run.emit("friend_follow",{"name":"Lumi"})
		else:
			if helper.path.is_empty():helper.target=run.at
			walk(helper,helper.target,2.8,dt)
			if helper.wait>22:helper.state="leave";helper.path=[];helper.wait=0.0
	elif helper.state=="offer":
		var approached:bool=run.at.distance_to(helper.get("offered_at",run.at))>.35 and helper.at.distance_to(run.at)<float(helper.get("offer_distance",2.7))-.25
		if helper.wait>1 and approached and helper.at.distance_to(run.at)<2.5:
			if helper.gift=="flare":flash_left=maxf(flash_left,25)
			elif helper.gift=="water":run.ammo+=3
			else:run.hint_tokens+=1
			run.emit("friend_gift",{"gift":helper.gift,"name":"Lumi"})
			helper.state="lead";helper.target=next_gate_position();helper.path=[];helper.wait=0.0
		elif helper.wait>18 or helper.at.distance_to(run.at)>9:helper.state="leave";helper.path=[];helper.wait=0.0
	elif helper.state=="lead":
		if helper.at.distance_to(run.at)<5.5:
			helper["waiting_for_child"]=0.0
			walk(helper,helper.target,1.9,dt)
			if helper.at.distance_to(helper.target)<.35:
				run.emit("friend_gate");helper.state="leave";helper.path=[];helper.wait=0.0;rescue="finished" if kind=="rescue" else rescue
		else:
			helper["waiting_for_child"]=float(helper.get("waiting_for_child",0.0))+dt
			if helper.waiting_for_child>18:helper.state="leave";helper.path=[];helper.wait=0.0
	elif helper.state=="leave":
		if walk(helper,helper.get("entrance",run.level.pos(Vector2i.ZERO)+Vector3(1.6,0,0)),2.4,dt) or helper.wait>25:helper.state="depart";helper.wait=0.0
	elif helper.state=="depart":
		if helper.wait>=1.2:helper.state="rest";helper.wait=0.0;help_after=run.age+80;helper["effort"]=0.0
	if kind=="rescue" and rescue in ["pressure","clearing"]:
		rescue="clearing";run.invulnerable=maxf(run.invulnerable,1.0)
		if helper.shot<=0 and helper.state not in ["rest","appear","depart"]:
			for b in run.bots:
				if b.away<=0 and b.at.distance_to(helper.at)<12 and run.clear_line(helper.at,b.at):
					run.shots.append({"at":helper.at+Vector3(0,.9,0),"dir":(b.at-helper.at).normalized(),"speed":7.0,"life":2.0,"enemy":false,"friendly":true});helper.shot=1.1;break
		if helper.state in ["leave","rest"] or (run.age-rescue_time>90 and helper.state!="lead"):rescue="finished"

func step_carrier(dt:float)->void:
	carrier.time-=dt
	if carrier.state=="rest" and carrier.time<=0:
		carrier.state="approach";carrier.time=2.5;run.emit("carrier_warning")
	elif carrier.state=="approach":
		var target:Vector3=run.at+Vector3(0,1.4,0)
		carrier.at=carrier.at.move_toward(target,1.15*dt)
		if carrier.time<=0 and Vector2(carrier.at.x-run.at.x,carrier.at.z-run.at.z).length()<.75:
			carrier.visits+=1;carrier.from=run.at;carrier.flight=0.0
			var index:=maxi(0,progress_index());var limit:=run.level.route.find(run.level.cell_for(next_gate_position()))
			var destination:=maxi(0,index-3) if int(carrier.visits)%4!=0 else mini(index+3,maxi(index,limit))
			carrier.to=run.level.pos(run.level.route[clampi(destination,0,run.level.route.size()-2)])
			carrier.state="carry";run.emit("carrier_ride")
	elif carrier.state=="carry":
		# Choose free landing space while still visibly airborne, not by pushing a
		# grounded character aside after the drop.
		if not run.body_clear(carrier.to,"hero"):
			var found:=false
			for ring in range(1,7):
				for sector in 12:
					var candidate:Vector3=carrier.to+Vector3(cos(sector*TAU/12),0,sin(sector*TAU/12))*ring*.2
					if run.body_clear(candidate,"hero"):carrier.to=candidate;found=true;break
				if found:break
		carrier.flight+=dt;carrier.at=hero_position()+Vector3(0,1.1,0);run.invulnerable=maxf(run.invulnerable,.5)
		if carrier.flight>=4 and run.body_clear(carrier.to,"hero"):
			run.at=carrier.to;carrier.state="escape";carrier.time=8.0;run.emit("carrier_drop")
	elif carrier.state=="escape":
		carrier.at=carrier.at.move_toward(Vector3(-5,4,-5),4*dt)
		if carrier.time<=0:carrier.state="rest";carrier.time=38.0
func carrier_hit()->void:
	carrier.state="escape";carrier.time=8.0;run.emit("splash",{"at":carrier.at})

func snapshot()->Dictionary:
	return {"settings":settings.duplicate(true),"tray":tray.duplicate(),"complete":complete,"letter_errors":letter_errors,"letters":run.letters.duplicate(true),"flash_left":flash_left,"flares":flares.duplicate(true),"helper":helper.duplicate(true),"carrier":carrier.duplicate(true),"last_progress":last_progress,"best_progress":best_progress,"last_solved":last_solved,"help_after":help_after,"gift_count":gift_count,"rescue":rescue,"rescue_time":rescue_time}
func restore(data:Dictionary)->bool:
	if data.get("settings")!=settings or not data.get("letters") is Array or data.letters.size()!=run.letters.size():return false
	for id in data.get("tray",[]):
		if not id is int or id<0 or id>=run.letters.size():return false
	for key in snapshot():
		if not data.has(key) or typeof(data[key])!=typeof(snapshot()[key]):return false
	for key in snapshot():
		if key=="letters":run.letters=data.letters.duplicate(true)
		elif key!="settings":set(key,data[key])
	helper.name="Lumi"
	if not helper.has("effort"):helper["effort"]=0.0;helper["active_total"]=0.0;help_after=maxf(help_after,run.age+45)
	return true
