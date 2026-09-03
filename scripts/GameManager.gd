extends Node
## GameManager
## Autoload (singleton) que guarda o estado da campanha:
## progresso do jogador e a configuração de cada dia (e-mails, código a
## digitar, velocidade/precisão da IA e falas do chefe).
##
## Estrutura da campanha:
##   Dia 0 - Treinamento: sem concorrência de IA, só pra aprender o fluxo.
##   (transição "2 anos depois...")
##   Dia 1 a 14 - Jornada real contra a IA da empresa, que evolui de versão
##   a cada 2 dias (ChatBot-1000 -> ChatBot-7000). A cada dia o jogador e a
##   IA são comparados por uma pontuação (precisão % + tempo); se a IA
##   pontuar mais, é demissão na hora.

signal state_changed

## Antigamente eram 3 "avisos" acumulados até ser demitido. Agora a
## comparação de pontuação decide o dia inteiro: uma única derrota já é
## suficiente pra demissão (ver is_fired()).
const MAX_LOSSES: int = 1

var current_day: int = 1
var total_losses: int = 0

## Uma entrada (bool) por e-mail do dia atual: true = já lido. É reiniciada
## sempre que o dia muda (ver register_win/reset_game/_init_day_email_flags).
var email_read_flags: Array = []

# Cada entrada representa um dia de trabalho.
#
# "emails": lista de mensagens que chegam nesse dia (RH, chefe, ou a
#     empresa da IA avisando de atualização). Cada uma tem "from", "subject"
#     e "body". O jogador pode ler em qualquer ordem, indo e voltando entre
#     elas na caixa de entrada.
# "ai_active": se falso, o dia roda sem oponente de IA e o jogador sempre
#     "vence" (usado só no Dia 0 - treinamento, antes da IA existir).
# "ai_version_name": nome exibido da IA concorrente nesse dia (evolui a
#     cada 2 dias: ChatBot-1000, ChatBot-2000, ... até ChatBot-7000).
# "code": o snippet que o jogador precisa digitar.
# "ai_wpm": velocidade da IA em palavras por minuto (1 palavra = 5
#     caracteres) - usada tanto pra animar a barra dela quanto pra calcular
#     o "tempo teórico" dela na hora de pontuar.
# "ai_stutter_chance": chance da IA "hesitar" por um instante (dá uma
#     sensação mais orgânica à animação e uma pequena folga extra no tempo
#     teórico dela).
# "ai_accuracy": taxa de acerto da IA (0.0 a 1.0), usada como o "percentual
#     de precisão" dela na pontuação final. Sobe aos poucos a cada versão e
#     é limitada a 0.94 (94%) mesmo na melhor versão - a IA nunca é
#     perfeita, então o jogador sempre tem uma chance real.
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
		"ai_version_name": "—",
		"code": "func soma(a, b):\n    return a + b",
		"ai_wpm": 0,
		"ai_stutter_chance": 0.0,
		"ai_accuracy": 1.0,
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
				"body": "Bom dia. Você foi bem no treinamento, isso é bom - vai precisar disso.\n\nComo deve ter visto no comunicado do RH, as coisas estão apertadas por aqui. Pra ajudar a bater as metas, contratamos uma nova assistente de programação: a ChatBot-1000, primeira versão da nossa nova IA de código. A partir de hoje ela trabalha ao seu lado, todo santo dia.\n\nVou ser direto: a cada dia, quem pontuar mais entre você e ela continua. Pra não virar meu próximo corte de custos, você precisa ter um desempenho melhor. Boa sorte."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-1000",
		"code": "func fatorial(n):\n    if n <= 1:\n        return 1\n    return n * fatorial(n - 1)",
		"ai_wpm": 25,
		"ai_stutter_chance": 0.20,
		"ai_accuracy": 0.78,
		"boss_win": "Nada mal! Você superou a ChatBot-1000 na estreia dela.",
		"boss_lose": "A ChatBot-1000 pontuou mais que você logo no primeiro dia. Isso é ruim."
	},
	{
		"day": 2,
		"title": "Dia 2 - Esquentando",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Bom trabalho ontem",
				"body": "Parabéns pelo resultado de ontem. A ChatBot-1000 recebeu um pequeno ajuste de velocidade durante a madrugada - nada muito grande, mas hoje ela deve render um pouco mais rápido. Fica esperto."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-1000",
		"code": "func eh_primo(num):\n    if num < 2:\n        return false\n    for i in range(2, num):\n        if num % i == 0:\n            return false\n    return true",
		"ai_wpm": 30,
		"ai_stutter_chance": 0.18,
		"ai_accuracy": 0.79,
		"boss_win": "Segurou a onda de novo! Só não vacile.",
		"boss_lose": "Isso é preocupante. A IA está ganhando terreno."
	},
	{
		"day": 3,
		"title": "Dia 3 - Nova versão",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Mais um dia, mais uma vitória",
				"body": "A diretoria está satisfeita com sua produtividade até aqui. Continue nesse ritmo - mas dá uma olhada no e-mail da NeuralCode que chegou hoje."
			},
			{
				"from": "NeuralCode Inc. <updates@neuralcode.ai>",
				"subject": "Atualização disponível: ChatBot-2000",
				"body": "A NeuralCode tem o prazer de anunciar o lançamento da ChatBot-2000!\n\nA nova versão traz uma velocidade de digitação superior e uma taxa de erros reduzida em relação ao modelo anterior. A atualização já foi aplicada automaticamente ao ambiente de trabalho da CodeCorp.\n\nEquipe NeuralCode."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-2000",
		"code": "func ordenar(lista):\n    for i in range(lista.size()):\n        for j in range(0, lista.size() - i - 1):\n            if lista[j] > lista[j + 1]:\n                var tmp = lista[j]\n                lista[j] = lista[j + 1]\n                lista[j + 1] = tmp\n    return lista",
		"ai_wpm": 40,
		"ai_stutter_chance": 0.16,
		"ai_accuracy": 0.82,
		"boss_win": "A ChatBot-2000 é mais rápida, mas você continua na frente. Bom trabalho.",
		"boss_lose": "A versão nova da IA já te superou. Isso não é um bom sinal."
	},
	{
		"day": 4,
		"title": "Dia 4 - Ritmo novo",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Continue assim",
				"body": "A ChatBot-2000 vem cada dia mais ajustada, mas seu resultado de ontem foi sólido. Não relaxe."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-2000",
		"code": "func buscar_binaria(lista, alvo):\n    var inicio = 0\n    var fim = lista.size() - 1\n    while inicio <= fim:\n        var meio = (inicio + fim) / 2\n        if lista[meio] == alvo:\n            return meio\n        elif lista[meio] < alvo:\n            inicio = meio + 1\n        else:\n            fim = meio - 1\n    return -1",
		"ai_wpm": 45,
		"ai_stutter_chance": 0.15,
		"ai_accuracy": 0.83,
		"boss_win": "Ok, você me surpreendeu de novo. Continue assim.",
		"boss_lose": "Mais um dia perdido pra IA... Estou anotando tudo, sabia?"
	},
	{
		"day": 5,
		"title": "Dia 5 - Nova versão",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Metade da primeira semana",
				"body": "A diretoria está de olho nos números de produtividade. A IA não erra fácil. E você?"
			},
			{
				"from": "NeuralCode Inc. <updates@neuralcode.ai>",
				"subject": "Atualização disponível: ChatBot-3000",
				"body": "Chegou a ChatBot-3000!\n\nMais uma rodada de otimizações de velocidade e uma redução adicional na taxa de erros. A atualização já está ativa no ambiente da CodeCorp.\n\nEquipe NeuralCode."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-3000",
		"code": "func fibonacci(n):\n    if n <= 1:\n        return n\n    var a = 0\n    var b = 1\n    for i in range(2, n + 1):\n        var tmp = a + b\n        a = b\n        b = tmp\n    return b",
		"ai_wpm": 55,
		"ai_stutter_chance": 0.13,
		"ai_accuracy": 0.85,
		"boss_win": "Ok, você me surpreendeu de novo. Continue assim.",
		"boss_lose": "Mais um deslize... Estou anotando tudo, sabia?"
	},
	{
		"day": 6,
		"title": "Dia 6",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Seguindo firme",
				"body": "A ChatBot-3000 está mais consistente, mas seu desempenho de ontem foi muito bom. Vamos ver até onde isso vai."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-3000",
		"code": "func inverter_lista(lista):\n    var resultado = []\n    for i in range(lista.size() - 1, -1, -1):\n        resultado.append(lista[i])\n    return resultado",
		"ai_wpm": 62,
		"ai_stutter_chance": 0.12,
		"ai_accuracy": 0.86,
		"boss_win": "Você está lutando bem. Continue de olho nos detalhes.",
		"boss_lose": "Isso não está bom. Nada bom mesmo."
	},
	{
		"day": 7,
		"title": "Dia 7 - Nova versão",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Uma semana inteira",
				"body": "Uma semana inteira segurando a onda. Parabéns. Só que a NeuralCode não para - olha o e-mail que chegou hoje de manhã."
			},
			{
				"from": "NeuralCode Inc. <updates@neuralcode.ai>",
				"subject": "Atualização disponível: ChatBot-4000",
				"body": "Apresentamos a ChatBot-4000!\n\nEssa versão traz o maior salto de desempenho da linha até agora, com digitação bem mais rápida e menos erros. Atualização aplicada automaticamente.\n\nEquipe NeuralCode."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-4000",
		"code": "func eh_palindromo(txt):\n    var invertido = \"\"\n    for i in range(txt.length() - 1, -1, -1):\n        invertido += txt[i]\n    return txt == invertido",
		"ai_wpm": 72,
		"ai_stutter_chance": 0.10,
		"ai_accuracy": 0.88,
		"boss_win": "Impressionante! A ChatBot-4000 é rápida e você ainda assim ganhou.",
		"boss_lose": "A ChatBot-4000 mostrou a que veio. Cuidado com os próximos dias."
	},
	{
		"day": 8,
		"title": "Dia 8",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Ainda na disputa",
				"body": "Você segue firme mesmo com a ChatBot-4000 no seu encalço. Bom trabalho ontem. Amanhã tem novidade de novo, se prepare."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-4000",
		"code": "func maior_lista(lista):\n    var maior = lista[0]\n    for valor in lista:\n        if valor > maior:\n            maior = valor\n    return maior",
		"ai_wpm": 80,
		"ai_stutter_chance": 0.09,
		"ai_accuracy": 0.89,
		"boss_win": "Você está lutando bem. Amanhã tem mais uma atualização da IA.",
		"boss_lose": "Isso não está bom. Nada bom mesmo."
	},
	{
		"day": 9,
		"title": "Dia 9 - Nova versão",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Fica de olho nessa",
				"body": "Bom trabalho ontem. Mas presta atenção: a versão que chegou hoje da NeuralCode é, de longe, a mais rápida que já vimos até agora. Vai ser um teste de verdade."
			},
			{
				"from": "NeuralCode Inc. <updates@neuralcode.ai>",
				"subject": "Atualização disponível: ChatBot-5000",
				"body": "A ChatBot-5000 chegou com um salto expressivo de velocidade de digitação, além de uma taxa de erros ainda menor. É a atualização mais agressiva da linha até o momento. Já está ativa no seu ambiente.\n\nEquipe NeuralCode."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-5000",
		"code": "func contar_vogais(txt):\n    var vogais = \"aeiouAEIOU\"\n    var total = 0\n    for letra in txt:\n        if vogais.find(letra) != -1:\n            total += 1\n    return total",
		"ai_wpm": 95,
		"ai_stutter_chance": 0.08,
		"ai_accuracy": 0.90,
		"boss_win": "Isso foi difícil de assistir - a ChatBot-5000 é rápida pra caramba. E mesmo assim você ganhou.",
		"boss_lose": "A ChatBot-5000 provou o que eu temia: essa versão é brutal. Amanhã vai ser ainda pior."
	},
	{
		"day": 10,
		"title": "Dia 10 - O pico",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Hoje é o dia mais difícil",
				"body": "Sinceramente? Hoje é o dia mais duro até agora. A ChatBot-5000 está no auge da versão dela. Se você passar por hoje, o resto fica mais tranquilo de encarar."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-5000",
		"code": "func mdc(a, b):\n    while b != 0:\n        var resto = a % b\n        a = b\n        b = resto\n    return a",
		"ai_wpm": 110,
		"ai_stutter_chance": 0.07,
		"ai_accuracy": 0.91,
		"boss_win": "Você... conseguiu passar do dia mais difícil até agora. Sério, muito bem.",
		"boss_lose": "Era o dia mais difícil mesmo. Não foi vergonha nenhuma perder pra essa versão."
	},
	{
		"day": 11,
		"title": "Dia 11 - Nova versão",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Passou do pico",
				"body": "Se você superou ontem, já provou o que precisava provar. Ainda assim, chegou atualização nova - dá uma olhada."
			},
			{
				"from": "NeuralCode Inc. <updates@neuralcode.ai>",
				"subject": "Atualização disponível: ChatBot-6000",
				"body": "A ChatBot-6000 já está disponível, com mais ganhos de velocidade e precisão em relação à geração anterior. Atualização aplicada automaticamente ao ambiente da CodeCorp.\n\nEquipe NeuralCode."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-6000",
		"code": "func remover_duplicados(lista):\n    var vistos = []\n    var resultado = []\n    for item in lista:\n        if not vistos.has(item):\n            vistos.append(item)\n            resultado.append(item)\n    return resultado",
		"ai_wpm": 125,
		"ai_stutter_chance": 0.06,
		"ai_accuracy": 0.92,
		"boss_win": "Depois do dia 10, isso deve ter parecido quase tranquilo. Bom trabalho.",
		"boss_lose": "A ChatBot-6000 é rápida demais. Faltam só alguns dias, não desiste agora."
	},
	{
		"day": 12,
		"title": "Dia 12",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Reta final",
				"body": "Faltam só dois dias. A diretoria já está de olho em quem vai sobrar na equipe. Continue no seu melhor nível."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-6000",
		"code": "func somar_matriz(matriz):\n    var total = 0\n    for linha in matriz:\n        for valor in linha:\n            total += valor\n    return total",
		"ai_wpm": 140,
		"ai_stutter_chance": 0.05,
		"ai_accuracy": 0.93,
		"boss_win": "Você está lutando bem. Amanhã chega a última versão.",
		"boss_lose": "Isso não está bom. Nada bom mesmo."
	},
	{
		"day": 13,
		"title": "Dia 13 - Versão final",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "A última versão chegou",
				"body": "Penúltimo dia. A NeuralCode acabou de lançar a versão que, segundo eles, é a mais avançada da linha até agora. Dá uma olhada no e-mail deles."
			},
			{
				"from": "NeuralCode Inc. <updates@neuralcode.ai>",
				"subject": "Atualização disponível: ChatBot-7000",
				"body": "A ChatBot-7000 é a versão mais avançada da nossa linha de assistentes de código até o momento, com o menor índice de erros já registrado. Atualização aplicada automaticamente ao ambiente da CodeCorp.\n\nEquipe NeuralCode."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-7000",
		"code": "func particionar(lista, baixo, alto):\n    var pivo = lista[alto]\n    var i = baixo - 1\n    for j in range(baixo, alto):\n        if lista[j] <= pivo:\n            i += 1\n            var tmp = lista[i]\n            lista[i] = lista[j]\n            lista[j] = tmp\n    var tmp2 = lista[i + 1]\n    lista[i + 1] = lista[alto]\n    lista[alto] = tmp2\n    return i + 1",
		"ai_wpm": 155,
		"ai_stutter_chance": 0.04,
		"ai_accuracy": 0.94,
		"boss_win": "A versão final da IA e você ainda assim ganhou. Amanhã é o último dia.",
		"boss_lose": "A ChatBot-7000 é o auge do que a NeuralCode conseguiu fazer. Só falta um dia."
	},
	{
		"day": 14,
		"title": "Dia 14 - O Duelo Final",
		"pre_transition": [],
		"emails": [
			{
				"from": "Seu Chefe <chefe@codecorp.com>",
				"subject": "Último dia",
				"body": "Chegamos até aqui. Último dia, contra a versão mais avançada que a NeuralCode já lançou. Prove que um humano ainda tem valor nesta empresa."
			}
		],
		"ai_active": true,
		"ai_version_name": "ChatBot-7000",
		"code": "func intercalar(esquerda, direita):\n    var resultado = []\n    var i = 0\n    var j = 0\n    while i < esquerda.size() and j < direita.size():\n        if esquerda[i] <= direita[j]:\n            resultado.append(esquerda[i])\n            i += 1\n        else:\n            resultado.append(direita[j])\n            j += 1\n    while i < esquerda.size():\n        resultado.append(esquerda[i])\n        i += 1\n    while j < direita.size():\n        resultado.append(direita[j])\n        j += 1\n    return resultado",
		"ai_wpm": 170,
		"ai_stutter_chance": 0.03,
		"ai_accuracy": 0.94,
		"boss_win": "Você... você conseguiu. Parabéns. Você mostrou que raciocínio humano ainda faz diferença aqui. Bem-vindo à equipe, de vez.",
		"boss_lose": "Sinto muito. As regras são as regras."
	},
]


