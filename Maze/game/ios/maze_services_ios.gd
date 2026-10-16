extends Node
## iOS stand-in for the Android host's MazeServices plugin (MinikMaze app/src/main/java/.../MazeServices.kt).
## world.gd finds it as the "MazeServices" engine singleton and uses the same methods and signals:
## - the grown-up gate (Android FamilyAdultGate) before the parent area, learning settings, the purchase and links;
## - the permanent unlock through the App Store (MazeStoreKit, Maze/native); without it "Purchase unavailable";
## - the privacy page (an iOS text, ios/privacy) and More Minik apps (the bundled family catalogue);
## - no ads, as on Android; result_break only reports the break as finished.
## The online records stay on Android (Maze/README.md), so this has no load_records and world.gd hides them.

@warning_ignore("unused_signal")
signal records_changed(raw:String)
@warning_ignore("unused_signal")
signal test_level_selected(level:int)
signal break_finished
signal learning_settings
signal grown_up
signal ownership_changed(owned:bool)

const PRODUCT:="full_game_unlock"
const SETTINGS:="user://maze_services.cfg"
const SUPPORT:="appsbybros.dev@gmail.com"
const DIRECTORY:="https://miniklearn.com/apps/index.html"
const APPLICATION_ID:="com.appsbybros.minik.maze"
const LANDING_HOSTS:=["miniklearn.com","easycallandanswer.com"]

var language:="en"
var copy:Dictionary={}
var family_text:Dictionary={}
var owned:=false
var store:Object
var configured:=false
var layer:CanvasLayer
var dialogs:Array[Control]=[]
var keyboard_panel:Control
var last_keyboard:=-1.0

func _init()->void:
	# "-- --ios-services" turns the same services on in a desktop run, for testing.
	if not (OS.get_name()=="iOS" or OS.get_cmdline_user_args().has("--ios-services")):return
	var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://ios/family-text.json"))
	if parsed is Dictionary:family_text=parsed
	var settings:=ConfigFile.new()
	if settings.load(SETTINGS)==OK:owned=bool(settings.get_value("store","owned",false))
	if ClassDB.class_exists("MazeStoreKit"):
		store=ClassDB.instantiate("MazeStoreKit")
		store.connect("owned",_store_owned)
		store.connect("purchase_failed",_store_failed)
		store.connect("restore_finished",_store_restored)
		# world.gd redraws an open unlock screen on ownership_changed, which also shows a price that arrived late.
		store.connect("price_changed",func(_price):ownership_changed.emit(owned))
	layer=CanvasLayer.new();layer.layer=100;add_child(layer)
	Engine.register_singleton("MazeServices",self)

func _ready()->void:
	if layer!=null:get_viewport().size_changed.connect(_place_all)

# ---- Android MazeServices methods ---------------------------------------------------------------------------------

func test_tools_available()->bool:return false # Android: debug builds only.
func choose_test_level(_current,_locale)->void:pass
func idle_menu()->void:pass # No advertising or remove-ads prompts.
func primary_language()->String:return OS.get_locale_language()
func full_game_owned()->bool:return owned
func unlock_price()->String:return str(store.get_price()) if store!=null else ""
func result_break(_id,_seconds)->void:break_finished.emit.call_deferred()
func learning_settings_gate()->void:gate(learning_settings.emit)
func parent_menu()->void:gate(grown_up.emit)
func buy_full_game()->void:gate(_buy)
func more_apps()->void:show_more_apps()
func show_privacy()->void:show_privacy_page()
func report_concern()->void:
	gate(func():open_link("mailto:%s?subject=Minik%%20Maze%%20record%%20report"%SUPPORT))

func configure(locale:String,strings:String)->void:
	language=locale
	var parsed=JSON.parse_string(strings)
	copy=parsed if parsed is Dictionary else {}
	if configured:return
	configured=true
	if store!=null:store.start(PRODUCT)

func restore_full_game()->void:
	if store==null:notice(t("Purchase unavailable. Please try again later."));return
	store.restore()

# ---- App Store ------------------------------------------------------------------------------------------------------

func _buy()->void:
	if store==null or not store.can_buy():notice(t("Purchase unavailable. Please try again later."));return
	store.buy()

func _store_owned()->void:set_owned(true)
func _store_failed(reason:String)->void:
	if reason!="cancelled":notice(t("Purchase unavailable. Please try again later."))
