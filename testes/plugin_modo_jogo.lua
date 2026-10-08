--[[
  Teste do pipeline do plugin YashScript V7.1 (caminho direto, sem Runtime).

  Aqui NAO se testa a UI: testa-se exatamente a logica que os botoes "Gravar" e
  "Validar" chamam — opcoesDoAlvo() + gerarLuau() — contra as fontes reais do
  plugin, carregadas de texto. O que o console aprova tem de ser o mesmo que
  vai para o Source.

  Invariante central do V7.1: o Luau gerado nao contem NENHUM vesticio da
  arquitetura antiga — nem _YashConfig, nem Runtime, nem marcadores --YASHC1/2--.
]]

local ENTRADA = _G.ENTRADA or {}
local carregarTexto = loadstring or load

local compilador = assert(carregarTexto(ENTRADA.compiladorFonte))()
local gerador = assert(carregarTexto(ENTRADA.geradorFonte))()
assert(type(gerador.GerarLuau) == "function", "GerarLuau nao encontrado no gerador")

local arquivos = ENTRADA.arquivos or {}

local falhas = 0
local function checar(cond, nome, detalhe)
	if cond then
		print("[OK] " .. nome)
	else
		falhas = falhas + 1
		print("[FALHOU] " .. nome .. (detalhe and (" -> " .. tostring(detalhe)) or ""))
	end
end

-- busca literal (sem padroes Lua) para assertar trechos exatos do Luau
local function contem(luau, trecho)
	return luau:find(trecho, 1, true) ~= nil
end

-- ------------------------------------------------------------------
-- replicas das funcoes do plugin (mesma logica, sem Instance/UI)
-- ------------------------------------------------------------------

-- contexto vem da CLASSE do alvo, nunca do texto
local function opcoesDoAlvo(classe, ancestraGui)
	local opcoes = { modulo = false }
	if classe == "ModuleScript" then
		opcoes.contexto = "comum"
		opcoes.modulo = true
	elseif classe == "LocalScript" then
		opcoes.contexto = "cliente"
	else
		opcoes.contexto = "servidor"
	end
	opcoes.ancestraGui = ancestraGui
	return opcoes
end

-- mesmo pipeline de gerarLuau() no plugin
-- Contrato do Gerador: (true, luau) ou (false, { erro = ..., linha = ... })
local function gerarLuau(yash, opcoes)
	local ok, res = compilador.Compilar(yash or "", arquivos)
	if not ok then
		return nil, res and res.erro or "erro desconhecido de compilacao"
	end
	-- mesma forma do plugin: closure em vez de referencia direta
	local gok, g1, g2 = pcall(function()
		return gerador.GerarLuau(res, opcoes)
	end)
	if not gok then
		return nil, "erro ao gerar Luau: " .. tostring(g1)
	end
	if g1 ~= true then
		local msg = type(g2) == "table" and (g2.erro or "erro desconhecido") or tostring(g2)
		return nil, msg
	end
	return g2, nil
end

-- qualquer vesticio do caminho legado no Luau gerado e falha
local function semVestigios(luau)
	local proibidos = {
		{ pat = "_YashConfig", nome = "_YashConfig" },
		{ pat = "Runtime%.", nome = "Runtime." },
		{ pat = "YASHC1", nome = "marcador --YASHC1--" },
		{ pat = "YASHC2", nome = "marcador --YASHC2--" },
		{ pat = "ReplicatedStorage:Yash", nome = "ReplicatedStorage.Yash" },
		{ pat = "YASHSCRIPT", nome = "marker YASHSCRIPT:" },
	}
	for _, p in ipairs(proibidos) do
		if luau:find(p.pat) then
			return p.nome
		end
	end
	return nil
end

-- ------------------------------------------------------------------
-- 1) milestone: clique num botao dentro da GUI (caso de referencia)
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Botao" = StarterGui.ScreenGui.Painel.Botao

quando clicar Botao
    print("clicou")
