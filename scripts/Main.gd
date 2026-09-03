extends Control
## Main
## Ponto de entrada do jogo. Constrói toda a interface por código (sem
## depender de nós pré-montados no editor), simulando a tela de um
## monitor CRT onde roda um desktop no estilo Windows XP.
##
## Fluxo de estados:
##   MENU -> (transição) -> DESKTOP -> EMAIL (caixa de entrada) -> RACE (editor) ->
##   RESULT (comparação de pontuação) -> volta pro DESKTOP, ou FIRED / VICTORY no fim.
##
## Estrutura da campanha (ver GameManager.gd):
##   Dia 0 é treinamento, sem oponente de IA. Ao vencer o Dia 0, o jogo
##   mostra uma transição extra ("2 anos depois...") antes de cair no Dia 1,
##   quando a IA da empresa entra em ação de verdade e evolui de versão a
##   cada 2 dias.
##
## Sistema de pontuação (Dias 1-14):
##   Em vez de "quem termina primeiro", cada corrida agora sempre termina
##   quando o JOGADOR conclui o código (a barra da IA é só decoração visual
##   em tempo real, guiada pelas mesmas ai_wpm/ai_stutter_chance de sempre).
##   Ao concluir, calculamos uma pontuação pra cada lado a partir de dois
##   atributos, com peso igual (média simples):
##     - precisão (%): caracteres digitados corretamente / total digitado
##       pra frente (backspaces não contam contra o jogador - ele já "pagou"
##       o erro na hora de digitar errado).
##     - tempo: comparado com um "tempo de referência" calculado a partir do
##       tamanho do código (ver _target_time_seconds). Quanto mais rápido
##       que a referência, mais perto de 100 pontos; nunca passa de 100.
##   A IA usa "ai_accuracy" (fixo por dia, configurado em GameManager) como
##   precisão, e um tempo teórico calculado a partir de ai_wpm/stutter (ver
##   _ai_theoretical_time) - não depende da animação real da barra, então a
##   pontuação fica previsível mesmo com a aleatoriedade visual do stutter.
##   Quem pontuar mais, vence o dia. Uma única derrota já é demissão
##   (GameManager.MAX_LOSSES = 1) - a tela de demissão é propositalmente
##   simples por enquanto.

enum State { MENU, CONFIG_MENU, BOOT, DESKTOP, EMAIL, RACE, RESULT, FIRED, VICTORY }

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
const C_UNREAD := Color(0.75, 0.10, 0.10)
const C_SELECTED_ITEM := Color(0.43, 0.43, 0.42)
const C_SELECTED_ITEM_UNREAD_TEXT := Color(1.0, 0.55, 0.45)

# ---------------------------------------------------------------------------
# Som de notificação (aviso de nova mensagem)
# ---------------------------------------------------------------------------
# Coloque aqui o arquivo de som (.wav ou .ogg) que você quiser usar como
# "pop" de notificação. Se o arquivo não existir ainda, o jogo simplesmente
# não toca nada (sem erro) - é só trocar/adicionar o arquivo nesse caminho
# quando tiver o som definitivo.
const NOTIFICATION_SOUND_PATH := "res://assets/sfx/notification.wav"

# ---------------------------------------------------------------------------
# Som de clique (retro) - toca em QUALQUER clique esquerdo do jogo: botões
# de menu, ícones da área de trabalho, abrir/fechar janelas, etc. Basta
# colocar o arquivo definitivo nesse caminho; enquanto ele não existir, o
# jogo não toca nada (sem erro).
# ---------------------------------------------------------------------------
const CLICK_SOUND_PATH := "res://assets/sfx/click.wav"

# ---------------------------------------------------------------------------
# Música do menu principal - toca em loop enquanto o jogador está no MENU ou
# no CONFIG_MENU, e some com um fade curto assim que a campanha começa. Se o
# arquivo ainda não existir, o jogo simplesmente fica em silêncio.
# ---------------------------------------------------------------------------
const MENU_MUSIC_PATH := "res://assets/music/menu_theme.ogg"

# ---------------------------------------------------------------------------
# Imagens de fundo (wallpapers) - opcionais. Se o arquivo não existir ainda
# (os desenhos estão sendo feitos por outro membro da equipe), cai no fundo
# de cor sólida de sempre, sem erro nenhum. Quando o arquivo chegar, é só
# colocar nesse caminho que passa a aparecer automaticamente.
# ---------------------------------------------------------------------------
const MENU_BG_IMAGE_PATH := "res://assets/images/menu_background.png"
const DESKTOP_BG_IMAGE_PATH := "res://assets/images/desktop_wallpaper.png"

# ---------------------------------------------------------------------------
# Fonte de código (JetBrains Mono Nerd Font, com fallback)
# ---------------------------------------------------------------------------
# Se um arquivo .ttf/.otf da JetBrains Mono Nerd Font for colocado nesse
# caminho, ele é usado com prioridade (visual idêntico ao original). Caso
# contrário, caímos num SystemFont que procura a fonte já instalada no
# computador e, se não encontrar, usa a melhor alternativa monoespaçada
# disponível no sistema.
const CODE_FONT_TTF_PATH := "res://assets/fonts/JetBrainsMonoNerdFont-Regular.ttf"
const CODE_FONT_SYSTEM_NAMES := [
	"JetBrainsMono Nerd Font", "JetBrains Mono Nerd Font", "JetBrainsMono NFM",
	"JetBrains Mono", "Cascadia Code", "Fira Code", "Consolas",
	"Source Code Pro", "Courier New", "monospace"
]
var _code_font: Font

# ---------------------------------------------------------------------------
# Referência de tempo pra pontuação da corrida (ver cabeçalho do arquivo).
# Representa uma digitação "competente" de ~45 palavras por minuto; bater
# esse tempo (ou ser mais rápido) já garante os 100 pontos de tempo.
# ---------------------------------------------------------------------------
const TARGET_WPM_BASELINE := 45.0

