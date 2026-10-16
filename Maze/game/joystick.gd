class_name MazeJoystick
extends Control
signal throw_requested
var vector:=Vector2.ZERO
var pointer:=-1
var ammo:=0
var blink:=0.0
var pressed_at:=Vector2.ZERO
var dragging:=false
var clock:=0.0
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
func set_ammo(value:int)->void:
	if value>ammo:blink=2.8
	ammo=value;queue_redraw()
func _process(dt:float)->void:
	clock+=dt;blink=maxf(0,blink-dt)
	if blink>0:queue_redraw()
func begin(id:int,p:Vector2)->void:
	if pointer!=-1:return
	pointer=id;pressed_at=p;dragging=p.distance_to(size/2)>size.x*.23
	if dragging:set_knob(p)
func end(id:int)->void:
	if pointer!=id:return
	if not dragging and ammo>0:blink=0;throw_requested.emit()
	pointer=-1;vector=Vector2.ZERO;dragging=false;queue_redraw()
func drag(id:int,p:Vector2)->void:
	if pointer!=id:return
	if p.distance_to(pressed_at)>12:dragging=true
	if dragging:set_knob(p)
func _gui_input(event:InputEvent)->void:
	if event is InputEventScreenTouch:
		if event.pressed:begin(event.index,event.position)
		else:end(event.index)
	elif event is InputEventScreenDrag:drag(event.index,event.position)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:begin(-2,event.position)
		else:end(-2)
	elif event is InputEventMouseMotion:drag(-2,event.position)
	accept_event()
func set_knob(p:Vector2)->void:
	vector=((p-size/2)/(size.x*.32)).limit_length();queue_redraw()
func _draw()->void:
	var c:=size/2;var r:=size.x*.46
	draw_circle(c+Vector2(0,6),r,Color("73b5d9"));draw_circle(c,r,Color(.9,.97,1,.93));draw_arc(c,r,0,TAU,64,Color("b0e5ff"),3,true);draw_arc(c,r-5,PI,TAU,48,Color.WHITE,3,true)
	for d in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:draw_circle(c+d*r*.72,4,Color("519ec9"))
	var at:=c+vector*r*.58
	if ammo<=0:
		draw_circle(at,r*.34,Color("309ddc"));draw_circle(at+Vector2(-4,-6),r*.2,Color("b6eeff"));return
	var pulse:=1.0+(.12*sin(clock*TAU*1.8) if blink>0 else 0.0)
	draw_circle(at,r*.39*pulse,Color("d8f7ff"))
	draw_set_transform(at,0,Vector2(.82,1.02)*pulse)
	draw_circle(Vector2(0,-3),r*.3,Color("16aee1"));draw_circle(Vector2(-6,-11),r*.11,Color("aff4ff"))
	draw_colored_polygon(PackedVector2Array([Vector2(-5,r*.23),Vector2(5,r*.23),Vector2(0,r*.35)]),Color("087bb0"))
	draw_set_transform(Vector2.ZERO)
	draw_string(ThemeDB.fallback_font,at+Vector2(-8,r*.7),str(ammo),HORIZONTAL_ALIGNMENT_CENTER,24,18,Color("203955"))
