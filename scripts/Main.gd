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

enum State { MENU, CONFIG_MENU, BOOT, DESKTOP, EMAIL, RACE, RESULT, FIRED, VICTORY, QUIT, CREDITS }

# ---------------------------------------------------------------------------
# Paleta "Windows XP"
# ---------------------------------------------------------------------------
const C_BEZEL := Color(0.08, 0.08, 0.09)
const C_SCREEN_OFF := Color(0, 0, 0)
const C_DESKTOP := Color(0.10, 0.35, 0.68)
const C_TASKBAR := Color(0.13, 0.44, 0.85)
const C_TASKBAR_DARK := Color(0.05, 0.22, 0.55)
const C_START_GREEN := Color(0.20, 0.62, 0.22)

# ---------------------------------------------------------------------------
# Paleta da barra de tarefas "Bricks" (bege/marrom, extraída do mockup do
# jogo) - substitui o visual azul "XP" só na taskbar: fundo bege, logo
# "BRICKS" em marrom escuro no lugar do botão "Iniciar", e um pequeno painel
# mais escuro em volta do relógio, no canto direito.
# ---------------------------------------------------------------------------
const C_TASKBAR_BEIGE := Color(0.847, 0.788, 0.698)
const C_TASKBAR_BEIGE_BORDER := Color(0.667, 0.580, 0.427)
const C_BRICKS_LOGO := Color(0.267, 0.184, 0.035)
const C_CLOCK_PANEL_BG := Color(0.667, 0.580, 0.427)
const C_CLOCK_PANEL_BORDER := Color(0.576, 0.490, 0.345)
# Fundo da tela de boot do "Bricks" - mesma família bege/marrom da taskbar,
# só um tom mais claro (creme) pra servir de fundo de tela cheia.
const C_BOOT_BG := Color(0.93, 0.88, 0.78)
# Roxo/índigo escuro do mockup do menu - usado como fundo do menu principal
# e da tela de créditos quando não há wallpaper próprio configurado.
const C_MENU_BG_PURPLE := Color(0.102, 0.071, 0.392)
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

# =====================================================================
# 1) No topo do Main.gd, junto dos outros caminhos de assets
# =====================================================================

# Imagens possíveis pra "janela falsa" de sabotagem (pop-up de vírus/spam
# genérico). Se houver mais de uma, sorteamos entre elas pra dar variedade;
# se nenhuma existir ainda, cai num pop-up só de texto (sem erro).
const FAKE_WINDOW_IMAGE_PATHS := [
	"res://assets/images/sabotagem1.jpg",
	"res://assets/images/sabotagem2.jpg",
	"res://assets/images/sabotagem3.jpg",
	"res://assets/images/sabotagem4.jpg",
	"res://assets/images/sabotagem5.jpg",
	"res://assets/images/sabotagem6.jpg",
	"res://assets/images/sabotagem7.jpg",
	"res://assets/images/sabotagem8.jpg",
	"res://assets/images/sabotagem9.jpg",
	"res://assets/images/sabotagem10.jpg",
]

var _sabotage: SabotageManager
# Guarda as janelas falsas abertas no momento, pra poder fechar todas de
# uma vez quando a corrida terminar (ver _finish_race / fechamento manual).
var _open_sabotage_windows: Array[Control] = []

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
# Som de boot (computador/sistema antigo ligando) - toca ao abrir a tela de
# inicialização do "Bricks", logo após clicar em START. Se o arquivo ainda
# não existir, a sequência de boot roda normalmente, só sem som.
# ---------------------------------------------------------------------------
const BOOT_SOUND_PATH := "res://assets/sfx/boot.wav"

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
# Ícones da área de trabalho (imagens) - opcionais. Se o arquivo ainda não
# existir num desses caminhos, o ícone cai de volta no quadradinho colorido
# de sempre, sem erro nenhum (mesmo esquema dos wallpapers acima).
# ---------------------------------------------------------------------------
const ICON_EMAIL_IMAGE_PATH := "res://assets/images/icons/icon_email.png"
const ICON_EDITOR_IMAGE_PATH := "res://assets/images/icons/icon_editor.png"
const ICON_COMPUTER_IMAGE_PATH := "res://assets/images/icons/icon_computer.png"
const ICON_TRASH_IMAGE_PATH := "res://assets/images/icons/icon_trash.png"

# ---------------------------------------------------------------------------
# Moldura de janela (usada em TODAS as janelas do jogo - email, editor de
# código, pop-ups de confirmação, sabotagem, resultado) e o "kit" visual do
# menu principal (botão, título e o selo "daesc" que abre os créditos).
# Todos opcionais - se o arquivo não existir ainda, cada um cai no visual
# de sempre (sem erro), então dá pra ir adicionando aos poucos.
# ---------------------------------------------------------------------------
const WINDOW_FRAME_IMAGE_PATH := "res://assets/images/window_frame.png"
# Moldura da janela (window_frame.png): reexportada em 3x (nearest-neighbor)
# a partir do recorte original do mockup - o ícone de fechar (o único botão
# que sobrou; restaurar/minimizar foram apagados da própria imagem, já que
# não são mais usados) ficou grande o bastante pra não parecer "espremido"
# nem ficar off-center dentro da barra de título. Retângulo/margens abaixo
# já são as coordenadas da versão em 3x.
const WINDOW_FRAME_MARGIN_LEFT := 6
const WINDOW_FRAME_MARGIN_TOP := 33
const WINDOW_FRAME_MARGIN_RIGHT := 6
const WINDOW_FRAME_MARGIN_BOTTOM := 6
const WINDOW_FRAME_CLOSE_RECT := Rect2(6, 6, 21, 21)
# Fonte "estilo pixel" pro título da janela. Opcional - coloque um .ttf (ex.:
# "Press Start 2P", "Silkscreen", "VT323") nesse caminho pra usar a fonte de
# verdade; sem o arquivo, cai numa fonte pixelada já instalada no sistema
# (se houver) e, por último, na fonte padrão.
const WINDOW_TITLE_FONT_TTF_PATH := "res://assets/fonts/pixel_font.ttf"
const WINDOW_TITLE_FONT_SYSTEM_NAMES := [
	"Press Start 2P", "Silkscreen", "VT323", "Pixel Operator", "monogram",
	"Perfect DOS VGA 437", "monospace"
]
var _window_title_font: Font
const MENU_BUTTON_IMAGE_PATH := "res://assets/images/menu_button.png"
const MENU_TITLE_IMAGE_PATH := "res://assets/images/menu_title.png"
const DAESC_BADGE_IMAGE_PATH := "res://assets/images/daesc_badge.png"
# Créditos - placeholder editável. Adicione uma linha por pessoa/arte
# conforme o time for entrando; a tela de créditos já lê essa lista sozinha.
const CREDITS_LINES := [
	"daesc",
	"",
	"(em breve: mais créditos e artes aqui)",
]

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
var _boot_player: AudioStreamPlayer