var state: State = State.MENU

# Referências construídas em tempo de execução.
var screen: Control
var desktop_layer: Control
var window_layer: Control
var transition_layer: Control
var taskbar_clock: Label
var email_icon_flash: bool = false
var email_badge: Control
var _notification_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer
var _menu_music_player: AudioStreamPlayer

# --- Variáveis da corrida (race) ---
var race_code: String = ""
var race_input: CodeEdit
var race_target_label: RichTextLabel
var race_player_bar: ProgressBar
var race_ai_bar: ProgressBar
var race_status_label: Label
var race_timer_label: Label
var race_accuracy_label: Label
var race_ai_progress_chars: float = 0.0
var race_ai_wpm: float = 30.0
var race_ai_stutter_chance: float = 0.1
var race_ai_stutter_timer: float = 0.0
var race_finished: bool = false
var race_active: bool = false
# Se falso (Dia 0 - treinamento), a corrida roda sem oponente de IA: sem
# barra da IA, sem pontuação comparada, o jogador só pratica no próprio ritmo.
var race_ai_active: bool = true

# --- Cronômetro e precisão (ver cabeçalho do arquivo) ---
var race_start_msec: int = 0
var race_prev_input: String = ""
var race_total_typed: int = 0
var race_error_typed: int = 0

# --- Resultado da última corrida, usado pela tela de resultado ---
var race_last_player_score: float = 0.0
var race_last_ai_score: float = 0.0
var race_last_player_accuracy: float = 100.0
var race_last_player_time: float = 0.0
var race_last_ai_accuracy: float = 0.0
var race_last_ai_time: float = 0.0
var race_last_had_ai: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(1280, 720)
	_notification_player = AudioStreamPlayer.new()
	add_child(_notification_player)
	_click_player = AudioStreamPlayer.new()
	add_child(_click_player)
	_menu_music_player = AudioStreamPlayer.new()
	add_child(_menu_music_player)
	_menu_music_player.finished.connect(_on_menu_music_finished)
	_build_monitor_frame()
	_show_main_menu()


func _process(delta: float) -> void:
	if race_active and not race_finished:
		if race_ai_active:
			_update_ai_progress(delta)
		_update_race_hud()


# ---------------------------------------------------------------------------
# SOM DE CLIQUE GLOBAL
# ---------------------------------------------------------------------------
# Usamos _input (não _unhandled_input) de propósito: assim o clique soa
# sempre, mesmo quando o botão/ícone/janela abaixo do cursor "consome" o
# evento (o que aconteceria com _unhandled_input). Cobre literalmente
# qualquer clique esquerdo do jogo - menu, ícones da área de trabalho, abrir
# app, fechar janela, etc. - sem precisar conectar som em cada botão.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_click_sound()


func _play_click_sound() -> void:
	if not ResourceLoader.exists(CLICK_SOUND_PATH):
		# Sem arquivo definitivo ainda: não toca nada, sem erro. Basta colocar
		# um .wav/.ogg em CLICK_SOUND_PATH quando o som retro estiver pronto.
		return
	if _click_player.stream == null:
		_click_player.stream = load(CLICK_SOUND_PATH)
	# Pequena variação aleatória de pitch a cada clique: dá uma sensação mais
	# "mecânica/retro" (tecla física) em vez do exact mesmo som toda vez.
	_click_player.pitch_scale = randf_range(0.92, 1.08)
	_click_player.play()


# ---------------------------------------------------------------------------
# MÚSICA DO MENU
# ---------------------------------------------------------------------------
func _play_menu_music() -> void:
	if not ResourceLoader.exists(MENU_MUSIC_PATH):
		return
	if _menu_music_player.stream == null:
		_menu_music_player.stream = load(MENU_MUSIC_PATH)
	if not _menu_music_player.playing:
		_menu_music_player.volume_db = 0.0
		_menu_music_player.play()


func _stop_menu_music() -> void:
	if not _menu_music_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_menu_music_player, "volume_db", -40.0, 0.5)
	tween.tween_callback(_menu_music_player.stop)
	tween.tween_callback(func(): _menu_music_player.volume_db = 0.0)


func _on_menu_music_finished() -> void:
	# Faz a música voltar ao início e continuar (loop manual), mas só
	# enquanto ainda estivermos numa tela de menu - evita que ela volte a
	# tocar sozinha se _stop_menu_music() já tiver sido chamada.
	if state == State.MENU or state == State.CONFIG_MENU:
		_menu_music_player.play()


# ---------------------------------------------------------------------------
# FUNDO (cor sólida ou imagem, se já existir)
# ---------------------------------------------------------------------------
func _make_background(color_fallback: Color, image_path: String) -> Control:
	if ResourceLoader.exists(image_path):
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(image_path)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tex_rect
	var rect := ColorRect.new()
	rect.color = color_fallback
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# ---------------------------------------------------------------------------
# FONTE DE CÓDIGO
# ---------------------------------------------------------------------------
func _get_code_font() -> Font:
	if _code_font:
		return _code_font

	if ResourceLoader.exists(CODE_FONT_TTF_PATH):
		# Arquivo real da JetBrains Mono Nerd Font presente em
		# assets/fonts -> usa ele.
		_code_font = load(CODE_FONT_TTF_PATH)
	else:
		# Sem arquivo bundlado: usa a JetBrains Mono Nerd Font do sistema
		# operacional, se estiver instalada, com fallback pra outras fontes
		# monoespaçadas.
		var sys_font := SystemFont.new()
		sys_font.font_names = PackedStringArray(CODE_FONT_SYSTEM_NAMES)
		_code_font = sys_font

	return _code_font


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

	# Camada de transição: fica dentro do mesmo "bezel", por cima da "screen"
	# (mesmo recorte/tamanho), mas é uma IRMÃ da screen, não uma filha dela.
	# Isso é de propósito: várias funções (ex.: _build_desktop, _show_main_menu)
	# limpam TODOS os filhos de "screen" quando trocam de tela. Se o overlay
	# de transição fosse filho de "screen", ele seria apagado no meio da
	# própria animação. Ficando fora de "screen", ele sobrevive a qualquer
	# troca de estado.
	transition_layer = Control.new()
	transition_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	transition_layer.offset_left = 36
	transition_layer.offset_top = 36
	transition_layer.offset_right = -36
	transition_layer.offset_bottom = -70
	transition_layer.clip_contents = true
	transition_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bezel.add_child(transition_layer)


