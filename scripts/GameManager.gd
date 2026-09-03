extends Node
## GameManager
## Autoload (singleton) que guarda o estado da campanha:
## progresso do jogador, número de avisos (strikes) e a configuração
## de cada dia (e-mails, código a digitar, velocidade da IA e falas do chefe).
##
## Estrutura da campanha:
##   Dia 0 - Treinamento: sem concorrência de IA, só pra aprender o fluxo.
##   (transição "2 anos depois...")
##   Dia 1 a 5 - Jornada real contra a ChatBot-1000.

signal state_changed

const MAX_LOSSES: int = 3

## Nome da IA concorrente, usado em todas as falas e telas do jogo.
const AI_NAME := "ChatBot-1000"

var current_day: int = 1
var total_losses: int = 0

## Quantidade de e-mails ainda não lidos no dia atual. É inicializado com
## base na quantidade de e-mails do dia (ver "emails" em day_configs) sempre
## que o dia muda (register_win/reset_game).
var unread_email_count: int = 1

# Cada entrada representa um dia de trabalho.
# "emails": lista de mensagens que chegam nesse dia, na ordem em que devem
#     ser lidas. Cada uma tem "from", "subject" e "body".
# "ai_active": se falso, a corrida daquele dia roda sem oponente de IA
#     (usado no Dia 0 - treinamento, antes da ChatBot-1000 existir).
# "code": o snippet que o jogador precisa digitar.
# "ai_wpm": velocidade da IA em palavras por minuto (1 palavra = 5 caracteres).
# "ai_stutter_chance": chance da IA "hesitar" por um instante (só pra dar uma
#     sensação mais orgânica e dar uma folga ocasional ao jogador).
# "pre_transition": textos extras exibidos em telas pretas ANTES do título
#     do dia (ex.: "2 anos depois..."). Vazio na maioria dos dias.
var day_configs: Array = [
	{
		"day": 0,
		"title": "Dia 0 - TREINAMENTO",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Bem-vindo à CodeCorp!",
				"body": "Bem-vindo à CodeCorp! Eu sou seu chefe direto e vou te acompanhar nessa primeira semana.\n\nHoje é só treinamento: sem pressão, sem concorrência, sem pegadinha nenhuma. Quero ver você se acostumar com o nosso editor de código e com o nosso fluxo de trabalho.\n\nAbra o Editor de Código na área de trabalho e complete o exercício abaixo, no seu ritmo."
			}
		],
		"ai_active": false,
		"code": "func soma(a, b):\n    return a + b",
		"ai_wpm": 0,
		"ai_stutter_chance": 0.0,
		"boss_win": "Muito bem para o primeiro dia! Vá descansar - amanhã a rotina começa de verdade.",
		"boss_lose": "Sem problema, isso aqui é só treino. Tenta de novo com calma."
	},
	{
		"day": 1,
		"title": "Dia 1 - De volta ao trabalho",
		"pre_transition": ["2 anos depois..."],
		"emails": [
			{
				"from": "RH - CodeCorp <rh@codecorp.com>",
				"subject": "Comunicado Interno: Redução de Custos",
				"body": "Prezados colaboradores,\n\nDevido ao cenário econômico atual, a CodeCorp está iniciando um programa de redução de custos, com reestruturação de equipes e otimização de processos em todos os departamentos.\n\nContamos com a compreensão e o empenho de todos nesse momento de transição.\n\nAtenciosamente,\nRecursos Humanos"
			},
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Novidades na equipe",
				"body": "Bom dia. Como deve ter visto no comunicado do RH, as coisas estão apertadas por aqui.\n\nPra ajudar a bater as metas, contratamos uma nova assistente de programação: a ChatBot-1000, primeira versão da nossa nova IA de código. A partir de hoje ela trabalha ao seu lado.\n\nVou ser direto: pra não virar meu próximo corte de custos, você precisa ter um desempenho melhor que o dela. Boa sorte."
			}
		],
		"ai_active": true,
		"code": "func fatorial(n):\n    if n <= 1:\n        return 1\n    return n * fatorial(n - 1)",
		"ai_wpm": 25,
		"ai_stutter_chance": 0.18,
		"boss_win": "Nada mal! Você segurou a onda contra a ChatBot-1000 hoje. Mas ela ainda está esquentando.",
		"boss_lose": "Hmm... a IA foi mais rápida dessa vez. Ainda é cedo, mas fique atento."
	},
	{
		"day": 2,
		"title": "Dia 2 - Esquentando",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Dia 2",
				"body": "A ChatBot-1000 está aprendendo rápido. Hoje o código é um pouco maior. Mostre que você também evolui."
			}
		],
		"ai_active": true,
		"code": "func eh_primo(num):\n    if num < 2:\n        return false\n    for i in range(2, num):\n        if num % i == 0:\n            return false\n    return true",
		"ai_wpm": 35,
		"ai_stutter_chance": 0.14,
		"boss_win": "Impressionante! Só não vacile agora.",
		"boss_lose": "Isso é preocupante. Já são alguns avisos acumulados. Recomponha-se."
	},
	{
		"day": 3,
		"title": "Dia 3 - Meio da semana",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Dia 3",
				"body": "Metade da semana. A diretoria está de olho nos números de produtividade. A IA não erra. E você?"
			}
		],
		"ai_active": true,
		"code": "func ordenar(lista):\n    for i in range(lista.size()):\n        for j in range(0, lista.size() - i - 1):\n            if lista[j] > lista[j + 1]:\n                var tmp = lista[j]\n                lista[j] = lista[j + 1]\n                lista[j + 1] = tmp\n    return lista",
		"ai_wpm": 50,
		"ai_stutter_chance": 0.10,
		"boss_win": "Ok, você me surpreendeu de novo. Continue assim.",
		"boss_lose": "Mais um deslize... Estou anotando tudo, sabia?"
	},
	{
		"day": 4,
		"title": "Dia 4 - Quase lá",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Dia 4",
				"body": "Só restam dois dias. Se acumular avisos demais, vou ter que tomar uma decisão difícil sobre seu cargo."
			}
		],
		"ai_active": true,
		"code": "func buscar_binaria(lista, alvo):\n    var inicio = 0\n    var fim = lista.size() - 1\n    while inicio <= fim:\n        var meio = (inicio + fim) / 2\n        if lista[meio] == alvo:\n            return meio\n        elif lista[meio] < alvo:\n            inicio = meio + 1\n        else:\n            fim = meio - 1\n    return -1",
		"ai_wpm": 65,
		"ai_stutter_chance": 0.08,
		"boss_win": "Você está lutando bem. Amanhã é o dia decisivo.",
		"boss_lose": "Isso não está bom. Nada bom mesmo."
	},
	{
		"day": 5,
		"title": "Dia 5 - O Duelo Final",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Dia 5 - Último dia",
				"body": "Último dia. A ChatBot-1000 está no limite máximo de desempenho dela. Prove que um humano ainda tem valor nesta empresa."
			}
		],
		"ai_active": true,
		"code": "func fibonacci(n):\n    if n <= 1:\n        return n\n    var a = 0\n    var b = 1\n    for i in range(2, n + 1):\n        var tmp = a + b\n        a = b\n        b = tmp\n    return b",
		"ai_wpm": 85,
		"ai_stutter_chance": 0.05,
		"boss_win": "Você... você conseguiu. Parabéns. Você mostrou que raciocínio humano ainda faz diferença aqui. Bem-vindo à equipe, de vez.",
		"boss_lose": "Sinto muito. As regras são as regras."
	},
]


func get_current_config() -> Dictionary:
	return day_configs[current_day - 1]


## Retorna o próximo e-mail não lido do dia atual (respeitando a ordem da
## lista "emails"), com base em quantos ainda faltam ler.
func get_current_email() -> Dictionary:
	var emails: Array = get_current_config()["emails"]
	var index: int = emails.size() - unread_email_count
	index = clampi(index, 0, emails.size() - 1)
	return emails[index]


func has_unread_email() -> bool:
	return unread_email_count > 0


func total_days() -> int:
	return day_configs.size()


func register_win() -> void:
	current_day += 1
	if current_day <= total_days():
		unread_email_count = get_current_config()["emails"].size()
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
	unread_email_count = day_configs[0]["emails"].size()
	state_changed.emit()
