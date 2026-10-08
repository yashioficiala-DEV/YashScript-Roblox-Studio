--[[
  Runner local de testes do compilador YashScript (roda fora do Roblox).

  Pode ser executado:
    - direto no terminal com Lua 5.1+:   lua testes/rodar.lua
    - via Node + fengari:                node testes/rodar.js
]]

local ENTRADA = _G.ENTRADA or {}
local carregarTexto = loadstring or load

local compilador
if ENTRADA.compiladorFonte then
	local f
	f = assert(carregarTexto(ENTRADA.compiladorFonte))
	compilador = f()
else
	compilador = assert(loadfile("compilador/compilador.lua"))()
end

local gerador
if ENTRADA.geradorFonte then
	gerador = assert(carregarTexto(ENTRADA.geradorFonte))()
end

local function lerArquivo(caminho)
	if ENTRADA.arquivos and ENTRADA.arquivos[caminho] then return ENTRADA.arquivos[caminho] end
	if io and io.open then
		local f = io.open(caminho, "r")
		if f then
			local c = f:read("*a")
			f:close()
			return c
		end
	end
	return nil
end

local arquivos = {}
local visual = ENTRADA.arquivos and ENTRADA.arquivos["visual.yash"] or lerArquivo("testes/exemplos/visual.yash")
if visual then arquivos["visual.yash"] = visual end

local fontePrincipal = ENTRADA.fontePrincipal or lerArquivo("testes/exemplos/main.yash")

local fonteJogo = ENTRADA.arquivos and ENTRADA.arquivos["jogo.yash"] or lerArquivo("testes/exemplos/jogo.yash")