# ---------------------------------------------------------------------------
# MENU PRINCIPAL
# ---------------------------------------------------------------------------
func _show_main_menu() -> void:
	state = State.MENU
	for c in screen.get_children():
		c.queue_free()

	var bg := _make_background(C_DESKTOP.darkened(0.45), MENU_BG_IMAGE_PATH)
	screen.add_child(bg)

	_play_menu_music()

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.position = Vector2(screen.size.x / 2.0 - 160, screen.size.y / 2.0 - 140)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	screen.add_child(vbox)

	var title := Label.new()
	title.text = "CODE WARRIOR\nHumano vs IA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var start_btn := _make_menu_button("START")
	start_btn.pressed.connect(_on_menu_start_pressed)
	vbox.add_child(start_btn)

	var config_btn := _make_menu_button("CONFIG")
	config_btn.pressed.connect(_show_config_menu)
	vbox.add_child(config_btn)

	var exit_btn := _make_menu_button("EXIT")
	exit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(exit_btn)


func _make_menu_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(240, 46)
	btn.add_theme_font_size_override("font_size", 18)
	return btn


# ---------------------------------------------------------------------------
# MENU DE CONFIGURAÇÕES
# ---------------------------------------------------------------------------
# Por enquanto só tem o botão de voltar. No futuro, novas opções (volume,
# dificuldade, fonte, etc.) entram aqui dentro do vbox, sem precisar mexer
# no menu principal.
func _show_config_menu() -> void:
	state = State.CONFIG_MENU
	for c in screen.get_children():
		c.queue_free()

	var bg := _make_background(C_DESKTOP.darkened(0.45), MENU_BG_IMAGE_PATH)
	screen.add_child(bg)

	# A música do menu continua tocando aqui (só reinicia se, por algum
	# motivo, tiver parado) - CONFIG_MENU ainda conta como "tela de menu".
	_play_menu_music()

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.position = Vector2(screen.size.x / 2.0 - 160, screen.size.y / 2.0 - 100)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	screen.add_child(vbox)

	var title := Label.new()
	title.text = "CONFIGURAÇÕES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(title)

	var placeholder := Label.new()
	placeholder.text = "(em breve)"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	placeholder.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(placeholder)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var back_btn := _make_menu_button("RETURN")
	back_btn.pressed.connect(_show_main_menu)
	vbox.add_child(back_btn)


func _on_menu_start_pressed() -> void:
	_stop_menu_music()
	var cfg: Dictionary = GameManager.get_current_config()
	_play_day_transition_for_cfg(cfg, func():
		_build_desktop()
	)