# --- Personalização da área de trabalho (ícones) ---
# Posições customizadas (o jogador pode arrastar os ícones livremente).
# Guardadas por icon_id, persistem entre a troca de dias dentro da mesma
# partida; são limpas em _reset_desktop_customizations() (novo jogo).
var _icon_positions: Dictionary = {}
# Se o jogador arrastar a "Caixa de E-mail" ou o "Editor de Código" para a
# lixeira e confirmar, o ícone correspondente é removido em definitivo (ver
# _delete_desktop_icon) e o jogo vai direto pra tela de "Você se demitiu".
var _email_icon_deleted: bool = false
var _editor_icon_deleted: bool = false
# "Meu Computador" também pode ser excluído na lixeira, mas é só cosmético -
# não dispara a tela de "Você se demitiu" (ver _delete_desktop_icon).
var _computer_icon_deleted: bool = false
var _trash_icon_box: Control = null

# --- Barra de tarefas "de verdade" (menu do Bricks + janelas abertas) ---
# Linha de botões da taskbar com os apps abertos no momento (email, editor).
var _taskbar_row: HBoxContainer
# icon_id ("email"/"editor") -> Button correspondente na taskbar.
var _taskbar_buttons: Dictionary = {}
# icon_id -> janela (Control) atual daquele app, pra minimizar/restaurar.
var _open_windows: Dictionary = {}
# Menuzinho que abre ao clicar no símbolo do Bricks (Voltar ao Menu /
# Configurações / Sair). Só existe enquanto estiver aberto.
var _start_menu_popup: Control = null

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
# Fica falso até o jogador digitar o primeiro caractere - o cronômetro (e a
# IA) só passam a andar a partir daí, em vez de já começar a contar no
# instante em que a janela do editor abre.
var race_started_typing: bool = false
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
	_boot_player = AudioStreamPlayer.new()
	add_child(_boot_player)
	_sabotage = SabotageManager.new()
	add_child(_sabotage)
	_sabotage.popup_requested.connect(_on_sabotage_popup_requested)
	_build_monitor_frame()
	_show_main_menu()


func _process(delta: float) -> void:
	if race_active and not race_finished:
		# Nada anda (nem o cronômetro, nem a IA) até o jogador digitar o
		# primeiro caractere - ver race_started_typing / _on_race_text_changed.
		if race_started_typing:
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
		# COVERED (em vez de SCALE puro): a imagem preenche a tela toda,
		# sempre "grande", sem esticar/deformar fora da proporção original -
		# o excesso é cortado nas bordas em vez de espremer o desenho.
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.clip_contents = true
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


# Fonte "estilo pixel" usada no título das janelas (ver WINDOW_TITLE_FONT_*
# no topo do arquivo) - mesmo padrão de fallback gracioso da fonte de código.
func _get_window_title_font() -> Font:
	if _window_title_font:
		return _window_title_font

	if ResourceLoader.exists(WINDOW_TITLE_FONT_TTF_PATH):
		_window_title_font = load(WINDOW_TITLE_FONT_TTF_PATH)
	else:
		var sys_font := SystemFont.new()
		sys_font.font_names = PackedStringArray(WINDOW_TITLE_FONT_SYSTEM_NAMES)
		_window_title_font = sys_font

	return _window_title_font


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

	# Sem wallpaper próprio configurado (MENU_BG_IMAGE_PATH), cai no roxo/
	# índigo do mockup em vez do azul de antes - já fica com a cara certa
	# mesmo sem nenhuma imagem de fundo.
	var bg := _make_background(C_MENU_BG_PURPLE, MENU_BG_IMAGE_PATH)
	screen.add_child(bg)

	_play_menu_music()

	# Largura do título (imagem "THE AI PARABLE") - maior que a largura dos
	# botões de propósito, pra ficar em destaque; os botões usam
	# SIZE_SHRINK_CENTER (ver _make_menu_button) então continuam com o
	# tamanho de sempre e ficam centralizados mesmo com o vbox mais largo.
	const TITLE_WIDTH := 460.0
	const TITLE_HEIGHT := 90.0

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(TITLE_WIDTH, 0)
	vbox.position = Vector2(screen.size.x / 2.0 - TITLE_WIDTH / 2.0, screen.size.y / 2.0 - 160)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	screen.add_child(vbox)

	if ResourceLoader.exists(MENU_TITLE_IMAGE_PATH):
		var title_tex := TextureRect.new()
		title_tex.texture = load(MENU_TITLE_IMAGE_PATH)
		title_tex.custom_minimum_size = Vector2(TITLE_WIDTH, TITLE_HEIGHT)
		title_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		title_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		title_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vbox.add_child(title_tex)
	else:
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

	# Selo "daesc" no canto inferior direito - clicável, abre os créditos
	# (ver _show_credits_screen). É onde mais artes/créditos entram no
	# futuro.
	_add_daesc_credits_button()


# ---------------------------------------------------------------------------
# SÍMBOLO DO "BRICKS" (logo do sistema operacional)
# ---------------------------------------------------------------------------
# Ícone de "tijolinhos" desenhado inteiramente em código (sem depender de
# nenhuma imagem externa) - um quadrado com 2 fileiras de tijolos em
# alvenaria clássica (fiada de baixo deslocada em meio tijolo). Usado em
# TODO lugar que precisar do símbolo do "Bricks" com a mesma cara: barra de
# tarefas e tela de boot (ver _build_taskbar / _play_boot_sequence).
func _make_bricks_logo(size: float = 22.0) -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(size, size)
	# Fica com tamanho fixo (não estica) e centralizado, mesmo dentro de
	# containers (HBox/VBox) que por padrão esticariam um Control comum.
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = C_CLOCK_PANEL_BG
	fsb.border_width_left = 1
	fsb.border_width_right = 1
	fsb.border_width_top = 1
	fsb.border_width_bottom = 1
	fsb.border_color = C_CLOCK_PANEL_BORDER
	fsb.corner_radius_top_left = 3
	fsb.corner_radius_top_right = 3
	fsb.corner_radius_bottom_left = 3
	fsb.corner_radius_bottom_right = 3
	frame.add_theme_stylebox_override("panel", fsb)

	var clip := Control.new()
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(clip)

	var brick_w: float = size / 2.0
	var brick_h: float = size / 3.0
	var gap := 1.0

	# Fiada de cima: 2 tijolos inteiros.
	for i in range(2):
		var r := ColorRect.new()
		r.color = C_BRICKS_LOGO
		r.position = Vector2(i * brick_w + gap, gap)
		r.size = Vector2(brick_w - gap * 2.0, brick_h - gap)
		clip.add_child(r)

	# Fiada de baixo: deslocada meio tijolo (padrão clássico de alvenaria).
	for i in range(-1, 2):
		var r := ColorRect.new()
		r.color = C_BRICKS_LOGO
		r.position = Vector2(brick_w / 2.0 + i * brick_w + gap, brick_h + gap * 2.0)
		r.size = Vector2(brick_w - gap * 2.0, brick_h - gap)
		clip.add_child(r)

	return frame


