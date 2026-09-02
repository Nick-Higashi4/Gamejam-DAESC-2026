# Code Warrior: Humano vs IA

- Danilo Moreira
- Eduardo Tadra Mainjinski
- Evelyn Carolina Massuline
- Fábio Luiz da Silva Jr
- Nícolas Higashi
- Vitor Inácio Borges

Protótipo jogável feito em **Godot Engine 4.3+** (GDScript). Você é um
programador cuja empresa contratou a IA "CodeBot-3000". Ao longo de 5 dias
de trabalho, você precisa vencer corridas de digitação de código
(estilo TypeRacer) contra a IA. Perca avisos demais e é demitido; vença
os 5 dias e mantém o emprego.

## Como abrir

1. Abra o **Godot Engine 4.3 ou superior**.
2. Clique em "Importar" e selecione a pasta deste projeto (o arquivo
   `project.godot`).
3. Rode a cena principal (`scenes/Main.tscn`) com F5 ou o botão de Play.

Todo o jogo é uma **única cena** (`Main.tscn`) cujo script
(`scripts/Main.gd`) monta a interface inteira em tempo de execução:
a moldura do monitor, o "desktop" estilo Windows XP, os e-mails do chefe
e o "IDE" onde acontece a corrida de digitação. Isso foi feito de
propósito para não depender de nós complexos pré-montados no editor —
tudo é código puro, fácil de ler e de modificar.

## Estrutura

```
project.godot          -> configuração do projeto (autoload, tela, etc.)
scenes/Main.tscn        -> cena raiz (praticamente vazia, só o root com o script)
scripts/GameManager.gd  -> autoload/singleton: estado da campanha (dia atual,
                            avisos/strikes) e os dados de cada um dos 5 dias
                            (código a digitar, velocidade da IA, falas do chefe)
scripts/Main.gd         -> toda a lógica de UI e do puzzle da corrida
```

## Como funciona o puzzle (TypeRacer)

- `race_code` guarda o snippet do dia atual.
- A cada tecla digitada (`_on_race_text_changed`), o jogo calcula o maior
  prefixo do texto digitado que bate exatamente com o código alvo
  (`_longest_correct_prefix`). Esse valor vira o progresso do jogador —
  ou seja, digitar errado **trava** o progresso até você corrigir, igual
  a um TypeRacer de verdade.
- A IA avança sozinha em `_update_ai_progress`, com uma velocidade em
  "palavras por minuto" (convertida para caracteres/segundo) definida por
  dia em `GameManager.day_configs`. Ela também tem uma pequena chance de
  "hesitar" por um instante (`ai_stutter_chance`), pra não parecer um
  robô perfeito o tempo todo.
- Quem chegar a 100% primeiro vence a rodada.

## Dificuldade por dia

| Dia | Tamanho do código | Velocidade da IA (wpm) |
|-----|--------------------|--------------------------|
| 1   | curto (~70 car.)   | 25 |
| 2   | médio (~150 car.)  | 35 |
| 3   | médio-longo        | 50 |
| 4   | longo              | 65 |
| 5   | muito longo        | 85 |

Tudo isso é só dados em `GameManager.gd` — é fácil adicionar mais dias,
mudar os códigos ou ajustar a curva de dificuldade sem tocar em `Main.gd`.

## Sugestões de próximos passos (não implementado aqui)

- **Fontes monoespaçadas de verdade**: coloque um `.ttf` monoespaçado
  (ex.: JetBrains Mono, Fira Code) em `assets/fonts/` e aplique via
  `add_theme_font_override` no `race_target_label` e no `race_input` em
  `Main.gd`, para o código ficar visualmente mais parecido com um editor.
- **Sons**: efeito de tecla ao digitar, som de vitória/derrota, música de
  fundo (usando `AudioStreamPlayer`).
- **Câmera 3D em primeira pessoa** olhando para um monitor dentro de uma
  cena 3D (mesa, cadeira, escritório) em vez do monitor 2D em tela cheia —
  bastaria colocar esse `Control` como uma `SubViewport` aplicada como
  textura numa tela 3D (`MeshInstance3D` com um `ViewportTexture`).
- **Ranking de WPM do jogador** ao final de cada dia, salvo com
  `FileAccess`/`ConfigFile` para comparar tentativas.
- **Mais variação na IA**: erros de digitação simulados que ela precisa
  "corrigir" (recuando o progresso), deixando-a menos perfeita.