# Android restore(): the ownership is what the store reports.
func _store_restored(found:bool)->void:set_owned(found)

func set_owned(value:bool)->void:
	owned=value
	var settings:=ConfigFile.new();settings.load(SETTINGS)
	settings.set_value("store","owned",value);settings.save(SETTINGS)
	ownership_changed.emit(value)

# ---- texts ------------------------------------------------------------------------------------------------------------

func t(key:String)->String:return str(copy.get(key,key))
## Android FamilyMessages.text / FamilyText: the family controls in the game's language, else English.
func ft(key:String)->String:
	var row:Dictionary=family_text.get(key,{})
	var value:=str(row.get(language,""))
	return value if value!="" else key
func rtl()->bool:return language in ["he","ar"]

# ---- dialogs ----------------------------------------------------------------------------------------------------------

func label(value:String,font_size:int=24,bold:bool=false)->Label:
	var l:=Label.new();l.text=value;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size",font_size);l.add_theme_font_override("font",MazeSkyUI.font(bold))
	l.add_theme_color_override("font_color",MazeSkyUI.INK)
	return l

func button(value:String,action:Callable,color:Color=MazeSkyUI.BLUE)->Button:
	var b:=Button.new();b.text=value;b.custom_minimum_size=Vector2(0,68);b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size",26);MazeSkyUI.dress(b,color);b.pressed.connect(action)
	return b

## A sky card over a soft shade. Scrolling cards (privacy, More Minik apps) take most of the screen;
## the others fit their content.
func dialog(title:String,scrolling:bool=false)->VBoxContainer:
	var root:=Control.new();root.name="IOSDialog";root.mouse_filter=Control.MOUSE_FILTER_STOP
	root.layout_direction=Control.LAYOUT_DIRECTION_RTL if rtl() else Control.LAYOUT_DIRECTION_LTR
	root.theme=Theme.new();root.theme.default_font=MazeSkyUI.font()
	layer.add_child(root);root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(0.07,0.16,0.3,0.45);shade.mouse_filter=Control.MOUSE_FILTER_STOP
	root.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=PanelContainer.new();panel.name="Card";panel.add_theme_stylebox_override("panel",MazeSkyUI.surface(MazeSkyUI.BLUE,false,true))
	root.add_child(panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",16);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if scrolling:
		var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
		scroll.add_child(box)
	else:
		panel.add_child(box)
	root.set_meta("scrolling",scrolling)
	if title!="":box.add_child(label(title,30,true))
	dialogs.append(root)
	# Wrapped text is only measured once the card has its width, so the card is placed again then.
	panel.minimum_size_changed.connect(_place.bind(root))
	_place.call_deferred(root)
	return box

## Closes the card that holds `node` (Godot renames same-named siblings, so the card is found in `dialogs`).
func close(node:Control)->void:
	var root:=node
	while root!=null and not dialogs.has(root):root=root.get_parent() as Control
	if root==null:return
	dialogs.erase(root)
	if keyboard_panel!=null and root.is_ancestor_of(keyboard_panel):keyboard_panel=null
	root.queue_free()

func _place_all()->void:
	for root in dialogs:_place(root)

func _place(root:Control)->void:
	if not is_instance_valid(root):return
	var size:=root.get_viewport_rect().size
	var panel:=root.get_node("Card") as PanelContainer
	var w:=minf(size.x-32,660)
	var keyboard:=_keyboard_height(size)
	if bool(root.get_meta("scrolling")):
		panel.size=Vector2(w,minf(size.y-48,980));panel.position=(size-panel.size)/2
		return
	panel.custom_minimum_size.x=w
	var h:=panel.get_combined_minimum_size().y
	# Above the on-screen keyboard while the gate's answer field is in use.
	var top:=clampf(size.y*.14,16,maxf(16,(size.y-h)/2))
	if keyboard>0:top=clampf(size.y-keyboard-h-16,16,top)
	panel.position=Vector2((size.x-w)/2,top);panel.size=Vector2(w,h)

func _keyboard_height(size:Vector2)->float:
	if keyboard_panel==null or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):return 0.0
	var screen:=Vector2(DisplayServer.window_get_size())
	if screen.y<=0:return 0.0
	return DisplayServer.virtual_keyboard_get_height()*size.y/screen.y

