extends Control
## Main
## Ponto de entrada do jogo. Constrói toda a interface por código (sem
## depender de nós pré-montados no editor), simulando a tela de um
## monitor CRT onde roda um desktop no estilo Windows XP.
##
## Fluxo de estados:
##   BOOT -> DESKTOP -> EMAIL (recado do chefe) -> RACE (typeracer) ->
##   RESULT (venceu/perdeu) -> volta pro DESKTOP, ou FIRED / VICTORY no fim.

enum State { BOOT, DESKTOP, EMAIL, RACE, RESULT, FIRED, VICTORY }

# ---------------------------------------------------------------------------
# Paleta "Windows XP"
# ---------------------------------------------------------------------------
const C_BEZEL := Color(0.08, 0.08, 0.09)
const C_SCREEN_OFF := Color(0, 0, 0)
const C_DESKTOP := Color(0.10, 0.35, 0.68)
const C_TASKBAR := Color(0.13, 0.44, 0.85)
const C_TASKBAR_DARK := Color(0.05, 0.22, 0.55)
const C_START_GREEN := Color(0.20, 0.62, 0.22)
const C_WINDOW_BG := Color(0.93, 0.93, 0.91)
const C_TITLEBAR_A := Color(0.10, 0.32, 0.85)
const C_TITLEBAR_B := Color(0.35, 0.58, 0.95)
const C_TEXT_DARK := Color(0.10, 0.10, 0.10)
const C_PLAYER_BAR := Color(0.20, 0.75, 0.25)
const C_AI_BAR := Color(0.85, 0.20, 0.20)
const C_ERROR := Color(0.80, 0.10, 0.10)

var state: State = State.BOOT

# Referências construídas em tempo de execução.
var screen: Control
var desktop_layer: Control
var window_layer: Control
var taskbar_clock: Label
var email_icon_flash: bool = false

# --- Variáveis da corrida (race) ---
var race_code: String = ""
var race_input: TextEdit
var race_target_label: RichTextLabel
var race_player_bar: ProgressBar
var race_ai_bar: ProgressBar
var race_status_label: Label
var race_ai_progress_chars: float = 0.0
var race_ai_wpm: float = 30.0
var race_ai_stutter_chance: float = 0.1
var race_ai_stutter_timer: float = 0.0
var race_finished: bool = false
var race_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(1280, 720)
	_build_monitor_frame()
	_show_boot_sequence()


func _process(delta: float) -> void:
	if race_active and not race_finished:
		_update_ai_progress(delta)


# ---------------------------------------------------------------------------
# MONTAGEM DO MONITOR (moldura + "tela")
# ---------------------------------------------------------------------------
func _build_monitor_frame() -> void:
	var bezel := ColorRect.new()
	bezel.color = C_BEZEL
	bezel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bezel)

	var stand := ColorRect.new()
	stand.color = C_BEZEL.lightened(0.05)
	stand.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	stand.size = Vector2(220, 26)
	stand.position = Vector2(-110, -6)
	bezel.add_child(stand)

	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.offset_left = 36
	screen.offset_top = 36
	screen.offset_right = -36
	screen.offset_bottom = -70
	screen.clip_contents = true
	bezel.add_child(screen)

	var screen_bg := ColorRect.new()
	screen_bg.color = C_SCREEN_OFF
	screen_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(screen_bg)

	# leve vinheta/scanline pra dar um clima de CRT (bem sutil)
	var vignette := ColorRect.new()
	vignette.color = Color(0, 0, 0, 0.12)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(vignette)


func _show_boot_sequence() -> void:
	state = State.BOOT
	var boot_label := Label.new()
	boot_label.text = "Iniciando sistema...\n\nCodeCorp OS v2001"
	boot_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	boot_label.add_theme_font_size_override("font_size", 22)
	boot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boot_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(boot_label)

	var t := get_tree().create_timer(1.6)
	t.timeout.connect(func():
		boot_label.queue_free()
		_build_desktop()
	)