func get_current_config() -> Dictionary:
	return day_configs[current_day - 1]


## Nome da IA concorrente do dia atual, sempre seguro de chamar (mesmo
## depois da campanha terminar, com current_day fora do intervalo válido).
func current_ai_name() -> String:
	var idx: int = clampi(current_day, 1, total_days())
	return day_configs[idx - 1].get("ai_version_name", "ChatBot-1000")


func total_days() -> int:
	return day_configs.size()


# ---------------------------------------------------------------------------
# E-MAILS (uma flag de "lido" por mensagem do dia atual - permite o jogador
# navegar livremente entre elas na caixa de entrada, em vez de forçar uma
# ordem rígida de abrir/ler/fechar uma por vez)
# ---------------------------------------------------------------------------
func _ready() -> void:
	_init_day_email_flags()


func _init_day_email_flags() -> void:
	var count: int = get_current_config()["emails"].size()
	email_read_flags = []
	for i in range(count):
		email_read_flags.append(false)


func is_email_read(index: int) -> bool:
	if index < 0 or index >= email_read_flags.size():
		return true
	return email_read_flags[index]


func mark_email_read(index: int) -> void:
	if index < 0 or index >= email_read_flags.size():
		return
	email_read_flags[index] = true


func has_unread_email() -> bool:
	return email_read_flags.has(false)


func unread_email_count() -> int:
	var n := 0
	for read in email_read_flags:
		if not read:
			n += 1
	return n


func register_win() -> void:
	current_day += 1
	if current_day <= total_days():
		_init_day_email_flags()
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
	_init_day_email_flags()
	state_changed.emit()
