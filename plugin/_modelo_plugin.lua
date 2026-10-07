--[[
  YashScript V8.0 — Plugin do Roblox Studio (editor avançado + compilador Luau direto)

  NOVAS FUNCIONALIDADES DO EDITOR:
  - Auto-par de brackets: () [] {} "" ''
  - Syntax highlighting (RichText) por tipo: eventos, comandos, variáveis, etc.
  - Autocomplete/IntelliSense com dicionário completo da linguagem (painel informativo, sem aceitar texto)
  - Editor padrão: Tab insere tab, Enter quebra linha, setas livres (sem capturas de tecla)
  - Estado "sujo" por script (* no nome) persiste na memória ao trocar de script
  - Scroll horizontal automático quando linha passa da tela
  - Dicionário contextual (hover mostra documentação)

  FLUXO
    1) Escolha um Script / LocalScript / ModuleScript (lista ou 'Selecionado').
    2) O plugin lê a fonte YashScript do atributo "YashScript" do script.
    3) Edite no painel avançado e clique "Gravar".
    4) O plugin faz Compilar -> GerarLuau e escreve o LUAU PURO no Source.

  O Source gerado (V8.0):
    - `_YashConfig` e o literal de config
    - `Runtime.executar` / `Runtime.montarMundo`
    - os marcadores `--YASHC1--` / `--YASHC2--`
    - qualquer trecho YashScript

  O Source é Luau comum: dá para abrir, ler, editar e versionar no Studio.
  A fonte YashScript fica separada, no atributo "YashScript" do próprio script.

  CONTEXTO: vem da CLASSE do alvo, nunca do texto.
    Script       -> servidor
    LocalScript  -> cliente   (StarterGui vira PlayerGui; resolve pelo ancestral
                               quando o script já vive dentro de um ScreenGui)
    ModuleScript -> comum, e o módulo retorna uma tabela

  Compilador e Gerador moram DENTRO do plugin (fonte embutida). O lugar não
  precisa de nenhum ModuleScript: o script gerado é Luau puro e roda sozinho.
]]

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")

local FONTES = {
	Compilador = HttpService:JSONDecode(@@COMPILADOR@@),
	Gerador = HttpService:JSONDecode(@@GERADOR@@),
}

-- ------------------------------------------------------------------
-- DICIONÁRIO COMPLETO DA LINGUAGEM YASHSCRIPT V8.0
-- ------------------------------------------------------------------