# Se MENU_BUTTON_IMAGE_PATH existir, o "molde" pixel art vira o fundo do
# botão (esticado como StyleBoxTexture, preservando as bordas/bisel); senão
# cai no Button padrão de sempre.
func _make_menu_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(240, 46)
	# Fica com largura fixa e centralizado, mesmo dentro de um vbox mais
	# largo que ele (ex.: pra acomodar o título maior no menu principal).
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 18)
	if ResourceLoader.exists(MENU_BUTTON_IMAGE_PATH):
		var tex := load(MENU_BUTTON_IMAGE_PATH)
		var btn_sb := StyleBoxTexture.new()
		btn_sb.texture = tex
		btn_sb.texture_margin_left = 10
		btn_sb.texture_margin_right = 10
		btn_sb.texture_margin_top = 8
		btn_sb.texture_margin_bottom = 8
		btn.add_theme_stylebox_override("normal", btn_sb)
		btn.add_theme_stylebox_override("hover", btn_sb)
		btn.add_theme_stylebox_override("pressed", btn_sb)
		btn.add_theme_stylebox_override("focus", btn_sb)
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
		btn.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	return btn


# ---------------------------------------------------------------------------
# SELO "DAESC" (canto inferior direito do menu) -> TELA DE CRÉDITOS
# ---------------------------------------------------------------------------
# Botão com a arte do selo, se ela já existir; senão cai num círculo simples
# com "?" no meio - mesmo canto, mesma função, só sem a arte final ainda.
func _add_daesc_credits_button() -> void:
	var has_image := ResourceLoader.exists(DAESC_BADGE_IMAGE_PATH)
	var badge_size := Vector2(52, 45)
	var badge: Control

	if has_image:
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(DAESC_BADGE_IMAGE_PATH)
		tex_rect.custom_minimum_size = badge_size
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		badge = tex_rect
	else:
		var fallback := Panel.new()
		fallback.custom_minimum_size = badge_size
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = C_MENU_BG_PURPLE.lightened(0.15)
		fsb.border_width_left = 2
		fsb.border_width_right = 2
		fsb.border_width_top = 2
		fsb.border_width_bottom = 2
		fsb.border_color = Color(1, 1, 1, 0.6)
		fsb.corner_radius_top_left = int(badge_size.y / 2.0)
		fsb.corner_radius_top_right = int(badge_size.y / 2.0)
		fsb.corner_radius_bottom_left = int(badge_size.y / 2.0)
		fsb.corner_radius_bottom_right = int(badge_size.y / 2.0)
		fallback.add_theme_stylebox_override("panel", fsb)
		var q := Label.new()
		q.text = "?"
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.add_theme_color_override("font_color", Color(1, 1, 1))
		q.add_theme_font_size_override("font_size", 18)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.add_child(q)
		badge = fallback

	badge.position = Vector2(screen.size.x - badge_size.x - 14, screen.size.y - badge_size.y - 14)
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	badge.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_credits_screen()
	)
	screen.add_child(badge)


func _show_credits_screen() -> void:
	state = State.CREDITS
	for c in screen.get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = C_MENU_BG_PURPLE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	_play_menu_music()

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.position = Vector2(screen.size.x / 2.0 - 210, 50)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	screen.add_child(vbox)

	var title := Label.new()
	title.text = "CRÉDITOS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(title)

	var title_spacer := Control.new()
	title_spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(title_spacer)

	# Lista de créditos - editável em CREDITS_LINES, lá no topo do arquivo.
	# Adicione uma linha por pessoa/arte conforme o time for entrando; essa
	# tela já lê a lista sozinha, sem precisar mexer aqui.
	for line in CREDITS_LINES:
		var lbl := Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		lbl.custom_minimum_size = Vector2(420, 0)
		vbox.add_child(lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var back_btn := _make_menu_button("VOLTAR")
	back_btn.pressed.connect(_show_main_menu)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(back_btn)


# ---------------------------------------------------------------------------
# MENU DE CONFIGURAÇÕES
# ---------------------------------------------------------------------------
# Por enquanto só tem o botão de voltar. No futuro, novas opções (volume,
# dificuldade, fonte, etc.) entram aqui dentro do vbox, sem precisar mexer
# no menu principal.
# "return_callback" opcional: se vazio, o RETURN volta pro menu principal
# (comportamento de sempre, quando a config é aberta a partir do menu). Se
# for passado (ver _on_start_menu_open_config), o RETURN chama ele em vez
# disso - por exemplo _build_desktop, pra voltar direto pro MESMO dia em
# andamento sem resetar o progresso da campanha nem replayer o boot/
# transição de dia inteiros de novo.
func _show_config_menu(return_callback: Callable = Callable()) -> void:
	state = State.CONFIG_MENU
	for c in screen.get_children():
		c.queue_free()

	var bg := _make_background(C_MENU_BG_PURPLE, MENU_BG_IMAGE_PATH)
	screen.add_child(bg)

	# A música do menu só toca se a volta for pro menu principal (que já tem
	# música própria). Se a config foi aberta de dentro do jogo, o desktop
	# não tem música - evita ela ficar tocando por cima ao voltar pro dia.
	if not return_callback.is_valid():
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
	back_btn.pressed.connect(func():
		if return_callback.is_valid():
			_stop_menu_music()
			return_callback.call()
		else:
			_show_main_menu()
	)
	vbox.add_child(back_btn)


func _on_menu_start_pressed() -> void:
	_stop_menu_music()
	# 1) transição (fade pro preto) saindo do menu; 2) tela de boot do
	# "Bricks" carregando de verdade; 3) só quando o boot termina, a
	# transição de "Dia 0" e a área de trabalho aparecem.
	_play_multi_text_transition([], func():
		_play_boot_sequence(func():
			var cfg: Dictionary = GameManager.get_current_config()
			_play_day_transition_for_cfg(cfg, func():
				_build_desktop()
			)
		)
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


# ---------------------------------------------------------------------------
# SEQUÊNCIA DE BOOT ("Bricks" - o sistema operacional do jogo)
# ---------------------------------------------------------------------------
# Tela cheia preta com o logo do "Bricks" e uma barra de carregamento real:
# o "on_complete" só é chamado quando a barra termina de encher (ou seja, só
# depois que o "sistema operacional" termina de carregar de verdade) - nunca
# antes disso.
func _play_boot_sequence(on_complete: Callable) -> void:
	state = State.BOOT
	for c in screen.get_children():
		c.queue_free()

	# Mesma paleta bege/marrom da barra de tarefas - o "Bricks" é sempre a
	# mesma cara, do boot ao desktop.
	var bg := ColorRect.new()
	bg.color = C_BOOT_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.position = Vector2(screen.size.x / 2.0 - 160, screen.size.y / 2.0 - 50)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	vbox.modulate = Color(1, 1, 1, 0)
	screen.add_child(vbox)

	var logo_row := HBoxContainer.new()
	logo_row.add_theme_constant_override("separation", 10)
	logo_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(logo_row)

	logo_row.add_child(_make_bricks_logo(30.0))

	var logo := Label.new()
	logo.text = "BRICKS OS"
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo.add_theme_font_size_override("font_size", 32)
	logo.add_theme_color_override("font_color", C_BRICKS_LOGO)
	logo_row.add_child(logo)

	var bar_spacer := Control.new()
	bar_spacer.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(bar_spacer)

	# Barra de carregamento com cantos arredondados (~5px) em vez de reta -
	# mesma cor de sempre, só com border_radius pra ficar mais suave.
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(320, 14)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1.0, 0.97, 0.92)
	bar_bg.border_width_left = 1
	bar_bg.border_width_right = 1
	bar_bg.border_width_top = 1
	bar_bg.border_width_bottom = 1
	bar_bg.border_color = C_TASKBAR_BEIGE_BORDER
	bar_bg.corner_radius_top_left = 5
	bar_bg.corner_radius_top_right = 5
	bar_bg.corner_radius_bottom_left = 5
	bar_bg.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = C_BRICKS_LOGO
	bar_fill.corner_radius_top_left = 5
	bar_fill.corner_radius_top_right = 5
	bar_fill.corner_radius_bottom_left = 5
	bar_fill.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(bar)

	var status := Label.new()
	status.text = "Carregando..."
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", C_TASKBAR_BEIGE_BORDER)
	status.add_theme_font_size_override("font_size", 12)
	status.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(status)

	_play_boot_sound()

	var tween := create_tween()
	tween.tween_property(vbox, "modulate:a", 1.0, 0.4)
	tween.tween_property(bar, "value", 100.0, 1.9).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func(): status.text = "Bricks iniciado.")
	tween.tween_interval(0.35)
	tween.tween_callback(on_complete)