# ---------------------------------------------------------------------------
# TRANSIÇÃO DE DIA (tela preta com o(s) texto(s) do dia -> some revelando o
# monitor)
# ---------------------------------------------------------------------------
# 1) um overlay preto cobre a tela (fade-in do preto)
# 2) cada texto da sequência aparece, segura um instante e (exceto o último)
#    some antes do próximo aparecer - isso é o que permite encadear algo como
#    ["2 anos depois...", "Dia 1 - De volta ao trabalho"] numa única
#    transição contínua, sem precisar clarear o monitor no meio.
# 3) por trás do overlay (ainda opaco), troca o conteúdo da tela via
#    "on_fully_covered" (ex.: construir o desktop)
# 4) o overlay (preto + texto) desaparece suavemente, revelando o que foi
#    construído no passo 3
func _play_multi_text_transition(texts: Array, on_fully_covered: Callable) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_layer.add_child(overlay)

	var day_label := Label.new()
	day_label.text = ""
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	day_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	day_label.add_theme_font_size_override("font_size", 34)
	day_label.add_theme_color_override("font_color", Color(1, 1, 1))
	day_label.modulate = Color(1, 1, 1, 0)
	overlay.add_child(day_label)

	var tween := create_tween()
	# fade pro preto
	tween.tween_property(overlay, "color:a", 1.0, 0.35)

	for i in range(texts.size()):
		var txt: String = texts[i]
		tween.tween_callback(func(): day_label.text = txt)
		# texto atual surge
		tween.tween_property(day_label, "modulate:a", 1.0, 0.45)
		# segura a tela preta com o texto por um instante
		tween.tween_interval(0.9)
		if i < texts.size() - 1:
			# some pra dar lugar ao próximo texto da sequência
			tween.tween_property(day_label, "modulate:a", 0.0, 0.3)

	# troca o conteúdo da "screen" por trás do overlay (que está numa camada
	# separada, então não é afetado pela limpeza de filhos que essas funções
	# fazem em "screen")
	tween.tween_callback(on_fully_covered)
	# o texto some rápido, e o preto todo se dissolve revelando a tela nova
	tween.tween_property(day_label, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(overlay, "color:a", 0.0, 0.7)
	tween.tween_callback(overlay.queue_free)


# Monta a sequência de textos de um dia (pre_transition + título do próprio
# dia) e dispara a transição. Use esta função em vez de chamar
# _play_multi_text_transition diretamente sempre que a transição for a de
# "entrar num dia" da campanha.
func _play_day_transition_for_cfg(cfg: Dictionary, on_fully_covered: Callable) -> void:
	var texts: Array = []
	for t in cfg.get("pre_transition", []):
		texts.append(t)
	texts.append(cfg["title"])
	_play_multi_text_transition(texts, on_fully_covered)


# Sem uso direto no fluxo atual (o START agora vai direto pra transição de
# dia + desktop). Deixei a função aqui caso você queira reaproveitar esse
# efeito de "boot" em algum outro ponto do jogo.
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

	var bg := _make_background(C_DESKTOP, DESKTOP_BG_IMAGE_PATH)
	screen.add_child(bg)

	desktop_layer = Control.new()
	desktop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(desktop_layer)

	# Cabeçalho com status da campanha
	var hud := Label.new()
	var cfg: Dictionary = GameManager.get_current_config()
	if cfg.get("ai_active", true):
		hud.text = "%s   |   Adversária: %s" % [cfg["title"], GameManager.current_ai_name()]
	else:
		hud.text = cfg["title"]
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_font_size_override("font_size", 16)
	hud.position = Vector2(16, 10)
	desktop_layer.add_child(hud)

	# Ícones do desktop
	email_badge = _add_desktop_icon(desktop_layer, Vector2(30, 60), "Outlook\nExpress", Color(0.95, 0.85, 0.2), true, _open_email)
	if email_badge:
		# A bolinha nasce escondida - só aparece com a animação/som depois de
		# 1s, controlada por _schedule_email_notification() logo abaixo.
		email_badge.visible = false
	_add_desktop_icon(desktop_layer, Vector2(30, 170), "Editor de\nCódigo", Color(0.25, 0.55, 0.95), false, _try_open_editor)
	_add_desktop_icon(desktop_layer, Vector2(30, 280), "Meu\nComputador", Color(0.8, 0.8, 0.85), false, func(): _show_toast("Nada de interessante por aqui..."))
	_add_desktop_icon(desktop_layer, Vector2(30, 390), "Lixeira", Color(0.6, 0.6, 0.65), false, func(): _show_toast("A lixeira está vazia."))

	# Camada de janelas (fica por cima de tudo, mas ainda dentro da tela)
	window_layer = Control.new()
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(window_layer)

	_build_taskbar()

	if GameManager.has_unread_email():
		_schedule_email_notification()


func _add_desktop_icon(parent: Control, pos: Vector2, caption: String, tint: Color, notify: bool, on_activate: Callable) -> Control:
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

	var badge_bg: Panel = null
	if notify:
		var badge := Label.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.text = "!"
		badge.add_theme_color_override("font_color", Color(1, 1, 1))
		badge.add_theme_font_size_override("font_size", 14)
		badge_bg = Panel.new()
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
		badge_bg.pivot_offset = Vector2(8, 8)
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
	return badge_bg


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
# NOTIFICAÇÃO DE NOVA MENSAGEM (bolinha vermelha + som + aviso do "Bricks")
# ---------------------------------------------------------------------------
# 1s depois do desktop aparecer, se houver e-mail(s) não lido(s): toca um
# som, anima a bolinha vermelha do ícone do Outlook Express surgindo, e
# mostra um aviso no canto inferior direito (estilo balão de notificação),
# tipo "Bricks - 1 nova mensagem" / "Bricks - 2 novas mensagens". Essa
# bolinha SÓ some quando todas as mensagens do dia forem lidas (ver
# GameManager.has_unread_email / mark_email_read).
func _schedule_email_notification() -> void:
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(func():
		if not is_instance_valid(email_badge):
			return
		_play_notification_sound()
		_animate_email_badge_in()
		_show_system_notification(GameManager.unread_email_count())
	)


func _play_notification_sound() -> void:
	if ResourceLoader.exists(NOTIFICATION_SOUND_PATH):
		_notification_player.stream = load(NOTIFICATION_SOUND_PATH)
		_notification_player.play()
	# Se o arquivo ainda não existir, simplesmente não toca nada - sem erro.
	# Basta colocar um .wav/.ogg em NOTIFICATION_SOUND_PATH quando tiver o
	# som definitivo.


func _animate_email_badge_in() -> void:
	email_badge.visible = true
	email_badge.scale = Vector2(0.2, 0.2)
	email_badge.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(email_badge, "scale", Vector2(1, 1), 0.35)
	tween.parallel().tween_property(email_badge, "modulate:a", 1.0, 0.2)


func _show_system_notification(unread_count: int) -> void:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.97, 0.95)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = C_TITLEBAR_A
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_size = 6
	sb.shadow_color = Color(0, 0, 0, 0.35)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(260, 64)
	panel.size = Vector2(260, 64)
	# Canto inferior direito, encostado logo acima da barra de tarefas.
	panel.position = Vector2(screen.size.x - 260 - 16, screen.size.y - 64 - 36 - 12)
	panel.modulate = Color(1, 1, 1, 0)
	window_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Bricks"
	title.add_theme_color_override("font_color", C_TITLEBAR_A)
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var word_nova := "nova" if unread_count == 1 else "novas"
	var word_msg := "mensagem" if unread_count == 1 else "mensagens"
	var msg := Label.new()
	msg.text = "%d %s %s" % [unread_count, word_nova, word_msg]
	msg.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(msg)

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


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
# CAIXA DE ENTRADA (e-mail do chefe, RH, NeuralCode etc.)
# ---------------------------------------------------------------------------
# Layout tipo "cliente de e-mail de verdade": uma lista de mensagens à
# esquerda (com uma bolinha vermelha nas ainda não lidas) e o conteúdo da
# mensagem selecionada à direita, dentro de um ScrollContainer - mensagens
# longas nunca ficam cortadas, aparece uma barra de rolagem em vez disso.
# O jogador pode clicar em qualquer mensagem da lista a qualquer momento
# (não precisa ler em ordem, nem fechar e reabrir a janela pra trocar de
# mensagem). Cada mensagem é marcada como lida assim que é exibida, e a
# bolinha do ícone na área de trabalho só some quando TODAS as mensagens do
# dia estiverem lidas.
func _open_email() -> void:
	state = State.EMAIL
	var emails: Array = GameManager.get_current_config()["emails"]
	var start_index := 0
	for i in range(emails.size()):
		if not GameManager.is_email_read(i):
			start_index = i
			break
	_render_email_window(start_index)