local YASH_DICTIONARY = {
	-- Eventos
	["quando"] = { tipo = "evento", desc = "Inicia um manipulador de evento", sintaxe = "quando <evento> <alvo>\n    <comandos>\nfim" },
	["clicar"] = { tipo = "evento", desc = "Dispara quando clicam no objeto", sintaxe = "quando clicar \"Botao\"" },
	["mouse_em"] = { tipo = "evento", desc = "Mouse entrou no objeto", sintaxe = "quando mouse_em \"Botao\"" },
	["mouse_sair"] = { tipo = "evento", desc = "Mouse saiu do objeto", sintaxe = "quando mouse_sair \"Botao\"" },
	["tocar"] = { tipo = "evento", desc = "Personagem encostou no objeto", sintaxe = "quando jogador tocar \"Moeda\"" },
	["encostar"] = { tipo = "evento", desc = "Sinônimo de tocar", sintaxe = "quando encostar \"Objeto\"" },
	["apertar"] = { tipo = "evento", desc = "Tecla pressionada", sintaxe = "quando apertar \"W\"" },
	["solte"] = { tipo = "evento", desc = "Tecla solta", sintaxe = "quando solte \"W\"" },
	["iniciar"] = { tipo = "evento", desc = "Script iniciado", sintaxe = "quando iniciar" },
	["carregar"] = { tipo = "evento", desc = "Jogo carregado", sintaxe = "quando carregar" },
	["a cada"] = { tipo = "evento", desc = "Timer repetido", sintaxe = "a cada 1\n    print(\"tick\")\nfim" },

	-- Comandos de fluxo
	["se"] = { tipo = "comando", desc = "Condicional", sintaxe = "se condicao\n    comandos\nfim" },
	["senao"] = { tipo = "comando", desc = "Senão", sintaxe = "se condicao\n    ...\nsenao\n    ...\nfim" },
	["senao se"] = { tipo = "comando", desc = "Senão se", sintaxe = "se a\n    ...\nsenao se b\n    ...\nfim" },
	["enquanto"] = { tipo = "comando", desc = "Loop enquanto", sintaxe = "enquanto condicao\n    comandos\nfim" },
	["repita"] = { tipo = "comando", desc = "Loop repita até", sintaxe = "repita\n    comandos\nate condicao" },
	["para"] = { tipo = "comando", desc = "Loop para cada", sintaxe = "para cada item em lista\n    comandos\nfim" },
	["cada"] = { tipo = "comando", desc = "Parte do para cada", sintaxe = "para cada x em t" },
	["em"] = { tipo = "comando", desc = "Parte do para cada", sintaxe = "para cada x em t" },
	["fim"] = { tipo = "comando", desc = "Fecha bloco", sintaxe = "fim" },
	["pare"] = { tipo = "comando", desc = "Break do loop", sintaxe = "pare" },
	["continuar"] = { tipo = "comando", desc = "Continue do loop", sintaxe = "continuar" },
	["retornar"] = { tipo = "comando", desc = "Return da função", sintaxe = "retornar valor" },
	["return"] = { tipo = "comando", desc = "Return da função (inglês)", sintaxe = "return valor" },

	-- Criação de objetos
	["criar"] = { tipo = "comando", desc = "Cria objeto/estilo/ação/animação", sintaxe = "criar bloco \"Nome\"\n    propriedades\nfim" },
	["bloco"] = { tipo = "objeto", desc = "Cria Part", sintaxe = "criar bloco \"Nome\"" },
	["esfera"] = { tipo = "objeto", desc = "Cria Sphere", sintaxe = "criar esfera \"Nome\"" },
	["cilindro"] = { tipo = "objeto", desc = "Cria Cylinder", sintaxe = "criar cilindro \"Nome\"" },
	["cunha"] = { tipo = "objeto", desc = "Cria Wedge", sintaxe = "criar cunha \"Nome\"" },
	["paralelepipedo"] = { tipo = "objeto", desc = "Cria Block", sintaxe = "criar paralelepipedo \"Nome\"" },
	["plataforma"] = { tipo = "objeto", desc = "Cria plataforma", sintaxe = "criar plataforma \"Nome\"" },
	["painel"] = { tipo = "objeto", desc = "Cria Frame", sintaxe = "criar painel \"Nome\"" },
	["texto"] = { tipo = "objeto", desc = "Cria TextLabel", sintaxe = "criar texto \"Nome\"" },
	["botao"] = { tipo = "objeto", desc = "Cria TextButton", sintaxe = "criar botao \"Nome\"" },
	["campo"] = { tipo = "objeto", desc = "Cria TextBox", sintaxe = "criar campo \"Nome\"" },
	["imagem"] = { tipo = "objeto", desc = "Cria ImageLabel", sintaxe = "criar imagem \"Nome\"" },
	["elemento"] = { tipo = "objeto", desc = "Cria Frame genérico", sintaxe = "criar elemento \"Nome\"" },
	["cena"] = { tipo = "objeto", desc = "Cria Scene", sintaxe = "criar cena \"Nome\"" },
	["estilo"] = { tipo = "objeto", desc = "Cria Style", sintaxe = "criar estilo \"Nome\"\n    propriedades\nfim" },
	["animacao"] = { tipo = "objeto", desc = "Cria Animation", sintaxe = "criar animacao 'nome'\n    animacao = fade out + duracao = 1\nfim" },
	["acao"] = { tipo = "objeto", desc = "Cria Action", sintaxe = "criar acao 'nome'\n    propriedades\nfim" },

	-- Animações
	["animar"] = { tipo = "comando", desc = "Executa animação no objeto", sintaxe = "animar(\"Objeto\") crescer + escala = 1.5 + duracao = 0.3" },
	["crescer"] = { tipo = "animacao", desc = "Escala para cima", sintaxe = "animar(\"Obj\") crescer + escala = 2" },
	["diminuir"] = { tipo = "animacao", desc = "Escala para baixo", sintaxe = "animar(\"Obj\") diminuir + escala = 0.5" },
	["fade out"] = { tipo = "animacao", desc = "Fade out", sintaxe = "animacao = fade out + duracao = 1" },
	["fade in"] = { tipo = "animacao", desc = "Fade in", sintaxe = "animacao = fade in + duracao = 1" },
	["executar animacao"] = { tipo = "comando", desc = "Executa animação criada", sintaxe = "executar animacao 'nome'" },

	-- Variáveis e dados
	["variavel"] = { tipo = "comando", desc = "Declara variável", sintaxe = "variavel Nome = valor" },
	["var"] = { tipo = "comando", desc = "Declara variável (curto)", sintaxe = "var Nome = valor" },
	["let"] = { tipo = "comando", desc = "Declara variável (JS style)", sintaxe = "let Nome = valor" },
	["usar"] = { tipo = "comando", desc = "Aponta para instância existente", sintaxe = "usar \"Nome\" = Caminho" },
	["tabela"] = { tipo = "comando", desc = "Cria tabela", sintaxe = "variavel T = {}\nT.chave = valor" },
	["lista"] = { tipo = "comando", desc = "Cria lista", sintaxe = "variavel L = {1, 2, 3}" },

	-- Funções
	["criar funcao"] = { tipo = "comando", desc = "Define função", sintaxe = "criar funcao Nome(param)\n    comandos\n    retornar valor\nfim" },
	["funcao"] = { tipo = "comando", desc = "Define função", sintaxe = "criar funcao Nome()\n    ...\nfim" },
	["função"] = { tipo = "comando", desc = "Define função (com acento)", sintaxe = "criar função Nome()\n    ...\nfim" },

	-- Operadores
	["e"] = { tipo = "operador", desc = "AND lógico", sintaxe = "se a e b" },
	["and"] = { tipo = "operador", desc = "AND lógico", sintaxe = "se a and b" },
	["ou"] = { tipo = "operador", desc = "OR lógico", sintaxe = "se a ou b" },
	["or"] = { tipo = "operador", desc = "OR lógico", sintaxe = "se a or b" },
	["não"] = { tipo = "operador", desc = "NOT lógico", sintaxe = "se não a" },
	["nao"] = { tipo = "operador", desc = "NOT lógico", sintaxe = "se nao a" },
	["not"] = { tipo = "operador", desc = "NOT lógico", sintaxe = "se not a" },
	["então"] = { tipo = "operador", desc = "Then (opcional)", sintaxe = "se a então" },
	["entao"] = { tipo = "operador", desc = "Then (opcional)", sintaxe = "se a entao" },

	-- Comparadores
	["<"] = { tipo = "operador", desc = "Menor que", sintaxe = "a < b" },
	[">"] = { tipo = "operador", desc = "Maior que", sintaxe = "a > b" },
	["<="] = { tipo = "operador", desc = "Menor ou igual", sintaxe = "a <= b" },
	[">="] = { tipo = "operador", desc = "Maior ou igual", sintaxe = "a >= b" },
	["="] = { tipo = "operador", desc = "Igual/Atribuição", sintaxe = "a = b" },
	["=="] = { tipo = "operador", desc = "Igualdade", sintaxe = "a == b" },
	["!="] = { tipo = "operador", desc = "Diferente", sintaxe = "a != b" },
	["~="] = { tipo = "operador", desc = "Diferente (Luau)", sintaxe = "a ~= b" },

	-- Matemáticos
	["+"] = { tipo = "operador", desc = "Soma", sintaxe = "a + b" },
	["-"] = { tipo = "operador", desc = "Subtração", sintaxe = "a - b" },
	["*"] = { tipo = "operador", desc = "Multiplicação", sintaxe = "a * b" },
	["/"] = { tipo = "operador", desc = "Divisão", sintaxe = "a / b" },
	["//"] = { tipo = "operador", desc = "Divisão inteira", sintaxe = "a // b" },
	["%"] = { tipo = "operador", desc = "Módulo", sintaxe = "a % b" },
	["^"] = { tipo = "operador", desc = "Potência", sintaxe = "a ^ b" },
	[".."] = { tipo = "operador", desc = "Concatenação", sintaxe = "\"a\" .. \"b\"" },
	["+="] = { tipo = "operador", desc = "Soma e atribui", sintaxe = "a += 1" },
	["-="] = { tipo = "operador", desc = "Subtrai e atribui", sintaxe = "a -= 1" },

	-- Propriedades comuns
	["ancorado"] = { tipo = "propriedade", desc = "Anchored", sintaxe = "ancorado = verdadeiro" },
	["anchored"] = { tipo = "propriedade", desc = "Anchored", sintaxe = "anchored = true" },
	["colisao"] = { tipo = "propriedade", desc = "CanCollide", sintaxe = "colisao = falso" },
	["cancollide"] = { tipo = "propriedade", desc = "CanCollide", sintaxe = "cancollide = false" },
	["transparencia"] = { tipo = "propriedade", desc = "Transparency", sintaxe = "transparencia = 0.5" },
	["transparency"] = { tipo = "propriedade", desc = "Transparency", sintaxe = "transparency = 0.5" },
	["cor"] = { tipo = "propriedade", desc = "Color3", sintaxe = "cor = rgb(255, 0, 0)" },
	["color"] = { tipo = "propriedade", desc = "Color3", sintaxe = "color = rgb(255, 0, 0)" },
	["cor_fundo"] = { tipo = "propriedade", desc = "BackgroundColor3", sintaxe = "cor_fundo = rgb(0, 0, 0)" },
	["backgroundcolor3"] = { tipo = "propriedade", desc = "BackgroundColor3", sintaxe = "backgroundcolor3 = rgb(0,0,0)" },
	["cor_texto"] = { tipo = "propriedade", desc = "TextColor3", sintaxe = "cor_texto = branco" },
	["textcolor3"] = { tipo = "propriedade", desc = "TextColor3", sintaxe = "textcolor3 = white" },
	["cor_borda"] = { tipo = "propriedade", desc = "BorderColor3", sintaxe = "cor_borda = preto" },
	["bordacolor3"] = { tipo = "propriedade", desc = "BorderColor3", sintaxe = "bordacolor3 = black" },
	["borda"] = { tipo = "propriedade", desc = "BorderSizePixel", sintaxe = "borda = 2" },
	["bordersizepixel"] = { tipo = "propriedade", desc = "BorderSizePixel", sintaxe = "bordersizepixel = 2" },
	["tamanho_fonte"] = { tipo = "propriedade", desc = "TextSize", sintaxe = "tamanho_fonte = 14" },
	["textsize"] = { tipo = "propriedade", desc = "TextSize", sintaxe = "textsize = 14" },
	["fonte"] = { tipo = "propriedade", desc = "Font", sintaxe = "fonte = \"Gotham\"" },
	["font"] = { tipo = "propriedade", desc = "Font", sintaxe = "font = \"Gotham\"" },
	["texto"] = { tipo = "propriedade", desc = "Text", sintaxe = "texto = \"Olá\"" },
	["text"] = { tipo = "propriedade", desc = "Text", sintaxe = "text = \"Olá\"" },
	["visivel"] = { tipo = "propriedade", desc = "Visible", sintaxe = "visivel = verdadeiro" },
	["visible"] = { tipo = "propriedade", desc = "Visible", sintaxe = "visible = true" },
	["ativo"] = { tipo = "propriedade", desc = "Active", sintaxe = "ativo = verdadeiro" },
	["active"] = { tipo = "propriedade", desc = "Active", sintaxe = "active = true" },
	["selecionavel"] = { tipo = "propriedade", desc = "Selectable", sintaxe = "selecionavel = verdadeiro" },
	["selectable"] = { tipo = "propriedade", desc = "Selectable", sintaxe = "selectable = true" },
	["modal"] = { tipo = "propriedade", desc = "Modal (só botões)", sintaxe = "botao.modal = verdadeiro" },
	["largura"] = { tipo = "propriedade", desc = "Size.X (só elementos criados)", sintaxe = "largura = 200" },
	["altura"] = { tipo = "propriedade", desc = "Size.Y (só elementos criados)", sintaxe = "altura = 100" },
	["arredondamento"] = { tipo = "propriedade", desc = "CornerRadius", sintaxe = "arredondamento = 8" },
	["posicao"] = { tipo = "propriedade", desc = "Position", sintaxe = "posicao = udim2(0, 0, 0, 0)" },
	["position"] = { tipo = "propriedade", desc = "Position", sintaxe = "position = udim2(0, 0, 0, 0)" },
	["tamanho"] = { tipo = "propriedade", desc = "Size", sintaxe = "tamanho = udim2(1, 0, 1, 0)" },
	["size"] = { tipo = "propriedade", desc = "Size", sintaxe = "size = udim2(1, 0, 1, 0)" },
	["rotacao"] = { tipo = "propriedade", desc = "Rotation", sintaxe = "rotacao = 45" },
	["rotation"] = { tipo = "propriedade", desc = "Rotation", sintaxe = "rotation = 45" },
	["layout_order"] = { tipo = "propriedade", desc = "LayoutOrder", sintaxe = "layout_order = 1" },
	["layoutorder"] = { tipo = "propriedade", desc = "LayoutOrder", sintaxe = "layoutorder = 1" },
	["z_index"] = { tipo = "propriedade", desc = "ZIndex", sintaxe = "z_index = 10" },
	["zindex"] = { tipo = "propriedade", desc = "ZIndex", sintaxe = "zindex = 10" },

	-- Câmera
	["camera"] = { tipo = "objeto", desc = "Workspace.CurrentCamera", sintaxe = "camera.CameraType = \"Scriptable\"" },
	["cameratype"] = { tipo = "propriedade", desc = "CameraType", sintaxe = "camera.CameraType = \"Scriptable\"" },
	["cframe"] = { tipo = "propriedade", desc = "CFrame", sintaxe = "camera.CFrame = parte.CFrame" },

	-- Valores booleanos
	["verdadeiro"] = { tipo = "valor", desc = "True", sintaxe = "ativo = verdadeiro" },
	["true"] = { tipo = "valor", desc = "True", sintaxe = "ativo = true" },
	["falso"] = { tipo = "valor", desc = "False", sintaxe = "ativo = falso" },
	["false"] = { tipo = "valor", desc = "False", sintaxe = "ativo = false" },

	-- Cores nomeadas (só 4 funcionam no gerador V8)
	["preto"] = { tipo = "cor", desc = "Preto (funciona)", sintaxe = "cor = preto" },
	["black"] = { tipo = "cor", desc = "Preto (funciona)", sintaxe = "cor = black" },
	["branco"] = { tipo = "cor", desc = "Branco (funciona)", sintaxe = "cor = branco" },
	["white"] = { tipo = "cor", desc = "Branco (funciona)", sintaxe = "cor = white" },

	-- Site (UI)
	["site"] = { tipo = "comando", desc = "Configura ScreenGui", sintaxe = "site { fundo = rgb(0,0,0) }" },
	["fundo"] = { tipo = "propriedade", desc = "Background do site", sintaxe = "site { fundo = rgb(0,0,0) }" },

	-- Jogador (sujeito lógico de tocar)
	["jogador"] = { tipo = "palavra-chave", desc = "Sujeito de 'quando jogador tocar'", sintaxe = "quando jogador tocar Objeto" },
	["player"] = { tipo = "palavra-chave", desc = "Sinônimo de jogador", sintaxe = "quando player tocar Objeto" },

	-- Métodos
	["print"] = { tipo = "funcao", desc = "Imprime no console", sintaxe = "print(\"texto\")" },
	["destruir"] = { tipo = "funcao", desc = "Destrói objeto", sintaxe = "destruir objeto \"Nome\"" },
	["destruir objeto"] = { tipo = "funcao", desc = "Destrói objeto", sintaxe = "destruir objeto \"Nome\"" },
	["tocar som"] = { tipo = "funcao", desc = "Toca som", sintaxe = "tocar som \"SomId\"" },
	["esperar"] = { tipo = "funcao", desc = "Espera segundos", sintaxe = "esperar 1" },
	["wait"] = { tipo = "funcao", desc = "Espera segundos", sintaxe = "wait 1" },
	["aguardar"] = { tipo = "funcao", desc = "Pausa a execução (sinônimo de esperar)", sintaxe = "aguardar 0.5" },
	["devolver"] = { tipo = "comando", desc = "Encerra a função e devolve valor", sintaxe = "devolver expressão" },

	-- Interface: mostrar/esconder/alternar/mudar
	["mostrar"] = { tipo = "comando", desc = "Mostra um elemento ou cena", sintaxe = "mostrar Elemento" },
	["esconder"] = { tipo = "comando", desc = "Esconde um elemento ou cena", sintaxe = "esconder Elemento" },
	["alternar"] = { tipo = "comando", desc = "Alterna a visibilidade", sintaxe = "alternar(Elemento)" },
	["mudar"] = { tipo = "comando", desc = "Troca para uma cena", sintaxe = "mudar cena Nome" },
	["mostrar texto"] = { tipo = "comando", desc = "Mostra uma mensagem simples", sintaxe = "mostrar texto \"mensagem\"" },

	-- Mundo / HUD
	["mundo"] = { tipo = "comando", desc = "Configura iluminação/ambiente", sintaxe = "mundo\n    propriedade = valor\nfim" },
	["hud"] = { tipo = "objeto", desc = "Cria uma exibição ligada a dados", sintaxe = "criar hud \"Nome\"\n    mostrar objeto.campo\nfim" },

	-- Comandos de dados/jogo
	["somar"] = { tipo = "comando", desc = "Soma valor de uma referência em outra", sintaxe = "somar Origem a Destino" },
	["subtrair"] = { tipo = "comando", desc = "Subtrai valor de uma referência de outra", sintaxe = "subtrair Origem de Destino" },
	["causar dano"] = { tipo = "comando", desc = "Aplica dano ao alvo", sintaxe = "causar dano Alvo N" },
	["curar"] = { tipo = "comando", desc = "Restaura vida do alvo", sintaxe = "curar Alvo N" },
	["matar"] = { tipo = "comando", desc = "Zera a vida do alvo", sintaxe = "matar Alvo" },
	["respawnar"] = { tipo = "comando", desc = "Ressuscita o personagem", sintaxe = "respawnar Jogador" },
	["teleportar"] = { tipo = "comando", desc = "Move para posição 3D", sintaxe = "teleportar Alvo (x, y, z)" },
	["mover"] = { tipo = "comando", desc = "Move um objeto", sintaxe = "mover Alvo para (x, y, z) velocidade N" },
	["rotacionar"] = { tipo = "comando", desc = "Anima a rotação", sintaxe = "rotacionar Alvo para (x, y, z) duracao N" },
	["sortear"] = { tipo = "comando", desc = "Cria variável aleatória", sintaxe = "sortear Nome entre mínimo e máximo" },
	["explodir"] = { tipo = "comando", desc = "Cria explosão no alvo", sintaxe = "explodir Alvo raio N dano N" },
	["seguir"] = { tipo = "comando", desc = "Faz um alvo seguir outro", sintaxe = "seguir Quem o Alvo" },
	["clonar"] = { tipo = "comando", desc = "Clona/coloca cópia no destino", sintaxe = "clonar Origem para Destino como Nome" },
	["proibir"] = { tipo = "comando", desc = "Bloqueia comandos de um evento", sintaxe = "proibir evento Botao de comandos se visivel(\"Alvo\")" },
	["remover"] = { tipo = "comando", desc = "Destrói objeto/elemento (sinônimo de destruir)", sintaxe = "remover objeto Alvo" },
	["executar"] = { tipo = "comando", desc = "Executa ação ou animação", sintaxe = "executar acao Nome" },
	["chamar"] = { tipo = "comando", desc = "Chama ação ou animação", sintaxe = "chamar animacao Nome" },

	-- Condições
	["distancia"] = { tipo = "condicao", desc = "Compara distância entre objetos", sintaxe = "se distancia A de B menor que N" },
	["perto"] = { tipo = "condicao", desc = "Verifica proximidade", sintaxe = "se distancia A de B menor que 10" },
	["longe"] = { tipo = "condicao", desc = "Verifica distância", sintaxe = "se distancia A de B maior que 10" },
	["menor"] = { tipo = "condicao", desc = "Menor para distância", sintaxe = "distancia A de B menor que N" },
	["maior"] = { tipo = "condicao", desc = "Maior para distância", sintaxe = "distancia A de B maior que N" },
	["que"] = { tipo = "condicao", desc = "Ligação de condição (menor que / maior que)", sintaxe = "se Vida menor que 10" },
	["vivo"] = { tipo = "condicao", desc = "Testa se o alvo tem vida", sintaxe = "se Alvo vivo" },
	["morto"] = { tipo = "condicao", desc = "Testa se o alvo morreu", sintaxe = "se Alvo morto" },
	["oculto"] = { tipo = "condicao", desc = "Testa se o elemento está oculto", sintaxe = "se visivel(\"X\")" },
	["teclado"] = { tipo = "condicao", desc = "Testa tecla pressionada", sintaxe = "se teclado apertar E" },
	["criado"] = { tipo = "condicao", desc = "Verifica resultado de criação", sintaxe = "se \"Nome\" criado com sucesso" },
	["sucesso"] = { tipo = "condicao", desc = "Parte de 'criado com sucesso'", sintaxe = "se \"Nome\" criado com sucesso" },

	-- Valores
	["sim"] = { tipo = "valor", desc = "True (sinônimo)", sintaxe = "ativo = sim" },
	["nulo"] = { tipo = "valor", desc = "Nil", sintaxe = "variavel X = nulo" },
	["rgb"] = { tipo = "valor", desc = "Cria cor RGB", sintaxe = "cor = rgb(255, 0, 0)" },
	["tupla"] = { tipo = "valor", desc = "Grupo (x, y) ou (x, y, z)", sintaxe = "posicao = (0, 5, 0)" },
	["ipairs"] = { tipo = "iterador", desc = "Percorre lista", sintaxe = "para cada item em Lista" },
	["pairs"] = { tipo = "iterador", desc = "Percorre mapa", sintaxe = "para cada chave, valor em Mapa" },

	-- Laços
	["de"] = { tipo = "laço", desc = "Intervalo do 'para'", sintaxe = "para i de 1 ate 10" },
	["ate"] = { tipo = "laço", desc = "Limite do 'para'/'repita'", sintaxe = "para i de 1 ate 10" },
	["passo"] = { tipo = "laço", desc = "Incremento do 'para'", sintaxe = "para i de 1 ate 10 passo 2" },

	-- Animações: parâmetros
	["duracao"] = { tipo = "animacao", desc = "Tempo da animação em segundos", sintaxe = "animar(\"X\") fade out + duracao = 0.5" },
	["delta"] = { tipo = "animacao", desc = "Distância do deslizamento", sintaxe = "slide left + delta = 100" },
	["escala"] = { tipo = "animacao", desc = "Escala do efeito", sintaxe = "crescer + escala = 1.5" },
	["graus"] = { tipo = "animacao", desc = "Ângulo de giro", sintaxe = "girar + graus = 8" },
	["direcao"] = { tipo = "animacao", desc = "Direção da curva", sintaxe = "direcao = entrada" },

	-- Animações: efeitos
	["aparecer"] = { tipo = "animacao", desc = "Fade in (sinônimo)", sintaxe = "animar(\"X\") aparecer + duracao = 0.5" },
	["desaparecer"] = { tipo = "animacao", desc = "Fade out (sinônimo)", sintaxe = "animar(\"X\") desaparecer + duracao = 0.5" },
	["sumir"] = { tipo = "animacao", desc = "Fade out (sinônimo)", sintaxe = "animar(\"X\") sumir + duracao = 0.5" },
	["pulsar"] = { tipo = "animacao", desc = "Pulsa a escala", sintaxe = "pulsar + escala = 1.1" },
	["pulse"] = { tipo = "animacao", desc = "Pulsa (inglês)", sintaxe = "pulse" },
	["girar"] = { tipo = "animacao", desc = "Gira o alvo", sintaxe = "girar + graus = 8" },
	["spin"] = { tipo = "animacao", desc = "Gira (inglês)", sintaxe = "spin + graus = 8" },
	["aumentar"] = { tipo = "animacao", desc = "Crescer (sinônimo)", sintaxe = "aumentar + escala = 2" },
	["encolher"] = { tipo = "animacao", desc = "Diminuir (sinônimo)", sintaxe = "encolher + escala = 0.5" },
	["slide left"] = { tipo = "animacao", desc = "Desliza para a esquerda", sintaxe = "slide left + delta = 100" },
	["esquerda"] = { tipo = "animacao", desc = "Slide left (sinônimo)", sintaxe = "esquerda + delta = 100" },
	["slide esquerda"] = { tipo = "animacao", desc = "Slide left (sinônimo)", sintaxe = "slide esquerda + delta = 100" },
	["slide right"] = { tipo = "animacao", desc = "Desliza para a direita", sintaxe = "slide right + delta = 100" },
	["direita"] = { tipo = "animacao", desc = "Slide right (sinônimo)", sintaxe = "direita + delta = 100" },
	["slide direita"] = { tipo = "animacao", desc = "Slide right (sinônimo)", sintaxe = "slide direita + delta = 100" },
	["slide up"] = { tipo = "animacao", desc = "Desliza para cima", sintaxe = "slide up + delta = 100" },
	["subir"] = { tipo = "animacao", desc = "Slide up (sinônimo)", sintaxe = "subir + delta = 100" },
	["cima"] = { tipo = "animacao", desc = "Slide up (sinônimo)", sintaxe = "cima + delta = 100" },
	["slide cima"] = { tipo = "animacao", desc = "Slide up (sinônimo)", sintaxe = "slide cima + delta = 100" },
	["slide down"] = { tipo = "animacao", desc = "Desliza para baixo", sintaxe = "slide down + delta = 100" },
	["descer"] = { tipo = "animacao", desc = "Slide down (sinônimo)", sintaxe = "descer + delta = 100" },
	["baixo"] = { tipo = "animacao", desc = "Slide down (sinônimo)", sintaxe = "baixo + delta = 100" },
	["slide baixo"] = { tipo = "animacao", desc = "Slide down (sinônimo)", sintaxe = "slide baixo + delta = 100" },

	-- Animações: easing
	["linear"] = { tipo = "animacao", desc = "Easing linear", sintaxe = "estilo = linear" },
	["suave"] = { tipo = "animacao", desc = "Easing sine", sintaxe = "estilo = suave" },
	["sine"] = { tipo = "animacao", desc = "Easing sine (inglês)", sintaxe = "estilo = sine" },
	["senoidal"] = { tipo = "animacao", desc = "Easing sine (sinônimo)", sintaxe = "estilo = senoidal" },
	["quad"] = { tipo = "animacao", desc = "Easing quad", sintaxe = "estilo = quad" },
	["quadratico"] = { tipo = "animacao", desc = "Easing quad (sinônimo)", sintaxe = "estilo = quadratico" },
	["cubico"] = { tipo = "animacao", desc = "Easing cubic", sintaxe = "estilo = cubico" },
	["cubic"] = { tipo = "animacao", desc = "Easing cubic (inglês)", sintaxe = "estilo = cubic" },
	["quart"] = { tipo = "animacao", desc = "Easing quart", sintaxe = "estilo = quart" },
	["quartico"] = { tipo = "animacao", desc = "Easing quart (sinônimo)", sintaxe = "estilo = quartico" },
	["quint"] = { tipo = "animacao", desc = "Easing quint", sintaxe = "estilo = quint" },
	["quintico"] = { tipo = "animacao", desc = "Easing quint (sinônimo)", sintaxe = "estilo = quintico" },
	["exponencial"] = { tipo = "animacao", desc = "Easing exponential", sintaxe = "estilo = exponencial" },
	["expo"] = { tipo = "animacao", desc = "Easing exponential (curto)", sintaxe = "estilo = expo" },
	["circular"] = { tipo = "animacao", desc = "Easing circular", sintaxe = "estilo = circular" },
	["circ"] = { tipo = "animacao", desc = "Easing circular (curto)", sintaxe = "estilo = circ" },
	["elastico"] = { tipo = "animacao", desc = "Easing elastic", sintaxe = "estilo = elastico" },
	["elastic"] = { tipo = "animacao", desc = "Easing elastic (inglês)", sintaxe = "estilo = elastic" },
	["ressalto"] = { tipo = "animacao", desc = "Easing bounce", sintaxe = "estilo = ressalto" },
	["bounce"] = { tipo = "animacao", desc = "Easing bounce (inglês)", sintaxe = "estilo = bounce" },
	["voltar"] = { tipo = "animacao", desc = "Easing back", sintaxe = "estilo = voltar" },
	["back"] = { tipo = "animacao", desc = "Easing back (inglês)", sintaxe = "estilo = back" },
	["entrada"] = { tipo = "animacao", desc = "Direção In", sintaxe = "direcao = entrada" },
	["saida"] = { tipo = "animacao", desc = "Direção Out", sintaxe = "direcao = saida" },
	["entrada_saida"] = { tipo = "animacao", desc = "Direção InOut", sintaxe = "direcao = entrada_saida" },
	["inout"] = { tipo = "animacao", desc = "Direção InOut (inglês)", sintaxe = "direcao = inout" },

	-- Propriedades (tradução V8 do gerador)
	["vida"] = { tipo = "propriedade", desc = "Health", sintaxe = "vida = 100" },
	["health"] = { tipo = "propriedade", desc = "Health", sintaxe = "health = 100" },
	["vida_maxima"] = { tipo = "propriedade", desc = "MaxHealth", sintaxe = "vida_maxima = 100" },
	["max_vida"] = { tipo = "propriedade", desc = "MaxHealth", sintaxe = "max_vida = 100" },
	["maxhealth"] = { tipo = "propriedade", desc = "MaxHealth", sintaxe = "maxhealth = 100" },
	["velocidade"] = { tipo = "propriedade", desc = "WalkSpeed", sintaxe = "velocidade = 16" },
	["walkspeed"] = { tipo = "propriedade", desc = "WalkSpeed", sintaxe = "walkspeed = 16" },
	["jumppower"] = { tipo = "propriedade", desc = "JumpPower", sintaxe = "jumppower = 50" },
	["enabled"] = { tipo = "propriedade", desc = "Enabled", sintaxe = "enabled = verdadeiro" },
	["transparente"] = { tipo = "propriedade", desc = "Transparency", sintaxe = "transparente = verdadeiro" },
	["material"] = { tipo = "propriedade", desc = "Material", sintaxe = "material = \"Neon\"" },
	["posicao_3d"] = { tipo = "propriedade", desc = "Position (3D)", sintaxe = "posicao_3d = (0, 0, 0)" },
	["cor_3d"] = { tipo = "propriedade", desc = "Color (3D)", sintaxe = "cor_3d = rgb(0,0,0)" },
	["placeholder"] = { tipo = "propriedade", desc = "PlaceholderText", sintaxe = "placeholder = \"Digite...\"" },
	["auto"] = { tipo = "propriedade", desc = "AutoButtonColor", sintaxe = "auto = verdadeiro" },
	["layout"] = { tipo = "propriedade", desc = "LayoutOrder (curto)", sintaxe = "layout = 1" },
	["anchor_point"] = { tipo = "propriedade", desc = "AnchorPoint", sintaxe = "anchor_point = (0.5, 0.5)" },
	["grupo"] = { tipo = "propriedade", desc = "GroupColor3", sintaxe = "grupo = rgb(255,255,255)" },
	["estado"] = { tipo = "propriedade", desc = "State", sintaxe = "estado = 0" },
	["exclusivo"] = { tipo = "propriedade", desc = "Exclusive", sintaxe = "exclusivo = verdadeiro" },
	["encerrado"] = { tipo = "propriedade", desc = "CloseOnEscape", sintaxe = "encerrado = verdadeiro" },
	["distancia_lateral"] = { tipo = "propriedade", desc = "AbsolutePosition", sintaxe = "distancia_lateral = (0, 0)" },
	["tamanho_absoluto"] = { tipo = "propriedade", desc = "AbsoluteSize", sintaxe = "tamanho_absoluto = (100, 50)" },
	["name"] = { tipo = "propriedade", desc = "Name", sintaxe = "name = \"Nome\"" },
	["parent"] = { tipo = "propriedade", desc = "Parent", sintaxe = "parent = workspace" },

	-- Estrutura
	["incluir"] = { tipo = "comando", desc = "Inclui outro arquivo YashScript", sintaxe = "incluir \"arquivo.yash\"" },
	["YASHSCRIPT"] = { tipo = "estrutura", desc = "Cabeçalho opcional do arquivo", sintaxe = "YASHSCRIPT:" },

	-- Serviços Roblox
	["workspace"] = { tipo = "servico", desc = "Workspace", sintaxe = "usar \"X\" = workspace.X" },
	["replicatedstorage"] = { tipo = "servico", desc = "ReplicatedStorage", sintaxe = "usar \"X\" = ReplicatedStorage.X" },
	["serverstorage"] = { tipo = "servico", desc = "ServerStorage", sintaxe = "usar \"X\" = ServerStorage.X" },
	["serverscriptservice"] = { tipo = "servico", desc = "ServerScriptService", sintaxe = "usar \"X\" = ServerScriptService.X" },
	["players"] = { tipo = "servico", desc = "Players", sintaxe = "usar \"Jogadores\" = Players" },
	["lighting"] = { tipo = "servico", desc = "Lighting", sintaxe = "usar \"Luz\" = Lighting" },
	["runservice"] = { tipo = "servico", desc = "RunService", sintaxe = "usar \"Run\" = RunService" },
	["userinputservice"] = { tipo = "servico", desc = "UserInputService", sintaxe = "usar \"Input\" = UserInputService" },
	["tweenservice"] = { tipo = "servico", desc = "TweenService", sintaxe = "usar \"Tween\" = TweenService" },
	["soundservice"] = { tipo = "servico", desc = "SoundService", sintaxe = "usar \"Som\" = SoundService" },
	["debris"] = { tipo = "servico", desc = "Debris", sintaxe = "usar \"Debris\" = Debris" },
	["debrisservice"] = { tipo = "servico", desc = "Debris", sintaxe = "usar \"Debris\" = Debris" },
	["debisservice"] = { tipo = "servico", desc = "Debris", sintaxe = "usar \"Debris\" = Debris" },
	["contextactionservice"] = { tipo = "servico", desc = "ContextActionService", sintaxe = "usar \"Acoes\" = ContextActionService" },
	["httpservice"] = { tipo = "servico", desc = "HttpService", sintaxe = "usar \"Http\" = HttpService" },
	["datastoreservice"] = { tipo = "servico", desc = "DataStoreService", sintaxe = "usar \"Dados\" = DataStoreService" },
	["marketplaceservice"] = { tipo = "servico", desc = "MarketplaceService", sintaxe = "usar \"Loja\" = MarketplaceService" },
	["collectionservice"] = { tipo = "servico", desc = "CollectionService", sintaxe = "usar \"Tags\" = CollectionService" },
	["physicsservice"] = { tipo = "servico", desc = "PhysicsService", sintaxe = "usar \"Fisica\" = PhysicsService" },
	["textchatservice"] = { tipo = "servico", desc = "TextChatService", sintaxe = "usar \"Chat\" = TextChatService" },
	["chatwindowconfiguration"] = { tipo = "servico", desc = "ChatWindowConfiguration", sintaxe = "usar \"Chat\" = ChatWindowConfiguration" },
	["startergui"] = { tipo = "servico", desc = "StarterGui", sintaxe = "usar \"Menu\" = StarterGui.Menu" },
	["starterpack"] = { tipo = "servico", desc = "StarterPack", sintaxe = "usar \"Pack\" = StarterPack" },

	-- Globais Luau
	["Instance"] = { tipo = "luau", desc = "Construtor e namespace de instâncias", sintaxe = "Instance.new(\"Part\")" },
	["Enum"] = { tipo = "luau", desc = "Enums do Roblox", sintaxe = "Enum.Material.Neon" },
	["Vector2"] = { tipo = "luau", desc = "Vetor 2D", sintaxe = "Vector2.new(0, 0)" },
	["Vector3"] = { tipo = "luau", desc = "Vetor 3D", sintaxe = "Vector3.new(0, 0, 0)" },
	["Vector2int16"] = { tipo = "luau", desc = "Vetor 2D inteiro", sintaxe = "Vector2int16.new(0, 0)" },
	["Vector3int16"] = { tipo = "luau", desc = "Vetor 3D inteiro", sintaxe = "Vector3int16.new(0, 0, 0)" },
	["CFrame"] = { tipo = "luau", desc = "Posição + rotação", sintaxe = "CFrame.new(0, 0, 0)" },
	["Color3"] = { tipo = "luau", desc = "Cor RGB", sintaxe = "Color3.fromRGB(0, 0, 0)" },
	["UDim"] = { tipo = "luau", desc = "Dimensão com escala/pixels", sintaxe = "UDim.new(0, 100)" },
	["UDim2"] = { tipo = "luau", desc = "Tamanho/posição 2D", sintaxe = "UDim2.new(1, 0, 1, 0)" },
	["BrickColor"] = { tipo = "luau", desc = "Cor de tijolo", sintaxe = "BrickColor.new(\"Medium stone grey\")" },
	["TweenInfo"] = { tipo = "luau", desc = "Configuração de tween", sintaxe = "TweenInfo.new(0.5)" },
	["Ray"] = { tipo = "luau", desc = "Raio de colisão", sintaxe = "Ray.new(origem, direcao)" },
	["RaycastParams"] = { tipo = "luau", desc = "Parâmetros de raycast", sintaxe = "RaycastParams.new()" },
	["OverlapParams"] = { tipo = "luau", desc = "Parâmetros de overlap", sintaxe = "OverlapParams.new()" },
	["Region3"] = { tipo = "luau", desc = "Região 3D", sintaxe = "Region3.new(mn, mx)" },
	["Region3int16"] = { tipo = "luau", desc = "Região 3D inteira", sintaxe = "Region3int16.new(mn, mx)" },
	["NumberRange"] = { tipo = "luau", desc = "Intervalo numérico", sintaxe = "NumberRange.new(0, 10)" },
	["NumberSequence"] = { tipo = "luau", desc = "Sequência numérica", sintaxe = "NumberSequence.new(1)" },
	["NumberSequenceKeypoint"] = { tipo = "luau", desc = "Ponto de sequência", sintaxe = "NumberSequenceKeypoint.new(0, 1)" },
	["ColorSequence"] = { tipo = "luau", desc = "Sequência de cores", sintaxe = "ColorSequence.new(c1, c2)" },
	["ColorSequenceKeypoint"] = { tipo = "luau", desc = "Ponto de cor", sintaxe = "ColorSequenceKeypoint.new(0, cor)" },
	["PhysicalProperties"] = { tipo = "luau", desc = "Propriedades físicas", sintaxe = "PhysicalProperties.new()" },
	["Rect"] = { tipo = "luau", desc = "Retângulo 2D", sintaxe = "Rect.new(mn, mx)" },
	["Axes"] = { tipo = "luau", desc = "Eixos", sintaxe = "Axes.new(Enum.Axis.X)" },
	["Faces"] = { tipo = "luau", desc = "Faces", sintaxe = "Faces.new(Enum.NormalId.Top)" },
	["Font"] = { tipo = "luau", desc = "Fonte do Roblox", sintaxe = "Font.new(\"rbxassetid://0\")" },
	["DateTime"] = { tipo = "luau", desc = "Data/hora", sintaxe = "DateTime.now()" },
	["Random"] = { tipo = "luau", desc = "Aleatório", sintaxe = "Random.new()" },
	["task"] = { tipo = "luau", desc = "Agendamento", sintaxe = "task.wait(1)" },
	["math"] = { tipo = "luau", desc = "Funções matemáticas", sintaxe = "math.floor(1.5)" },
	["string"] = { tipo = "luau", desc = "Funções de texto", sintaxe = "string.lower(\"X\")" },
	["table"] = { tipo = "luau", desc = "Funções de tabela", sintaxe = "table.insert(L, v)" },
	["utf8"] = { tipo = "luau", desc = "Texto UTF-8", sintaxe = "utf8.len(\"ação\")" },
	["os"] = { tipo = "luau", desc = "Sistema", sintaxe = "os.time()" },
	["coroutine"] = { tipo = "luau", desc = "Corrotinas", sintaxe = "coroutine.create(f)" },
	["debug"] = { tipo = "luau", desc = "Depuração", sintaxe = "debug.traceback()" },
	["bit32"] = { tipo = "luau", desc = "Operações de bits", sintaxe = "bit32.band(1, 2)" },
	["buffer"] = { tipo = "luau", desc = "Memória", sintaxe = "buffer.create(8)" },
	["tostring"] = { tipo = "luau", desc = "Converte em texto", sintaxe = "tostring(1)" },
	["tonumber"] = { tipo = "luau", desc = "Converte em número", sintaxe = "tonumber(\"10\")" },
	["typeof"] = { tipo = "luau", desc = "Tipo do valor", sintaxe = "typeof(x)" },
	["type"] = { tipo = "luau", desc = "Tipo do valor", sintaxe = "type(x)" },
	["assert"] = { tipo = "luau", desc = "Verifica condição", sintaxe = "assert(x)" },
	["error"] = { tipo = "luau", desc = "Lança erro", sintaxe = "error(\"msg\")" },
	["pcall"] = { tipo = "luau", desc = "Chamada protegida", sintaxe = "pcall(f)" },
	["xpcall"] = { tipo = "luau", desc = "Chamada protegida com handler", sintaxe = "xpcall(f, h)" },
	["select"] = { tipo = "luau", desc = "Seleciona argumentos", sintaxe = "select(\"#\", ...)" },
	["unpack"] = { tipo = "luau", desc = "Desempacota tabela", sintaxe = "unpack(t)" },
	["next"] = { tipo = "luau", desc = "Próximo item de tabela", sintaxe = "next(t)" },
	["warn"] = { tipo = "luau", desc = "Aviso no console", sintaxe = "warn(\"msg\")" },
	["rawget"] = { tipo = "luau", desc = "Leitura sem metatabela", sintaxe = "rawget(t, k)" },
	["rawset"] = { tipo = "luau", desc = "Escrita sem metatabela", sintaxe = "rawset(t, k, v)" },
	["rawequal"] = { tipo = "luau", desc = "Igualdade sem metatabela", sintaxe = "rawequal(a, b)" },
	["rawlen"] = { tipo = "luau", desc = "Tamanho sem metatabela", sintaxe = "rawlen(t)" },
	["getmetatable"] = { tipo = "luau", desc = "Metatabela", sintaxe = "getmetatable(t)" },
	["setmetatable"] = { tipo = "luau", desc = "Define metatabela", sintaxe = "setmetatable(t, m)" },
	["require"] = { tipo = "luau", desc = "Carrega módulo", sintaxe = "require(module)" },
}

