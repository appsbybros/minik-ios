class_name MazeLessons
extends RefCounted

static var bank:Array=[]
static func entries()->Array:
	if bank.is_empty():bank=JSON.parse_string(FileAccess.get_file_as_string("res://lesson-words.json"))
	return bank
static func word(entry:int,language:String)->Array:
	return entries()[posmod(entry,entries().size())].units.get(language,entries()[entry%entries().size()].units.en).duplicate()
static func title(entry:int,language:String)->String:return "".join(word(entry,language))
static func choose(number:int,tier:int,language:String)->int:
	var eligible:Array=[]
	for i in entries().size():
		var length:=word(i,language).size()
		if (tier<3 and length<=4) or (tier==3 and length>=4 and length<=9):eligible.append(i)
	return int(eligible[posmod(number-2,eligible.size())]) if not eligible.is_empty() else 0
static func tier(profile:Dictionary)->int:
	if not profile.get("word_auto",true):return clampi(int(profile.get("word_tier",0)),0,3)
	return clampi(int(profile.get("word_levels",{}).get(profile.learning,0)),0,3)
static func options(profile:Dictionary)->Dictionary:
	return {"question_version":1,"question_auto":profile.get("question_auto",true),"question_manual_levels":profile.get("question_manual_levels",{}).duplicate(true),"question_progress":profile.get("question_progress",{}).duplicate(true),"game_mode":profile.get("game_mode","child"),"subjects":profile.get("explorer_subjects",[]) if profile.get("game_mode","child")=="explorer" else profile.get("child_subjects",["math","en"]),"question_language":profile.get("question_language","en"),"tier":tier(profile),"source":profile.get("prompt_language",profile.ui),"mode":profile.get("lesson_mode","mixed")}
static func alphabet(language:String)->Array:
	var out:Array=[]
	for i in entries().size():
		for unit in word(i,language):
			if not out.has(unit):out.append(unit)
	return out
static func special(level:MazeLevel)->String:
	if level.number<4 or (level.race and level.generation<5) or level.timer>0:return ""
	match level.number%12:
		4:return "wall"
		6:return "translation"
		8:return "night"
		11:return "rescue"
		1:return "carrier"
	return ""
static func configure_gates(level:MazeLevel,language:String,options:Dictionary,special_kind:String,collect_word:int)->void:
	var tier_value:=int(options.get("tier",0))
	var source:=str(options.get("source","en"))
	var mode:=str(options.get("mode","mixed"))
	for g in level.gates:
		g["lesson"]="math";g["display_prompt"]=g.prompt+" = ?";g["display_choices"]={};g["picture"]=""
		if level.number<=2:continue
		var kind:=mode
		if kind=="mixed":
			kind="first_picture" if tier_value==0 else ("first_word" if tier_value==1 else "translation")
			if level.number>=15 and int(g.id)%2==0:kind="math"
			elif tier_value>=2 and int(g.id)%3==0:kind="first_picture"
		if special_kind=="translation" and mode=="mixed":kind="translation"
		if special_kind=="wall" and g==level.gates.back():
			g.lesson="wall";g.display_prompt=title(collect_word,language);g["walk_choice"]=false
			g["word_entry"]=collect_word;continue
		if kind=="math":continue
		g.lesson=kind
		var entry:=choose(level.number+int(g.id),tier_value,language)
		g["word_entry"]=entry
		g.display_prompt=title(entry,source)
		if kind=="first_picture":g.picture=entries()[entry].image;g.display_prompt=""
		# With the same question/answer language, use a picture-to-word match
		# instead of revealing the answer by printing the identical word twice.
		if kind=="translation" and source==language:g.picture=entries()[entry].image;g.display_prompt=""
		var correct:=title(entry,language) if kind=="translation" else str(word(entry,language)[0])
		var texts:Array=[correct]
		for i in entries().size():
			var value:=title((entry+i+1)%entries().size(),language) if kind=="translation" else str(word((entry+i+1)%entries().size(),language)[0])
			if not texts.has(value):texts.append(value)
		var values:=level.branch_values(g)
		for i in values.size():g.display_choices[str(values[i])]=texts[i]
static func answer_text(g:Dictionary,value:int)->String:
	return str(g.get("display_choices",{}).get(str(value),str(value)))