func _render_email_window(selected_index: int) -> void:
	var emails: Array = GameManager.get_current_config()["emails"]
	selected_index = clampi(selected_index, 0, emails.size() - 1)

	# Ler é simplesmente visualizar: marcar como lida assim que a mensagem é
	# exibida (sem precisar de um botão extra tipo "Entendido" por mensagem).
	GameManager.mark_email_read(selected_index)
	if is_instance_valid(email_badge):
		email_badge.visible = GameManager.has_unread_email()

	var built := _make_window("Caixa de Entrada - Outlook Express", Vector2(680, 440))
	var content: Control = built["content"]
	var win: Control = built["window"]

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	content.add_child(hbox)

	# --- Sidebar: lista de mensagens ---
	var sidebar := Panel.new()
	sidebar.custom_minimum_size = Vector2(200, 0)
	var sidebar_sb := StyleBoxFlat.new()
	sidebar_sb.bg_color = Color(0.88, 0.88, 0.86)
	sidebar_sb.border_width_right = 1
	sidebar_sb.border_color = Color(0.6, 0.6, 0.6)
	sidebar.add_theme_stylebox_override("panel", sidebar_sb)
	hbox.add_child(sidebar)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	sidebar_margin.add_theme_constant_override("margin_left", 6)
	sidebar_margin.add_theme_constant_override("margin_top", 6)
	sidebar_margin.add_theme_constant_override("margin_right", 6)
	sidebar_margin.add_theme_constant_override("margin_bottom", 6)
	sidebar.add_child(sidebar_margin)

	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_margin.add_child(sidebar_scroll)

	var sidebar_list := VBoxContainer.new()
	sidebar_list.custom_minimum_size = Vector2(184, 0)
	sidebar_list.add_theme_constant_override("separation", 4)
	sidebar_scroll.add_child(sidebar_list)

	for i in range(emails.size()):
		var email: Dictionary = emails[i]
		var is_read := GameManager.is_email_read(i)
		var is_selected := i == selected_index

		var item_btn := Button.new()
		item_btn.custom_minimum_size = Vector2(0, 42)
		item_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_btn.clip_text = true
		item_btn.text = ("%s" if is_read else "●  %s") % email["subject"]
		item_btn.add_theme_font_size_override("font_size", 12)
		# O contorno de foco padrão do Godot é o que sobrava azul depois de
		# clicar num item (mesmo depois de trocar a seleção) - como a seleção
		# já é indicada pela cor de fundo/texto abaixo, não precisamos do
		# foco de teclado aqui.
		item_btn.focus_mode = Control.FOCUS_NONE

		# Paleta única e explícita pros 4 estados possíveis (lido/não lido x
		# selecionado/não selecionado). Nada fica por conta do tema padrão do
		# Godot - é isso que causava cores "vazando" (azul de foco, hover
		# cinza com fonte errada, etc.).
		var bg_color: Color
		var font_color: Color
		if is_selected:
			bg_color = C_SELECTED_ITEM
			font_color = C_SELECTED_ITEM_UNREAD_TEXT if not is_read else Color(1, 1, 1)
		else:
			bg_color = Color(0.95, 0.95, 0.93)
			font_color = C_UNREAD if not is_read else C_TEXT_DARK

		var sb := StyleBoxFlat.new()
		sb.bg_color = bg_color
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		# Mesmo estilo em todos os estados do botão - sem isso, o Godot usa o
		# estilo padrão dele (cinza) pra "hover"/"pressed"/"focus", que foi
		# exatamente o efeito feio que apareceu.
		item_btn.add_theme_stylebox_override("normal", sb)
		item_btn.add_theme_stylebox_override("hover", sb)
		item_btn.add_theme_stylebox_override("pressed", sb)
		item_btn.add_theme_stylebox_override("focus", sb)
		item_btn.add_theme_color_override("font_color", font_color)
		item_btn.add_theme_color_override("font_hover_color", font_color)
		item_btn.add_theme_color_override("font_pressed_color", font_color)
		item_btn.add_theme_color_override("font_focus_color", font_color)

		var idx_capture := i
		item_btn.pressed.connect(func():
			if idx_capture == selected_index:
				return
			win.queue_free()
			_render_email_window(idx_capture)
		)
		sidebar_list.add_child(item_btn)

	# --- Painel direito: conteúdo da mensagem selecionada ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)

	var right_margin := MarginContainer.new()
	right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_theme_constant_override("margin_left", 16)
	right_margin.add_theme_constant_override("margin_top", 12)
	right_margin.add_theme_constant_override("margin_right", 16)
	right_margin.add_theme_constant_override("margin_bottom", 12)
	right.add_child(right_margin)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 10)
	right_margin.add_child(right_vbox)

	var email: Dictionary = emails[selected_index]
	var header := Label.new()
	header.text = "De: %s\nAssunto: %s" % [email["from"], email["subject"]]
	header.add_theme_color_override("font_color", C_TEXT_DARK)
	right_vbox.add_child(header)

	var sep := HSeparator.new()
	right_vbox.add_child(sep)

	# ScrollContainer garante que mensagens longas NUNCA fiquem cortadas: se
	# o texto não couber na área visível, aparece uma barra de rolagem em
	# vez de sumir um pedaço do final (o bug que cortava a parte de baixo).
	var body_scroll := ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.custom_minimum_size = Vector2(0, 220)
	right_vbox.add_child(body_scroll)

	var body := Label.new()
	body.text = email["body"]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_color_override("font_color", C_TEXT_DARK)
	body.custom_minimum_size = Vector2(420, 0)
	body_scroll.add_child(body)

	# Navegação entre mensagens direto pela caixa de entrada (sem precisar
	# fechar e reabrir a janela pra ver a próxima).
	if emails.size() > 1:
		var nav_row := HBoxContainer.new()
		nav_row.add_theme_constant_override("separation", 8)
		var prev_btn := Button.new()
		prev_btn.text = "< Anterior"
		prev_btn.custom_minimum_size = Vector2(110, 30)
		prev_btn.disabled = selected_index <= 0
		prev_btn.pressed.connect(func():
			win.queue_free()
			_render_email_window(selected_index - 1)
		)
		nav_row.add_child(prev_btn)
		var next_btn := Button.new()
		next_btn.text = "Próxima >"
		next_btn.custom_minimum_size = Vector2(110, 30)
		next_btn.disabled = selected_index >= emails.size() - 1
		next_btn.pressed.connect(func():
			win.queue_free()
			_render_email_window(selected_index + 1)
		)
		nav_row.add_child(next_btn)
		right_vbox.add_child(nav_row)

	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.custom_minimum_size = Vector2(120, 32)
	close_btn.pressed.connect(func():
		win.queue_free()
		state = State.DESKTOP
	)
	right_vbox.add_child(close_btn)

	built["close_button"].pressed.connect(func():
		win.queue_free()
		state = State.DESKTOP
	)