-- Palavras-chave por categoria para syntax highlighting
local SYNTAX_COLORS = {
	evento = Color3.fromRGB(255, 180, 100),      -- Laranja
	comando = Color3.fromRGB(150, 220, 150),     -- Verde claro
	objeto = Color3.fromRGB(100, 200, 255),      -- Azul claro
	animacao = Color3.fromRGB(255, 150, 255),    -- Rosa
	propriedade = Color3.fromRGB(200, 255, 150), -- Verde menta
	operador = Color3.fromRGB(255, 255, 150),    -- Amarelo
	valor = Color3.fromRGB(255, 200, 100),       -- Laranja claro
	cor = Color3.fromRGB(255, 150, 150),         -- Vermelho claro
	funcao = Color3.fromRGB(180, 180, 255),      -- Roxo claro
	["palavra-chave"] = Color3.fromRGB(255, 180, 180), -- Vermelho bem claro
	comentario = Color3.fromRGB(100, 180, 100),  -- Verde escuro
	string = Color3.fromRGB(200, 255, 200),      -- Verde bem claro
	numero = Color3.fromRGB(150, 255, 255),      -- Ciano
	padrao = Color3.fromRGB(235, 235, 235),      -- Branco
}

-- Auto-par de brackets
local BRACKET_PAIRS = {
	["("] = ")",
	["["] = "]",
	["{"] = "}",
	['"'] = '"',
	["'"] = "'",
}