# ---------------------------------------------------------------------------
# DESKTOP
# ---------------------------------------------------------------------------
func _build_desktop() -> void:
	state = State.DESKTOP

	for c in screen.get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = C_DESKTOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	desktop_layer = Control.new()
	desktop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(desktop_layer)

	# Cabeçalho com status da campanha
	var hud := Label.new()
	var cfg: Dictionary = GameManager.get_current_config()
	hud.text = "%s   |   Avisos: %d/%d" % [cfg["title"], GameManager.total_losses, GameManager.MAX_LOSSES]
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_font_size_override("font_size", 16)
	hud.position = Vector2(16, 10)
	desktop_layer.add_child(hud)

	# Ícones do desktop
	_add_desktop_icon(desktop_layer, Vector2(30, 60), "Outlook\nExpress", Color(0.95, 0.85, 0.2), true, _open_email)
	_add_desktop_icon(desktop_layer, Vector2(30, 170), "Editor de\nCódigo", Color(0.25, 0.55, 0.95), false, _try_open_editor)
	_add_desktop_icon(desktop_layer, Vector2(30, 280), "Meu\nComputador", Color(0.8, 0.8, 0.85), false, func(): _show_toast("Nada de interessante por aqui..."))
	_add_desktop_icon(desktop_layer, Vector2(30, 390), "Lixeira", Color(0.6, 0.6, 0.65), false, func(): _show_toast("A lixeira está vazia."))

	# Camada de janelas (fica por cima de tudo, mas ainda dentro da tela)
	window_layer = Control.new()
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(window_layer)

	_build_taskbar()


func _add_desktop_icon(parent: Control, pos: Vector2, caption: String, tint: Color, notify: bool, on_activate: Callable) -> void:
	var box := VBoxContainer.new()
	box.position = pos
	box.custom_minimum_size = Vector2(72, 84)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_panel := Panel.new()
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.custom_minimum_size = Vector2(48, 48)
	icon_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1, 1, 1, 0.6)
	icon_panel.add_theme_stylebox_override("panel", sb)
	box.add_child(icon_panel)

	if notify:
		var badge := Label.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.text = "!"
		badge.add_theme_color_override("font_color", Color(1, 1, 1))
		badge.add_theme_font_size_override("font_size", 14)
		var badge_bg := Panel.new()
		badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.9, 0.15, 0.15)
		bsb.corner_radius_top_left = 8
		bsb.corner_radius_top_right = 8
		bsb.corner_radius_bottom_left = 8
		bsb.corner_radius_bottom_right = 8
		badge_bg.add_theme_stylebox_override("panel", bsb)
		badge_bg.custom_minimum_size = Vector2(16, 16)
		badge_bg.position = Vector2(34, -4)
		badge_bg.add_child(badge)
		icon_panel.add_child(badge_bg)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)

	box.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_activate.call()
	)

	parent.add_child(box)


func _build_taskbar() -> void:
	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TASKBAR
	sb.border_width_top = 2
	sb.border_color = Color(0.7, 0.85, 1.0)
	bar.add_theme_stylebox_override("panel", sb)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.custom_minimum_size = Vector2(0, 36)
	bar.offset_top = -36
	bar.offset_bottom = 0
	screen.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	bar.add_child(hbox)

	var start_btn := Button.new()
	start_btn.text = "  Iniciar"
	start_btn.custom_minimum_size = Vector2(90, 32)
	var start_sb := StyleBoxFlat.new()
	start_sb.bg_color = C_START_GREEN
	start_sb.corner_radius_top_right = 10
	start_sb.corner_radius_bottom_right = 10
	start_btn.add_theme_stylebox_override("normal", start_sb)
	start_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	start_btn.disabled = true # decorativo, só pro clima
	hbox.add_child(start_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	taskbar_clock = Label.new()
	taskbar_clock.add_theme_color_override("font_color", Color(1, 1, 1))
	var t: Dictionary = Time.get_time_dict_from_system()
	taskbar_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]
	hbox.add_child(taskbar_clock)

	var margin := Control.new()
	margin.custom_minimum_size = Vector2(12, 0)
	hbox.add_child(margin)


func _show_toast(msg: String) -> void:
	var toast := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	toast.add_theme_stylebox_override("panel", sb)
	toast.custom_minimum_size = Vector2(260, 40)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-130, 20)
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.add_child(lbl)
	window_layer.add_child(toast)
	var t := get_tree().create_timer(1.8)
	t.timeout.connect(func(): toast.queue_free())


