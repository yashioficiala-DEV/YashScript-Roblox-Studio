--[[
  YashScript V8.1 — Núcleo do compilador: lexer + parser (Luau puro, sem Roblox)

  ARQUITETURA ATUAL (V8.1)
    YashScript  ->  Compilar  ->  programa  ->  gerador.GerarLuau  ->  Luau puro

  Este arquivo cuida da PRIMEIRA etapa: tokenizar e produzir o programa
  (a estrutura intermediária). A tradução para Luau mora em gerador.lua, e o
  Source do Script recebe só o Luau — sem `_YashConfig`, sem interpretador.

  O parser devolve uma estrutura intermediária exclusiva do compilador. O
  plugin grava a fonte original no atributo "YashScript" e escreve Luau
  direto no Source; não há runtime interpretado no pipeline V8.

  Funciona fora do Roblox (Lua 5.1+), o que permite testar a gramática localmente.

  Uso:
    local compilador = require(script.compilador)   -- ou dofile no host
    local ok, resultado = compilador.Compilar(fonte)
    -- ok = true  -> resultado = programa (estrutura intermediária)
    -- ok = false -> resultado = { erro = "mensagem", linha = n }
]]

local Compilador = { VERSAO = "8.1" }

local EMPILHAR = table.insert

-----------------------------------------------------------------------
-- LEXER
-----------------------------------------------------------------------

-- produz: { t = "palavra|numero|string|simbolo|nova", v = valor, l = linha, ini, fim }
local function tokenizar(texto)
	local toks = {}
	local i, n = 1, #texto
	local linha = 1

	local function lerNumero(inicio, sinal)
		local num = sinal or ""
		if sinal then i = i + 1 end
		while i <= n and string.match(texto:sub(i, i), "%d") do
			num = num .. texto:sub(i, i)
			i = i + 1
		end
		if texto:sub(i, i) == "." and string.match(texto:sub(i + 1, i + 1), "%d") then
			num = num .. "."
			i = i + 1
			while i <= n and string.match(texto:sub(i, i), "%d") do
				num = num .. texto:sub(i, i)
				i = i + 1
			end
		end
		-- Expoente: 1e7 / 1E-7 / 2.5e+3. Sem isso "1e-7" virava "1 e -7".
		if texto:sub(i, i):match("[eE]") then
			local expo = texto:sub(i, i)
			local sExpo = texto:sub(i + 1, i + 1)
			if sExpo == "+" or sExpo == "-" then
				expo = expo .. sExpo
				i = i + 2 -- pula o sinal: o digito vem DEPOIS dele
			end
			local digitos = ""
			while i <= n and texto:sub(i, i):match("%d") do
				digitos = digitos .. texto:sub(i, i)
				i = i + 1
			end
			-- "1e" sem digitos NAO e numero: devolve os caracteres.
			if digitos ~= "" then
				num = num .. expo .. digitos
			else
				i = i - #expo
			end
		end
		local valor = tonumber(num)
		if valor == nil then
			error("número inválido: " .. num, 0)
		end
		EMPILHAR(toks, { t = "numero", v = valor, l = linha, ini = inicio, fim = i - 1 })
	end

	while i <= n do
		local c = texto:sub(i, i)
		if c == "\n" then
			EMPILHAR(toks, { t = "nova", l = linha, ini = i, fim = i })
			linha = linha + 1
			i = i + 1
		elseif c == " " or c == "\t" or c == "\r" then
			i = i + 1
		elseif c == "#" then
			-- comentário até o fim da linha
			local fimLinha = string.find(texto, "\n", i, true)
			if fimLinha then i = fimLinha else i = n + 1 end
		elseif c == '"' or c == "'" then
			local ini = i
			local aspas = c
			local buf = {}
			i = i + 1
			while i <= n do
				local cc = texto:sub(i, i)
				if cc == "\\" then
					local nx = texto:sub(i + 1, i + 1)
					if nx == aspas then EMPILHAR(buf, aspas); i = i + 2
					elseif nx == "n" then EMPILHAR(buf, "\n"); i = i + 2
					elseif nx == "t" then EMPILHAR(buf, "\t"); i = i + 2
					elseif nx == "\\" then EMPILHAR(buf, "\\"); i = i + 2
					elseif nx == "r" then EMPILHAR(buf, "\r"); i = i + 2
					elseif nx:match("%d") then
						-- Escape decimal \ddd: e o que o gerador emite para
						-- caracteres de controle. Sem isso o ciclo nao fecha.
						local d = texto:sub(i + 1, i + 3)
						if d:match("^%d%d%d$") then
							EMPILHAR(buf, string.char(tonumber(d)))
							i = i + 4
						else
							EMPILHAR(buf, cc); i = i + 1
						end
					else EMPILHAR(buf, cc); i = i + 1 end
				elseif cc == aspas then
					i = i + 1
					break
				elseif cc == "\n" then
					break
				else
					EMPILHAR(buf, cc)
					i = i + 1
				end
			end
			EMPILHAR(toks, { t = "string", v = table.concat(buf), l = linha, ini = ini, fim = i - 1 })
		elseif string.match(c, "%d") then
			lerNumero(i, nil)
		elseif string.match(c, "%a") or c == "_" then
			local ini = i
			local palavra = ""
			while i <= n and string.match(texto:sub(i, i), "[%a_%d]") do
				palavra = palavra .. texto:sub(i, i)
				i = i + 1
			end
			EMPILHAR(toks, { t = "palavra", v = palavra, l = linha, ini = ini, fim = i - 1 })
		else
			-- símbolos de 2 caracteres primeiro
			local dois = texto:sub(i, i + 1)
			if dois == "<=" or dois == ">=" or dois == "==" or dois == "!="
				or dois == "~=" or dois == ".." or dois == "//" then
				EMPILHAR(toks, { t = "simbolo", v = dois, l = linha, ini = i, fim = i + 1 })
				i = i + 2
			elseif dois == "+=" or dois == "-=" then
				-- atribuição composta (jogador.moedas += 1)
				EMPILHAR(toks, { t = "simbolo", v = dois, l = linha, ini = i, fim = i + 1 })
				i = i + 2
			elseif c == "(" or c == ")" or c == "[" or c == "]" or c == "{" or c == "}"
				or c == "=" or c == "," or c == ";" or c == "+" or c == "-"
				or c == "*" or c == "/" or c == "%" or c == "^" or c == "."
				or c == "<" or c == ">" or c == "!" or c == ":" then
				EMPILHAR(toks, { t = "simbolo", v = c, l = linha, ini = i, fim = i })
				i = i + 1
			else
				error({ erro = "caractere inesperado '" .. c .. "'", linha = linha }, 0)
			end
		end
	end
	return toks
end

-----------------------------------------------------------------------
-- PARSER
-----------------------------------------------------------------------

-- config inicial
local function novaConfig()
	return {
		incluir = {},
		aliases = {},
		comandos = {},
		site = {},
		mundo = {},
		estilos = {},
		cenas = {},
		elementos = {},
		formas = {},
		objetos = {},
		variaveis = {},
		huds = {},
		acoes = {},
		funcoes = {},
		animacoes = {},
		eventos = {},
		continuos = {},
		loops = {},
		timers = {},
		proibicoes = {},
		ordem_elementos = {},
	}
end

-- eventos aceitos em blocos "quando". Serve para distinguir a forma legada
-- ("quando tocar 'moeda'") da forma com sujeito ("quando jogador tocar moeda"):
-- se a primeira palavra NÃO for um evento conhecido, ela é o sujeito.
local EVENTOS_CONHECIDOS = {
	carregar = true,
	iniciar = true,
	tocar = true,
	encostar = true,
	clicar = true,
	mouse_em = true,
	mouse_sair = true,
}

-- Eventos em que o proprio sujeito e o alvo.
-- Para clicar/mouse_em/mouse_sair o sujeito vira o alvo, e ai as duas formas
-- valem:
--     quando clicar Botao      (alvo depois do evento)
--     quando Botao clicar      (sujeito antes do evento)
-- Para tocar nao: emissor e alvo sao sempre separados.
--     quando Cubo tocar moeda
local EMISSOR_PROPRIO = {
	clicar = true,
	mouse_em = true,
	mouse_sair = true,
}

