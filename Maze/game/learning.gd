class_name MazeLearning
extends RefCounted

# Question mastery is independent of maze geometry, lives and race results.
const FIELDS:=["lesson","display_prompt","display_choices","picture","explanation","subject","question_id","answer_language","word_entry","walk_choice","difficulty"]
static func key(options:Dictionary,subject:String)->String:
	return str(options.get("game_mode","child"))+":"+str(options.get("question_language","en"))+":"+subject
static func maximum(options:Dictionary,subject:String)->int:
	if options.get("game_mode","child")!="explorer":return 6 if subject=="math" else 4
	var highest:=1
	for q in MazeCurriculum.questions(options,subject):highest=maxi(highest,int(q.level))
	return highest
static func level_for(options:Dictionary,subject:String)->int:
	var k:=key(options,subject)
	var value=options.get("question_progress",{}).get(k,{}).get("level",1) if options.get("question_auto",true) else options.get("question_manual_levels",{}).get(k,1)
	return clampi(int(value),1,maximum(options,subject))
static func new_state(options:Dictionary)->Dictionary:
	if int(options.get("question_version",0))!=1:return {}
	return {"progress":options.get("question_progress",{}).duplicate(true),"answered":{},"seen":{},"questions":{},"revision":0}
static func capture(run:MazeRun)->void:
	if run.learning.is_empty():return
	for g in run.level.gates:
		var item:Dictionary={}
		for field in FIELDS:
			if g.has(field):item[field]=g[field]
		run.learning.questions[g.id]=item.duplicate(true)
static func restore_questions(run:MazeRun)->void:
	for g in run.level.gates:
		var item:Dictionary=run.learning.get("questions",{}).get(g.id,{})
		for field in FIELDS:
			if item.has(field):g[field]=item[field]
static func mark_seen(run:MazeRun,id:int)->void:
	if not run.learning.is_empty():run.learning.seen[id]=true
static func record(run:MazeRun,g:Dictionary,correct:bool)->void:
	if run.learning.is_empty() or run.learning.answered.has(g.id):return
	run.learning.answered[g.id]=true;run.learning.seen[g.id]=true
	var options:Dictionary=run.adventure.settings
	if not options.get("question_auto",true):return
	var subject:=str(g.subject);var k:=key(options,subject)
	var progress:Dictionary=run.learning.progress.get(k,{"level":int(g.difficulty),"right":0,"wrong":0}).duplicate()
	progress["right"]=int(progress.get("right",0))+1 if correct else 0
	progress["wrong"]=0 if correct else int(progress.get("wrong",0))+1
	var old:=int(progress.level)
	if progress.right>=2:progress.level=mini(maximum(options,subject),old+1);progress.right=0
	if progress.wrong>=2:progress.level=maxi(1,old-1);progress.wrong=0
	run.learning.progress[k]=progress;options.question_progress=run.learning.progress.duplicate(true)
	run.learning.revision+=1
	if int(progress.level)!=old:refresh(run)
static func refresh(run:MazeRun)->void:
	if run.learning.is_empty():return
	for g in run.level.gates:
		if not run.learning.seen.has(g.id):MazeCurriculum.configure_gate(run.level,g,run.adventure.settings)
	capture(run)
static func apply_preferences(run:MazeRun,profile:Dictionary)->void:
	if run.learning.is_empty():return # A legacy saved attempt keeps its original questions.
	for field in ["question_auto","question_manual_levels"]:run.adventure.settings[field]=profile[field].duplicate(true) if profile[field] is Dictionary else profile[field]
	run.learning.revision+=1;refresh(run)
static func example(options:Dictionary,subject:String,number:int)->String:
	if options.get("game_mode","child")=="explorer":
		for q in MazeCurriculum.questions(options,subject):
			if int(q.level)==number:return str(q.prompt)
		return ""
	if subject=="math":return ["1 + 2 = ?","4 + 5 = ?","12 − 5 = ?","46 + 27 = ?","5 × 4 = ?","42 ÷ 6 = ?"][number-1]
	var entry:=MazeLessons.choose(3 if number<4 else 12,number-1,subject)
	var word:=MazeLessons.title(entry,subject)
	return word+" → "+str(MazeLessons.word(entry,subject)[0]) if number<=2 else MazeLessons.title(entry,str(options.get("source","en")))+" → "+word