fim
]]
	local opcoes = opcoesDoAlvo("LocalScript", { "ScreenGui", "Painel" })
	local luau, erro = gerarLuau(fonte, opcoes)
	checar(luau ~= nil, "milestone: gera Luau", erro)
	if luau then
		checar(semVestigios(luau) == nil,
			"milestone: sem vesticio legado", semVestigios(luau))
		checar(luau:find("local _raiz = script:IsA") ~= nil,
			"milestone: usa _raiz (ancestral ScreenGui)")
		-- com ancestral, o ScreenGui NAO e esperado: resolvemos a partir dele
		checar(luau:find('WaitForChild%("ScreenGui') == nil,
			"milestone: nao espera o ScreenGui (resolve pelo ancestral)")
		checar(luau:find(":Connect%(") ~= nil, "milestone: conecta no evento")
		checar(luau:find("print%(") ~= nil, "milestone: mantem o print")
		checar(luau:find("return ") == nil, "milestone: LocalScript nao retorna tabela")
	end
end

-- ------------------------------------------------------------------
-- "quando Botao clicar" (sujeito antes do evento) precisa produzir o mesmo
-- Luau que "quando clicar Botao" (alvo depois do evento)
-- ------------------------------------------------------------------
do
	local yashSujeito = [==[
usar "Botao" = StarterGui.ScreenGui.Painel.Botao

quando Botao clicar
    print("a")
fim
]==]
	local yashDepois = 'usar "Botao" = StarterGui.ScreenGui.Painel.Botao\n\nquando clicar Botao\n    print("a")\nfim\n'

	local luauSub, erroSub = gerarLuau(yashSujeito, opcoesDoAlvo("LocalScript", { "ScreenGui", "Painel" }))
	local luauDep, erroDep = gerarLuau(yashDepois, opcoesDoAlvo("LocalScript", { "ScreenGui", "Painel" }))

	checar(luauSub ~= nil, "evento com sujeito: gera Luau", erroSub)
	checar(luauDep ~= nil, "evento com alvo depois: gera Luau", erroDep)
	if luauSub and luauDep then
		checar(luauSub == luauDep,
			"evento: as duas formas produzem Luau identico",
			luauSub == luauDep and "" or "divergiram:\n--- sujeito ---\n" .. luauSub .. "\n--- depois ---\n" .. luauDep)
		checar(luauSub:find("Botao%.MouseButton1Click:Connect") ~= nil,
			"evento: conecta em MouseButton1Click")
	end
end

-- ------------------------------------------------------------------
-- 2) contexto cliente SEM ancestral: precisa passar por PlayerGui
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Rotulo" = StarterGui.Rotulo

quando clicar Rotulo
    print("oi")
fim
]]
	local luau = gerarLuau(fonte, opcoesDoAlvo("LocalScript"))
	checar(luau ~= nil, "cliente sem ancestral: gera Luau")
	if luau then
		checar(luau:find("PlayerGui") ~= nil, "cliente sem ancestral: usa PlayerGui")
		checar(luau:find("_raiz") == nil, "cliente sem ancestral: nao usa _raiz")
	end
end

-- ------------------------------------------------------------------
-- 3) servidor: contexto "servidor", sem ClientStarterGui
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Cubo" = Workspace.Cubo

quando tocar Cubo
    Cubo.Transparency = 0.5
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("Script"))
	checar(luau ~= nil, "servidor: gera Luau", erro)
	if luau then
		checar(semVestigios(luau) == nil, "servidor: sem vesticio legado", semVestigios(luau))
		checar(luau:find("ClientStarterGui") == nil, "servidor: nao menciona ClientStarterGui")
		checar(luau:find("Players") == nil, "servidor: nao menciona Players")
		checar(luau:find("Transparency") ~= nil, "servidor: escreve a propriedade")
	end
end

-- ------------------------------------------------------------------
-- 4) ModuleScript: contexto comum + return de tabela
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Modulo" = ReplicatedStorage.Pasta.Modulo
usar "Valor" = 7
usar "Nome" = "pasta"