func _try_open_editor() -> void:
	if GameManager.has_unread_email():
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
	race_ai_active = cfg.get("ai_active", true)
	race_ai_wpm = float(cfg["ai_wpm"])
	race_ai_stutter_chance = float(cfg["ai_stutter_chance"])
	race_ai_progress_chars = 0.0
	race_ai_stutter_timer = 0.0
	race_finished = false

	# reinicia cronômetro e contadores de precisão
	race_start_msec = Time.get_ticks_msec()
	race_prev_input = ""
	race_total_typed = 0
	race_error_typed = 0

	# A caixa de código-alvo precisa caber (ou pelo menos rolar direitinho)
	# até o código mais longo do jogo. Antes ela tinha altura fixa de 130px
	# com rolagem desligada - para códigos de mais de ~6 linhas (a partir do
	# Dia 3), a(s) última(s) linha(s) ficava(m) invisível(is) mas ainda
	# contava(m) pro progresso, travando a barra antes de 100%.
	var code_line_count: int = race_code.split("\n").size()
	var target_label_height: int = clampi(code_line_count * 20 + 24, 90, 210)
	var window_height: float = 520.0 + max(0, target_label_height - 130)

	var built := _make_window("CodeMaster IDE - main.gd", Vector2(760, window_height))
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
	if race_ai_active:
		instructions.text = "%s — Digite o código abaixo mais rápido e com mais precisão que a %s!" % [cfg["title"], GameManager.current_ai_name()]
	else:
		instructions.text = "%s — Pratique digitando o código abaixo. Sem pressa, hoje é só treino." % cfg["title"]
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD
	instructions.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(instructions)

	# Linha de status ao vivo: cronômetro + percentual de precisão. Atualizada
	# a cada frame por _update_race_hud(), enquanto a corrida estiver ativa.
	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 24)
	race_timer_label = Label.new()
	race_timer_label.text = "Tempo: 00:00"
	race_timer_label.add_theme_color_override("font_color", C_TEXT_DARK)
	race_timer_label.add_theme_font_size_override("font_size", 14)
	hud_row.add_child(race_timer_label)
	race_accuracy_label = Label.new()
	race_accuracy_label.text = "Precisão: 100.0%"
	race_accuracy_label.add_theme_color_override("font_color", C_TEXT_DARK)
	race_accuracy_label.add_theme_font_size_override("font_size", 14)
	hud_row.add_child(race_accuracy_label)
	vbox.add_child(hud_row)

	# Painel com o código de referência
	# Fonte de código, usada tanto no painel de referência quanto no campo
	# de digitação, pra dar aquele visual de editor "de verdade".
	var code_font := _get_code_font()

	race_target_label = RichTextLabel.new()
	race_target_label.bbcode_enabled = true
	race_target_label.custom_minimum_size = Vector2(720, target_label_height)
	# Rolagem ligada como rede de segurança: mesmo que o código de algum dia
	# futuro seja maior do que cabe na caixa, dá pra rolar até o fim - nunca
	# mais fica um trecho invisível "impossível de completar".
	race_target_label.scroll_active = true
	race_target_label.add_theme_color_override("default_color", C_TEXT_DARK)
	race_target_label.add_theme_font_override("normal_font", code_font)
	race_target_label.add_theme_font_override("mono_font", code_font)
	race_target_label.add_theme_font_size_override("normal_font_size", 15)
	race_target_label.add_theme_font_size_override("mono_font_size", 15)
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

	# Usamos CodeEdit em vez de TextEdit: as propriedades de indentação
	# (indent_use_spaces, indent_size, indent_automatic) só existem na classe
	# CodeEdit — é a mesma classe usada pelo editor de script do próprio
	# Godot, então é a escolha certa para uma área de "escrever código".
	race_input = CodeEdit.new()
	race_input.custom_minimum_size = Vector2(720, 110)
	race_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	race_input.text = ""
	race_input.add_theme_font_override("font", code_font)
	race_input.add_theme_font_size_override("font_size", 15)
	# --- Correção do TAB ---
	# O código de referência usa espaços para indentação (4 por nível). Por
	# padrão, o editor insere um caractere de tabulação real ao pressionar
	# TAB, o que nunca bate com o texto esperado e trava o progresso. Com
	# "indent_use_spaces" ligado e "indent_size" = 4, o TAB passa a inserir
	# exatamente 4 espaços — o mesmo resultado de apertar espaço 4 vezes — e
	# a corrida reconhece a indentação corretamente. "indent_automatic" fica
	# desligado para o editor não adicionar espaços extras sozinho (o que
	# bagunçaria a comparação com o código alvo).
	race_input.indent_use_spaces = true
	race_input.indent_size = 4
	race_input.indent_automatic = false
	# CodeEdit vem por padrão com recursos extras (gutter de números de
	# linha, autocomplete etc.). Desligamos tudo isso pra manter a mesma
	# cara simples que o TextEdit original tinha.
	race_input.gutters_draw_line_numbers = false
	race_input.gutters_draw_fold_gutter = false
	race_input.gutters_draw_breakpoints_gutter = false
	race_input.gutters_draw_bookmarks = false
	race_input.gutters_draw_executing_lines = false
	race_input.code_completion_enabled = false
	race_input.highlight_current_line = false
	race_input.draw_tabs = false
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

	# A barra da IA é só decoração visual (a decisão de quem vence o dia
	# agora vem da comparação de pontuação em _finish_race, não de quem
	# termina primeiro). No Dia 0 - treinamento ela nem existe: a IA ainda
	# não foi contratada, é só o jogador praticando sozinho.
	if race_ai_active:
		var ai_row := HBoxContainer.new()
		var ai_tag := Label.new()
		ai_tag.text = "%s:" % GameManager.current_ai_name()
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
	else:
		race_ai_bar = null

	race_status_label = Label.new()
	race_status_label.text = "Corrida em andamento..." if race_ai_active else "Treino livre — capriche com calma."
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

	# Auto-scroll: a caixa acompanha sozinha a linha em que o jogador está
	# digitando, então ele nunca precisa rolar manualmente enquanto corre
	# contra o tempo.
	var caret_pos: int = min(current_input.length(), race_code.length())
	var current_line: int = race_code.substr(0, caret_pos).count("\n")
	race_target_label.scroll_to_line(current_line)