# ---------------------------------------------------------------------------
# JANELA GENÉRICA (estilo XP) - usada pelo e-mail e pelo editor
# ---------------------------------------------------------------------------
func _make_window(title: String, size: Vector2) -> Dictionary:
	var win := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_WINDOW_BG
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.05, 0.2, 0.55)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	win.add_theme_stylebox_override("panel", sb)
	win.custom_minimum_size = size
	win.size = size
	win.mouse_filter = Control.MOUSE_FILTER_STOP
	win.position = (screen.size - size) / 2.0
	if win.position.y < 4:
		win.position.y = 4

	var titlebar := Panel.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = C_TITLEBAR_A
	tsb.corner_radius_top_left = 6
	tsb.corner_radius_top_right = 6
	titlebar.add_theme_stylebox_override("panel", tsb)
	titlebar.custom_minimum_size = Vector2(size.x, 28)
	titlebar.size = Vector2(size.x, 28)
	titlebar.mouse_filter = Control.MOUSE_FILTER_STOP
	win.add_child(titlebar)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", Color(1, 1, 1))
	title_label.position = Vector2(8, 4)
	titlebar.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(24, 22)
	close_btn.position = Vector2(size.x - 30, 3)
	titlebar.add_child(close_btn)

	_make_draggable(win, titlebar)

	window_layer.add_child(win)

	var content := Control.new()
	content.position = Vector2(0, 28)
	content.size = Vector2(size.x, size.y - 28)
	win.add_child(content)

	return {"window": win, "titlebar": titlebar, "content": content, "close_button": close_btn}


func _make_draggable(win: Control, handle: Control) -> void:
	var dragging := {"active": false, "offset": Vector2.ZERO}
	handle.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging["active"] = true
				dragging["offset"] = win.position - handle.get_global_mouse_position()
			else:
				dragging["active"] = false
		elif event is InputEventMouseMotion and dragging["active"]:
			win.position = handle.get_global_mouse_position() + dragging["offset"]
	)


# ---------------------------------------------------------------------------
# E-MAIL DO CHEFE
# ---------------------------------------------------------------------------
func _open_email() -> void:
	state = State.EMAIL
	var cfg: Dictionary = GameManager.get_current_config()
	var built := _make_window("Caixa de Entrada - Outlook Express", Vector2(560, 340))
	var content: Control = built["content"]

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	content.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "De: Seu Chefe <chefe@codecorp.com>\nAssunto: %s" % cfg["title"]
	header.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var body := Label.new()
	body.text = cfg["boss_intro"]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_color_override("font_color", C_TEXT_DARK)
	body.custom_minimum_size = Vector2(520, 140)
	vbox.add_child(body)

	var footer := Label.new()
	footer.text = "Abra o Editor de Código na área de trabalho quando estiver pronto."
	footer.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
	footer.add_theme_font_size_override("font_size", 12)
	vbox.add_child(footer)

	var ok_btn := Button.new()
	ok_btn.text = "Entendido"
	ok_btn.custom_minimum_size = Vector2(120, 32)
	vbox.add_child(ok_btn)

	var win: Control = built["window"]
	var close := func():
		GameManager.email_read_today = true
		win.queue_free()
		state = State.DESKTOP
	ok_btn.pressed.connect(close)
	built["close_button"].pressed.connect(close)


func _try_open_editor() -> void:
	if not GameManager.email_read_today:
		_show_toast("Leia o e-mail do chefe primeiro!")
		return
	_open_editor()