local testes = {
	{
		nome = "Chamada de metodo como instrucao avulsa (dois pontos)",
		fonte = [[
usar "Botao" = Workspace.Botao
usar "Parte" = Workspace.Parte
Botao:Destroy()
Parte:PivotTo((0, 5, 0))
]],
		deve = "ok",
	},

	{
		nome = "Chamada de metodo com base de caminho",
		fonte = [[
usar "Casa" = Workspace.Casa
Workspace.Parte:PivotTo((0, 5, 0))
Casa.Porta:Destroy()
]],
		deve = "ok",
	},

	{
		nome = "Chamada de metodo em evento, funcao e laco",
		fonte = [[
criar funcao Limpar()
    Workspace.B:Remove()
fim
usar "B" = Workspace.B
para indice de 1 ate 2
    B:Remove()
fim
quando clicar B
    B:Remove()
fim
Limpar()
]],
		deve = "ok",
	},

	{
		nome = "Chamada de metodo legada com ponto (destruir/remover)",
		fonte = [[
usar "Moeda" = Workspace.Moeda
Moeda.destruir()
Moeda.remover()
]],
		deve = "ok",
	},
	{
		nome = "Exemplo principal (do docx V6.5)",
		fonte = fontePrincipal,
		arquivos = arquivos,
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Jogo completo (mundo 3D + servidor)",
		fonte = fonteJogo,
		arquivos = arquivos,
		deve = "ok",
	},
	{
		nome = "Bloco site + estilos isolados",
		fonte = [[
site
    fundo = rgb(0,0,0)
    fonte = Arial
fim
]],
		deve = "ok",
	},
	{
		nome = "Elementos com animação composta",
		fonte = [[
criar botao 'b'
    largura = 120
    posicao = (10, 20)
fim
quando clicar 'b'
    mostrar texto "ai"
    mostrar(X)
    esconder(b) animacao = slide left + delta = 40
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Objetos, HUD e condições contínuas",
		fonte = [[
criar objeto 'jogador'
    x = 100
    y = 200
    velocidade = 5
    vida = 100
fim
criar objeto 'inimigo'
    x = 300
    y = 150
    velocidade_x = 3
    inimigo = sim
fim
criar hud 'vida'
    mostrar jogador.vida
fim
se jogador.vida <= 0
    destruir objeto jogador
fim
se jogador tocar inimigo
    destruir objeto inimigo
fim
se jogador apertar espaco
    mostrar texto "pulou"
fim
]],
		deve = "ok",
	},
	{
		nome = "Proibições (evento inválido falha)",
		fonte = [[
proibir clicar 'abrirChat' de mostrar(Chat) se visivel('Chat')
proibir clicar 'botao' de mostrar(A) + esconder(B) se oculto('A')
proibir clique 'x' de mostrar(Chat) somente 'fecharChat'
]],
		deve = "erro",
	},
	{
		nome = "Proibições válidas",
		fonte = [[
proibir clicar 'abrirChat' de mostrar(Chat) se visivel('Chat')
proibir clicar 'botao' de mostrar(A) + esconder(B) se oculto('A')
proibir clicar 'x' de mostrar(Chat) somente 'fecharChat'
]],
		deve = "ok",
	},
	{
		nome = "Ações e animações nomeadas",
		fonte = [[
criar acao 'sobreSistema'
    mostrar texto "Yash Engine V6.5"
fim
criar animacao 'pulsar'
    animacao = fade in + escala = +5
    animacao = fade out + escala = -5
fim
quando clicar 'botao'
    executar animacao pulsar
    executar acao sobreSistema
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Compatibilidade com sinal + em números",
		fonte = [[
criar texto 't'
    texto = "oi"
    escala = +10
fim
]],
		deve = "ok",
	},
	{
		nome = "Funções com parâmetros, retorno e expressão chamada",
		fonte = [[
variavel resultado = Somar(2, 3)
variavel agrupado = (Somar(1, 2) + Somar(3, 4))
Somar(1, 2)
criar funcao Somar(a, b)
    retornar a + b
fim
criar funcao PossuiLetra(texto, letra)
    retornar texto:find(letra) ~= nulo
fim
criar funcao ObterResultado()
    retornar resultado
fim
quando iniciar
    resultado = Somar(resultado, 4)
    se Somar(resultado, 1) > 9
        resultado += 1
    fim
fim
]],
		deve = "ok",
	},
	{
		nome = "Tabelas, listas, índices e atribuição composta",
		fonte = ENTRADA.fonteColecoes or [[
variavel Inventario = {"espada", "escudo"}
variavel Dados = { pontos = 10, ganho = 2 }
Inventario[2] = "lanca"
Dados["pontos"] += Dados.ganho
Dados.resultado = Dados.pontos + 3
]],
		deve = "ok",
	},
	{
		nome = "Laços numéricos e para cada (lista e mapa)",
		fonte = ENTRADA.fonteRepeticoes or [[
variavel Valores = {1, 2, 3, 4}
variavel Soma = 0
para cada valor em Valores
    Soma += valor
fim
para indice de 1 ate 5 passo 2
    Soma += indice
fim
]],
		deve = "ok",
	},
	{
		nome = "Laço repita/ate pós-condicional",
		fonte = [[
variavel Tentativas = 0
repita
    Tentativas += 1
ate Tentativas >= 3
]],
		deve = "ok",
	},
	{
		nome = "continuar dentro de laço aninhado em se",
		fonte = ENTRADA.fonteContinue or [[
variavel Valores = {1, 2, 3}
variavel Soma = 0
para cada valor em Valores
    se valor == 2
        continuar
    fim
    Soma += valor
fim
]],
		deve = "ok",
	},
	{
		nome = "ramos senao se em topo e funções",
		fonte = ENTRADA.fonteCondicionais or "",
		deve = "ok",
	},
	{
		nome = "variáveis locais isoladas por função",
		fonte = ENTRADA.fonteEscoposFuncao or "",
		deve = "ok",
	},
	{
		nome = "variáveis locais e retorno em evento",
		fonte = ENTRADA.fonteEscoposEvento or "",
		deve = "ok",
	},
	{
		nome = "retornar encerra temporizador",
		fonte = ENTRADA.fonteRetornoTemporizador or "",
		deve = "ok",
	},
	{
		nome = "Erro: variável local repetida na função",
		fonte = "criar funcao Repetir()\nvariavel Local = 1\nvariavel Local = 2\nfim\n",
		deve = "erro",
	},
	{
		nome = "Erro: pare fora de laço",
		fonte = "pare\n",
		deve = "erro",
	},
	{
		nome = "Erro: continuar fora de laço",
		fonte = "continuar\n",
		deve = "erro",
	},
	{
		nome = "Propriedades CSS removidas no V8 sao rejeitadas",
		fonte = [[
criar painel 'Chat'
    sombra = 0px 10px 70px rgba(255,255,255,0.3)
fim
]],
		deve = "erro",
	},
	{
		nome = "Mundo 3D: formas, mundo e timers",
		fonte = [[
mundo
    ceu = rgb(135,206,235)
    chao = rgb(60,60,60)
fim
criar bloco 'chao'
    posicao = (0, 0, 0)
    tamanho = (100, 1, 100)
    cor = rgb(80,80,80)
    material = concreto
fim
criar esfera 'moeda'
    posicao = (5, 2, 0)
    tamanho = (1, 1, 1)
    cor = rgb(255,215,0)
    raio_tocar = 3
fim
criar plataforma 'pilha'
    posicao = (0, 2, 0)
    rotacao = (0, 45, 0)
    tamanho = (10, 0.5, 10)
fim
a cada 5
    sortear moeda_pos entre 1 e 10
fim
quando tocar 'moeda'
    somar moeda_pos a jogador.moedas
    destruir objeto moeda
fim
quando iniciar
    esperar 1
    mostrar texto "comecou"
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Comandos de jogo (dano, mover, explodir, seguir)",
		fonte = [[
criar objeto 'jogador'
    vida = 100
fim
criar bloco 'inimigo'
    posicao = (0, 0, 10)
fim
criar acao 'atacar'
    causar dano jogador 10
fim
quando iniciar
    mover inimigo para (0, 0, 0) velocidade 25
    rotacionar inimigo para (0, 90, 0) duracao 1
    teleportar jogador (5, 0, 5)
    explodir inimigo raio 8 dano 50
fim
se jogador morto
    respawnar jogador
fim
se jogador perto de inimigo
    seguir inimigo o jogador
fim
]],
		deve = "ok",
	},
	{
		nome = "Condições de distância e vida",
		fonte = [[
se distancia jogador de inimigo menor que 5
    mostrar texto "perto"
fim
se distancia jogador de inimigo maior que 20
    mostrar texto "longe"
fim
se inimigo vivo
    somar pontos a jogador.moedas
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Som e sortear",
		fonte = [[
quando clicar 'botao'
    tocar som 9129606758
    sortear premio entre 1 e 100
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Erro: condição viva inválida",
		fonte = [[
se jogador vivo e morto
    mostrar texto "x"
fim
]],
		deve = "erro",
	},
	-- ------------------------------------------------------------------
	-- YASHSCRIPT: cabeçalho + linguagem própria
	-- ------------------------------------------------------------------
	{
		nome = "YASHSCRIPT: exemplo canônico do dev",
		fonte = [[
YASHSCRIPT:

criar objeto 'jogador'
    moedas = 0
    vida = 100
fim

criar esfera 'moeda'
    posicao = (8, 2, 0)
fim

quando jogador tocar moeda
    jogador.moedas += 1
    moeda.destruir()
fim
]],
		deve = "ok",
	},
	{
		nome = "YASHSCRIPT: sem regime legado (cliente)",
		fonte = [[
YASHSCRIPT:

criar painel 'Caixa'
    largura = 200
    altura = 100
fim
quando clicar 'Caixa'
    mostrar texto "ok"
fim
]],
		deve = "ok",
	},
	{
		nome = "YASHSCRIPT: regime no cabecalho foi removido",
		fonte = "YASHSCRIPT: servidor\n",
		deve = "erro",
	},
	{
		nome = "print com aspas duplas e simples",
		fonte = [[
YASHSCRIPT:
quando iniciar
    print("sucesso")
    print('sucesso2')
fim
]],
		deve = "ok",
	},
	{
		nome = "print com número e valor de atributo",
		fonte = [[
YASHSCRIPT:
quando iniciar
    print(jogador.moedas)
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Atribuição composta -= e atribuição simples por ponto",
		fonte = [[
YASHSCRIPT:
quando iniciar
    jogador.vida = 80
    jogador.vida -= 10
    jogador.moedas += 5
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Números negativos preservados com YASHSCRIPT:",
		fonte = [[
YASHSCRIPT:
criar esfera 'b'
    posicao = (-5, -2.5, 0)
    velocidade = -3
fim
criar objeto 'j'
    moedas = -10
    vida = -1
fim
]],
		deve = "ok",
	},
	{
		nome = "Evento com sujeito quando tocar",
		fonte = [[
YASHSCRIPT:
criar esfera 'moeda'
    posicao = (8, 2, 0)
fim
quando inimigo tocar moeda
    mostrar texto "atingido"
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Método .destruir() e outros métodos de objeto",
		fonte = [[
YASHSCRIPT:
criar esfera 'a'
    posicao = (0, 1, 0)
fim
quando iniciar
    a.destruir()
    mostrar(a)
    esconder(a)
fim
]],
		deve = "ok",
	},
	{
		nome = "Legado: quando tocar 'alvo' sem sujeito continua funcionando",
		fonte = [[
YASHSCRIPT:
criar esfera 'moeda'
    posicao = (8, 2, 0)
fim
quando tocar 'moeda'
    mostrar texto "tocou"
fim
]],
		deve = "ok",
	},
	{
		nome = "Condição criado com sucesso (com e sem entao)",
		fonte = [[
YASHSCRIPT:

criar objeto 'jogador'
    vida = 100
fim

criar esfera 'moeda'
    posicao = (8, 2, 0)
fim

quando iniciar
	se "jogador" criado com sucesso entao
		print("jogador pronto")
	fim

	se "moeda" criado com sucesso entao
		print("moeda pronta")
	fim

	enquanto moeda criado com sucesso
        esperar 0
	fim
	fim
]],
		deve = "ok",
	},
	{
		nome = "Erro: criado com sucesso incompleto",
		fonte = [[
YASHSCRIPT:

quando iniciar
	se "jogador" criado entao
		print("x")
	fim
]],
		deve = "erro",
	},
	{
		nome = "Erro: método desconhecido",
		fonte = [[
YASHSCRIPT:
    moeda.explodir()
fim
]],
		deve = "erro",
	},
	{
		nome = "Erro: YASHSCRIPT sem dois pontos",
		fonte = [[
YASHSCRIPT

criar esfera 'a'
    posicao = (0, 1, 0)
fim
]],
		deve = "erro",
	},
	{
		nome = "Erro: evento desconhecido com sujeito",
		fonte = [[
YASHSCRIPT:
quando jogador voar moeda
    mostrar texto "x"
fim
]],
		deve = "erro",
	},
	{
		nome = "Tween: propriedades com duracao",
		fonte = [[
YASHSCRIPT:

quando clicar Botao
    animar("Botao") posicao = (0, 100) + tamanho = (200, 50) + duracao = 0.5
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Tween: efeito com parametros",
		fonte = [[
YASHSCRIPT:

quando iniciar
    animar("Painel") fade in + duracao = 1
    animar("Painel") slide left + delta = 200
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Tween: efeito curto e animacao criada",
		fonte = [[
YASHSCRIPT:

criar animacao 'pulsar'
    animacao = fade in + duracao = 0.2
    animacao = fade out + duracao = 0.2
fim

quando clicar Botao
    animar("Botao") pulsar
    executar animacao pulsar
    animar("Botao") animacao = pulsar
fim
]],
		gera = false, -- so compilacao: usa nomes sem `usar`
		deve = "ok",
	},
	{
		nome = "Erro: animar sem efeito nem propriedade",
		fonte = [[
YASHSCRIPT:

quando clicar Botao
    animar("Botao")
fim
]],
		deve = "erro",
	},
}

local falhas = 0
for _, tc in ipairs(testes) do
	local ok, res = compilador.Compilar(tc.fonte, tc.arquivos)
	local esperado = tc.deve == "ok"
	if ok == esperado then
		print("[OK] " .. tc.nome)
	else
		falhas = falhas + 1
		print("[FALHOU] " .. tc.nome)
		print("    esperado: " .. tc.deve .. " | obtido: " .. tostring(ok))
		if not ok then
			print("    erro: " .. tostring(res.erro) .. " (linha " .. tostring(res.linha) .. ")")
		else
			print(compilador.Serializar(res))
		end
	end
end

-- ------------------------------------------------------------------
-- Evento com sujeito antes do nome: "quando Botao clicar" tem de produzir
-- exatamente o mesmo evento que "quando clicar Botao". Para tocar, o sujeito
-- continua sendo separado do alvo.
-- ------------------------------------------------------------------
do
	local function primeiroEvento(fonte)
		local ok, cfg = compilador.Compilar(fonte, {})
		if not ok then return nil, cfg end
		return cfg.eventos and cfg.eventos[1], nil
	end

	local function checar(cond, nome, detalhe)
		if cond then
			print("[OK] " .. nome)
		else
			falhas = falhas + 1
			print("[FALHOU] " .. nome .. (detalhe and (" -> " .. tostring(detalhe)) or ""))
		end
	end

	local evDepois, errA = primeiroEvento('quando clicar Botao\n    print("x")\nfim\n')
	local evAntes, errB = primeiroEvento('quando Botao clicar\n    print("x")\nfim\n')

	checar(evDepois ~= nil and evAntes ~= nil,
		"evento: as duas formas compilam", errA and errA.erro or errB and errB.erro)
	if evDepois and evAntes then
		checar(evDepois.tipo == "clicar" and evAntes.tipo == "clicar",
			"evento: tipo 'clicar' nas duas formas")
		checar(evDepois.alvo == "Botao" and evAntes.alvo == "Botao",
			"evento: alvo 'Botao' nas duas formas",
			tostring(evDepois.alvo) .. " / " .. tostring(evAntes.alvo))
		checar(evDepois.sujeito == nil and evAntes.sujeito == nil,
			"evento: nenhum residuo de sujeito",
			tostring(evDepois.sujeito) .. " / " .. tostring(evAntes.sujeito))
	end

	local evMouse, errC = primeiroEvento('quando Botao mouse_em\n    print("x")\nfim\n')
	checar(evMouse ~= nil and evMouse.alvo == "Botao" and evMouse.sujeito == nil,
		"evento: 'quando Botao mouse_em' usa Botao como alvo", errC and errC.erro)

	-- tocar mantem emissor e alvo separados: o sujeito NAO vira alvo
	local evTocar, errD = primeiroEvento('quando Cubo tocar Moeda\n    print("x")\nfim\n')
	checar(evTocar ~= nil, "evento: 'quando Cubo tocar Moeda' compila", errD and errD.erro)
	if evTocar then
		checar(evTocar.sujeito == "Cubo" and evTocar.alvo == "Moeda",
			"evento: tocar preserva sujeito e alvo separados",
			tostring(evTocar.sujeito) .. " / " .. tostring(evTocar.alvo))
	end
end

if gerador then
	local exemploOk, exemploPrograma = compilador.Compilar(ENTRADA.fonteFuncoes or "")
	local exemploGerado, exemploLuau = false, nil
	if exemploOk then exemploGerado, exemploLuau = gerador.GerarLuau(exemploPrograma, { contexto = "cliente" }) end
	local exemploChunk = exemploGerado and (loadstring or load)(exemploLuau) or nil
	if exemploChunk then
		local executouExemplo = pcall(exemploChunk)
		if executouExemplo then print("[GEN OK] LOGS/funcoes.yash compila e executa no ambiente de teste")
		else falhas = falhas + 1; print("[GEN FALHOU] LOGS/funcoes.yash não executou") end
	else
		falhas = falhas + 1
		print("[GEN FALHOU] LOGS/funcoes.yash: " .. tostring((not exemploOk and exemploPrograma.erro) or (not exemploGerado and exemploLuau) or "Luau inválido"))
	end

	local colecoesOk, colecoesPrograma = compilador.Compilar(ENTRADA.fonteColecoes or "")
	local colecoesGeradas, colecoesLuau = false, nil
	if colecoesOk then colecoesGeradas, colecoesLuau = gerador.GerarLuau(colecoesPrograma, { contexto = "comum", modulo = true }) end
	local colecoesChunk = colecoesGeradas and (loadstring or load)(colecoesLuau) or nil
	local rodouColecoes, colecoesExports = false, nil
	if colecoesChunk then rodouColecoes, colecoesExports = pcall(colecoesChunk) end
	local colecoesValidas = rodouColecoes and type(colecoesExports) == "table"
		and colecoesExports.LerItem(2) == "lanca" and colecoesExports.LerPontos() == 15
	if colecoesValidas then
		print("[GEN OK] LOGS/colecoes.yash compila e lê/escreve listas e tabelas")
	else
		falhas = falhas + 1
		print("[GEN FALHOU] LOGS/colecoes.yash: " .. tostring((not colecoesOk and colecoesPrograma.erro)
			or (not colecoesGeradas and colecoesLuau) or "resultado de índice/tabela incorreto"))
	end

	local loopsOk, loopsPrograma = compilador.Compilar(ENTRADA.fonteRepeticoes or "")
	local loopsGerados, loopsLuau = false, nil
	if loopsOk then loopsGerados, loopsLuau = gerador.GerarLuau(loopsPrograma, { contexto = "comum", modulo = true }) end
	local loopsChunk = loopsGerados and (loadstring or load)(loopsLuau) or nil
	local rodouLoops, loopsExports = false, nil
	if loopsChunk then rodouLoops, loopsExports = pcall(loopsChunk) end
	local loopsValidos = rodouLoops and type(loopsExports) == "table" and loopsExports.Resultado() == 36
	if loopsValidos then
		print("[GEN OK] LOGS/repeticoes.yash executa laços de lista, mapa, intervalo e repita/ate")
	else
		falhas = falhas + 1
		print("[GEN FALHOU] LOGS/repeticoes.yash: " .. tostring((not loopsOk and loopsPrograma.erro)
			or (not loopsGerados and loopsLuau) or "resultado dos laços incorreto"))
	end

	local condOk, condPrograma = compilador.Compilar(ENTRADA.fonteCondicionais or "")
	local condGeradas, condLuau = false, nil
	if condOk then condGeradas, condLuau = gerador.GerarLuau(condPrograma, { contexto = "comum", modulo = true }) end
	local condChunk = condGeradas and (loadstring or load)(condLuau) or nil
	local condExecutou, condExports = false, nil
	if condChunk then condExecutou, condExports = pcall(condChunk) end
	local condicionaisValidas = condExecutou and type(condExports) == "table"
		and condExports.ObterResultado() == 20 and condExports.Escolher(1) == 10
		and condExports.Escolher(2) == 20 and condExports.Escolher(3) == 30
		and condExports.Escolher(4) == 40
		and string.find(condLuau, "elseif", 1, true) ~= nil
	if condicionaisValidas then
		print("[GEN OK] LOGS/condicionais.yash executa ramos senao se no topo e em função")
	else
		falhas = falhas + 1
		print("[GEN FALHOU] LOGS/condicionais.yash: " .. tostring((not condOk and condPrograma.erro)
			or (not condGeradas and condLuau) or (condLuau or "") .. "\nResultado="
				.. tostring(condExports and condExports.ObterResultado and condExports.ObterResultado()) .. ", funcoes="
				.. tostring(condExports and condExports.Escolher and condExports.Escolher(1)) .. "/"
				.. tostring(condExports and condExports.Escolher and condExports.Escolher(2)) .. "/"
				.. tostring(condExports and condExports.Escolher and condExports.Escolher(3)) .. "/"
				.. tostring(condExports and condExports.Escolher and condExports.Escolher(4))))
	end

	local escoposOk, escoposPrograma = compilador.Compilar(ENTRADA.fonteEscoposFuncao or "")
	local escoposGerados, escoposLuau = false, nil
	if escoposOk then escoposGerados, escoposLuau = gerador.GerarLuau(escoposPrograma, { contexto = "comum", modulo = true }) end
	local escoposChunk = escoposGerados and (loadstring or load)(escoposLuau) or nil
	local escoposExecutaram, escoposExports = false, nil
	if escoposChunk then escoposExecutaram, escoposExports = pcall(escoposChunk) end
	local escoposValidos = escoposExecutaram and type(escoposExports) == "table"
		and escoposExports.Proxima() == 1 and escoposExports.Proxima() == 1
		and escoposExports.UsarMesmoNome() == 7 and escoposExports.SomarGlobal(2) == 101
	local escoposLuauValidos = escoposValidos and string.find(escoposLuau, "local Contador", 1, true) ~= nil
	if escoposLuauValidos then
		print("[GEN OK] LOGS/escopos_funcao.yash isola locais por chamada e preserva globais")
	else
		falhas = falhas + 1
		print("[GEN FALHOU] LOGS/escopos_funcao.yash: " .. tostring((not escoposOk and escoposPrograma.erro)
			or (not escoposGerados and escoposLuau) or "escopo local compartilhado ou global indisponível"))
	end

	local fonteEscoposEvento = ENTRADA.fonteEscoposEvento or ""
	local eventoEscopoOk, eventoEscopoPrograma = compilador.Compilar(fonteEscoposEvento)
	local eventoEscopoGerado, eventoEscopoLuau = false, nil
	if eventoEscopoOk then eventoEscopoGerado, eventoEscopoLuau = gerador.GerarLuau(eventoEscopoPrograma, { contexto = "comum" }) end
	local eventoEscopoChunk = eventoEscopoGerado and (loadstring or load)(eventoEscopoLuau) or nil
	local eventoLocais = eventoEscopoLuau and select(2, string.gsub(eventoEscopoLuau, "local Temporario", "")) or 0
	if eventoEscopoChunk and eventoLocais == 2 then
		print("[GEN OK] callbacks aceitam locais independentes com o mesmo nome")
	else
		falhas = falhas + 1
		print("[GEN FALHOU] escopo de callbacks: " .. tostring((not eventoEscopoOk and eventoEscopoPrograma.erro)
			or (not eventoEscopoGerado and eventoEscopoLuau) or "variável de callback fora do seu handler"))
	end

	local fonteFuncao = [[
variavel resultado = Somar(2, 3)
variavel agrupado = (Somar(1, 2) + Somar(3, 4))
Somar(1, 2)
criar funcao Somar(a, b)
    retornar a + b
fim
criar funcao PossuiLetra(texto, letra)
    retornar texto:find(letra) ~= nulo
fim
criar funcao ObterResultado()
    retornar resultado
fim
quando iniciar
    resultado = Somar(resultado, 4)
    se Somar(resultado, 1) > 9
        resultado += 1
    fim
fim
]]
	local ok, programa = compilador.Compilar(fonteFuncao)
	local gerou, codigo = false, nil
	if ok then gerou, codigo = gerador.GerarLuau(programa, { contexto = "comum", modulo = true }) end
	local carregarLuau = loadstring or load
	local chunk = gerou and carregarLuau(codigo) or nil
	local executou, exports = false, nil
	if chunk then executou, exports = pcall(chunk) end
	local sintaxeOk = chunk ~= nil and executou
	local conteudoOk = sintaxeOk
		and string.find(codigo, "return (a + b)", 1, true) ~= nil
		and type(exports) == "table" and exports.Somar(4, 5) == 9
		and exports.PossuiLetra("Yash", "a") == true
		and exports.PossuiLetra("Yash", "z") == false
		and exports.ObterResultado() == 10
		and not (string.find(codigo, "local Somar\n\nlocal Somar", 1, true)
			or string.find(codigo, "local Somar, Somar", 1, true))
	if conteudoOk then
		print("[GEN OK] Função YashScript gera Luau válido com argumentos e retorno")
	else
		falhas = falhas + 1
		print("[GEN FALHOU] Função YashScript: " .. tostring((not ok and programa.erro) or (not gerou and codigo) or "Luau inválido ou chamada ausente"))
	end
end

print("")
if falhas == 0 then
	print(">>> TODOS OS TESTES PASSARAM")
else
	print(">>> " .. falhas .. " TESTE(S) FALHARAM")
	os.exit(1)
end

-- ------------------------------------------------------------------
-- Round-trip: Compilar -> Descompilar -> Compilar deve preservar a config
-- ------------------------------------------------------------------
local function rodarRodada()
	local rtFalhas = 0
	local somenteCompilacao = 0
	for _, tc in ipairs(testes) do
		if tc.deve == "ok" and tc.gera == false then
			somenteCompilacao = somenteCompilacao + 1
			-- Fixture de SO COMPILACAO por declaracao. Se ele passar a gerar
			-- Luau, sinaliza: a marca precisa ser removida.
			local cOk, cCfg = compilador.Compilar(tc.fonte, tc.arquivos)
			local gOk, gRes = false, { erro = "nao compilou" }
			if cOk then
				gOk, gRes = gerador.GerarLuau(cCfg, { contexto = tc.contexto or "comum", modulo = tc.modulo })
			end
			if gOk then
				print("[RT FALHOU] " .. tc.nome .. " (marcado como so-compilacao mas agora gera Luau: remova gera = false)")
				rtFalhas = rtFalhas + 1
			else
				print("[RT skip] " .. tc.nome .. " (so compilacao, por declaracao: " .. tostring(gRes.erro) .. ")")
			end
		end
		if tc.deve == "ok" and tc.gera ~= false then
			local ok1, c1 = compilador.Compilar(tc.fonte, tc.arquivos)
			if ok1 then
				local yash2 = compilador.Descompilar(c1)
				local ok2, c2 = compilador.Compilar(yash2, tc.arquivos)
				if not ok2 then
					rtFalhas = rtFalhas + 1
					print("[RT FALHOU] " .. tc.nome .. " (recompilar descompilada)")
					print("    erro: " .. tostring(c2 and c2.erro) .. " (linha " .. tostring(c2 and c2.linha) .. ")")
					print("    descompilado:")
					for linha in yash2:gmatch("([^\n]*)\n") do print("      | " .. linha) end
				else
					-- Fixture que o GERADOR nao aceita (ex.: usa "Botao" sem
					-- declarar "usar"). Nao e falha de round-trip; e fixture
					-- invalida para geracao. Conta separadamente.
					local g1, luau1 = gerador.GerarLuau(c1, { contexto = tc.contexto or "comum", modulo = tc.modulo })
					if not g1 then
						-- Fixture marcado como geravel que parou de gerar = regressao.
						rtFalhas = rtFalhas + 1
						print("[RT FALHOU] " .. tc.nome .. " (esperava gerar Luau: " .. tostring(luau1.erro) .. ")")
					else
						-- Round-trip SEMANTICO: o Luau gerado a partir da fonte
						-- descompilada precisa ser identico ao da fonte original.
						local ctx = { contexto = tc.contexto or "comum", modulo = tc.modulo }
						local g2, luau2 = gerador.GerarLuau(c2, ctx)
						if not g2 then
							rtFalhas = rtFalhas + 1
							print("[RT FALHOU] " .. tc.nome .. " (recompilado nao gera: " .. tostring(luau2.erro) .. ")")
							print("    descompilado:")
							for linha in yash2:gmatch("([^\n]*)\n") do print("      | " .. linha) end
						elseif luau1 ~= luau2 then
							rtFalhas = rtFalhas + 1
							print("[RT FALHOU] " .. tc.nome .. " (Luau gerado divergiu no round-trip)")
							print("    descompilado:")
							for linha in yash2:gmatch("([^\n]*)\n") do print("      | " .. linha) end
							print("    esperado:")
							for linha in luau1:gmatch("([^\n]*)\n") do print("      | " .. linha) end
							print("    obtido:")
							for linha in luau2:gmatch("([^\n]*)\n") do print("      | " .. linha) end
						else
							print("[RT OK] " .. tc.nome)
						end
				end
			end
		end
	end
	end
	print("")
	print("--- " .. somenteCompilacao .. " fixture(s) sao de so compilacao (gera = false) ---")
	if rtFalhas == 0 then
		print(">>> ROUND-TRIP OK")
		os.exit(0)
	else
		print(">>> " .. rtFalhas .. " ROUND-TRIP FALHOU")
		os.exit(1)
	end
end

rodarRodada()