print(Modulo)
print(Valor)
print(Nome)
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("ModuleScript"))
	checar(luau ~= nil, "modulo: gera Luau", erro)
	if luau then
		checar(luau:find("return ") ~= nil, "modulo: retorna tabela")
		checar(luau:find("ReplicatedStorage") ~= nil, "modulo: resolve o caminho compartilhado")
		checar(semVestigios(luau) == nil, "modulo: sem vesticio legado", semVestigios(luau))
	end
end

-- ------------------------------------------------------------------
-- 5) fontes reais: exemplos do repositorio
--    (o pipeline novo aceita o que ja foi migrado; o que falta da erro)
-- ------------------------------------------------------------------
do
	for _, nome in ipairs({ "jogo.yash", "main.yash", "visual.yash" }) do
		local yash = arquivos[nome]
		if yash then
			local luau, erro = gerarLuau(yash, opcoesDoAlvo("Script"))
			if luau then
				checar(semVestigios(luau) == nil, nome .. ": sem vesticio legado", semVestigios(luau))
			else
				-- construcao ainda nao migrada: a rejeicao tem que ser explicita,
				-- nunca um Luau silenciosamente errado
				checar(type(erro) == "string" and #erro > 0,
					nome .. ": rejeicao explicita quando nao migrado", erro)
			end
		end
	end
end

-- ------------------------------------------------------------------
-- 6) rejeicoes explicitas: nao pode gerar Luau invalido em silencio
-- ------------------------------------------------------------------
do
	local casos = {
		{
			nome = "construcao nao migrada",
			fonte = "criar elemento 'Painel'\n    texto = \"oi\"\nfim\n",
		},
		{
			nome = "alvo de evento inexistente",
			fonte = "quando clicar Jogar\n    print(\"oi\")\n",
		},
		{
			nome = "sintaxe invalida",
			fonte = "quando isso nao fecha\n",
		},
	}
	for _, caso in ipairs(casos) do
		local luau, erro = gerarLuau(caso.fonte, opcoesDoAlvo("Script"))
		checar(luau == nil, caso.nome .. ": rejeitado (nao gera Luau)")
		checar(type(erro) == "string" and #erro > 5,
			caso.nome .. ": mensagem de erro preenchida", erro)
	end
end

-- ------------------------------------------------------------------
-- 7) o Luau gerado tem de carregar como chunk (Luau puro de verdade)
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Cubo" = Workspace.Cubo

quando tocar Cubo
    Cubo.Transparency = 0.5
fim
]]
	local luau = gerarLuau(fonte, opcoesDoAlvo("Script"))
	checar(luau ~= nil, "chunk: gera Luau")
	if luau then
		local fn, msg = carregarTexto(luau)
		checar(type(fn) == "function", "chunk: Luau gerado carrega", msg)
	end
end

-- ------------------------------------------------------------------
-- 8) exemplo do pedido original: usar + clicar + print + visivel = falso
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Jogar" = StarterGui.ScreenGui.Frame.Jogar

quando clicar Jogar
    print("CLICOU NO JOGAR")
    Jogar.visivel = falso
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("LocalScript", { "ScreenGui", "Frame" }))
	checar(luau ~= nil, "exemplo: gera Luau", erro)
	if luau then
		checar(contem(luau, 'local Jogar = _raiz:WaitForChild("Frame"):WaitForChild("Jogar")'),
			"exemplo: alias resolve pelo ancestral ScreenGui")
		checar(contem(luau, "Jogar.MouseButton1Click:Connect(function()"),
			"exemplo: conecta o clique")
		checar(contem(luau, 'print("CLICOU NO JOGAR")'), "exemplo: print no corpo")
		checar(contem(luau, "Jogar.Visible = false"), "exemplo: visivel = falso vira Visible = false")
		checar(semVestigios(luau) == nil, "exemplo: sem vesticio legado", semVestigios(luau))
	end
end

