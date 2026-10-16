class_name MazeJourney
extends Control
signal selected(level:int)
signal expanded
var current:=1
var first:=0
var bests:Dictionary={}
var nodes:Array=[]
var backdrop:Texture2D
var mascot:Texture2D
const PLACES:=[Vector2(.175,.79),Vector2(.32,.775),Vector2(.395,.55),Vector2(.50,.43),Vector2(.605,.48),Vector2(.695,.54),Vector2(.775,.46),Vector2(.914,.56)]
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_STOP;layout_direction=Control.LAYOUT_DIRECTION_LTR
	backdrop=ImageTexture.create_from_image(Image.load_from_file("res://art/ui/stages-background.png"))
	mascot=ImageTexture.create_from_image(Image.load_from_file("res://art/ui/journey-minik.png"))
	resized.connect(queue_redraw)
func _draw()->void:
	var art_size:=Vector2(size.x,size.x*856.0/1836.0)
	if art_size.y>size.y:art_size*=size.y/art_size.y
	var origin:=(size-art_size)/2
	draw_texture_rect(backdrop,Rect2(origin,art_size),false)
	nodes=[]
	var start:=maxi(1,current-1) if first==0 else first
	var count:=mini(8,101-start);var curve:=Curve2D.new()
	for i in count:
		var point:Vector2=origin+PLACES[i]*art_size
		nodes.append({"level":start+i,"point":point})
		var tangent:Vector2=(PLACES[mini(i+1,count-1)]-PLACES[maxi(0,i-1)])*art_size*.18
		curve.add_point(point,-tangent if i>0 else Vector2.ZERO,tangent if i<count-1 else Vector2.ZERO)
	# A soft illustrated route ends at the last circle; no trail beyond level 100.
	if count>1:
		var line:=curve.get_baked_points()
		for pair in [[Color("9265b2"),.050],[Color("d9a650"),.043],[Color("ffdf83"),.038],[Color("ffedb7"),.022]]:
			draw_polyline(line,pair[0],maxf(2,art_size.x*float(pair[1])),true)
	var font:=MazeSkyUI.font(true);var radius:=art_size.x*.030
	for node in nodes:
		var point:Vector2=node.point;var id:int=node.level;var done:=bests.has(str(id))
		draw_circle(point+Vector2(0,3),radius+3,Color("785c98"))
		draw_circle(point,radius+3,Color.WHITE)
		draw_circle(point,radius,Color("53b7f3") if done else Color("ffce61"))
		draw_arc(point,radius-2,PI,TAU,32,Color("bfeeff") if done else Color("ffe9a8"),2,true)
		var value:=str(id);var fs:=maxi(15,int(radius*1.1));var measured:=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs)
		var baseline:=point+Vector2(-measured.x/2,(font.get_ascent(fs)-font.get_descent(fs))/2-1)
		draw_string_outline(font,baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,2,Color("ba863a") if not done else Color("2589bf"))
		draw_string(font,baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color.WHITE)
		if id==current:
			var cat_size:=Vector2(art_size.x*.13,art_size.x*.145)
			draw_texture_rect(mascot,Rect2(point-Vector2(cat_size.x/2,radius+cat_size.y+4),cat_size),false)
func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for node in nodes:
			if event.position.distance_to(node.point)<maxf(24,size.x*.034):
				if node.level<=current:selected.emit(node.level)
				accept_event();return
		expanded.emit();accept_event()
