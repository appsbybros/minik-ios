class_name MazeSkyUI
extends RefCounted

const INK:=Color("204878")
const BLUE:=Color("a6dcff")
const GOLD:=Color("ffe59d")
const MINT:=Color("b1eddb")
const PINK:=Color("e63f89")
static var textures:Dictionary={}
static var fonts:Dictionary={}
static func font(bold:bool=false)->FontFile:
	var key:="bold" if bold else "medium"
	if not fonts.has(key):
		var f:=FontFile.new();f.data=FileAccess.get_file_as_bytes("res://art/ui/fredoka_"+key+".ttf");fonts[key]=f
	return fonts[key]
static func svg_texture(key:String,svg:String)->ImageTexture:
	if not textures.has(key):
		var image:=Image.new();image.load_svg_from_string(svg);textures[key]=ImageTexture.create_from_image(image)
	return textures[key]
static func palette(c:Color)->Color:
	if c.a<.1:return BLUE
	if c.r>.95 and c.g>.9 and c.b>.9:return Color("e8f6ff")
	if c.r>c.g*1.2 and c.b<c.r*.86:return Color("ffb8b3")
	if c.r>.9 and c.g>.7 and c.b<.72:return GOLD
	if c.g>c.r*1.06 and c.g>c.b*.98:return MINT
	if c.r>.7 and c.b>.9 and c.g<c.b*.94:return BLUE
	return BLUE
static func surface(c:Color=BLUE,pressed:bool=false,panel:bool=false,disabled:bool=false)->StyleBoxTexture:
	var base:=c;var key:=c.to_html()+str(pressed)+str(panel)+str(disabled)
	var pink:=c==PINK
	var upper:="#"+base.lightened(.75 if not pink else .32).to_html(false)
	var lower:="#"+base.lightened(.32 if not pink else 0).to_html(false)
	var edge:="#"+base.darkened(.18 if not pink else .25).to_html(false)
	var border:="#"+base.lightened(.05).to_html(false)
	if disabled:upper="#f2f5f8";lower="#dce7ef";edge="#b4cadb";border="#c5dbe8"
	var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="240" height="80"><defs><linearGradient id="face" x2="0" y2="1"><stop stop-color="%s"/><stop offset=".48" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient><linearGradient id="shine" x2="0" y2="1"><stop stop-color="white" stop-opacity=".9"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient></defs>' % [upper,lower,lower]
	if panel:
		svg='<svg xmlns="http://www.w3.org/2000/svg" width="240" height="320"><defs><linearGradient id="face" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#dff5ff"/><stop offset=".35" stop-color="#fffef2"/><stop offset=".7" stop-color="#f4fbff"/><stop offset="1" stop-color="#ffdeeb"/></linearGradient></defs><rect x="4" y="10" width="232" height="304" rx="30" fill="#3869a5" opacity=".18"/><rect x="4" y="3" width="232" height="303" rx="30" fill="url(#face)" stroke="#ffffff" stroke-width="3"/><path d="M26 18 Q90 4 160 18" fill="none" stroke="white" stroke-width="4" opacity=".8"/></svg>'
	else:
		var y:=7 if pressed else 1
		svg+='<rect x="4" y="12" width="232" height="63" rx="24" fill="#3869a5" opacity=".18"/><rect x="5" y="9" width="230" height="60" rx="23" fill="%s"/><rect x="5" y="%s" width="230" height="60" rx="23" fill="url(#face)" stroke="%s" stroke-width="2"/><rect x="13" y="%s" width="214" height="54" rx="19" fill="none" stroke="white" stroke-opacity=".72" stroke-width="2"/><rect x="25" y="%s" width="190" height="15" rx="7" fill="url(#shine)"/></svg>' % [edge,str(y),border,str(y+4),str(y+6)]
	var s:=StyleBoxTexture.new();s.texture=svg_texture(key,svg)
	s.texture_margin_left=36;s.texture_margin_right=36;s.texture_margin_top=32 if panel else 24;s.texture_margin_bottom=36 if panel else 28
	s.content_margin_left=20;s.content_margin_right=20;s.content_margin_top=14 if panel else 8;s.content_margin_bottom=14 if panel else 20
	return s