func _play_boot_sound() -> void:
	if not ResourceLoader.exists(BOOT_SOUND_PATH):
		# Sem arquivo definitivo ainda: a sequência de boot roda normalmente,
		# só sem som - basta colocar um .wav/.ogg em BOOT_SOUND_PATH quando o
		# efeito de "computador antigo ligando" estiver pronto.
		return
	if _boot_player.stream == null:
		_boot_player.stream = load(BOOT_SOUND_PATH)
	_boot_player.play()


# ---------------------------------------------------------------------------
# DESKTOP
# ---------------------------------------------------------------------------
func _build_desktop() -> void:
	state = State.DESKTOP
	_close_bricks_start_menu()

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

	# Ícones do desktop (arrastáveis - ver _add_desktop_icon). Qualquer um
	# deles some pro resto da partida se já foi excluído na lixeira.
	_trash_icon_box = null
	email_badge = null
	if not _email_icon_deleted:
		email_badge = _add_desktop_icon(desktop_layer, Vector2(30, 60), "Outlook\nExpress", Color(0.95, 0.85, 0.2), true, _open_email, "email", ICON_EMAIL_IMAGE_PATH)
		if email_badge:
			# A bolinha nasce escondida - só aparece com a animação/som depois de
			# 1s, controlada por _schedule_email_notification() logo abaixo.
			email_badge.visible = false
	if not _editor_icon_deleted:
		_add_desktop_icon(desktop_layer, Vector2(30, 170), "Editor de\nCódigo", Color(0.25, 0.55, 0.95), false, _try_open_editor, "editor", ICON_EDITOR_IMAGE_PATH)
	if not _computer_icon_deleted:
		_add_desktop_icon(desktop_layer, Vector2(30, 280), "Meu\nComputador", Color(0.8, 0.8, 0.85), false, func(): _show_toast("Nada de interessante por aqui..."), "computer", ICON_COMPUTER_IMAGE_PATH)
	_add_desktop_icon(desktop_layer, Vector2(30, 390), "Lixeira", Color(0.6, 0.6, 0.65), false, func(): _show_toast("A lixeira está vazia."), "trash", ICON_TRASH_IMAGE_PATH)

	# Camada de janelas (fica por cima de tudo, mas ainda dentro da tela)
	window_layer = Control.new()
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(window_layer)

	_build_taskbar()

	if not _email_icon_deleted and GameManager.has_unread_email():
		_schedule_email_notification()


# Resolve o caminho de um ícone, tentando também uma variação sem a
# subpasta "icons/" (assets/images/icon_x.png em vez de
# assets/images/icons/icon_x.png). Se nenhuma das duas existir, avisa no
# console (fica só no Output do editor - não trava nem mostra erro pro
# jogador) com os dois caminhos tentados, pra facilitar achar o motivo
# (pasta com nome diferente, arquivo ainda não importado pelo Godot, etc.).
func _resolve_icon_path(icon_image_path: String) -> String:
	if icon_image_path == "":
		return ""
	if ResourceLoader.exists(icon_image_path):
		return icon_image_path
	var flat_path := icon_image_path.replace("icons/", "")
	if ResourceLoader.exists(flat_path):
		return flat_path
	push_warning("Ícone não encontrado em '%s' nem em '%s' - usando o quadradinho colorido de fallback. Confira se o arquivo existe nesse caminho e se o Godot já importou (abra o editor uma vez e espere a importação)." % [icon_image_path, flat_path])
	return ""


