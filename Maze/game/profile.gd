class_name MazeProfile
extends RefCounted

var data:Dictionary={"mode_chosen":false,"played":false,"game_mode":"child","child_subjects":["math","en"],"explorer_subjects":["general_knowledge","science","arithmetic"],"question_language":"en","word_auto":true,"word_tier":0,"word_levels":{},"prompt_language":"","lesson_mode":"mixed","question_auto":true,"question_manual_levels":{},"question_progress":{},"schema":1,"bests":{},"unlocked":1,"ui":"en","learning":"en","sound":true,"comfort":false,"large_controls":false,"quality":"balanced","nickname":"","skills":{"math":0.0,"words":0.0,"maze":0.0,"enemies":0.0},"attempts":0,"receipts":[],"active":""}
var path:="user://progress.json"
func _init(file_path:String="user://progress.json",primary_locale:String="") ->void:
	path=file_path
	var locale:=(OS.get_locale_language() if primary_locale.is_empty() else primary_locale).split("_")[0].split("-")[0]
	if locale=="iw":locale="he"
	if MazeWords.NAMES.has(locale):data.ui=locale;data.learning=locale
	data.question_language="he" if locale=="he" else "en"
	if FileAccess.file_exists(path):
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("schema")==1:
			for key in data:
				if parsed.has(key) and typeof(parsed[key])==typeof(data[key]): data[key]=parsed[key]
	# JSON numbers are floats. Only accept bounded finite numeric counters.
			for key in ["unlocked","attempts","word_tier"]:
				if parsed.get(key) is float and is_finite(parsed[key]):data[key]=clampi(int(parsed[key]),0,1000000)
	for axis in ["math","words","maze","enemies"]:
		var value=data.skills.get(axis,0.0)
		data.skills[axis]=clampf(float(value),0,1) if (value is float or value is int) and is_finite(float(value)) else 0.0
	for key in ["ui","learning"]:
		if not MazeWords.NAMES.has(data[key]):data[key]="en"
	if data.quality not in ["battery","balanced","high"]:data.quality="balanced"
	if data.prompt_language.is_empty() or not MazeWords.NAMES.has(data.prompt_language):data.prompt_language=data.ui
	data.word_tier=clampi(int(data.word_tier),0,3)
	if data.lesson_mode not in ["mixed","first_picture","first_word","translation","math"]:data.lesson_mode="mixed"
	if data.game_mode not in ["child","explorer"]:data.game_mode="child"
	if data.question_language not in ["en","he"]:data.question_language="he" if data.ui=="he" else "en"
	data.child_subjects=data.child_subjects.filter(func(v):return v=="math" or MazeWords.STUDY_CODES.has(v))
	data.explorer_subjects=data.explorer_subjects.filter(func(v):return MazeCurriculum.SUBJECTS.has(v))
	if data.child_subjects.is_empty():data.child_subjects=["math","en"]
	if data.explorer_subjects.is_empty():data.explorer_subjects=["general_knowledge","science","arithmetic"]
	for k in data.question_progress.keys():
		var item=data.question_progress[k]
		if not item is Dictionary:data.question_progress.erase(k);continue
		for field in ["level","right","wrong"]:
			var value=item.get(field,1 if field=="level" else 0)
			item[field]=clampi(int(value),1 if field=="level" else 0,18 if field=="level" else 1) if (value is int or value is float) and is_finite(float(value)) else (1 if field=="level" else 0)
	for k in data.question_manual_levels.keys():
		var value=data.question_manual_levels[k]
		data.question_manual_levels[k]=clampi(int(value),1,18) if (value is int or value is float) and is_finite(float(value)) else 1
	data.played=data.played or data.attempts>0 or not data.bests.is_empty() or not data.active.is_empty()
	data.unlocked=clampi(int(data.unlocked),1,100)
	for key in data.bests.keys():
		var value=data.bests[key]
		if not str(key).is_valid_int() or int(key)<1 or int(key)>100 or not (value is int or value is float) or not is_finite(float(value)) or int(value)<0 or int(value)>400:data.bests.erase(key)
func save()->void:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(path+".tmp",path)
func total()->int:
	var result:=0
	for value in data.bests.values():result+=int(value)
	return result
func finish(run:MazeRun)->int:
	if run.state=="playing" or data.receipts.has(run.attempt_id):return 0
	data.receipts.append(run.attempt_id)
	if data.receipts.size()>256:data.receipts.pop_front()
	if not run.learning.is_empty():data.question_progress=run.learning.progress.duplicate(true)
	data.active=""
	data.attempts+=1
	# Independent, slowly adapting local axes. A single mistake does not reset mastery.
	var signals:={"math":1.0-float(run.mistakes.size())/maxi(1,run.level.gates.size()),"words":float(run.next_letter)/maxi(1,run.units.size()),"maze":1.0 if run.state=="won" else 0.0,"enemies":1.0-float(run.hits)/3}
	for axis in signals:
		if (axis=="words" and run.level.number<2) or (axis=="enemies" and run.bots.is_empty()):continue
		data.skills[axis]=clampf(float(data.skills[axis])*.85+float(signals[axis])*.15,0,1)
	if run.adventure!=null and data.word_auto and not run.letters.is_empty():
		var current:=MazeLessons.tier(data)
		if run.adventure.complete and run.adventure.letter_errors==0 and run.state=="won":current=mini(3,current+1)
		elif run.adventure.letter_errors>=3:current=maxi(0,current-1)
		data.word_levels[run.language_code]=current
	var difference:=0
	if run.state=="won":
		var id:=str(run.level.number)
		var old:=int(data.bests.get(id,0))
		data.bests[id]=maxi(old,run.provisional)
		difference=int(data.bests[id])-old
		data.unlocked=maxi(int(data.unlocked),mini(100,run.level.number+1))
	save()
	return difference

func checkpoint(run:MazeRun)->void:
	if run.state!="playing":return
	if not run.learning.is_empty():data.question_progress=run.learning.progress.duplicate(true)
	data.active=Marshalls.raw_to_base64(var_to_bytes(run.snapshot()))
	save()

func active_run()->Dictionary:
	if data.active.is_empty():return {}
	var bytes:=Marshalls.base64_to_raw(data.active)
	if bytes.is_empty() or bytes.size()>1000000:return {}
	var value=bytes_to_var(bytes)
	if value is Dictionary and value.get("schema")==1 and value.get("number") is int and value.number>=1 and value.number<=int(data.unlocked):return value
	return {}

func reset_progress()->void:
	# Retain preferences and the separately stored purchase entitlement.
	data.bests={};data.unlocked=1;data.active="";data.attempts=0;data.receipts=[];data.played=false
	data.skills={"math":0.0,"words":0.0,"maze":0.0,"enemies":0.0};data.word_levels={};data.question_progress={}
	save()