static func dress(b:BaseButton,c:Color=BLUE)->void:
	b.mouse_filter=Control.MOUSE_FILTER_PASS
	for state in ["normal","hover","pressed","disabled","normal_mirrored","hover_mirrored","pressed_mirrored","disabled_mirrored"]:
		b.add_theme_stylebox_override(state,surface(c,state.begins_with("pressed"),false,state.begins_with("disabled")))
	var focus:=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=Color("2587d6");focus.set_border_width_all(3);focus.set_corner_radius_all(25);b.add_theme_stylebox_override("focus",focus)
	for key in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:b.add_theme_color_override(key,Color.WHITE if c==PINK else INK)
	b.add_theme_color_override("font_disabled_color",Color("718b9e"));b.add_theme_font_override("font",font(true))
static func toggle(b:CheckButton)->void:
	dress(b,BLUE)
	for on in [false,true]:
		var x:=43 if on else 17
		var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="38"><rect x="2" y="3" width="60" height="32" rx="16" fill="%s"/><rect x="4" y="4" width="56" height="25" rx="13" fill="%s"/><circle cx="%s" cy="17" r="12" fill="white" stroke="#b8ddf4" stroke-width="2"/></svg>' % ["#269d90" if on else "#6999be","#70d4bd" if on else "#c8e4f5",str(x)]
		for suffix in ["","_mirrored"]:
			var image:=svg
			if suffix!="":image=svg.replace('cx="%s"'%str(x),'cx="%s"'%str(64-x))
			b.add_theme_icon_override(("checked" if on else "unchecked")+suffix,svg_texture("toggle"+str(on)+suffix,image))
static func compact(b:Button)->void:
	dress(b)
	var t:=svg_texture("round-control",'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><defs><linearGradient id="b" x2="0" y2="1"><stop stop-color="white"/><stop offset="1" stop-color="#a6dcff"/></linearGradient></defs><circle cx="32" cy="35" r="28" fill="#719bb9" opacity=".3"/><circle cx="32" cy="32" r="28" fill="#69aed8"/><circle cx="32" cy="28" r="26" fill="url(#b)" stroke="#b8e8ff" stroke-width="2"/><ellipse cx="29" cy="15" rx="17" ry="8" fill="white" opacity=".7"/></svg>')
	for key in ["normal","hover","pressed","normal_mirrored","hover_mirrored","pressed_mirrored"]:
		var skin:=StyleBoxTexture.new();skin.texture=t;skin.set_content_margin_all(0)
		if key.begins_with("pressed"):skin.modulate_color=Color("c6e6fa")
		b.add_theme_stylebox_override(key,skin)
 
static func backdrop(parent:Control)->void:
	var t:=TextureRect.new();t.name="SkyBackdrop";t.mouse_filter=Control.MOUSE_FILTER_IGNORE;t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.texture=svg_texture("sky",'<svg xmlns="http://www.w3.org/2000/svg" width="720" height="1200"><defs><linearGradient id="s" x2="0" y2="1"><stop stop-color="#6ac5ee"/><stop offset=".5" stop-color="#ceeefe"/><stop offset="1" stop-color="#fbd4e4"/></linearGradient><radialGradient id="c"><stop stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></radialGradient></defs><rect width="720" height="1200" fill="url(#s)"/><g fill="white" opacity=".6"><ellipse cx="80" cy="160" rx="150" ry="65"/><ellipse cx="150" cy="130" rx="90" ry="60"/><ellipse cx="630" cy="430" rx="170" ry="80"/><ellipse cx="690" cy="380" rx="100" ry="80"/><ellipse cx="60" cy="950" rx="180" ry="70"/><ellipse cx="220" cy="1020" rx="150" ry="85"/><ellipse cx="600" cy="1120" rx="250" ry="75"/></g><g fill="#fffaf0"><path d="M560 110l4 14 14 4-14 4-4 14-4-14-14-4 14-4z"/><path d="M100 570l4 14 14 4-14 4-4 14-4-14-14-4 14-4z"/><path d="M660 810l4 14 14 4-14 4-4 14-4-14-14-4 14-4z"/></g></svg>')
	parent.add_child(t);t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