func _add_desktop_icon(parent: Control, default_pos: Vector2, caption: String, tint: Color, notify: bool, on_activate: Callable, icon_id: String = "", icon_image_path: String = "") -> Control:
	var box := VBoxContainer.new()
	# Se o jogador já arrastou esse ícone antes (nessa mesma partida), volta
	# pra posição que ele deixou em vez de nascer sempre no lugar padrão.
	box.position = _icon_positions.get(icon_id, default_pos) if icon_id != "" else default_pos
	box.custom_minimum_size = Vector2(72, 84)
	box.pivot_offset = Vector2(36, 42)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	# Ícone de verdade (imagem), se o arquivo já existir; senão cai no
	# quadradinho colorido de sempre - sem erro nenhum (mesmo esquema dos
	# outros assets opcionais do jogo). Também tenta uma variação sem a
	# subpasta "icons/" (caso o arquivo tenha sido colocado direto em
	# assets/images/), pra não depender de acertar a estrutura de pastas
	# exata na primeira tentativa.
	var icon_panel: Control
	var resolved_icon_path := _resolve_icon_path(icon_image_path)
	if resolved_icon_path != "":
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(resolved_icon_path)
		tex_rect.custom_minimum_size = Vector2(48, 48)
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Filtro "nearest": mantém a arte pixelada nítida ao escalar, em vez
		# de borrar (o padrão do Godot borraria os pixels do ícone).
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_panel = tex_rect
	else:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(48, 48)
		panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
		panel.add_theme_stylebox_override("panel", sb)
		icon_panel = panel
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	# Distingue "clique" de "arraste": só considera arraste se o mouse se
	# moveu mais que um pequeno limiar depois de pressionado - abaixo disso,
	# conta como clique normal (abre o app, com o feedback de
	# _activate_desktop_icon). Ao soltar em cima da lixeira, dispara a
	# confirmação de exclusão (só pra "email"/"editor" - ver
	# _on_desktop_icon_dropped).
	var drag := {"active": false, "moved": false, "grab_offset": Vector2.ZERO, "start_pos": Vector2.ZERO}
	box.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag["active"] = true
				drag["moved"] = false
				drag["grab_offset"] = box.get_global_mouse_position() - box.position
				drag["start_pos"] = box.position
			elif drag["active"]:
				drag["active"] = false
				if drag["moved"]:
					if icon_id != "":
						_icon_positions[icon_id] = box.position
					_on_desktop_icon_dropped(box, icon_id)
				else:
					_activate_desktop_icon(box, icon_id, on_activate)
		elif event is InputEventMouseMotion and drag["active"]:
			var target: Vector2 = box.get_global_mouse_position() - drag["grab_offset"]
			target.x = clamp(target.x, 0.0, max(0.0, screen.size.x - box.custom_minimum_size.x))
			target.y = clamp(target.y, 0.0, max(0.0, screen.size.y - 40.0 - box.custom_minimum_size.y))
			if target.distance_to(drag["start_pos"]) > 4.0:
				drag["moved"] = true
			box.position = target
	)

	parent.add_child(box)
	if icon_id == "trash":
		_trash_icon_box = box
	return badge_bg


# Pequeno efeito de "clique" (o ícone encolhe e volta) seguido de um atraso
# curto antes de a janela do aplicativo realmente abrir.
func _activate_desktop_icon(box: Control, icon_id: String, on_activate: Callable) -> void:
	var tween := create_tween()
	tween.tween_property(box, "scale", Vector2(0.85, 0.85), 0.07)
	tween.tween_property(box, "scale", Vector2(1.0, 1.0), 0.09)
	var t := get_tree().create_timer(0.16)
	t.timeout.connect(func():
		if not is_instance_valid(box):
			return
		# Se esse app (email/editor) já está aberto, um segundo clique - ou
		# um duplo-clique rápido de hábito - só restaura/traz a janela
		# existente pra frente, em vez de abrir uma SEGUNDA janela por cima
		# (o que deixava uma órfã sem botão na taskbar ao fechar a outra).
		if icon_id != "" and _open_windows.has(icon_id) and is_instance_valid(_open_windows[icon_id]):
			var win: Control = _open_windows[icon_id]
			win.visible = true
			if is_instance_valid(window_layer):
				window_layer.move_child(win, window_layer.get_child_count() - 1)
			return
		on_activate.call()
	)


# Chamado quando o jogador solta um ícone depois de arrastá-lo. "Caixa de
# E-mail", "Editor de Código" e "Meu Computador" disparam a mecânica da
# lixeira (excluir de vez, com confirmação); os demais ícones (ex.: a
# própria Lixeira) apenas ficam na nova posição.
func _on_desktop_icon_dropped(box: Control, icon_id: String) -> void:
	if icon_id != "email" and icon_id != "editor" and icon_id != "computer":
		return
	if not is_instance_valid(_trash_icon_box) or _trash_icon_box == box:
		return
	var trash_rect := Rect2(_trash_icon_box.global_position, _trash_icon_box.size)
	var box_rect := Rect2(box.global_position, box.size)
	if trash_rect.intersects(box_rect):
		_show_trash_confirm_popup(box, icon_id)


func _show_trash_confirm_popup(icon_box: Control, icon_id: String) -> void:
	var built := _make_window("Lixeira", Vector2(360, 170))
	var win: Control = built["window"]
	var content: Control = built["content"]
	built["close_button"].pressed.connect(func(): win.queue_free())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	content.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var msg := Label.new()
	msg.text = "Você tem certeza? Essa alteração será irreversível."
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg.add_theme_color_override("font_color", C_TEXT_DARK)
	msg.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.custom_minimum_size = Vector2(120, 32)
	cancel_btn.pressed.connect(func(): win.queue_free())
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "Excluir"
	confirm_btn.custom_minimum_size = Vector2(120, 32)
	confirm_btn.pressed.connect(func():
		win.queue_free()
		_delete_desktop_icon(icon_box, icon_id)
	)
	btn_row.add_child(confirm_btn)


# Exclusão definitiva do ícone. Email e editor tornam o dia de trabalho
# impossível de completar - por isso vão direto pra tela de "Você se
# demitiu" (ver _show_quit_screen). "Meu Computador" é só decorativo: some
# do desktop e pronto, sem nenhuma outra consequência.
func _delete_desktop_icon(icon_box: Control, icon_id: String) -> void:
	if icon_id == "email":
		_email_icon_deleted = true
		if is_instance_valid(email_badge):
			email_badge.visible = false
	elif icon_id == "editor":
		_editor_icon_deleted = true
	elif icon_id == "computer":
		_computer_icon_deleted = true
	_icon_positions.erase(icon_id)
	if is_instance_valid(icon_box):
		icon_box.queue_free()
	if icon_id == "email" or icon_id == "editor":
		_show_quit_screen()
	else:
		_show_toast("Item excluído.")


# Limpa toda a personalização da área de trabalho (posições arrastadas e
# ícones excluídos). Chamado sempre que a campanha é reiniciada do zero.
func _reset_desktop_customizations() -> void:
	_icon_positions.clear()
	_email_icon_deleted = false
	_editor_icon_deleted = false
	_computer_icon_deleted = false
	_trash_icon_box = null