-- ------------------------------------------------------------------
-- utilitários
-- ------------------------------------------------------------------

local alvo
local scriptsCache = {} -- script -> { texto = "", sujo = false }
local editorLinhas = {}
local autocompleteAtivo = false
local autocompleteFrame = nil

-- declaradas cedo para que os closures acima encontre-as (locals nao sao
-- içadas em Lua: usar antes de declarar daria "attempt to call a nil value")
local _listarScripts, _repovoarLista, _mostrarScript

local editor, editorRolagem, listaRolagem, rotuloAlvo
local listaCabecalho, consoleCabecalho, consoleTexto, consoleRolagem, consolePainel
local listaAberta, consoleAberto = true, false
local linhasLog = {}
local BOTOES = {}
local ACOES = {}
local alternarConsole, aplicarLayout, atualizarCabecalhoLista
local dica, mostrarDica, esconderDica
local btnLista, abrirBtn, menuRaiz, menuPainel, subBotoes
local atualizarMenuBotoes
local numerosLinhas, numerosRolagem

local COR_TEXTO = Color3.fromRGB(235, 235, 235)
local COR_LINHA = Color3.fromRGB(42, 42, 52)
local COR_OK = Color3.fromRGB(120, 220, 120)
local COR_ERRO = Color3.fromRGB(255, 130, 130)
local COR_AVISO = Color3.fromRGB(255, 210, 120)
local COR_FUNDO_EDITOR = Color3.fromRGB(24, 24, 30)
local COR_LINHA_NUMERO = Color3.fromRGB(80, 80, 90)
local COR_LINHA_ATUAL = Color3.fromRGB(60, 60, 75)

