extends Node
## GameManager
## Autoload (singleton) que guarda o estado da campanha de 5 dias:
## progresso do jogador, número de avisos (strikes) e a configuração
## de cada dia (código a digitar, velocidade da IA e falas do chefe).

signal state_changed

const MAX_LOSSES: int = 3

var current_day: int = 1
var total_losses: int = 0
var unread_email_count: int = 1

# Cada entrada representa um dia de trabalho.
# "code": o snippet que o jogador precisa digitar.
# "ai_wpm": velocidade da IA em palavras por minuto (1 palavra = 5 caracteres).
# "ai_stutter_chance": chance da IA "hesitar" por um instante (só pra dar uma
#     sensação mais orgânica e dar uma folga ocasional ao jogador).
var day_configs: Array = [
	{
		"day": 1,
		"title": "Dia 1 - TUTORIAL",
		"boss_intro": "Bom dia. A partir de hoje você será testado contra a nossa nova assistente, a CodeBot-3000. Vamos ver do que você é capaz. Comece com algo simples.",
		"boss_win": "Nada mal para o primeiro dia. Mas isso foi só o aquecimento.",
		"boss_lose": "Hmm... a IA foi mais rápida dessa vez. Ainda é cedo, mas fique atento.",
		"code": "func soma(a, b):\n    return a + b",
		"ai_wpm": 25,
		"ai_stutter_chance": 0.18
	},
	{
		"day": 2,
		"title": "Dia 2 - Esquentando",
		"boss_intro": "A CodeBot-3000 está aprendendo rápido. Hoje o código é um pouco maior. Mostre que você também evolui.",
		"boss_win": "Impressionante! Só não vacile agora.",
		"boss_lose": "Isso é preocupante. Já são alguns avisos acumulados. Recomponha-se.",
		"code": "func fatorial(n):\n    if n <= 1:\n        return 1\n    return n * fatorial(n - 1)",
		"ai_wpm": 35,
		"ai_stutter_chance": 0.14
	},
	{
		"day": 3,
		"title": "Dia 3 - Meio da semana",
		"boss_intro": "Metade da semana. A diretoria está de olho nos números de produtividade. A IA não erra. E você?",
		"boss_win": "Ok, você me surpreendeu de novo. Continue assim.",
		"boss_lose": "Mais um deslize... Estou anotando tudo, sabia?",
		"code": "func eh_primo(num):\n    if num < 2:\n        return false\n    for i in range(2, num):\n        if num % i == 0:\n            return false\n    return true",
		"ai_wpm": 50,
		"ai_stutter_chance": 0.10
	},
	{
		"day": 4,
		"title": "Dia 4 - Quase lá",
		"boss_intro": "Só restam dois dias. Se acumular avisos demais, vou ter que tomar uma decisão difícil sobre seu cargo.",
		"boss_win": "Você está lutando bem. Amanhã é o dia decisivo.",
		"boss_lose": "Isso não está bom. Nada bom mesmo.",
		"code": "func ordenar(lista):\n    for i in range(lista.size()):\n        for j in range(0, lista.size() - i - 1):\n            if lista[j] > lista[j + 1]:\n                var tmp = lista[j]\n                lista[j] = lista[j + 1]\n                lista[j + 1] = tmp\n    return lista",
		"ai_wpm": 65,
		"ai_stutter_chance": 0.08
	},
	{
		"day": 5,
		"title": "Dia 5 - O Duelo Final",
		"boss_intro": "Último dia. A CodeBot-3000 está no limite máximo de desempenho dela. Prove que um humano ainda tem valor nesta empresa.",
		"boss_win": "Você... você conseguiu. Parabéns. Você mostrou que raciocínio humano ainda faz diferença aqui. Bem-vindo à equipe, de vez.",
		"boss_lose": "Sinto muito. As regras são as regras.",
		"code": "func buscar_binaria(lista, alvo):\n    var inicio = 0\n    var fim = lista.size() - 1\n    while inicio <= fim:\n        var meio = (inicio + fim) / 2\n        if lista[meio] == alvo:\n            return meio\n        elif lista[meio] < alvo:\n            inicio = meio + 1\n        else:\n            fim = meio - 1\n    return -1",
		"ai_wpm": 85,
		"ai_stutter_chance": 0.05
	},
]


func get_current_config() -> Dictionary:
	return day_configs[current_day - 1]


func has_unread_email() -> bool:
	return unread_email_count > 0


func total_days() -> int:
	return day_configs.size()


func register_win() -> void:
	current_day += 1
	unread_email_count += 1
	state_changed.emit()


func register_loss() -> void:
	total_losses += 1
	state_changed.emit()


func is_fired() -> bool:
	return total_losses >= MAX_LOSSES


func is_campaign_won() -> bool:
	return current_day > total_days()


func reset_game() -> void:
	current_day = 1
	total_losses = 0
	unread_email_count = 1
	state_changed.emit()