func _build_taskbar() -> void:
	# Visual "Bricks" (bege/marrom): logo do sistema à esquerda no lugar do
	# botão "Iniciar", e o relógio à direita dentro de um painelzinho.
	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TASKBAR_BEIGE
	sb.border_width_top = 2
	sb.border_color = C_TASKBAR_BEIGE_BORDER
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

	# Botão "Iniciar" do Bricks: o símbolo + "BRICKS", clicável - abre o
	# menuzinho com Voltar ao Menu / Configurações / Sair (ver
	# _show_bricks_start_menu). Usamos um Control com gui_input (mesmo
	# padrão dos ícones da área de trabalho) em vez de um Button de verdade,
	# pra poder controlar o layout interno (ícone + texto) livremente.
	var logo_margin := MarginContainer.new()
	logo_margin.add_theme_constant_override("margin_left", 10)
	logo_margin.add_theme_constant_override("margin_right", 10)
	logo_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	logo_margin.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_bricks_start_menu()
	)
	hbox.add_child(logo_margin)

	var logo_row := HBoxContainer.new()
	logo_row.add_theme_constant_override("separation", 8)
	logo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	logo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_margin.add_child(logo_row)

	logo_row.add_child(_make_bricks_logo(22.0))

	var logo_label := Label.new()
	logo_label.text = "BRICKS"
	logo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo_label.add_theme_font_size_override("font_size", 18)
	logo_label.add_theme_color_override("font_color", C_BRICKS_LOGO)
	logo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_row.add_child(logo_label)

	# Janelas abertas no momento (email, editor de código - ver
	# _taskbar_register_window). Reconstruída do zero a cada dia, junto com
	# o resto da taskbar.
	_taskbar_buttons.clear()
	_open_windows.clear()
	_taskbar_row = HBoxContainer.new()
	_taskbar_row.add_theme_constant_override("separation", 6)
	hbox.add_child(_taskbar_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var clock_panel := Panel.new()
	var clock_sb := StyleBoxFlat.new()
	clock_sb.bg_color = C_CLOCK_PANEL_BG
	clock_sb.border_width_left = 1
	clock_sb.border_width_top = 1
	clock_sb.border_width_bottom = 1
	clock_sb.border_color = C_CLOCK_PANEL_BORDER
	clock_sb.content_margin_left = 12
	clock_sb.content_margin_right = 12
	clock_panel.add_theme_stylebox_override("panel", clock_sb)
	clock_panel.custom_minimum_size = Vector2(70, 36)
	hbox.add_child(clock_panel)

	taskbar_clock = Label.new()
	taskbar_clock.add_theme_color_override("font_color", C_BRICKS_LOGO)
	taskbar_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	taskbar_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taskbar_clock.set_anchors_preset(Control.PRESET_FULL_RECT)
	var t: Dictionary = Time.get_time_dict_from_system()
	taskbar_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]
	clock_panel.add_child(taskbar_clock)


# ---------------------------------------------------------------------------
# JANELAS ABERTAS NA BARRA DE TAREFAS (email, editor de código)
# ---------------------------------------------------------------------------
# Um botão por "app" (não por janela): a caixa de entrada, por exemplo,
# recria a janela toda vez que o jogador troca de mensagem
# (_render_email_window), mas continua sendo o MESMO app aberto - por isso
# _taskbar_register_window reaproveita o botão existente em vez de duplicar,
# só atualizando qual é a janela "atual" daquele app.
func _make_taskbar_app_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(130, 28)
	btn.add_theme_font_size_override("font_size", 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CLOCK_PANEL_BG
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = C_CLOCK_PANEL_BORDER
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	# Mesmo estilo em todo estado do botão, senão o Godot usa o padrão
	# (azul/cinza) pra hover/pressed/focus, destoando da paleta bege.
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", C_BRICKS_LOGO)
	btn.add_theme_color_override("font_hover_color", C_BRICKS_LOGO)
	btn.add_theme_color_override("font_pressed_color", C_BRICKS_LOGO)
	btn.add_theme_color_override("font_focus_color", C_BRICKS_LOGO)
	return btn


# Registra (ou atualiza) o botão de um app na taskbar. Chame sempre que uma
# janela desse app for criada/recriada - se já existir um botão pra esse
# icon_id, só troca a janela "atual" e o texto, sem duplicar.
func _taskbar_register_window(icon_id: String, label: String, win: Control) -> void:
	_open_windows[icon_id] = win
	if _taskbar_buttons.has(icon_id) and is_instance_valid(_taskbar_buttons[icon_id]):
		_taskbar_buttons[icon_id].text = label
		return
	if not is_instance_valid(_taskbar_row):
		return
	var btn := _make_taskbar_app_button(label)
	btn.pressed.connect(func(): _on_taskbar_app_button_pressed(icon_id))
	_taskbar_row.add_child(btn)
	_taskbar_buttons[icon_id] = btn


# Remove o botão de um app da taskbar (chamado quando a janela é realmente
# fechada, não só recriada - ver os close_button/"Fechar" do email e do
# editor).
func _taskbar_unregister_window(icon_id: String) -> void:
	_open_windows.erase(icon_id)
	if _taskbar_buttons.has(icon_id):
		var btn = _taskbar_buttons[icon_id]
		if is_instance_valid(btn):
			btn.queue_free()
		_taskbar_buttons.erase(icon_id)


# Clique no botão da taskbar: minimiza (esconde) se a janela estiver
# visível, ou restaura e traz pra frente se estiver minimizada.
func _on_taskbar_app_button_pressed(icon_id: String) -> void:
	if not _open_windows.has(icon_id):
		return
	var win: Control = _open_windows[icon_id]
	if not is_instance_valid(win):
		_taskbar_unregister_window(icon_id)
		return
	if win.visible:
		win.visible = false
	else:
		win.visible = true
		window_layer.move_child(win, window_layer.get_child_count() - 1)
		win.grab_focus()


# Limpa todos os botões/janelas registrados na taskbar de uma vez - usado
# quando TODAS as janelas são fechadas de propósito (fim de corrida, tela de
# "Você se demitiu"), sem passar pelo close_button de cada uma.
func _clear_taskbar_windows() -> void:
	for icon_id in _taskbar_buttons.keys():
		var btn = _taskbar_buttons[icon_id]
		if is_instance_valid(btn):
			btn.queue_free()
	_taskbar_buttons.clear()
	_open_windows.clear()


# ---------------------------------------------------------------------------
# MENU DO BOTÃO "BRICKS" (Voltar ao Menu / Configurações / Sair)
# ---------------------------------------------------------------------------
func _show_bricks_start_menu() -> void:
	# Clicar de novo no símbolo com o menu já aberto funciona como fechar
	# (mesmo esquema de um menu Iniciar de verdade).
	if is_instance_valid(_start_menu_popup):
		_close_bricks_start_menu()
		return

	# Overlay invisível cobrindo a tela toda: clicar em qualquer lugar fora
	# do menuzinho fecha ele (mesmo truque usado em menus popup nativos).
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_bricks_start_menu()
	)
	window_layer.add_child(overlay)

	var menu := Panel.new()
	var msb := StyleBoxFlat.new()
	msb.bg_color = C_TASKBAR_BEIGE
	msb.border_width_left = 1
	msb.border_width_right = 1
	msb.border_width_top = 1
	msb.border_width_bottom = 1
	msb.border_color = C_TASKBAR_BEIGE_BORDER
	menu.add_theme_stylebox_override("panel", msb)
	# 3 itens de 30px + 2 espaços de 4px entre eles + 12px de margem (6 em
	# cima, 6 embaixo) - ver margin/vbox logo abaixo.
	var menu_size := Vector2(190, 3 * 30 + 2 * 4 + 12)
	menu.custom_minimum_size = menu_size
	menu.size = menu_size
	menu.position = Vector2(8, screen.size.y - 36 - menu_size.y - 4)
	# Consome o clique nela mesma, pra não vazar pro overlay por trás e
	# fechar o menu ao clicar num item.
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(menu)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	menu.add_child(margin)
	margin.add_child(vbox)

	var btn_menu := _make_start_menu_item("Voltar ao Menu")
	btn_menu.pressed.connect(func():
		_close_bricks_start_menu()
		_on_start_menu_return_to_main()
	)
	vbox.add_child(btn_menu)

	var btn_config := _make_start_menu_item("Configurações")
	btn_config.pressed.connect(func():
		_close_bricks_start_menu()
		_on_start_menu_open_config()
	)
	vbox.add_child(btn_config)

	var btn_exit := _make_start_menu_item("Sair")
	btn_exit.pressed.connect(func(): get_tree().quit())
	vbox.add_child(btn_exit)

	_start_menu_popup = overlay


