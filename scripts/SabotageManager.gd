extends Node
class_name SabotageManager
## SabotageManager
## Cuida só do "QUANDO" e do "O QUÊ" da sabotagem da IA durante a corrida -
## não desenha nada sozinho. Quem constrói a UI de verdade (pop-up falso ou
## vídeo com som) é o Main.gd, conectado no sinal "popup_requested" abaixo.
## Essa separação existe pra deixar o ajuste de dificuldade (intervalo entre
## pop-ups, chance de vídeo) isolado num lugar só, fácil de mexer por nível.
##
## Uso básico (feito pelo Main.gd):
##   sabotage.popup_requested.connect(_on_sabotage_popup_requested)
##   sabotage.start(dia_atual)   # ao abrir o editor/começar a corrida
##   sabotage.stop()             # ao terminar/fechar a corrida
##
## kind emitido em popup_requested: "fake_window" (janela falsa comum) ou
## "video" (vídeo com som, tipo "vírus de spam"). "payload" fica reservado
## pra uso futuro (hoje sempre chega vazio).

signal popup_requested(kind: String, payload: Dictionary)

# ---------------------------------------------------------------------------
# INTERVALO ENTRE POP-UPS, POR DIA/NÍVEL (em segundos)
# ---------------------------------------------------------------------------
# Vector2(min, max): o próximo pop-up é sorteado dentro desse intervalo,
# contado a partir do início da corrida OU do instante em que o ÚLTIMO
# pop-up apareceu (o que valer no momento) - não de quando ele foi fechado.
# Ou seja: se o jogador demorar pra fechar um pop-up e o intervalo for
# curto, outro pode aparecer em cima - efeito "sabotagem em cascata", de
# propósito, pra IA ficar mais agressiva conforme o dia fica mais difícil.
#
# Ajuste os valores abaixo livremente por dia. Dias sem entrada explícita
# aqui usam DEFAULT_INTERVAL.
const DEFAULT_INTERVAL := Vector2(10.0, 15.0)
const INTERVALS_BY_DAY := {
	0: Vector2(999999.0, 999999.0), # Dia 0 (treinamento): sabotagem desligada.
	1: Vector2(999999.0, 999999.0),
	2: Vector2(999999.0, 999999.0),
	3: Vector2(999999.0, 999999.0),
	4: Vector2(999999.0, 999999.0),
	5: Vector2(999999.0, 999999.0),
	6: Vector2(12.0, 17.0),
	7: Vector2(11.0, 16.0),
	8: Vector2(10.0, 15.0),
	9: Vector2(9.0, 14.0),
	10: Vector2(8.0, 13.0),
	11: Vector2(8.0, 12.0),
	12: Vector2(7.0, 11.0),
	13: Vector2(6.0, 10.0),
	14: Vector2(5.0, 9.0),
}

# ---------------------------------------------------------------------------
# CHANCE DE O POP-UP SER UM VÍDEO (COM SOM) EM VEZ DE JANELA FALSA COMUM
# ---------------------------------------------------------------------------
# Mesmo esquema do intervalo: um valor padrão + overrides por dia, caso você
# queira a IA mandando mais vídeo (mais barulhento/invasivo) nos dias finais.
const DEFAULT_VIDEO_CHANCE := 0.35
const VIDEO_CHANCE_BY_DAY := {
	0: 0.0,
}

var _day: int = 1
var _active: bool = false
# Incrementado a cada start()/stop(): invalida qualquer timer pendente de um
# ciclo anterior, mesmo que start() seja chamado de novo antes do timer
# antigo disparar (evita duas correntes de pop-up rodando em paralelo).
var _generation: int = 0


func start(day: int) -> void:
	_day = day
	_active = true
	_generation += 1
	_schedule_next(_generation)


func stop() -> void:
	_active = false
	_generation += 1


func _interval_for_day() -> Vector2:
	return INTERVALS_BY_DAY.get(_day, DEFAULT_INTERVAL)


func _video_chance_for_day() -> float:
	return VIDEO_CHANCE_BY_DAY.get(_day, DEFAULT_VIDEO_CHANCE)


func _schedule_next(gen: int) -> void:
	if not _active or gen != _generation:
		return
	var range: Vector2 = _interval_for_day()
	var wait: float = randf_range(range.x, range.y)
	get_tree().create_timer(wait).timeout.connect(_on_timer_timeout.bind(gen))


func _on_timer_timeout(gen: int) -> void:
	if not _active or gen != _generation:
		return
	var kind := "video" if randf() < _video_chance_for_day() else "fake_window"
	popup_requested.emit(kind, {})
	# Já agenda o próximo a partir de AGORA (ver comentário de
	# INTERVALS_BY_DAY acima) - não espera o pop-up atual ser fechado.
	_schedule_next(gen)