local function analisar(fonte, toks)
	local config = novaConfig()
	local idx = 1
	local funcoesDeclaradas = {}
	for pos = 1, #toks - 2 do
		if toks[pos].t == "palavra" and toks[pos].v == "criar"
			and toks[pos + 1] and toks[pos + 1].t == "palavra" and toks[pos + 1].v == "funcao"
			and toks[pos + 2] and toks[pos + 2].t == "palavra" then
			funcoesDeclaradas[toks[pos + 2].v] = true
		end
	end

	local function at() return toks[idx] end

	local function avancar() idx = idx + 1 end

	local function fimLinha()
		local t = at()
		return t == nil or t.t == "nova"
	end

	local function pularNovas()
		while at() and at().t == "nova" do avancar() end
	end

	local function erroJ(msg)
		local l = 0
		if at() and at().l then l = at().l end
		error({ erro = msg, linha = l }, 0)
		return nil
	end

	local function espera(tipo, val)
		local t = at()
		if not t then erroJ("fim inesperado do arquivo") end
		if t.t ~= tipo then erroJ("esperava " .. tipo .. " mas veio '" .. tostring(t.v) .. "'") end
		if val and tostring(t.v) ~= val then erroJ("esperava '" .. val .. "' mas veio '" .. tostring(t.v) .. "'") end
		avancar()
		return t.v
	end

	-- aceita nome entre aspas OU identificador simples
	local function esperaNome()
		local t = at()
		if not t then erroJ("nome esperado (entre aspas ou identificador)") end
		if t.t == "string" or t.t == "palavra" then
			avancar()
			return t.v
		end
		return erroJ("nome esperado (entre aspas ou identificador)")
	end

	-- caminho: jogador.vida  ou  apenas jogador
	local function lerCaminho()
		local t = at()
		if not t or t.t ~= "palavra" then erroJ("nome de objeto esperado") end
		local nome = t.v
		avancar()
		if at() and at().t == "simbolo" and at().v == "." then
			avancar()
			local atrib = espera("palavra")
			return nome .. "." .. atrib
		end
		return nome
	end

	-- aceita "Nome", Nome ou Nome.filho.neto (varios niveis) — usado por
	-- comandos com alvo, como `animar("Gui.Botao")`, onde o alvo pode ser
	-- um caminho completo da arvore
	local function lerNomeCaminho()
		local t = at()
		if not t then erroJ("nome esperado") end
		if t.t == "string" then avancar(); return t.v end
		if t.t ~= "palavra" then erroJ("nome esperado (entre aspas ou identificador)") end
		local nome = t.v
		avancar()
		while at() and at().t == "simbolo" and at().v == "." do
			avancar()
			nome = nome .. "." .. espera("palavra")
		end
		return nome
	end

	-- converte o texto de caminho (A.B.C) no valor rico `caminho` do gerador
	local function exprCaminho(caminho)
		local e = { k = "caminho", partes = {} }
		for p in string.gmatch(tostring(caminho), "[^%.]+") do
			table.insert(e.partes, p)
		end
		return e
	end

	-- extrai o texto exato de um trecho de tokens (preserva "0px", "0.4s" etc.)
	local function textoTrecho(inic, fimm)
		local t1 = toks[inic]
		local t2 = toks[fimm]
		local t = fonte:sub(t1.ini, t2.fim)
		t = string.gsub(t, "^%s+", "")
		t = string.gsub(t, "%s+$", "")
		return t
	end

	-- classifica uma lista de índices de tokens como valor
	--
	-- YASHSCRIPT: além dos formatos legados, o classificador reconhece valores
	-- "ricos" que o gerador de Luau consome diretamente:
	--   k = "caminho" -> A.B.C   (caminho da árvore do Roblox ou alias)
	--   k = "ident"   -> palavra (nome solto: alias, serviço ou constante)
	--   k = "bool"    -> verdadeiro / falso / sim / nao
	--   k = "nulo"    -> nulo
	-- `valorFinal` continua convertendo tudo para o formato legado, então o
	-- comportamento antigo dos blocos `criar` não muda.
	local PRECEDENCIA_EXPR = {
		["ou"] = 1, ["or"] = 1, ["e"] = 2, ["and"] = 2,
		["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3,
		["="] = 3, ["=="] = 3, ["!="] = 3, ["~="] = 3,
		[".."] = 4, ["+"] = 5, ["-"] = 5,
		["*"] = 6, ["/"] = 6, ["//"] = 6, ["%"] = 6, ["^"] = 7,
	}
	local function analisarExpressao(indices)
		local pos = 1
		local function tokenAtual() return indices[pos] and toks[indices[pos]] end
		local parseExpressao
		local function primario()
			local tk = tokenAtual()
			if not tk then return nil end
			if tk.t == "simbolo" and (tk.v == "-" or tk.v == "+") then
				pos = pos + 1
				local v = primario()
				if not v then return nil end
				return { k = "unario", op = tk.v, valor = v }
			end
			if tk.t == "palavra" and (tk.v == "nao" or tk.v == "not") then
				pos = pos + 1
				local v = primario()
				if not v then return nil end
				return { k = "unario", op = "not", valor = v }
			end
			local function lerArgumentos(fecho)
				local args = {}
				pos = pos + 1
				if tokenAtual() and tokenAtual().t == "simbolo" and tokenAtual().v == fecho then
					pos = pos + 1
					return args
				end
			while true do
				local arg = parseExpressao(1)
				if not arg then return nil end
				table.insert(args, arg)
				if tokenAtual() and tokenAtual().t == "simbolo" and tokenAtual().v == "," then
					pos = pos + 1
				else break end
			end
			if not tokenAtual() or tokenAtual().t ~= "simbolo" or tokenAtual().v ~= fecho then return nil end
			pos = pos + 1
			return args
		end
			local function sufixos(expr)
				while tokenAtual() do
					local prox = tokenAtual()
					if prox.t == "simbolo" and prox.v == "." then
						local nome = indices[pos + 1] and toks[indices[pos + 1]]
						if not nome or nome.t ~= "palavra" then return nil end
						pos = pos + 2
						if expr.k == "ident" then
							expr = { k = "caminho", partes = { expr.v, nome.v } }
						elseif expr.k == "caminho" then
							table.insert(expr.partes, nome.v)
						else
							expr = { k = "membro", base = expr, nome = nome.v }
						end
					elseif prox.t == "simbolo" and prox.v == "[" then
						pos = pos + 1
						local chave = parseExpressao(1)
						if not chave or not tokenAtual() or tokenAtual().t ~= "simbolo" or tokenAtual().v ~= "]" then return nil end
						pos = pos + 1
						expr = { k = "indice", base = expr, chave = chave }
					elseif prox.t == "simbolo" and prox.v == "(" then
						local args = lerArgumentos(")")
						if not args then return nil end
						expr = { k = "chamada", alvo = expr, args = args }
					elseif prox.t == "simbolo" and prox.v == ":" then
						local metodo = indices[pos + 1] and toks[indices[pos + 1]]
						if not metodo or metodo.t ~= "palavra" or not indices[pos + 2]
							or toks[indices[pos + 2]].v ~= "(" then return nil end
						pos = pos + 2
						local args = lerArgumentos(")")
						if not args then return nil end
						expr = { k = "metodo_expr", base = expr, metodo = metodo.v, args = args }
					else
						break
					end
				end
				return expr
			end

			local expr
			if tk.t == "numero" then pos = pos + 1; expr = { k = "num", v = tk.v }
			elseif tk.t == "string" then pos = pos + 1; expr = { k = "str", v = tk.v }
			elseif tk.t == "simbolo" and tk.v == "(" then
				pos = pos + 1
				expr = parseExpressao(1)
				if not expr or not tokenAtual() or tokenAtual().v ~= ")" then return nil end
				pos = pos + 1
			elseif tk.t == "simbolo" and tk.v == "{" then
				pos = pos + 1
				local campos = {}
				while tokenAtual() and not (tokenAtual().t == "simbolo" and tokenAtual().v == "}") do
					local chave, valor
					local atual = tokenAtual()
					if atual.t == "simbolo" and atual.v == "[" then
						pos = pos + 1
						chave = parseExpressao(1)
						if not chave or not tokenAtual() or tokenAtual().v ~= "]" then return nil end
						pos = pos + 1
						if not tokenAtual() or tokenAtual().v ~= "=" then return nil end
						pos = pos + 1
						valor = parseExpressao(1)
					elseif (atual.t == "palavra" or atual.t == "string") and indices[pos + 1]
						and toks[indices[pos + 1]].t == "simbolo" and toks[indices[pos + 1]].v == "=" then
						chave = { k = "str", v = atual.v }
						pos = pos + 2
						valor = parseExpressao(1)
					else
						valor = parseExpressao(1)
					end
					if not valor then return nil end
					table.insert(campos, { chave = chave, valor = valor })
					if tokenAtual() and tokenAtual().t == "simbolo" and tokenAtual().v == "," then
						pos = pos + 1
					else break end
				end
				if not tokenAtual() or tokenAtual().t ~= "simbolo" or tokenAtual().v ~= "}" then return nil end
				pos = pos + 1
				expr = { k = "tabela", campos = campos }
			elseif tk.t == "palavra" then
				pos = pos + 1
				local baixo = string.lower(tk.v)
				if baixo == "verdadeiro" or baixo == "sim" then expr = { k = "bool", v = true }
				elseif baixo == "falso" or baixo == "nao" then expr = { k = "bool", v = false }
				elseif baixo == "nulo" then expr = { k = "nulo" }
				else expr = { k = "ident", v = tk.v }
				end
			else return nil end
			return sufixos(expr)
		end
		parseExpressao = function(min)
			local esquerda = primario()
			if not esquerda then return nil end
			while tokenAtual() do
				local tk = tokenAtual()
				local op = tk.v
				if tk.t == "palavra" then op = string.lower(op) end
				local prec = PRECEDENCIA_EXPR[op]
				if not prec or prec < min then break end
				pos = pos + 1
				local direita = parseExpressao(prec + ((op == "^" or op == "..") and 0 or 1))
				if not direita then return nil end
				esquerda = { k = "binario", op = op, esq = esquerda, dir = direita }
			end
			return esquerda
		end
		local expr = parseExpressao(1)
		if expr and pos > #indices then return expr end
		return nil
	end

	local function classificarClausula(c)
		if #c == 1 then
			local tk1 = toks[c[1]]
			if tk1.t == "string" then return { k = "str", v = tk1.v }
			elseif tk1.t == "numero" then return { k = "num", v = tk1.v }
			elseif tk1.t == "palavra" then
				local l = string.lower(tostring(tk1.v))
				if l == "verdadeiro" or l == "sim" then return { k = "bool", v = true }
				elseif l == "falso" or l == "nao" then return { k = "bool", v = false }
				elseif l == "nulo" then return { k = "nulo" }
				end
				return { k = "ident", v = tk1.v }
			end
		end
		local texto = textoTrecho(c[1], c[#c])
		-- cor: rgb(r,g,b) / rgba(r,g,b,a)  -> tokens: palavra "rgb", "(", num, ",", num, ",", num, [",",num,] ")"
		local t1 = toks[c[1]]
		local t2 = toks[c[2]]
		if t1.t == "palavra" and (t1.v == "rgb" or t1.v == "rgba") and t2 and t2.t == "simbolo" and t2.v == "(" then
			local args = {}
			local j = 3
			while j <= #c do
				local tkj = toks[c[j]]
				if tkj.t == "numero" then EMPILHAR(args, tkj.v) end
				j = j + 1
			end
			if #args >= 3 then
				return { k = "cor", r = args[1], g = args[2], b = args[3] }
			end
			erroJ("cor inválida: " .. texto)
		end
		-- par triplo: (x, y)  ou  (x, y, z)
		if t1.t == "simbolo" and t1.v == "(" and toks[c[#c]].t == "simbolo" and toks[c[#c]].v == ")" then
			local args = {}
			local temVirgula = false
			local sinal = 1
			local esperaValor, tuplaSimples = true, true
			for j = 2, #c - 1 do
				local tkj = toks[c[j]]
				if tkj.t == "simbolo" and tkj.v == "," and not esperaValor then
					temVirgula = true
					esperaValor = true
					sinal = 1
				elseif tkj.t == "simbolo" and esperaValor and (tkj.v == "-" or tkj.v == "+") then
					sinal = tkj.v == "-" and -1 or 1
				elseif tkj.t == "numero" and esperaValor then
					EMPILHAR(args, sinal * tkj.v)
					esperaValor = false
				else
					tuplaSimples = false
					break
				end
			end
			if tuplaSimples and temVirgula and not esperaValor and #args >= 2 then
				local r = { k = "par", x = args[1], y = args[2] }
				if #args >= 3 then r.z = args[3] end
				return r
			end
		end
		-- caminho: palavra (. palavra)*     ->  A.B.C
		local partes = {}
		local ehCaminho = true
		local j = 1
		while j <= #c do
			local tkj = toks[c[j]]
			if tkj.t == "palavra" then
				EMPILHAR(partes, tkj.v)
				j = j + 1
				if j <= #c then
					local sep = toks[c[j]]
					if sep.t == "simbolo" and sep.v == "." then
						j = j + 1
					else
						ehCaminho = false
						break
					end
				end
			else
				ehCaminho = false
				break
			end
		end
		if ehCaminho and #partes >= 2 then
			return { k = "caminho", partes = partes }
		end
		-- parâmetro: nome = valor
		if #c >= 3 then
			local a0 = toks[c[1]]
			local a1 = toks[c[2]]
			if a0.t == "palavra" and a1.t == "simbolo" and a1.v == "=" then
				local resto = {}
				for jp = 3, #c do EMPILHAR(resto, c[jp]) end
				local vval = classificarClausula(resto)
				return { k = "param", nome = a0.v, valor = vval }
			end
		end
		if #c > 1 then
			local expr = analisarExpressao(c)
			if expr then return expr end
		end
		return { k = "str", v = texto }
	end

	-- transforma um valor classificado no formato final de config
	-- (formato legado; o gerador de Luau usa o `expr` rico direto do parser)
	local function valorFinal(v)
		if not v then return nil end
		if v.k == "num" then return v.v
		elseif v.k == "str" then return v.v
		elseif v.k == "ident" then return v.v
		elseif v.k == "caminho" then return table.concat(v.partes, ".")
		elseif v.k == "bool" then return v.v
		elseif v.k == "nulo" then return nil
		elseif v.k == "cor" then return { t = "cor", r = v.r, g = v.g, b = v.b }
		elseif v.k == "par" then
			local r = { t = "par", x = v.x, y = v.y }
			if v.z then r.z = v.z end
			return r
		elseif v.k == "anim" then
			local r = { t = "anim", efeito = v.efeito }
			for k, vv in pairs(v.params or {}) do r[k] = valorFinal(vv) end
			return r
		end
		return nil
	end

	-- lê um "valor" até o fim da linha, quebrando cláusulas no "+" de separação
	local function parseValor(expressao, delimitador)
		if expressao then
			local indices = {}
			local profundidadeParen, profundidadeColchete, profundidadeChave = 0, 0, 0
			while not fimLinha() do
				local tk = at()
				if delimitador and profundidadeParen == 0 and profundidadeColchete == 0 and profundidadeChave == 0
					and tk.t == "simbolo" and (tk.v == delimitador or tk.v == ",") then break end
				EMPILHAR(indices, idx)
				if tk.t == "simbolo" then
					if tk.v == "(" then profundidadeParen = profundidadeParen + 1
					elseif tk.v == ")" then profundidadeParen = math.max(0, profundidadeParen - 1)
					elseif tk.v == "[" then profundidadeColchete = profundidadeColchete + 1
					elseif tk.v == "]" then profundidadeColchete = math.max(0, profundidadeColchete - 1)
					elseif tk.v == "{" then profundidadeChave = profundidadeChave + 1
					elseif tk.v == "}" then profundidadeChave = math.max(0, profundidadeChave - 1) end
				end
				avancar()
			end
			if #indices == 0 then return nil end
			return classificarClausula(indices)
		end
		local clausulas = {}
		local atual = nil
		while not fimLinha() do
			local t = at()
			if t.t == "simbolo" and t.v == "+" and not atual then
				avancar()
			elseif t.t == "simbolo" and t.v == "+" then
				local anterior = atual and atual[#atual] and toks[atual[#atual]]
				if anterior and anterior.v == "=" then
					-- Sinal unário positivo em um parâmetro (escala = +5).
					EMPILHAR(atual, idx)
					avancar()
				else
					EMPILHAR(clausulas, atual)
					atual = nil
					avancar()
				end
			else
				if not atual then atual = {} end
				EMPILHAR(atual, idx)
				avancar()
			end
		end
		if atual then EMPILHAR(clausulas, atual) end

		if #clausulas == 0 then return nil end

		if #clausulas == 1 then
			return classificarClausula(clausulas[1])
		end

		-- múltiplas cláusulas -> animação composta
		local efeito = nil
		local params = {}
		for i, cl in ipairs(clausulas) do
			local v = classificarClausula(cl)
			if v.k == "param" then
				params[v.nome] = v.valor
			elseif i == 1 then
				efeito = v
			end
		end
		return { k = "anim", efeito = (efeito and efeito.v) or "", params = params }
	end

	-- Props removidas no V8: o gerador as descartava em silencio, ou seja,
	-- eram aceitas sem traduzir para nada. Agora sao erro explicito.
	local PROPS_REMOVIDAS = {
		transicao = "propriedade `transicao` nao existe no Roblox; use `animar`",
		sombra = "propriedade `sombra` (box-shadow do CSS) nao existe no Roblox",
		controlavel = "propriedade `controlavel` era do runtime V7; nao ha equivalente no Luau gerado",
	}

	-- normaliza props booleanas conhecidas
	local function normalizarProps(props)
		for k, motivo in pairs(PROPS_REMOVIDAS) do
			if props[k] ~= nil then erroJ(motivo .. ' (propriedade removida no V8)') end
		end
		for k, v in pairs(props) do
			if k == "mostrar" or k == "inimigo" then
				if type(v) == "string" then
					local limpo = string.lower(string.gsub(v, "%s+", ""))
					if limpo == "verdadeiro" or limpo == "sim" or limpo == "true" then
						props[k] = true
					elseif limpo == "falso" or limpo == "nao" or limpo == "false" then
						props[k] = false
					end
				end
			end
		end
		return props
	end

	-- linha de propriedade simples: nome = valor
	local function parsePropLinha()
		local nome = espera("palavra")
		espera("simbolo", "=")
		local v = parseValor()
		if not v then erroJ("valor esperado após '" .. nome .. " ='") end
		return nome, valorFinal(v)
	end

	-- bloco de propriedades até "fim"
	local function parseBlocoProps()
		local props = {}
		pularNovas()
		while true do
			local t = at()
			if t == nil then erroJ("esperava 'fim'") end
			if t.t == "nova" then avancar(); pularNovas()
			elseif t.t == "palavra" and t.v == "fim" then avancar(); break
			else
				local nome, v = parsePropLinha()
				props[nome] = v
			end
		end
		return normalizarProps(props)
	end

	-- sufixo opcional: animacao = <valor>  (ex: mostrar(Painel) animacao = fade in)
	-- o valor fica RICO (mesmo formato de `animar`), para o gerador receber
	-- efeito + duracao/estilo/direcao sem perda
	local function parseAnimSufixo()
		if fimLinha() then return nil end
		local t = at()
		if t.t == "palavra" and t.v == "animacao" then
			avancar()
			espera("simbolo", "=")
			local v = parseValor()
			if not v then erroJ("valor esperado após 'animacao ='") end
			return v
		end
		return erroJ("sintaxe inesperada após comando")
	end

	local function operandoCondicao()
		local tk = at()
		if not tk then erroJ("valor esperado na condição") end
		if tk.t == "numero" then avancar(); return { k = "num", v = tk.v } end
		if tk.t == "string" then avancar(); return { k = "str", v = tk.v } end
		if tk.t ~= "palavra" then erroJ("nome ou literal esperado na condição") end
		avancar()
		local l = string.lower(tostring(tk.v))
		if l == "verdadeiro" or l == "sim" then return { k = "bool", v = true } end
		if l == "falso" or l == "nao" then return { k = "bool", v = false } end
		if l == "nulo" then return { k = "nulo" } end
		local partes = { tk.v }
		while at() and at().t == "simbolo" and at().v == "." do
			avancar()
			table.insert(partes, espera("palavra"))
		end
		if #partes == 1 then return { k = "ident", v = partes[1] } end
		return { k = "caminho", partes = partes }
	end

	local function parseCondicao()
		local t1 = at()
		if not t1 or (t1.t ~= "palavra" and t1.t ~= "string" and t1.t ~= "numero") then erroJ("condição inválida") end

		if t1.v == "visivel" or t1.v == "oculto" then
			avancar()
			espera("simbolo", "(")
			local nome = espera("string")
			espera("simbolo", ")")
			return { tipo = "estado", oq = t1.v, el = nome }
		end

		if t1.v == "distancia" then
			avancar()
			local a = espera("palavra")
			espera("palavra", "de")
			local b = espera("palavra")
			local comp = espera("palavra")
			if comp ~= "menor" and comp ~= "maior" then erroJ("esperava 'menor' ou 'maior' após a distância") end
			local que = at()
			if que and que.t == "palavra" and que.v == "que" then avancar() end
			local valtk = at()
			if not valtk or valtk.t ~= "numero" then erroJ("número esperado") end
			avancar()
			return { tipo = "dist", a = a, b = b, op = (comp == "menor") and "<" or ">", val = valtk.v }
		end

		-- Comparações aritméticas usam a mesma gramática de expressões das
		-- atribuições, sem interferir nos predicados naturais abaixo.
		local comparadores = { ["<"] = true, [">"] = true, ["<="] = true,
			[">="] = true, ["="] = true, ["=="] = true, ["!="] = true, ["~="] = true }
		local inicio, comparador, fimEsq, fimDir = idx, nil, nil, nil
		local profundidade, aritmetica = 0, false
		local operadoresArit = { ["+"] = true, ["-"] = true, ["*"] = true,
			["/"] = true, ["//"] = true, ["%"] = true, ["^"] = true, [".."] = true }
		local j = idx
		while toks[j] and toks[j].t ~= "nova" do
			local tk = toks[j]
			if tk.t == "simbolo" and tk.v == "(" then profundidade = profundidade + 1; aritmetica = true
			elseif tk.t == "simbolo" and tk.v == ")" then profundidade = math.max(0, profundidade - 1)
			elseif profundidade == 0 and tk.t == "palavra"
				and (tk.v == "e" or tk.v == "ou" or tk.v == "and" or tk.v == "or") then break
			elseif profundidade == 0 and tk.t == "simbolo" and comparadores[tk.v] then
				comparador = tk.v
				fimEsq = j - 1
				j = j + 1
				local profDir = 0
				while toks[j] and toks[j].t ~= "nova" do
					local td = toks[j]
					if td.t == "simbolo" and td.v == "(" then profDir = profDir + 1
					elseif td.t == "simbolo" and td.v == ")" then
						if profDir == 0 then break end
						profDir = profDir - 1
					elseif profDir == 0 and td.t == "palavra"
						and (td.v == "e" or td.v == "ou" or td.v == "and" or td.v == "or") then break end
					j = j + 1
				end
				fimDir = j - 1
				break
			end
			if tk.t == "simbolo" and operadoresArit[tk.v] then aritmetica = true end
			j = j + 1
		end
		if comparador and fimEsq >= inicio and fimDir >= fimEsq + 2 then
			-- Detecta operadores nos dois lados; comparações simples continuam no
			-- caminho existente para preservar condições especializadas.
			for k = fimEsq + 2, fimDir do
				local tk = toks[k]
				if tk and tk.t == "simbolo" and operadoresArit[tk.v] then aritmetica = true end
			end
			if aritmetica then
				local esquerda, direita = {}, {}
				for k = inicio, fimEsq do EMPILHAR(esquerda, k) end
				for k = fimEsq + 2, fimDir do EMPILHAR(direita, k) end
				if #esquerda == 0 or #direita == 0 then erroJ("expressão incompleta na comparação") end
				idx = fimDir + 1
				return { tipo = "comp", esq = classificarClausula(esquerda),
					op = comparador, dir = classificarClausula(direita) }
			end
		end

		local lhs = operandoCondicao()
		local obja = (lhs.k == "caminho" and table.concat(lhs.partes, ".")) or lhs.v
		local t2 = at()
		if not t2 or t2.t == "nova" or (t2.t == "palavra" and (t2.v == "senao" or t2.v == "fim" or t2.v == "entao" or t2.v == "e" or t2.v == "ou" or t2.v == "and" or t2.v == "or")) then
			if lhs.k == "ident" and (lhs.v == "vivo" or lhs.v == "morto") then
				erroJ("a condição 'vivo' ou 'morto' precisa de um alvo antes dela")
			end
			return { tipo = "truthy", valor = lhs }
		end

		local opsDiretos = {
			["<"] = true, [">"] = true, ["<="] = true, [">="] = true,
			["="] = true, ["=="] = true, ["!="] = true,
		}
		if t2.t == "simbolo" and opsDiretos[t2.v] then
			avancar()
			return { tipo = "comp", esq = lhs, op = t2.v, dir = operandoCondicao() }
		end

		if t2.t == "palavra" and t2.v == "apertar" and lhs.k == "ident" then
			avancar()
			local tecla = espera("palavra")
			return { tipo = "tecla", obj = obja, tecla = tecla }
		end

		if t2.t == "palavra" and t2.v == "tocar" and lhs.k == "ident" then
			avancar()
			local b = espera("palavra")
			return { tipo = "tocar", a = obja, b = b }
		end

		if t2.t == "palavra" and (t2.v == "vivo" or t2.v == "morto") and lhs.k == "ident" then
			avancar()
			return { tipo = "vida", alvo = obja, estado = (t2.v == "vivo") }
		end

		if t2.t == "palavra" and (t2.v == "perto" or t2.v == "longe") and lhs.k == "ident" then
			avancar()
			espera("palavra", "de")
			local b = espera("palavra")
			return { tipo = "dist", a = obja, b = b, op = (t2.v == "perto") and "<" or ">", raio = true, val = 12 }
		end

		if t2.t == "palavra" and t2.v == "criado" and (lhs.k == "str" or lhs.k == "ident") then
			avancar()
			espera("palavra", "com")
			espera("palavra", "sucesso")
			return { tipo = "criado", nome = obja }
		end

		return { tipo = "truthy", valor = lhs }
	end

	-- aceita `entao` opcional depois da condição: `se X > 5 entao` ou `se X > 5`
	local function parseCond()
		local function atom()
			local t = at()
			if t and t.t == "palavra" and (t.v == "nao" or t.v == "not") then
				avancar()
				return { tipo = "nao", cond = atom() }
			end
			if t and t.t == "simbolo" and t.v == "(" then
				avancar()
				local dentro = parseCond()
				espera("simbolo", ")")
				return dentro
			end
			return parseCondicao()
		end
		local function e()
			local cond = atom()
			while at() and at().t == "palavra" and (at().v == "e" or at().v == "and") do
				local op = at().v
				avancar()
				cond = { tipo = "logica", esq = cond, op = op, dir = atom() }
			end
			return cond
		end
		local cond = e()
		while at() and at().t == "palavra" and (at().v == "ou" or at().v == "or") do
			local op = at().v
			avancar()
			cond = { tipo = "logica", esq = cond, op = op, dir = e() }
		end
		local nt = at()
		if nt and nt.t == "palavra" and nt.v == "entao" then avancar() end
		return cond
	end

	-- corpo de comandos até uma das palavras em parar (não consome o token)
	local parseComando
	local profundidadeLaco = 0
	local escoposVariaveis = {}
	local function variavelDeclarada(nome)
		if config.variaveis[nome] then return true end
		for i = #escoposVariaveis, 1, -1 do
			if escoposVariaveis[i][nome] then return true end
		end
		return false
	end
	local function parseComandos(parar)
		local corpo = {}
		pularNovas()
		while true do
			local t = at()
			if t == nil then return corpo end
			if t.t == "nova" then avancar(); pularNovas()
			elseif t.t == "palavra" and parar[t.v] then return corpo
			else
				EMPILHAR(corpo, parseComando())
			end
		end
	end
	local function parseRamosSenao()
		local alternativas, senao = {}, nil
		while at() and at().t == "palavra" and at().v == "senao" do
			avancar()
			if at() and at().t == "palavra" and at().v == "se" then
				avancar()
				local cond = parseCond()
				local corpo = parseComandos({ fim = true, senao = true })
				EMPILHAR(alternativas, { cond = cond, corpo = corpo })
			else
				senao = parseComandos({ fim = true })
				break
			end
		end
		return alternativas, senao
	end
	local function parseCorpoLaco()
		profundidadeLaco = profundidadeLaco + 1
		local corpo = parseComandos({ fim = true })
		profundidadeLaco = profundidadeLaco - 1
		return corpo
	end

	parseComando = function()
		local t = at()
		if not t or t.t ~= "palavra" then erroJ("comando esperado") end
		local a = t.v
		avancar()

		if a == "variavel" or a == "var" or a == "let" then
			local nome = esperaNome()
			local escopoAtual = escoposVariaveis[#escoposVariaveis]
			if escopoAtual then
				if escopoAtual[nome] then erroJ("variável já declarada na função: '" .. nome .. "'") end
				escopoAtual[nome] = true
			else
				if config.variaveis[nome] then erroJ("variável já declarada: '" .. nome .. "'") end
				config.variaveis[nome] = true
			end
			local expr = nil
			if at() and at().t == "simbolo" and at().v == "=" then
				avancar()
				expr = parseValor(true)
				if not expr then erroJ("valor esperado após a declaração de '" .. nome .. "'") end
			end
			return { tipo = "variavel", nome = nome, expr = expr, norm = "variavel " .. nome }
		end

		if a == "retornar" or a == "devolver" then
			local expr = nil
			if not fimLinha() then
				expr = parseValor(true)
				if not expr then erroJ("expressão esperada após 'retornar'") end
			end
			return { tipo = "retornar", expr = expr, norm = "retornar" }
		end

		if a == "pare" or a == "continuar" then
			if profundidadeLaco == 0 then erroJ("'" .. a .. "' só pode ser usado dentro de um laço") end
			return { tipo = a, norm = a }
		end

		-- YASHSCRIPT: acesso por ponto em comandos.
		--   jogador.vida = 80      -> atribui dado do objeto
		--   jogador.moedas += 1    -> atribuição composta
		--   moeda.destruir()       -> chamada de método (ponto)
		--   moeda:Destruir()       -> chamada de método Luau (dois pontos)
		--   Workspace.Casa:PivotTo(...) -> chamada com base de caminho
		--
		-- Monta uma chamada de método a partir do alvo já lido: posiciona o
		-- cursor no nome do método, consome os argumentos posicionais e devolve
		-- o nó. `sep` guarda o separador usado, para o descompilador reemitir
		-- exatamente a mesma forma.
		local function metodoEm(partes, sep, idxNome)
			idx = idxNome
			local metodo = espera("palavra")
			espera("simbolo", "(")
			local args = {}
			if not (at() and at().t == "simbolo" and at().v == ")") then
				while true do
					local inicio = idx
					local profundidade = 0
					while at() do
						local tk = at()
						if tk.t == "simbolo" and tk.v == "(" then profundidade = profundidade + 1
						elseif tk.t == "simbolo" and tk.v == ")" then
							if profundidade == 0 then break end
							profundidade = profundidade - 1
						elseif tk.t == "simbolo" and tk.v == "," and profundidade == 0 then break end
						avancar()
					end
					if idx == inicio then erroJ("argumento esperado para '" .. metodo .. "'") end
					local indices = {}
					for j = inicio, idx - 1 do EMPILHAR(indices, j) end
					EMPILHAR(args, classificarClausula(indices))
					if at() and at().t == "simbolo" and at().v == "," then
						avancar()
					else break end
				end
			end
			espera("simbolo", ")")
			local alvo = table.concat(partes, ".")
			return { tipo = "metodo", metodo = metodo, alvo = alvo, args = args,
				sep = sep, norm = alvo .. sep .. metodo .. "()" }
		end

		local nt0 = at()
		if nt0 and nt0.t == "simbolo" and (nt0.v == "[" or nt0.v == ".") then
			local j = idx
			local indicesBase = { idx - 1 }
			while toks[j] and toks[j].t == "simbolo" and toks[j].v == "."
				and toks[j + 1] and toks[j + 1].t == "palavra" do
				EMPILHAR(indicesBase, j)
				EMPILHAR(indicesBase, j + 1)
				j = j + 2
			end
			local operador = toks[j]
			if #indicesBase > 1 and operador and operador.t == "simbolo"
				and (operador.v == "=" or operador.v == "+=" or operador.v == "-=") then
				local partes = { a }
				for p = 2, #indicesBase, 2 do EMPILHAR(partes, toks[indicesBase[p + 1]].v) end
				idx = j + 1
				local valor = parseValor(true)
				if not valor then erroJ("valor esperado após a atribuição a '" .. table.concat(partes, ".") .. "'") end
				local caminho = table.concat(partes, ".")
				return { tipo = "atrib", op = operador.v, caminho = caminho, valor = valorFinal(valor),
					expr = valor, norm = caminho .. " " .. operador.v }
			end
			if toks[j] and toks[j].t == "simbolo" and toks[j].v == "[" then
				local destino = classificarClausula(indicesBase)
				idx = j
				while at() and at().t == "simbolo" and at().v == "[" do
					avancar()
					local inicio, profundidade = idx, 0
					while at() do
						local tk = at()
						if tk.t == "simbolo" and tk.v == "[" then profundidade = profundidade + 1
						elseif tk.t == "simbolo" and tk.v == "]" then
							if profundidade == 0 then break end
							profundidade = profundidade - 1
						end
						avancar()
					end
					if idx == inicio then erroJ("índice vazio") end
					local indicesChave = {}
					for k = inicio, idx - 1 do EMPILHAR(indicesChave, k) end
					local chave = classificarClausula(indicesChave)
					espera("simbolo", "]")
					destino = { k = "indice", base = destino, chave = chave }
				end
				local opTk = at()
				if not opTk or opTk.t ~= "simbolo" or (opTk.v ~= "=" and opTk.v ~= "+=" and opTk.v ~= "-=") then
					erroJ("esperava '=' ou atribuição composta após o índice")
				end
				local op = opTk.v
				avancar()
				local valor = parseValor(true)
				if not valor then erroJ("valor esperado após a atribuição por índice") end
				return { tipo = "atrib_indice", destino = destino, op = op, expr = valor,
					norm = "atribuição por índice " .. op }
			end
		end
		if nt0 and nt0.t == "simbolo" and (nt0.v == "." or nt0.v == ":") then
			-- Base completa: palavra seguida de (.palavra)*, sem consumir tokens.
			-- Isso permite tanto `moeda:Destruir()` quanto `Workspace.Casa:PivotTo()`.
			local j = idx
			local partes = { a }
			while toks[j] and toks[j].t == "simbolo" and toks[j].v == "."
				and toks[j + 1] and toks[j + 1].t == "palavra" do
				table.insert(partes, toks[j + 1].v)
				j = j + 2
			end

			-- <base>:<metodo>(args) -> chamada de método Luau
			if toks[j] and toks[j].t == "simbolo" and toks[j].v == ":"
				and toks[j + 1] and toks[j + 1].t == "palavra"
				and toks[j + 2] and toks[j + 2].t == "simbolo" and toks[j + 2].v == "(" then
				return metodoEm(partes, ":", j + 1)
			end

			-- <base>.<campo> = valor -> atribuição (apenas com ponto)
			if nt0.v == "." then
				local t2, t3 = toks[idx + 1], toks[idx + 2]
				if t2 and t2.t == "palavra" and t3 and t3.t == "simbolo" then
					if t3.v == "=" or t3.v == "+=" or t3.v == "-=" then
						avancar()
						local prop = espera("palavra")
						local op = at().v
						avancar()
						local v = parseValor(true)
						if not v then erroJ("valor esperado em '" .. a .. "." .. prop .. "'") end
						local caminho = a .. "." .. prop
						return { tipo = "atrib", op = op, caminho = caminho, valor = valorFinal(v), expr = v, norm = caminho .. " " .. op }
					elseif t3.v == "(" then table.remove(partes) -- tira o nome do metodo do caminho
						return metodoEm(partes, ".", j - 1)
					end
				end
			end
		end

		-- YASHSCRIPT: atribuição composta em nome simples (moedas += 1)
		if nt0 and nt0.t == "simbolo" and (nt0.v == "+=" or nt0.v == "-=") then
			local op = nt0.v
			avancar()
			local v = parseValor(true)
			if not v then erroJ("valor esperado após '" .. a .. " " .. op .. "'") end
			return { tipo = "atrib", op = op, caminho = a, valor = valorFinal(v), expr = v, norm = a .. " " .. op }
		end

		if funcoesDeclaradas[a] and nt0 and nt0.t == "simbolo" and nt0.v == "(" then
			local indices = { idx - 1 }
			while not fimLinha() do EMPILHAR(indices, idx); avancar() end
			local expr = analisarExpressao(indices)
			if not expr or expr.k ~= "chamada" then erroJ("chamada de função inválida") end
			return { tipo = "expressao", expr = expr, norm = a .. "()" }
		end

		if nt0 and nt0.t == "simbolo" and nt0.v == "=" and variavelDeclarada(a) then
			avancar()
			local v = parseValor(true)
			if not v then erroJ("valor esperado após '" .. a .. " ='") end
			return { tipo = "atrib", op = "=", caminho = a, valor = valorFinal(v), expr = v, norm = a .. " =" }
		end

		-- YASHSCRIPT: print(...) como saida simples de teste
		if a == "print" then
			local args = {}
			if at() and at().t == "simbolo" and at().v == "(" then
				avancar()
				if at() and at().t == "simbolo" and at().v == ")" then
					avancar()
				else
					while true do
						local arg = parseValor(true, ")")
						if not arg then erroJ("expressão esperada em print") end
						EMPILHAR(args, arg)
						if at() and at().t == "simbolo" and at().v == "," then avancar() else break end
					end
					espera("simbolo", ")")
				end
			else
				local arg = parseValor(true)
				if not arg then erroJ("expressão esperada em print") end
				EMPILHAR(args, arg)
			end
			return { tipo = "log", args = args, forma = "print", norm = "print" }
		end

		-- tupla numérica entre parênteses: (x, y, z)
		local function lerTupla()
			espera("simbolo", "(")
			local nums = {}
			while true do
				local tk = at()
				if tk and tk.t == "simbolo" and (tk.v == "-" or tk.v == "+")
					and toks[idx + 1] and toks[idx + 1].t == "numero" then
					local sinal = tk.v == "-" and -1 or 1
					avancar()
					EMPILHAR(nums, sinal * espera("numero"))
				elseif tk and tk.t == "numero" then EMPILHAR(nums, tk.v); avancar()
				elseif tk and tk.t == "simbolo" and tk.v == "," then avancar()
				else break end
			end
			espera("simbolo", ")")
			if #nums == 0 then erroJ("tupla (x,y,z) esperada") end
			return nums
		end

		if a == "mostrar" or a == "esconder" or a == "alternar" then
			local map = { mostrar = "mostrar", esconder = "esconder", alternar = "alternar" }
			local nt = at()
			if nt and nt.t == "palavra" and nt.v == "texto" then
				avancar()
				local msg = espera("string")
				return { tipo = "log", texto = msg, forma = "mostrar", norm = "mostrar texto" }
			elseif nt and nt.t == "palavra" and nt.v == "cena" then
				avancar()
				local nome = esperaNome()
				local anim = parseAnimSufixo()
				return { tipo = "cena", acao = map[a], alvo = nome, anim = anim, norm = a .. " cena " .. nome }
			elseif nt and nt.t == "simbolo" and nt.v == "(" then
				avancar()
				local nome = esperaNome()
				espera("simbolo", ")")
				local anim = parseAnimSufixo()
				local norm = a .. "(" .. nome .. ")"
				-- nome solto (com ou sem aspas) vira referência para o gerador
				return { tipo = "visivel", acao = map[a], alvo = nome, anim = anim,
					expr = { k = "ident", v = nome }, norm = norm }
			elseif nt and (nt.t == "palavra" or nt.t == "string") then
				-- `mostrar Cubo` / `mostrar "Cubo"`: nome solto, sem parenteses
				local nome = nt.v
				avancar()
				local anim = parseAnimSufixo()
				return { tipo = "visivel", acao = map[a], alvo = nome, anim = anim,
					expr = { k = "ident", v = nome }, norm = a .. " " .. nome }
			end
			erroJ("sintaxe de " .. a .. " inválida")
		end

		if a == "mudar" then
			espera("palavra", "cena")
			local nome = esperaNome()
			local anim = parseAnimSufixo()
			return { tipo = "cena", acao = "mudar", alvo = nome, anim = anim, norm = "mudar cena " .. nome }
		end

		-- YASHSCRIPT: animar — tween de verdade (TweenService) sobre um alvo:
		--   animar("Jogar") posicao = (0, 100) + tamanho = (200, 50) + duracao = 0.5
		--   animar("Painel") fade in + duracao = 1          (efeito com parametros)
		--   animar("Painel") pulsar                          (efeito curto)
		--   animar("Painel") animacao = abrir                (animacao criada)
		-- A forma legada `animar pulsar` (nome sozinho, nada depois) continua
		-- valendo como atalho de `executar animacao pulsar`.
		if a == "animar" then
			local nt = at()
			local alvo = nil
			local formaCurta = false
			if nt and nt.t == "simbolo" and nt.v == "(" then
				avancar()
				alvo = lerNomeCaminho()
				espera("simbolo", ")")
			elseif nt and (nt.t == "string" or nt.t == "palavra") then
				alvo = lerNomeCaminho()
				-- nome sozinho em forma curta so e legado se nada vier depois
				if nt.t == "palavra" and fimLinha() then formaCurta = true end
			end
			if formaCurta then
				return { tipo = "animacao", nome = alvo, norm = "executar animacao " .. alvo }
			end
			if not alvo then
				erroJ("alvo esperado após 'animar' (ex: animar(\"Jogar\") fade in)")
			end
			local valor = parseValor()
			if not valor then
				erroJ("efeito ou propriedade esperado após 'animar(" .. alvo .. ")'")
			end
			return { tipo = "tween", alvo = alvo, expr = exprCaminho(alvo),
				valor = valor, norm = "animar " .. alvo }
		end

		if a == "executar" or a == "chamar" then
			local k = at()
			if not k or k.t ~= "palavra" then erroJ("tipo (animacao/acao) esperado após '" .. a .. "'") end
			if k.v == "animacao" then
				avancar()
				local nome = esperaNome()
				return { tipo = "animacao", nome = nome, norm = "executar animacao " .. nome }
			elseif k.v == "acao" then
				avancar()
				local nome = esperaNome()
				return { tipo = "acao", nome = nome, norm = "executar acao " .. nome }
			end
			erroJ("esperava 'animacao' ou 'acao' após '" .. a .. "'")
		end

		if a == "destruir" then
			local k = espera("palavra")
			if k ~= "objeto" and k ~= "elemento" then erroJ("esperava 'objeto' ou 'elemento' após 'destruir'") end
			local nome = esperaNome()
			return { tipo = "destruir", oq = k, alvo = nome, norm = "destruir " .. k .. " " .. nome }
		end

		if a == "somar" or a == "subtrair" then
			local de = lerCaminho()
			if a == "somar" then espera("palavra", "a") else espera("palavra", "de") end
			local para = lerCaminho()
			return { tipo = "soma", op = a, de = de, para = para }
		end

		if a == "se" then
			local cond = parseCond()
			local corpo = parseComandos({ fim = true, senao = true })
			local alternativas, senao = parseRamosSenao()
			espera("palavra", "fim")
			return { tipo = "se", cond = cond, corpo = corpo, alternativas = alternativas, senao = senao }
		end

		if a == "para" then
			if at() and at().t == "palavra" and at().v == "cada" then
				avancar()
				local nomes = { esperaNome() }
				if at() and at().t == "simbolo" and at().v == "," then
					avancar()
					local segundo = esperaNome()
					if segundo == nomes[1] then erroJ("variáveis repetidas no laço 'para cada'") end
					EMPILHAR(nomes, segundo)
				end
				espera("palavra", "em")
				local colecao = parseValor(true)
				if not colecao then erroJ("coleção esperada após 'em'") end
				local corpo = parseCorpoLaco()
				espera("palavra", "fim")
				return { tipo = "para_cada", nomes = nomes, iterador = #nomes == 2 and "pairs" or "ipairs",
					colecao = colecao, corpo = corpo }
			end
			local nome = esperaNome()
			espera("palavra", "de")
			local function lerExpressaoAte(cortadores)
				local indices, parenteses, colchetes, chaves = {}, 0, 0, 0
				while at() and at().t ~= "nova" do
					local tk = at()
					if parenteses == 0 and colchetes == 0 and chaves == 0
						and tk.t == "palavra" and cortadores[tk.v] then break end
					EMPILHAR(indices, idx)
					if tk.t == "simbolo" then
						if tk.v == "(" then parenteses = parenteses + 1
						elseif tk.v == ")" then parenteses = math.max(0, parenteses - 1)
						elseif tk.v == "[" then colchetes = colchetes + 1
						elseif tk.v == "]" then colchetes = math.max(0, colchetes - 1)
						elseif tk.v == "{" then chaves = chaves + 1
						elseif tk.v == "}" then chaves = math.max(0, chaves - 1) end
					end
					avancar()
				end
				if #indices == 0 then erroJ("expressão esperada no laço 'para'") end
				return classificarClausula(indices)
			end
			local inicio = lerExpressaoAte({ ate = true })
			espera("palavra", "ate")
			local limite = lerExpressaoAte({ passo = true })
			local passo = { k = "num", v = 1 }
			if at() and at().t == "palavra" and at().v == "passo" then
				avancar()
				passo = parseValor(true)
				if not passo then erroJ("expressão esperada após 'passo'") end
			end
			local corpo = parseCorpoLaco()
			espera("palavra", "fim")
			return { tipo = "para", nome = nome, inicio = inicio, limite = limite, passo = passo, corpo = corpo }
		end

		if a == "enquanto" then
			local cond = parseCond()
			local corpo = parseCorpoLaco()
			espera("palavra", "fim")
			return { tipo = "enquanto", cond = cond, corpo = corpo }
		end

		if a == "repita" then
			profundidadeLaco = profundidadeLaco + 1
			local corpo = parseComandos({ ate = true })
			profundidadeLaco = profundidadeLaco - 1
			espera("palavra", "ate")
			local cond = parseCond()
			return { tipo = "repita", corpo = corpo, cond = cond }
		end

		-- comandos de jogo (mundo 3D/servidor)
		if a == "esperar" or a == "aguardar" then
			local vt = at()
			if not vt or vt.t ~= "numero" then erroJ("segundos esperados após '" .. a .. "'") end
			avancar()
			return { tipo = "espera", valor = vt.v, norm = "esperar " .. vt.v }
		end

		if a == "causar" then
			espera("palavra", "dano")
			local alvo = esperaNome()
			local vtk = at()
			if not vtk or vtk.t ~= "numero" then erroJ("valor do dano esperado") end
			avancar()
			return { tipo = "dano", alvo = alvo, valor = vtk.v, norm = "causar dano " .. alvo .. " " .. vtk.v }
		end

		if a == "curar" then
			local alvo = esperaNome()
			local vtk = at()
			if not vtk or vtk.t ~= "numero" then erroJ("quantidade esperada") end
			avancar()
			return { tipo = "curar", alvo = alvo, valor = vtk.v, norm = "curar " .. alvo .. " " .. vtk.v }
		end

		if a == "matar" then
			local alvo = esperaNome()
			return { tipo = "matar", alvo = alvo, norm = "matar " .. alvo }
		end

		if a == "respawnar" then
			local alvo = esperaNome()
			return { tipo = "respawnar", alvo = alvo, norm = "respawnar " .. alvo }
		end

		if a == "teleportar" then
			local alvo = esperaNome()
			local nums = lerTupla()
			return { tipo = "teleportar", alvo = alvo, pos = { t = "par", x = nums[1], y = nums[2], z = nums[3] or 0 }, norm = "teleportar " .. alvo .. " (" .. nums[1] .. ", " .. nums[2] .. ", " .. (nums[3] or 0) .. ")" }
		end

		if a == "mover" then
			local alvo = esperaNome()
			espera("palavra", "para")
			local nums = lerTupla()
			local velocidade = 20
			if not fimLinha() then
				espera("palavra", "velocidade")
				local vt2 = at()
				if not vt2 or vt2.t ~= "numero" then erroJ("velocidade esperada") end
				avancar()
				velocidade = vt2.v
			end
			return { tipo = "mover", alvo = alvo, para = { t = "par", x = nums[1], y = nums[2], z = nums[3] or 0 }, velocidade = velocidade, norm = "mover " .. alvo .. " para (" .. nums[1] .. ", " .. nums[2] .. ", " .. (nums[3] or 0) .. ") velocidade " .. velocidade }
		end

		if a == "rotacionar" then
			local alvo = esperaNome()
			espera("palavra", "para")
			local nums = lerTupla()
			local duracao = 0.3
			if not fimLinha() then
				espera("palavra", "duracao")
				local dt2 = at()
				if not dt2 or dt2.t ~= "numero" then erroJ("duracao esperada") end
				avancar()
				duracao = dt2.v
			end
			return { tipo = "rotacionar", alvo = alvo, para = { t = "par", x = nums[1], y = nums[2], z = nums[3] or 0 }, duracao = duracao, norm = "rotacionar " .. alvo .. " para (" .. nums[1] .. ", " .. nums[2] .. ", " .. (nums[3] or 0) .. ") duracao " .. duracao }
		end

		if a == "sortear" then
			local nome = esperaNome()
			espera("palavra", "entre")
			local mn = at()
			if not mn or mn.t ~= "numero" then erroJ("primeiro número esperado") end
			avancar()
			espera("palavra", "e")
			local mx = at()
			if not mx or mx.t ~= "numero" then erroJ("segundo número esperado") end
			avancar()
			return { tipo = "sortear", nome = nome, min = mn.v, max = mx.v, norm = "sortear " .. nome .. " entre " .. mn.v .. " e " .. mx.v }
		end

		if a == "tocar" then
			espera("palavra", "som")
			local id = at()
			if not id or (id.t ~= "numero" and id.t ~= "string") then erroJ("id do som esperado") end
			avancar()
			return { tipo = "som", id = tostring(id.v), norm = "tocar som " .. id.v }
		end

		if a == "explodir" then
			local alvo = esperaNome()
			local raio, dano = 8, 50
			if not fimLinha() then
				espera("palavra", "raio")
				local rt3 = at()
				if not rt3 or rt3.t ~= "numero" then erroJ("raio esperado") end
				avancar()
				raio = rt3.v
				if not fimLinha() then
					espera("palavra", "dano")
					local dt3 = at()
					if not dt3 or dt3.t ~= "numero" then erroJ("dano esperado") end
					avancar()
					dano = dt3.v
				end
			end
			return { tipo = "explodir", alvo = alvo, raio = raio, dano = dano, norm = "explodir " .. alvo .. " raio " .. raio .. " dano " .. dano }
		end

		if a == "seguir" then
			local quem = esperaNome()
			local de = at()
			if de and de.t == "palavra" and de.v == "o" then avancar() end
			local alvo = esperaNome()
			return { tipo = "seguir", quem = quem, alvo = alvo, norm = "seguir " .. quem .. " o " .. alvo }
		end

		if a == "clonar" then
			local origem = lerNomeCaminho()
			espera("palavra", "para")
			local pai = lerNomeCaminho()
			local nome = nil
			if at() and at().t == "palavra" and at().v == "como" then
				avancar()
				nome = esperaNome()
			end
			return { tipo = "clonar", origem = origem, pai = pai, nome = nome,
				norm = "clonar " .. origem .. " para " .. pai }
		end

		-- propriedade genérica aplicada ao elemento do evento: nome = valor
		local eq = at()
		if eq and eq.t == "simbolo" and eq.v == "=" then
			avancar()
			local v = parseValor(true)
			if not v then erroJ("valor esperado após '" .. a .. " ='") end
			return { tipo = "prop", propNome = a, props = { [a] = valorFinal(v) },
				exprs = { [a] = v }, expr = v }
		end

		return erroJ("comando desconhecido '" .. a .. "'")
	end

	local function parseBlocoHud()
		local campo = nil
		pularNovas()
		while true do
			local t = at()
			if t == nil then erroJ("esperava 'fim' no hud") end
			if t.t == "nova" then avancar(); pularNovas()
			elseif t.t == "palavra" and t.v == "fim" then avancar(); break
			elseif t.t == "palavra" and t.v == "mostrar" then
				avancar()
				campo = lerCaminho()
			else
				erroJ("em hud use: mostrar <objeto>.<atributo>")
			end
		end
		return campo
	end

	local function parseBlocoAnimacao()
		local lista = {}
		pularNovas()
		while true do
			local t = at()
			if t == nil then erroJ("esperava 'fim' na animação") end
			if t.t == "nova" then avancar(); pularNovas()
			elseif t.t == "palavra" and t.v == "fim" then avancar(); break
			else
				espera("palavra", "animacao")
				espera("simbolo", "=")
				local v = parseValor()
				if not v then erroJ("valor de animação esperado") end
				EMPILHAR(lista, v)
			end
		end
		return lista
	end

	-- comando de proibição
	local function parseProibir()
		local evt = espera("palavra")
		if evt ~= "clicar" and evt ~= "mouse_em" and evt ~= "mouse_sair" then
			erroJ("tipo de evento inválido em proibir: '" .. evt .. "'")
		end
		local alvo = esperaNome()
		espera("palavra", "de")

		local comandos = {}
		local atual = {}
		while not fimLinha() do
			local t = at()
			if t.t == "palavra" and (t.v == "se" or t.v == "somente") then break end
			if t.t == "simbolo" and t.v == "+" then
				if #atual > 0 then EMPILHAR(comandos, atual) end
				atual = {}
				avancar()
			else
				EMPILHAR(atual, idx)
				avancar()
			end
		end
		if #atual > 0 then EMPILHAR(comandos, atual) end

		local normComandos = {}
		for _, cl in ipairs(comandos) do
			local txt = textoTrecho(cl[1], cl[#cl])
			txt = string.gsub(txt, "%s+", "")
			EMPILHAR(normComandos, txt)
		end

		local cond = nil
		local somente = nil
		if not fimLinha() then
			local t = at()
			if t and t.t == "palavra" and t.v == "se" then
				avancar()
				local oq = espera("palavra")
				local el = nil
				if oq == "visivel" or oq == "oculto" then
					espera("simbolo", "(")
					el = espera("string")
					espera("simbolo", ")")
					cond = { tipo = "estado", oq = oq, el = el }
				end
			elseif t and t.t == "palavra" and t.v == "somente" then
				avancar()
				somente = espera("string")
			else
				erroJ("sintaxe de proibir inválida")
			end
		end

		EMPILHAR(config.proibicoes, {
			evt = evt,
			alvo = alvo,
			comandos = normComandos,
			cond = cond,
			somente = somente,
		})
	end

	-- laço principal
	pularNovas()
	while true do
		local t = at()
		if t == nil then break end
		if t.t == "nova" then avancar(); pularNovas()
		elseif t.t ~= "palavra" then erroJ("instrução inesperada")
		else
		local a = t.v
		if a == "YASHSCRIPT" then
			-- cabeçalho: identifica o arquivo como YashScript.
			avancar()
			espera("simbolo", ":")
			config.marcador = "YASHSCRIPT:"
			-- O contexto NUNCA vem do texto: ele vem da classe do script no
			-- Studio (Script/LocalScript/ModuleScript). Por isso o cabecalho nao
			-- aceita mais `servidor`/`cliente` -- esse campo nunca foi lido.
		elseif a == "incluir" then
			avancar()
			local arq = espera("string")
			EMPILHAR(config.incluir, arq)
		elseif a == "usar" then
			-- YASHSCRIPT: usar "Nome" = <caminho da árvore | valor>
			-- Declara um nome do desenvolvedor. O gerador de Luau transforma em
			-- `local Nome = <expressão resolvida>` no ponto em que aparece.
			avancar()
			local nome = esperaNome()
			espera("simbolo", "=")
			local v = parseValor(true)
			if not v then erroJ("valor esperado em 'usar " .. nome .. " ='") end
			EMPILHAR(config.aliases, { nome = nome, expr = v, linha = t.l })
		elseif a == "criar" then
			avancar()
			local tipo = espera("palavra")
			local nome = esperaNome()

			local elementos_tipos = {
				painel = true, texto = true, botao = true, campo = true,
				imagem = true, elemento = true,
			}

			local formas_tipos = {
				bloco = true, esfera = true, cilindro = true, cunha = true,
				paralelepipedo = true, plataforma = true,
			}

			if tipo == "cena" then
				config.cenas[nome] = parseBlocoProps()
			elseif tipo == "estilo" then
				config.estilos[nome] = parseBlocoProps()
			elseif elementos_tipos[tipo] then
				config.elementos[nome] = { tipo = tipo, props = parseBlocoProps() }
				EMPILHAR(config.ordem_elementos, nome)
			elseif formas_tipos[tipo] then
				config.formas[nome] = { tipo = tipo, props = parseBlocoProps() }
			elseif tipo == "objeto" then
				config.objetos[nome] = parseBlocoProps()
			elseif tipo == "funcao" then
				local parametros = {}
				local vistos = {}
				espera("simbolo", "(")
				if not (at() and at().t == "simbolo" and at().v == ")") then
					while true do
						local parametro = esperaNome()
						if vistos[parametro] then erroJ("parâmetro repetido: " .. parametro) end
						vistos[parametro] = true
						EMPILHAR(parametros, parametro)
						if at() and at().t == "simbolo" and at().v == "," then avancar() else break end
					end
				end
				espera("simbolo", ")")
				if config.funcoes[nome] then erroJ("função já declarada: '" .. nome .. "'") end
				local escopoFuncao = {}
				for _, parametro in ipairs(parametros) do escopoFuncao[parametro] = true end
				table.insert(escoposVariaveis, escopoFuncao)
				local corpo = parseComandos({ fim = true })
				espera("palavra", "fim")
				table.remove(escoposVariaveis)
				config.funcoes[nome] = { parametros = parametros, corpo = corpo }
			elseif tipo == "acao" then
				local escopoAcao = {}
				table.insert(escoposVariaveis, escopoAcao)
				local corpo = parseComandos({ fim = true })
				espera("palavra", "fim")
				table.remove(escoposVariaveis)
				config.acoes[nome] = corpo
			elseif tipo == "animacao" then
				config.animacoes[nome] = { lista = parseBlocoAnimacao() }
			elseif tipo == "hud" then
				config.huds[nome] = { campo = parseBlocoHud() }
			else
				erroJ("tipo desconhecido no 'criar': '" .. tipo .. "'")
			end
		elseif a == "site" then
			avancar()
			config.site = parseBlocoProps()
		elseif a == "mundo" then
			avancar()
			config.mundo = parseBlocoProps()
		elseif a == "a" then
			avancar()
			espera("palavra", "cada")
			local vt = at()
			if not vt or vt.t ~= "numero" then erroJ("segundos esperados após 'a cada'") end
			avancar()
			table.insert(escoposVariaveis, {})
			local corpo = parseComandos({ fim = true })
			espera("palavra", "fim")
			table.remove(escoposVariaveis)
			EMPILHAR(config.timers, { intervalo = vt.v, corpo = corpo })
		elseif a == "quando" then
			avancar()
			local primeira = espera("palavra")
			-- "quando tocar 'moeda'"        -> forma legada, sem sujeito
			-- "quando jogador tocar moeda" -> o primeiro nome e o SUJEITO
			local sujeito = nil
			local evt = primeira
			if not EVENTOS_CONHECIDOS[primeira] then
				sujeito = primeira
				evt = espera("palavra")
			end
			if not EVENTOS_CONHECIDOS[evt] then
				erroJ("evento desconhecido: '" .. evt .. "'")
			end
			local alvo = nil
			if EMISSOR_PROPRIO[evt] then
				-- "quando Botao clicar": o sujeito ja e o alvo
				if sujeito then
					alvo = sujeito
					sujeito = nil
				else
					alvo = esperaNome()
				end
			elseif evt == "tocar" or evt == "encostar" then
				-- "quando tocar Cubo" ou "quando Cubo tocar Cubo"
				alvo = esperaNome()
			end
			local localEvento = evt ~= "iniciar" and evt ~= "carregar"
			if localEvento then table.insert(escoposVariaveis, {}) end
			local corpo = parseComandos({ fim = true })
			espera("palavra", "fim")
			if localEvento then table.remove(escoposVariaveis) end
			EMPILHAR(config.eventos, { tipo = evt, alvo = alvo, sujeito = sujeito, corpo = corpo })
		elseif a == "se" then
			avancar()
			local cond = parseCond()
			local corpo = parseComandos({ fim = true, senao = true })
			local alternativas, senao = parseRamosSenao()
			espera("palavra", "fim")
			EMPILHAR(config.continuos, { cond = cond, corpo = corpo, alternativas = alternativas, senao = senao })
		elseif a == "enquanto" then
			avancar()
			local cond = parseCond()
			local corpo = parseCorpoLaco()
			espera("palavra", "fim")
			EMPILHAR(config.loops, { cond = cond, corpo = corpo })
		elseif a == "proibir" then
			avancar()
			parseProibir()
		else
			-- comando simples em nivel superior: print(...), mostrar Cubo,
			-- Botao.texto = 1, Cubo.destruir()
			local marca = idx
			local okCmd, cmd = pcall(parseComando)
			if okCmd and type(cmd) == "table" and cmd.tipo then
				EMPILHAR(config.comandos, cmd)
			else
				idx = marca
				erroJ("instrução de nível superior desconhecida: '" .. a .. "'")
			end
		end
		end
	end

	return config
end

-----------------------------------------------------------------------
-- EXPANSÃO DE "incluir"
-----------------------------------------------------------------------

local function expandirIncluir(fonte, arquivos, pilha)
	pilha = pilha or {}
	local saida = {}
	for linha in string.gmatch(fonte .. "\n", "(.-)\n") do
		local nome = string.match(linha, "^%s*incluir%s+[\"']([^\"']+)[\"']")
		if nome then
			if pilha[nome] then
				error({ erro = "inclusão circular de '" .. nome .. "'", linha = 0 }, 0)
			end
			local conteudo = arquivos and arquivos[nome]
			if conteudo then
				pilha[nome] = true
				local exp = expandirIncluir(conteudo, arquivos, pilha)
				pilha[nome] = nil
				EMPILHAR(saida, exp)
			else
				-- mantém a linha original; o consumidor (plugin/host) decide o que fazer
				EMPILHAR(saida, linha)
			end
		else
			EMPILHAR(saida, linha)
		end
	end
	return table.concat(saida, "\n")
end

-----------------------------------------------------------------------
-- API PÚBLICA
-----------------------------------------------------------------------

function Compilador.Compilar(fonte, arquivos)
	arquivos = arquivos or {}
	fonte = string.gsub(fonte or "", "\r\n", "\n")
	local ok, ret = pcall(function()
		local expandida = expandirIncluir(fonte, arquivos, {})
		local toks = tokenizar(expandida)
		if #toks == 0 then return novaConfig() end
		return analisar(expandida, toks)
	end)
	if ok then
		return true, ret
	end
	if type(ret) ~= "table" then
		return false, { erro = "[interno] " .. tostring(ret), linha = 0 }
	end
	return false, { erro = ret.erro or "erro desconhecido", linha = ret.linha or 0 }
end

-----------------------------------------------------------------------
-- SERIALIZAÇÃO (LEGADA — arquitetura _YashConfig)
--   Mantida apenas para compatibilidade com o runtime legado e com scripts já
--   gravados. O caminho novo NÃO usa isto: o gerador de Luau é gerador.lua.
-----------------------------------------------------------------------

local RESERVADAS = {
	["and"] = true, ["break"] = true, ["continue"] = true, ["do"] = true,
	["else"] = true, ["elseif"] = true, ["end"] = true, ["false"] = true,
	["for"] = true, ["function"] = true, ["goto"] = true, ["if"] = true,
	["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
	["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true,
	["true"] = true, ["until"] = true, ["while"] = true,
}

-- Escape de texto em estilo Luau, de forma canonica e independente do host.
-- Nao usamos string.format("%q"): a saida muda entre Luau e Lua 5.3 e pode
-- gerar codigo invalido (ex.: \n virava barra + quebra de linha real).
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

local function chaveValida(k)
	return type(k) == "string"
		and string.match(k, "^[%a_][%w_]*$") ~= nil
		and not RESERVADAS[k]
end

local function chaveLua(k)
	if chaveValida(k) then return k end
	if type(k) == "string" then return escaparTexto(k) end
	return tostring(k)
end

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

local function valorLua(v, profundidade)
	local tabs = string.rep("\t", profundidade or 0)
	if type(v) == "number" then return numeroLua(v) end
	if type(v) == "boolean" then return tostring(v) end
	if type(v) == "string" then
		return escaparTexto(v)
	end
	if type(v) == "table" then
		if v.t == "cor" then
			return "cor(" .. numeroLua(v.r) .. ", " .. numeroLua(v.g) .. ", " .. numeroLua(v.b) .. ")"
		end
		if v.t == "par" then
			if v.z ~= nil then
				return "par(" .. numeroLua(v.x) .. ", " .. numeroLua(v.y) .. ", " .. numeroLua(v.z) .. ")"
			end
			return "par(" .. numeroLua(v.x) .. ", " .. numeroLua(v.y) .. ")"
		end
		-- array simples?
		local ehArray = true
		for k in pairs(v) do
			if type(k) ~= "number" then ehArray = false; break end
		end
		if ehArray and #v > 0 then
			local itens = {}
			for i = 1, #v do
				EMPILHAR(itens, valorLua(v[i], profundidade + 1))
			end
			return "{" .. table.concat(itens, ", ") .. "}"
		end
		-- mapa ordenado por chave
		local chaves = {}
		for k in pairs(v) do EMPILHAR(chaves, k) end
		table.sort(chaves, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local itens = {}
		for _, k in ipairs(chaves) do
			local chv = chaveLua(k)
			if chaveValida(k) then
				EMPILHAR(itens, chv .. " = " .. valorLua(v[k], profundidade + 1))
			else
				EMPILHAR(itens, "[" .. chv .. "] = " .. valorLua(v[k], profundidade + 1))
			end
		end
		return "{\n" .. tabs .. "\t" .. table.concat(itens, ",\n" .. tabs .. "\t") .. "\n" .. tabs .. "}"
	end
	return "nil"
end

function Compilador.Serializar(config)
	return "return " .. valorLua(config, 0)
end

-----------------------------------------------------------------------
-- DESCOMPILAÇÃO (LEGADA — config -> código .yash)
--   Só o caminho legado usa. O plugin agora guarda a fonte YashScript no
--   atributo "YashScript" do script e NÃO precisa ler o Source de volta.
-----------------------------------------------------------------------

local function textoValor(v)
	if type(v) == "number" then return tostring(v) end
	if type(v) == "boolean" then return v and "verdadeiro" or "falso" end
	if type(v) == "string" then return escaparTexto(v) end
	if type(v) == "table" then
		if v.t == "cor" then
			return string.format("rgb(%d,%d,%d)", v.r or 0, v.g or 0, v.b or 0)
		elseif v.t == "par" then
			if v.z ~= nil then
				return string.format("(%s, %s, %s)", tostring(v.x), tostring(v.y), tostring(v.z))
			end
			return string.format("(%s, %s)", tostring(v.x), tostring(v.y))
		elseif v.t == "anim" then
			local cl = {}
			if v.efeito and v.efeito ~= "" then table.insert(cl, v.efeito) end
			for k, vv in pairs(v) do
				if k ~= "t" and k ~= "efeito" then
					table.insert(cl, k .. " = " .. textoValor(vv))
				end
			end
			return table.concat(cl, " + ")
		end
	end
	return tostring(v)
end

-- renderiza de volta para YashScript um valor RICO do parser (campo `expr`)
local function textoExpr(e)
	if not e then return "" end
	if e.k == "num" then return tostring(e.v) end
	if e.k == "str" then return escaparTexto(e.v) end
	if e.k == "bool" then return e.v and "verdadeiro" or "falso" end
	if e.k == "nulo" then return "nulo" end
	if e.k == "ident" then return tostring(e.v) end
	if e.k == "caminho" then return table.concat(e.partes, ".") end
	if e.k == "unario" then return tostring(e.op) .. textoExpr(e.valor) end
	if e.k == "binario" then
		return "(" .. textoExpr(e.esq) .. " " .. tostring(e.op) .. " " .. textoExpr(e.dir) .. ")"
	end
	if e.k == "chamada" then
		local args = {}
		for _, arg in ipairs(e.args or {}) do table.insert(args, textoExpr(arg)) end
		return textoExpr(e.alvo) .. "(" .. table.concat(args, ", ") .. ")"
	end
	if e.k == "metodo_expr" then
		local args = {}
		for _, arg in ipairs(e.args or {}) do table.insert(args, textoExpr(arg)) end
		return textoExpr(e.base) .. ":" .. tostring(e.metodo) .. "(" .. table.concat(args, ", ") .. ")"
	end
	if e.k == "membro" then return textoExpr(e.base) .. "." .. tostring(e.nome) end
	if e.k == "indice" then return textoExpr(e.base) .. "[" .. textoExpr(e.chave) .. "]" end
	if e.k == "tabela" then
		local campos = {}
		for _, campo in ipairs(e.campos or {}) do
			if campo.chave then
				table.insert(campos, "[" .. textoExpr(campo.chave) .. "] = " .. textoExpr(campo.valor))
			else
				table.insert(campos, textoExpr(campo.valor))
			end
		end
		return "{" .. table.concat(campos, ", ") .. "}"
	end
	if e.k == "cor" then
		return string.format("rgb(%s, %s, %s)", tostring(e.r), tostring(e.g), tostring(e.b))
	end
	if e.k == "par" then
		local partes = { tostring(e.x), tostring(e.y) }
		if e.z then table.insert(partes, tostring(e.z)) end
		return "(" .. table.concat(partes, ", ") .. ")"
	end
	if e.k == "param" then
		return tostring(e.nome) .. " = " .. textoExpr(e.valor)
	end
	if e.k == "anim" then
		local cl = {}
		if e.efeito and e.efeito ~= "" then table.insert(cl, tostring(e.efeito)) end
		local ks = {}
		for nome in pairs(e.params or {}) do table.insert(ks, nome) end
		table.sort(ks)
		for _, nome in ipairs(ks) do
			table.insert(cl, nome .. " = " .. textoExpr(e.params[nome]))
		end
		return table.concat(cl, " + ")
	end
	return textoValor(e.v)
end

local function textoProps(props)
	local linhas = {}
	for k, v in pairs(props or {}) do
		table.insert(linhas, string.format("    %s = %s", k, textoValor(v)))
	end
	table.sort(linhas)
	return table.concat(linhas, "\n")
end

local function textoCond(c)
	if not c then return "" end
	if c.tipo == "logica" then
		return textoCond(c.esq) .. " " .. c.op .. " " .. textoCond(c.dir)
	elseif c.tipo == "nao" then
		return "nao (" .. textoCond(c.cond) .. ")"
	elseif c.tipo == "comp" then
		return textoExpr(c.esq) .. " " .. c.op .. " " .. textoExpr(c.dir)
	elseif c.tipo == "truthy" then
		return textoExpr(c.valor)
	elseif c.tipo == "estado" then
		return c.oq .. "('" .. c.el .. "')"
	elseif c.tipo == "num" then
		return c.obj .. " " .. c.op .. " " .. tostring(c.val)
	elseif c.tipo == "tecla" then
		return c.obj .. " apertar " .. c.tecla
	elseif c.tipo == "vida" then
		return c.alvo .. " " .. (c.estado and "vivo" or "morto")
	elseif c.tipo == "dist" then
		if c.op == "<" then
			if c.raio then return c.a .. " perto de " .. c.b end
			return "distancia " .. c.a .. " de " .. c.b .. " menor que " .. tostring(c.val)
		end
		if c.raio then return c.a .. " longe de " .. c.b end
		return "distancia " .. c.a .. " de " .. c.b .. " maior que " .. tostring(c.val)
	elseif c.tipo == "tocar" then
		return c.a .. " tocar " .. c.b
	elseif c.tipo == "criado" then
		return string.format("%q criado com sucesso", c.nome)
	end
	return ""
end

local function sufixoAnim(anim)
	if not anim then return "" end
	return " animacao = " .. textoExpr(anim)
end

local function empilharComandos(corpo, recuo, linhas)
	for _, cmd in ipairs(corpo or {}) do
		if cmd.tipo == "log" then
			if cmd.args then
				local args = {}
				for _, arg in ipairs(cmd.args) do table.insert(args, textoExpr(arg)) end
				table.insert(linhas, recuo .. "print(" .. table.concat(args, ", ") .. ")")
			elseif cmd.caminho then
				table.insert(linhas, recuo .. "print(" .. cmd.caminho .. ")")
			elseif cmd.forma == "mostrar" then
				table.insert(linhas, recuo .. "mostrar texto " .. escaparTexto(cmd.texto))
			else
				table.insert(linhas, recuo .. "print(" .. escaparTexto(cmd.texto) .. ")")
			end
		elseif cmd.tipo == "cena" then
			local prefixo = cmd.acao == "mudar" and "mudar cena" or (cmd.acao .. " cena")
			table.insert(linhas, recuo .. prefixo .. " '" .. cmd.alvo .. "'" .. sufixoAnim(cmd.anim))
		elseif cmd.tipo == "visivel" then
			table.insert(linhas, recuo .. cmd.acao .. "('" .. cmd.alvo .. "')" .. sufixoAnim(cmd.anim))
		elseif cmd.tipo == "prop" then
			for k, v in pairs(cmd.props or {}) do
				table.insert(linhas, recuo .. k .. " = " .. textoValor(v))
			end
		elseif cmd.tipo == "animacao" then
			table.insert(linhas, recuo .. "executar animacao " .. cmd.nome .. sufixoAnim(cmd.anim))
		elseif cmd.tipo == "tween" then
			table.insert(linhas, recuo .. "animar(" .. escaparTexto(cmd.alvo) .. ") " .. textoExpr(cmd.valor))
		elseif cmd.tipo == "acao" then
			table.insert(linhas, recuo .. "executar acao " .. cmd.nome)
		elseif cmd.tipo == "destruir" then
			table.insert(linhas, recuo .. "destruir " .. cmd.oq .. " " .. cmd.alvo)
		elseif cmd.tipo == "metodo" then
			-- preserva o separador original (ponto ou dois pontos) e os argumentos
			local sep = cmd.sep or "."
			local args = {}
			for _, v in ipairs(cmd.args or {}) do table.insert(args, textoExpr(v)) end
			table.insert(linhas, recuo .. cmd.alvo .. sep .. cmd.metodo
				.. "(" .. table.concat(args, ", ") .. ")")
		elseif cmd.tipo == "atrib" then
			table.insert(linhas, recuo .. cmd.caminho .. " " .. cmd.op .. " "
				.. (cmd.expr and textoExpr(cmd.expr) or textoValor(cmd.valor)))
		elseif cmd.tipo == "atrib_indice" then
			table.insert(linhas, recuo .. textoExpr(cmd.destino) .. " " .. cmd.op .. " " .. textoExpr(cmd.expr))
		elseif cmd.tipo == "soma" then
			if cmd.op == "somar" then
				table.insert(linhas, recuo .. "somar " .. cmd.de .. " a " .. cmd.para)
			else
				table.insert(linhas, recuo .. "subtrair " .. cmd.de .. " de " .. cmd.para)
			end
		elseif cmd.tipo == "se" then
			table.insert(linhas, recuo .. "se " .. textoCond(cmd.cond))
			empilharComandos(cmd.corpo, recuo .. "    ", linhas)
			for _, alternativa in ipairs(cmd.alternativas or {}) do
				table.insert(linhas, recuo .. "senao se " .. textoCond(alternativa.cond))
				empilharComandos(alternativa.corpo, recuo .. "    ", linhas)
			end
			if cmd.senao then
				table.insert(linhas, recuo .. "senao")
				empilharComandos(cmd.senao, recuo .. "    ", linhas)
			end
			table.insert(linhas, recuo .. "fim")
		elseif cmd.tipo == "enquanto" then
			table.insert(linhas, recuo .. "enquanto " .. textoCond(cmd.cond))
			empilharComandos(cmd.corpo, recuo .. "    ", linhas)
			table.insert(linhas, recuo .. "fim")
		elseif cmd.tipo == "repita" then
			table.insert(linhas, recuo .. "repita")
			empilharComandos(cmd.corpo, recuo .. "    ", linhas)
			table.insert(linhas, recuo .. "ate " .. textoCond(cmd.cond))
		elseif cmd.tipo == "pare" then
			table.insert(linhas, recuo .. "pare")
		elseif cmd.tipo == "continuar" then
			table.insert(linhas, recuo .. "continuar")
		elseif cmd.tipo == "para" then
			table.insert(linhas, recuo .. "para " .. cmd.nome .. " de " .. textoExpr(cmd.inicio)
				.. " ate " .. textoExpr(cmd.limite) .. " passo " .. textoExpr(cmd.passo))
			empilharComandos(cmd.corpo, recuo .. "    ", linhas)
			table.insert(linhas, recuo .. "fim")
		elseif cmd.tipo == "para_cada" then
			table.insert(linhas, recuo .. "para cada " .. table.concat(cmd.nomes or {}, ", ")
				.. " em " .. textoExpr(cmd.colecao))
			empilharComandos(cmd.corpo, recuo .. "    ", linhas)
			table.insert(linhas, recuo .. "fim")
		elseif cmd.tipo == "espera" then
			table.insert(linhas, recuo .. "esperar " .. tostring(cmd.valor))
		elseif cmd.tipo == "dano" then
			table.insert(linhas, recuo .. "causar dano " .. cmd.alvo .. " " .. tostring(cmd.valor))
		elseif cmd.tipo == "curar" then
			table.insert(linhas, recuo .. "curar " .. cmd.alvo .. " " .. tostring(cmd.valor))
		elseif cmd.tipo == "matar" then
			table.insert(linhas, recuo .. "matar " .. cmd.alvo)
		elseif cmd.tipo == "respawnar" then
			table.insert(linhas, recuo .. "respawnar " .. cmd.alvo)
		elseif cmd.tipo == "teleportar" then
			table.insert(linhas, recuo .. "teleportar " .. cmd.alvo .. " " .. textoValor(cmd.pos))
		elseif cmd.tipo == "mover" then
			table.insert(linhas, recuo .. "mover " .. cmd.alvo .. " para " .. textoValor(cmd.para) .. " velocidade " .. tostring(cmd.velocidade))
		elseif cmd.tipo == "rotacionar" then
			table.insert(linhas, recuo .. "rotacionar " .. cmd.alvo .. " para " .. textoValor(cmd.para) .. " duracao " .. tostring(cmd.duracao))
		elseif cmd.tipo == "sortear" then
			table.insert(linhas, recuo .. "sortear " .. cmd.nome .. " entre " .. tostring(cmd.min) .. " e " .. tostring(cmd.max))
		elseif cmd.tipo == "som" then
			table.insert(linhas, recuo .. "tocar som " .. cmd.id)
		elseif cmd.tipo == "explodir" then
			table.insert(linhas, recuo .. "explodir " .. cmd.alvo .. " raio " .. tostring(cmd.raio) .. " dano " .. tostring(cmd.dano))
		elseif cmd.tipo == "seguir" then
			table.insert(linhas, recuo .. "seguir " .. cmd.quem .. " o " .. cmd.alvo)
		elseif cmd.tipo == "variavel" then
			table.insert(linhas, recuo .. "variavel " .. cmd.nome .. (cmd.expr and (" = " .. textoExpr(cmd.expr)) or ""))
		elseif cmd.tipo == "retornar" then
			table.insert(linhas, recuo .. "retornar" .. (cmd.expr and (" " .. textoExpr(cmd.expr)) or ""))
		elseif cmd.tipo == "expressao" then
			table.insert(linhas, recuo .. textoExpr(cmd.expr))
		end
	end
end

local function chavesOrdenadas(tab)
	local chaves = {}
	for k in pairs(tab or {}) do table.insert(chaves, k) end
	table.sort(chaves, function(a, b) return tostring(a) < tostring(b) end)
	return chaves
end

function Compilador.Descompilar(config)
	config = config or {}
	local L = {}
	if config.marcador then
		table.insert(L, "YASHSCRIPT:")
	end

	for _, inc in ipairs(config.incluir or {}) do
		table.insert(L, 'incluir "' .. inc .. '"')
	end

	if config.site and next(config.site) then
		table.insert(L, "site")
		table.insert(L, textoProps(config.site))
		table.insert(L, "fim")
	end

	if config.mundo and next(config.mundo) then
		table.insert(L, "mundo")
		table.insert(L, textoProps(config.mundo))
		table.insert(L, "fim")
	end

	for _, nome in ipairs(chavesOrdenadas(config.cenas)) do
		table.insert(L, "criar cena '" .. nome .. "'")
		table.insert(L, textoProps(config.cenas[nome]))
		table.insert(L, "fim")
	end

	for _, nome in ipairs(chavesOrdenadas(config.estilos)) do
		table.insert(L, "criar estilo '" .. nome .. "'")
		table.insert(L, textoProps(config.estilos[nome]))
		table.insert(L, "fim")
	end

	local vistos = {}
	for _, nome in ipairs(config.ordem_elementos or {}) do
		local def = config.elementos[nome]
		if def then
			table.insert(L, "criar " .. def.tipo .. " '" .. nome .. "'")
			table.insert(L, textoProps(def.props))
			table.insert(L, "fim")
			vistos[nome] = true
		end
	end
	for _, nome in ipairs(chavesOrdenadas(config.elementos)) do
		if not vistos[nome] then
			local def = config.elementos[nome]
			table.insert(L, "criar " .. def.tipo .. " '" .. nome .. "'")
			table.insert(L, textoProps(def.props))
			table.insert(L, "fim")
		end
	end

	for _, nome in ipairs(chavesOrdenadas(config.objetos)) do
		table.insert(L, "criar objeto '" .. nome .. "'")
		table.insert(L, textoProps(config.objetos[nome]))
		table.insert(L, "fim")
	end

	for _, nome in ipairs(chavesOrdenadas(config.formas)) do
		local def = config.formas[nome]
		table.insert(L, "criar " .. def.tipo .. " '" .. nome .. "'")
		table.insert(L, textoProps(def.props))
		table.insert(L, "fim")
	end

	for _, tme in ipairs(config.timers or {}) do
		table.insert(L, "a cada " .. tostring(tme.intervalo))
		local linhas = {}
		empilharComandos(tme.corpo, "    ", linhas)
		for _, l in ipairs(linhas) do table.insert(L, l) end
		table.insert(L, "fim")
	end

	for _, nome in ipairs(chavesOrdenadas(config.huds)) do
		table.insert(L, "criar hud '" .. nome .. "'")
		if config.huds[nome].campo then
			table.insert(L, "    mostrar " .. config.huds[nome].campo)
		end
		table.insert(L, "fim")
	end

	for _, nome in ipairs(chavesOrdenadas(config.acoes)) do
		table.insert(L, "criar acao '" .. nome .. "'")
		local linhas = {}
		empilharComandos(config.acoes[nome], "    ", linhas)
		for _, l in ipairs(linhas) do table.insert(L, l) end
		table.insert(L, "fim")
	end

	for _, nome in ipairs(chavesOrdenadas(config.funcoes)) do
		local def = config.funcoes[nome]
		table.insert(L, "criar funcao " .. nome .. "(" .. table.concat(def.parametros or {}, ", ") .. ")")
		local linhas = {}
		empilharComandos(def.corpo, "    ", linhas)
		for _, l in ipairs(linhas) do table.insert(L, l) end
		table.insert(L, "fim")
	end

	for _, nome in ipairs(chavesOrdenadas(config.animacoes)) do
		table.insert(L, "criar animacao '" .. nome .. "'")
		for _, a in ipairs(config.animacoes[nome].lista or {}) do
			table.insert(L, "    animacao = " .. textoExpr(a))
		end
		table.insert(L, "fim")
	end

	-- `usar "Nome" = <caminho>` volta a ser `usar` na descompilacao
	for _, al in ipairs(config.aliases or {}) do
		table.insert(L, "usar " .. escaparTexto(al.nome) .. " = " .. textoExpr(al.expr))
	end

	local linhasCmd = {}
	empilharComandos(config.comandos, "", linhasCmd)
	for _, l in ipairs(linhasCmd) do table.insert(L, l) end

	for _, ev in ipairs(config.eventos or {}) do
		local cab
		if ev.sujeito then
			cab = "quando " .. ev.sujeito .. " " .. ev.tipo
			if ev.alvo then cab = cab .. " '" .. ev.alvo .. "'" end
		elseif ev.tipo == "carregar" or ev.tipo == "iniciar" then
			cab = "quando " .. ev.tipo
		else
			cab = "quando " .. ev.tipo .. " '" .. ev.alvo .. "'"
		end
		table.insert(L, cab)
		local linhas = {}
		empilharComandos(ev.corpo, "    ", linhas)
		for _, l in ipairs(linhas) do table.insert(L, l) end
		table.insert(L, "fim")
	end

	for _, c in ipairs(config.continuos or {}) do
		table.insert(L, "se " .. textoCond(c.cond))
		local linhas = {}
		empilharComandos(c.corpo, "    ", linhas)
		for _, l in ipairs(linhas) do table.insert(L, l) end
		for _, alternativa in ipairs(c.alternativas or {}) do
			table.insert(L, "senao se " .. textoCond(alternativa.cond))
			linhas = {}
			empilharComandos(alternativa.corpo, "    ", linhas)
			for _, l in ipairs(linhas) do table.insert(L, l) end
		end
		if c.senao then
			table.insert(L, "senao")
			linhas = {}
			empilharComandos(c.senao, "    ", linhas)
			for _, l in ipairs(linhas) do table.insert(L, l) end
		end
		table.insert(L, "fim")
	end

	for _, c in ipairs(config.loops or {}) do
		table.insert(L, "enquanto " .. textoCond(c.cond))
		local linhas = {}
		empilharComandos(c.corpo, "    ", linhas)
		for _, l in ipairs(linhas) do table.insert(L, l) end
		table.insert(L, "fim")
	end

	for _, p in ipairs(config.proibicoes or {}) do
		local linha = "proibir " .. p.evt .. " '" .. p.alvo .. "' de "
			.. table.concat(p.comandos or {}, " + ")
		if p.cond then linha = linha .. " se " .. textoCond(p.cond) end
		if p.somente then linha = linha .. " somente " .. escaparTexto(p.somente) end
		table.insert(L, linha)
	end

	return table.concat(L, "\n") .. "\n"
end

function Compilador.Tokenizar(fonte)
	local ok, ret = pcall(tokenizar, string.gsub(fonte or "", "\r\n", "\n"))
	if ok then return true, ret end
	return false, { erro = ret.erro or "erro", linha = ret.linha or 0 }
end

return Compilador