func _close_bricks_start_menu() -> void:
	if is_instance_valid(_start_menu_popup):
		_start_menu_popup.queue_free()
	_start_menu_popup = null


func _make_start_menu_item(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 30)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_constant_override("h_separation", 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = 10
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = C_CLOCK_PANEL_BG
	hover_sb.content_margin_left = 10
	hover_sb.corner_radius_top_left = 3
	hover_sb.corner_radius_top_right = 3
	hover_sb.corner_radius_bottom_left = 3
	hover_sb.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_color_override("font_color", C_BRICKS_LOGO)
	btn.add_theme_color_override("font_hover_color", C_BRICKS_LOGO)
	btn.add_theme_color_override("font_pressed_color", C_BRICKS_LOGO)
	btn.add_theme_color_override("font_focus_color", C_BRICKS_LOGO)
	return btn


# "Voltar ao Menu": encerra o que estiver rolando na corrida/sabotagem e
# volta pra tela principal, SEM resetar o progresso da campanha (o dia
# atual continua o mesmo - clicar em START de novo retoma daqui).
func _on_start_menu_return_to_main() -> void:
	race_active = false
	_sabotage.stop()
	_close_all_sabotage_windows()
	_stop_menu_music()
	_show_main_menu()


func _on_start_menu_open_config() -> void:
	race_active = false
	_sabotage.stop()
	_close_all_sabotage_windows()
	# Passa _build_desktop como "pra onde voltar": o RETURN da config leva
	# direto pro desktop do MESMO dia (current_day não muda em nenhum
	# momento desse fluxo), sem passar pelo menu principal nem replayer o
	# boot/transição de dia inteiros de novo.
	_show_config_menu(_build_desktop)


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
# Botão invisível (sem texto/estilo próprio) posicionado exatamente em cima
# de um dos ícones já desenhados na moldura (X, restaurar, traço). Só existe
# pra captar o clique - o desenho do botão em si já está na imagem, então
# nada é redesenhado por cima (evita o efeito "amassado"/duplicado).
func _make_chrome_button(rect: Rect2) -> Button:
	var btn := Button.new()
	btn.position = rect.position
	btn.size = rect.size
	btn.custom_minimum_size = rect.size
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_sb := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)
	return btn


func _make_window(title: String, size: Vector2) -> Dictionary:
	var win := Panel.new()
	# Se a moldura pixel art existir, ela vira o visual de verdade da janela
	# (ver NinePatchRect logo abaixo) - o Panel em si fica só como área de
	# clique/arraste, sem desenhar nada por cima da arte.
	var use_frame_image := ResourceLoader.exists(WINDOW_FRAME_IMAGE_PATH)
	if use_frame_image:
		win.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
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

	var content_top: float = WINDOW_FRAME_MARGIN_TOP if use_frame_image else 28.0

	if use_frame_image:
		# NinePatchRect: preserva os cantos e a faixa de título (com os 3
		# botões já desenhados) no tamanho original, e estica só o miolo
		# (um preenchimento de cor sólida, sem nenhuma linha atravessando)
		# pra caber em qualquer tamanho de janela sem amassar.
		var frame := NinePatchRect.new()
		frame.texture = load(WINDOW_FRAME_IMAGE_PATH)
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.patch_margin_left = WINDOW_FRAME_MARGIN_LEFT
		frame.patch_margin_top = WINDOW_FRAME_MARGIN_TOP
		frame.patch_margin_right = WINDOW_FRAME_MARGIN_RIGHT
		frame.patch_margin_bottom = WINDOW_FRAME_MARGIN_BOTTOM
		win.add_child(frame)
	else:
		var fallback_titlebar := Panel.new()
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = C_TITLEBAR_A
		tsb.corner_radius_top_left = 6
		tsb.corner_radius_top_right = 6
		fallback_titlebar.add_theme_stylebox_override("panel", tsb)
		fallback_titlebar.size = Vector2(size.x, content_top)
		fallback_titlebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(fallback_titlebar)

	var title_label := Label.new()
	title_label.text = title
	# Alinhado à esquerda, logo depois do botão de fechar (em vez de
	# centralizado sobre a janela toda) - mesmo layout do molde: ícone,
	# depois o nome do app colado ao lado.
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_bottom = content_top
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_override("font", _get_window_title_font())
	if use_frame_image:
		title_label.offset_left = WINDOW_FRAME_CLOSE_RECT.position.x + WINDOW_FRAME_CLOSE_RECT.size.x + 12
		title_label.add_theme_color_override("font_color", Color(0.067, 0.2, 0.318))
		title_label.add_theme_font_size_override("font_size", 15)
	else:
		title_label.offset_left = 8
		title_label.add_theme_color_override("font_color", Color(1, 1, 1))
		title_label.add_theme_font_size_override("font_size", 14)
	win.add_child(title_label)

	# Área de arraste = a faixa de título inteira. Os 3 botões (quando a
	# moldura existe) são filhos dela e "roubam" o clique antes que vire
	# arraste - por isso não é preciso excluir a região deles manualmente.
	var titlebar_drag := Control.new()
	titlebar_drag.set_anchors_preset(Control.PRESET_TOP_WIDE)
	titlebar_drag.offset_bottom = content_top
	titlebar_drag.mouse_filter = Control.MOUSE_FILTER_STOP
	win.add_child(titlebar_drag)
	_make_draggable(win, titlebar_drag)

	# Só o botão de fechar é funcional - maximizar/minimizar foi removido
	# (o resto da arte na barra de título é só decorativo, se houver).
	var close_btn: Button
	if use_frame_image:
		# Invisível, exatamente sobre o ícone de fechar já desenhado na
		# moldura (ver WINDOW_FRAME_CLOSE_RECT no topo do arquivo).
		close_btn = _make_chrome_button(WINDOW_FRAME_CLOSE_RECT)
	else:
		# Sem a moldura, cai num "X" simples no canto (visual de sempre).
		close_btn = Button.new()
		close_btn.text = "X"
		close_btn.custom_minimum_size = Vector2(24, 22)
		close_btn.position = Vector2(size.x - 30, 3)
	titlebar_drag.add_child(close_btn)

	window_layer.add_child(win)

	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = content_top
	content.clip_contents = true
	win.add_child(content)

	return {"window": win, "titlebar": titlebar_drag, "content": content, "close_button": close_btn}


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
	# A janela é recriada a cada troca de mensagem (win.queue_free() +
	# _render_email_window de novo), mas continua sendo o MESMO app aberto -
	# _taskbar_register_window só atualiza a referência, sem duplicar botão.
	_taskbar_register_window("email", "Caixa de Entrada", win)

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
		_taskbar_unregister_window("email")
	)
	right_vbox.add_child(close_btn)

	built["close_button"].pressed.connect(func():
		win.queue_free()
		state = State.DESKTOP
		_taskbar_unregister_window("email")
	)