func _longest_correct_prefix(input_text: String, target: String) -> int:
	var n: int = min(input_text.length(), target.length())
	var i := 0
	while i < n and input_text[i] == target[i]:
		i += 1
	return i


# ---------------------------------------------------------------------------
# PRECISÃO E TEMPO (ver explicação completa no cabeçalho do arquivo)
# ---------------------------------------------------------------------------
func _track_typing_accuracy(typed: String) -> void:
	if typed.length() > race_prev_input.length():
		# Caracteres novos digitados "pra frente": cada um conta pro total, e
		# é um erro se não bate com o código alvo naquela posição. Backspaces
		# (typed mais curto que antes) não entram nessa contagem — o jogador
		# já "pagou" o erro no momento em que digitou o caractere errado.
		for i in range(race_prev_input.length(), typed.length()):
			race_total_typed += 1
			if i >= race_code.length() or typed[i] != race_code[i]:
				race_error_typed += 1


func _player_accuracy_percent() -> float:
	if race_total_typed <= 0:
		return 100.0
	return 100.0 * float(race_total_typed - race_error_typed) / float(race_total_typed)


func _race_elapsed_seconds() -> float:
	if race_start_msec == 0:
		return 0.0
	return float(Time.get_ticks_msec() - race_start_msec) / 1000.0


func _format_time(seconds: float) -> String:
	var total := int(round(seconds))
	var m := total / 60
	var s := total % 60
	return "%02d:%02d" % [m, s]


func _update_race_hud() -> void:
	if not is_instance_valid(race_timer_label) or not is_instance_valid(race_accuracy_label):
		return
	race_timer_label.text = "Tempo: %s" % _format_time(_race_elapsed_seconds())
	race_accuracy_label.text = "Precisão: %.1f%%" % _player_accuracy_percent()


# Tempo "de referência" pra converter tempo em pontuação (0 a 100): baseado
# no tamanho do código e numa velocidade de digitação competente
# (TARGET_WPM_BASELINE). Bater esse tempo ou ser mais rápido já garante os
# 100 pontos de tempo pro lado em questão (jogador ou IA).
func _target_time_seconds(code: String) -> float:
	var chars_per_minute: float = TARGET_WPM_BASELINE * 5.0
	if chars_per_minute <= 0.0:
		return 1.0
	return (float(code.length()) / chars_per_minute) * 60.0


func _time_score(elapsed: float, target: float) -> float:
	if elapsed <= 0.0:
		return 100.0
	return clamp(100.0 * target / elapsed, 0.0, 100.0)


# Tempo "teórico" da IA pra fins de pontuação: calculado a partir de
# ai_wpm, com uma pequena margem proporcional à chance de "hesitação"
# (ai_stutter_chance) configurada pro dia. É determinístico de propósito -
# não depende da aleatoriedade real da animação da barra dela - assim a
# pontuação final fica consistente e previsível.
func _ai_theoretical_time(cfg: Dictionary) -> float:
	var wpm: float = float(cfg.get("ai_wpm", 0))
	if wpm <= 0.0:
		return 999999.0
	var chars_per_second: float = (wpm * 5.0) / 60.0
	var base_time: float = float(race_code.length()) / chars_per_second
	var stutter: float = float(cfg.get("ai_stutter_chance", 0.0))
	return base_time * (1.0 + stutter * 0.6)


func _on_race_text_changed() -> void:
	if not race_active or race_finished:
		return
	var typed := race_input.text
	_track_typing_accuracy(typed)
	var correct_len := _longest_correct_prefix(typed, race_code)
	race_player_bar.value = correct_len
	_refresh_target_display(typed)
	race_prev_input = typed

	if correct_len >= race_code.length():
		_finish_race()


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
	# A barra só é decoração visual a partir daqui - ela pode encher antes ou
	# depois do jogador terminar, sem efeito nenhum no resultado. Quem
	# decide o dia é a comparação de pontuação em _finish_race().