-- ------------------------------------------------------------------
-- 9) §8: referencia por hierarquia, SEM `usar`
--    script dentro de ScreenGui > Frame; `Jogar` e filho de Frame
-- ------------------------------------------------------------------
do
	local fonte = [[
quando clicar Jogar
    print("CLICOU NO JOGAR")
    Jogar.visivel = falso
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("LocalScript", { "ScreenGui", "Frame" }))
	checar(luau ~= nil, "hierarquia: Jogar resolve sem usar", erro)
	if luau then
		checar(contem(luau, '_raiz:WaitForChild("Frame"):WaitForChild("Jogar")'),
			"hierarquia: caminho parte do script.Parent")
		checar(contem(luau, '.MouseButton1Click:Connect(function()'),
			"hierarquia: conecta no clique do Jogar")
		checar(contem(luau, 'print("CLICOU NO JOGAR")'), "hierarquia: mantem o print")
		checar(contem(luau, 'Jogar").Visible = false'),
			"hierarquia: visivel = falso vira Visible = false")
		checar(luau:find("return ") == nil,
			"hierarquia: evento sem argumento nao ganha return")
		checar(semVestigios(luau) == nil, "hierarquia: sem vesticio legado", semVestigios(luau))
		local fn, msg = carregarTexto(luau)
		checar(type(fn) == "function", "hierarquia: Luau gerado carrega", msg)
	end
end

-- ------------------------------------------------------------------
-- 10) `quando tocar Moeda` no caminho direto: Touched + debounce 0.4s
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Moeda" = Workspace.Moeda

quando tocar Moeda
    print("tocou")
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("Script"))
	checar(luau ~= nil, "tocar: gera Luau", erro)
	if luau then
		checar(semVestigios(luau) == nil, "tocar: sem vesticio legado", semVestigios(luau))
		checar(contem(luau, "Moeda.Touched:Connect(function(_alvo)"),
			"tocar: conecta em Touched com o argumento")
		checar(contem(luau, "local _ultimoToque = 0"),
			"tocar: declara o ultimo toque por evento")
		checar(contem(luau, "os.clock()"), "tocar: debounce usa os.clock()")
		checar(contem(luau, "- _ultimoToque < 0.4 then return end"),
			"tocar: janela de debounce de 0.4s")
		checar(not contem(luau, "IsDescendantOf"),
			"tocar sem sujeito: nenhuma guarda de sujeito")
		local fn, msg = carregarTexto(luau)
		checar(type(fn) == "function", "tocar: Luau gerado carrega", msg)
	end
end

-- ------------------------------------------------------------------
-- 11) `quando jogador tocar Moeda`: sujeito logico exige Humanoid
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Moeda" = Workspace.Moeda

quando jogador tocar Moeda
    print("jogador tocou")
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("Script"))
	checar(luau ~= nil, "tocar jogador: gera Luau", erro)
	if luau then
		checar(contem(luau, 'FindFirstAncestorOfClass("Model")'),
			"tocar jogador: procura o personagem do tocador")
		checar(contem(luau, 'FindFirstChildOfClass("Humanoid")'),
			"tocar jogador: exige Humanoid no personagem")
		checar(not contem(luau, "IsDescendantOf"),
			"tocar jogador: sem comparacao de objetos")
		local fn, msg = carregarTexto(luau)
		checar(type(fn) == "function", "tocar jogador: Luau gerado carrega", msg)
	end
end

-- ------------------------------------------------------------------
-- 12) `quando Cubo tocar Moeda`: sujeito objeto, guarda nas duas direcoes
--     e o personagem do tocador contam -- ordem do Runtime legado
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Moeda" = Workspace.Moeda
usar "Cubo" = Workspace.Cubo

quando Cubo tocar Moeda
    print("o cubo tocou a moeda")
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("Script"))
	checar(luau ~= nil, "tocar Cubo: gera Luau", erro)
	if luau then
		checar(contem(luau, "_alvo:IsDescendantOf(Cubo) or Cubo:IsDescendantOf(_alvo)"),
			"tocar Cubo: compara as DUAS direcoes")
		checar(contem(luau, "_personagem:IsDescendantOf(Cubo) or Cubo:IsDescendantOf(_personagem)"),
			"tocar Cubo: cobre o personagem de quem tocou")
		checar(contem(luau, "if not _doSujeito then return end"),
			"tocar Cubo: guarda de sujeito presente")
		local posGuarda = luau:find("_doSujeito", 1, true)
		local posDebounce = luau:find("- _ultimoToque <", 1, true)
		checar(posGuarda and posDebounce and posGuarda < posDebounce,
			"tocar Cubo: sujeito ANTES do debounce (nao consome a janela)")
		local fn, msg = carregarTexto(luau)
		checar(type(fn) == "function", "tocar Cubo: Luau gerado carrega", msg)
	end
