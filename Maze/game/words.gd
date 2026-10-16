class_name MazeWords
extends RefCounted
# Authored teaching units preserve Indic vowel signs and joined-language graphemes.
# A word's visual string is joined normally; the cubes use these explicit units.
const BANKS := {
 "en":[["C","A","T"],["S","U","N"],["D","O","G"],["M","O","O","N"],["S","T","A","R"],["B","I","R","D"],["T","R","E","E"],["W","A","T","E","R"],["G","A","R","D","E","N"],["R","A","I","N","B","O","W"]],
 "he":[["ש","מ","ש"],["ח","ת","ו","ל"],["כ","ל","ב"],["י","ר","ח"],["כ","ו","כ","ב"],["צ","י","פ","ו","ר"],["ע","ץ"],["מ","י","ם"],["ג","י","נ","ה"],["ק","ש","ת"]],
 "nl":[["K","A","T"],["Z","O","N"],["H","O","N","D"],["M","A","A","N"],["S","T","E","R"],["V","O","G","E","L"],["B","O","O","M"],["W","A","T","E","R"],["T","U","I","N"],["R","E","G","E","N","B","O","O","G"]],
 "es":[["G","A","T","O"],["S","O","L"],["P","E","R","R","O"],["L","U","N","A"],["E","S","T","R","E","L","L","A"],["P","Á","J","A","R","O"],["Á","R","B","O","L"],["A","G","U","A"],["J","A","R","D","Í","N"],["A","R","C","O","Í","R","I","S"]],
 "fr":[["C","H","A","T"],["S","O","L","E","I","L"],["C","H","I","E","N"],["L","U","N","E"],["É","T","O","I","L","E"],["O","I","S","E","A","U"],["A","R","B","R","E"],["E","A","U"],["J","A","R","D","I","N"],["P","A","P","I","L","L","O","N"]],
 "hi":[["बि","ल्ली"],["सू","र","ज"],["कु","त्ता"],["चाँ","द"],["ता","रा"],["चि","ड़ि","या"],["पे","ड़"],["पा","नी"],["ब","गी","चा"],["ति","त","ली"]],
 "ar":[["ق","ط"],["ش","م","س"],["ك","ل","ب"],["ق","م","ر"],["ن","ج","م"],["ط","ا","ئ","ر"],["ش","ج","ر","ة"],["م","ا","ء"],["ح","د","ي","ق","ة"],["ف","ر","ا","ش","ة"]]
}
const NAMES := {"en":"English","he":"עברית","nl":"Nederlands","es":"Español","fr":"Français","hi":"हिन्दी","ar":"العربية"}
const STUDY_CODES := ["en","he","es","fr"]
static func eligible(_primary_os:String)->Array:
	return STUDY_CODES.duplicate()
static func units(language:String,level:int,mastery:float=-1)->Array:
	var bank:Array=BANKS.get(language,BANKS.en)
	var chosen:Array=bank[(level-1)%mini(bank.size(),3+(level/10))]
	# Familiar vocabulary at lower mastery, with the same unit count and reward.
	if mastery>=0 and mastery<.35:
		for word in bank:
			if word.size()==chosen.size():chosen=word;break
	return chosen.duplicate()