# ---------------------------------------------------------------------------
# EDITOR DE CÓDIGO / CORRIDA DE DIGITAÇÃO (o puzzle principal)
# ---------------------------------------------------------------------------
func _open_editor() -> void:
	state = State.RACE
	var cfg: Dictionary = GameManager.get_current_config()
	race_code = cfg["code"]
	race_ai_wpm = float(cfg["ai_wpm"])
	race_ai_stutter_chance = float(cfg["ai_stutter_chance"])
	race_ai_progress_chars = 0.0
	race_ai_stutter_timer = 0.0
	race_finished = false

	var built := _make_window("CodeMaster IDE - main.gd", Vector2(760, 480))
	var content: Control = built["content"]

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	content.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var instructions := Label.new()
	instructions.text = "%s — Digite o código abaixo mais rápido que a CodeBot-3000!" % cfg["title"]
	instructions.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(instructions)

	# Painel com o código de referência
	race_target_label = RichTextLabel.new()
	race_target_label.bbcode_enabled = true
	race_target_label.custom_minimum_size = Vector2(720, 130)
	race_target_label.scroll_active = false
	race_target_label.add_theme_color_override("default_color", C_TEXT_DARK)
	var target_bg := StyleBoxFlat.new()
	target_bg.bg_color = Color(1, 1, 1)
	target_bg.border_width_left = 1
	target_bg.border_width_right = 1
	target_bg.border_width_top = 1
	target_bg.border_width_bottom = 1
	target_bg.border_color = Color(0.6, 0.6, 0.6)
	race_target_label.add_theme_stylebox_override("normal", target_bg)
	vbox.add_child(race_target_label)

	var input_label := Label.new()
	input_label.text = "Digite aqui:"
	input_label.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(input_label)

	race_input = TextEdit.new()
	race_input.custom_minimum_size = Vector2(720, 110)
	race_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	race_input.text = ""
	vbox.add_child(race_input)
	race_input.text_changed.connect(_on_race_text_changed)

	# Barras de progresso
	var player_row := HBoxContainer.new()
	var player_tag := Label.new()
	player_tag.text = "Você:      "
	player_tag.add_theme_color_override("font_color", C_TEXT_DARK)
	player_tag.custom_minimum_size = Vector2(80, 0)
	player_row.add_child(player_tag)
	race_player_bar = ProgressBar.new()
	race_player_bar.min_value = 0
	race_player_bar.max_value = race_code.length()
	race_player_bar.value = 0
	race_player_bar.custom_minimum_size = Vector2(600, 22)
	var pfill := StyleBoxFlat.new()
	pfill.bg_color = C_PLAYER_BAR
	race_player_bar.add_theme_stylebox_override("fill", pfill)
	player_row.add_child(race_player_bar)
	vbox.add_child(player_row)

	var ai_row := HBoxContainer.new()
	var ai_tag := Label.new()
	ai_tag.text = "CodeBot-3000:"
	ai_tag.add_theme_color_override("font_color", C_TEXT_DARK)
	ai_tag.custom_minimum_size = Vector2(80, 0)
	ai_row.add_child(ai_tag)
	race_ai_bar = ProgressBar.new()
	race_ai_bar.min_value = 0
	race_ai_bar.max_value = race_code.length()
	race_ai_bar.value = 0
	race_ai_bar.custom_minimum_size = Vector2(600, 22)
	var afill := StyleBoxFlat.new()
	afill.bg_color = C_AI_BAR
	race_ai_bar.add_theme_stylebox_override("fill", afill)
	ai_row.add_child(race_ai_bar)
	vbox.add_child(ai_row)

	race_status_label = Label.new()
	race_status_label.text = "Corrida em andamento..."
	race_status_label.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(race_status_label)

	var win: Control = built["window"]
	built["close_button"].pressed.connect(func():
		race_active = false
		win.queue_free()
		state = State.DESKTOP
	)

	_refresh_target_display("")
	race_active = true
	race_input.grab_focus()


func _refresh_target_display(current_input: String) -> void:
	var correct_len := _longest_correct_prefix(current_input, race_code)
	var bb := "[code]"
	for i in range(race_code.length()):
		var ch := race_code[i]
		var shown := ch
		if i < correct_len:
			bb += "[bgcolor=#c8f7c5]%s[/bgcolor]" % shown
		elif i == correct_len and i < current_input.length():
			bb += "[bgcolor=#f7c5c5]%s[/bgcolor]" % shown
		else:
			bb += shown
	bb += "[/code]"
	race_target_label.text = bb


func _longest_correct_prefix(input_text: String, target: String) -> int:
	var n: int = min(input_text.length(), target.length())
	var i := 0
	while i < n and input_text[i] == target[i]:
		i += 1
	return i


func _on_race_text_changed() -> void:
	if not race_active or race_finished:
		return
	var typed := race_input.text
	var correct_len := _longest_correct_prefix(typed, race_code)
	race_player_bar.value = correct_len
	_refresh_target_display(typed)

	if correct_len >= race_code.length():
		_finish_race(true)


func _update_ai_progress(delta: float) -> void:
	if race_ai_stutter_timer > 0.0:
		race_ai_stutter_timer -= delta
		return

	if randf() < race_ai_stutter_chance * delta * 2.0:
		race_ai_stutter_timer = randf_range(0.2, 0.9)
		return

	var chars_per_second: float = (race_ai_wpm * 5.0) / 60.0
	race_ai_progress_chars += chars_per_second * delta
	race_ai_bar.value = min(race_ai_progress_chars, race_code.length())

	if race_ai_progress_chars >= race_code.length():
		_finish_race(false)