end

-- ------------------------------------------------------------------
-- 13) `encostar` e sinonimo de `tocar` (Touched) em todas as formas
-- ------------------------------------------------------------------
do
	local fonte = [[
usar "Moeda" = Workspace.Moeda

quando encostar Moeda
    print("encostou")
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("Script"))
	checar(luau ~= nil, "encostar: gera Luau", erro)
	if luau then
		checar(contem(luau, "Moeda.Touched:Connect"),
			"encostar: conecta no mesmo Touched de tocar")
	end

	local fonteSujeito = [[
usar "Moeda" = Workspace.Moeda
usar "Cubo" = Workspace.Cubo

quando Cubo encostar Moeda
    print("encostou")
fim
]]
	local luau2, erro2 = gerarLuau(fonteSujeito, opcoesDoAlvo("Script"))
	checar(luau2 ~= nil, "encostar com sujeito: gera Luau", erro2)
	if luau2 then
		checar(contem(luau2, "_doSujeito"), "encostar com sujeito: guarda presente")
	end
end

-- ------------------------------------------------------------------
-- 14) rejeicoes explicitas do caminho de eventos de toque
-- ------------------------------------------------------------------
do
	local casos = {
		{
			nome = "evento iniciar nao aceita sujeito",
			fonte = "quando jogador iniciar\n    print(\"oi\")\nfim\n",
		},
		{
			nome = "sujeito de tocar sem alias nem servico",
			fonte = "usar \"Moeda\" = Workspace.Moeda\n\nquando desconhecido tocar Moeda\n    print(\"oi\")\nfim\n",
		},
	}
	for _, caso in ipairs(casos) do
		local luau, erro = gerarLuau(caso.fonte, opcoesDoAlvo("Script"))
		checar(luau == nil, caso.nome .. ": rejeitado (nao gera Luau)")
		checar(type(erro) == "string" and #erro > 5,
			caso.nome .. ": mensagem de erro preenchida", erro)
	end
end

