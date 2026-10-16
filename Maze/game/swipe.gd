class_name MazeSwipe
extends RefCounted
# Shared screen-space convention with the visible joystick. Pointer ownership
# prevents another finger (Throw/Map) from redirecting or stopping movement.
var pointer:=-1
var origin:=Vector2.ZERO
var vector:=Vector2.ZERO
var radius:=64.0
func begin(id:int,at:Vector2,reach:float)->bool:
	if pointer!=-1:return false
	pointer=id;origin=at;radius=maxf(24,reach);vector=Vector2.ZERO
	return true
func drag(id:int,at:Vector2)->void:
	if id==pointer:vector=((at-origin)/radius).limit_length()
func end(id:int)->void:
	if id==pointer:reset()
func reset()->void:
	pointer=-1;vector=Vector2.ZERO
