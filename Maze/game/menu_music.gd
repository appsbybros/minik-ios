extends AudioStreamPlayer
# Two persistent players crossfade between the full menu song and quiet gameplay loop.
const MENU_GAIN:=0.5
const GAME_GAIN:=0.12
var game:=AudioStreamPlayer.new()
var game_gain:=0.0
const FADE_SECONDS:=0.9
var gain:=0.0
var foreground:=true
var focused:=true

func _ready()->void:
 name="MenuMusic"
 var song:=AudioStreamMP3.new()
 song.data=FileAccess.get_file_as_bytes("res://audio/Pixel_Parade_Arcade_Full.mp3")
 song.loop=true
 stream=song
 volume_db=-80
 game.name="GameplayMusic"
 var loop:=AudioStreamWAV.load_from_file("res://audio/Pixel_Parade_Arcade_Game_Loop.wav")
 loop.loop_mode=AudioStreamWAV.LOOP_FORWARD
 loop.loop_begin=0
 loop.loop_end=loop.data.size()/4-1 # Final PCM frame is a copy of frame zero: wrap guard, outside loop.
 game.stream=loop
 game.volume_db=-80
 add_child(game)

func silence()->void:
 gain=0.0
 volume_db=-80
 stream_paused=true
 game_gain=0.0
 game.volume_db=-80
 game.stream_paused=true

func update_music(dt:float,menus:bool,enabled:bool,advertising:bool)->void:
 if not enabled or not foreground or not focused or advertising:
  silence()
  return
 var target:=MENU_GAIN if menus else 0.0
 gain=move_toward(gain,target,MENU_GAIN*dt/FADE_SECONDS)
 if gain>0:
  if not has_stream_playback():play()
  stream_paused=false
  volume_db=linear_to_db(gain)
 else:
  volume_db=-80
  stream_paused=true
 var game_target:=0.0 if menus else GAME_GAIN
 game_gain=move_toward(game_gain,game_target,GAME_GAIN*dt/FADE_SECONDS)
 if game_gain>0:
  if not game.has_stream_playback():game.play()
  game.stream_paused=false
  game.volume_db=linear_to_db(game_gain)
 else:
  game.volume_db=-80
  game.stream_paused=true

func _notification(what:int)->void:
 if what==NOTIFICATION_APPLICATION_PAUSED:
  foreground=false
  silence()
 elif what==NOTIFICATION_APPLICATION_RESUMED:foreground=true
 elif what==NOTIFICATION_APPLICATION_FOCUS_OUT:
  focused=false
  silence()
 elif what==NOTIFICATION_APPLICATION_FOCUS_IN:focused=true
