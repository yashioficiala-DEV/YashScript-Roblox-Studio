--[[
  YashScript V8.1 — Gerador de Luau

  Recebe o PROGRAMA (a estrutura devolvida por compilador.Compilar) e devolve
  Luau puro, pronto para o Source de um Script / LocalScript / ModuleScript.

    YashScript  ->  Compilar  ->  programa  ->  GerarLuau  ->  Luau

  Regras desta camada:
    * nada de `_YashConfig`, nada de interpretador, nada de marcador;
    * cada construção do YashScript vira a instrução Luau equivalente;
    * o contexto (servidor / cliente / comum) é informado pelo PLUGIN e vem da
      classe do script alvo -- nunca do texto-fonte;
    * referências à árvore do Roblox são resolvidas semanticamente: em cliente,
      `StarterGui` vira `PlayerGui`; se o script já estiver dentro de um
      ScreenGui, a resolução parte do ancestral, não do serviço.

  Uso:
    local Gerador = require(script.gerador)
    local ok, luau = Gerador.GerarLuau(programa, {
      contexto = "cliente",              -- "servidor" | "cliente" | "comum"
      ancestraGui = {"ScreenGui","Frame"}, -- nomes do ScreenGui ate script.Parent
      modulo = false,                    -- true = ModuleScript (retorna tabela)
    })
    -- ok = false -> luau = { erro = "mensagem", linha = n }
]]

local Gerador = { VERSAO = "8.1" }

local JUNTAR = table.concat

-----------------------------------------------------------------------
-- dicionarios de traducao
-----------------------------------------------------------------------

-- Servicos do Roblox conhecidos pelo nome em portugues/ingles.
-- Valor = nome canonico; o gerador emite game:GetService("<canonico>").
local SERVICOS = {
	workspace = "Workspace",
	replicatedstorage = "ReplicatedStorage",
	serverstorage = "ServerStorage",
	serverscriptservice = "ServerScriptService",
	players = "Players",
	lighting = "Lighting",
	runservice = "RunService",
	userinputservice = "UserInputService",
	tweenservice = "TweenService",
	soundservice = "SoundService",
	debris = "Debris",
	debrisservice = "Debris",
	debisservice = "Debris",
	contextactionservice = "ContextActionService",
	httpservice = "HttpService",
	datastoreservice = "DataStoreService",
	marketplaceservice = "MarketplaceService",
	collectionservice = "CollectionService",
	physicsservice = "PhysicsService",
	textchatservice = "TextChatService",
	chatwindowconfiguration = "ChatWindowConfiguration",
	startergui = "StarterGui",
	starterpack = "StarterPack",
}

-- Construtores e namespaces globais do Luau/Roblox que podem ser usados em
-- expressoes (por exemplo Instance.new, Vector3.new e Enum.Material.Neon).
-- Eles sao encaminhados literalmente; nomes fora desta lista continuam
-- exigindo alias, local, funcao declarada ou servico conhecido.
local GLOBAIS_LUAU = {
	Instance = true, Enum = true, Vector2 = true, Vector3 = true,
	Vector2int16 = true, Vector3int16 = true, CFrame = true, Color3 = true,
	UDim = true, UDim2 = true, BrickColor = true, TweenInfo = true,
	Ray = true, RaycastParams = true, OverlapParams = true, Region3 = true,
	Region3int16 = true, NumberRange = true, NumberSequence = true,
	NumberSequenceKeypoint = true, ColorSequence = true,
	ColorSequenceKeypoint = true, PhysicalProperties = true, Rect = true,
	Axes = true, Faces = true, Font = true, DateTime = true, Random = true,
	SharedTable = true, task = true, math = true, string = true, table = true,
	utf8 = true, os = true, coroutine = true, debug = true, bit32 = true,
	buffer = true,
}

local FUNCOES_LUAU = {
	assert = true, error = true, ipairs = true, pairs = true, next = true,
	pcall = true, xpcall = true, select = true, tonumber = true,
	tostring = true, type = true, typeof = true, unpack = true, print = true,
	warn = true, rawget = true, rawset = true, rawequal = true, rawlen = true,
	getmetatable = true, setmetatable = true, require = true,
}

-- Onde cada servico realmente esta quando o codigo roda no CLIENTE.
-- `StarterGui` e `PlayerGui` nao sao o mesmo objeto em runtime, entao o
-- gerador traduz em vez de indexar direto.
local SERVICOS_CLIENTE = {
	startergui = 'Players.LocalPlayer:WaitForChild("PlayerGui")',
}

-- Propriedades YashScript -> propriedade real do Roblox.
-- Adicionar uma traducao nova e UMA LINHA nesta tabela.
local PROPRIEDADES = {
	visivel = "Visible",
	texto = "Text",
	vida = "Health",
	health = "Health",
	vida_maxima = "MaxHealth",
	max_vida = "MaxHealth",
	maxhealth = "MaxHealth",
	velocidade = "WalkSpeed",
	walkspeed = "WalkSpeed",
	jumppower = "JumpPower",
	position = "Position",
	size = "Size",
	cframe = "CFrame",
	currentcamera = "CurrentCamera",
	name = "Name",
	parent = "Parent",
	transparency = "Transparency",
	visible = "Visible",
	enabled = "Enabled",
	ancorado = "Anchored",
	anchored = "Anchored",
	colisao = "CanCollide",
	cancollide = "CanCollide",
	material = "Material",
	color = "Color",
	rotation = "Rotation",
	transparente = "Transparency",
	posicao_3d = "Position",
	cor_3d = "Color",
	placeholder = "PlaceholderText",
	transparencia = "BackgroundTransparency",
	cor = "BackgroundColor3",
	cor_fundo = "BackgroundColor3",
	cor_texto = "TextColor3",
	cor_borda = "BorderColor3",
	borda = "BorderSizePixel",
	tamanho_fonte = "TextSize",
	fonte = "Font",
	imagem = "Image",
	ativo = "Active",
	selecionavel = "Selectable",
	auto = "AutoButtonColor",
	layout_order = "LayoutOrder",
	layout = "LayoutOrder",
	anchor_point = "AnchorPoint",
	z_index = "ZIndex",
	grupo = "GroupColor3",
	rotacao = "Rotation",
	estado = "State",
	modal = "Modal",
	exclusivo = "Exclusive",
	reset = "ResetOnSpawn",
	encerrado = "CloseOnEscape",
	tamanho = "Size",
	posicao = "Position",
	distancia_lateral = "AbsolutePosition",
	tamanho_absoluto = "AbsoluteSize",
}

-- Propriedades que recebem UDim2 quando o valor e uma tupla (x, y[, z]).
-- Qualquer outra tupla vira Vector3.new.
local PROPS_UDIM2 = {
	posicao = true, tamanho = true,
	distancia_lateral = true, tamanho_absoluto = true,
	position = true, size = true,
}

-- Propriedades cujo valor e booleano (aceitam os verbos do YashScript).
local PROPS_BOOL = {
	visivel = true, ativo = true, selecionavel = true, auto = true,
	modal = true, reset = true,
}

-- Eventos YashScript -> evento Roblox.
-- `argumento = true` significa que o callback recebe o parametro do evento.
-- `repete = true` significa que o Roblox dispara o evento muitas vezes seguidas
-- (Touched): o gerador aplica o mesmo debounce de 0.4s do Runtime legado.
local EVENTOS = {
	clicar = { evento = "MouseButton1Click", argumento = false },
	mouse_em = { evento = "MouseEnter", argumento = false },
	mouse_sair = { evento = "MouseLeave", argumento = false },
	tocar = { evento = "Touched", argumento = true, repete = true },
	encostar = { evento = "Touched", argumento = true, repete = true },
}

-- Eventos sem alvo: executam inline, sem Connect.
local EVENTOS_INLINE = {
	iniciar = true, carregar = true,
}

-- Sujeitos logicos em `quando <sujeito> tocar <alvo>`: nao existem na arvore,
-- representam QUEM encosta. O gerador exige um Humanoid no que tocou (mesma
-- condicao que o Runtime legado usava para sujeito que nao era um objeto).
local SUJEITOS_LOGICOS = {
	jogador = true,
	player = true,
}

local DEBOUNCE_TOQUE = 0.4

-- Efeitos de animacao reconhecidos e seus sinonimos. O valor canonico e a
-- chave dos emissores de efeito (fade in, fade out, slide left, ...).
local EFEITOS = {
	["fade in"] = "fade in", aparecer = "fade in",
	["fade out"] = "fade out", desaparecer = "fade out", sumir = "fade out",
	["slide left"] = "slide left", esquerda = "slide left",
	["slide esquerda"] = "slide left",
	["slide right"] = "slide right", direita = "slide right",
	["slide direita"] = "slide right",
	["slide up"] = "slide up", subir = "slide up", cima = "slide up",
	["slide cima"] = "slide up",
	["slide down"] = "slide down", descer = "slide down", baixo = "slide down",
	["slide baixo"] = "slide down",
	pulsar = "pulsar", pulse = "pulsar",
	girar = "girar", spin = "girar",
	crescer = "crescer", aumentar = "crescer",
	diminuir = "diminuir", encolher = "diminuir",
}

-- Parametros extras que cada efeito aceita (alem de duracao/estilo/direcao).
local EFEITO_PARAMS = {
	["fade in"] = {}, ["fade out"] = {},
	["slide left"] = { delta = true }, ["slide right"] = { delta = true },
	["slide up"] = { delta = true }, ["slide down"] = { delta = true },
	pulsar = { escala = true }, crescer = { escala = true },
	diminuir = { escala = true }, girar = { graus = true },
}

-- estilo de suavizacao -> Enum.EasingStyle
local ESTILOS_EASING = {
	linear = "Linear",
	suave = "Sine", sine = "Sine", senoidal = "Sine",
	quad = "Quad", quadratico = "Quad",
	cubico = "Cubic", cubic = "Cubic",
	quart = "Quart", quartico = "Quart",
	quint = "Quint", quintico = "Quint",
	exponencial = "Exponential", expo = "Exponential",
	circular = "Circular", circ = "Circular",
	elastico = "Elastic", elastic = "Elastic",
	ressalto = "Bounce", bounce = "Bounce",
	voltar = "Back", back = "Back",
}

-- direcao do easing -> Enum.EasingDirection
local DIRECOES_EASING = {
	entrada = "In", ["in"] = "In",
	saida = "Out", ["out"] = "Out",
	entrada_saida = "InOut", inout = "InOut",
}

-- palavras reservadas do Luau: nao podem virar identificador
local PALAVRAS_LUA = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
	["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true,
}

-----------------------------------------------------------------------
-- utilidades de texto
-----------------------------------------------------------------------

local function numeroLua(v)
	if type(v) ~= "number" then return "0" end
	if v ~= v or v == math.huge or v == -math.huge then return "0" end
	if v == math.floor(v) and math.abs(v) < 1e15 then
		return string.format("%d", v)
	end
	-- Menor representacao decimal que volta EXATAMENTE ao mesmo numero.
	-- (%.6f truncava: 0.7142857 virava 0.714286 e 1e-7 virava 0.)
	local s = string.format("%.15g", v)
	if tonumber(s) ~= v then s = string.format("%.17g", v) end
	-- Luau aceita notacao cientifica; um flutuante inteiro precisa de ponto
	if not s:find("[%.eE]") then s = s .. ".0" end
	return s
end

-- Escape de texto em estilo Luau, de forma canonica e independente do host.
-- Deve ficar IDENTICO ao de compilador/compilador.lua: os dois participates do
-- ciclo compilar -> gerar -> descompilar -> compilar.
local function escaparTexto(s)
	s = tostring(s)
	s = s:gsub("\\", "\\\\")
	s = s:gsub("\"", "\\\"")
	s = s:gsub("\n", "\\n")
	s = s:gsub("\r", "\\r")
	s = s:gsub("\t", "\\t")
	s = s:gsub("[%z\1-\31\127]", function(c)
		return string.format("\\%03d", string.byte(c))
	end)
	return "\"" .. s .. "\""
end

local function textoLua(s)
	return escaparTexto(s)
end

-- Chaves em ordem estavel. Mesma politica do Compilador.Descompilar, para
-- que gerar e descompilar concordem sobre a ordem dos blocos de topo.
local function nomesOrdenados(tab)
	local nomes = {}
	for nome in pairs(tab or {}) do table.insert(nomes, nome) end
	table.sort(nomes, function(a, b) return tostring(a) < tostring(b) end)
	return nomes
end

local function identificadorValido(nome)
	return type(nome) == "string"
		and string.match(nome, "^[%a_][%w_]*$") ~= nil
		and not PALAVRAS_LUA[nome]
end

local function dividirCaminho(caminho)
	local partes = {}
	for p in string.gmatch(tostring(caminho), "[^%.]+") do
		table.insert(partes, p)
	end
	return partes
end

local function recuo(n)
	return string.rep("\t", n or 0)
end

-- normaliza "sim"/"verdadeiro"/"true" -> true; "nao"/"falso"/"false" -> false
local function normalizarBool(expr)
	if expr == nil then return nil end
	if expr.k == "bool" then return expr.v end
	if expr.k == "str" then
		local l = string.lower(string.gsub(tostring(expr.v), "%s+", ""))
		if l == "sim" or l == "verdadeiro" or l == "true" then return true end
		if l == "nao" or l == "falso" or l == "false" then return false end
	end
	return nil
end

-----------------------------------------------------------------------
-- Gerador
-----------------------------------------------------------------------