func _process(_dt:float)->void:
	if keyboard_panel==null:return
	var height:=float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	if height!=last_keyboard:
		last_keyboard=height
		for root in dialogs:
			if root.is_ancestor_of(keyboard_panel):_place(root)

func notice(message:String)->void:
	var box:=dialog("")
	box.add_child(label(message,26))
	box.add_child(button(t("Close"),func():close(box)))

## Android FamilyAdultGate: a multiplication with an answer field; Continue checks it.
func gate(approved:Callable)->void:
	var x:=4+randi()%6;var y:=3+randi()%6
	var box:=dialog(ft("For a grown-up"))
	var question:=label("%d × %d = ?"%[x,y],34,true);question.text_direction=Control.TEXT_DIRECTION_LTR;box.add_child(question)
	var answer:=LineEdit.new();answer.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER;answer.max_length=3
	answer.alignment=HORIZONTAL_ALIGNMENT_CENTER;answer.custom_minimum_size=Vector2(220,64);answer.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	answer.placeholder_text=ft("Answer");answer.text_direction=Control.TEXT_DIRECTION_LTR;answer.select_all_on_focus=true
	answer.add_theme_font_size_override("font_size",32);answer.add_theme_font_override("font",MazeSkyUI.font(true))
	answer.add_theme_color_override("font_color",Color("17364a"));answer.add_theme_color_override("font_placeholder_color",Color("596776"))
	var field:=StyleBoxFlat.new();field.bg_color=Color("edf4ff");field.border_color=Color("75b9df");field.set_border_width_all(2);field.set_corner_radius_all(18)
	field.content_margin_left=16;field.content_margin_right=16
	answer.add_theme_stylebox_override("normal",field);answer.add_theme_stylebox_override("focus",field)
	box.add_child(answer)
	var error:=label(ft("Try again."),22);error.add_theme_color_override("font_color",Color("b42346"));error.visible=false;box.add_child(error)
	var check:=func():
		var typed:=answer.text.strip_edges()
		if typed.is_valid_int() and int(typed)==x*y:
			close(box);approved.call()
		else:
			error.visible=true;answer.clear();answer.grab_focus()
	answer.text_submitted.connect(func(_text):check.call())
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);box.add_child(row)
	for pair in [[ft("Cancel"),func():close(box),MazeSkyUI.BLUE],[ft("Continue"),check,MazeSkyUI.MINT]]:
		var b:=button(pair[0],pair[1],pair[2]);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(b)
	keyboard_panel=answer
	answer.grab_focus.call_deferred()

func open_link(url:String)->void:
	if OS.shell_open(url)!=OK:notice(ft("No browser is available."))

# ---- privacy page -----------------------------------------------------------------------------------------------------

## The iOS privacy text (ios/privacy/<language>.html) as BBCode; its links open after the grown-up gate.
func show_privacy_page()->void:
	var lang:=language if FileAccess.file_exists("res://ios/privacy/%s.html"%language) else "en"
	var html:=FileAccess.get_file_as_string("res://ios/privacy/%s.html"%lang)
	var box:=dialog(t("Privacy policy"),true)
	var page:=RichTextLabel.new();page.bbcode_enabled=true;page.fit_content=true;page.scroll_active=false
	page.size_flags_horizontal=Control.SIZE_EXPAND_FILL;page.selection_enabled=false
	page.text_direction=Control.TEXT_DIRECTION_RTL if lang in ["he","ar"] else Control.TEXT_DIRECTION_LTR
	page.add_theme_font_override("normal_font",MazeSkyUI.font());page.add_theme_font_override("bold_font",MazeSkyUI.font(true))
	page.add_theme_font_size_override("normal_font_size",21);page.add_theme_font_size_override("bold_font_size",23)
	page.add_theme_color_override("default_color",MazeSkyUI.INK);page.add_theme_constant_override("line_separation",4)
	page.text=privacy_bbcode(html)
	page.meta_clicked.connect(func(meta):gate(open_link.bind(str(meta))))
	box.add_child(page)
	box.add_child(button(t("Close"),func():close(box)))