func _on_sabotage_popup_requested(kind: String, _payload: Dictionary) -> void:
	if kind == "video":
		return # ainda não implementado - próximo passo
	_show_sabotage_fake_window()


func _show_sabotage_fake_window() -> void:
	var win_size := Vector2(320, 200)
	var built := _make_window("Aviso do Sistema", win_size)
	var win: Control = built["window"]
	var content: Control = built["content"]
	_play_notification_sound()

	# Posição aleatória dentro da tela (em vez do centro padrão de
	# _make_window), com uma margem pra não nascer cortada nas bordas.
	var max_x: float = max(screen.size.x - win_size.x - 8, 8)
	var max_y: float = max(screen.size.y - win_size.y - 8, 8)
	win.position = Vector2(randf_range(8, max_x), randf_range(8, max_y))

	var img_path := _pick_random_fake_window_image()
	if img_path != "":
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(img_path)
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(tex_rect)
	else:
		# Sem imagem definitiva ainda: fallback só com texto, sem travar
		# o desenvolvimento - basta colocar os arquivos em
		# FAKE_WINDOW_IMAGE_PATHS quando estiverem prontos.
		var lbl := Label.new()
		lbl.text = "⚠ Seu sistema está em risco!\nClique aqui para verificar."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_color_override("font_color", C_TEXT_DARK)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(lbl)

	_open_sabotage_windows.append(win)
	built["close_button"].pressed.connect(func():
		_open_sabotage_windows.erase(win)
		win.queue_free()
	)


func _pick_random_fake_window_image() -> String:
	var available: Array = []
	for p in FAKE_WINDOW_IMAGE_PATHS:
		if ResourceLoader.exists(p):
			available.append(p)
	if available.is_empty():
		return ""
	return available[randi() % available.size()]


func _close_all_sabotage_windows() -> void:
	for w in _open_sabotage_windows:
		if is_instance_valid(w):
			w.queue_free()
	_open_sabotage_windows.clear()

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

	# reinicia cronômetro e contadores de precisão - o cronômetro em si só
	# começa a contar de fato quando o jogador digitar o primeiro caractere
	# (ver race_started_typing em _on_race_text_changed).
	race_start_msec = 0
	race_started_typing = false
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
	_taskbar_register_window("editor", "Editor de Código", win)
	built["close_button"].pressed.connect(func():
		race_active = false
		_sabotage.stop()
		_close_all_sabotage_windows()
		win.queue_free()
		state = State.DESKTOP
		_taskbar_unregister_window("editor")
	)


	_refresh_target_display("")
	race_active = true
	_sabotage.start(GameManager.current_day)
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
	if not race_started_typing and typed.length() > 0:
		race_started_typing = true
		race_start_msec = Time.get_ticks_msec()
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
	_sabotage.stop()
	_close_all_sabotage_windows()

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
	_clear_taskbar_windows()

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
		_reset_desktop_customizations()
		GameManager.reset_game()
		_show_main_menu()
	)

	var tween := create_tween()
	tween.tween_property(vbox, "modulate:a", 1.0, 0.6)


# ---------------------------------------------------------------------------
# TELA DE DESISTÊNCIA ("Você se demitiu") - disparada só quando o jogador
# arrasta a Caixa de E-mail ou o Editor de Código pra lixeira e confirma a
# exclusão (ver _delete_desktop_icon). É diferente da tela de demissão por
# perder pontuação pra IA (_show_fired_screen), que continua intacta.
# ---------------------------------------------------------------------------
func _show_quit_screen() -> void:
	state = State.QUIT
	race_active = false
	_sabotage.stop()
	_close_all_sabotage_windows()

	for c in window_layer.get_children():
		c.queue_free()
	_clear_taskbar_windows()
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
	title.text = "VOCÊ SE DEMITIU"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", C_ERROR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Sem a caixa de e-mail e sem o editor de código, não há mais como continuar o trabalho por aqui."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.add_theme_color_override("font_color", C_ERROR)
	sub.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(sub)

	var btn := Button.new()
	btn.text = "Retornar para o Menu"
	btn.custom_minimum_size = Vector2(200, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn)
	btn.pressed.connect(func():
		_reset_desktop_customizations()
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
	sub.text = "Por enquanto você superou o chatbot. Parabéns, você chegou ao limite do jogo. Aguarde mais atualizações."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	sub.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(sub)

	var btn := Button.new()
	btn.text = "Jogar novamente"
	btn.custom_minimum_size = Vector2(180, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn)
	btn.pressed.connect(func():
		_reset_desktop_customizations()
		GameManager.reset_game()
		_build_desktop()
	)