func _finish_race(player_won: bool) -> void:
	if race_finished:
		return
	race_finished = true
	race_active = false
	race_input.editable = false

	if player_won:
		race_status_label.text = "Você venceu a CodeBot-3000! 🎉"
		GameManager.register_win()
	else:
		race_status_label.text = "A CodeBot-3000 terminou primeiro..."
		GameManager.register_loss()

	var t := get_tree().create_timer(0.9)
	t.timeout.connect(func(): _show_result(player_won))


func _show_result(player_won: bool) -> void:
	state = State.RESULT
	for c in window_layer.get_children():
		c.queue_free()

	# Se venceu, current_day já avançou dentro de register_win(); pegamos a
	# config do dia que acabou de terminar para exibir a fala certa do chefe.
	var finished_day_index := GameManager.current_day - 1 if player_won else GameManager.current_day
	finished_day_index = clamp(finished_day_index, 1, GameManager.total_days())
	var finished_cfg: Dictionary = GameManager.day_configs[finished_day_index - 1]

	var title := "Resultado"
	var msg := ""
	if player_won:
		msg = finished_cfg["boss_win"]
	else:
		msg = finished_cfg["boss_lose"] + "\n\nAvisos: %d/%d" % [GameManager.total_losses, GameManager.MAX_LOSSES]

	var built := _make_window(title, Vector2(480, 260))
	var content: Control = built["content"]
	built["close_button"].visible = false

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 14)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	content.add_child(margin)
	margin.add_child(vbox)

	var heading := Label.new()
	heading.text = "Você venceu!" if player_won else "Você perdeu essa rodada."
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", C_PLAYER_BAR if player_won else C_ERROR)
	vbox.add_child(heading)

	var body := Label.new()
	body.text = msg
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(440, 100)
	body.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(body)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 34)
	vbox.add_child(btn)

	var win: Control = built["window"]

	if GameManager.is_fired():
		btn.text = "..."
		btn.visible = false
		var t := get_tree().create_timer(1.2)
		t.timeout.connect(func():
			win.queue_free()
			_show_fired_screen()
		)
	elif GameManager.is_campaign_won():
		btn.text = "..."
		btn.visible = false
		var t := get_tree().create_timer(1.2)
		t.timeout.connect(func():
			win.queue_free()
			_show_victory_screen()
		)
	elif player_won:
		btn.text = "Continuar para o próximo dia"
		btn.pressed.connect(func():
			win.queue_free()
			_build_desktop()
		)
	else:
		btn.text = "Tentar novamente"
		btn.pressed.connect(func():
			win.queue_free()
			_build_desktop()
		)


# ---------------------------------------------------------------------------
# TELAS FINAIS
# ---------------------------------------------------------------------------
func _show_fired_screen() -> void:
	state = State.FIRED
	for c in screen.get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(screen.size.x / 2.0 - 260, screen.size.y / 2.0 - 100)
	vbox.custom_minimum_size = Vector2(520, 200)
	vbox.add_theme_constant_override("separation", 16)
	screen.add_child(vbox)

	var title := Label.new()
	title.text = "VOCÊ FOI DEMITIDO"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", C_ERROR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "A CodeCorp decidiu seguir 100% com a CodeBot-3000.\nSeu crachá foi desativado."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	sub.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(sub)

	var btn := Button.new()
	btn.text = "Tentar de novo"
	btn.custom_minimum_size = Vector2(160, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn)
	btn.pressed.connect(func():
		GameManager.reset_game()
		_build_desktop()
	)


func _show_victory_screen() -> void:
	state = State.VICTORY
	for c in screen.get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.15, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(screen.size.x / 2.0 - 280, screen.size.y / 2.0 - 110)
	vbox.custom_minimum_size = Vector2(560, 220)
	vbox.add_theme_constant_override("separation", 16)
	screen.add_child(vbox)

	var title := Label.new()
	title.text = "VOCÊ VENCEU A CODEBOT-3000!"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", C_PLAYER_BAR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Cinco dias, cinco vitórias. O emprego é seu — por enquanto."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	sub.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(sub)

	var btn := Button.new()
	btn.text = "Jogar novamente"
	btn.custom_minimum_size = Vector2(180, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn)
	btn.pressed.connect(func():
		GameManager.reset_game()
		_build_desktop()
	)