static func privacy_bbcode(html:String)->String:
	var body:=html.substr(html.find("<body"))
	body=body.substr(body.find(">")+1).replace("</body>","")
	var tags:=RegEx.create_from_string("<h1[^>]*>.*?</h1>")
	body=tags.sub(body,"",true) # The card already shows the title.
	var out:=body.replace("[","(").replace("]",")")
	out=RegEx.create_from_string("<h2[^>]*>(.*?)</h2>").sub(out,"[b]$1[/b]\n\n",true)
	out=RegEx.create_from_string("<a href=\"(https://[^\"]+)\">(.*?)</a>").sub(out,"[url=$1][u]$2[/u][/url]",true)
	out=RegEx.create_from_string("<p[^>]*>(.*?)</p>").sub(out,"$1\n\n",true)
	out=RegEx.create_from_string("<[^>]+>").sub(out,"",true)
	return out.replace("&amp;","&").replace("&lt;","<").replace("&gt;",">").strip_edges()

# ---- More Minik apps --------------------------------------------------------------------------------------------------

## Android FamilyMessages.showMoreApps: one other family app from the bundled catalogue, with links behind the gate.
func show_more_apps()->void:
	var entry:=choose_family_app()
	if entry.is_empty():
		gate(open_link.bind(DIRECTORY));return
	var box:=dialog("",true)
	var eyebrow:=label(ft("From the Minik family"),20,true);eyebrow.add_theme_color_override("font_color",Color("6951a1"));box.add_child(eyebrow)
	var asset:=localized(entry.get("artAsset",{}))
	if RegEx.create_from_string("^minik-family/art/[a-z0-9_-]+\\.(png|webp|jpg)$").search(asset)!=null and FileAccess.file_exists("res://"+asset):
		var image:=Image.load_from_file("res://"+asset)
		if image!=null and not image.is_empty():
			var art:=TextureRect.new();art.texture=ImageTexture.create_from_image(image);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.custom_minimum_size=Vector2(0,280);box.add_child(art)
	box.add_child(label(localized(entry.get("title",{})),30,true))
	box.add_child(label(localized(entry.get("body",{})),22))
	box.add_child(label(ft("Discover all our apps and games at miniklearn.com."),19))
	for link in [["landingUrl","Meet this app",LANDING_HOSTS],["webUrl","Play on the website",LANDING_HOSTS],["iosUrl","Also available for iPhone",["apps.apple.com"]]]:
		var url:=safe_link(str(entry.get(link[0],"")),link[2])
		if url!="":box.add_child(button(ft(link[1]),gate.bind(open_link.bind(url))))
	box.add_child(button(ft("All our apps & games"),gate.bind(open_link.bind(DIRECTORY))))
	box.add_child(button(ft("Keep playing"),func():close(box),MazeSkyUI.MINT))

func choose_family_app()->Dictionary:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://minik-family/catalog.json"))
	if not parsed is Dictionary or not bool(parsed.get("enabled",true)) or not parsed.get("apps") is Dictionary:return {}
	var choices:Array[Dictionary]=[];var total:=0
	for key in parsed.apps:
		var entry=parsed.apps[key]
		if not entry is Dictionary or not bool(entry.get("enabled",true)):continue
		if not (entry.get("title") is Dictionary and entry.get("body") is Dictionary and entry.title.has("en") and entry.body.has("en")):continue
		var names:Array=[str(entry.get("applicationId",""))]
		if entry.get("aliases") is Array:names.append_array(entry.aliases)
		var own:=false
		for alias in names:
			if APPLICATION_ID==str(alias) or APPLICATION_ID.begins_with(str(alias)+".debug") or APPLICATION_ID.begins_with(str(alias)+".qa"):own=true
		if own:continue
		choices.append(entry);total+=clampi(int(entry.get("weight",1)),1,20)
	if choices.is_empty():return {}
	var pick:=randi()%total
	for entry in choices:
		pick-=clampi(int(entry.get("weight",1)),1,20)
		if pick<0:return entry
	return choices[-1]

func localized(values)->String:
	if not values is Dictionary:return ""
	if values.has(language):return str(values[language])
	var base:=language.split("-")[0]
	if values.has(base):return str(values[base])
	return str(values.get("en",""))

static func safe_link(url:String,hosts:Array)->String:
	if not url.begins_with("https://"):return ""
	var host:=url.trim_prefix("https://").split("/")[0].to_lower()
	for allowed in hosts:
		if host==allowed or host.ends_with("."+allowed):return url
	return ""
