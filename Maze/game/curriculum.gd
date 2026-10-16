class_name MazeCurriculum
extends RefCounted
static var corpus:Dictionary={}
const SUBJECTS:={"arithmetic":"Arithmetic","english":"English","general_knowledge":"General knowledge","science":"Science","astronomy":"Astronomy","artificial_intelligence":"Artificial intelligence","history":"History","mathematics":"Mathematics","programming":"Programming","bagrut_mathematics":"Advanced mathematics","paradoxes":"Paradoxes"}
static func questions(options:Dictionary,subject:String)->Array:
	if corpus.is_empty():corpus=JSON.parse_string(FileAccess.get_file_as_string("res://explorer-questions.json"))
	return corpus.get(str(options.get("question_language","en")),corpus.en).get(subject,corpus.en.general_knowledge)
static func configure(level:MazeLevel,options:Dictionary)->void:
	for g in level.gates:configure_gate(level,g,options)
static func configure_gate(level:MazeLevel,g:Dictionary,options:Dictionary)->void:
	var selected:Array=options.get("subjects",["math","en"])
	if selected.is_empty():selected=["math"]
	var subject:=str(selected[posmod(level.number-1+int(g.id),selected.size())])
	var adaptive:=int(options.get("question_version",0))==1
	var difficulty:=MazeLearning.level_for(options,subject) if adaptive else 1
	g["subject"]=subject;g["difficulty"]=difficulty
	if options.get("game_mode","child")=="explorer":
		var bank:=questions(options,subject)
		if adaptive:
			var filtered:Array=bank.filter(func(q):return int(q.level)==difficulty)
			if not filtered.is_empty():bank=filtered
		var q:Dictionary=bank[posmod((level.number-1)*7+int(g.id)*13,bank.size())]
		var answers:Array=[q.answers[int(q.correct)]]
		for i in q.answers.size():
			if i!=int(q.correct):answers.append(q.answers[i])
		g["lesson"]="knowledge";g["display_prompt"]=q.prompt;g["picture"]="";g["explanation"]=q.explanation;g["question_id"]=q.id
		g["display_choices"]={}
		var values:=level.branch_values(g)
		for i in values.size():g.display_choices[str(values[i])]=answers[i]
	elif subject=="math":
		g["lesson"]="math";g["display_prompt"]=g.prompt+" = ?";g["display_choices"]={};g["picture"]=""
		if adaptive:configure_math(level,g,difficulty)
	else:
		var one:=MazeLevel.new(1,{},1);one.gates=[g];one.number=maxi(3,level.number)
		var tier:=difficulty-1 if adaptive else (0 if level.number<8 else 1 if level.number<18 else 2)
		var mode:=("first_picture" if tier==0 else "first_word" if tier==1 else "translation") if adaptive else "mixed"
		MazeLessons.configure_gates(one,subject,{"tier":tier,"source":options.get("source","en"),"mode":mode},"",0)
		g["answer_language"]=subject
	g["walk_choice"]=true
static func configure_math(level:MazeLevel,g:Dictionary,difficulty:int)->void:
	var seed_value:=("math:%d:%d:%d"%[level.number,int(g.id),difficulty]).sha256_text().left(8).hex_to_int()
	var a:=1+seed_value%3;var b:=1+(seed_value/7)%2;var result:=a+b;var op:="+"
	match difficulty:
		2:a=1+seed_value%8;b=1+(seed_value/7)%(10-a);result=a+b
		3:
			a=5+seed_value%15;b=1+(seed_value/7)%a;op="−" if seed_value%2==0 else "+"
			if op=="+":b=1+(seed_value/7)%(20-a)
			result=a-b if op=="−" else a+b
		4:
			a=20+seed_value%60;b=1+(seed_value/7)%20;op="−" if seed_value%2==0 else "+";result=a-b if op=="−" else a+b
		5:a=[2,5,10][seed_value%3];b=1+(seed_value/7)%10;op="×";result=a*b
		6:
			a=2+seed_value%9;b=2+(seed_value/7)%9
			if seed_value%2==0:result=a*b;op="×"
			else:result=a;a*=b;op="÷"
	g.display_prompt="%d %s %d = ?"%[a,op,b]
	var answers:Array=[result];var values:=level.branch_values(g)
	for delta in [1,-1,2,-2,3]:
		if result+delta>=0 and not answers.has(result+delta):answers.append(result+delta)
	for i in values.size():g.display_choices[str(values[i])]=str(answers[i])