-- ------------------------------------------------------------------
-- 15) Animacoes/TweenService: tween de propriedades, efeitos com
--     parametros, `criar animacao` + `executar`, e rejeicoes
-- ------------------------------------------------------------------
do
	-- 15a) tween puro de propriedades dentro de um evento
	local fonte = [[
usar "Botao" = StarterGui.ScreenGui.Frame.Botao

quando clicar Botao
    animar("Botao") posicao = (0, 100) + rotacao = 45 + duracao = 0.5
fim
]]
	local luau, erro = gerarLuau(fonte, opcoesDoAlvo("LocalScript", { "ScreenGui", "Frame" }))
	checar(luau ~= nil, "tween: gera Luau", erro)
	if luau then
		checar(contem(luau, "TweenService:Create(_alvo, TweenInfo.new(0.5"),
			"tween: cria via TweenService:Create com alvo")
		checar(contem(luau, "TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)"),
			"tween: TweenInfo com duracao pedida e defaults Quad/Out")
		checar(contem(luau, "Position = UDim2.fromOffset(0, 100),"),
			"tween: posicao vira goal UDim2")
		checar(contem(luau, "Rotation = 45,"),
			"tween: numero solto vira goal numerico")
		checar(contem(luau, "}):Play()"),
			"tween: chama Play() no encadeamento")
		checar(semVestigios(luau) == nil, "tween: sem vestigios de Runtime")
		local fn, msg = carregarTexto(luau)
		checar(type(fn) == "function", "tween: Luau gerado carrega", msg)
	end

	-- 15b) efeito `fade in` como sufixo de `mostrar`: suprime o bloco base
	local fonteFade = [[
usar "Painel" = StarterGui.ScreenGui.Painel

quando iniciar
    mostrar(Painel) animacao = fade in
fim
]]
	local luauFade, erroFade = gerarLuau(fonteFade, opcoesDoAlvo("LocalScript", { "ScreenGui" }))
	checar(luauFade ~= nil, "fade mostrar: gera Luau", erroFade)
	if luauFade then
		checar(contem(luauFade, "_alvo:IsA(\"CanvasGroup\")"),
			"fade mostrar: cadeia IsA por classe de GUI")
		checar(contem(luauFade, "_alvo.Visible = true"),
			"fade mostrar: torna visivel antes do fade")
		checar(contem(luauFade, "_metas.GroupTransparency = 0"),
			"fade mostrar: goal de GroupTransparency para CanvasGroup")
		checar(not contem(luauFade, "Painel.Visible = true"),
			"fade mostrar: suprime o bloco base de `mostrar`")
		local fnF, msgF = carregarTexto(luauFade)
		checar(type(fnF) == "function", "fade mostrar: Luau gerado carrega", msgF)
	end

	-- 15c) `criar animacao` + `executar` + efeito `pulsar` com volta
	local fontePulsar = [[
YASHSCRIPT:

criar animacao 'pulsar'
    animacao = crescer + escala = 1.4 + duracao = 0.2
    animacao = diminuir + escala = 0.75 + duracao = 0.2
fim

usar "Botao" = StarterGui.ScreenGui.Botao

quando clicar Botao
    animar("Botao") pulsar
    executar animacao pulsar
    animar("Botao") animacao = pulsar
fim
]]
	local luauP, erroP = gerarLuau(fontePulsar, opcoesDoAlvo("LocalScript", { "ScreenGui" }))
	checar(luauP ~= nil, "pulsar/executar: gera Luau", erroP)
	if luauP then
		checar(contem(luauP, "local _anim_pulsar")
			and contem(luauP, "_anim_pulsar = function(inst)"),
			"pulsar/executar: animacao criada vira funcao local")
		checar(contem(luauP, "task.wait(0.25)"),
			"pulsar/executar: espera duracao+0.05 entre passos")
		checar(contem(luauP, "task.spawn(function() _anim_pulsar(Botao) end)"),
			"pulsar/executar: executar animacao chama a funcao em spawn")
		checar(contem(luauP, "local _tamanho = _alvo.Size"),
			"pulsar: captura tamanho atual para voltar")
		checar(contem(luauP, "task.delay("),
			"pulsar: agenda a volta apos metade da duracao")
		local fnP, msgP = carregarTexto(luauP)
		checar(type(fnP) == "function", "pulsar/executar: Luau gerado carrega", msgP)
	end

	-- 15d) rejeicoes explicitas do caminho de animacao
	local casosAnim = {
		{
			nome = "tween de texto",
			fonte = "usar \"Botao\" = Workspace.Botao\n\nquando iniciar\n    animar(\"Botao\") texto = \"oi\"\nfim\n",
		},
		{
			nome = "efeito desconhecido",
			fonte = "usar \"Botao\" = Workspace.Botao\n\nquando iniciar\n    animar(\"Botao\") desconhecido\nfim\n",
		},
		{
			nome = "executar animacao inexistente",
			fonte = "usar \"Botao\" = Workspace.Botao\n\nquando iniciar\n    executar animacao fantasma\nfim\n",
		},
	}
	for _, caso in ipairs(casosAnim) do
		local luauR, erroR = gerarLuau(caso.fonte, opcoesDoAlvo("Script"))
		checar(luauR == nil, caso.nome .. ": rejeitado (nao gera Luau)")
		checar(type(erroR) == "string" and #erroR > 5,
			caso.nome .. ": mensagem de erro preenchida", erroR)
	end
end

print("")
if falhas == 0 then
	print(">>> MODO JOGO OK")
	os.exit(0)
else
	print(">>> " .. falhas .. " FALHA(S) NO MODO JOGO")
	os.exit(1)
end