local function GerarLuau(programa, opcoes)
	programa = programa or {}
	opcoes = opcoes or {}

	local contexto = opcoes.contexto or "comum"
	if contexto ~= "servidor" and contexto ~= "cliente" and contexto ~= "comum" then
		return false, { erro = "contexto invalido: " .. tostring(contexto), linha = 0 }
	end

	local modulo = opcoes.modulo == true
	local ancestraGui = opcoes.ancestraGui

	-- estado da geracao -------------------------------------------------
	-- As linhas vao para uma PILHA de buffers. Cada bloco (corpo de `se`,
	-- callback de evento, corpo de `a cada`) e renderizado num buffer proprio
	-- com o recuo certo e so depois anexado onde pertence. Isso permite gerar
	-- TODO o codigo ANTES de montar o cabecalho, garantindo que um servico
	-- descoberto no meio de um corpo ja exista como `local` no topo.
	local linhas = {}          -- buffer raiz: o codigo ja montado
	local pilha = { { linhas = linhas, nivel = 0 } }
	local servicosUsados = {}  -- canonico -> nome da local
	local aliases = {}         -- nome YashScript -> nome Luau
	local objetosDados = {}     -- objetos lógicos declarados com `criar objeto`
	local LOCAIS_GERADOS = {   -- locais criadas pelo proprio gerador
		_alvo = true,
		_raiz = true,
		_personagem = true,
		_ultimoToque = true,
		_agora = true,
		_doSujeito = true,
		_vis = true,
		_tween = true,
		_metas = true,
		_pos = true,
		_tamanho = true,
		_metade = true,
		_humanoide = true,
		_alvoVida = true,
		_player = true,
		_personagemAlvo = true,
		_pivotInicial = true,
		_explosao = true,
		_som = true,
		_acao = true,
		_acaoAlvo = true,
		_tela = true,
		_frameRaiz = true,
	}
	local usadoRaiz = false    -- precisa da local do ScreenGui

	local function buffer() return pilha[#pilha].linhas end
	local function nivel() return pilha[#pilha].nivel end

	local function emitir(s)
		table.insert(buffer(), recuo(nivel()) .. s)
	end

	-- anexa linhas ja indentadas ao buffer atual
	local function anexar(ls)
		local b = buffer()
		for _, l in ipairs(ls) do table.insert(b, l) end
	end

	-- renderiza fn() num buffer novo com o recuo informado e devolve as linhas.
	-- NAO anexa ao pai: quem chama decide onde o bloco entra.
	local function blocoNovo(nivelBase, fn)
		table.insert(pilha, { linhas = {}, nivel = nivelBase })
		local ok, err = fn()
		local filho = table.remove(pilha)
		if not ok then return nil, err end
		return filho.linhas
	end

	-- garante uma local para o servico e devolve o nome dela
	local function servico(nomeCanonico)
		if servicosUsados[nomeCanonico] then return servicosUsados[nomeCanonico] end
		servicosUsados[nomeCanonico] = nomeCanonico
		return nomeCanonico
	end

	-----------------------------------------------------------------------
	-- resolucao de caminhos da arvore do Roblox
	-----------------------------------------------------------------------

	local function navegar(codigo, partes, ini)
		for i = ini, #partes do
			local seg = partes[i]
			local canonico = SERVICOS[string.lower(seg)]
			if canonico and canonico ~= "StarterGui" then
				codigo = codigo .. ':GetService("' .. canonico .. '")'
			else
				codigo = codigo .. ':WaitForChild("' .. seg .. '")'
			end
		end
		return codigo
	end

	-- devolve a expressao Luau para uma lista de segmentos:
	--   {"StarterGui","ScreenGui","Frame","Jogar"}
	-- `semArvoreGui` desliga a resolucao pela arvore do ScreenGui: e usado nos
	-- alvos/sujeitos de `tocar`, que nunca sao objetos de GUI.
	local function resolverCaminho(partes, semArvoreGui)
		if #partes == 0 then return nil, "caminho vazio" end

		local primeiro = partes[1]
		local baixo = string.lower(primeiro)

		-- 1) alias declarado com `usar`
		if aliases[primeiro] then
			local codigo = aliases[primeiro]
			for i = 2, #partes do codigo = codigo .. "." .. partes[i] end
			return codigo
		end

		-- 2) `game`
		if baixo == "game" then
			return navegar("game", partes, 2)
		end

		-- 2b) construtores e namespaces globais do ambiente Luau.
		if GLOBAIS_LUAU[primeiro] then
			return table.concat(partes, ".")
		end

		-- 3) servico conhecido
		local canonico = SERVICOS[baixo]
		if canonico then
			-- StarterGui em cliente nao e o mesmo objeto em runtime
			if contexto == "cliente" and SERVICOS_CLIENTE[baixo] then
				-- o script ja esta dentro de um ScreenGui? resolve pelo ancestral
				if ancestraGui and ancestraGui[1] and #partes >= 2
					and partes[2] == ancestraGui[1] then
					usadoRaiz = true
					return navegar("_raiz", partes, 3)
				end
				-- senao: PlayerGui
				servico("Players")
				return navegar(SERVICOS_CLIENTE[baixo], partes, 2)
			end

			-- demais contextos: acesso pelo servico real
			return navegar(servico(canonico), partes, 2)
		end

		-- 4) nome da propria arvore do GUI (cliente dentro de um ScreenGui):
		--    `Jogar` vira _raiz:WaitForChild(...) sem precisar de `usar`.
		--    Se o nome for um dos ancestrais do script, parte dele; senao,
		--    procura como filho de script.Parent (o ultimo nome do ancestral).
		if ancestraGui and #ancestraGui > 0 and not semArvoreGui then
			usadoRaiz = true
			local codigo = "_raiz"
			local corte = nil
			for i = 1, #ancestraGui do
				if ancestraGui[i] == primeiro then
					corte = i
					break
				end
			end
			if corte then
				for i = 2, corte do
					codigo = codigo .. ':WaitForChild("' .. ancestraGui[i] .. '")'
				end
			else
				for i = 2, #ancestraGui do
					codigo = codigo .. ':WaitForChild("' .. ancestraGui[i] .. '")'
				end
				codigo = codigo .. ':WaitForChild("' .. primeiro .. '")'
			end
			for i = 2, #partes do
				codigo = codigo .. ':WaitForChild("' .. partes[i] .. '")'
			end
			return codigo
		end

		return nil, '"' .. primeiro .. '" nao e um alias declarado (`usar "'
			.. primeiro .. '" = ...`) nem um servico do Roblox'
	end

	-----------------------------------------------------------------------
	-- valores e expressoes
	-----------------------------------------------------------------------

	local gerarValor

	local function gerarTupla(v, propYash)
		if propYash ~= nil and PROPS_UDIM2[string.lower(propYash)] then
			return "UDim2.fromOffset(" .. numeroLua(v.x) .. ", " .. numeroLua(v.y) .. ")"
		end
		return "Vector3.new(" .. numeroLua(v.x) .. ", " .. numeroLua(v.y)
			.. ", " .. numeroLua(v.z or 0) .. ")"
	end

	-- resolve um nome/caminho usado como valor (alias, servico, arvore ou uma
	-- das locais que o proprio gerador cria, como o parametro do callback)
	local function gerarReferencia(v, semArvoreGui)
		local nome = nil
		if v.k == "ident" then
			nome = v.v
		elseif v.k == "caminho" and #v.partes == 1 then
			nome = v.partes[1]
		end
		if nome then
			if aliases[nome] then return aliases[nome] end
			if LOCAIS_GERADOS[nome] then return nome end
		end
		if v.k == "ident" then return resolverCaminho({ v.v }, semArvoreGui) end
		if v.k == "caminho" then return resolverCaminho(v.partes, semArvoreGui) end
		return nil, "nao e uma referencia: " .. tostring(v.v or v.k)
	end

	-- valor simples, sem depender do destino
	function gerarValor(v, propYash)
		if v == nil then return nil, "valor ausente" end
		local k = v.k

		if k == "binario" then
			local esquerda, err = gerarValor(v.esq, propYash)
			if not esquerda then return nil, err end
			local direita, e = gerarValor(v.dir, propYash)
			if not direita then return nil, e end
			local op = v.op
			if op == "!=" then op = "~="
			elseif op == "e" then op = "and"
			elseif op == "ou" then op = "or" end
			return "(" .. esquerda .. " " .. op .. " " .. direita .. ")"
		end
		if k == "unario" then
			local valor, err = gerarValor(v.valor, propYash)
			if not valor then return nil, err end
			return "(" .. v.op .. " " .. valor .. ")"
		end
		if k == "num" then return numeroLua(v.v) end
		if k == "str" then return textoLua(v.v) end
		if k == "bool" then return tostring(v.v) end
		if k == "nulo" then return "nil" end
		if k == "par" then return gerarTupla(v, propYash) end
		if k == "cor" then
			return "Color3.fromRGB(" .. numeroLua(v.r) .. ", " .. numeroLua(v.g)
				.. ", " .. numeroLua(v.b) .. ")"
		end
		if k == "ident" then
			if aliases[v.v] then return aliases[v.v] end
			if LOCAIS_GERADOS[v.v] then return v.v end
			if FUNCOES_LUAU[v.v] or GLOBAIS_LUAU[v.v] then return v.v end
			return gerarReferencia(v)
		end
		if k == "caminho" then
			if ({ math = true, string = true, table = true, utf8 = true })[string.lower((v.partes or {})[1] or "")] then
				return table.concat(v.partes, ".")
			end
			-- Caminhos podem terminar numa propriedade, não apenas num filho.
			-- Nomes em português como `jogador.vida` são normalizados aqui e na
			-- atribuição, mantendo a resolução normal de caminhos desconhecidos.
			local partes = v.partes or {}
			if #partes > 1 then
				if objetosDados[partes[1]] and aliases[partes[1]] then
					return aliases[partes[1]] .. "." .. partes[#partes]
				end
				local prop = partes[#partes]
				local canon = PROPRIEDADES[string.lower(prop)]
				if canon then
					local basePartes = {}
					for i = 1, #partes - 1 do basePartes[i] = partes[i] end
					local base, err = gerarReferencia({ k = "caminho", partes = basePartes })
					if not base then return nil, err end
					return base .. "." .. canon
				end
			end
			return gerarReferencia(v)
		end
		if k == "chamada" then
			local alvo, err = gerarValor(v.alvo)
			if not alvo then return nil, err end
			local args = {}
			for _, arg in ipairs(v.args or {}) do
				local valor, e = gerarValor(arg)
				if not valor then return nil, e end
				table.insert(args, valor)
			end
			return alvo .. "(" .. table.concat(args, ", ") .. ")"
		end
		if k == "metodo_expr" then
			local base, err = gerarValor(v.base)
			if not base then return nil, err end
			local args = {}
			for _, arg in ipairs(v.args or {}) do
				local valor, e = gerarValor(arg)
				if not valor then return nil, e end
				table.insert(args, valor)
			end
			return base .. ":" .. v.metodo .. "(" .. table.concat(args, ", ") .. ")"
		end
		if k == "membro" then
			local base, err = gerarValor(v.base)
			if not base then return nil, err end
			local membro = PROPRIEDADES[string.lower(v.nome)] or v.nome
			return base .. "." .. membro
		end
		if k == "indice" then
			local base, err = gerarValor(v.base)
			if not base then return nil, err end
			local chave, e = gerarValor(v.chave)
			if not chave then return nil, e end
			return base .. "[" .. chave .. "]"
		end
		if k == "tabela" then
			local campos = {}
			for _, campo in ipairs(v.campos or {}) do
				local valor, err = gerarValor(campo.valor)
				if not valor then return nil, err end
				if campo.chave then
					local chave, e = gerarValor(campo.chave)
					if not chave then return nil, e end
					table.insert(campos, "[" .. chave .. "] = " .. valor)
				else
					table.insert(campos, valor)
				end
			end
			return "{" .. table.concat(campos, ", ") .. "}"
		end
		if k == "param" then
			return nil, "parametro nomeado ainda nao traduzido no caminho direto ("
				.. tostring(v.nome) .. " = ...)"
		end
		if k == "anim" then
			return nil, "animacao composta ainda nao traduzida no caminho direto"
		end
		return nil, "valor nao suportado: " .. tostring(k)
	end

	-----------------------------------------------------------------------
	-- animacoes (TweenService)
	-----------------------------------------------------------------------

	-- texto simples de um parametro (numero, palavra ou texto)
	local function textoParametro(expr)
		if not expr then return nil end
		if expr.k == "num" then return numeroLua(expr.v) end
		if expr.k == "str" then return expr.v end
		if expr.k == "ident" then return expr.v end
		return nil
	end

	-- normaliza o nome de um efeito e devolve o canonico (ou nil se desconhecido)
	local function canonizarEfeito(nome)
		if type(nome) ~= "string" then return nil end
		local l = string.lower(nome)
		l = string.gsub(l, "%s+", " ")
		l = string.gsub(l, "^%s+", "")
		l = string.gsub(l, "%s+$", "")
		return EFEITOS[l]
	end

	-- classifica o valor rico (parseValor) numa especificacao de tween:
	-- { efeito, animacao, duracao, estilo, direcao, goals, eparams }
	local function specDeAnim(v, onde)
		if not v then return nil, "animacao ausente em " .. onde end
		local spec = { goals = {}, eparams = {} }
		local params

		if v.k == "anim" then
			if v.efeito ~= "" then spec.efeito = v.efeito end
			params = v.params or {}
		elseif v.k == "param" then
			params = { [v.nome] = v.valor }
		elseif v.k == "ident" or v.k == "str" then
			spec.efeito = v.v
			params = {}
		else
			return nil, "efeito, propriedade ou animacao esperado em " .. onde
		end

		for nome, valor in pairs(params) do
			local l = string.lower(nome)
			if l == "duracao" then
				if not valor or valor.k ~= "num" then
					return nil, "duracao em " .. onde .. " precisa ser um numero"
				end
				spec.duracao = valor.v
			elseif l == "estilo" then
				local s = textoParametro(valor)
				if not s then return nil, "estilo em " .. onde .. " precisa ser uma palavra" end
				spec.estilo = s
			elseif l == "direcao" then
				local s = textoParametro(valor)
				if not s then return nil, "direcao em " .. onde .. " precisa ser uma palavra" end
				spec.direcao = s
			elseif l == "animacao" then
				local s = textoParametro(valor)
				if not s then return nil, "animacao em " .. onde .. " precisa ser um nome" end
				spec.animacao = s
			elseif l == "delta" or l == "escala" or l == "graus" then
				if not valor or valor.k ~= "num" then
					return nil, l .. " em " .. onde .. " precisa ser um numero"
				end
				spec.eparams[l] = valor.v
			elseif PROPRIEDADES[l] ~= nil or identificadorValido(nome) then
				table.insert(spec.goals, { propYash = nome, expr = valor })
			else
				return nil, "propriedade invalida `" .. tostring(nome) .. "` em " .. onde
			end
		end

		if spec.animacao and (spec.efeito or #spec.goals > 0 or next(spec.eparams) ~= nil) then
			return nil, "`animacao = <nome>` em " .. onde
				.. " nao pode misturar com efeito ou propriedades"
		end
		return spec
	end

	-- TweenInfo textual + duracao efetiva (padroes do legado: 0.3, Quad, Out)
	local function infoDeSpec(spec, onde, durOverride)
		local dur = durOverride or spec.duracao or 0.3
		local estilo = "Quad"
		if spec.estilo then
			local e = string.lower(string.gsub(spec.estilo, "%s+", ""))
			local achado = ESTILOS_EASING[e]
			if not achado then
				if identificadorValido(spec.estilo) then
					achado = spec.estilo
				else
					return nil, "estilo de animacao desconhecido `" .. tostring(spec.estilo)
						.. "` em " .. onde
				end
			end
			estilo = achado
		end
		local direcao = "Out"
		if spec.direcao then
			local d = string.lower(string.gsub(spec.direcao, "%s+", ""))
			local achado = DIRECOES_EASING[d]
			if not achado then
				return nil, "direcao de animacao desconhecida `" .. tostring(spec.direcao)
					.. "` em " .. onde
			end
			direcao = achado
		end
		return "TweenInfo.new(" .. numeroLua(dur) .. ", Enum.EasingStyle." .. estilo
			.. ", Enum.EasingDirection." .. direcao .. ")", dur
	end

	-- traduz as metas de propriedade em pares ordenados { prop, val }
	local function goalsExtras(spec, onde)
		local gs = {}
		for _, g in ipairs(spec.goals) do
			if g.expr.k == "str" or g.expr.k == "bool" or g.expr.k == "nulo" then
				return nil, "tween de `" .. g.propYash .. "` em " .. onde
					.. " nao aceita texto/verdadeiro/nulo (use numero, tupla, cor ou referencia)"
			end
			local prop = PROPRIEDADES[string.lower(g.propYash)] or g.propYash
			local val, err = gerarValor(g.expr, g.propYash)
			if not val then
				return nil, "propriedade `" .. g.propYash .. "` em " .. onde .. ": " .. tostring(err)
			end
			table.insert(gs, { prop = prop, val = val })
		end
		table.sort(gs, function(a, b) return a.prop < b.prop end)
		return gs
	end

	-- emite Create + Play de um tween puro; exige `local _alvo` ja emitido
	local function emitirGoalsPlay(info, gs)
		emitir(servico("TweenService") .. ":Create(_alvo, " .. info .. ", {")
		for _, g in ipairs(gs) do
			emitir("\t" .. g.prop .. " = " .. g.val .. ",")
		end
		emitir("}):Play()")
		return ""
	end

	-- efeito fade in: aparece suavemente a partir de transparente.
	-- LayerCollector (ScreenGui) nao tem transparencia: vira so Enabled = true.
	local function efeitoFadeIn(info)
		emitir("local _metas = {}")
		emitir("if _alvo:IsA(\"LayerCollector\") then")
		emitir("\t_alvo.Enabled = true")
		emitir("elseif _alvo:IsA(\"CanvasGroup\") then")
		emitir("\t_alvo.Visible = true")
		emitir("\t_alvo.GroupTransparency = 1")
		emitir("\t_metas.GroupTransparency = 0")
		emitir("elseif _alvo:IsA(\"ImageLabel\") or _alvo:IsA(\"ImageButton\") then")
		emitir("\t_alvo.Visible = true")
		emitir("\t_alvo.BackgroundTransparency = 1")
		emitir("\t_alvo.ImageTransparency = 1")
		emitir("\t_metas.BackgroundTransparency = 0")
		emitir("\t_metas.ImageTransparency = 0")
		emitir("elseif _alvo:IsA(\"TextLabel\") or _alvo:IsA(\"TextButton\") or _alvo:IsA(\"TextBox\") then")
		emitir("\t_alvo.Visible = true")
		emitir("\t_alvo.BackgroundTransparency = 1")
		emitir("\t_alvo.TextTransparency = 1")
		emitir("\t_metas.BackgroundTransparency = 0")
		emitir("\t_metas.TextTransparency = 0")
		emitir("else")
		emitir("\t_alvo.Visible = true")
		emitir("\t_alvo.BackgroundTransparency = 1")
		emitir("\t_metas.BackgroundTransparency = 0")
		emitir("end")
		emitir("if next(_metas) ~= nil then")
		emitir("\t" .. servico("TweenService") .. ":Create(_alvo, "
			.. info .. ", _metas):Play()")
		emitir("end")
		return ""
	end

	-- efeito fade out: some suavemente e desliga a visibilidade no fim
	local function efeitoFadeOut(info, dur)
		emitir("local _metas = {}")
		emitir("if _alvo:IsA(\"LayerCollector\") then")
		emitir("\t-- LayerCollector nao tem transparencia: some so no fim")
		emitir("elseif _alvo:IsA(\"CanvasGroup\") then")
		emitir("\t_metas.GroupTransparency = 1")
		emitir("elseif _alvo:IsA(\"ImageLabel\") or _alvo:IsA(\"ImageButton\") then")
		emitir("\t_metas.BackgroundTransparency = 1")
		emitir("\t_metas.ImageTransparency = 1")
		emitir("elseif _alvo:IsA(\"TextLabel\") or _alvo:IsA(\"TextButton\") or _alvo:IsA(\"TextBox\") then")
		emitir("\t_metas.BackgroundTransparency = 1")
		emitir("\t_metas.TextTransparency = 1")
		emitir("else")
		emitir("\t_metas.BackgroundTransparency = 1")
		emitir("end")
		emitir("if next(_metas) ~= nil then")
		emitir("\t" .. servico("TweenService") .. ":Create(_alvo, "
			.. info .. ", _metas):Play()")
		emitir("end")
		emitir("task.delay(" .. numeroLua(dur + 0.05) .. ", function()")
		emitir("\tif _alvo:IsA(\"LayerCollector\") then")
		emitir("\t\t_alvo.Enabled = false")
		emitir("\telse")
		emitir("\t\t_alvo.Visible = false")
		emitir("\tend")
		emitir("end)")
		return ""
	end

	local SLIDES = {
		["slide left"] = { eixo = "X", sinal = -1 },
		["slide right"] = { eixo = "X", sinal = 1 },
		["slide up"] = { eixo = "Y", sinal = -1 },
		["slide down"] = { eixo = "Y", sinal = 1 },
	}

	-- efeito slide: desloca a posicao em um eixo a partir do valor atual
	local function efeitoSlide(info, spec, eixo, sinal)
		local delta = spec.eparams.delta or 100
		local op = (sinal < 0) and " - " or " + "
		local x = "_pos.X.Scale, _pos.X.Offset"
		local y = "_pos.Y.Scale, _pos.Y.Offset"
		if eixo == "X" then
			x = x .. op .. numeroLua(delta)
		else
			y = y .. op .. numeroLua(delta)
		end
		emitir("local _pos = _alvo.Position")
		emitir(servico("TweenService") .. ":Create(_alvo, "
			.. info .. ", {")
		emitir("\tPosition = UDim2.new(" .. x .. ", " .. y .. "),")
		emitir("}):Play()")
		return ""
	end

	-- efeito pulsar: cresce e volta ao tamanho original
	local function efeitoPulsar(spec, onde, info, dur)
		local escala = spec.eparams.escala or 1.2
		local infoMeia, e = infoDeSpec(spec, onde, dur / 2)
		if not infoMeia then return nil, e end
		local m = numeroLua(escala)
		emitir("local _tamanho = _alvo.Size")
		emitir(servico("TweenService") .. ":Create(_alvo, "
			.. info .. ", {")
		emitir("\tSize = UDim2.new(_tamanho.X.Scale * " .. m .. ", _tamanho.X.Offset * "
			.. m .. ", _tamanho.Y.Scale * " .. m .. ", _tamanho.Y.Offset * " .. m .. "),")
		emitir("}):Play()")
		emitir("task.delay(" .. numeroLua(dur / 2) .. ", function()")
		emitir("\t" .. servico("TweenService") .. ":Create(_alvo, "
			.. infoMeia .. ", {")
		emitir("\t\tSize = _tamanho,")
		emitir("\t}):Play()")
		emitir("end)")
		return ""
	end

	-- efeito girar: soma graus (padrao 360) na rotacao atual
	local function efeitoGirar(info, spec)
		local graus = spec.eparams.graus or 360
		emitir(servico("TweenService") .. ":Create(_alvo, "
			.. info .. ", {")
		emitir("\tRotation = _alvo.Rotation + " .. numeroLua(graus) .. ",")
		emitir("}):Play()")
		return ""
	end

	-- efeito crescer/diminuir: multiplica o tamanho atual por um fator
	local function efeitoEscala(info, spec, fator)
		local m = numeroLua(fator)
		emitir("local _tamanho = _alvo.Size")
		emitir(servico("TweenService") .. ":Create(_alvo, "
			.. info .. ", {")
		emitir("\tSize = UDim2.new(_tamanho.X.Scale * " .. m .. ", _tamanho.X.Offset * "
			.. m .. ", _tamanho.Y.Scale * " .. m .. ", _tamanho.Y.Offset * " .. m .. "),")
		emitir("}):Play()")
		return ""
	end

	-- emite o corpo de um efeito (exige `local _alvo` ja emitido)
	local function emitirEfeito(ref, spec, onde)
		local canon = canonizarEfeito(spec.efeito)
		if not canon then
			return nil, "efeito de animacao desconhecido `" .. tostring(spec.efeito)
				.. "` em " .. onde
		end
		for nome in pairs(spec.eparams) do
			if not EFEITO_PARAMS[canon][nome] then
				return nil, "o efeito `" .. canon .. "` nao aceita o parametro `"
					.. nome .. "` em " .. onde
			end
		end
		local info, extra = infoDeSpec(spec, onde)
		if not info then return nil, extra end
		local dur = extra
		emitir("local _alvo = " .. ref)
		local sl = SLIDES[canon]
		if sl then
			return efeitoSlide(info, spec, sl.eixo, sl.sinal)
		elseif canon == "fade in" then
			return efeitoFadeIn(info)
		elseif canon == "fade out" then
			return efeitoFadeOut(info, dur)
		elseif canon == "pulsar" then
			return efeitoPulsar(spec, onde, info, dur)
		elseif canon == "girar" then
			return efeitoGirar(info, spec)
		elseif canon == "crescer" then
			return efeitoEscala(info, spec, spec.eparams.escala or 1.25)
		elseif canon == "diminuir" then
			return efeitoEscala(info, spec, spec.eparams.escala or 0.75)
		end
		return nil, "efeito nao implementado: " .. canon
	end

	-- nome da funcao Luau gerada para uma animacao criada
	local function nomeFnAnim(nome)
		local limpo = string.gsub(tostring(nome), "[^%w_]", "_")
		if string.match(limpo, "^%d") then limpo = "_" .. limpo end
		return "_anim_" .. limpo
	end

	local function nomeFnAcao(nome)
		local limpo = string.gsub(tostring(nome), "[^%w_]", "_")
		if string.match(limpo, "^%d") then limpo = "_" .. limpo end
		return "_acao_" .. limpo
	end

	-- devolve o nome da funcao se a animacao foi criada no programa, senao nil
	local function animacaoCriada(nome)
		if programa.animacoes and programa.animacoes[nome] then
			return nomeFnAnim(nome)
		end
		return nil
	end

	-- aplica uma especificacao de tween no ref (string Luau ja resolvida).
	-- animacao criada -> task.spawn; efeito -> emissor de efeito;
	-- senao -> tween puro de propriedades.
	local function aplicarSpecNoRef(ref, spec, onde)
		if spec.animacao then
			local fn = animacaoCriada(spec.animacao)
			if not fn then
				return nil, "animacao `" .. spec.animacao .. "` nao existe (crie com `criar animacao \""
					.. spec.animacao .. "\"`) em " .. onde
			end
			emitir("task.spawn(function() " .. fn .. "(" .. ref .. ") end)")
			return ""
		end
		emitir("do")
		local blk, e = blocoNovo(nivel() + 1, function()
			if spec.efeito then
				return emitirEfeito(ref, spec, onde)
			end
			if next(spec.eparams) ~= nil then
				return nil, "`delta`/`escala`/`graus` so valem junto de um efeito em " .. onde
			end
			if #spec.goals == 0 then
				return nil, "tween sem propriedades para animar em " .. onde
			end
			local gs, gerr = goalsExtras(spec, onde)
			if not gs then return nil, gerr end
			local info, ierr = infoDeSpec(spec, onde)
			if not info then return nil, ierr end
			emitir("local _alvo = " .. ref)
			return emitirGoalsPlay(info, gs)
		end)
		if not blk then return nil, e end
		anexar(blk)
		emitir("end")
		return ""
	end

	-----------------------------------------------------------------------
	-- condicoes
	-----------------------------------------------------------------------

	local function gerarCondicao(c)
		if c == nil then return nil, "condicao ausente" end
		local t = c.tipo

		if t == "logica" then
			local esq, err = gerarCondicao(c.esq)
			if not esq then return nil, err end
			local op = (c.op == "ou" or c.op == "or") and "or" or "and"
			local dir, e = gerarCondicao(c.dir)
			if not dir then return nil, e end
			return "(" .. esq .. " " .. op .. " " .. dir .. ")"
		elseif t == "nao" then
			local expr, err = gerarCondicao(c.cond)
			if not expr then return nil, err end
			return "(not " .. expr .. ")"
		elseif t == "comp" then
			local esq, err = gerarValor(c.esq)
			if not esq then return nil, err end
			local dir, e = gerarValor(c.dir)
			if not dir then return nil, e end
			local op = (c.op == "!=") and "~=" or c.op
			return "(" .. esq .. " " .. op .. " " .. dir .. ")"
		elseif t == "truthy" then
			local valor, err = gerarValor(c.valor)
			if not valor then return nil, err end
			return "(" .. valor .. " ~= nil and " .. valor .. " ~= false)"
		end

		if t == "num" then
			local partes = dividirCaminho(c.obj)
			local ref, err = resolverCaminho(partes)
			if not ref then return nil, err end
			local op = (c.op == "!=") and "~=" or c.op
			return "(" .. ref .. " " .. op .. " " .. numeroLua(c.val) .. ")"
		end

		if t == "estado" then
			local ref, err = gerarReferencia({ k = "ident", v = c.el })
			if not ref then return nil, err end
			local valor = (c.oq == "visivel") and "true" or "false"
			-- mesma regra do comando de visibilidade: LayerCollector (ScreenGui e
			-- afins) expoe Enabled; o restante da GUI expoe Visible
			return "((function() local _vis = " .. ref
				.. " if _vis:IsA(\"LayerCollector\") then return _vis.Enabled"
				.. " else return _vis.Visible end end)() == " .. valor .. ")"
		end

		if t == "tecla" then
			return "(" .. servico("UserInputService") .. ":IsKeyDown(Enum.KeyCode."
				.. string.upper(c.tecla) .. "))"
		end

		if t == "dist" then
			local a, err = gerarValor(c.aExpr or { k = "ident", v = c.a })
			if not a then return nil, err end
			local b, e = gerarValor(c.bExpr or { k = "ident", v = c.b })
			if not b then return nil, e end
			local op = c.op or "<"
			local raio = numeroLua(c.val or (c.raio and 10) or 0)
			return "((" .. a .. ":GetPivot().Position - " .. b .. ":GetPivot().Position).Magnitude "
				.. op .. " " .. raio .. ")"
		end

		if t == "vida" then
			local ref, err = gerarValor(c.alvoExpr or { k = "ident", v = c.alvo })
			if not ref then return nil, err end
			local compara = c.estado and "> 0" or "<= 0"
			return "((function() if type(" .. ref .. ") == \"table\" then return (" .. ref .. ".vida or 0) " .. compara .. " end; local _humanoide = (" .. ref
				.. "):IsA(\"Humanoid\") and " .. ref .. " or ("
				.. ref .. "):IsA(\"Player\") and " .. ref
				.. ".Character and " .. ref .. ".Character:FindFirstChildOfClass(\"Humanoid\") or ("
				.. ref .. "):FindFirstChildOfClass(\"Humanoid\"); return _humanoide ~= nil and _humanoide.Health "
				.. compara .. " end)())"
		end

		if t == "tocar" then
			local a, err = gerarValor(c.aExpr or { k = "ident", v = c.a })
			if not a then return nil, err end
			local b, e = gerarValor(c.bExpr or { k = "ident", v = c.b })
			if not b then return nil, e end
			return "((function() for _, _posarte in ipairs(" .. a .. ":GetTouchingParts()) do "
				.. "if _posarte == " .. b .. " or _posarte:IsDescendantOf(" .. b
				.. ") or " .. b .. ":IsDescendantOf(_posarte) then return true end end; return false end)())"
		end

		if t == "criado" then
			if (programa.objetos and programa.objetos[c.nome])
				or (programa.formas and programa.formas[c.nome])
				or (programa.elementos and programa.elementos[c.nome]) then return "true" end
			local name = textoLua(c.nome)
			return "(game:FindFirstChild(" .. name .. ", true) ~= nil)"
		end

		return nil, "condicao ainda nao traduzida no caminho direto: " .. tostring(t)
	end

	-----------------------------------------------------------------------
	-- comandos
	-----------------------------------------------------------------------

	-- alvo do evento cujo corpo esta sendo renderizado agora (nil fora de eventos).
	-- Permite que `cor = rgb(...)` solto dentro de `quando clicar Botao` saiba em
	-- qual objeto a propriedade deve ser aplicada.
	local alvoEvento = nil
	local dentroFuncao = false
	local eventoAtual = nil
	local traduzindoProibicao = false

	-- base de um `alvo` ou `objeto.propriedade`, resolvendo alias / arvore /
	-- servico / local do proprio gerador. `prop` volta nil quando o alvo e uma
	-- local simples (`Valor -= 1`).
	local function resolverBase(caminho)
		local partes = dividirCaminho(caminho)
		if #partes == 0 then
			return nil, nil, "atribuicao sem destino: " .. tostring(caminho)
		end
		if #partes == 1 then
			local base, err = gerarReferencia({ k = "ident", v = partes[1] })
			if not base then return nil, nil, err end
			return base, nil, nil
		end
		local basePartes = {}
		for i = 1, #partes - 1 do table.insert(basePartes, partes[i]) end
		local prop = partes[#partes]
		local base, err
		if #basePartes == 1 and aliases[basePartes[1]] then
			base = aliases[basePartes[1]]
		else
			base, err = resolverCaminho(basePartes)
		end
		if not base then return nil, nil, err end
		return base, prop, nil
	end

	-- <obj>.<prop> = <valor>
	local function gerarAtribuicao(caminho, expr)
		local partesAtrib = dividirCaminho(caminho)
		local base, prop, err = resolverBase(caminho)
		if not base then return nil, err end

		-- largura / altura mexem em uma dimensao do Size
		if prop == "largura" or prop == "altura" then
			if expr and expr.k == "num" then
				local eixo = (prop == "largura") and "X" or "Y"
				local outro = (eixo == "X") and "Y" or "X"
				emitir(base .. ".Size = UDim2.new(" .. base .. ".Size." .. eixo
					.. ".Scale, " .. numeroLua(expr.v) .. ", " .. base .. ".Size."
					.. outro .. ".Scale, " .. base .. ".Size." .. outro .. ".Offset)")
				return ""
			end
			return nil, prop .. " espera um numero"
		end

		local destino = prop and ((partesAtrib[1] and objetosDados[partesAtrib[1]])
			and prop or PROPRIEDADES[string.lower(prop)] or prop) or nil
		local prefixo = destino and (base .. "." .. destino) or base

		-- CameraType e uma propriedade Enum; aceite os nomes mais usados como
		-- valores YashScript para evitar exigir sintaxe Luau no menu/camera.
		if string.lower(prop or "") == "cameratype" and expr and expr.k == "ident" then
			local tiposCamera = { scriptable = "Scriptable", custom = "Custom", attach = "Attach", track = "Track", watch = "Watch" }
			local tipoCamera = tiposCamera[string.lower(tostring(expr.v))]
			if tipoCamera then
				emitir(prefixo .. " = Enum.CameraType." .. tipoCamera)
				return ""
			end
		end

		-- propriedade booleana aceita os verbos do YashScript
		if destino and PROPS_BOOL[string.lower(prop)] then
			local b = normalizarBool(expr)
			if b ~= nil then
				emitir(prefixo .. " = " .. tostring(b))
				return ""
			end
		end

		local valor, verr = gerarValor(expr, prop)
		if not valor then return nil, verr end
		emitir(prefixo .. " = " .. valor)
		return ""
	end

	local function gerarCorpo(corpo, linhaBase)
		if not corpo or #corpo == 0 then return "" end
		for _, cmd in ipairs(corpo) do
			local r, err = gerarComando(cmd, linhaBase)
			if r == nil then return nil, err end
		end
		return ""
	end

	function gerarComando(cmd, linhaBase)
		local l = linhaBase or 0
		local t = cmd.tipo
		if eventoAtual and not traduzindoProibicao and cmd.norm then
			local normCmd = string.lower(string.gsub(cmd.norm, "[%s%(%)]", ""))
			for _, p in ipairs(programa.proibicoes or {}) do
				local normEvt = p.evt == "clicar" and "clicar" or p.evt
				local normAlvo = tostring(p.alvo or "")
				for _, proibido in ipairs(p.comandos or {}) do
					local alvoCompat = eventoAtual.alvo == normAlvo and eventoAtual.tipo == normEvt
					local normProibido = string.lower(string.gsub(tostring(proibido), "[%s%(%)]", ""))
					if alvoCompat and normCmd == normProibido then
						if not p.cond then
							if p.somente then
								local somente = tostring(p.somente)
								if eventoAtual.alvo == somente then return "" end
							else
							return ""
							end
						else
							local cond, err = gerarCondicao(p.cond)
							if not cond then return nil, err end
							emitir("if not (" .. cond .. ") then")
							traduzindoProibicao = true
							local ok, e = gerarComando(cmd, l)
							traduzindoProibicao = false
							if not ok then return nil, e end
							emitir("end")
							return ""
						end
					end
				end
			end
		end

		if t == "log" then
			if cmd.args then
				local args = {}
				for _, arg in ipairs(cmd.args) do
					local codigo, err = gerarValor(arg)
					if not codigo then return nil, err or "argumento inválido em print" end
					table.insert(args, codigo)
				end
				emitir("print(" .. table.concat(args, ", ") .. ")")
				return ""
			end
			local v, err
			if cmd.expr then
				v, err = gerarValor(cmd.expr)
			elseif cmd.texto then
				v = textoLua(cmd.texto)
			end
			if not v then return nil, err or "print sem valor" end
			emitir("print(" .. v .. ")")
			return ""
		end

		if t == "atrib" then
			if cmd.op == "=" then
				return gerarAtribuicao(cmd.caminho, cmd.expr)
			end
			-- += / -= viram operacao Luau direta
			local base, prop, err = resolverBase(cmd.caminho)
			if not base then return nil, err end
			local valor, verr = gerarValor(cmd.expr)
			if not valor then return nil, verr end
			local partesAtrib = dividirCaminho(cmd.caminho)
			local destino = prop and ((objetosDados[partesAtrib[1]]) and prop
				or PROPRIEDADES[string.lower(prop)] or prop) or nil
			local prefixo = destino and (base .. "." .. destino) or base
			local op = (cmd.op == "+=") and "+" or "-"
			emitir(prefixo .. " = " .. prefixo .. " " .. op .. " " .. valor)
			return ""
		end

		if t == "atrib_indice" then
			local tabela, err = gerarValor(cmd.destino.base)
			if not tabela then return nil, err end
			local indice, e = gerarValor(cmd.destino.chave)
			if not indice then return nil, e end
			local valor, verr = gerarValor(cmd.expr)
			if not valor then return nil, verr end
			local atribuir = cmd.op == "=" and ("_tabela[_indice] = " .. valor)
				or ("_tabela[_indice] = _tabela[_indice] "
					.. (cmd.op == "+=" and "+" or "-") .. " " .. valor)
			emitir("do")
			local bloco, be = blocoNovo(nivel() + 1, function()
				emitir("local _tabela = " .. tabela)
				emitir("local _indice = " .. indice)
				emitir(atribuir)
				return ""
			end)
			if not bloco then return nil, be end
			anexar(bloco)
			emitir("end")
			return ""
		end

		if t == "variavel" then
			if cmd.expr then return gerarAtribuicao(cmd.nome, cmd.expr) end
			return ""
		end

		if t == "retornar" then
			if not dentroFuncao then return nil, "'retornar' só pode ser usado dentro de uma função" end
			if not cmd.expr then emitir("do return nil end"); return "" end
			local valor, err = gerarValor(cmd.expr)
			if not valor then return nil, err end
			emitir("do return " .. valor .. " end")
			return ""
		end

		if t == "expressao" then
			local valor, err = gerarValor(cmd.expr)
			if not valor then return nil, err end
			emitir(valor)
			return ""
		end

		if t == "visivel" then
			local ref, err
			if cmd.expr then
				ref, err = gerarReferencia(cmd.expr)
			else
				ref, err = gerarReferencia({ k = "ident", v = cmd.alvo })
			end
			if not ref then return nil, err end

			-- sufixo `animacao = ...`: efeito/propriedades aplicados junto da
			-- visibilidade (ex: mostrar(Painel) animacao = fade in)
			local spec = nil
			if cmd.anim ~= nil then
				local s, serr = specDeAnim(cmd.anim, (cmd.acao or "visivel") .. "(...)")
				if not s then return nil, serr end
				spec = s
			end

			-- fade in em mostrar / fade out em esconder ja cuidam da
			-- visibilidade sozinhos: o bloco base nao e emitido
			local canonEfeito = (spec and spec.efeito) and canonizarEfeito(spec.efeito) or nil
			local soEfeito = (canonEfeito == "fade in" and cmd.acao == "mostrar")
				or (canonEfeito == "fade out" and cmd.acao == "esconder")
			if soEfeito then
				return aplicarSpecNoRef(ref, spec, (cmd.acao or "visivel") .. "(...)")
			end

			-- ScreenGui/SurfaceGui/BillboardGui (LayerCollector) usam Enabled;
			-- o restante da GUI usa Visible. A classe so existe em runtime,
			-- entao o gerador emite a escolha em runtime.
			local function corpoVisibilidade(prop)
				return function()
					if cmd.acao == "alternar" then
						emitir(prop .. " = not " .. prop)
					elseif cmd.acao == "mostrar" then
						emitir(prop .. " = true")
					else
						emitir(prop .. " = false")
					end
					return ""
				end
			end
			emitir("do")
			local blk, e = blocoNovo(nivel() + 1, function()
				emitir("local _vis = " .. ref)
				emitir("if _vis:IsA(\"LayerCollector\") then")
				local s1, e1 = blocoNovo(nivel() + 1, corpoVisibilidade("_vis.Enabled"))
				if not s1 then return nil, e1 end
				anexar(s1)
				emitir("else")
				local s2, e2 = blocoNovo(nivel() + 1, corpoVisibilidade("_vis.Visible"))
				if not s2 then return nil, e2 end
				anexar(s2)
				emitir("end")
				return ""
			end)
			if not blk then return nil, e end
			anexar(blk)
			emitir("end")

			if spec then
				local ok, e = aplicarSpecNoRef(ref, spec, (cmd.acao or "visivel") .. "(...)")
				if not ok then return nil, e end
			end
			return ""
		end

		if t == "cena" then
			local nome = textoLua(cmd.alvo)
			local workspace = servico("Workspace")
			local players = servico("Players")
			local ativo = cmd.acao ~= "esconder"
			local mudaTudo = cmd.acao == "mudar"
			emitir("do")
			local blk, e = blocoNovo(nivel() + 1, function()
				emitir("local _cenaAtual = " .. nome)
				emitir("for _, _instancia in ipairs(" .. workspace .. ":GetDescendants()) do")
				emitir("\tif _instancia:GetAttribute(\"Cena\") then")
				emitir("\t\tlocal _mostrarCena = _instancia:GetAttribute(\"Cena\") == _cenaAtual")
				if mudaTudo then
					emitir("\t\tif _instancia:IsA(\"GuiObject\") then _instancia.Visible = _mostrarCena")
					emitir("\t\telseif _instancia:IsA(\"BasePart\") then _instancia.Transparency = _mostrarCena and 0 or 1; _instancia.CanCollide = _mostrarCena end")
				else
					emitir("\t\tif _mostrarCena and _instancia:IsA(\"GuiObject\") then _instancia.Visible = " .. tostring(ativo))
					emitir("\t\telseif _mostrarCena and _instancia:IsA(\"BasePart\") then _instancia.Transparency = " .. (ativo and "0" or "1") .. "; _instancia.CanCollide = " .. tostring(ativo) .. " end")
				end
				emitir("\tend")
				emitir("end")
				emitir("local _jogador = " .. players .. ".LocalPlayer")
				emitir("local _gui = _jogador and _jogador:FindFirstChildOfClass(\"PlayerGui\")")
				emitir("if _gui then for _, _instancia in ipairs(_gui:GetDescendants()) do")
				if mudaTudo then
					emitir("\tif _instancia:GetAttribute(\"Cena\") then _instancia.Visible = (_instancia:GetAttribute(\"Cena\") == _cenaAtual) end")
				else
					emitir("\tif _instancia:GetAttribute(\"Cena\") == _cenaAtual then _instancia.Visible = " .. tostring(ativo) .. " end")
				end
				emitir("end end")
				return ""
			end)
			if not blk then return nil, e end
			anexar(blk); emitir("end")
			return ""
		end

		if t == "prop" then
			-- `nome = valor` solto dentro de um evento: aplica no alvo do evento
			if not alvoEvento then
				return nil, "propriedade solta (" .. tostring(cmd.propNome)
					.. " = ...) so faz sentido dentro de um evento com alvo"
			end
			if cmd.propNome == "animacao" then
				local onde = "animacao = ... (no evento de " .. alvoEvento .. ")"
				local spec, serr = specDeAnim(cmd.expr, onde)
				if not spec then return nil, serr end
				local ref, err = gerarReferencia({ k = "ident", v = alvoEvento })
				if not ref then return nil, err end
				return aplicarSpecNoRef(ref, spec, onde)
			end
			return gerarAtribuicao(alvoEvento .. "." .. cmd.propNome, cmd.expr)
		end

		if t == "tween" then
			local ref, err = gerarReferencia(cmd.expr)
			if not ref then return nil, err end
			local onde = "animar(" .. textoLua(cmd.alvo) .. ")"
			local spec, serr = specDeAnim(cmd.valor, onde)
			if not spec then return nil, serr end
			return aplicarSpecNoRef(ref, spec, onde)
		end

		if t == "animacao" then
			if not alvoEvento then
				return nil, "executar animacao so faz sentido dentro de um evento com alvo"
					.. "; para animar outro objeto use animar(\"<Alvo>\") animacao = "
					.. tostring(cmd.nome)
			end
			local fn = animacaoCriada(cmd.nome)
			if not fn then
				return nil, "animacao `" .. tostring(cmd.nome) .. "` nao existe (crie com `criar animacao \""
					.. tostring(cmd.nome) .. "\"`)"
			end
			local ref, err = gerarReferencia({ k = "ident", v = alvoEvento })
			if not ref then return nil, err end
			emitir("task.spawn(function() " .. fn .. "(" .. ref .. ") end)")
			return ""
		end

		if t == "acao" then
			local fn = programa.acoes and programa.acoes[cmd.nome] and nomeFnAcao(cmd.nome)
			if not fn then return nil, "acao `" .. tostring(cmd.nome) .. "` nao existe" end
			local alvo = "nil"
			if alvoEvento then
				local ref, err = gerarReferencia({ k = "ident", v = alvoEvento })
				if not ref then return nil, err end
				alvo = ref
			end
			emitir(fn .. "(" .. alvo .. ")")
			return ""
		end

		if t == "metodo" then
			-- O alvo pode ser um alias simples (`Botao`) ou um caminho
			-- (`Workspace.Casa`); nos dois casos a base e resolvida pela mesma
			-- regra de referencias usada no resto do gerador.
			local alvoPartes = dividirCaminho(cmd.alvo or "")
			local ref, err
			if #alvoPartes > 1 then
				ref, err = resolverCaminho(alvoPartes)
			else
				ref, err = gerarReferencia({ k = "ident", v = cmd.alvo })
			end
			if not ref then return nil, err end
			local metodo = cmd.metodo
			if metodo == "destruir" or metodo == "remover" then metodo = "Destroy" end
			local args = {}
			for _, valor in ipairs(cmd.args or {}) do
				local codigo, e = gerarValor(valor)
				if not codigo then return nil, e end
				table.insert(args, codigo)
			end
			-- Chamadas de método passam diretamente para Luau, permitindo acessar
			-- métodos Roblox sem manter uma lista fechada no compilador.
			emitir(ref .. ":" .. metodo .. "(" .. table.concat(args, ", ") .. ")")
			return ""
		end

		if t == "espera" then
			emitir("task.wait(" .. numeroLua(cmd.valor or 0) .. ")")
			return ""
		end

		if t == "dano" or t == "curar" or t == "matar" then
			local alvo, err = gerarReferencia({ k = "ident", v = cmd.alvo }, true)
			if not alvo then return nil, err end
			emitir("do")
			local blk, e = blocoNovo(nivel() + 1, function()
				emitir("local _alvoVida = " .. alvo)
				emitir("if type(_alvoVida) == \"table\" and type(_alvoVida.vida) == \"number\" then")
				if t == "dano" then
					emitir("\t_alvoVida.vida = math.max(0, _alvoVida.vida - " .. numeroLua(cmd.valor) .. ")")
				elseif t == "curar" then
					emitir("\t_alvoVida.vida = math.min(_alvoVida.vida_maxima or math.huge, _alvoVida.vida + " .. numeroLua(cmd.valor) .. ")")
				else
					emitir("\t_alvoVida.vida = 0")
				end
				emitir("else")
				emitir("local _humanoide = (_alvoVida:IsA(\"Humanoid\") and _alvoVida) or (_alvoVida:IsA(\"Player\") and _alvoVida.Character and _alvoVida.Character:FindFirstChildOfClass(\"Humanoid\")) or _alvoVida:FindFirstChildOfClass(\"Humanoid\")")
				emitir("if _humanoide then")
				if t == "dano" then
					emitir("\t_humanoide:TakeDamage(" .. numeroLua(cmd.valor) .. ")")
				elseif t == "curar" then
					emitir("\t_humanoide.Health = math.clamp(_humanoide.Health + " .. numeroLua(cmd.valor) .. ", 0, _humanoide.MaxHealth)")
				else
					emitir("\t_humanoide.Health = 0")
				end
				emitir("end")
				emitir("end")
				return ""
			end)
			if not blk then return nil, e end
			anexar(blk); emitir("end")
			return ""
		end

		if t == "respawnar" then
			local alvo, err = gerarReferencia({ k = "ident", v = cmd.alvo }, true)
			if not alvo then return nil, err end
			local players = servico("Players")
			emitir("do")
			local blk, e = blocoNovo(nivel() + 1, function()
				emitir("local _alvoVida = " .. alvo)
				emitir("local _player = (_alvoVida:IsA(\"Player\") and _alvoVida) or " .. players .. ":GetPlayerFromCharacter(_alvoVida) or " .. players .. ":FindFirstChild(_alvoVida.Name)")
				emitir("if _player then _player:LoadCharacter() end")
				return ""
			end)
			if not blk then return nil, e end
			anexar(blk); emitir("end")
			return ""
		end

		if t == "teleportar" then
			local alvo, err = gerarReferencia({ k = "ident", v = cmd.alvo }, true)
			if not alvo then return nil, err end
			emitir(alvo .. ":PivotTo(CFrame.new(" .. numeroLua(cmd.pos.x) .. ", " .. numeroLua(cmd.pos.y) .. ", " .. numeroLua(cmd.pos.z or 0) .. "))")
			return ""
		end

		if t == "mover" or t == "rotacionar" then
			local alvo, err = gerarReferencia({ k = "ident", v = cmd.alvo }, true)
			if not alvo then return nil, err end
			local tweenService = servico("TweenService")
			local duracao = cmd.duracao or (20 / math.max(tonumber(cmd.velocidade) or 20, 0.1))
			local cf
			if t == "mover" then
				cf = "CFrame.new(" .. numeroLua(cmd.para.x) .. ", " .. numeroLua(cmd.para.y) .. ", " .. numeroLua(cmd.para.z or 0) .. ")"
			else
				cf = "CFrame.new(_alvo:GetPivot().Position) * CFrame.Angles(math.rad(" .. numeroLua(cmd.para.x) .. "), math.rad(" .. numeroLua(cmd.para.y) .. "), math.rad(" .. numeroLua(cmd.para.z or 0) .. "))"
			end
			emitir("do")
			local blk, e = blocoNovo(nivel() + 1, function()
				emitir("local _alvo = " .. alvo)
				emitir("local _inicio = _alvo:GetPivot()")
				if t == "mover" then
					emitir("local _destino = CFrame.new(" .. numeroLua(cmd.para.x) .. ", " .. numeroLua(cmd.para.y) .. ", " .. numeroLua(cmd.para.z or 0) .. ") * _inicio.Rotation")
				else
					emitir("local _destino = " .. cf)
				end
				emitir("if _alvo:IsA(\"BasePart\") then")
				emitir("\t" .. tweenService .. ":Create(_alvo, TweenInfo.new(" .. numeroLua(duracao) .. "), { CFrame = _destino }):Play()")
				emitir("else")
				emitir("\ttask.spawn(function()")
				emitir("\t\tlocal _inicioTempo = os.clock()")
				emitir("\t\twhile _alvo.Parent and os.clock() - _inicioTempo < " .. numeroLua(duracao) .. " do")
				emitir("\t\t\tlocal _alpha = math.clamp((os.clock() - _inicioTempo) / math.max(" .. numeroLua(duracao) .. ", 0.001), 0, 1)")
				emitir("\t\t\t_alvo:PivotTo(_inicio:Lerp(_destino, _alpha))")
				emitir("\t\t\ttask.wait()")
				emitir("\t\tend")
				emitir("\t\tif _alvo.Parent then _alvo:PivotTo(_destino) end")
				emitir("\tend)")
				emitir("end")
				return ""
			end)
			if not blk then return nil, e end
			anexar(blk); emitir("end")
			return ""
		end

		if t == "som" then
			local soundService = servico("SoundService")
			local debris = servico("Debris")
			emitir("do")
			local blk, e = blocoNovo(nivel() + 1, function()
				emitir('local _som = Instance.new("Sound")')
				emitir('_som.SoundId = "rbxassetid://' .. tostring(cmd.id) .. '"')
				emitir("_som.Parent = " .. soundService)
				emitir("_som:Play()")
				emitir(debris .. ":AddItem(_som, 5)")
				return ""
			end)
			if not blk then return nil, e end
			anexar(blk); emitir("end")
			return ""
		end

		if t == "destruir" then
			local alvo, err = gerarReferencia({ k = "ident", v = cmd.alvo }, true)
			if not alvo then return nil, err end
			emitir(alvo .. ":Destroy()")
			return ""
		end

		if t == "sortear" then
			local nome, err = gerarReferencia({ k = "ident", v = cmd.nome })
			if not nome then return nil, err end
			emitir(nome .. " = math.random(" .. numeroLua(cmd.min) .. ", " .. numeroLua(cmd.max) .. ")")
			return ""
		end

		if t == "soma" then
			local destinoPartes = dividirCaminho(cmd.para)
			local fontePartes = dividirCaminho(cmd.de)
			local destinoExpr = #destinoPartes > 1 and { k = "caminho", partes = destinoPartes } or { k = "ident", v = destinoPartes[1] }
			local fonteExpr = #fontePartes > 1 and { k = "caminho", partes = fontePartes } or { k = "ident", v = fontePartes[1] }
			local destino, err = gerarValor(destinoExpr)
			if not destino then return nil, err end
			local fonte, e = gerarValor(fonteExpr)
			if not fonte then return nil, e end
			local op = cmd.op == "somar" and "+" or "-"
			emitir(destino .. " = " .. destino .. " " .. op .. " " .. fonte)
			return ""
		end

		if t == "explodir" then
			local alvo, err = gerarReferencia({ k = "ident", v = cmd.alvo }, true)
			if not alvo then return nil, err end
			local workspace = servico("Workspace")
			emitir("do")
			local blk, e = blocoNovo(nivel() + 1, function()
				emitir('local _explosao = Instance.new("Explosion")')
				emitir("_explosao.Position = " .. alvo .. ":GetPivot().Position")
				emitir("_explosao.BlastRadius = " .. numeroLua(cmd.raio or 8))
				emitir("_explosao.BlastPressure = " .. numeroLua(cmd.dano or 50))
				emitir("_explosao.Parent = " .. workspace)
				return ""
			end)
			if not blk then return nil, e end
			anexar(blk); emitir("end")
			return ""
		end

		if t == "seguir" then
			local quem, err = gerarReferencia({ k = "ident", v = cmd.quem }, true)
			if not quem then return nil, err end
			local alvo, e = gerarReferencia({ k = "ident", v = cmd.alvo }, true)
			if not alvo then return nil, e end
			emitir("task.spawn(function()")
			local blk, be = blocoNovo(nivel() + 1, function()
				emitir("local _quem = " .. quem)
				emitir("local _personagemAlvo = _quem:IsA(\"Player\") and (_quem.Character or _quem.CharacterAdded:Wait()) or _quem")
				emitir("local _humanoide = _personagemAlvo:IsA(\"Humanoid\") and _personagemAlvo or _personagemAlvo:FindFirstChildOfClass(\"Humanoid\")")
				emitir("while _personagemAlvo.Parent and " .. alvo .. ".Parent do")
				emitir("\tif _humanoide then _humanoide:MoveTo(" .. alvo .. ":GetPivot().Position) else _personagemAlvo:PivotTo(" .. alvo .. ":GetPivot()) end")
				emitir("\ttask.wait(0.2)")
				emitir("end")
				return ""
			end)
			if not blk then return nil, be end
			anexar(blk); emitir("end)")
			return ""
		end

		if t == "clonar" then
			local origParts = dividirCaminho(cmd.origem)
			local paiParts = dividirCaminho(cmd.pai)
			local origem, err = gerarReferencia({ k = #origParts > 1 and "caminho" or "ident", partes = origParts, v = origParts[1] })
			if not origem then return nil, err end
			local pai, e = gerarReferencia({ k = #paiParts > 1 and "caminho" or "ident", partes = paiParts, v = paiParts[1] })
			if not pai then return nil, e end
			local clone = cmd.nome and aliases[cmd.nome] or "_instanciaClonada"
			if cmd.nome and not clone then return nil, "variavel de destino do clonar nao foi declarada: " .. tostring(cmd.nome) end
			emitir("do")
			local blk, be = blocoNovo(nivel() + 1, function()
				emitir("local _copiaTemp = " .. origem .. ":Clone()")
				emitir("if _copiaTemp then")
				if cmd.nome then
					emitir("\t" .. clone .. " = _copiaTemp")
					emitir("\t" .. clone .. ".Name = " .. textoLua(cmd.nome))
				end
				emitir("\t_copiaTemp.Parent = " .. pai)
				emitir("end")
				return ""
			end)
			if not blk then return nil, be end
			anexar(blk); emitir("end")
			return ""
		end

		if t == "se" then
			local cond, err = gerarCondicao(cmd.cond)
			if not cond then return nil, err end
			emitir("if " .. cond .. " then")
			local corpo, e = blocoNovo(nivel() + 1, function()
				return gerarCorpo(cmd.corpo, l)
			end)
			if not corpo then return nil, e end
			anexar(corpo)
			for _, alternativa in ipairs(cmd.alternativas or {}) do
				local condAlternativa, errAlternativa = gerarCondicao(alternativa.cond)
				if not condAlternativa then return nil, errAlternativa end
				emitir("elseif " .. condAlternativa .. " then")
				local ramo, erroRamo = blocoNovo(nivel() + 1, function()
					return gerarCorpo(alternativa.corpo, l)
				end)
				if not ramo then return nil, erroRamo end
				anexar(ramo)
			end
			if cmd.senao and #cmd.senao > 0 then
				emitir("else")
				local sen, e2 = blocoNovo(nivel() + 1, function()
					return gerarCorpo(cmd.senao, l)
				end)
				if not sen then return nil, e2 end
				anexar(sen)
			end
			emitir("end")
			return ""
		end

		if t == "enquanto" then
			local cond, err = gerarCondicao(cmd.cond)
			if not cond then return nil, err end
			emitir("while " .. cond .. " do")
			local corpo, e = blocoNovo(nivel() + 1, function()
				return gerarCorpo(cmd.corpo, l)
			end)
			if not corpo then return nil, e end
			anexar(corpo)
			emitir("end")
			return ""
		end

		if t == "repita" then
			local cond, err = gerarCondicao(cmd.cond)
			if not cond then return nil, err end
			emitir("repeat")
			local corpo, e = blocoNovo(nivel() + 1, function()
				return gerarCorpo(cmd.corpo, l)
			end)
			if not corpo then return nil, e end
			anexar(corpo)
			emitir("until " .. cond)
			return ""
		end

		if t == "pare" then emitir("break"); return "" end
		if t == "continuar" then emitir("continue"); return "" end

		if t == "para" then
			if not identificadorValido(cmd.nome) then return nil, "nome inválido no laço 'para': " .. tostring(cmd.nome) end
			local inicio, err = gerarValor(cmd.inicio)
			if not inicio then return nil, err end
			local limite, e = gerarValor(cmd.limite)
			if not limite then return nil, e end
			local passo, pe = gerarValor(cmd.passo)
			if not passo then return nil, pe end
			local aliasAnterior, localAnterior = aliases[cmd.nome], LOCAIS_GERADOS[cmd.nome]
			aliases[cmd.nome] = cmd.nome
			LOCAIS_GERADOS[cmd.nome] = true
			emitir("for " .. cmd.nome .. " = " .. inicio .. ", " .. limite .. ", " .. passo .. " do")
			local corpo, ce = blocoNovo(nivel() + 1, function() return gerarCorpo(cmd.corpo, l) end)
			aliases[cmd.nome], LOCAIS_GERADOS[cmd.nome] = aliasAnterior, localAnterior
			if not corpo then return nil, ce end
			anexar(corpo)
			emitir("end")
			return ""
		end

		if t == "para_cada" then
			local colecao, err = gerarValor(cmd.colecao)
			if not colecao then return nil, err end
			local nomes = cmd.nomes or {}
			local anterior, locais = {}, {}
			for _, nome in ipairs(nomes) do
				if not identificadorValido(nome) then return nil, "nome inválido no laço 'para cada': " .. tostring(nome) end
				anterior[nome], locais[nome] = aliases[nome], LOCAIS_GERADOS[nome]
				aliases[nome], LOCAIS_GERADOS[nome] = nome, true
			end
			local iterador = cmd.iterador == "pairs" and "pairs" or "ipairs"
			local variaveis = #nomes == 2 and table.concat(nomes, ", ") or ("_, " .. tostring(nomes[1]))
			emitir("for " .. variaveis .. " in " .. iterador .. "(" .. colecao .. ") do")
			local corpo, ce = blocoNovo(nivel() + 1, function() return gerarCorpo(cmd.corpo, l) end)
			for _, nome in ipairs(nomes) do aliases[nome], LOCAIS_GERADOS[nome] = anterior[nome], locais[nome] end
			if not corpo then return nil, ce end
			anexar(corpo)
			emitir("end")
			return ""
		end

		-- construcoes legadas ainda nao migradas: erro explicito (fila de migracao)
		return nil, "construcao ainda nao traduzida para Luau direto: " .. tostring(t)
	end

	-----------------------------------------------------------------------
	-- topo do programa
	-----------------------------------------------------------------------

	-- Materializa as construções estáticas restantes em instâncias Luau nativas.
	local inicializadores = {}
	local varsCriadas = {}
	local function nomeInterno(prefixo, nome)
		local limpo = string.gsub(tostring(nome), "[^%w_]", "_")
		if string.match(limpo, "^%d") then limpo = "_" .. limpo end
		return prefixo .. limpo
	end
	local function legadoLua(v, prop, gui)
		if type(v) == "number" then return numeroLua(v) end
		if type(v) == "boolean" then return tostring(v) end
		if type(v) == "table" then
			if v.t == "cor" then return "Color3.fromRGB(" .. numeroLua(v.r) .. ", " .. numeroLua(v.g) .. ", " .. numeroLua(v.b) .. ")" end
			if v.t == "par" then
				if gui then return "UDim2.fromOffset(" .. numeroLua(v.x) .. ", " .. numeroLua(v.y) .. ")" end
				return "Vector3.new(" .. numeroLua(v.x) .. ", " .. numeroLua(v.y) .. ", " .. numeroLua(v.z or 0) .. ")"
			end
			return nil
		end
		if type(v) ~= "string" then return nil end
		local l = string.lower(v)
		if l == "verdadeiro" or l == "sim" or l == "true" then return "true" end
		if l == "falso" or l == "nao" or l == "false" then return "false" end
		local cores = { white = "Color3.new(1, 1, 1)", preto = "Color3.new(0, 0, 0)", black = "Color3.new(0, 0, 0)", branco = "Color3.new(1, 1, 1)" }
		if cores[l] and (prop == "cor" or prop == "cor_texto" or prop == "cor_borda" or prop == "fundo") then return cores[l] end
		if prop == "material" then
			local materiais = { grama = "Grass", concreto = "Concrete", madeira = "Wood", metal = "Metal", vidro = "Glass", plastico = "Plastic", areia = "Sand", agua = "Water", pedra = "Slate", gelo = "Ice" }
			return "Enum.Material." .. (materiais[l] or v)
		end
		if prop == "fonte" then
			local fontes = { arial = "Arial", gothic = "Gotham", gotham = "Gotham", code = "Code", cartoony = "Cartoon", cartoon = "Cartoon", sci_fi = "SciFi", scifi = "SciFi", fantasy = "Fantasy" }
			return "Enum.Font." .. (fontes[l] or v)
		end
		return textoLua(v)
	end
	local function mesclar(estilo, props)
		local r = {}
		for k, v in pairs(estilo or {}) do r[k] = v end
		for k, v in pairs(props or {}) do r[k] = v end
		return r
	end
	local function cenaVisivel(nome)
		local def = nome and programa.cenas and programa.cenas[nome]
		local v = def and def.mostrar
		if v == nil then return true end
		if type(v) == "boolean" then return v end
		if type(v) == "string" then
			local l = string.lower(v)
			return not (l == "falso" or l == "nao" or l == "false")
		end
		return v ~= false
	end
	local elementosOrdem = {}
	for _, nome in ipairs(programa.ordem_elementos or {}) do
		if programa.elementos and programa.elementos[nome] then table.insert(elementosOrdem, nome) end
	end
	local incluidos = {}
	for _, nome in ipairs(elementosOrdem) do incluidos[nome] = true end
	-- sobras (sem ordem deterministica): pares() sem ordem deixaria a saida nao-deterministica
	for _, nome in ipairs(nomesOrdenados(programa.elementos)) do
		if not incluidos[nome] then table.insert(elementosOrdem, nome) end
	end
	local aliasesDeclarados = {}
	for _, alias in ipairs(programa.aliases or {}) do aliasesDeclarados[alias.nome] = true end
	local nomesFuncoes = {}
	for nome in pairs(programa.funcoes or {}) do
		if aliasesDeclarados[nome] then return false, { erro = "função conflita com alias usar: " .. nome, linha = 0 } end
		if not identificadorValido(nome) then return false, { erro = "nome de função inválido para Luau: " .. tostring(nome), linha = 0 } end
		if SERVICOS[string.lower(nome)] then return false, { erro = "nome de função conflita com serviço Roblox: " .. nome, linha = 0 } end
		for _, declaracoesNomes in ipairs({ programa.elementos or {}, programa.formas or {}, programa.objetos or {}, programa.huds or {} }) do
			if declaracoesNomes[nome] then return false, { erro = "nome de função conflita com objeto declarado: " .. nome, linha = 0 } end
		end
		local interno = nome
		if aliases[nome] then return false, { erro = "nome de função conflita com outro identificador: " .. nome, linha = 0 } end
		aliases[nome] = interno
		LOCAIS_GERADOS[interno] = true
		table.insert(nomesFuncoes, nome)
	end
	table.sort(nomesFuncoes)
	local function coletarLocaisFuncao(corpo, nomes)
		for _, cmd in ipairs(corpo or {}) do
			if cmd.tipo == "variavel" or cmd.tipo == "sortear" then nomes[cmd.nome] = true end
			if cmd.tipo == "clonar" and cmd.nome then nomes[cmd.nome] = true end
			if cmd.corpo then coletarLocaisFuncao(cmd.corpo, nomes) end
			if cmd.senao then coletarLocaisFuncao(cmd.senao, nomes) end
			for _, alternativa in ipairs(cmd.alternativas or {}) do
				coletarLocaisFuncao(alternativa.corpo, nomes)
			end
		end
	end
	local function gerarCorpoComLocais(corpoAst, nivelCorpo, renderizar, contexto)
		local nomesSet, nomes = {}, {}
		coletarLocaisFuncao(corpoAst, nomesSet)
		local aliasesSalvos, locaisSalvos = {}, {}
		for nome in pairs(nomesSet) do
			if not identificadorValido(nome) then
				return nil, "variável local inválida para Luau" .. (contexto and " em `" .. contexto .. "`" or "") .. ": " .. tostring(nome)
			end
			aliasesSalvos[nome] = aliases[nome]
			locaisSalvos[nome] = LOCAIS_GERADOS[nome]
			aliases[nome] = nome
			LOCAIS_GERADOS[nome] = true
			table.insert(nomes, nome)
		end
		table.sort(nomes)
		local corpo, err = blocoNovo(nivelCorpo, renderizar)
		for _, nome in ipairs(nomes) do
			aliases[nome] = aliasesSalvos[nome]
			LOCAIS_GERADOS[nome] = locaisSalvos[nome]
		end
		if not corpo then return nil, err end
		if #nomes > 0 then
			table.insert(corpo, 1, string.rep("\t", nivelCorpo) .. "local " .. table.concat(nomes, ", "))
		end
		return corpo
	end
	local variaveisDeclaradas = {}
	local variaveisSortear = {}
	local variaveisClonar = {}
	local function coletarVariaveis(corpo)
		for _, cmd in ipairs(corpo or {}) do
			if cmd.tipo == "variavel" then variaveisDeclaradas[cmd.nome] = true end
			if cmd.tipo == "sortear" then variaveisSortear[cmd.nome] = true end
			if cmd.tipo == "clonar" and cmd.nome then variaveisClonar[cmd.nome] = true end
			if cmd.corpo then coletarVariaveis(cmd.corpo) end
			if cmd.senao then coletarVariaveis(cmd.senao) end
			for _, alternativa in ipairs(cmd.alternativas or {}) do
				coletarVariaveis(alternativa.corpo)
			end
		end
	end
	coletarVariaveis(programa.comandos)
	for _, ev in ipairs(programa.eventos or {}) do
		if EVENTOS_INLINE[ev.tipo] then coletarVariaveis(ev.corpo) end
	end
	for _, ev in ipairs(programa.continuos or {}) do
		coletarVariaveis(ev.corpo); coletarVariaveis(ev.senao)
		for _, alternativa in ipairs(ev.alternativas or {}) do coletarVariaveis(alternativa.corpo) end
	end
	for _, ev in ipairs(programa.loops or {}) do coletarVariaveis(ev.corpo) end
	for nome in pairs(programa.funcoes or {}) do
		if variaveisDeclaradas[nome] then return false, { erro = "função conflita com variável: " .. nome, linha = 0 } end
	end
	local nomesDeclarados = {}
	for nome in pairs(variaveisDeclaradas) do
		if aliasesDeclarados[nome] then return false, { erro = "variável conflita com alias usar: " .. nome, linha = 0 } end
		if not identificadorValido(nome) then return false, { erro = "nome de variável inválido para Luau: " .. tostring(nome), linha = 0 } end
		aliases[nome] = nome
		LOCAIS_GERADOS[nome] = true
		table.insert(nomesDeclarados, nome)
	end
	table.sort(nomesDeclarados)
	for _, nome in ipairs(nomesDeclarados) do table.insert(inicializadores, "local " .. nome) end
	for _, nome in ipairs(nomesFuncoes) do table.insert(inicializadores, "local " .. aliases[nome]) end
	local sortearNomes = {}
	for nome in pairs(variaveisSortear) do
		if not aliasesDeclarados[nome] and not aliases[nome] and identificadorValido(nome) then
			aliases[nome] = nome
			table.insert(sortearNomes, nome)
		end
	end
	for nome in pairs(variaveisClonar) do
		if aliasesDeclarados[nome] then return false, { erro = "nome de clone conflita com alias usar: " .. nome, linha = 0 } end
		if not aliases[nome] and identificadorValido(nome) then aliases[nome] = nome end
	end
	table.sort(sortearNomes)
	local nomesTemporarios = {}
	for nome in pairs(variaveisClonar) do if aliases[nome] == nome and not variaveisSortear[nome] then table.insert(nomesTemporarios, nome) end end
	table.sort(nomesTemporarios)
	for _, nome in ipairs(sortearNomes) do table.insert(nomesTemporarios, nome) end
	if #nomesTemporarios > 0 then table.insert(inicializadores, "local " .. table.concat(nomesTemporarios, ", ")) end
	for _, nome in ipairs(nomesOrdenados(programa.objetos)) do
		local var = nomeInterno("_dados_", nome)
		if varsCriadas[var] and varsCriadas[var] ~= nome then return false, { erro = "nomes de objetos geram colisao interna: " .. nome, linha = 0 } end
		varsCriadas[var] = nome
		aliases[nome] = var
		objetosDados[nome] = true
		local campos = {}
		local props = programa.objetos[nome] or {}
		for _, k in ipairs((function() local a = {}; for chave in pairs(props) do table.insert(a, chave) end; table.sort(a); return a end)()) do
			local valor = legadoLua(props[k], k, false)
			if valor ~= nil then table.insert(campos, "\t[" .. textoLua(k) .. "] = " .. valor .. ",") end
		end
		table.insert(inicializadores, "local " .. var .. " = {\n" .. table.concat(campos, "\n") .. "\n}")
	end
	local temGui = next(programa.elementos or {}) ~= nil or next(programa.huds or {}) ~= nil or (programa.site and next(programa.site) ~= nil)
	local hudServidor = contexto == "servidor" and next(programa.huds or {}) ~= nil
		and next(programa.elementos or {}) == nil and (not programa.site or next(programa.site) == nil)
	if temGui then
		servico("Players")
		table.insert(inicializadores, 'local _tela = Instance.new("ScreenGui")')
		table.insert(inicializadores, '_tela.Name = "Tela"')
		table.insert(inicializadores, '_tela.ResetOnSpawn = false')
		if hudServidor then
			table.insert(inicializadores, '_tela.Archivable = true')
		elseif contexto == "servidor" then
			return false, { erro = "criar elementos de interface requer LocalScript; no servidor, use criar hud", linha = 0 }
		else
			table.insert(inicializadores, '_tela.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")')
		end
		table.insert(inicializadores, 'local _frameRaiz = Instance.new("Frame")')
		table.insert(inicializadores, '_frameRaiz.Name = "Raiz"')
		table.insert(inicializadores, '_frameRaiz.Size = UDim2.fromScale(1, 1)')
		table.insert(inicializadores, '_frameRaiz.BackgroundTransparency = 1')
		local fundo = programa.site and programa.site.fundo
		if fundo then table.insert(inicializadores, "_frameRaiz.BackgroundColor3 = " .. (legadoLua(fundo, "fundo", true) or "Color3.new(0, 0, 0)")); table.insert(inicializadores, "_frameRaiz.BackgroundTransparency = 0") end
		table.insert(inicializadores, '_frameRaiz.Parent = _tela')
	end
	local classesGui = { painel = "Frame", texto = "TextLabel", botao = "TextButton", campo = "TextBox", imagem = "ImageLabel", elemento = "Frame" }
	local function emitirProps(var, props, gui)
		local chaves = {}
		for k in pairs(props or {}) do table.insert(chaves, k) end
		table.sort(chaves)
		for _, prop in ipairs(chaves) do
			local valor = props[prop]
			if prop == "pai" or prop == "estilo" or prop == "cena" or prop == "arredondamento" or prop == "mostrar" or prop == "inimigo" or prop == "vida" or prop == "velocidade" then
				-- metadados estruturais usados abaixo ou dados de gameplay
			elseif gui and (prop == "largura" or prop == "altura") then
				-- largura/altura são combinadas abaixo numa única atribuição Size.
			elseif prop == "posicao" then
				local cod = legadoLua(valor, prop, gui)
				if cod then table.insert(inicializadores, var .. (gui and ".Position = " or ".Position = ") .. cod) end
			elseif prop == "tamanho" then
				local cod = legadoLua(valor, prop, gui)
				if cod then table.insert(inicializadores, var .. (gui and ".Size = " or ".Size = ") .. cod) end
			else
				local canon = (not gui and prop == "cor") and "Color" or PROPRIEDADES[string.lower(prop)]
				local cod = legadoLua(valor, prop, gui)
				if canon and cod then table.insert(inicializadores, var .. "." .. canon .. " = " .. cod) end
			end
		end
	end
	for _, nome in ipairs(elementosOrdem) do
		local def = programa.elementos[nome]
		local propsBase = def.props or {}
		local estilo = propsBase.estilo and programa.estilos and programa.estilos[propsBase.estilo] or nil
		local props = mesclar(estilo, propsBase)
		local var = nomeInterno("_criado_", nome)
		aliases[nome] = var
		local class = classesGui[def.tipo] or "Frame"
		table.insert(inicializadores, "local " .. var .. " = Instance.new(" .. textoLua(class) .. ")")
		table.insert(inicializadores, var .. ".Name = " .. textoLua(nome))
		if class == "Frame" or class == "TextLabel" or class == "TextButton" or class == "TextBox" then
			table.insert(inicializadores, var .. ".Size = UDim2.fromOffset(100, 40)")
			table.insert(inicializadores, var .. ".BackgroundColor3 = Color3.fromRGB(35, 35, 45)")
		end
		if props.cena then table.insert(inicializadores, var .. ":SetAttribute(\"Cena\", " .. textoLua(props.cena) .. ")") end
		if props.cena and not cenaVisivel(props.cena) then table.insert(inicializadores, var .. ".Visible = false") end
		emitirProps(var, props, true)
		if props.arredondamento then
			local corner = nomeInterno("_canto_", nome)
			table.insert(inicializadores, "local " .. corner .. ' = Instance.new("UICorner")')
			table.insert(inicializadores, corner .. ".CornerRadius = UDim.new(0, " .. numeroLua(tonumber(props.arredondamento) or 8) .. ")")
			table.insert(inicializadores, corner .. ".Parent = " .. var)
		end
		local pai = props.pai and aliases[props.pai] or "_frameRaiz"
		if props.largura or props.altura then
			local largura = tonumber(props.largura) or 100
			local altura = tonumber(props.altura) or 40
			table.insert(inicializadores, var .. ".Size = UDim2.fromOffset(" .. numeroLua(largura) .. ", " .. numeroLua(altura) .. ")")
		end
		table.insert(inicializadores, var .. ".Parent = " .. (pai or "_frameRaiz"))
	end
	local nomesHuds = {}
	local hudsGerados = {}
	for nome in pairs(programa.huds or {}) do table.insert(nomesHuds, nome) end
	table.sort(nomesHuds)
	for indice, nome in ipairs(nomesHuds) do
		local def = programa.huds[nome]
		local var = nomeInterno("_hud_", nome)
		aliases[nome] = var
		table.insert(inicializadores, 'local ' .. var .. ' = Instance.new("TextLabel")')
		table.insert(inicializadores, var .. ".Name = " .. textoLua(nome))
		table.insert(inicializadores, var .. ".Position = UDim2.fromOffset(12, " .. numeroLua((indice - 1) * 32 + 12) .. ")")
		table.insert(inicializadores, var .. ".Size = UDim2.fromOffset(240, 28)")
		table.insert(inicializadores, var .. '.BackgroundTransparency = 1')
		table.insert(inicializadores, var .. '.TextXAlignment = Enum.TextXAlignment.Left')
		table.insert(inicializadores, var .. '.Parent = _frameRaiz')
		local partes = dividirCaminho(def.campo or "")
		local expr = #partes > 1 and { k = "caminho", partes = partes } or { k = "ident", v = partes[1] or "" }
		local valor, err = gerarValor(expr)
		if not valor then return false, { erro = "hud `" .. nome .. "`: " .. tostring(err), linha = 0 } end
		if hudServidor then
			table.insert(hudsGerados, { nome = nome, valor = valor })
		else
			table.insert(inicializadores, "task.spawn(function() while " .. var .. ".Parent do " .. var .. ".Text = " .. textoLua(nome .. ": ") .. " .. tostring(" .. valor .. "); task.wait(0.1) end end)")
		end
	end
	if hudServidor then
		table.insert(inicializadores, "local _criarHUD = function(_jogador)")
		table.insert(inicializadores, "\tlocal _telaJogador = _tela:Clone()")
		table.insert(inicializadores, "\t_telaJogador.Parent = _jogador:WaitForChild(\"PlayerGui\")")
		table.insert(inicializadores, "\ttask.spawn(function()")
		table.insert(inicializadores, "\t\twhile _telaJogador.Parent do")
		for _, hud in ipairs(hudsGerados) do
			local label = nomeInterno("_labelHud_", hud.nome)
			table.insert(inicializadores, "\t\t\tlocal " .. label .. " = _telaJogador:FindFirstChild(" .. textoLua(hud.nome) .. ", true)")
			table.insert(inicializadores, "\t\t\tif " .. label .. " then " .. label .. ".Text = " .. textoLua(hud.nome .. ": ") .. " .. tostring(" .. hud.valor .. ") end")
		end
		table.insert(inicializadores, "\t\t\ttask.wait(0.1)")
		table.insert(inicializadores, "\t\tend")
		table.insert(inicializadores, "\tend)")
		table.insert(inicializadores, "end")
		table.insert(inicializadores, "for _, _jogador in ipairs(Players:GetPlayers()) do _criarHUD(_jogador) end")
		table.insert(inicializadores, "Players.PlayerAdded:Connect(_criarHUD)")
	end
	local classesForma = { bloco = "Block", paralelepipedo = "Block", plataforma = "Block", esfera = "Ball", cilindro = "Cylinder", cunha = "Wedge" }
	local nomesForma = {}
	for nome in pairs(programa.formas or {}) do table.insert(nomesForma, nome) end
	table.sort(nomesForma)
	for _, nome in ipairs(nomesForma) do
		local def = programa.formas[nome]
		local props = def.props or {}
		local var = nomeInterno("_criado_", nome)
		aliases[nome] = var
		table.insert(inicializadores, 'local ' .. var .. ' = Instance.new("Part")')
		table.insert(inicializadores, var .. ".Name = " .. textoLua(nome))
		table.insert(inicializadores, var .. ".Shape = Enum.PartType." .. (classesForma[def.tipo] or "Block"))
		table.insert(inicializadores, var .. ".Anchored = true")
		table.insert(inicializadores, var .. ".CanCollide = true")
		if props.cena then table.insert(inicializadores, var .. ':SetAttribute("Cena", ' .. textoLua(props.cena) .. ")") end
		if props.cena and not cenaVisivel(props.cena) then
			table.insert(inicializadores, var .. ".Transparency = 1")
			table.insert(inicializadores, var .. ".CanCollide = false")
		end
		emitirProps(var, props, false)
		table.insert(inicializadores, var .. ".Parent = Workspace")
		servico("Workspace")
	end
	if next(programa.mundo or {}) ~= nil then
		local mundo = programa.mundo
		servico("Lighting")
		local ordemMundo = { "ceu", "neblina", "neblina_inicio", "neblina_fim" }
		local mapeia = { ceu = "ColorShift_Top", neblina = "FogColor", neblina_inicio = "FogStart", neblina_fim = "FogEnd" }
		for _, chave in ipairs(ordemMundo) do
			local prop = mapeia[chave]
			if mundo[chave] ~= nil then
				local valor = legadoLua(mundo[chave], chave, false)
				if valor then table.insert(inicializadores, "Lighting." .. prop .. " = " .. valor) end
			end
		end
		if mundo.sol then table.insert(inicializadores, "Lighting.ClockTime = 12") end
	end

	-- 1) declaracoes `usar` — sempre primeiro, sao declaracoes
	local declaracoes = {}
	for _, v in ipairs(programa.aliases or {}) do
		if not identificadorValido(v.nome) then
			return false, { erro = '"' .. tostring(v.nome)
				.. '" nao e um identificador valido para Luau (use letras, numeros '
				.. 'e _ sem comecar por numero)', linha = v.linha or 0 }
		end
		local expr = v.expr
		local codigo, err
		if expr.k == "caminho" then
			-- Use o mesmo resolvedor de caminhos/propriedades dos outros valores:
			-- isso permite aliases para propriedades como workspace.CurrentCamera.
			codigo, err = gerarValor(expr)
		elseif expr.k == "ident" and aliases[expr.v] then
			codigo = aliases[expr.v]
		else
			codigo, err = gerarValor(expr)
		end
		if not codigo then
			return false, { erro = "`usar " .. textoLua(v.nome) .. " = ...`: "
				.. tostring(err or "nao foi possivel resolver"), linha = v.linha or 0 }
		end
		aliases[v.nome] = v.nome
		table.insert(declaracoes, { nome = v.nome, codigo = codigo })
	end

	-- 2) eventos
	local eventos = {}
	for _, ev in ipairs(programa.eventos or {}) do
		if EVENTOS_INLINE[ev.tipo] then
			if ev.sujeito then
				return false, { erro = "evento `" .. ev.tipo .. "` nao aceita sujeito "
					.. "(`quando " .. ev.sujeito .. " " .. ev.tipo .. "`)", linha = 0 }
			end
			table.insert(eventos, { tipo = "inline", corpo = ev.corpo })
		else
			local info = EVENTOS[ev.tipo]
			if not info then
				return false, { erro = "evento ainda nao traduzido no caminho direto: "
					.. tostring(ev.tipo), linha = 0 }
			end
			if not ev.alvo then
				return false, { erro = "evento `" .. ev.tipo .. "` precisa de um alvo", linha = 0 }
			end
			-- alvo de Touched nunca mora na GUI: resolve so por alias/servico
			local ref, err = gerarReferencia({ k = "ident", v = ev.alvo }, info.argumento == true)
			if not ref then
				return false, { erro = "alvo do evento `" .. ev.tipo .. "`: " .. tostring(err), linha = 0 }
			end
			-- sujeito: quem dispara o evento. Vale para eventos com argumento
			-- (Touched), onde da para distinguir o que encostou.
			local sujeito = nil
			if ev.sujeito then
				if not info.argumento then
					return false, { erro = "evento `" .. ev.tipo .. "` nao aceita sujeito "
						.. "(`quando " .. ev.sujeito .. " " .. ev.tipo .. "`)", linha = 0 }
				end
				if SUJEITOS_LOGICOS[string.lower(ev.sujeito)] then
					sujeito = { tipo = "logico" }
				else
					local sref, serr = gerarReferencia({ k = "ident", v = ev.sujeito }, true)
					if not sref then
						return false, { erro = "sujeito do evento `" .. ev.tipo .. "`: "
							.. tostring(serr) .. " (e nao e um sujeito logico, como `jogador`)", linha = 0 }
					end
					sujeito = { tipo = "objeto", ref = sref }
				end
			end
			table.insert(eventos, { tipo = "connect", ref = ref, alvo = ev.alvo, info = info,
				sujeito = sujeito, sujeitoNome = ev.sujeito, corpo = ev.corpo })
		end
	end

	-- 3) temporizadores
	local temporizadores = {}
	for _, tmr in ipairs(programa.timers or {}) do
		table.insert(temporizadores, { intervalo = tmr.intervalo, corpo = tmr.corpo })
	end

	-- Inclusões sem conteúdo são um erro de entrada claro. Compilar() expande
	-- arquivos quando o host fornece a tabela; o plugin Studio não possui
	-- acesso a arquivos arbitrários do computador.
	if #(programa.incluir or {}) > 0 then
		return false, { erro = "arquivo incluido nao foi fornecido ao compilador: `" .. tostring(programa.incluir[1])
			.. "` (passe-o na tabela de arquivos de Compilar)", linha = 0 }
	end

	-- 5) renderiza os blocos. Feito ANTES do cabecalho de proposito: um servico
	--    (ou o ScreenGui) usado só dentro de um corpo ainda precisa da local.
	local blocos = {}
	local blocosDef = {}
	local nomesDef = {}
	local funcoesDef = {}
	local listaDef = {}
	for nome in pairs(programa.acoes or {}) do table.insert(listaDef, { nome = nome, tipo = "acao" }) end
	for nome in pairs(programa.animacoes or {}) do table.insert(listaDef, { nome = nome, tipo = "animacao" }) end
	table.sort(listaDef, function(a, b)
		if a.tipo ~= b.tipo then return a.tipo < b.tipo end
		return a.nome < b.nome
	end)
	for _, item in ipairs(listaDef) do
		local fn = item.tipo == "acao" and nomeFnAcao(item.nome) or nomeFnAnim(item.nome)
		if nomesDef[fn] and nomesDef[fn] ~= item.tipo .. ":" .. item.nome then
			return false, { erro = "funcoes `" .. nomesDef[fn] .. "` e `" .. item.tipo .. ":" .. item.nome .. "` geram o mesmo nome interno `" .. fn .. "`", linha = 0 }
		end
		nomesDef[fn] = item.tipo .. ":" .. item.nome
		funcoesDef[item.tipo .. ":" .. item.nome] = fn
	end
	if #listaDef > 0 then
		local nomes = {}
		for _, item in ipairs(listaDef) do table.insert(nomes, funcoesDef[item.tipo .. ":" .. item.nome]) end
		table.insert(blocosDef, { "local " .. table.concat(nomes, ", ") })
	end

	-- comandos soltos de nivel superior: print(...), mostrar Cubo, ...
	if #(programa.comandos or {}) > 0 then
		local corpo, err = blocoNovo(0, function()
			return gerarCorpo(programa.comandos, 0)
		end)
		if not corpo then return false, { erro = err, linha = 0 } end
		if #corpo > 0 then table.insert(blocos, corpo) end
	end

	-- 5b) animacoes criadas: cada uma vira uma funcao local com os passos em
	--     sequencia (espera a duracao de um passo antes do proximo)
	local nomeAnims = {}
	if programa.animacoes then
		for nome in pairs(programa.animacoes) do
			table.insert(nomeAnims, nome)
		end
	end
	table.sort(nomeAnims)
	local fnVistas = {}
	for _, nome in ipairs(nomeAnims) do
		local fnNome = nomeFnAnim(nome)
		if fnVistas[fnNome] and fnVistas[fnNome] ~= nome then
			return false, { erro = "animacoes `" .. fnVistas[fnNome] .. "` e `" .. nome
				.. "` geram o mesmo nome interno `" .. fnNome .. "`", linha = 0 }
		end
		fnVistas[fnNome] = nome
		local passos = programa.animacoes[nome].lista or {}
		local corpo, err = blocoNovo(0, function()
			for i, passo in ipairs(passos) do
				local onde = "animacao `" .. nome .. "` passo " .. i
				local spec, serr = specDeAnim(passo, onde)
				if not spec then return nil, serr end
				if spec.animacao then
					return nil, "animacao `" .. nome .. "` passo " .. i
						.. " nao pode chamar outra animacao (`" .. spec.animacao .. "`)"
				end
				local ok, e = aplicarSpecNoRef("inst", spec, onde)
				if not ok then return nil, e end
				if i < #passos then
					emitir("task.wait(" .. numeroLua((spec.duracao or 0.3) + 0.05) .. ")")
				end
			end
			return ""
		end)
		if not corpo then return false, { erro = err, linha = 0 } end
		local bloco = { fnNome .. " = function(inst)" }
		for _, linha in ipairs(corpo) do
			table.insert(bloco, "\t" .. linha)
		end
		table.insert(bloco, "end")
		table.insert(blocosDef, bloco)
	end

	-- ações nomeadas viram funções locais Luau e podem chamar umas às outras.
	local nomesAcoes = {}
	for nome in pairs(programa.acoes or {}) do table.insert(nomesAcoes, nome) end
	table.sort(nomesAcoes)
	for _, nome in ipairs(nomesAcoes) do
		local fn = funcoesDef["acao:" .. nome]
		local anterior = alvoEvento
		alvoEvento = "_acaoAlvo"
		local funcaoAnterior = dentroFuncao
		dentroFuncao = true
		local corpo, err = gerarCorpoComLocais(programa.acoes[nome], 1, function()
			return gerarCorpo(programa.acoes[nome], 0)
		end, "ação " .. nome)
		dentroFuncao = funcaoAnterior
		alvoEvento = anterior
		if not corpo then return false, { erro = "acao `" .. nome .. "`: " .. tostring(err), linha = 0 } end
		local bloco = { fn .. " = function(_acaoAlvo)" }
		for _, linha in ipairs(corpo) do table.insert(bloco, linha) end
		table.insert(bloco, "end")
		table.insert(blocosDef, bloco)
	end

	for _, nome in ipairs(nomesFuncoes) do
		local definicao = programa.funcoes[nome]
		local parametros = definicao.parametros or {}
		local aliasesSalvos, locaisSalvos = {}, {}
		for _, parametro in ipairs(parametros) do
			if not identificadorValido(parametro) then
				return false, { erro = "parâmetro inválido para Luau em `" .. nome .. "`: " .. tostring(parametro), linha = 0 }
			end
			aliasesSalvos[parametro] = aliases[parametro]
			locaisSalvos[parametro] = LOCAIS_GERADOS[parametro]
			aliases[parametro] = parametro
			LOCAIS_GERADOS[parametro] = true
		end
		local nomesLocaisSet, nomesLocais = {}, {}
		coletarLocaisFuncao(definicao.corpo, nomesLocaisSet)
		for nomeLocal in pairs(nomesLocaisSet) do
			if not identificadorValido(nomeLocal) then
				return false, { erro = "variável local inválida para Luau em `" .. nome .. "`: " .. tostring(nomeLocal), linha = 0 }
			end
			aliasesSalvos[nomeLocal] = aliases[nomeLocal]
			locaisSalvos[nomeLocal] = LOCAIS_GERADOS[nomeLocal]
			aliases[nomeLocal] = nomeLocal
			LOCAIS_GERADOS[nomeLocal] = true
			table.insert(nomesLocais, nomeLocal)
		end
		table.sort(nomesLocais)
		local antes = dentroFuncao
		dentroFuncao = true
		local corpo, err = blocoNovo(1, function() return gerarCorpo(definicao.corpo, 0) end)
		dentroFuncao = antes
		for _, nomeLocal in ipairs(nomesLocais) do
			aliases[nomeLocal] = aliasesSalvos[nomeLocal]
			LOCAIS_GERADOS[nomeLocal] = locaisSalvos[nomeLocal]
		end
		for _, parametro in ipairs(parametros) do
			aliases[parametro] = aliasesSalvos[parametro]
			LOCAIS_GERADOS[parametro] = locaisSalvos[parametro]
		end
		if not corpo then return false, { erro = "função `" .. nome .. "`: " .. tostring(err), linha = 0 } end
		local bloco = { aliases[nome] .. " = function(" .. table.concat(parametros, ", ") .. ")" }
		if #nomesLocais > 0 then table.insert(bloco, "\tlocal " .. table.concat(nomesLocais, ", ")) end
		for _, linha in ipairs(corpo) do table.insert(bloco, linha) end
		table.insert(bloco, "end")
		table.insert(blocosDef, bloco)
	end

	for _, ev in ipairs(eventos) do
		if ev.tipo == "connect" then
			local arg = ev.info.argumento and "_alvo" or ""
			local repete = ev.info.repete == true
			local corpo, err
			local anterior = alvoEvento
			local eventoAnterior = eventoAtual
			alvoEvento = ev.alvo
			eventoAtual = { tipo = ev.info.evento == "MouseButton1Click" and "clicar" or ev.info.evento, alvo = ev.alvo }
			-- a DSL usa o nome do evento, enquanto o gerador armazena o nome Roblox.
			for nomeEvento, infoEvento in pairs(EVENTOS) do
				if infoEvento.evento == ev.info.evento then eventoAtual.tipo = nomeEvento; break end
			end
			local funcaoAnterior = dentroFuncao
			dentroFuncao = true
			corpo, err = gerarCorpoComLocais(ev.corpo, repete and 2 or 1, function()
				return gerarCorpo(ev.corpo, 0)
			end, "evento " .. tostring(ev.tipo))
			dentroFuncao = funcaoAnterior
			alvoEvento = anterior
			eventoAtual = eventoAnterior
			if not corpo then return false, { erro = err, linha = 0 } end

			local bloco = {}
			local ind = repete and "\t" or ""
			if repete then
				-- ultimoToque vive num escopo proprio: cada evento tem o dele
				table.insert(bloco, "do")
				table.insert(bloco, "\tlocal _ultimoToque = 0")
			end
			table.insert(bloco, ind .. ev.ref .. "." .. ev.info.evento
				.. ":Connect(function(" .. arg .. ")")
			if repete and ev.sujeito then
				-- mesma ordem do Runtime legado: primeiro o sujeito, depois o
				-- debounce -- um toque que nao e do sujeito nao consome a janela
				table.insert(bloco, "\t\tlocal _personagem = _alvo:FindFirstAncestorOfClass(\"Model\")")
				if ev.sujeito.tipo == "logico" then
					table.insert(bloco, "\t\tif not (_personagem and _personagem:FindFirstChildOfClass(\"Humanoid\")) then return end")
				else
					local ref = ev.sujeito.ref
					table.insert(bloco, "\t\tlocal _doSujeito = _alvo:IsDescendantOf(" .. ref
						.. ") or " .. ref .. ":IsDescendantOf(_alvo)")
					table.insert(bloco, "\t\t\tor (_personagem and (_personagem:IsDescendantOf(" .. ref
						.. ") or " .. ref .. ":IsDescendantOf(_personagem)))")
					table.insert(bloco, "\t\tif not _doSujeito then return end")
				end
			end
			if repete then
				table.insert(bloco, "\t\tlocal _agora = os.clock()")
				table.insert(bloco, "\t\tif _agora - _ultimoToque < "
					.. numeroLua(DEBOUNCE_TOQUE) .. " then return end")
				table.insert(bloco, "\t\t_ultimoToque = _agora")
			end
			for _, linha in ipairs(corpo) do table.insert(bloco, linha) end
			if repete then
				table.insert(bloco, "\tend)")
				table.insert(bloco, "end")
			else
				table.insert(bloco, "end)")
			end
			table.insert(blocos, bloco)
		else
			-- evento inline (iniciar / carregar): roda direto no topo
			local eventoAnterior = eventoAtual
			eventoAtual = { tipo = ev.tipo, alvo = nil }
			local corpo, err = blocoNovo(0, function()
				return gerarCorpo(ev.corpo, 0)
			end)
			eventoAtual = eventoAnterior
			if not corpo then return false, { erro = err, linha = 0 } end
			table.insert(blocos, corpo)
		end
	end

	-- Condicionais de topo sao avaliadas uma vez na inicializacao; laços de
	-- topo permanecem ativos durante a vida do script.
	for _, c in ipairs(programa.continuos or {}) do
		local cond, err = gerarCondicao(c.cond)
		if not cond then return false, { erro = err, linha = 0 } end
		local corpo, e = blocoNovo(1, function() return gerarCorpo(c.corpo, 0) end)
		if not corpo then return false, { erro = e, linha = 0 } end
		local bloco = { "if " .. cond .. " then" }
		for _, linha in ipairs(corpo) do table.insert(bloco, linha) end
		for _, alternativa in ipairs(c.alternativas or {}) do
			local condAlt, errAlt = gerarCondicao(alternativa.cond)
			if not condAlt then return false, { erro = errAlt, linha = 0 } end
			local alt, errCorpo = blocoNovo(1, function() return gerarCorpo(alternativa.corpo, 0) end)
			if not alt then return false, { erro = errCorpo, linha = 0 } end
			table.insert(bloco, "elseif " .. condAlt .. " then")
			for _, linha in ipairs(alt) do table.insert(bloco, linha) end
		end
		if c.senao and #c.senao > 0 then
			table.insert(bloco, "else")
			local sen, se = blocoNovo(1, function() return gerarCorpo(c.senao, 0) end)
			if not sen then return false, { erro = se, linha = 0 } end
			for _, linha in ipairs(sen) do table.insert(bloco, linha) end
		end
		table.insert(bloco, "end")
		table.insert(blocos, bloco)
	end

	-- `enquanto` de topo: laço direto, sem intermediario
	for _, lp in ipairs(programa.loops or {}) do
		local cond, err = gerarCondicao(lp.cond)
		if not cond then return false, { erro = err, linha = 0 } end
		local corpo, e = blocoNovo(1, function()
			return gerarCorpo(lp.corpo, 0)
		end)
		if not corpo then return false, { erro = e, linha = 0 } end
		local bloco = { "while " .. cond .. " do" }
		for _, linha in ipairs(corpo) do table.insert(bloco, linha) end
		table.insert(bloco, "end")
		table.insert(blocos, bloco)
	end

	for _, tmr in ipairs(temporizadores) do
		local funcaoAnterior = dentroFuncao
		dentroFuncao = true
		local corpo, err = gerarCorpoComLocais(tmr.corpo, 1, function()
			return gerarCorpo(tmr.corpo, 0)
		end, "temporizador")
		dentroFuncao = funcaoAnterior
		if not corpo then return false, { erro = err, linha = 0 } end
		local bloco = { "task.spawn(function()" }
		if corpo[1] and string.sub(corpo[1], 1, 7) == "\tlocal " then
			table.insert(bloco, corpo[1])
			table.remove(corpo, 1)
		end
		table.insert(bloco, "\twhile true do")
		for _, linha in ipairs(corpo) do table.insert(bloco, "\t" .. linha) end
		table.insert(bloco, "\t\ttask.wait(" .. numeroLua(tmr.intervalo) .. ")")
		table.insert(bloco, "\tend")
		table.insert(bloco, "end)")
		table.insert(blocos, bloco)
	end

	-----------------------------------------------------------------------
	-- monta o texto final
	-----------------------------------------------------------------------

	-- local do ScreenGui quando o script vive dentro de um
	if usadoRaiz then
		table.insert(linhas, "")
		table.insert(linhas, 'local _raiz = script:IsA("ScreenGui") and script '
			.. 'or script:FindFirstAncestorWhichIsA("ScreenGui")')
	end

	-- locals dos servicos usados
	local ordem = {}
	for canonico in pairs(servicosUsados) do table.insert(ordem, canonico) end
	table.sort(ordem)
	if #ordem > 0 then
		table.insert(linhas, "")
		for _, canonico in ipairs(ordem) do
			table.insert(linhas, 'local ' .. canonico .. ' = game:GetService("'
				.. canonico .. '")')
		end
	end
	for _, linha in ipairs(inicializadores) do table.insert(linhas, linha) end

	-- aliases
	for _, d in ipairs(declaracoes) do
		table.insert(linhas, "")
		table.insert(linhas, "local " .. d.nome .. " = " .. d.codigo)
	end

	-- funções locais são definidas antes dos comandos executáveis para que
	-- chamadas no topo e referências entre ações sejam válidas.
	for _, bloco in ipairs(blocosDef) do
		table.insert(linhas, "")
		for _, l in ipairs(bloco) do table.insert(linhas, l) end
	end

	-- eventos e temporizadores (ja renderizados)
	for _, bloco in ipairs(blocos) do
		table.insert(linhas, "")
		for _, l in ipairs(bloco) do table.insert(linhas, l) end
	end

	-- ModuleScript: expoe os aliases como tabela
	if modulo then
		table.insert(linhas, "")
		if #declaracoes > 0 or #nomesFuncoes > 0 then
			local partes = {}
			for _, d in ipairs(declaracoes) do
				table.insert(partes, "\t" .. d.nome .. " = " .. d.nome .. ",")
			end
			for _, nome in ipairs(nomesFuncoes) do
				table.insert(partes, "\t" .. nome .. " = " .. aliases[nome] .. ",")
			end
			table.insert(linhas, "return {\n" .. JUNTAR(partes, "\n") .. "\n}")
		else
			table.insert(linhas, "return {}")
		end
	end

	return true, JUNTAR(linhas, "\n") .. "\n"
end

Gerador.GerarLuau = GerarLuau

return Gerador