local function caminhoScript(s)
	local partes = {}
	local p = s
	while p do
		table.insert(partes, 1, p.Name)
		p = p.Parent
	end
	return table.concat(partes, ".")
end

local LIMITE_LOG = 200

local function corHex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function escaparRichText(s)
	local r = string.gsub(tostring(s), "&", "&amp;")
	r = string.gsub(r, "<", "&lt;")
	r = string.gsub(r, ">", "&gt;")
	return r
end

local function setarStatus(msg, cor)
	cor = cor or COR_AVISO
	linhasLog[#linhasLog + 1] = os.date("%H:%M:%S") .. "  <font color=\"#" .. corHex(cor) .. "\">" .. escaparRichText(msg) .. "</font>"
	while #linhasLog > LIMITE_LOG do table.remove(linhasLog, 1) end
	if not consoleTexto then return end
	consoleTexto.Text = table.concat(linhasLog, "\n")
	if cor == COR_ERRO and not consoleAberto then
		consoleAberto = true
		if consolePainel then
			consolePainel.Size = UDim2.new(1, 0, 0, 150)
			consoleRolagem.Visible = true
			consoleCabecalho.Text = "Console ▼"
		end
	end
	task.defer(function()
		if not consoleRolagem or not consoleTexto or not consoleAberto then return end
		local conteudo = consoleTexto.AbsoluteSize.Y
		consoleRolagem.CanvasSize = UDim2.new(0, 0, 0, conteudo)
		local visivel = consoleRolagem.AbsoluteSize.Y
		local excedente = math.max(conteudo - visivel, 0)
		if excedente > 0 then consoleRolagem.CanvasPosition = Vector2.new(0, excedente) end
	end)
end

local _compCache = nil
local function obterCompilador()
	if _compCache then return _compCache end
	local chunk = loadstring(FONTES.Compilador)
	if type(chunk) ~= "function" then return nil end
	local ok, c = pcall(chunk)
	if ok and type(c) == "table" then _compCache = c; return c end
	return nil
end

local _gerCache = nil
local function obterGerador()
	if _gerCache then return _gerCache end
	local chunk = loadstring(FONTES.Gerador)
	if type(chunk) ~= "function" then return nil end
	local ok, g = pcall(chunk)
	if ok and type(g) == "table" and type(g.GerarLuau) == "function" then _gerCache = g; return g end
	return nil
end

local function lerYashDoScript(s)
	local attr = s:GetAttribute("YashScript")
	if type(attr) == "string" and attr ~= "" then return attr end
	return nil
end

local function ancestraGuiDoScript(s)
	local gui
	local p = s.Parent
	while p do
		if p:IsA("ScreenGui") then gui = p; break end
		p = p.Parent
	end
	if not gui then return nil end
	local cadeia = {}
	local atual = s.Parent
	while atual and atual ~= gui do table.insert(cadeia, 1, atual.Name); atual = atual.Parent end
	table.insert(cadeia, 1, gui.Name)
	return cadeia
end

local function opcoesDoAlvo(s)
	local opcoes = { modulo = false }
	if s:IsA("ModuleScript") then opcoes.contexto = "comum"; opcoes.modulo = true
	elseif s:IsA("LocalScript") then opcoes.contexto = "cliente"
	else opcoes.contexto = "servidor" end
	opcoes.ancestraGui = ancestraGuiDoScript(s)
	return opcoes
end

local function gerarLuau(yash, opcoes)
	local comp = obterCompilador()
	if not comp then return nil, "falha ao carregar o compilador embutido" end
	local ger = obterGerador()
	if not ger then return nil, "falha ao carregar o gerador embutido" end
	local ok, res = comp.Compilar(yash or "", {})
	if not ok then
		local msg = res and res.erro or "erro desconhecido de compilação"
		if res and res.linha and res.linha > 0 then msg = msg .. " (linha " .. res.linha .. ")" end
		return nil, msg
	end
	local gok, g1, g2 = pcall(function() return ger.GerarLuau(res, opcoes) end)
	if not gok then return nil, "erro ao gerar Luau: " .. tostring(g1) end
	if g1 ~= true then
		local msg = type(g2) == "table" and (g2.erro or "erro desconhecido") or tostring(g2)
		if type(g2) == "table" and g2.linha and g2.linha > 0 then msg = msg .. " (linha " .. g2.linha .. ")" end
		return nil, msg
	end
	return g2, nil
end

-- ------------------------------------------------------------------
-- SYNTAX HIGHLIGHTING
-- ------------------------------------------------------------------

local function destacarLinha(linha)
	local saida, plano = {}, {}
	local i = 1
	while i <= #linha do
		local c = linha:sub(i, i)
		-- comentario ate o fim da linha
		if c == "-" and linha:sub(i + 1, i + 1) == "-" then
			if #plano > 0 then
				saida[#saida + 1] = escaparRichText(table.concat(plano))
				table.clear(plano)
			end
			saida[#saida + 1] = '<font color="#' .. corHex(SYNTAX_COLORS.comentario) .. '">'
				.. escaparRichText(linha:sub(i)) .. "</font>"
			return table.concat(saida)
		end
		-- string
		if c == '"' or c == "'" then
			local j = i + 1
			while j <= #linha do
				local d = linha:sub(j, j)
				if d == "\\" then
					j = j + 2
				elseif d == c then
					j = j + 1
					break
				else
					j = j + 1
				end
			end
			if #plano > 0 then
				saida[#saida + 1] = escaparRichText(table.concat(plano))
				table.clear(plano)
			end
			saida[#saida + 1] = '<font color="#' .. corHex(SYNTAX_COLORS.string) .. '">'
				.. escaparRichText(linha:sub(i, j - 1)) .. "</font>"
			i = j
		elseif c:match("[%w_]") then
			local j = i
			while j <= #linha and linha:sub(j, j):match("[%w_]") do j = j + 1 end
			local palavra = linha:sub(i, j - 1)
			local info = YASH_DICTIONARY[palavra] or YASH_DICTIONARY[palavra:lower()]
			if info then
				if #plano > 0 then
					saida[#saida + 1] = escaparRichText(table.concat(plano))
					table.clear(plano)
				end
				local cor = SYNTAX_COLORS[info.tipo] or SYNTAX_COLORS.padrao
				saida[#saida + 1] = '<font color="#' .. corHex(cor) .. '">'
					.. escaparRichText(palavra) .. "</font>"
			else
				plano[#plano + 1] = palavra
			end
			i = j
		else
			plano[#plano + 1] = c
			i = i + 1
		end
	end
	if #plano > 0 then
		saida[#saida + 1] = escaparRichText(table.concat(plano))
	end
	return table.concat(saida)
end

local function aplicarSyntaxHighlight(texto)
	if not texto or texto == "" then return "" end
	local linhas = string.split(texto, "\n")
	local resultado = {}
	for _, linha in ipairs(linhas) do
		resultado[#resultado + 1] = destacarLinha(linha)
	end
	return table.concat(resultado, "\n")
end

--
-- AUTOCOMPLETE
-- ------------------------------------------------------------------

local function obterPalavraAtual(texto, posCursor)
	local _inicio = posCursor
	while _inicio > 1 do
		local c = texto:sub(_inicio-1, _inicio-1)
		if not c:match("[%w_]") then break end
		_inicio = _inicio - 1
	end
	return texto:sub(_inicio, posCursor-1), _inicio
end

local function buscarSugestoes(prefixo)
	local sugestoes = {}
	local prefixoLower = prefixo:lower()
	
	for palavra, info in pairs(YASH_DICTIONARY) do
		if palavra:lower():sub(1, #prefixoLower) == prefixoLower then
			table.insert(sugestoes, {palavra = palavra, info = info})
		end
	end
	
	table.sort(sugestoes, function(a, b) return a.palavra < b.palavra end)
	return sugestoes
end

local function mostrarAutocomplete(sugestoes)
	if autocompleteFrame then autocompleteFrame:Destroy() end
	if #sugestoes == 0 then autocompleteAtivo = false; return end
	
	autocompleteAtivo = true
	
	autocompleteFrame = Instance.new("Frame")
	autocompleteFrame.Name = "AutocompleteFrame"
	autocompleteFrame.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
	autocompleteFrame.BorderSizePixel = 1
	autocompleteFrame.BorderColor3 = Color3.fromRGB(100, 100, 120)
	autocompleteFrame.ZIndex = 100
	autocompleteFrame.Parent = editorRolagem
	
	local _layout = Instance.new("UIListLayout")
	_layout.Parent = autocompleteFrame
	
	for i, sug in ipairs(sugestoes) do
		local item = Instance.new("TextLabel")
		item.Name = "Item_" .. i
		item.Size = UDim2.new(1, 0, 0, 20)
		item.BackgroundTransparency = 1
		item.TextColor3 = COR_TEXTO
		item.TextSize = 12
		item.Font = Enum.Font.Code
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Text = sug.palavra
		item.ZIndex = 101
		item.Parent = autocompleteFrame
		
		local corTipo = SYNTAX_COLORS[sug.info.tipo] or SYNTAX_COLORS.padrao
		local badge = Instance.new("TextLabel")
		badge.Name = "Badge"
		badge.Size = UDim2.new(0, 60, 1, 0)
		badge.Position = UDim2.new(1, -65, 0, 0)
		badge.BackgroundTransparency = 1
		badge.TextColor3 = corTipo
		badge.TextSize = 10
		badge.Font = Enum.Font.Code
		badge.TextXAlignment = Enum.TextXAlignment.Right
		badge.Text = sug.info.tipo
		badge.ZIndex = 102
		badge.Parent = item
	end
	
	autocompleteFrame.Size = UDim2.new(0, 280, 0, math.min(#sugestoes, 8) * 20)
	
	-- Posicionar perto do cursor
	local posCursor = editor.CursorPosition
	local linhaAtual = 1
	local colunaAtual = 1
	for i = 1, posCursor do
		if editor.Text:sub(i, i) == "\n" then
			linhaAtual = linhaAtual + 1
			colunaAtual = 1
		else
			colunaAtual = colunaAtual + 1
		end
	end
	
	local charSize = 7.8 -- aproximado para fonte Code 13
	local x = 4 + (colunaAtual - 1) * charSize + editorRolagem.AbsolutePosition.X
	local y = 4 + (linhaAtual - 1) * 15 + editorRolagem.AbsolutePosition.Y + 20
	
	autocompleteFrame.Position = UDim2.fromOffset(x - editorRolagem.AbsolutePosition.X, y - editorRolagem.AbsolutePosition.Y)
end

function _esconderAutocomplete()
	if autocompleteFrame then
		autocompleteFrame:Destroy()
		autocompleteFrame = nil
	end
	autocompleteAtivo = false
end

-- ------------------------------------------------------------------
-- EDITOR AVANÇADO
-- ------------------------------------------------------------------

local function criarEditorAvancado(parent)
	local container = Instance.new("Frame")
	container.Name = "EditorContainer"
	container.BackgroundColor3 = COR_FUNDO_EDITOR
	container.BorderSizePixel = 0
	container.Size = UDim2.new(1, 0, 1, 0)
	container.Parent = parent
	
	-- Números de linha
	numerosRolagem = Instance.new("ScrollingFrame")
	numerosRolagem.Name = "NumerosRolagem"
	numerosRolagem.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
	numerosRolagem.BorderSizePixel = 0
	numerosRolagem.ScrollBarThickness = 0
	numerosRolagem.ScrollingEnabled = false
	numerosRolagem.Size = UDim2.new(0, 30, 1, 0)
	numerosRolagem.Parent = container
	
	numerosLinhas = Instance.new("TextLabel")
	numerosLinhas.Name = "NumerosLinhas"
	numerosLinhas.BackgroundTransparency = 1
	numerosLinhas.TextColor3 = COR_LINHA_NUMERO
	numerosLinhas.TextSize = 13
	numerosLinhas.Font = Enum.Font.Code
	numerosLinhas.TextXAlignment = Enum.TextXAlignment.Right
	numerosLinhas.TextYAlignment = Enum.TextYAlignment.Top
	numerosLinhas.Size = UDim2.new(1, -5, 1, 0)
	numerosLinhas.Position = UDim2.new(0, 0, 0, 0)
	numerosLinhas.Text = "1"
	numerosLinhas.Parent = numerosRolagem
	
	-- Editor principal (TextBox com RichText falso via overlay)
	editorRolagem = Instance.new("ScrollingFrame")
	editorRolagem.Name = "EditorRolagem"
	editorRolagem.BackgroundColor3 = COR_FUNDO_EDITOR
	editorRolagem.BorderSizePixel = 0
	editorRolagem.ScrollBarThickness = 8
	editorRolagem.HorizontalScrollBarInset = Enum.ScrollBarInset.Always
	editorRolagem.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	editorRolagem.Size = UDim2.new(1, -30, 1, 0)
	editorRolagem.Position = UDim2.new(0, 30, 0, 0)
	editorRolagem.Parent = container
	
	-- TextBox base (invisível, captura input)
	local textBox = Instance.new("TextBox")
	textBox.Name = "EditorTextBox"
	textBox.Size = UDim2.new(1, 0, 0, 10000)
	textBox.Position = UDim2.new(0, 0, 0, 0)
	textBox.BackgroundTransparency = 1
	textBox.TextWrapped = false
	textBox.MultiLine = true
	textBox.ClearTextOnFocus = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.TextColor3 = COR_TEXTO
	textBox.TextSize = 13
	textBox.Font = Enum.Font.Code
	textBox.Text = ""
	textBox.PlaceholderText = "-- Digite YashScript aqui..."
	textBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
	textBox.Parent = editorRolagem
	
	-- Overlay para syntax highlighting (RichText Label)
	local highlightLabel = Instance.new("TextLabel")
	highlightLabel.Name = "HighlightLabel"
	highlightLabel.Size = UDim2.new(1, 0, 1, 0)
	highlightLabel.Position = UDim2.new(0, 0, 0, 0)
	highlightLabel.BackgroundTransparency = 1
	highlightLabel.TextColor3 = COR_TEXTO
	highlightLabel.TextSize = 13
	highlightLabel.Font = Enum.Font.Code
	highlightLabel.TextXAlignment = Enum.TextXAlignment.Left
	highlightLabel.TextYAlignment = Enum.TextYAlignment.Top
	highlightLabel.RichText = true
	highlightLabel.Text = ""
	highlightLabel.ZIndex = 1
	highlightLabel.Parent = editorRolagem
	
	-- Linha atual highlight
	local linhaAtualHighlight = Instance.new("Frame")
	linhaAtualHighlight.Name = "LinhaAtualHighlight"
	linhaAtualHighlight.BackgroundColor3 = COR_LINHA_ATUAL
	linhaAtualHighlight.BorderSizePixel = 0
	linhaAtualHighlight.Size = UDim2.new(1, 0, 0, 15)
	linhaAtualHighlight.Visible = false
	linhaAtualHighlight.ZIndex = 0
	linhaAtualHighlight.Parent = editorRolagem
	
	editor = textBox

	-- O TextBox fica com o texto invisivel para o overlay colorido aparecer; isso
	-- apagaria tambem o cursor nativo, entao desenhamos um cursor proprio.
	local LARGURA_CHAR = TextService:GetTextSize("M", 13, Enum.Font.Code, Vector2.new(10000, 10000)).X
	local ALTURA_LINHA = TextService:GetTextSize("MM", 13, Enum.Font.Code, Vector2.new(10000, 10000)).Y

	local cursorFalso = Instance.new("Frame")
	cursorFalso.Name = "CursorFalso"
	cursorFalso.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
	cursorFalso.BorderSizePixel = 0
	cursorFalso.Size = UDim2.new(0, 2, 0, ALTURA_LINHA)
	cursorFalso.ZIndex = 5
	cursorFalso.Visible = false
	cursorFalso.Parent = editorRolagem

	local function linhaColunaDe(pos)
		local texto = editor.Text
		local linha, col = 1, 1
		for i = 1, math.min(pos - 1, #texto) do
			if texto:sub(i, i) == "\n" then
				linha = linha + 1
				col = 1
			else
				col = col + 1
			end
		end
		return linha, col
	end

	local function atualizarCursorFalso()
		local linha, col = linhaColunaDe(editor.CursorPosition)
		cursorFalso.Position = UDim2.new(0, (col - 1) * LARGURA_CHAR, 0, (linha - 1) * ALTURA_LINHA)
	end

	local function atualizarAutocomplete()
		if not editor:IsFocused() then _esconderAutocomplete(); return end
		local palavra = obterPalavraAtual(editor.Text, editor.CursorPosition)
		if #palavra >= 1 then
			local sugestoes = buscarSugestoes(palavra)
			if #sugestoes > 0 then
				mostrarAutocomplete(sugestoes)
			else
				_esconderAutocomplete()
			end
		else
			_esconderAutocomplete()
		end
	end

	-- Selecao: o TextBox transparente apaga o highlight nativo da selecao,
	-- entao desenhamos um retangulo azul atras do texto selecionado.
	local selecaoFrame = Instance.new("Frame")
	selecaoFrame.Name = "SelecaoHighlight"
	selecaoFrame.BackgroundColor3 = Color3.fromRGB(70, 130, 220)
	selecaoFrame.BackgroundTransparency = 0.45
	selecaoFrame.BorderSizePixel = 0
	selecaoFrame.ZIndex = 2
	selecaoFrame.Visible = false
	selecaoFrame.Parent = editorRolagem

	local function atualizarSelecao()
		local a = editor.SelectionStart
		local b = editor.CursorPosition
		if a == -1 or b == -1 or a == b then
			selecaoFrame.Visible = false
			return
		end
		local iniPos, fimPos = math.min(a, b), math.max(a, b)
		local linhaIni, colIni = linhaColunaDe(iniPos)
		local linhaFim, colFim = linhaColunaDe(fimPos)
		selecaoFrame.Position = UDim2.new(0, (colIni - 1) * LARGURA_CHAR, 0, (linhaIni - 1) * ALTURA_LINHA)
		if linhaIni == linhaFim then
			selecaoFrame.Size = UDim2.new(0, (colFim - colIni) * LARGURA_CHAR, 0, ALTURA_LINHA)
		else
			selecaoFrame.Position = UDim2.new(0, 0, 0, (linhaIni - 1) * ALTURA_LINHA)
			selecaoFrame.Size = UDim2.new(1, 0, 0, (linhaFim - linhaIni + 1) * ALTURA_LINHA)
		end
		selecaoFrame.Visible = true
	end

	editor:GetPropertyChangedSignal("SelectionStart"):Connect(atualizarSelecao)
	editor:GetPropertyChangedSignal("CursorPosition"):Connect(atualizarSelecao)

	-- Cursor falso desativado: usamos o cursor nativo do TextBox
	-- cursorFalso.Visible = false

	-- Sincronizar scroll
	local function sincronizarScroll()
		numerosRolagem.CanvasPosition = Vector2.new(0, editorRolagem.CanvasPosition.Y)
		_esconderAutocomplete()
	end

	editorRolagem:GetPropertyChangedSignal("CanvasPosition"):Connect(sincronizarScroll)
	
	-- Atualizar números de linha e highlight
	local function atualizarLinhas()
		local texto = editor.Text
		local linhas = select(2, texto:gsub("\n", "\n")) + 1
		local nums = {}
		for i = 1, linhas do table.insert(nums, tostring(i)) end
		numerosLinhas.Text = table.concat(nums, "\n")
		
		-- Canvas size
		local alturaLinha = ALTURA_LINHA
		local alturaTotal = linhas * alturaLinha
		editorRolagem.CanvasSize = UDim2.new(0, 0, 0, alturaTotal)
		numerosRolagem.CanvasSize = UDim2.new(0, 0, 0, alturaTotal)
		textBox.Size = UDim2.new(1, 0, 0, alturaTotal)
		highlightLabel.Size = UDim2.new(1, 0, 0, alturaTotal)
		
	-- Syntax highlight (Texto do TextBox invisivel; o label mostra colorido)
	highlightLabel.RichText = true
	if #texto > 0 then
		highlightLabel.Text = aplicarSyntaxHighlight(texto)
	else
		highlightLabel.Text = '<font color="#64646E">-- Digite YashScript aqui...</font>'
	end
	textBox.TextTransparency = 0.15
	atualizarCursorFalso()
end
	
	editor:GetPropertyChangedSignal("Text"):Connect(function()
		atualizarLinhas()
		task.wait(0.02)
		atualizarAutocomplete()
	end)

	-- Auto-par: detecta o caractere recem-digitado por diff de texto (o KeyCode
	-- fisico nao distingue "(" de "9", entao a comparacao por KeyCode falhava).
	local ajustandoPar = false
	local textoAnteriorPar = editor.Text
	editor:GetPropertyChangedSignal("Text"):Connect(function()
		if ajustandoPar then return end
		local ant, novo = textoAnteriorPar, editor.Text
		textoAnteriorPar = novo
		local s = 1
		local minlen = math.min(#ant, #novo)
		while s <= minlen and ant:sub(s, s) == novo:sub(s, s) do s = s + 1 end
		local e1, e2 = #ant, #novo
		while e1 >= s and e2 >= s and ant:sub(e1, e1) == novo:sub(e2, e2) do
			e1 = e1 - 1
			e2 = e2 - 1
		end
		local inserido = novo:sub(s, e2)
		local deletado = ant:sub(s, e1)
		if #inserido == 1 then
			local fecha = BRACKET_PAIRS[inserido]
			if fecha then
				ajustandoPar = true
				editor.Text = novo:sub(1, s) .. fecha .. novo:sub(s + 1)
				editor.CursorPosition = s + 1
				textoAnteriorPar = editor.Text
				ajustandoPar = false
			end
		elseif #deletado == 1 and #inserido == 0 then
			local fechaDoRemovido = BRACKET_PAIRS[deletado]
			if fechaDoRemovido and novo:sub(s, s) == fechaDoRemovido then
				-- apagou o abridor: remove tambem o fechador vazio logo a frente
				ajustandoPar = true
				editor.Text = novo:sub(1, s - 1) .. novo:sub(s + 1)
				editor.CursorPosition = s
				textoAnteriorPar = editor.Text
				ajustandoPar = false
			else
				for abre, par_fecha in pairs(BRACKET_PAIRS) do
					if par_fecha == deletado and novo:sub(s - 1, s - 1) == abre then
						-- apagou o fechador: remove tambem o abridor vazio anterior
						ajustandoPar = true
						editor.Text = novo:sub(1, s - 2) .. novo:sub(s)
						editor.CursorPosition = s - 1
						textoAnteriorPar = editor.Text
						ajustandoPar = false
						break
					end
				end
			end
		end
	end)
	
	-- Cursor position -> linha atual highlight
	editor:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		local linha = linhaColunaDe(editor.CursorPosition)
		linhaAtualHighlight.Position = UDim2.new(0, 0, 0, (linha - 1) * ALTURA_LINHA)
		linhaAtualHighlight.Size = UDim2.new(1, 0, 0, ALTURA_LINHA)
		linhaAtualHighlight.Visible = true
		atualizarCursorFalso()
	end)
	
	-- Inicializar
	atualizarLinhas()
	
	return container, editor, highlightLabel
end

-- ------------------------------------------------------------------
-- GERENCIAMENTO DE SCRIPTS (com estado sujo)
-- ------------------------------------------------------------------

local function obterScriptCache(script)
	if not scriptsCache[script] then
		local yash = lerYashDoScript(script)
		scriptsCache[script] = {
			texto = yash or "",
			sujo = false,
			ultimoSalvo = yash or ""
		}
	end
	return scriptsCache[script]
end

local function marcarSujo(script, sujo)
	local cache = obterScriptCache(script)
	cache.sujo = sujo
	atualizarCabecalhoLista(#_listarScripts())
end

local function salvarNoCache(script)
	local cache = obterScriptCache(script)
	cache.texto = editor.Text
	cache.ultimoSalvo = editor.Text
	cache.sujo = false
	marcarSujo(script, false)
end

local function restaurarDoCache(script)
	local cache = obterScriptCache(script)
	if cache.texto ~= editor.Text then
		editor.Text = cache.texto
		marcarSujo(script, cache.sujo)
	end
end

-- ------------------------------------------------------------------
-- INTERFACE (adaptada do original)
-- ------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("YashScript")
print("[YashScript] toolbar criada")
local botaoAbrir = toolbar:CreateButton("YashScript V8.0", "Abrir o editor YashScript avançado", "rbxassetid://16955637958")

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 500, 700, 400, 500)
local widget = plugin:CreateDockWidgetPluginGui("YashScriptPainel", info)
widget.Title = "YashScript V8.0 — Editor Avançado"

botaoAbrir.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled then aplicarLayout(); pcall(_repovoarLista) end
end)

local root = Instance.new("Frame")
root.Name = "Raiz"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
root.BorderSizePixel = 0
root.Parent = widget

-- Toolbar superior
local toolbarFrame = Instance.new("Frame")
toolbarFrame.Name = "Toolbar"
toolbarFrame.Size = UDim2.new(1, 0, 0, 32)
toolbarFrame.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
toolbarFrame.BorderSizePixel = 0
toolbarFrame.Parent = root

abrirBtn = Instance.new("TextButton")
abrirBtn.Name = "abrirBtn"
abrirBtn.Size = UDim2.new(0, 78, 0, 24)
abrirBtn.Position = UDim2.new(0, 8, 0, 4)
abrirBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 92)
abrirBtn.TextColor3 = COR_TEXTO
abrirBtn.Text = "ABRIR"
abrirBtn.TextSize = 11
abrirBtn.Font = Enum.Font.SourceSansBold
abrirBtn.BorderSizePixel = 0
abrirBtn.AutoButtonColor = true
local c1 = Instance.new("UICorner")
c1.CornerRadius = UDim.new(0, 4)
c1.Parent = abrirBtn
abrirBtn.Parent = toolbarFrame

btnLista = Instance.new("TextButton")
btnLista.Name = "btnLista"
btnLista.Size = UDim2.new(0, 108, 0, 24)
btnLista.Position = UDim2.new(0, 92, 0, 4)
btnLista.BackgroundColor3 = Color3.fromRGB(52, 52, 66)
btnLista.TextColor3 = COR_TEXTO
btnLista.Text = "Scripts (0) ▼"
btnLista.TextSize = 11
btnLista.Font = Enum.Font.SourceSansBold
btnLista.BorderSizePixel = 0
btnLista.AutoButtonColor = true
local cornerLista = Instance.new("UICorner")
cornerLista.CornerRadius = UDim.new(0, 4)
cornerLista.Parent = btnLista
btnLista.Parent = toolbarFrame

local titulo = Instance.new("TextLabel")
titulo.Name = "titulo"
titulo.Size = UDim2.new(1, -212, 0, 24)
titulo.Position = UDim2.new(0, 206, 0, 4)
titulo.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
titulo.TextColor3 = COR_TEXTO
titulo.Text = "YashScript V8.0 — Editor Avançado"
titulo.TextSize = 14
titulo.Font = Enum.Font.SourceSansSemibold
titulo.Parent = root

-- Lista de scripts (esquerda)
listaCabecalho = Instance.new("TextButton")
listaCabecalho.Name = "listaCabecalho"
listaCabecalho.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
listaCabecalho.TextColor3 = COR_TEXTO
listaCabecalho.Text = "Scripts (0) ▼"
listaCabecalho.TextSize = 11
listaCabecalho.TextXAlignment = Enum.TextXAlignment.Left
listaCabecalho.BorderSizePixel = 0
listaCabecalho.Size = UDim2.new(0, 180, 0, 22)
listaCabecalho.Visible = false
listaCabecalho.Parent = root

listaRolagem = Instance.new("ScrollingFrame")
listaRolagem.Name = "listaRolagem"
listaRolagem.BackgroundColor3 = COR_LINHA
listaRolagem.BorderSizePixel = 0
listaRolagem.ScrollBarThickness = 6
listaRolagem.CanvasSize = UDim2.new(0, 0, 0, 0)
listaRolagem.Size = UDim2.new(0, 180, 1, -60)
listaRolagem.Position = UDim2.new(0, 0, 0, 56)
listaRolagem.Parent = root

-- Editor central (AVANÇADO)
local editorContainer, editorTextBox, _highlightLabel = criarEditorAvancado(root)
editorContainer.Name = "EditorContainer"
editorContainer.Size = UDim2.new(1, -180, 1, -140)
editorContainer.Position = UDim2.new(0, 180, 0, 56)
editor = editorTextBox

-- Status do alvo
rotuloAlvo = Instance.new("TextLabel")
rotuloAlvo.Name = "rotuloAlvo"
rotuloAlvo.BackgroundColor3 = COR_LINHA
rotuloAlvo.TextColor3 = COR_TEXTO
rotuloAlvo.Text = "Alvo: nenhum"
rotuloAlvo.TextSize = 10
rotuloAlvo.TextXAlignment = Enum.TextXAlignment.Left
rotuloAlvo.TextWrapped = true
rotuloAlvo.Size = UDim2.new(1, -180, 0, 20)
rotuloAlvo.Position = UDim2.new(0, 180, 1, -20)
rotuloAlvo.Parent = root

-- Console (baixo)
consolePainel = Instance.new("Frame")
consolePainel.Name = "consolePainel"
consolePainel.AnchorPoint = Vector2.new(0, 1)
consolePainel.BackgroundColor3 = COR_LINHA
consolePainel.BorderSizePixel = 0
consolePainel.Size = UDim2.new(1, 0, 0, 22)
consolePainel.Position = UDim2.new(0, 0, 1, 0)
consolePainel.Parent = root

consoleCabecalho = Instance.new("TextButton")
consoleCabecalho.Name = "consoleCabecalho"
consoleCabecalho.BackgroundTransparency = 1
consoleCabecalho.TextColor3 = COR_AVISO
consoleCabecalho.Text = "Console ▲"
consoleCabecalho.TextSize = 10
consoleCabecalho.TextXAlignment = Enum.TextXAlignment.Left
consoleCabecalho.Font = Enum.Font.SourceSansSemibold
consoleCabecalho.BorderSizePixel = 0
consoleCabecalho.Size = UDim2.new(1, 0, 0, 22)
consoleCabecalho.Parent = consolePainel

consoleRolagem = Instance.new("ScrollingFrame")
consoleRolagem.Name = "consoleRolagem"
consoleRolagem.BackgroundTransparency = 1
consoleRolagem.BorderSizePixel = 0
consoleRolagem.ScrollBarThickness = 6
consoleRolagem.CanvasSize = UDim2.new(0, 0, 0, 0)
consoleRolagem.AutomaticCanvasSize = Enum.AutomaticSize.Y
consoleRolagem.Visible = false
consoleRolagem.Size = UDim2.new(1, 0, 1, -22)
consoleRolagem.Position = UDim2.new(0, 0, 0, 22)
consoleRolagem.Parent = consolePainel

consoleTexto = Instance.new("TextLabel")
consoleTexto.Name = "consoleTexto"
consoleTexto.BackgroundTransparency = 1
consoleTexto.TextColor3 = COR_TEXTO
consoleTexto.Text = ""
consoleTexto.TextSize = 10
consoleTexto.Font = Enum.Font.Code
consoleTexto.RichText = true
consoleTexto.TextXAlignment = Enum.TextXAlignment.Left
consoleTexto.TextYAlignment = Enum.TextYAlignment.Top
consoleTexto.TextWrapped = true
consoleTexto.AutomaticSize = Enum.AutomaticSize.Y
consoleTexto.Size = UDim2.new(1, -6, 0, 0)
consoleTexto.Parent = consoleRolagem

-- Botões de ação (direita inferior)
local botoesFrame = Instance.new("Frame")
botoesFrame.Name = "BotoesFrame"
botoesFrame.BackgroundTransparency = 1
botoesFrame.Size = UDim2.new(0, 180, 0, 80)
botoesFrame.Position = UDim2.new(1, -180, 1, -100)
botoesFrame.Parent = root

local function criarBotaoAcao(nome, texto, callback, yOffset)
	local btn = Instance.new("TextButton")
	btn.Name = nome
	btn.Text = texto
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	btn.TextColor3 = COR_TEXTO
	btn.TextSize = 11
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(1, -16, 0, 24)
	btn.Position = UDim2.new(0, 8, 0, yOffset)
	btn.Font = Enum.Font.SourceSansBold
	btn.AutoButtonColor = true
	btn.Parent = botoesFrame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn
	
	btn.Activated:Connect(callback)
	ACOES[nome] = callback
	return btn
end

criarBotaoAcao("Gravar", "Gravar no script (Ctrl+S)", function()
	if not alvo then setarStatus("Escolha um script primeiro.", COR_ERRO); return end
	local opcoes = opcoesDoAlvo(alvo)
	local luau, erro = gerarLuau(editor.Text, opcoes)
	if not luau then setarStatus("Erro: " .. tostring(erro), COR_ERRO); return end
	
	local ok = pcall(function()
		alvo.Source = luau
		alvo:SetAttribute("YashScript", editor.Text)
	end)
	if not ok then setarStatus("Falha ao gravar (script protegido?).", COR_ERRO); return end
	
	salvarNoCache(alvo)
	ultimaFonte = alvo.Source
	ultimoYash = editor.Text
	local detalhe = opcoes.contexto
	if opcoes.ancestraGui then detalhe = detalhe .. ", gui " .. table.concat(opcoes.ancestraGui, ".") end
	setarStatus("'" .. alvo.Name .. "' gravado: " .. #luau .. " bytes (" .. detalhe .. ")", COR_OK)
end, 0)

criarBotaoAcao("Selecionado", "Usar Selecionado", function()
	local sel = nil
	local ok, res = pcall(function() return plugin:GetSelected() end)
	if ok and res then for _, i in ipairs(res) do if i:IsA("BaseScript") then sel = i; break end end end
	if not sel then pcall(function() for _, i in ipairs(game:GetService("Selection"):Get()) do if i:IsA("BaseScript") then sel = i; break end end end) end
	if sel then _mostrarScript(sel); pcall(_repovoarLista) else setarStatus("Selecione um script no Studio.", COR_AVISO) end
end, 28)

criarBotaoAcao("Validar", "Validar (Ctrl+Enter)", function()
	if not alvo then setarStatus("Escolha um script primeiro.", COR_ERRO); return end
	local opcoes = opcoesDoAlvo(alvo)
	local luau, erro = gerarLuau(editor.Text, opcoes)
	if not luau then setarStatus("Erro: " .. tostring(erro), COR_ERRO); return end
	local rotulo = alvo.ClassName .. " (" .. opcoes.contexto
	if opcoes.ancestraGui then rotulo = rotulo .. ", gui " .. table.concat(opcoes.ancestraGui, ".") end
	rotulo = rotulo .. ")"
	setarStatus("Luau válido: " .. #luau .. " bytes, " .. rotulo, COR_OK)
end, 56)

-- Menu ABRIR: lista os botoes de acao e permite mostra-los/oculta-los
local menuAbrir = Instance.new("Frame")
menuAbrir.Name = "MenuAbrir"
menuAbrir.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
menuAbrir.BorderSizePixel = 0
menuAbrir.Size = UDim2.new(0, 178, 0, 110)
menuAbrir.Position = UDim2.new(0, 8, 0, 34)
menuAbrir.Visible = false
menuAbrir.ZIndex = 100
menuAbrir.Parent = toolbarFrame

local function botaoAcaoPorNome(nome)
	for _, filho in ipairs(botoesFrame:GetChildren()) do
		if filho:IsA("TextButton") and filho.Name == nome then return filho end
	end
	return nil
end

local construirMenuAbrir
construirMenuAbrir = function()
	for _, filho in ipairs(menuAbrir:GetChildren()) do filho:Destroy() end

	local tituloMenu = Instance.new("TextLabel")
	tituloMenu.Name = "tituloMenu"
	tituloMenu.Size = UDim2.new(1, 0, 0, 20)
	tituloMenu.Position = UDim2.new(0, 0, 0, 2)
	tituloMenu.BackgroundTransparency = 1
	tituloMenu.TextColor3 = COR_AVISO
	tituloMenu.TextSize = 11
	tituloMenu.Font = Enum.Font.SourceSansBold
	tituloMenu.TextXAlignment = Enum.TextXAlignment.Left
	tituloMenu.Text = "  Mostrar botoes"
	tituloMenu.ZIndex = 101
	tituloMenu.Parent = menuAbrir

	local y = 24
	for _, nome in ipairs({ "Gravar", "Selecionado", "Validar" }) do
		local alvoBtn = botaoAcaoPorNome(nome)
		if alvoBtn then
			local item = Instance.new("TextButton")
			item.Name = "menu_" .. nome
			item.Size = UDim2.new(1, -8, 0, 24)
			item.Position = UDim2.new(0, 4, 0, y)
			item.BackgroundColor3 = Color3.fromRGB(52, 52, 68)
			item.TextColor3 = COR_TEXTO
			item.TextSize = 12
			item.Font = Enum.Font.Code
			item.TextXAlignment = Enum.TextXAlignment.Left
			item.BorderSizePixel = 0
			item.ZIndex = 101
			item.Text = (alvoBtn.Visible and "  \u{2713}  " or "       ") .. nome
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = item
			item.Activated:Connect(function()
				alvoBtn.Visible = not alvoBtn.Visible
				construirMenuAbrir()
			end)
			item.Parent = menuAbrir
			y = y + 26
		end
	end
end

construirMenuAbrir()
abrirBtn.Activated:Connect(function()
	menuAbrir.Visible = not menuAbrir.Visible
	if menuAbrir.Visible then
		construirMenuAbrir()
		-- garante que fique na frente do editor
		menuAbrir.Parent = root
	end
end)

-- Atalhos via UserInputService (plugin nao tem BindAction)
local function configurarAtalhos()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not editor:IsFocused() then return end
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if not ctrl then return end
		if input.KeyCode == Enum.KeyCode.S and ACOES.Gravar then ACOES.Gravar()
		elseif input.KeyCode == Enum.KeyCode.Return and ACOES.Validar then ACOES.Validar() end
	end)
end

-- Lista de scripts
function _listarScripts()
	local lista = {}
	for _, obj in ipairs(game:GetDescendants()) do
		if obj:IsA("BaseScript") and not obj:IsA("PluginScript") then table.insert(lista, obj) end
	end
	table.sort(lista, function(a, b) return a.Name:lower() < b.Name:lower() end)
	return lista
end

_repovoarLista = function()
	if not listaRolagem then return end
	for _, filho in ipairs(listaRolagem:GetChildren()) do filho:Destroy() end
	local scripts = _listarScripts()
	local offset = 4
	for _, s in ipairs(scripts) do
		local cache = scriptsCache[s]
		local sujo = cache and cache.sujo
		local btn = Instance.new("TextButton")
		btn.Name = "Item_" .. s.Name
		btn.Size = UDim2.new(1, -8, 0, 22)
		btn.Position = UDim2.new(0, 4, 0, offset)
		btn.Text = s.Name .. (sujo and " *" or "")
		btn.TextColor3 = sujo and Color3.fromRGB(255, 200, 100) or COR_TEXTO
		btn.BackgroundColor3 = (s == alvo) and Color3.fromRGB(60, 90, 120) or Color3.fromRGB(52, 52, 64)
		btn.TextSize = 11
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Font = Enum.Font.Code
		btn.BorderSizePixel = 0
		btn.Parent = listaRolagem
		btn.MouseEnter:Connect(function() mostrarDica(btn, caminhoScript(s) .. " (" .. s.ClassName .. ")") end)
		btn.MouseLeave:Connect(esconderDica)
		btn.Activated:Connect(function()
			esconderDica()
			if alvo and alvo ~= s then salvarNoCache(alvo) end
			_mostrarScript(s)
			pcall(_repovoarLista)
		end)
		offset = offset + 24
	end
	listaRolagem.CanvasSize = UDim2.new(0, 0, 0, offset + 4)
	atualizarCabecalhoLista(#scripts)
end

atualizarCabecalhoLista = function(n)
	local seta = listaAberta and "▼" or "▶"
	btnLista.Text = "Scripts (" .. n .. ") " .. seta
end

_mostrarScript = function(s)
	if alvo and alvo ~= s then salvarNoCache(alvo) end
	alvo = s
	restaurarDoCache(s)
	rotuloAlvo.Text = "Alvo: " .. caminhoScript(s)
	setarStatus("Mostrando " .. caminhoScript(s), COR_OK)
end

local function alternarListaVisibilidade()
	listaAberta = not listaAberta
	listaRolagem.Visible = listaAberta
	editorContainer.Visible = true
	if listaAberta then
		editorContainer.Size = UDim2.new(1, -180, 1, -140)
		editorContainer.Position = UDim2.new(0, 180, 0, 56)
	else
		editorContainer.Size = UDim2.new(1, 0, 1, -140)
		editorContainer.Position = UDim2.new(0, 0, 0, 56)
	end
	local n = #_listarScripts()
	local seta = listaAberta and "▼" or "▶"
	btnLista.Text = "Scripts (" .. n .. ") " .. seta
end

btnLista.Activated:Connect(alternarListaVisibilidade)

consoleCabecalho.Activated:Connect(function()
	consoleAberto = not consoleAberto
	consoleRolagem.Visible = consoleAberto
	consolePainel.Size = UDim2.new(1, 0, 0, consoleAberto and 150 or 22)
	consoleCabecalho.Text = "Console " .. (consoleAberto and "▼" or "▲")
	if consoleAberto then
		task.defer(function()
			local conteudo = consoleTexto.AbsoluteSize.Y
			consoleRolagem.CanvasSize = UDim2.new(0, 0, 0, conteudo)
			consoleRolagem.CanvasPosition = Vector2.new(0, math.max(0, conteudo - consoleRolagem.AbsoluteSize.Y))
		end)
	end
end)

-- Dica tooltip
dica = nil
mostrarDica = function(btn, texto)
	if not dica then
		dica = Instance.new("TextLabel")
		dica.Name = "dica"
		dica.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		dica.TextColor3 = COR_TEXTO
		dica.TextSize = 10
		dica.Font = Enum.Font.Code
		dica.BorderSizePixel = 0
		dica.ZIndex = 60
		dica.Visible = false
		dica.TextWrapped = true
		dica.AutomaticSize = Enum.AutomaticSize.Y
		dica.Size = UDim2.new(0, 280, 0, 0)
		dica.Parent = root
	end
	dica.Text = texto
	dica.Visible = true
	local p = btn.AbsolutePosition
	dica.Position = UDim2.fromOffset(math.max(4, math.min(p.X, root.AbsoluteSize.X - 284)), p.Y + 24)
end

esconderDica = function() if dica then dica.Visible = false end end

-- Sync externo
task.spawn(function()
	while true do
		if alvo and not editor:IsFocused() and alvo.Source ~= ultimaFonte then
			local yash = lerYashDoScript(alvo)
			ultimaFonte = alvo.Source
			if yash and yash ~= ultimoYash then
				ultimoYash = yash
				local cache = scriptsCache[alvo]
				if not cache or not cache.sujo then
					editor.Text = yash
					setarStatus("Script atualizado externamente.", COR_AVISO)
				end
			end
		end
		task.wait(0.5)
	end
end)

configurarAtalhos()
aplicarLayout = function() end -- layout fixo agora
widget.Enabled = true
pcall(_repovoarLista)
setarStatus("Pronto. Editor avançado carregado.", COR_OK)
print("[YashScript] Plugin V8.0 Advanced carregado")