# Chamada quando o JOGADOR termina de digitar o código corretamente (esse é
# o único jeito da corrida terminar agora). Calcula a pontuação de cada lado
# e decide o resultado do dia por comparação (ver cabeçalho do arquivo).
func _finish_race() -> void:
	if race_finished:
		return
	race_finished = true
	race_active = false
	race_input.editable = false

	var cfg: Dictionary = GameManager.get_current_config()
	var target_time := _target_time_seconds(race_code)

	var player_accuracy := _player_accuracy_percent()
	var player_elapsed := _race_elapsed_seconds()
	var player_time_score := _time_score(player_elapsed, target_time)
	var player_score := (player_accuracy + player_time_score) / 2.0

	race_last_player_accuracy = player_accuracy
	race_last_player_time = player_elapsed
	race_last_player_score = player_score
	race_last_had_ai = race_ai_active

	var player_won: bool

	if not race_ai_active:
		# Dia de treinamento: sem IA, sem comparação - o jogador sempre passa.
		player_won = true
		race_status_label.text = "Exercício concluído! 🎉"
	else:
		var ai_accuracy: float = float(cfg.get("ai_accuracy", 0.85)) * 100.0
		var ai_elapsed := _ai_theoretical_time(cfg)
		var ai_time_score := _time_score(ai_elapsed, target_time)
		var ai_score := (ai_accuracy + ai_time_score) / 2.0

		race_last_ai_accuracy = ai_accuracy
		race_last_ai_time = ai_elapsed
		race_last_ai_score = ai_score

		player_won = player_score > ai_score
		if player_won:
			race_status_label.text = "Você venceu a %s! 🎉" % GameManager.current_ai_name()
		else:
			race_status_label.text = "A %s pontuou mais que você..." % GameManager.current_ai_name()

	if player_won:
		GameManager.register_win()
	else:
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
	var msg: String = finished_cfg["boss_win"] if player_won else finished_cfg["boss_lose"]

	var window_height := 260.0 if not race_last_had_ai else 320.0
	var built := _make_window(title, Vector2(500, window_height))
	var content: Control = built["content"]
	built["close_button"].visible = false

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
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
	body.custom_minimum_size = Vector2(460, 70)
	body.add_theme_color_override("font_color", C_TEXT_DARK)
	vbox.add_child(body)

	# Resumo da pontuação (só faz sentido em dias com IA de verdade).
	if race_last_had_ai:
		var sep := HSeparator.new()
		vbox.add_child(sep)

		var score_line := Label.new()
		score_line.text = "Sua pontuação: %.1f   |   Pontuação da %s: %.1f" % [race_last_player_score, GameManager.current_ai_name(), race_last_ai_score]
		score_line.add_theme_color_override("font_color", C_TEXT_DARK)
		score_line.add_theme_font_size_override("font_size", 15)
		vbox.add_child(score_line)

		var detail_line := Label.new()
		detail_line.text = "Você: %.1f%% de precisão em %s   |   %s: %.1f%% de precisão em %s" % [
			race_last_player_accuracy, _format_time(race_last_player_time),
			GameManager.current_ai_name(), race_last_ai_accuracy, _format_time(race_last_ai_time)
		]
		detail_line.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
		detail_line.add_theme_font_size_override("font_size", 12)
		detail_line.autowrap_mode = TextServer.AUTOWRAP_WORD
		detail_line.custom_minimum_size = Vector2(460, 0)
		vbox.add_child(detail_line)

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
			var cfg: Dictionary = GameManager.get_current_config()
			_play_day_transition_for_cfg(cfg, func():
				_build_desktop()
			)
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
# Tela de demissão: uma pequena cinemática em 3 etapas, todas em fade sobre
# fundo preto, antes do painel final com o botão de reiniciar.
#   1) a notícia seca da demissão
#   2) uma reflexão mais melancólica/filosófica sobre o motivo
#   3) o painel final, com resumo e o botão "Tentar de novo"
func _show_fired_screen() -> void:
	state = State.FIRED
	for c in screen.get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var stage1 := _make_story_slide(
		"Infelizmente, você não conseguiu conter o avanço da %s.\nVocê foi demitido." % GameManager.current_ai_name(),
		C_ERROR, 28
	)
	screen.add_child(stage1)

	var stage2 := _make_story_slide(
		"Não importa o quanto você tentasse...\nmais cedo ou mais tarde, isso iria acontecer.",
		C_ERROR, 22
	)
	screen.add_child(stage2)

	var tween := create_tween()
	tween.tween_property(stage1, "modulate:a", 1.0, 0.8)
	tween.tween_interval(2.4)
	tween.tween_property(stage1, "modulate:a", 0.0, 0.7)
	tween.tween_property(stage2, "modulate:a", 1.0, 0.8)
	tween.tween_interval(2.8)
	tween.tween_property(stage2, "modulate:a", 0.0, 0.7)
	tween.tween_callback(func():
		stage1.queue_free()
		stage2.queue_free()
		_show_fired_final_panel()
	)


# Slide de história em tela cheia: texto centralizado (horizontal e
# vertical), com uma margem lateral pra não colar nas bordas, começando
# invisível (quem chama decide quando e como ele aparece/desaparece).
func _make_story_slide(text: String, color: Color, font_size: int) -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.modulate = Color(1, 1, 1, 0)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(lbl)
	return margin


func _show_fired_final_panel() -> void:
	for c in screen.get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(screen.size.x / 2.0 - 260, screen.size.y / 2.0 - 100)
	vbox.custom_minimum_size = Vector2(520, 200)
	vbox.add_theme_constant_override("separation", 16)
	vbox.modulate = Color(1, 1, 1, 0)
	screen.add_child(vbox)

	var title := Label.new()
	title.text = "VOCÊ FOI DEMITIDO"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", C_ERROR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "A CodeCorp decidiu seguir 100%% com a %s.\nSeu crachá foi desativado." % GameManager.current_ai_name()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", C_ERROR)
	sub.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(sub)

	var btn := Button.new()
	btn.text = "Voltar para o menu"
	btn.custom_minimum_size = Vector2(160, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn)
	btn.pressed.connect(func():
		GameManager.reset_game()
		_show_main_menu()
	)

	var tween := create_tween()
	tween.tween_property(vbox, "modulate:a", 1.0, 0.6)


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
	title.text = "VOCÊ VENCEU A %s!" % GameManager.current_ai_name()
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", C_PLAYER_BAR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Catorze dias de duelo contra a IA, catorze vitórias. O emprego é seu — por enquanto."
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
