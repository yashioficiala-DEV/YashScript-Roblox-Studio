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
	Compilador = HttpService:JSONDecode("\"--[[\\n  YashScript V8.0 — Núcleo do compilador: lexer + parser (Luau puro, sem Roblox)\\n\\n  ARQUITETURA ATUAL (V8.0)\\n    YashScript  ->  Compilar  ->  programa  ->  gerador.GerarLuau  ->  Luau puro\\n\\n  Este arquivo cuida da PRIMEIRA etapa: tokenizar e produzir o programa\\n  (a estrutura intermediária). A tradução para Luau mora em gerador.lua, e o\\n  Source do Script recebe só o Luau — sem `_YashConfig`, sem interpretador.\\n\\n  O parser devolve uma estrutura intermediária exclusiva do compilador. O\\n  plugin grava a fonte original no atributo \\\"YashScript\\\" e escreve Luau\\n  direto no Source; não há runtime interpretado no pipeline V8.\\n\\n  Funciona fora do Roblox (Lua 5.1+), o que permite testar a gramática localmente.\\n\\n  Uso:\\n    local compilador = require(script.compilador)   -- ou dofile no host\\n    local ok, resultado = compilador.Compilar(fonte)\\n    -- ok = true  -> resultado = programa (estrutura intermediária)\\n    -- ok = false -> resultado = { erro = \\\"mensagem\\\", linha = n }\\n]]\\n\\nlocal Compilador = { VERSAO = \\\"8.0\\\" }\\n\\nlocal EMPILHAR = table.insert\\n\\n-----------------------------------------------------------------------\\n-- LEXER\\n-----------------------------------------------------------------------\\n\\n-- produz: { t = \\\"palavra|numero|string|simbolo|nova\\\", v = valor, l = linha, ini, fim }\\nlocal function tokenizar(texto)\\n\\tlocal toks = {}\\n\\tlocal i, n = 1, #texto\\n\\tlocal linha = 1\\n\\n\\tlocal function lerNumero(inicio, sinal)\\n\\t\\tlocal num = sinal or \\\"\\\"\\n\\t\\tif sinal then i = i + 1 end\\n\\t\\twhile i <= n and string.match(texto:sub(i, i), \\\"%d\\\") do\\n\\t\\t\\tnum = num .. texto:sub(i, i)\\n\\t\\t\\ti = i + 1\\n\\t\\tend\\n\\t\\tif texto:sub(i, i) == \\\".\\\" and string.match(texto:sub(i + 1, i + 1), \\\"%d\\\") then\\n\\t\\t\\tnum = num .. \\\".\\\"\\n\\t\\t\\ti = i + 1\\n\\t\\t\\twhile i <= n and string.match(texto:sub(i, i), \\\"%d\\\") do\\n\\t\\t\\t\\tnum = num .. texto:sub(i, i)\\n\\t\\t\\t\\ti = i + 1\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\t-- Expoente: 1e7 / 1E-7 / 2.5e+3. Sem isso \\\"1e-7\\\" virava \\\"1 e -7\\\".\\n\\t\\tif texto:sub(i, i):match(\\\"[eE]\\\") then\\n\\t\\t\\tlocal expo = texto:sub(i, i)\\n\\t\\t\\tlocal sExpo = texto:sub(i + 1, i + 1)\\n\\t\\t\\tif sExpo == \\\"+\\\" or sExpo == \\\"-\\\" then\\n\\t\\t\\t\\texpo = expo .. sExpo\\n\\t\\t\\t\\ti = i + 2 -- pula o sinal: o digito vem DEPOIS dele\\n\\t\\t\\tend\\n\\t\\t\\tlocal digitos = \\\"\\\"\\n\\t\\t\\twhile i <= n and texto:sub(i, i):match(\\\"%d\\\") do\\n\\t\\t\\t\\tdigitos = digitos .. texto:sub(i, i)\\n\\t\\t\\t\\ti = i + 1\\n\\t\\t\\tend\\n\\t\\t\\t-- \\\"1e\\\" sem digitos NAO e numero: devolve os caracteres.\\n\\t\\t\\tif digitos ~= \\\"\\\" then\\n\\t\\t\\t\\tnum = num .. expo .. digitos\\n\\t\\t\\telse\\n\\t\\t\\t\\ti = i - #expo\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tlocal valor = tonumber(num)\\n\\t\\tif valor == nil then\\n\\t\\t\\terror(\\\"número inválido: \\\" .. num, 0)\\n\\t\\tend\\n\\t\\tEMPILHAR(toks, { t = \\\"numero\\\", v = valor, l = linha, ini = inicio, fim = i - 1 })\\n\\tend\\n\\n\\twhile i <= n do\\n\\t\\tlocal c = texto:sub(i, i)\\n\\t\\tif c == \\\"\\\\n\\\" then\\n\\t\\t\\tEMPILHAR(toks, { t = \\\"nova\\\", l = linha, ini = i, fim = i })\\n\\t\\t\\tlinha = linha + 1\\n\\t\\t\\ti = i + 1\\n\\t\\telseif c == \\\" \\\" or c == \\\"\\\\t\\\" or c == \\\"\\\\r\\\" then\\n\\t\\t\\ti = i + 1\\n\\t\\telseif c == \\\"#\\\" then\\n\\t\\t\\t-- comentário até o fim da linha\\n\\t\\t\\tlocal fimLinha = string.find(texto, \\\"\\\\n\\\", i, true)\\n\\t\\t\\tif fimLinha then i = fimLinha else i = n + 1 end\\n\\t\\telseif c == '\\\"' or c == \\\"'\\\" then\\n\\t\\t\\tlocal ini = i\\n\\t\\t\\tlocal aspas = c\\n\\t\\t\\tlocal buf = {}\\n\\t\\t\\ti = i + 1\\n\\t\\t\\twhile i <= n do\\n\\t\\t\\t\\tlocal cc = texto:sub(i, i)\\n\\t\\t\\t\\tif cc == \\\"\\\\\\\\\\\" then\\n\\t\\t\\t\\t\\tlocal nx = texto:sub(i + 1, i + 1)\\n\\t\\t\\t\\t\\tif nx == aspas then EMPILHAR(buf, aspas); i = i + 2\\n\\t\\t\\t\\t\\telseif nx == \\\"n\\\" then EMPILHAR(buf, \\\"\\\\n\\\"); i = i + 2\\n\\t\\t\\t\\t\\telseif nx == \\\"t\\\" then EMPILHAR(buf, \\\"\\\\t\\\"); i = i + 2\\n\\t\\t\\t\\t\\telseif nx == \\\"\\\\\\\\\\\" then EMPILHAR(buf, \\\"\\\\\\\\\\\"); i = i + 2\\n\\t\\t\\t\\t\\telseif nx == \\\"r\\\" then EMPILHAR(buf, \\\"\\\\r\\\"); i = i + 2\\n\\t\\t\\t\\t\\telseif nx:match(\\\"%d\\\") then\\n\\t\\t\\t\\t\\t\\t-- Escape decimal \\\\ddd: e o que o gerador emite para\\n\\t\\t\\t\\t\\t\\t-- caracteres de controle. Sem isso o ciclo nao fecha.\\n\\t\\t\\t\\t\\t\\tlocal d = texto:sub(i + 1, i + 3)\\n\\t\\t\\t\\t\\t\\tif d:match(\\\"^%d%d%d$\\\") then\\n\\t\\t\\t\\t\\t\\t\\tEMPILHAR(buf, string.char(tonumber(d)))\\n\\t\\t\\t\\t\\t\\t\\ti = i + 4\\n\\t\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\t\\tEMPILHAR(buf, cc); i = i + 1\\n\\t\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\telse EMPILHAR(buf, cc); i = i + 1 end\\n\\t\\t\\t\\telseif cc == aspas then\\n\\t\\t\\t\\t\\ti = i + 1\\n\\t\\t\\t\\t\\tbreak\\n\\t\\t\\t\\telseif cc == \\\"\\\\n\\\" then\\n\\t\\t\\t\\t\\tbreak\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\tEMPILHAR(buf, cc)\\n\\t\\t\\t\\t\\ti = i + 1\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\tEMPILHAR(toks, { t = \\\"string\\\", v = table.concat(buf), l = linha, ini = ini, fim = i - 1 })\\n\\t\\telseif string.match(c, \\\"%d\\\") then\\n\\t\\t\\tlerNumero(i, nil)\\n\\t\\telseif string.match(c, \\\"%a\\\") or c == \\\"_\\\" then\\n\\t\\t\\tlocal ini = i\\n\\t\\t\\tlocal palavra = \\\"\\\"\\n\\t\\t\\twhile i <= n and string.match(texto:sub(i, i), \\\"[%a_%d]\\\") do\\n\\t\\t\\t\\tpalavra = palavra .. texto:sub(i, i)\\n\\t\\t\\t\\ti = i + 1\\n\\t\\t\\tend\\n\\t\\t\\tEMPILHAR(toks, { t = \\\"palavra\\\", v = palavra, l = linha, ini = ini, fim = i - 1 })\\n\\t\\telse\\n\\t\\t\\t-- símbolos de 2 caracteres primeiro\\n\\t\\t\\tlocal dois = texto:sub(i, i + 1)\\n\\t\\t\\tif dois == \\\"<=\\\" or dois == \\\">=\\\" or dois == \\\"==\\\" or dois == \\\"!=\\\"\\n\\t\\t\\t\\tor dois == \\\"~=\\\" or dois == \\\"..\\\" or dois == \\\"//\\\" then\\n\\t\\t\\t\\tEMPILHAR(toks, { t = \\\"simbolo\\\", v = dois, l = linha, ini = i, fim = i + 1 })\\n\\t\\t\\t\\ti = i + 2\\n\\t\\t\\telseif dois == \\\"+=\\\" or dois == \\\"-=\\\" then\\n\\t\\t\\t\\t-- atribuição composta (jogador.moedas += 1)\\n\\t\\t\\t\\tEMPILHAR(toks, { t = \\\"simbolo\\\", v = dois, l = linha, ini = i, fim = i + 1 })\\n\\t\\t\\t\\ti = i + 2\\n\\t\\t\\telseif c == \\\"(\\\" or c == \\\")\\\" or c == \\\"[\\\" or c == \\\"]\\\" or c == \\\"{\\\" or c == \\\"}\\\"\\n\\t\\t\\t\\tor c == \\\"=\\\" or c == \\\",\\\" or c == \\\";\\\" or c == \\\"+\\\" or c == \\\"-\\\"\\n\\t\\t\\t\\tor c == \\\"*\\\" or c == \\\"/\\\" or c == \\\"%\\\" or c == \\\"^\\\" or c == \\\".\\\"\\n\\t\\t\\t\\tor c == \\\"<\\\" or c == \\\">\\\" or c == \\\"!\\\" or c == \\\":\\\" then\\n\\t\\t\\t\\tEMPILHAR(toks, { t = \\\"simbolo\\\", v = c, l = linha, ini = i, fim = i })\\n\\t\\t\\t\\ti = i + 1\\n\\t\\t\\telse\\n\\t\\t\\t\\terror({ erro = \\\"caractere inesperado '\\\" .. c .. \\\"'\\\", linha = linha }, 0)\\n\\t\\t\\tend\\n\\t\\tend\\n\\tend\\n\\treturn toks\\nend\\n\\n-----------------------------------------------------------------------\\n-- PARSER\\n-----------------------------------------------------------------------\\n\\n-- config inicial\\nlocal function novaConfig()\\n\\treturn {\\n\\t\\tincluir = {},\\n\\t\\taliases = {},\\n\\t\\tcomandos = {},\\n\\t\\tsite = {},\\n\\t\\tmundo = {},\\n\\t\\testilos = {},\\n\\t\\tcenas = {},\\n\\t\\telementos = {},\\n\\t\\tformas = {},\\n\\t\\tobjetos = {},\\n\\t\\tvariaveis = {},\\n\\t\\thuds = {},\\n\\t\\tacoes = {},\\n\\t\\tfuncoes = {},\\n\\t\\tanimacoes = {},\\n\\t\\teventos = {},\\n\\t\\tcontinuos = {},\\n\\t\\tloops = {},\\n\\t\\ttimers = {},\\n\\t\\tproibicoes = {},\\n\\t\\tordem_elementos = {},\\n\\t}\\nend\\n\\n-- eventos aceitos em blocos \\\"quando\\\". Serve para distinguir a forma legada\\n-- (\\\"quando tocar 'moeda'\\\") da forma com sujeito (\\\"quando jogador tocar moeda\\\"):\\n-- se a primeira palavra NÃO for um evento conhecido, ela é o sujeito.\\nlocal EVENTOS_CONHECIDOS = {\\n\\tcarregar = true,\\n\\tiniciar = true,\\n\\ttocar = true,\\n\\tencostar = true,\\n\\tclicar = true,\\n\\tmouse_em = true,\\n\\tmouse_sair = true,\\n}\\n\\n-- Eventos em que o proprio sujeito e o alvo.\\n-- Para clicar/mouse_em/mouse_sair o sujeito vira o alvo, e ai as duas formas\\n-- valem:\\n--     quando clicar Botao      (alvo depois do evento)\\n--     quando Botao clicar      (sujeito antes do evento)\\n-- Para tocar nao: emissor e alvo sao sempre separados.\\n--     quando Cubo tocar moeda\\nlocal EMISSOR_PROPRIO = {\\n\\tclicar = true,\\n\\tmouse_em = true,\\n\\tmouse_sair = true,\\n}\\n\\nlocal function analisar(fonte, toks)\\n\\tlocal config = novaConfig()\\n\\tlocal idx = 1\\n\\tlocal funcoesDeclaradas = {}\\n\\tfor pos = 1, #toks - 2 do\\n\\t\\tif toks[pos].t == \\\"palavra\\\" and toks[pos].v == \\\"criar\\\"\\n\\t\\t\\tand toks[pos + 1] and toks[pos + 1].t == \\\"palavra\\\" and toks[pos + 1].v == \\\"funcao\\\"\\n\\t\\t\\tand toks[pos + 2] and toks[pos + 2].t == \\\"palavra\\\" then\\n\\t\\t\\tfuncoesDeclaradas[toks[pos + 2].v] = true\\n\\t\\tend\\n\\tend\\n\\n\\tlocal function at() return toks[idx] end\\n\\n\\tlocal function avancar() idx = idx + 1 end\\n\\n\\tlocal function fimLinha()\\n\\t\\tlocal t = at()\\n\\t\\treturn t == nil or t.t == \\\"nova\\\"\\n\\tend\\n\\n\\tlocal function pularNovas()\\n\\t\\twhile at() and at().t == \\\"nova\\\" do avancar() end\\n\\tend\\n\\n\\tlocal function erroJ(msg)\\n\\t\\tlocal l = 0\\n\\t\\tif at() and at().l then l = at().l end\\n\\t\\terror({ erro = msg, linha = l }, 0)\\n\\t\\treturn nil\\n\\tend\\n\\n\\tlocal function espera(tipo, val)\\n\\t\\tlocal t = at()\\n\\t\\tif not t then erroJ(\\\"fim inesperado do arquivo\\\") end\\n\\t\\tif t.t ~= tipo then erroJ(\\\"esperava \\\" .. tipo .. \\\" mas veio '\\\" .. tostring(t.v) .. \\\"'\\\") end\\n\\t\\tif val and tostring(t.v) ~= val then erroJ(\\\"esperava '\\\" .. val .. \\\"' mas veio '\\\" .. tostring(t.v) .. \\\"'\\\") end\\n\\t\\tavancar()\\n\\t\\treturn t.v\\n\\tend\\n\\n\\t-- aceita nome entre aspas OU identificador simples\\n\\tlocal function esperaNome()\\n\\t\\tlocal t = at()\\n\\t\\tif not t then erroJ(\\\"nome esperado (entre aspas ou identificador)\\\") end\\n\\t\\tif t.t == \\\"string\\\" or t.t == \\\"palavra\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn t.v\\n\\t\\tend\\n\\t\\treturn erroJ(\\\"nome esperado (entre aspas ou identificador)\\\")\\n\\tend\\n\\n\\t-- caminho: jogador.vida  ou  apenas jogador\\n\\tlocal function lerCaminho()\\n\\t\\tlocal t = at()\\n\\t\\tif not t or t.t ~= \\\"palavra\\\" then erroJ(\\\"nome de objeto esperado\\\") end\\n\\t\\tlocal nome = t.v\\n\\t\\tavancar()\\n\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\".\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal atrib = espera(\\\"palavra\\\")\\n\\t\\t\\treturn nome .. \\\".\\\" .. atrib\\n\\t\\tend\\n\\t\\treturn nome\\n\\tend\\n\\n\\t-- aceita \\\"Nome\\\", Nome ou Nome.filho.neto (varios niveis) — usado por\\n\\t-- comandos com alvo, como `animar(\\\"Gui.Botao\\\")`, onde o alvo pode ser\\n\\t-- um caminho completo da arvore\\n\\tlocal function lerNomeCaminho()\\n\\t\\tlocal t = at()\\n\\t\\tif not t then erroJ(\\\"nome esperado\\\") end\\n\\t\\tif t.t == \\\"string\\\" then avancar(); return t.v end\\n\\t\\tif t.t ~= \\\"palavra\\\" then erroJ(\\\"nome esperado (entre aspas ou identificador)\\\") end\\n\\t\\tlocal nome = t.v\\n\\t\\tavancar()\\n\\t\\twhile at() and at().t == \\\"simbolo\\\" and at().v == \\\".\\\" do\\n\\t\\t\\tavancar()\\n\\t\\t\\tnome = nome .. \\\".\\\" .. espera(\\\"palavra\\\")\\n\\t\\tend\\n\\t\\treturn nome\\n\\tend\\n\\n\\t-- converte o texto de caminho (A.B.C) no valor rico `caminho` do gerador\\n\\tlocal function exprCaminho(caminho)\\n\\t\\tlocal e = { k = \\\"caminho\\\", partes = {} }\\n\\t\\tfor p in string.gmatch(tostring(caminho), \\\"[^%.]+\\\") do\\n\\t\\t\\ttable.insert(e.partes, p)\\n\\t\\tend\\n\\t\\treturn e\\n\\tend\\n\\n\\t-- extrai o texto exato de um trecho de tokens (preserva \\\"0px\\\", \\\"0.4s\\\" etc.)\\n\\tlocal function textoTrecho(inic, fimm)\\n\\t\\tlocal t1 = toks[inic]\\n\\t\\tlocal t2 = toks[fimm]\\n\\t\\tlocal t = fonte:sub(t1.ini, t2.fim)\\n\\t\\tt = string.gsub(t, \\\"^%s+\\\", \\\"\\\")\\n\\t\\tt = string.gsub(t, \\\"%s+$\\\", \\\"\\\")\\n\\t\\treturn t\\n\\tend\\n\\n\\t-- classifica uma lista de índices de tokens como valor\\n\\t--\\n\\t-- YASHSCRIPT: além dos formatos legados, o classificador reconhece valores\\n\\t-- \\\"ricos\\\" que o gerador de Luau consome diretamente:\\n\\t--   k = \\\"caminho\\\" -> A.B.C   (caminho da árvore do Roblox ou alias)\\n\\t--   k = \\\"ident\\\"   -> palavra (nome solto: alias, serviço ou constante)\\n\\t--   k = \\\"bool\\\"    -> verdadeiro / falso / sim / nao\\n\\t--   k = \\\"nulo\\\"    -> nulo\\n\\t-- `valorFinal` continua convertendo tudo para o formato legado, então o\\n\\t-- comportamento antigo dos blocos `criar` não muda.\\n\\tlocal PRECEDENCIA_EXPR = {\\n\\t\\t[\\\"ou\\\"] = 1, [\\\"or\\\"] = 1, [\\\"e\\\"] = 2, [\\\"and\\\"] = 2,\\n\\t\\t[\\\"<\\\"] = 3, [\\\">\\\"] = 3, [\\\"<=\\\"] = 3, [\\\">=\\\"] = 3,\\n\\t\\t[\\\"=\\\"] = 3, [\\\"==\\\"] = 3, [\\\"!=\\\"] = 3, [\\\"~=\\\"] = 3,\\n\\t\\t[\\\"..\\\"] = 4, [\\\"+\\\"] = 5, [\\\"-\\\"] = 5,\\n\\t\\t[\\\"*\\\"] = 6, [\\\"/\\\"] = 6, [\\\"//\\\"] = 6, [\\\"%\\\"] = 6, [\\\"^\\\"] = 7,\\n\\t}\\n\\tlocal function analisarExpressao(indices)\\n\\t\\tlocal pos = 1\\n\\t\\tlocal function tokenAtual() return indices[pos] and toks[indices[pos]] end\\n\\t\\tlocal parseExpressao\\n\\t\\tlocal function primario()\\n\\t\\t\\tlocal tk = tokenAtual()\\n\\t\\t\\tif not tk then return nil end\\n\\t\\t\\tif tk.t == \\\"simbolo\\\" and (tk.v == \\\"-\\\" or tk.v == \\\"+\\\") then\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\tlocal v = primario()\\n\\t\\t\\t\\tif not v then return nil end\\n\\t\\t\\t\\treturn { k = \\\"unario\\\", op = tk.v, valor = v }\\n\\t\\t\\tend\\n\\t\\t\\tif tk.t == \\\"palavra\\\" and (tk.v == \\\"nao\\\" or tk.v == \\\"not\\\") then\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\tlocal v = primario()\\n\\t\\t\\t\\tif not v then return nil end\\n\\t\\t\\t\\treturn { k = \\\"unario\\\", op = \\\"not\\\", valor = v }\\n\\t\\t\\tend\\n\\t\\t\\tlocal function lerArgumentos(fecho)\\n\\t\\t\\t\\tlocal args = {}\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\tif tokenAtual() and tokenAtual().t == \\\"simbolo\\\" and tokenAtual().v == fecho then\\n\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\t\\treturn args\\n\\t\\t\\t\\tend\\n\\t\\t\\twhile true do\\n\\t\\t\\t\\tlocal arg = parseExpressao(1)\\n\\t\\t\\t\\tif not arg then return nil end\\n\\t\\t\\t\\ttable.insert(args, arg)\\n\\t\\t\\t\\tif tokenAtual() and tokenAtual().t == \\\"simbolo\\\" and tokenAtual().v == \\\",\\\" then\\n\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\telse break end\\n\\t\\t\\tend\\n\\t\\t\\tif not tokenAtual() or tokenAtual().t ~= \\\"simbolo\\\" or tokenAtual().v ~= fecho then return nil end\\n\\t\\t\\tpos = pos + 1\\n\\t\\t\\treturn args\\n\\t\\tend\\n\\t\\t\\tlocal function sufixos(expr)\\n\\t\\t\\t\\twhile tokenAtual() do\\n\\t\\t\\t\\t\\tlocal prox = tokenAtual()\\n\\t\\t\\t\\t\\tif prox.t == \\\"simbolo\\\" and prox.v == \\\".\\\" then\\n\\t\\t\\t\\t\\t\\tlocal nome = indices[pos + 1] and toks[indices[pos + 1]]\\n\\t\\t\\t\\t\\t\\tif not nome or nome.t ~= \\\"palavra\\\" then return nil end\\n\\t\\t\\t\\t\\t\\tpos = pos + 2\\n\\t\\t\\t\\t\\t\\tif expr.k == \\\"ident\\\" then\\n\\t\\t\\t\\t\\t\\t\\texpr = { k = \\\"caminho\\\", partes = { expr.v, nome.v } }\\n\\t\\t\\t\\t\\t\\telseif expr.k == \\\"caminho\\\" then\\n\\t\\t\\t\\t\\t\\t\\ttable.insert(expr.partes, nome.v)\\n\\t\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\t\\texpr = { k = \\\"membro\\\", base = expr, nome = nome.v }\\n\\t\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\telseif prox.t == \\\"simbolo\\\" and prox.v == \\\"[\\\" then\\n\\t\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\t\\t\\tlocal chave = parseExpressao(1)\\n\\t\\t\\t\\t\\t\\tif not chave or not tokenAtual() or tokenAtual().t ~= \\\"simbolo\\\" or tokenAtual().v ~= \\\"]\\\" then return nil end\\n\\t\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\t\\t\\texpr = { k = \\\"indice\\\", base = expr, chave = chave }\\n\\t\\t\\t\\t\\telseif prox.t == \\\"simbolo\\\" and prox.v == \\\"(\\\" then\\n\\t\\t\\t\\t\\t\\tlocal args = lerArgumentos(\\\")\\\")\\n\\t\\t\\t\\t\\t\\tif not args then return nil end\\n\\t\\t\\t\\t\\t\\texpr = { k = \\\"chamada\\\", alvo = expr, args = args }\\n\\t\\t\\t\\t\\telseif prox.t == \\\"simbolo\\\" and prox.v == \\\":\\\" then\\n\\t\\t\\t\\t\\t\\tlocal metodo = indices[pos + 1] and toks[indices[pos + 1]]\\n\\t\\t\\t\\t\\t\\tif not metodo or metodo.t ~= \\\"palavra\\\" or not indices[pos + 2]\\n\\t\\t\\t\\t\\t\\t\\tor toks[indices[pos + 2]].v ~= \\\"(\\\" then return nil end\\n\\t\\t\\t\\t\\t\\tpos = pos + 2\\n\\t\\t\\t\\t\\t\\tlocal args = lerArgumentos(\\\")\\\")\\n\\t\\t\\t\\t\\t\\tif not args then return nil end\\n\\t\\t\\t\\t\\t\\texpr = { k = \\\"metodo_expr\\\", base = expr, metodo = metodo.v, args = args }\\n\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\tbreak\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\treturn expr\\n\\t\\t\\tend\\n\\n\\t\\t\\tlocal expr\\n\\t\\t\\tif tk.t == \\\"numero\\\" then pos = pos + 1; expr = { k = \\\"num\\\", v = tk.v }\\n\\t\\t\\telseif tk.t == \\\"string\\\" then pos = pos + 1; expr = { k = \\\"str\\\", v = tk.v }\\n\\t\\t\\telseif tk.t == \\\"simbolo\\\" and tk.v == \\\"(\\\" then\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\texpr = parseExpressao(1)\\n\\t\\t\\t\\tif not expr or not tokenAtual() or tokenAtual().v ~= \\\")\\\" then return nil end\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\telseif tk.t == \\\"simbolo\\\" and tk.v == \\\"{\\\" then\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\tlocal campos = {}\\n\\t\\t\\t\\twhile tokenAtual() and not (tokenAtual().t == \\\"simbolo\\\" and tokenAtual().v == \\\"}\\\") do\\n\\t\\t\\t\\t\\tlocal chave, valor\\n\\t\\t\\t\\t\\tlocal atual = tokenAtual()\\n\\t\\t\\t\\t\\tif atual.t == \\\"simbolo\\\" and atual.v == \\\"[\\\" then\\n\\t\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\t\\t\\tchave = parseExpressao(1)\\n\\t\\t\\t\\t\\t\\tif not chave or not tokenAtual() or tokenAtual().v ~= \\\"]\\\" then return nil end\\n\\t\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\t\\t\\tif not tokenAtual() or tokenAtual().v ~= \\\"=\\\" then return nil end\\n\\t\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\t\\t\\tvalor = parseExpressao(1)\\n\\t\\t\\t\\t\\telseif (atual.t == \\\"palavra\\\" or atual.t == \\\"string\\\") and indices[pos + 1]\\n\\t\\t\\t\\t\\t\\tand toks[indices[pos + 1]].t == \\\"simbolo\\\" and toks[indices[pos + 1]].v == \\\"=\\\" then\\n\\t\\t\\t\\t\\t\\tchave = { k = \\\"str\\\", v = atual.v }\\n\\t\\t\\t\\t\\t\\tpos = pos + 2\\n\\t\\t\\t\\t\\t\\tvalor = parseExpressao(1)\\n\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\tvalor = parseExpressao(1)\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\tif not valor then return nil end\\n\\t\\t\\t\\t\\ttable.insert(campos, { chave = chave, valor = valor })\\n\\t\\t\\t\\t\\tif tokenAtual() and tokenAtual().t == \\\"simbolo\\\" and tokenAtual().v == \\\",\\\" then\\n\\t\\t\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\t\\telse break end\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tif not tokenAtual() or tokenAtual().t ~= \\\"simbolo\\\" or tokenAtual().v ~= \\\"}\\\" then return nil end\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\texpr = { k = \\\"tabela\\\", campos = campos }\\n\\t\\t\\telseif tk.t == \\\"palavra\\\" then\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\tlocal baixo = string.lower(tk.v)\\n\\t\\t\\t\\tif baixo == \\\"verdadeiro\\\" or baixo == \\\"sim\\\" then expr = { k = \\\"bool\\\", v = true }\\n\\t\\t\\t\\telseif baixo == \\\"falso\\\" or baixo == \\\"nao\\\" then expr = { k = \\\"bool\\\", v = false }\\n\\t\\t\\t\\telseif baixo == \\\"nulo\\\" then expr = { k = \\\"nulo\\\" }\\n\\t\\t\\t\\telse expr = { k = \\\"ident\\\", v = tk.v }\\n\\t\\t\\t\\tend\\n\\t\\t\\telse return nil end\\n\\t\\t\\treturn sufixos(expr)\\n\\t\\tend\\n\\t\\tparseExpressao = function(min)\\n\\t\\t\\tlocal esquerda = primario()\\n\\t\\t\\tif not esquerda then return nil end\\n\\t\\t\\twhile tokenAtual() do\\n\\t\\t\\t\\tlocal tk = tokenAtual()\\n\\t\\t\\t\\tlocal op = tk.v\\n\\t\\t\\t\\tif tk.t == \\\"palavra\\\" then op = string.lower(op) end\\n\\t\\t\\t\\tlocal prec = PRECEDENCIA_EXPR[op]\\n\\t\\t\\t\\tif not prec or prec < min then break end\\n\\t\\t\\t\\tpos = pos + 1\\n\\t\\t\\t\\tlocal direita = parseExpressao(prec + ((op == \\\"^\\\" or op == \\\"..\\\") and 0 or 1))\\n\\t\\t\\t\\tif not direita then return nil end\\n\\t\\t\\t\\tesquerda = { k = \\\"binario\\\", op = op, esq = esquerda, dir = direita }\\n\\t\\t\\tend\\n\\t\\t\\treturn esquerda\\n\\t\\tend\\n\\t\\tlocal expr = parseExpressao(1)\\n\\t\\tif expr and pos > #indices then return expr end\\n\\t\\treturn nil\\n\\tend\\n\\n\\tlocal function classificarClausula(c)\\n\\t\\tif #c == 1 then\\n\\t\\t\\tlocal tk1 = toks[c[1]]\\n\\t\\t\\tif tk1.t == \\\"string\\\" then return { k = \\\"str\\\", v = tk1.v }\\n\\t\\t\\telseif tk1.t == \\\"numero\\\" then return { k = \\\"num\\\", v = tk1.v }\\n\\t\\t\\telseif tk1.t == \\\"palavra\\\" then\\n\\t\\t\\t\\tlocal l = string.lower(tostring(tk1.v))\\n\\t\\t\\t\\tif l == \\\"verdadeiro\\\" or l == \\\"sim\\\" then return { k = \\\"bool\\\", v = true }\\n\\t\\t\\t\\telseif l == \\\"falso\\\" or l == \\\"nao\\\" then return { k = \\\"bool\\\", v = false }\\n\\t\\t\\t\\telseif l == \\\"nulo\\\" then return { k = \\\"nulo\\\" }\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\treturn { k = \\\"ident\\\", v = tk1.v }\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tlocal texto = textoTrecho(c[1], c[#c])\\n\\t\\t-- cor: rgb(r,g,b) / rgba(r,g,b,a)  -> tokens: palavra \\\"rgb\\\", \\\"(\\\", num, \\\",\\\", num, \\\",\\\", num, [\\\",\\\",num,] \\\")\\\"\\n\\t\\tlocal t1 = toks[c[1]]\\n\\t\\tlocal t2 = toks[c[2]]\\n\\t\\tif t1.t == \\\"palavra\\\" and (t1.v == \\\"rgb\\\" or t1.v == \\\"rgba\\\") and t2 and t2.t == \\\"simbolo\\\" and t2.v == \\\"(\\\" then\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tlocal j = 3\\n\\t\\t\\twhile j <= #c do\\n\\t\\t\\t\\tlocal tkj = toks[c[j]]\\n\\t\\t\\t\\tif tkj.t == \\\"numero\\\" then EMPILHAR(args, tkj.v) end\\n\\t\\t\\t\\tj = j + 1\\n\\t\\t\\tend\\n\\t\\t\\tif #args >= 3 then\\n\\t\\t\\t\\treturn { k = \\\"cor\\\", r = args[1], g = args[2], b = args[3] }\\n\\t\\t\\tend\\n\\t\\t\\terroJ(\\\"cor inválida: \\\" .. texto)\\n\\t\\tend\\n\\t\\t-- par triplo: (x, y)  ou  (x, y, z)\\n\\t\\tif t1.t == \\\"simbolo\\\" and t1.v == \\\"(\\\" and toks[c[#c]].t == \\\"simbolo\\\" and toks[c[#c]].v == \\\")\\\" then\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tlocal temVirgula = false\\n\\t\\t\\tlocal sinal = 1\\n\\t\\t\\tlocal esperaValor, tuplaSimples = true, true\\n\\t\\t\\tfor j = 2, #c - 1 do\\n\\t\\t\\t\\tlocal tkj = toks[c[j]]\\n\\t\\t\\t\\tif tkj.t == \\\"simbolo\\\" and tkj.v == \\\",\\\" and not esperaValor then\\n\\t\\t\\t\\t\\ttemVirgula = true\\n\\t\\t\\t\\t\\tesperaValor = true\\n\\t\\t\\t\\t\\tsinal = 1\\n\\t\\t\\t\\telseif tkj.t == \\\"simbolo\\\" and esperaValor and (tkj.v == \\\"-\\\" or tkj.v == \\\"+\\\") then\\n\\t\\t\\t\\t\\tsinal = tkj.v == \\\"-\\\" and -1 or 1\\n\\t\\t\\t\\telseif tkj.t == \\\"numero\\\" and esperaValor then\\n\\t\\t\\t\\t\\tEMPILHAR(args, sinal * tkj.v)\\n\\t\\t\\t\\t\\tesperaValor = false\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\ttuplaSimples = false\\n\\t\\t\\t\\t\\tbreak\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\tif tuplaSimples and temVirgula and not esperaValor and #args >= 2 then\\n\\t\\t\\t\\tlocal r = { k = \\\"par\\\", x = args[1], y = args[2] }\\n\\t\\t\\t\\tif #args >= 3 then r.z = args[3] end\\n\\t\\t\\t\\treturn r\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\t-- caminho: palavra (. palavra)*     ->  A.B.C\\n\\t\\tlocal partes = {}\\n\\t\\tlocal ehCaminho = true\\n\\t\\tlocal j = 1\\n\\t\\twhile j <= #c do\\n\\t\\t\\tlocal tkj = toks[c[j]]\\n\\t\\t\\tif tkj.t == \\\"palavra\\\" then\\n\\t\\t\\t\\tEMPILHAR(partes, tkj.v)\\n\\t\\t\\t\\tj = j + 1\\n\\t\\t\\t\\tif j <= #c then\\n\\t\\t\\t\\t\\tlocal sep = toks[c[j]]\\n\\t\\t\\t\\t\\tif sep.t == \\\"simbolo\\\" and sep.v == \\\".\\\" then\\n\\t\\t\\t\\t\\t\\tj = j + 1\\n\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\tehCaminho = false\\n\\t\\t\\t\\t\\t\\tbreak\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\tend\\n\\t\\t\\telse\\n\\t\\t\\t\\tehCaminho = false\\n\\t\\t\\t\\tbreak\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tif ehCaminho and #partes >= 2 then\\n\\t\\t\\treturn { k = \\\"caminho\\\", partes = partes }\\n\\t\\tend\\n\\t\\t-- parâmetro: nome = valor\\n\\t\\tif #c >= 3 then\\n\\t\\t\\tlocal a0 = toks[c[1]]\\n\\t\\t\\tlocal a1 = toks[c[2]]\\n\\t\\t\\tif a0.t == \\\"palavra\\\" and a1.t == \\\"simbolo\\\" and a1.v == \\\"=\\\" then\\n\\t\\t\\t\\tlocal resto = {}\\n\\t\\t\\t\\tfor jp = 3, #c do EMPILHAR(resto, c[jp]) end\\n\\t\\t\\t\\tlocal vval = classificarClausula(resto)\\n\\t\\t\\t\\treturn { k = \\\"param\\\", nome = a0.v, valor = vval }\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tif #c > 1 then\\n\\t\\t\\tlocal expr = analisarExpressao(c)\\n\\t\\t\\tif expr then return expr end\\n\\t\\tend\\n\\t\\treturn { k = \\\"str\\\", v = texto }\\n\\tend\\n\\n\\t-- transforma um valor classificado no formato final de config\\n\\t-- (formato legado; o gerador de Luau usa o `expr` rico direto do parser)\\n\\tlocal function valorFinal(v)\\n\\t\\tif not v then return nil end\\n\\t\\tif v.k == \\\"num\\\" then return v.v\\n\\t\\telseif v.k == \\\"str\\\" then return v.v\\n\\t\\telseif v.k == \\\"ident\\\" then return v.v\\n\\t\\telseif v.k == \\\"caminho\\\" then return table.concat(v.partes, \\\".\\\")\\n\\t\\telseif v.k == \\\"bool\\\" then return v.v\\n\\t\\telseif v.k == \\\"nulo\\\" then return nil\\n\\t\\telseif v.k == \\\"cor\\\" then return { t = \\\"cor\\\", r = v.r, g = v.g, b = v.b }\\n\\t\\telseif v.k == \\\"par\\\" then\\n\\t\\t\\tlocal r = { t = \\\"par\\\", x = v.x, y = v.y }\\n\\t\\t\\tif v.z then r.z = v.z end\\n\\t\\t\\treturn r\\n\\t\\telseif v.k == \\\"anim\\\" then\\n\\t\\t\\tlocal r = { t = \\\"anim\\\", efeito = v.efeito }\\n\\t\\t\\tfor k, vv in pairs(v.params or {}) do r[k] = valorFinal(vv) end\\n\\t\\t\\treturn r\\n\\t\\tend\\n\\t\\treturn nil\\n\\tend\\n\\n\\t-- lê um \\\"valor\\\" até o fim da linha, quebrando cláusulas no \\\"+\\\" de separação\\n\\tlocal function parseValor(expressao, delimitador)\\n\\t\\tif expressao then\\n\\t\\t\\tlocal indices = {}\\n\\t\\t\\tlocal profundidadeParen, profundidadeColchete, profundidadeChave = 0, 0, 0\\n\\t\\t\\twhile not fimLinha() do\\n\\t\\t\\t\\tlocal tk = at()\\n\\t\\t\\t\\tif delimitador and profundidadeParen == 0 and profundidadeColchete == 0 and profundidadeChave == 0\\n\\t\\t\\t\\t\\tand tk.t == \\\"simbolo\\\" and (tk.v == delimitador or tk.v == \\\",\\\") then break end\\n\\t\\t\\t\\tEMPILHAR(indices, idx)\\n\\t\\t\\t\\tif tk.t == \\\"simbolo\\\" then\\n\\t\\t\\t\\t\\tif tk.v == \\\"(\\\" then profundidadeParen = profundidadeParen + 1\\n\\t\\t\\t\\t\\telseif tk.v == \\\")\\\" then profundidadeParen = math.max(0, profundidadeParen - 1)\\n\\t\\t\\t\\t\\telseif tk.v == \\\"[\\\" then profundidadeColchete = profundidadeColchete + 1\\n\\t\\t\\t\\t\\telseif tk.v == \\\"]\\\" then profundidadeColchete = math.max(0, profundidadeColchete - 1)\\n\\t\\t\\t\\t\\telseif tk.v == \\\"{\\\" then profundidadeChave = profundidadeChave + 1\\n\\t\\t\\t\\t\\telseif tk.v == \\\"}\\\" then profundidadeChave = math.max(0, profundidadeChave - 1) end\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\tend\\n\\t\\t\\tif #indices == 0 then return nil end\\n\\t\\t\\treturn classificarClausula(indices)\\n\\t\\tend\\n\\t\\tlocal clausulas = {}\\n\\t\\tlocal atual = nil\\n\\t\\twhile not fimLinha() do\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t.t == \\\"simbolo\\\" and t.v == \\\"+\\\" and not atual then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\telseif t.t == \\\"simbolo\\\" and t.v == \\\"+\\\" then\\n\\t\\t\\t\\tlocal anterior = atual and atual[#atual] and toks[atual[#atual]]\\n\\t\\t\\t\\tif anterior and anterior.v == \\\"=\\\" then\\n\\t\\t\\t\\t\\t-- Sinal unário positivo em um parâmetro (escala = +5).\\n\\t\\t\\t\\t\\tEMPILHAR(atual, idx)\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\tEMPILHAR(clausulas, atual)\\n\\t\\t\\t\\t\\tatual = nil\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tend\\n\\t\\t\\telse\\n\\t\\t\\t\\tif not atual then atual = {} end\\n\\t\\t\\t\\tEMPILHAR(atual, idx)\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tif atual then EMPILHAR(clausulas, atual) end\\n\\n\\t\\tif #clausulas == 0 then return nil end\\n\\n\\t\\tif #clausulas == 1 then\\n\\t\\t\\treturn classificarClausula(clausulas[1])\\n\\t\\tend\\n\\n\\t\\t-- múltiplas cláusulas -> animação composta\\n\\t\\tlocal efeito = nil\\n\\t\\tlocal params = {}\\n\\t\\tfor i, cl in ipairs(clausulas) do\\n\\t\\t\\tlocal v = classificarClausula(cl)\\n\\t\\t\\tif v.k == \\\"param\\\" then\\n\\t\\t\\t\\tparams[v.nome] = v.valor\\n\\t\\t\\telseif i == 1 then\\n\\t\\t\\t\\tefeito = v\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn { k = \\\"anim\\\", efeito = (efeito and efeito.v) or \\\"\\\", params = params }\\n\\tend\\n\\n\\t-- Props removidas no V8: o gerador as descartava em silencio, ou seja,\\n\\t-- eram aceitas sem traduzir para nada. Agora sao erro explicito.\\n\\tlocal PROPS_REMOVIDAS = {\\n\\t\\ttransicao = \\\"propriedade `transicao` nao existe no Roblox; use `animar`\\\",\\n\\t\\tsombra = \\\"propriedade `sombra` (box-shadow do CSS) nao existe no Roblox\\\",\\n\\t\\tcontrolavel = \\\"propriedade `controlavel` era do runtime V7; nao ha equivalente no Luau gerado\\\",\\n\\t}\\n\\n\\t-- normaliza props booleanas conhecidas\\n\\tlocal function normalizarProps(props)\\n\\t\\tfor k, motivo in pairs(PROPS_REMOVIDAS) do\\n\\t\\t\\tif props[k] ~= nil then erroJ(motivo .. ' (propriedade removida no V8)') end\\n\\t\\tend\\n\\t\\tfor k, v in pairs(props) do\\n\\t\\t\\tif k == \\\"mostrar\\\" or k == \\\"inimigo\\\" then\\n\\t\\t\\t\\tif type(v) == \\\"string\\\" then\\n\\t\\t\\t\\t\\tlocal limpo = string.lower(string.gsub(v, \\\"%s+\\\", \\\"\\\"))\\n\\t\\t\\t\\t\\tif limpo == \\\"verdadeiro\\\" or limpo == \\\"sim\\\" or limpo == \\\"true\\\" then\\n\\t\\t\\t\\t\\t\\tprops[k] = true\\n\\t\\t\\t\\t\\telseif limpo == \\\"falso\\\" or limpo == \\\"nao\\\" or limpo == \\\"false\\\" then\\n\\t\\t\\t\\t\\t\\tprops[k] = false\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn props\\n\\tend\\n\\n\\t-- linha de propriedade simples: nome = valor\\n\\tlocal function parsePropLinha()\\n\\t\\tlocal nome = espera(\\\"palavra\\\")\\n\\t\\tespera(\\\"simbolo\\\", \\\"=\\\")\\n\\t\\tlocal v = parseValor()\\n\\t\\tif not v then erroJ(\\\"valor esperado após '\\\" .. nome .. \\\" ='\\\") end\\n\\t\\treturn nome, valorFinal(v)\\n\\tend\\n\\n\\t-- bloco de propriedades até \\\"fim\\\"\\n\\tlocal function parseBlocoProps()\\n\\t\\tlocal props = {}\\n\\t\\tpularNovas()\\n\\t\\twhile true do\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t == nil then erroJ(\\\"esperava 'fim'\\\") end\\n\\t\\t\\tif t.t == \\\"nova\\\" then avancar(); pularNovas()\\n\\t\\t\\telseif t.t == \\\"palavra\\\" and t.v == \\\"fim\\\" then avancar(); break\\n\\t\\t\\telse\\n\\t\\t\\t\\tlocal nome, v = parsePropLinha()\\n\\t\\t\\t\\tprops[nome] = v\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn normalizarProps(props)\\n\\tend\\n\\n\\t-- sufixo opcional: animacao = <valor>  (ex: mostrar(Painel) animacao = fade in)\\n\\t-- o valor fica RICO (mesmo formato de `animar`), para o gerador receber\\n\\t-- efeito + duracao/estilo/direcao sem perda\\n\\tlocal function parseAnimSufixo()\\n\\t\\tif fimLinha() then return nil end\\n\\t\\tlocal t = at()\\n\\t\\tif t.t == \\\"palavra\\\" and t.v == \\\"animacao\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\"=\\\")\\n\\t\\t\\tlocal v = parseValor()\\n\\t\\t\\tif not v then erroJ(\\\"valor esperado após 'animacao ='\\\") end\\n\\t\\t\\treturn v\\n\\t\\tend\\n\\t\\treturn erroJ(\\\"sintaxe inesperada após comando\\\")\\n\\tend\\n\\n\\tlocal function operandoCondicao()\\n\\t\\tlocal tk = at()\\n\\t\\tif not tk then erroJ(\\\"valor esperado na condição\\\") end\\n\\t\\tif tk.t == \\\"numero\\\" then avancar(); return { k = \\\"num\\\", v = tk.v } end\\n\\t\\tif tk.t == \\\"string\\\" then avancar(); return { k = \\\"str\\\", v = tk.v } end\\n\\t\\tif tk.t ~= \\\"palavra\\\" then erroJ(\\\"nome ou literal esperado na condição\\\") end\\n\\t\\tavancar()\\n\\t\\tlocal l = string.lower(tostring(tk.v))\\n\\t\\tif l == \\\"verdadeiro\\\" or l == \\\"sim\\\" then return { k = \\\"bool\\\", v = true } end\\n\\t\\tif l == \\\"falso\\\" or l == \\\"nao\\\" then return { k = \\\"bool\\\", v = false } end\\n\\t\\tif l == \\\"nulo\\\" then return { k = \\\"nulo\\\" } end\\n\\t\\tlocal partes = { tk.v }\\n\\t\\twhile at() and at().t == \\\"simbolo\\\" and at().v == \\\".\\\" do\\n\\t\\t\\tavancar()\\n\\t\\t\\ttable.insert(partes, espera(\\\"palavra\\\"))\\n\\t\\tend\\n\\t\\tif #partes == 1 then return { k = \\\"ident\\\", v = partes[1] } end\\n\\t\\treturn { k = \\\"caminho\\\", partes = partes }\\n\\tend\\n\\n\\tlocal function parseCondicao()\\n\\t\\tlocal t1 = at()\\n\\t\\tif not t1 or (t1.t ~= \\\"palavra\\\" and t1.t ~= \\\"string\\\" and t1.t ~= \\\"numero\\\") then erroJ(\\\"condição inválida\\\") end\\n\\n\\t\\tif t1.v == \\\"visivel\\\" or t1.v == \\\"oculto\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\"(\\\")\\n\\t\\t\\tlocal nome = espera(\\\"string\\\")\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\treturn { tipo = \\\"estado\\\", oq = t1.v, el = nome }\\n\\t\\tend\\n\\n\\t\\tif t1.v == \\\"distancia\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal a = espera(\\\"palavra\\\")\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"de\\\")\\n\\t\\t\\tlocal b = espera(\\\"palavra\\\")\\n\\t\\t\\tlocal comp = espera(\\\"palavra\\\")\\n\\t\\t\\tif comp ~= \\\"menor\\\" and comp ~= \\\"maior\\\" then erroJ(\\\"esperava 'menor' ou 'maior' após a distância\\\") end\\n\\t\\t\\tlocal que = at()\\n\\t\\t\\tif que and que.t == \\\"palavra\\\" and que.v == \\\"que\\\" then avancar() end\\n\\t\\t\\tlocal valtk = at()\\n\\t\\t\\tif not valtk or valtk.t ~= \\\"numero\\\" then erroJ(\\\"número esperado\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"dist\\\", a = a, b = b, op = (comp == \\\"menor\\\") and \\\"<\\\" or \\\">\\\", val = valtk.v }\\n\\t\\tend\\n\\n\\t\\t-- Comparações aritméticas usam a mesma gramática de expressões das\\n\\t\\t-- atribuições, sem interferir nos predicados naturais abaixo.\\n\\t\\tlocal comparadores = { [\\\"<\\\"] = true, [\\\">\\\"] = true, [\\\"<=\\\"] = true,\\n\\t\\t\\t[\\\">=\\\"] = true, [\\\"=\\\"] = true, [\\\"==\\\"] = true, [\\\"!=\\\"] = true, [\\\"~=\\\"] = true }\\n\\t\\tlocal inicio, comparador, fimEsq, fimDir = idx, nil, nil, nil\\n\\t\\tlocal profundidade, aritmetica = 0, false\\n\\t\\tlocal operadoresArit = { [\\\"+\\\"] = true, [\\\"-\\\"] = true, [\\\"*\\\"] = true,\\n\\t\\t\\t[\\\"/\\\"] = true, [\\\"//\\\"] = true, [\\\"%\\\"] = true, [\\\"^\\\"] = true, [\\\"..\\\"] = true }\\n\\t\\tlocal j = idx\\n\\t\\twhile toks[j] and toks[j].t ~= \\\"nova\\\" do\\n\\t\\t\\tlocal tk = toks[j]\\n\\t\\t\\tif tk.t == \\\"simbolo\\\" and tk.v == \\\"(\\\" then profundidade = profundidade + 1; aritmetica = true\\n\\t\\t\\telseif tk.t == \\\"simbolo\\\" and tk.v == \\\")\\\" then profundidade = math.max(0, profundidade - 1)\\n\\t\\t\\telseif profundidade == 0 and tk.t == \\\"palavra\\\"\\n\\t\\t\\t\\tand (tk.v == \\\"e\\\" or tk.v == \\\"ou\\\" or tk.v == \\\"and\\\" or tk.v == \\\"or\\\") then break\\n\\t\\t\\telseif profundidade == 0 and tk.t == \\\"simbolo\\\" and comparadores[tk.v] then\\n\\t\\t\\t\\tcomparador = tk.v\\n\\t\\t\\t\\tfimEsq = j - 1\\n\\t\\t\\t\\tj = j + 1\\n\\t\\t\\t\\tlocal profDir = 0\\n\\t\\t\\t\\twhile toks[j] and toks[j].t ~= \\\"nova\\\" do\\n\\t\\t\\t\\t\\tlocal td = toks[j]\\n\\t\\t\\t\\t\\tif td.t == \\\"simbolo\\\" and td.v == \\\"(\\\" then profDir = profDir + 1\\n\\t\\t\\t\\t\\telseif td.t == \\\"simbolo\\\" and td.v == \\\")\\\" then\\n\\t\\t\\t\\t\\t\\tif profDir == 0 then break end\\n\\t\\t\\t\\t\\t\\tprofDir = profDir - 1\\n\\t\\t\\t\\t\\telseif profDir == 0 and td.t == \\\"palavra\\\"\\n\\t\\t\\t\\t\\t\\tand (td.v == \\\"e\\\" or td.v == \\\"ou\\\" or td.v == \\\"and\\\" or td.v == \\\"or\\\") then break end\\n\\t\\t\\t\\t\\tj = j + 1\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tfimDir = j - 1\\n\\t\\t\\t\\tbreak\\n\\t\\t\\tend\\n\\t\\t\\tif tk.t == \\\"simbolo\\\" and operadoresArit[tk.v] then aritmetica = true end\\n\\t\\t\\tj = j + 1\\n\\t\\tend\\n\\t\\tif comparador and fimEsq >= inicio and fimDir >= fimEsq + 2 then\\n\\t\\t\\t-- Detecta operadores nos dois lados; comparações simples continuam no\\n\\t\\t\\t-- caminho existente para preservar condições especializadas.\\n\\t\\t\\tfor k = fimEsq + 2, fimDir do\\n\\t\\t\\t\\tlocal tk = toks[k]\\n\\t\\t\\t\\tif tk and tk.t == \\\"simbolo\\\" and operadoresArit[tk.v] then aritmetica = true end\\n\\t\\t\\tend\\n\\t\\t\\tif aritmetica then\\n\\t\\t\\t\\tlocal esquerda, direita = {}, {}\\n\\t\\t\\t\\tfor k = inicio, fimEsq do EMPILHAR(esquerda, k) end\\n\\t\\t\\t\\tfor k = fimEsq + 2, fimDir do EMPILHAR(direita, k) end\\n\\t\\t\\t\\tif #esquerda == 0 or #direita == 0 then erroJ(\\\"expressão incompleta na comparação\\\") end\\n\\t\\t\\t\\tidx = fimDir + 1\\n\\t\\t\\t\\treturn { tipo = \\\"comp\\\", esq = classificarClausula(esquerda),\\n\\t\\t\\t\\t\\top = comparador, dir = classificarClausula(direita) }\\n\\t\\t\\tend\\n\\t\\tend\\n\\n\\t\\tlocal lhs = operandoCondicao()\\n\\t\\tlocal obja = (lhs.k == \\\"caminho\\\" and table.concat(lhs.partes, \\\".\\\")) or lhs.v\\n\\t\\tlocal t2 = at()\\n\\t\\tif not t2 or t2.t == \\\"nova\\\" or (t2.t == \\\"palavra\\\" and (t2.v == \\\"senao\\\" or t2.v == \\\"fim\\\" or t2.v == \\\"entao\\\" or t2.v == \\\"e\\\" or t2.v == \\\"ou\\\" or t2.v == \\\"and\\\" or t2.v == \\\"or\\\")) then\\n\\t\\t\\tif lhs.k == \\\"ident\\\" and (lhs.v == \\\"vivo\\\" or lhs.v == \\\"morto\\\") then\\n\\t\\t\\t\\terroJ(\\\"a condição 'vivo' ou 'morto' precisa de um alvo antes dela\\\")\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"truthy\\\", valor = lhs }\\n\\t\\tend\\n\\n\\t\\tlocal opsDiretos = {\\n\\t\\t\\t[\\\"<\\\"] = true, [\\\">\\\"] = true, [\\\"<=\\\"] = true, [\\\">=\\\"] = true,\\n\\t\\t\\t[\\\"=\\\"] = true, [\\\"==\\\"] = true, [\\\"!=\\\"] = true,\\n\\t\\t}\\n\\t\\tif t2.t == \\\"simbolo\\\" and opsDiretos[t2.v] then\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"comp\\\", esq = lhs, op = t2.v, dir = operandoCondicao() }\\n\\t\\tend\\n\\n\\t\\tif t2.t == \\\"palavra\\\" and t2.v == \\\"apertar\\\" and lhs.k == \\\"ident\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal tecla = espera(\\\"palavra\\\")\\n\\t\\t\\treturn { tipo = \\\"tecla\\\", obj = obja, tecla = tecla }\\n\\t\\tend\\n\\n\\t\\tif t2.t == \\\"palavra\\\" and t2.v == \\\"tocar\\\" and lhs.k == \\\"ident\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal b = espera(\\\"palavra\\\")\\n\\t\\t\\treturn { tipo = \\\"tocar\\\", a = obja, b = b }\\n\\t\\tend\\n\\n\\t\\tif t2.t == \\\"palavra\\\" and (t2.v == \\\"vivo\\\" or t2.v == \\\"morto\\\") and lhs.k == \\\"ident\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"vida\\\", alvo = obja, estado = (t2.v == \\\"vivo\\\") }\\n\\t\\tend\\n\\n\\t\\tif t2.t == \\\"palavra\\\" and (t2.v == \\\"perto\\\" or t2.v == \\\"longe\\\") and lhs.k == \\\"ident\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"de\\\")\\n\\t\\t\\tlocal b = espera(\\\"palavra\\\")\\n\\t\\t\\treturn { tipo = \\\"dist\\\", a = obja, b = b, op = (t2.v == \\\"perto\\\") and \\\"<\\\" or \\\">\\\", raio = true, val = 12 }\\n\\t\\tend\\n\\n\\t\\tif t2.t == \\\"palavra\\\" and t2.v == \\\"criado\\\" and (lhs.k == \\\"str\\\" or lhs.k == \\\"ident\\\") then\\n\\t\\t\\tavancar()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"com\\\")\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"sucesso\\\")\\n\\t\\t\\treturn { tipo = \\\"criado\\\", nome = obja }\\n\\t\\tend\\n\\n\\t\\treturn { tipo = \\\"truthy\\\", valor = lhs }\\n\\tend\\n\\n\\t-- aceita `entao` opcional depois da condição: `se X > 5 entao` ou `se X > 5`\\n\\tlocal function parseCond()\\n\\t\\tlocal function atom()\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t and t.t == \\\"palavra\\\" and (t.v == \\\"nao\\\" or t.v == \\\"not\\\") then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\treturn { tipo = \\\"nao\\\", cond = atom() }\\n\\t\\t\\tend\\n\\t\\t\\tif t and t.t == \\\"simbolo\\\" and t.v == \\\"(\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal dentro = parseCond()\\n\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\t\\treturn dentro\\n\\t\\t\\tend\\n\\t\\t\\treturn parseCondicao()\\n\\t\\tend\\n\\t\\tlocal function e()\\n\\t\\t\\tlocal cond = atom()\\n\\t\\t\\twhile at() and at().t == \\\"palavra\\\" and (at().v == \\\"e\\\" or at().v == \\\"and\\\") do\\n\\t\\t\\t\\tlocal op = at().v\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tcond = { tipo = \\\"logica\\\", esq = cond, op = op, dir = atom() }\\n\\t\\t\\tend\\n\\t\\t\\treturn cond\\n\\t\\tend\\n\\t\\tlocal cond = e()\\n\\t\\twhile at() and at().t == \\\"palavra\\\" and (at().v == \\\"ou\\\" or at().v == \\\"or\\\") do\\n\\t\\t\\tlocal op = at().v\\n\\t\\t\\tavancar()\\n\\t\\t\\tcond = { tipo = \\\"logica\\\", esq = cond, op = op, dir = e() }\\n\\t\\tend\\n\\t\\tlocal nt = at()\\n\\t\\tif nt and nt.t == \\\"palavra\\\" and nt.v == \\\"entao\\\" then avancar() end\\n\\t\\treturn cond\\n\\tend\\n\\n\\t-- corpo de comandos até uma das palavras em parar (não consome o token)\\n\\tlocal parseComando\\n\\tlocal profundidadeLaco = 0\\n\\tlocal escoposVariaveis = {}\\n\\tlocal function variavelDeclarada(nome)\\n\\t\\tif config.variaveis[nome] then return true end\\n\\t\\tfor i = #escoposVariaveis, 1, -1 do\\n\\t\\t\\tif escoposVariaveis[i][nome] then return true end\\n\\t\\tend\\n\\t\\treturn false\\n\\tend\\n\\tlocal function parseComandos(parar)\\n\\t\\tlocal corpo = {}\\n\\t\\tpularNovas()\\n\\t\\twhile true do\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t == nil then return corpo end\\n\\t\\t\\tif t.t == \\\"nova\\\" then avancar(); pularNovas()\\n\\t\\t\\telseif t.t == \\\"palavra\\\" and parar[t.v] then return corpo\\n\\t\\t\\telse\\n\\t\\t\\t\\tEMPILHAR(corpo, parseComando())\\n\\t\\t\\tend\\n\\t\\tend\\n\\tend\\n\\tlocal function parseRamosSenao()\\n\\t\\tlocal alternativas, senao = {}, nil\\n\\t\\twhile at() and at().t == \\\"palavra\\\" and at().v == \\\"senao\\\" do\\n\\t\\t\\tavancar()\\n\\t\\t\\tif at() and at().t == \\\"palavra\\\" and at().v == \\\"se\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal cond = parseCond()\\n\\t\\t\\t\\tlocal corpo = parseComandos({ fim = true, senao = true })\\n\\t\\t\\t\\tEMPILHAR(alternativas, { cond = cond, corpo = corpo })\\n\\t\\t\\telse\\n\\t\\t\\t\\tsenao = parseComandos({ fim = true })\\n\\t\\t\\t\\tbreak\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn alternativas, senao\\n\\tend\\n\\tlocal function parseCorpoLaco()\\n\\t\\tprofundidadeLaco = profundidadeLaco + 1\\n\\t\\tlocal corpo = parseComandos({ fim = true })\\n\\t\\tprofundidadeLaco = profundidadeLaco - 1\\n\\t\\treturn corpo\\n\\tend\\n\\n\\tparseComando = function()\\n\\t\\tlocal t = at()\\n\\t\\tif not t or t.t ~= \\\"palavra\\\" then erroJ(\\\"comando esperado\\\") end\\n\\t\\tlocal a = t.v\\n\\t\\tavancar()\\n\\n\\t\\tif a == \\\"variavel\\\" or a == \\\"var\\\" or a == \\\"let\\\" then\\n\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\tlocal escopoAtual = escoposVariaveis[#escoposVariaveis]\\n\\t\\t\\tif escopoAtual then\\n\\t\\t\\t\\tif escopoAtual[nome] then erroJ(\\\"variável já declarada na função: '\\\" .. nome .. \\\"'\\\") end\\n\\t\\t\\t\\tescopoAtual[nome] = true\\n\\t\\t\\telse\\n\\t\\t\\t\\tif config.variaveis[nome] then erroJ(\\\"variável já declarada: '\\\" .. nome .. \\\"'\\\") end\\n\\t\\t\\t\\tconfig.variaveis[nome] = true\\n\\t\\t\\tend\\n\\t\\t\\tlocal expr = nil\\n\\t\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\"=\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\texpr = parseValor(true)\\n\\t\\t\\t\\tif not expr then erroJ(\\\"valor esperado após a declaração de '\\\" .. nome .. \\\"'\\\") end\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"variavel\\\", nome = nome, expr = expr, norm = \\\"variavel \\\" .. nome }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"retornar\\\" or a == \\\"devolver\\\" then\\n\\t\\t\\tlocal expr = nil\\n\\t\\t\\tif not fimLinha() then\\n\\t\\t\\t\\texpr = parseValor(true)\\n\\t\\t\\t\\tif not expr then erroJ(\\\"expressão esperada após 'retornar'\\\") end\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"retornar\\\", expr = expr, norm = \\\"retornar\\\" }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"pare\\\" or a == \\\"continuar\\\" then\\n\\t\\t\\tif profundidadeLaco == 0 then erroJ(\\\"'\\\" .. a .. \\\"' só pode ser usado dentro de um laço\\\") end\\n\\t\\t\\treturn { tipo = a, norm = a }\\n\\t\\tend\\n\\n\\t\\t-- YASHSCRIPT: acesso por ponto em comandos.\\n\\t\\t--   jogador.vida = 80      -> atribui dado do objeto\\n\\t\\t--   jogador.moedas += 1    -> atribuição composta\\n\\t\\t--   moeda.destruir()       -> chamada de método (ponto)\\n\\t\\t--   moeda:Destruir()       -> chamada de método Luau (dois pontos)\\n\\t\\t--   Workspace.Casa:PivotTo(...) -> chamada com base de caminho\\n\\t\\t--\\n\\t\\t-- Monta uma chamada de método a partir do alvo já lido: posiciona o\\n\\t\\t-- cursor no nome do método, consome os argumentos posicionais e devolve\\n\\t\\t-- o nó. `sep` guarda o separador usado, para o descompilador reemitir\\n\\t\\t-- exatamente a mesma forma.\\n\\t\\tlocal function metodoEm(partes, sep, idxNome)\\n\\t\\t\\tidx = idxNome\\n\\t\\t\\tlocal metodo = espera(\\\"palavra\\\")\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\"(\\\")\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tif not (at() and at().t == \\\"simbolo\\\" and at().v == \\\")\\\") then\\n\\t\\t\\t\\twhile true do\\n\\t\\t\\t\\t\\tlocal inicio = idx\\n\\t\\t\\t\\t\\tlocal profundidade = 0\\n\\t\\t\\t\\t\\twhile at() do\\n\\t\\t\\t\\t\\t\\tlocal tk = at()\\n\\t\\t\\t\\t\\t\\tif tk.t == \\\"simbolo\\\" and tk.v == \\\"(\\\" then profundidade = profundidade + 1\\n\\t\\t\\t\\t\\t\\telseif tk.t == \\\"simbolo\\\" and tk.v == \\\")\\\" then\\n\\t\\t\\t\\t\\t\\t\\tif profundidade == 0 then break end\\n\\t\\t\\t\\t\\t\\t\\tprofundidade = profundidade - 1\\n\\t\\t\\t\\t\\t\\telseif tk.t == \\\"simbolo\\\" and tk.v == \\\",\\\" and profundidade == 0 then break end\\n\\t\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\tif idx == inicio then erroJ(\\\"argumento esperado para '\\\" .. metodo .. \\\"'\\\") end\\n\\t\\t\\t\\t\\tlocal indices = {}\\n\\t\\t\\t\\t\\tfor j = inicio, idx - 1 do EMPILHAR(indices, j) end\\n\\t\\t\\t\\t\\tEMPILHAR(args, classificarClausula(indices))\\n\\t\\t\\t\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\",\\\" then\\n\\t\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\telse break end\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\tlocal alvo = table.concat(partes, \\\".\\\")\\n\\t\\t\\treturn { tipo = \\\"metodo\\\", metodo = metodo, alvo = alvo, args = args,\\n\\t\\t\\t\\tsep = sep, norm = alvo .. sep .. metodo .. \\\"()\\\" }\\n\\t\\tend\\n\\n\\t\\tlocal nt0 = at()\\n\\t\\tif nt0 and nt0.t == \\\"simbolo\\\" and (nt0.v == \\\"[\\\" or nt0.v == \\\".\\\") then\\n\\t\\t\\tlocal j = idx\\n\\t\\t\\tlocal indicesBase = { idx - 1 }\\n\\t\\t\\twhile toks[j] and toks[j].t == \\\"simbolo\\\" and toks[j].v == \\\".\\\"\\n\\t\\t\\t\\tand toks[j + 1] and toks[j + 1].t == \\\"palavra\\\" do\\n\\t\\t\\t\\tEMPILHAR(indicesBase, j)\\n\\t\\t\\t\\tEMPILHAR(indicesBase, j + 1)\\n\\t\\t\\t\\tj = j + 2\\n\\t\\t\\tend\\n\\t\\t\\tlocal operador = toks[j]\\n\\t\\t\\tif #indicesBase > 1 and operador and operador.t == \\\"simbolo\\\"\\n\\t\\t\\t\\tand (operador.v == \\\"=\\\" or operador.v == \\\"+=\\\" or operador.v == \\\"-=\\\") then\\n\\t\\t\\t\\tlocal partes = { a }\\n\\t\\t\\t\\tfor p = 2, #indicesBase, 2 do EMPILHAR(partes, toks[indicesBase[p + 1]].v) end\\n\\t\\t\\t\\tidx = j + 1\\n\\t\\t\\t\\tlocal valor = parseValor(true)\\n\\t\\t\\t\\tif not valor then erroJ(\\\"valor esperado após a atribuição a '\\\" .. table.concat(partes, \\\".\\\") .. \\\"'\\\") end\\n\\t\\t\\t\\tlocal caminho = table.concat(partes, \\\".\\\")\\n\\t\\t\\t\\treturn { tipo = \\\"atrib\\\", op = operador.v, caminho = caminho, valor = valorFinal(valor),\\n\\t\\t\\t\\t\\texpr = valor, norm = caminho .. \\\" \\\" .. operador.v }\\n\\t\\t\\tend\\n\\t\\t\\tif toks[j] and toks[j].t == \\\"simbolo\\\" and toks[j].v == \\\"[\\\" then\\n\\t\\t\\t\\tlocal destino = classificarClausula(indicesBase)\\n\\t\\t\\t\\tidx = j\\n\\t\\t\\t\\twhile at() and at().t == \\\"simbolo\\\" and at().v == \\\"[\\\" do\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\tlocal inicio, profundidade = idx, 0\\n\\t\\t\\t\\t\\twhile at() do\\n\\t\\t\\t\\t\\t\\tlocal tk = at()\\n\\t\\t\\t\\t\\t\\tif tk.t == \\\"simbolo\\\" and tk.v == \\\"[\\\" then profundidade = profundidade + 1\\n\\t\\t\\t\\t\\t\\telseif tk.t == \\\"simbolo\\\" and tk.v == \\\"]\\\" then\\n\\t\\t\\t\\t\\t\\t\\tif profundidade == 0 then break end\\n\\t\\t\\t\\t\\t\\t\\tprofundidade = profundidade - 1\\n\\t\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\tif idx == inicio then erroJ(\\\"índice vazio\\\") end\\n\\t\\t\\t\\t\\tlocal indicesChave = {}\\n\\t\\t\\t\\t\\tfor k = inicio, idx - 1 do EMPILHAR(indicesChave, k) end\\n\\t\\t\\t\\t\\tlocal chave = classificarClausula(indicesChave)\\n\\t\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\"]\\\")\\n\\t\\t\\t\\t\\tdestino = { k = \\\"indice\\\", base = destino, chave = chave }\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tlocal opTk = at()\\n\\t\\t\\t\\tif not opTk or opTk.t ~= \\\"simbolo\\\" or (opTk.v ~= \\\"=\\\" and opTk.v ~= \\\"+=\\\" and opTk.v ~= \\\"-=\\\") then\\n\\t\\t\\t\\t\\terroJ(\\\"esperava '=' ou atribuição composta após o índice\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tlocal op = opTk.v\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal valor = parseValor(true)\\n\\t\\t\\t\\tif not valor then erroJ(\\\"valor esperado após a atribuição por índice\\\") end\\n\\t\\t\\t\\treturn { tipo = \\\"atrib_indice\\\", destino = destino, op = op, expr = valor,\\n\\t\\t\\t\\t\\tnorm = \\\"atribuição por índice \\\" .. op }\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tif nt0 and nt0.t == \\\"simbolo\\\" and (nt0.v == \\\".\\\" or nt0.v == \\\":\\\") then\\n\\t\\t\\t-- Base completa: palavra seguida de (.palavra)*, sem consumir tokens.\\n\\t\\t\\t-- Isso permite tanto `moeda:Destruir()` quanto `Workspace.Casa:PivotTo()`.\\n\\t\\t\\tlocal j = idx\\n\\t\\t\\tlocal partes = { a }\\n\\t\\t\\twhile toks[j] and toks[j].t == \\\"simbolo\\\" and toks[j].v == \\\".\\\"\\n\\t\\t\\t\\tand toks[j + 1] and toks[j + 1].t == \\\"palavra\\\" do\\n\\t\\t\\t\\ttable.insert(partes, toks[j + 1].v)\\n\\t\\t\\t\\tj = j + 2\\n\\t\\t\\tend\\n\\n\\t\\t\\t-- <base>:<metodo>(args) -> chamada de método Luau\\n\\t\\t\\tif toks[j] and toks[j].t == \\\"simbolo\\\" and toks[j].v == \\\":\\\"\\n\\t\\t\\t\\tand toks[j + 1] and toks[j + 1].t == \\\"palavra\\\"\\n\\t\\t\\t\\tand toks[j + 2] and toks[j + 2].t == \\\"simbolo\\\" and toks[j + 2].v == \\\"(\\\" then\\n\\t\\t\\t\\treturn metodoEm(partes, \\\":\\\", j + 1)\\n\\t\\t\\tend\\n\\n\\t\\t\\t-- <base>.<campo> = valor -> atribuição (apenas com ponto)\\n\\t\\t\\tif nt0.v == \\\".\\\" then\\n\\t\\t\\t\\tlocal t2, t3 = toks[idx + 1], toks[idx + 2]\\n\\t\\t\\t\\tif t2 and t2.t == \\\"palavra\\\" and t3 and t3.t == \\\"simbolo\\\" then\\n\\t\\t\\t\\t\\tif t3.v == \\\"=\\\" or t3.v == \\\"+=\\\" or t3.v == \\\"-=\\\" then\\n\\t\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\t\\tlocal prop = espera(\\\"palavra\\\")\\n\\t\\t\\t\\t\\t\\tlocal op = at().v\\n\\t\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\t\\tlocal v = parseValor(true)\\n\\t\\t\\t\\t\\t\\tif not v then erroJ(\\\"valor esperado em '\\\" .. a .. \\\".\\\" .. prop .. \\\"'\\\") end\\n\\t\\t\\t\\t\\t\\tlocal caminho = a .. \\\".\\\" .. prop\\n\\t\\t\\t\\t\\t\\treturn { tipo = \\\"atrib\\\", op = op, caminho = caminho, valor = valorFinal(v), expr = v, norm = caminho .. \\\" \\\" .. op }\\n\\t\\t\\t\\t\\telseif t3.v == \\\"(\\\" then table.remove(partes) -- tira o nome do metodo do caminho\\n\\t\\t\\t\\t\\t\\treturn metodoEm(partes, \\\".\\\", j - 1)\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\tend\\n\\n\\t\\t-- YASHSCRIPT: atribuição composta em nome simples (moedas += 1)\\n\\t\\tif nt0 and nt0.t == \\\"simbolo\\\" and (nt0.v == \\\"+=\\\" or nt0.v == \\\"-=\\\") then\\n\\t\\t\\tlocal op = nt0.v\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal v = parseValor(true)\\n\\t\\t\\tif not v then erroJ(\\\"valor esperado após '\\\" .. a .. \\\" \\\" .. op .. \\\"'\\\") end\\n\\t\\t\\treturn { tipo = \\\"atrib\\\", op = op, caminho = a, valor = valorFinal(v), expr = v, norm = a .. \\\" \\\" .. op }\\n\\t\\tend\\n\\n\\t\\tif funcoesDeclaradas[a] and nt0 and nt0.t == \\\"simbolo\\\" and nt0.v == \\\"(\\\" then\\n\\t\\t\\tlocal indices = { idx - 1 }\\n\\t\\t\\twhile not fimLinha() do EMPILHAR(indices, idx); avancar() end\\n\\t\\t\\tlocal expr = analisarExpressao(indices)\\n\\t\\t\\tif not expr or expr.k ~= \\\"chamada\\\" then erroJ(\\\"chamada de função inválida\\\") end\\n\\t\\t\\treturn { tipo = \\\"expressao\\\", expr = expr, norm = a .. \\\"()\\\" }\\n\\t\\tend\\n\\n\\t\\tif nt0 and nt0.t == \\\"simbolo\\\" and nt0.v == \\\"=\\\" and variavelDeclarada(a) then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal v = parseValor(true)\\n\\t\\t\\tif not v then erroJ(\\\"valor esperado após '\\\" .. a .. \\\" ='\\\") end\\n\\t\\t\\treturn { tipo = \\\"atrib\\\", op = \\\"=\\\", caminho = a, valor = valorFinal(v), expr = v, norm = a .. \\\" =\\\" }\\n\\t\\tend\\n\\n\\t\\t-- YASHSCRIPT: print(...) como saida simples de teste\\n\\t\\tif a == \\\"print\\\" then\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\"(\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\")\\\" then\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\twhile true do\\n\\t\\t\\t\\t\\t\\tlocal arg = parseValor(true, \\\")\\\")\\n\\t\\t\\t\\t\\t\\tif not arg then erroJ(\\\"expressão esperada em print\\\") end\\n\\t\\t\\t\\t\\t\\tEMPILHAR(args, arg)\\n\\t\\t\\t\\t\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\",\\\" then avancar() else break end\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\telse\\n\\t\\t\\t\\tlocal arg = parseValor(true)\\n\\t\\t\\t\\tif not arg then erroJ(\\\"expressão esperada em print\\\") end\\n\\t\\t\\t\\tEMPILHAR(args, arg)\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"log\\\", args = args, forma = \\\"print\\\", norm = \\\"print\\\" }\\n\\t\\tend\\n\\n\\t\\t-- tupla numérica entre parênteses: (x, y, z)\\n\\t\\tlocal function lerTupla()\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\"(\\\")\\n\\t\\t\\tlocal nums = {}\\n\\t\\t\\twhile true do\\n\\t\\t\\t\\tlocal tk = at()\\n\\t\\t\\t\\tif tk and tk.t == \\\"simbolo\\\" and (tk.v == \\\"-\\\" or tk.v == \\\"+\\\")\\n\\t\\t\\t\\t\\tand toks[idx + 1] and toks[idx + 1].t == \\\"numero\\\" then\\n\\t\\t\\t\\t\\tlocal sinal = tk.v == \\\"-\\\" and -1 or 1\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\tEMPILHAR(nums, sinal * espera(\\\"numero\\\"))\\n\\t\\t\\t\\telseif tk and tk.t == \\\"numero\\\" then EMPILHAR(nums, tk.v); avancar()\\n\\t\\t\\t\\telseif tk and tk.t == \\\"simbolo\\\" and tk.v == \\\",\\\" then avancar()\\n\\t\\t\\t\\telse break end\\n\\t\\t\\tend\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\tif #nums == 0 then erroJ(\\\"tupla (x,y,z) esperada\\\") end\\n\\t\\t\\treturn nums\\n\\t\\tend\\n\\n\\t\\tif a == \\\"mostrar\\\" or a == \\\"esconder\\\" or a == \\\"alternar\\\" then\\n\\t\\t\\tlocal map = { mostrar = \\\"mostrar\\\", esconder = \\\"esconder\\\", alternar = \\\"alternar\\\" }\\n\\t\\t\\tlocal nt = at()\\n\\t\\t\\tif nt and nt.t == \\\"palavra\\\" and nt.v == \\\"texto\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal msg = espera(\\\"string\\\")\\n\\t\\t\\t\\treturn { tipo = \\\"log\\\", texto = msg, forma = \\\"mostrar\\\", norm = \\\"mostrar texto\\\" }\\n\\t\\t\\telseif nt and nt.t == \\\"palavra\\\" and nt.v == \\\"cena\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\t\\tlocal anim = parseAnimSufixo()\\n\\t\\t\\t\\treturn { tipo = \\\"cena\\\", acao = map[a], alvo = nome, anim = anim, norm = a .. \\\" cena \\\" .. nome }\\n\\t\\t\\telseif nt and nt.t == \\\"simbolo\\\" and nt.v == \\\"(\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\t\\tlocal anim = parseAnimSufixo()\\n\\t\\t\\t\\tlocal norm = a .. \\\"(\\\" .. nome .. \\\")\\\"\\n\\t\\t\\t\\t-- nome solto (com ou sem aspas) vira referência para o gerador\\n\\t\\t\\t\\treturn { tipo = \\\"visivel\\\", acao = map[a], alvo = nome, anim = anim,\\n\\t\\t\\t\\t\\texpr = { k = \\\"ident\\\", v = nome }, norm = norm }\\n\\t\\t\\telseif nt and (nt.t == \\\"palavra\\\" or nt.t == \\\"string\\\") then\\n\\t\\t\\t\\t-- `mostrar Cubo` / `mostrar \\\"Cubo\\\"`: nome solto, sem parenteses\\n\\t\\t\\t\\tlocal nome = nt.v\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal anim = parseAnimSufixo()\\n\\t\\t\\t\\treturn { tipo = \\\"visivel\\\", acao = map[a], alvo = nome, anim = anim,\\n\\t\\t\\t\\t\\texpr = { k = \\\"ident\\\", v = nome }, norm = a .. \\\" \\\" .. nome }\\n\\t\\t\\tend\\n\\t\\t\\terroJ(\\\"sintaxe de \\\" .. a .. \\\" inválida\\\")\\n\\t\\tend\\n\\n\\t\\tif a == \\\"mudar\\\" then\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"cena\\\")\\n\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\tlocal anim = parseAnimSufixo()\\n\\t\\t\\treturn { tipo = \\\"cena\\\", acao = \\\"mudar\\\", alvo = nome, anim = anim, norm = \\\"mudar cena \\\" .. nome }\\n\\t\\tend\\n\\n\\t\\t-- YASHSCRIPT: animar — tween de verdade (TweenService) sobre um alvo:\\n\\t\\t--   animar(\\\"Jogar\\\") posicao = (0, 100) + tamanho = (200, 50) + duracao = 0.5\\n\\t\\t--   animar(\\\"Painel\\\") fade in + duracao = 1          (efeito com parametros)\\n\\t\\t--   animar(\\\"Painel\\\") pulsar                          (efeito curto)\\n\\t\\t--   animar(\\\"Painel\\\") animacao = abrir                (animacao criada)\\n\\t\\t-- A forma legada `animar pulsar` (nome sozinho, nada depois) continua\\n\\t\\t-- valendo como atalho de `executar animacao pulsar`.\\n\\t\\tif a == \\\"animar\\\" then\\n\\t\\t\\tlocal nt = at()\\n\\t\\t\\tlocal alvo = nil\\n\\t\\t\\tlocal formaCurta = false\\n\\t\\t\\tif nt and nt.t == \\\"simbolo\\\" and nt.v == \\\"(\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\talvo = lerNomeCaminho()\\n\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\telseif nt and (nt.t == \\\"string\\\" or nt.t == \\\"palavra\\\") then\\n\\t\\t\\t\\talvo = lerNomeCaminho()\\n\\t\\t\\t\\t-- nome sozinho em forma curta so e legado se nada vier depois\\n\\t\\t\\t\\tif nt.t == \\\"palavra\\\" and fimLinha() then formaCurta = true end\\n\\t\\t\\tend\\n\\t\\t\\tif formaCurta then\\n\\t\\t\\t\\treturn { tipo = \\\"animacao\\\", nome = alvo, norm = \\\"executar animacao \\\" .. alvo }\\n\\t\\t\\tend\\n\\t\\t\\tif not alvo then\\n\\t\\t\\t\\terroJ(\\\"alvo esperado após 'animar' (ex: animar(\\\\\\\"Jogar\\\\\\\") fade in)\\\")\\n\\t\\t\\tend\\n\\t\\t\\tlocal valor = parseValor()\\n\\t\\t\\tif not valor then\\n\\t\\t\\t\\terroJ(\\\"efeito ou propriedade esperado após 'animar(\\\" .. alvo .. \\\")'\\\")\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"tween\\\", alvo = alvo, expr = exprCaminho(alvo),\\n\\t\\t\\t\\tvalor = valor, norm = \\\"animar \\\" .. alvo }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"executar\\\" or a == \\\"chamar\\\" then\\n\\t\\t\\tlocal k = at()\\n\\t\\t\\tif not k or k.t ~= \\\"palavra\\\" then erroJ(\\\"tipo (animacao/acao) esperado após '\\\" .. a .. \\\"'\\\") end\\n\\t\\t\\tif k.v == \\\"animacao\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\t\\treturn { tipo = \\\"animacao\\\", nome = nome, norm = \\\"executar animacao \\\" .. nome }\\n\\t\\t\\telseif k.v == \\\"acao\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\t\\treturn { tipo = \\\"acao\\\", nome = nome, norm = \\\"executar acao \\\" .. nome }\\n\\t\\t\\tend\\n\\t\\t\\terroJ(\\\"esperava 'animacao' ou 'acao' após '\\\" .. a .. \\\"'\\\")\\n\\t\\tend\\n\\n\\t\\tif a == \\\"destruir\\\" then\\n\\t\\t\\tlocal k = espera(\\\"palavra\\\")\\n\\t\\t\\tif k ~= \\\"objeto\\\" and k ~= \\\"elemento\\\" then erroJ(\\\"esperava 'objeto' ou 'elemento' após 'destruir'\\\") end\\n\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\treturn { tipo = \\\"destruir\\\", oq = k, alvo = nome, norm = \\\"destruir \\\" .. k .. \\\" \\\" .. nome }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"somar\\\" or a == \\\"subtrair\\\" then\\n\\t\\t\\tlocal de = lerCaminho()\\n\\t\\t\\tif a == \\\"somar\\\" then espera(\\\"palavra\\\", \\\"a\\\") else espera(\\\"palavra\\\", \\\"de\\\") end\\n\\t\\t\\tlocal para = lerCaminho()\\n\\t\\t\\treturn { tipo = \\\"soma\\\", op = a, de = de, para = para }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"se\\\" then\\n\\t\\t\\tlocal cond = parseCond()\\n\\t\\t\\tlocal corpo = parseComandos({ fim = true, senao = true })\\n\\t\\t\\tlocal alternativas, senao = parseRamosSenao()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\treturn { tipo = \\\"se\\\", cond = cond, corpo = corpo, alternativas = alternativas, senao = senao }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"para\\\" then\\n\\t\\t\\tif at() and at().t == \\\"palavra\\\" and at().v == \\\"cada\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal nomes = { esperaNome() }\\n\\t\\t\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\",\\\" then\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\tlocal segundo = esperaNome()\\n\\t\\t\\t\\t\\tif segundo == nomes[1] then erroJ(\\\"variáveis repetidas no laço 'para cada'\\\") end\\n\\t\\t\\t\\t\\tEMPILHAR(nomes, segundo)\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"em\\\")\\n\\t\\t\\t\\tlocal colecao = parseValor(true)\\n\\t\\t\\t\\tif not colecao then erroJ(\\\"coleção esperada após 'em'\\\") end\\n\\t\\t\\t\\tlocal corpo = parseCorpoLaco()\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\t\\treturn { tipo = \\\"para_cada\\\", nomes = nomes, iterador = #nomes == 2 and \\\"pairs\\\" or \\\"ipairs\\\",\\n\\t\\t\\t\\t\\tcolecao = colecao, corpo = corpo }\\n\\t\\t\\tend\\n\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"de\\\")\\n\\t\\t\\tlocal function lerExpressaoAte(cortadores)\\n\\t\\t\\t\\tlocal indices, parenteses, colchetes, chaves = {}, 0, 0, 0\\n\\t\\t\\t\\twhile at() and at().t ~= \\\"nova\\\" do\\n\\t\\t\\t\\t\\tlocal tk = at()\\n\\t\\t\\t\\t\\tif parenteses == 0 and colchetes == 0 and chaves == 0\\n\\t\\t\\t\\t\\t\\tand tk.t == \\\"palavra\\\" and cortadores[tk.v] then break end\\n\\t\\t\\t\\t\\tEMPILHAR(indices, idx)\\n\\t\\t\\t\\t\\tif tk.t == \\\"simbolo\\\" then\\n\\t\\t\\t\\t\\t\\tif tk.v == \\\"(\\\" then parenteses = parenteses + 1\\n\\t\\t\\t\\t\\t\\telseif tk.v == \\\")\\\" then parenteses = math.max(0, parenteses - 1)\\n\\t\\t\\t\\t\\t\\telseif tk.v == \\\"[\\\" then colchetes = colchetes + 1\\n\\t\\t\\t\\t\\t\\telseif tk.v == \\\"]\\\" then colchetes = math.max(0, colchetes - 1)\\n\\t\\t\\t\\t\\t\\telseif tk.v == \\\"{\\\" then chaves = chaves + 1\\n\\t\\t\\t\\t\\t\\telseif tk.v == \\\"}\\\" then chaves = math.max(0, chaves - 1) end\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tif #indices == 0 then erroJ(\\\"expressão esperada no laço 'para'\\\") end\\n\\t\\t\\t\\treturn classificarClausula(indices)\\n\\t\\t\\tend\\n\\t\\t\\tlocal inicio = lerExpressaoAte({ ate = true })\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"ate\\\")\\n\\t\\t\\tlocal limite = lerExpressaoAte({ passo = true })\\n\\t\\t\\tlocal passo = { k = \\\"num\\\", v = 1 }\\n\\t\\t\\tif at() and at().t == \\\"palavra\\\" and at().v == \\\"passo\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tpasso = parseValor(true)\\n\\t\\t\\t\\tif not passo then erroJ(\\\"expressão esperada após 'passo'\\\") end\\n\\t\\t\\tend\\n\\t\\t\\tlocal corpo = parseCorpoLaco()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\treturn { tipo = \\\"para\\\", nome = nome, inicio = inicio, limite = limite, passo = passo, corpo = corpo }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"enquanto\\\" then\\n\\t\\t\\tlocal cond = parseCond()\\n\\t\\t\\tlocal corpo = parseCorpoLaco()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\treturn { tipo = \\\"enquanto\\\", cond = cond, corpo = corpo }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"repita\\\" then\\n\\t\\t\\tprofundidadeLaco = profundidadeLaco + 1\\n\\t\\t\\tlocal corpo = parseComandos({ ate = true })\\n\\t\\t\\tprofundidadeLaco = profundidadeLaco - 1\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"ate\\\")\\n\\t\\t\\tlocal cond = parseCond()\\n\\t\\t\\treturn { tipo = \\\"repita\\\", corpo = corpo, cond = cond }\\n\\t\\tend\\n\\n\\t\\t-- comandos de jogo (mundo 3D/servidor)\\n\\t\\tif a == \\\"esperar\\\" or a == \\\"aguardar\\\" then\\n\\t\\t\\tlocal vt = at()\\n\\t\\t\\tif not vt or vt.t ~= \\\"numero\\\" then erroJ(\\\"segundos esperados após '\\\" .. a .. \\\"'\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"espera\\\", valor = vt.v, norm = \\\"esperar \\\" .. vt.v }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"causar\\\" then\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"dano\\\")\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\tlocal vtk = at()\\n\\t\\t\\tif not vtk or vtk.t ~= \\\"numero\\\" then erroJ(\\\"valor do dano esperado\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"dano\\\", alvo = alvo, valor = vtk.v, norm = \\\"causar dano \\\" .. alvo .. \\\" \\\" .. vtk.v }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"curar\\\" then\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\tlocal vtk = at()\\n\\t\\t\\tif not vtk or vtk.t ~= \\\"numero\\\" then erroJ(\\\"quantidade esperada\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"curar\\\", alvo = alvo, valor = vtk.v, norm = \\\"curar \\\" .. alvo .. \\\" \\\" .. vtk.v }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"matar\\\" then\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\treturn { tipo = \\\"matar\\\", alvo = alvo, norm = \\\"matar \\\" .. alvo }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"respawnar\\\" then\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\treturn { tipo = \\\"respawnar\\\", alvo = alvo, norm = \\\"respawnar \\\" .. alvo }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"teleportar\\\" then\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\tlocal nums = lerTupla()\\n\\t\\t\\treturn { tipo = \\\"teleportar\\\", alvo = alvo, pos = { t = \\\"par\\\", x = nums[1], y = nums[2], z = nums[3] or 0 }, norm = \\\"teleportar \\\" .. alvo .. \\\" (\\\" .. nums[1] .. \\\", \\\" .. nums[2] .. \\\", \\\" .. (nums[3] or 0) .. \\\")\\\" }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"mover\\\" then\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"para\\\")\\n\\t\\t\\tlocal nums = lerTupla()\\n\\t\\t\\tlocal velocidade = 20\\n\\t\\t\\tif not fimLinha() then\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"velocidade\\\")\\n\\t\\t\\t\\tlocal vt2 = at()\\n\\t\\t\\t\\tif not vt2 or vt2.t ~= \\\"numero\\\" then erroJ(\\\"velocidade esperada\\\") end\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tvelocidade = vt2.v\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"mover\\\", alvo = alvo, para = { t = \\\"par\\\", x = nums[1], y = nums[2], z = nums[3] or 0 }, velocidade = velocidade, norm = \\\"mover \\\" .. alvo .. \\\" para (\\\" .. nums[1] .. \\\", \\\" .. nums[2] .. \\\", \\\" .. (nums[3] or 0) .. \\\") velocidade \\\" .. velocidade }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"rotacionar\\\" then\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"para\\\")\\n\\t\\t\\tlocal nums = lerTupla()\\n\\t\\t\\tlocal duracao = 0.3\\n\\t\\t\\tif not fimLinha() then\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"duracao\\\")\\n\\t\\t\\t\\tlocal dt2 = at()\\n\\t\\t\\t\\tif not dt2 or dt2.t ~= \\\"numero\\\" then erroJ(\\\"duracao esperada\\\") end\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tduracao = dt2.v\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"rotacionar\\\", alvo = alvo, para = { t = \\\"par\\\", x = nums[1], y = nums[2], z = nums[3] or 0 }, duracao = duracao, norm = \\\"rotacionar \\\" .. alvo .. \\\" para (\\\" .. nums[1] .. \\\", \\\" .. nums[2] .. \\\", \\\" .. (nums[3] or 0) .. \\\") duracao \\\" .. duracao }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"sortear\\\" then\\n\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"entre\\\")\\n\\t\\t\\tlocal mn = at()\\n\\t\\t\\tif not mn or mn.t ~= \\\"numero\\\" then erroJ(\\\"primeiro número esperado\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"e\\\")\\n\\t\\t\\tlocal mx = at()\\n\\t\\t\\tif not mx or mx.t ~= \\\"numero\\\" then erroJ(\\\"segundo número esperado\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"sortear\\\", nome = nome, min = mn.v, max = mx.v, norm = \\\"sortear \\\" .. nome .. \\\" entre \\\" .. mn.v .. \\\" e \\\" .. mx.v }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"tocar\\\" then\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"som\\\")\\n\\t\\t\\tlocal id = at()\\n\\t\\t\\tif not id or (id.t ~= \\\"numero\\\" and id.t ~= \\\"string\\\") then erroJ(\\\"id do som esperado\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\treturn { tipo = \\\"som\\\", id = tostring(id.v), norm = \\\"tocar som \\\" .. id.v }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"explodir\\\" then\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\tlocal raio, dano = 8, 50\\n\\t\\t\\tif not fimLinha() then\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"raio\\\")\\n\\t\\t\\t\\tlocal rt3 = at()\\n\\t\\t\\t\\tif not rt3 or rt3.t ~= \\\"numero\\\" then erroJ(\\\"raio esperado\\\") end\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\traio = rt3.v\\n\\t\\t\\t\\tif not fimLinha() then\\n\\t\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"dano\\\")\\n\\t\\t\\t\\t\\tlocal dt3 = at()\\n\\t\\t\\t\\t\\tif not dt3 or dt3.t ~= \\\"numero\\\" then erroJ(\\\"dano esperado\\\") end\\n\\t\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\t\\tdano = dt3.v\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"explodir\\\", alvo = alvo, raio = raio, dano = dano, norm = \\\"explodir \\\" .. alvo .. \\\" raio \\\" .. raio .. \\\" dano \\\" .. dano }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"seguir\\\" then\\n\\t\\t\\tlocal quem = esperaNome()\\n\\t\\t\\tlocal de = at()\\n\\t\\t\\tif de and de.t == \\\"palavra\\\" and de.v == \\\"o\\\" then avancar() end\\n\\t\\t\\tlocal alvo = esperaNome()\\n\\t\\t\\treturn { tipo = \\\"seguir\\\", quem = quem, alvo = alvo, norm = \\\"seguir \\\" .. quem .. \\\" o \\\" .. alvo }\\n\\t\\tend\\n\\n\\t\\tif a == \\\"clonar\\\" then\\n\\t\\t\\tlocal origem = lerNomeCaminho()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"para\\\")\\n\\t\\t\\tlocal pai = lerNomeCaminho()\\n\\t\\t\\tlocal nome = nil\\n\\t\\t\\tif at() and at().t == \\\"palavra\\\" and at().v == \\\"como\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tnome = esperaNome()\\n\\t\\t\\tend\\n\\t\\t\\treturn { tipo = \\\"clonar\\\", origem = origem, pai = pai, nome = nome,\\n\\t\\t\\t\\tnorm = \\\"clonar \\\" .. origem .. \\\" para \\\" .. pai }\\n\\t\\tend\\n\\n\\t\\t-- propriedade genérica aplicada ao elemento do evento: nome = valor\\n\\t\\tlocal eq = at()\\n\\t\\tif eq and eq.t == \\\"simbolo\\\" and eq.v == \\\"=\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal v = parseValor(true)\\n\\t\\t\\tif not v then erroJ(\\\"valor esperado após '\\\" .. a .. \\\" ='\\\") end\\n\\t\\t\\treturn { tipo = \\\"prop\\\", propNome = a, props = { [a] = valorFinal(v) },\\n\\t\\t\\t\\texprs = { [a] = v }, expr = v }\\n\\t\\tend\\n\\n\\t\\treturn erroJ(\\\"comando desconhecido '\\\" .. a .. \\\"'\\\")\\n\\tend\\n\\n\\tlocal function parseBlocoHud()\\n\\t\\tlocal campo = nil\\n\\t\\tpularNovas()\\n\\t\\twhile true do\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t == nil then erroJ(\\\"esperava 'fim' no hud\\\") end\\n\\t\\t\\tif t.t == \\\"nova\\\" then avancar(); pularNovas()\\n\\t\\t\\telseif t.t == \\\"palavra\\\" and t.v == \\\"fim\\\" then avancar(); break\\n\\t\\t\\telseif t.t == \\\"palavra\\\" and t.v == \\\"mostrar\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tcampo = lerCaminho()\\n\\t\\t\\telse\\n\\t\\t\\t\\terroJ(\\\"em hud use: mostrar <objeto>.<atributo>\\\")\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn campo\\n\\tend\\n\\n\\tlocal function parseBlocoAnimacao()\\n\\t\\tlocal lista = {}\\n\\t\\tpularNovas()\\n\\t\\twhile true do\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t == nil then erroJ(\\\"esperava 'fim' na animação\\\") end\\n\\t\\t\\tif t.t == \\\"nova\\\" then avancar(); pularNovas()\\n\\t\\t\\telseif t.t == \\\"palavra\\\" and t.v == \\\"fim\\\" then avancar(); break\\n\\t\\t\\telse\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"animacao\\\")\\n\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\"=\\\")\\n\\t\\t\\t\\tlocal v = parseValor()\\n\\t\\t\\t\\tif not v then erroJ(\\\"valor de animação esperado\\\") end\\n\\t\\t\\t\\tEMPILHAR(lista, v)\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn lista\\n\\tend\\n\\n\\t-- comando de proibição\\n\\tlocal function parseProibir()\\n\\t\\tlocal evt = espera(\\\"palavra\\\")\\n\\t\\tif evt ~= \\\"clicar\\\" and evt ~= \\\"mouse_em\\\" and evt ~= \\\"mouse_sair\\\" then\\n\\t\\t\\terroJ(\\\"tipo de evento inválido em proibir: '\\\" .. evt .. \\\"'\\\")\\n\\t\\tend\\n\\t\\tlocal alvo = esperaNome()\\n\\t\\tespera(\\\"palavra\\\", \\\"de\\\")\\n\\n\\t\\tlocal comandos = {}\\n\\t\\tlocal atual = {}\\n\\t\\twhile not fimLinha() do\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t.t == \\\"palavra\\\" and (t.v == \\\"se\\\" or t.v == \\\"somente\\\") then break end\\n\\t\\t\\tif t.t == \\\"simbolo\\\" and t.v == \\\"+\\\" then\\n\\t\\t\\t\\tif #atual > 0 then EMPILHAR(comandos, atual) end\\n\\t\\t\\t\\tatual = {}\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\telse\\n\\t\\t\\t\\tEMPILHAR(atual, idx)\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tif #atual > 0 then EMPILHAR(comandos, atual) end\\n\\n\\t\\tlocal normComandos = {}\\n\\t\\tfor _, cl in ipairs(comandos) do\\n\\t\\t\\tlocal txt = textoTrecho(cl[1], cl[#cl])\\n\\t\\t\\ttxt = string.gsub(txt, \\\"%s+\\\", \\\"\\\")\\n\\t\\t\\tEMPILHAR(normComandos, txt)\\n\\t\\tend\\n\\n\\t\\tlocal cond = nil\\n\\t\\tlocal somente = nil\\n\\t\\tif not fimLinha() then\\n\\t\\t\\tlocal t = at()\\n\\t\\t\\tif t and t.t == \\\"palavra\\\" and t.v == \\\"se\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tlocal oq = espera(\\\"palavra\\\")\\n\\t\\t\\t\\tlocal el = nil\\n\\t\\t\\t\\tif oq == \\\"visivel\\\" or oq == \\\"oculto\\\" then\\n\\t\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\"(\\\")\\n\\t\\t\\t\\t\\tel = espera(\\\"string\\\")\\n\\t\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\t\\t\\tcond = { tipo = \\\"estado\\\", oq = oq, el = el }\\n\\t\\t\\t\\tend\\n\\t\\t\\telseif t and t.t == \\\"palavra\\\" and t.v == \\\"somente\\\" then\\n\\t\\t\\t\\tavancar()\\n\\t\\t\\t\\tsomente = espera(\\\"string\\\")\\n\\t\\t\\telse\\n\\t\\t\\t\\terroJ(\\\"sintaxe de proibir inválida\\\")\\n\\t\\t\\tend\\n\\t\\tend\\n\\n\\t\\tEMPILHAR(config.proibicoes, {\\n\\t\\t\\tevt = evt,\\n\\t\\t\\talvo = alvo,\\n\\t\\t\\tcomandos = normComandos,\\n\\t\\t\\tcond = cond,\\n\\t\\t\\tsomente = somente,\\n\\t\\t})\\n\\tend\\n\\n\\t-- laço principal\\n\\tpularNovas()\\n\\twhile true do\\n\\t\\tlocal t = at()\\n\\t\\tif t == nil then break end\\n\\t\\tif t.t == \\\"nova\\\" then avancar(); pularNovas()\\n\\t\\telseif t.t ~= \\\"palavra\\\" then erroJ(\\\"instrução inesperada\\\")\\n\\t\\telse\\n\\t\\tlocal a = t.v\\n\\t\\tif a == \\\"YASHSCRIPT\\\" then\\n\\t\\t\\t-- cabeçalho: identifica o arquivo como YashScript.\\n\\t\\t\\tavancar()\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\":\\\")\\n\\t\\t\\tconfig.marcador = \\\"YASHSCRIPT:\\\"\\n\\t\\t\\t-- O contexto NUNCA vem do texto: ele vem da classe do script no\\n\\t\\t\\t-- Studio (Script/LocalScript/ModuleScript). Por isso o cabecalho nao\\n\\t\\t\\t-- aceita mais `servidor`/`cliente` -- esse campo nunca foi lido.\\n\\t\\telseif a == \\\"incluir\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal arq = espera(\\\"string\\\")\\n\\t\\t\\tEMPILHAR(config.incluir, arq)\\n\\t\\telseif a == \\\"usar\\\" then\\n\\t\\t\\t-- YASHSCRIPT: usar \\\"Nome\\\" = <caminho da árvore | valor>\\n\\t\\t\\t-- Declara um nome do desenvolvedor. O gerador de Luau transforma em\\n\\t\\t\\t-- `local Nome = <expressão resolvida>` no ponto em que aparece.\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal nome = esperaNome()\\n\\t\\t\\tespera(\\\"simbolo\\\", \\\"=\\\")\\n\\t\\t\\tlocal v = parseValor(true)\\n\\t\\t\\tif not v then erroJ(\\\"valor esperado em 'usar \\\" .. nome .. \\\" ='\\\") end\\n\\t\\t\\tEMPILHAR(config.aliases, { nome = nome, expr = v, linha = t.l })\\n\\t\\telseif a == \\\"criar\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal tipo = espera(\\\"palavra\\\")\\n\\t\\t\\tlocal nome = esperaNome()\\n\\n\\t\\t\\tlocal elementos_tipos = {\\n\\t\\t\\t\\tpainel = true, texto = true, botao = true, campo = true,\\n\\t\\t\\t\\timagem = true, elemento = true,\\n\\t\\t\\t}\\n\\n\\t\\t\\tlocal formas_tipos = {\\n\\t\\t\\t\\tbloco = true, esfera = true, cilindro = true, cunha = true,\\n\\t\\t\\t\\tparalelepipedo = true, plataforma = true,\\n\\t\\t\\t}\\n\\n\\t\\t\\tif tipo == \\\"cena\\\" then\\n\\t\\t\\t\\tconfig.cenas[nome] = parseBlocoProps()\\n\\t\\t\\telseif tipo == \\\"estilo\\\" then\\n\\t\\t\\t\\tconfig.estilos[nome] = parseBlocoProps()\\n\\t\\t\\telseif elementos_tipos[tipo] then\\n\\t\\t\\t\\tconfig.elementos[nome] = { tipo = tipo, props = parseBlocoProps() }\\n\\t\\t\\t\\tEMPILHAR(config.ordem_elementos, nome)\\n\\t\\t\\telseif formas_tipos[tipo] then\\n\\t\\t\\t\\tconfig.formas[nome] = { tipo = tipo, props = parseBlocoProps() }\\n\\t\\t\\telseif tipo == \\\"objeto\\\" then\\n\\t\\t\\t\\tconfig.objetos[nome] = parseBlocoProps()\\n\\t\\t\\telseif tipo == \\\"funcao\\\" then\\n\\t\\t\\t\\tlocal parametros = {}\\n\\t\\t\\t\\tlocal vistos = {}\\n\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\"(\\\")\\n\\t\\t\\t\\tif not (at() and at().t == \\\"simbolo\\\" and at().v == \\\")\\\") then\\n\\t\\t\\t\\t\\twhile true do\\n\\t\\t\\t\\t\\t\\tlocal parametro = esperaNome()\\n\\t\\t\\t\\t\\t\\tif vistos[parametro] then erroJ(\\\"parâmetro repetido: \\\" .. parametro) end\\n\\t\\t\\t\\t\\t\\tvistos[parametro] = true\\n\\t\\t\\t\\t\\t\\tEMPILHAR(parametros, parametro)\\n\\t\\t\\t\\t\\t\\tif at() and at().t == \\\"simbolo\\\" and at().v == \\\",\\\" then avancar() else break end\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tespera(\\\"simbolo\\\", \\\")\\\")\\n\\t\\t\\t\\tif config.funcoes[nome] then erroJ(\\\"função já declarada: '\\\" .. nome .. \\\"'\\\") end\\n\\t\\t\\t\\tlocal escopoFuncao = {}\\n\\t\\t\\t\\tfor _, parametro in ipairs(parametros) do escopoFuncao[parametro] = true end\\n\\t\\t\\t\\ttable.insert(escoposVariaveis, escopoFuncao)\\n\\t\\t\\t\\tlocal corpo = parseComandos({ fim = true })\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\t\\ttable.remove(escoposVariaveis)\\n\\t\\t\\t\\tconfig.funcoes[nome] = { parametros = parametros, corpo = corpo }\\n\\t\\t\\telseif tipo == \\\"acao\\\" then\\n\\t\\t\\t\\tlocal escopoAcao = {}\\n\\t\\t\\t\\ttable.insert(escoposVariaveis, escopoAcao)\\n\\t\\t\\t\\tlocal corpo = parseComandos({ fim = true })\\n\\t\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\t\\ttable.remove(escoposVariaveis)\\n\\t\\t\\t\\tconfig.acoes[nome] = corpo\\n\\t\\t\\telseif tipo == \\\"animacao\\\" then\\n\\t\\t\\t\\tconfig.animacoes[nome] = { lista = parseBlocoAnimacao() }\\n\\t\\t\\telseif tipo == \\\"hud\\\" then\\n\\t\\t\\t\\tconfig.huds[nome] = { campo = parseBlocoHud() }\\n\\t\\t\\telse\\n\\t\\t\\t\\terroJ(\\\"tipo desconhecido no 'criar': '\\\" .. tipo .. \\\"'\\\")\\n\\t\\t\\tend\\n\\t\\telseif a == \\\"site\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tconfig.site = parseBlocoProps()\\n\\t\\telseif a == \\\"mundo\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tconfig.mundo = parseBlocoProps()\\n\\t\\telseif a == \\\"a\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"cada\\\")\\n\\t\\t\\tlocal vt = at()\\n\\t\\t\\tif not vt or vt.t ~= \\\"numero\\\" then erroJ(\\\"segundos esperados após 'a cada'\\\") end\\n\\t\\t\\tavancar()\\n\\t\\t\\ttable.insert(escoposVariaveis, {})\\n\\t\\t\\tlocal corpo = parseComandos({ fim = true })\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\ttable.remove(escoposVariaveis)\\n\\t\\t\\tEMPILHAR(config.timers, { intervalo = vt.v, corpo = corpo })\\n\\t\\telseif a == \\\"quando\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal primeira = espera(\\\"palavra\\\")\\n\\t\\t\\t-- \\\"quando tocar 'moeda'\\\"        -> forma legada, sem sujeito\\n\\t\\t\\t-- \\\"quando jogador tocar moeda\\\" -> o primeiro nome e o SUJEITO\\n\\t\\t\\tlocal sujeito = nil\\n\\t\\t\\tlocal evt = primeira\\n\\t\\t\\tif not EVENTOS_CONHECIDOS[primeira] then\\n\\t\\t\\t\\tsujeito = primeira\\n\\t\\t\\t\\tevt = espera(\\\"palavra\\\")\\n\\t\\t\\tend\\n\\t\\t\\tif not EVENTOS_CONHECIDOS[evt] then\\n\\t\\t\\t\\terroJ(\\\"evento desconhecido: '\\\" .. evt .. \\\"'\\\")\\n\\t\\t\\tend\\n\\t\\t\\tlocal alvo = nil\\n\\t\\t\\tif EMISSOR_PROPRIO[evt] then\\n\\t\\t\\t\\t-- \\\"quando Botao clicar\\\": o sujeito ja e o alvo\\n\\t\\t\\t\\tif sujeito then\\n\\t\\t\\t\\t\\talvo = sujeito\\n\\t\\t\\t\\t\\tsujeito = nil\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\talvo = esperaNome()\\n\\t\\t\\t\\tend\\n\\t\\t\\telseif evt == \\\"tocar\\\" or evt == \\\"encostar\\\" then\\n\\t\\t\\t\\t-- \\\"quando tocar Cubo\\\" ou \\\"quando Cubo tocar Cubo\\\"\\n\\t\\t\\t\\talvo = esperaNome()\\n\\t\\t\\tend\\n\\t\\t\\tlocal localEvento = evt ~= \\\"iniciar\\\" and evt ~= \\\"carregar\\\"\\n\\t\\t\\tif localEvento then table.insert(escoposVariaveis, {}) end\\n\\t\\t\\tlocal corpo = parseComandos({ fim = true })\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\tif localEvento then table.remove(escoposVariaveis) end\\n\\t\\t\\tEMPILHAR(config.eventos, { tipo = evt, alvo = alvo, sujeito = sujeito, corpo = corpo })\\n\\t\\telseif a == \\\"se\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal cond = parseCond()\\n\\t\\t\\tlocal corpo = parseComandos({ fim = true, senao = true })\\n\\t\\t\\tlocal alternativas, senao = parseRamosSenao()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\tEMPILHAR(config.continuos, { cond = cond, corpo = corpo, alternativas = alternativas, senao = senao })\\n\\t\\telseif a == \\\"enquanto\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tlocal cond = parseCond()\\n\\t\\t\\tlocal corpo = parseCorpoLaco()\\n\\t\\t\\tespera(\\\"palavra\\\", \\\"fim\\\")\\n\\t\\t\\tEMPILHAR(config.loops, { cond = cond, corpo = corpo })\\n\\t\\telseif a == \\\"proibir\\\" then\\n\\t\\t\\tavancar()\\n\\t\\t\\tparseProibir()\\n\\t\\telse\\n\\t\\t\\t-- comando simples em nivel superior: print(...), mostrar Cubo,\\n\\t\\t\\t-- Botao.texto = 1, Cubo.destruir()\\n\\t\\t\\tlocal marca = idx\\n\\t\\t\\tlocal okCmd, cmd = pcall(parseComando)\\n\\t\\t\\tif okCmd and type(cmd) == \\\"table\\\" and cmd.tipo then\\n\\t\\t\\t\\tEMPILHAR(config.comandos, cmd)\\n\\t\\t\\telse\\n\\t\\t\\t\\tidx = marca\\n\\t\\t\\t\\terroJ(\\\"instrução de nível superior desconhecida: '\\\" .. a .. \\\"'\\\")\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tend\\n\\tend\\n\\n\\treturn config\\nend\\n\\n-----------------------------------------------------------------------\\n-- EXPANSÃO DE \\\"incluir\\\"\\n-----------------------------------------------------------------------\\n\\nlocal function expandirIncluir(fonte, arquivos, pilha)\\n\\tpilha = pilha or {}\\n\\tlocal saida = {}\\n\\tfor linha in string.gmatch(fonte .. \\\"\\\\n\\\", \\\"(.-)\\\\n\\\") do\\n\\t\\tlocal nome = string.match(linha, \\\"^%s*incluir%s+[\\\\\\\"']([^\\\\\\\"']+)[\\\\\\\"']\\\")\\n\\t\\tif nome then\\n\\t\\t\\tif pilha[nome] then\\n\\t\\t\\t\\terror({ erro = \\\"inclusão circular de '\\\" .. nome .. \\\"'\\\", linha = 0 }, 0)\\n\\t\\t\\tend\\n\\t\\t\\tlocal conteudo = arquivos and arquivos[nome]\\n\\t\\t\\tif conteudo then\\n\\t\\t\\t\\tpilha[nome] = true\\n\\t\\t\\t\\tlocal exp = expandirIncluir(conteudo, arquivos, pilha)\\n\\t\\t\\t\\tpilha[nome] = nil\\n\\t\\t\\t\\tEMPILHAR(saida, exp)\\n\\t\\t\\telse\\n\\t\\t\\t\\t-- mantém a linha original; o consumidor (plugin/host) decide o que fazer\\n\\t\\t\\t\\tEMPILHAR(saida, linha)\\n\\t\\t\\tend\\n\\t\\telse\\n\\t\\t\\tEMPILHAR(saida, linha)\\n\\t\\tend\\n\\tend\\n\\treturn table.concat(saida, \\\"\\\\n\\\")\\nend\\n\\n-----------------------------------------------------------------------\\n-- API PÚBLICA\\n-----------------------------------------------------------------------\\n\\nfunction Compilador.Compilar(fonte, arquivos)\\n\\tarquivos = arquivos or {}\\n\\tfonte = string.gsub(fonte or \\\"\\\", \\\"\\\\r\\\\n\\\", \\\"\\\\n\\\")\\n\\tlocal ok, ret = pcall(function()\\n\\t\\tlocal expandida = expandirIncluir(fonte, arquivos, {})\\n\\t\\tlocal toks = tokenizar(expandida)\\n\\t\\tif #toks == 0 then return novaConfig() end\\n\\t\\treturn analisar(expandida, toks)\\n\\tend)\\n\\tif ok then\\n\\t\\treturn true, ret\\n\\tend\\n\\tif type(ret) ~= \\\"table\\\" then\\n\\t\\treturn false, { erro = \\\"[interno] \\\" .. tostring(ret), linha = 0 }\\n\\tend\\n\\treturn false, { erro = ret.erro or \\\"erro desconhecido\\\", linha = ret.linha or 0 }\\nend\\n\\n-----------------------------------------------------------------------\\n-- SERIALIZAÇÃO (LEGADA — arquitetura _YashConfig)\\n--   Mantida apenas para compatibilidade com o runtime legado e com scripts já\\n--   gravados. O caminho novo NÃO usa isto: o gerador de Luau é gerador.lua.\\n-----------------------------------------------------------------------\\n\\nlocal RESERVADAS = {\\n\\t[\\\"and\\\"] = true, [\\\"break\\\"] = true, [\\\"continue\\\"] = true, [\\\"do\\\"] = true,\\n\\t[\\\"else\\\"] = true, [\\\"elseif\\\"] = true, [\\\"end\\\"] = true, [\\\"false\\\"] = true,\\n\\t[\\\"for\\\"] = true, [\\\"function\\\"] = true, [\\\"goto\\\"] = true, [\\\"if\\\"] = true,\\n\\t[\\\"in\\\"] = true, [\\\"local\\\"] = true, [\\\"nil\\\"] = true, [\\\"not\\\"] = true,\\n\\t[\\\"or\\\"] = true, [\\\"repeat\\\"] = true, [\\\"return\\\"] = true, [\\\"then\\\"] = true,\\n\\t[\\\"true\\\"] = true, [\\\"until\\\"] = true, [\\\"while\\\"] = true,\\n}\\n\\n-- Escape de texto em estilo Luau, de forma canonica e independente do host.\\n-- Nao usamos string.format(\\\"%q\\\"): a saida muda entre Luau e Lua 5.3 e pode\\n-- gerar codigo invalido (ex.: \\\\n virava barra + quebra de linha real).\\nlocal function escaparTexto(s)\\n\\ts = tostring(s)\\n\\ts = s:gsub(\\\"\\\\\\\\\\\", \\\"\\\\\\\\\\\\\\\\\\\")\\n\\ts = s:gsub(\\\"\\\\\\\"\\\", \\\"\\\\\\\\\\\\\\\"\\\")\\n\\ts = s:gsub(\\\"\\\\n\\\", \\\"\\\\\\\\n\\\")\\n\\ts = s:gsub(\\\"\\\\r\\\", \\\"\\\\\\\\r\\\")\\n\\ts = s:gsub(\\\"\\\\t\\\", \\\"\\\\\\\\t\\\")\\n\\ts = s:gsub(\\\"[%z\\\\1-\\\\31\\\\127]\\\", function(c)\\n\\t\\treturn string.format(\\\"\\\\\\\\%03d\\\", string.byte(c))\\n\\tend)\\n\\treturn \\\"\\\\\\\"\\\" .. s .. \\\"\\\\\\\"\\\"\\nend\\n\\nlocal function chaveValida(k)\\n\\treturn type(k) == \\\"string\\\"\\n\\t\\tand string.match(k, \\\"^[%a_][%w_]*$\\\") ~= nil\\n\\t\\tand not RESERVADAS[k]\\nend\\n\\nlocal function chaveLua(k)\\n\\tif chaveValida(k) then return k end\\n\\tif type(k) == \\\"string\\\" then return escaparTexto(k) end\\n\\treturn tostring(k)\\nend\\n\\nlocal function numeroLua(v)\\n\\tif type(v) ~= \\\"number\\\" then return \\\"0\\\" end\\n\\tif v ~= v or v == math.huge or v == -math.huge then return \\\"0\\\" end\\n\\tif v == math.floor(v) and math.abs(v) < 1e15 then\\n\\t\\treturn string.format(\\\"%d\\\", v)\\n\\tend\\n\\t-- Menor representacao decimal que volta EXATAMENTE ao mesmo numero.\\n\\t-- (%.6f truncava: 0.7142857 virava 0.714286 e 1e-7 virava 0.)\\n\\tlocal s = string.format(\\\"%.15g\\\", v)\\n\\tif tonumber(s) ~= v then s = string.format(\\\"%.17g\\\", v) end\\n\\t-- Luau aceita notacao cientifica; um flutuante inteiro precisa de ponto\\n\\tif not s:find(\\\"[%.eE]\\\") then s = s .. \\\".0\\\" end\\n\\treturn s\\nend\\n\\nlocal function valorLua(v, profundidade)\\n\\tlocal tabs = string.rep(\\\"\\\\t\\\", profundidade or 0)\\n\\tif type(v) == \\\"number\\\" then return numeroLua(v) end\\n\\tif type(v) == \\\"boolean\\\" then return tostring(v) end\\n\\tif type(v) == \\\"string\\\" then\\n\\t\\treturn escaparTexto(v)\\n\\tend\\n\\tif type(v) == \\\"table\\\" then\\n\\t\\tif v.t == \\\"cor\\\" then\\n\\t\\t\\treturn \\\"cor(\\\" .. numeroLua(v.r) .. \\\", \\\" .. numeroLua(v.g) .. \\\", \\\" .. numeroLua(v.b) .. \\\")\\\"\\n\\t\\tend\\n\\t\\tif v.t == \\\"par\\\" then\\n\\t\\t\\tif v.z ~= nil then\\n\\t\\t\\t\\treturn \\\"par(\\\" .. numeroLua(v.x) .. \\\", \\\" .. numeroLua(v.y) .. \\\", \\\" .. numeroLua(v.z) .. \\\")\\\"\\n\\t\\t\\tend\\n\\t\\t\\treturn \\\"par(\\\" .. numeroLua(v.x) .. \\\", \\\" .. numeroLua(v.y) .. \\\")\\\"\\n\\t\\tend\\n\\t\\t-- array simples?\\n\\t\\tlocal ehArray = true\\n\\t\\tfor k in pairs(v) do\\n\\t\\t\\tif type(k) ~= \\\"number\\\" then ehArray = false; break end\\n\\t\\tend\\n\\t\\tif ehArray and #v > 0 then\\n\\t\\t\\tlocal itens = {}\\n\\t\\t\\tfor i = 1, #v do\\n\\t\\t\\t\\tEMPILHAR(itens, valorLua(v[i], profundidade + 1))\\n\\t\\t\\tend\\n\\t\\t\\treturn \\\"{\\\" .. table.concat(itens, \\\", \\\") .. \\\"}\\\"\\n\\t\\tend\\n\\t\\t-- mapa ordenado por chave\\n\\t\\tlocal chaves = {}\\n\\t\\tfor k in pairs(v) do EMPILHAR(chaves, k) end\\n\\t\\ttable.sort(chaves, function(a, b)\\n\\t\\t\\treturn tostring(a) < tostring(b)\\n\\t\\tend)\\n\\t\\tlocal itens = {}\\n\\t\\tfor _, k in ipairs(chaves) do\\n\\t\\t\\tlocal chv = chaveLua(k)\\n\\t\\t\\tif chaveValida(k) then\\n\\t\\t\\t\\tEMPILHAR(itens, chv .. \\\" = \\\" .. valorLua(v[k], profundidade + 1))\\n\\t\\t\\telse\\n\\t\\t\\t\\tEMPILHAR(itens, \\\"[\\\" .. chv .. \\\"] = \\\" .. valorLua(v[k], profundidade + 1))\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn \\\"{\\\\n\\\" .. tabs .. \\\"\\\\t\\\" .. table.concat(itens, \\\",\\\\n\\\" .. tabs .. \\\"\\\\t\\\") .. \\\"\\\\n\\\" .. tabs .. \\\"}\\\"\\n\\tend\\n\\treturn \\\"nil\\\"\\nend\\n\\nfunction Compilador.Serializar(config)\\n\\treturn \\\"return \\\" .. valorLua(config, 0)\\nend\\n\\n-----------------------------------------------------------------------\\n-- DESCOMPILAÇÃO (LEGADA — config -> código .yash)\\n--   Só o caminho legado usa. O plugin agora guarda a fonte YashScript no\\n--   atributo \\\"YashScript\\\" do script e NÃO precisa ler o Source de volta.\\n-----------------------------------------------------------------------\\n\\nlocal function textoValor(v)\\n\\tif type(v) == \\\"number\\\" then return tostring(v) end\\n\\tif type(v) == \\\"boolean\\\" then return v and \\\"verdadeiro\\\" or \\\"falso\\\" end\\n\\tif type(v) == \\\"string\\\" then return escaparTexto(v) end\\n\\tif type(v) == \\\"table\\\" then\\n\\t\\tif v.t == \\\"cor\\\" then\\n\\t\\t\\treturn string.format(\\\"rgb(%d,%d,%d)\\\", v.r or 0, v.g or 0, v.b or 0)\\n\\t\\telseif v.t == \\\"par\\\" then\\n\\t\\t\\tif v.z ~= nil then\\n\\t\\t\\t\\treturn string.format(\\\"(%s, %s, %s)\\\", tostring(v.x), tostring(v.y), tostring(v.z))\\n\\t\\t\\tend\\n\\t\\t\\treturn string.format(\\\"(%s, %s)\\\", tostring(v.x), tostring(v.y))\\n\\t\\telseif v.t == \\\"anim\\\" then\\n\\t\\t\\tlocal cl = {}\\n\\t\\t\\tif v.efeito and v.efeito ~= \\\"\\\" then table.insert(cl, v.efeito) end\\n\\t\\t\\tfor k, vv in pairs(v) do\\n\\t\\t\\t\\tif k ~= \\\"t\\\" and k ~= \\\"efeito\\\" then\\n\\t\\t\\t\\t\\ttable.insert(cl, k .. \\\" = \\\" .. textoValor(vv))\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\treturn table.concat(cl, \\\" + \\\")\\n\\t\\tend\\n\\tend\\n\\treturn tostring(v)\\nend\\n\\n-- renderiza de volta para YashScript um valor RICO do parser (campo `expr`)\\nlocal function textoExpr(e)\\n\\tif not e then return \\\"\\\" end\\n\\tif e.k == \\\"num\\\" then return tostring(e.v) end\\n\\tif e.k == \\\"str\\\" then return escaparTexto(e.v) end\\n\\tif e.k == \\\"bool\\\" then return e.v and \\\"verdadeiro\\\" or \\\"falso\\\" end\\n\\tif e.k == \\\"nulo\\\" then return \\\"nulo\\\" end\\n\\tif e.k == \\\"ident\\\" then return tostring(e.v) end\\n\\tif e.k == \\\"caminho\\\" then return table.concat(e.partes, \\\".\\\") end\\n\\tif e.k == \\\"unario\\\" then return tostring(e.op) .. textoExpr(e.valor) end\\n\\tif e.k == \\\"binario\\\" then\\n\\t\\treturn \\\"(\\\" .. textoExpr(e.esq) .. \\\" \\\" .. tostring(e.op) .. \\\" \\\" .. textoExpr(e.dir) .. \\\")\\\"\\n\\tend\\n\\tif e.k == \\\"chamada\\\" then\\n\\t\\tlocal args = {}\\n\\t\\tfor _, arg in ipairs(e.args or {}) do table.insert(args, textoExpr(arg)) end\\n\\t\\treturn textoExpr(e.alvo) .. \\\"(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\"\\n\\tend\\n\\tif e.k == \\\"metodo_expr\\\" then\\n\\t\\tlocal args = {}\\n\\t\\tfor _, arg in ipairs(e.args or {}) do table.insert(args, textoExpr(arg)) end\\n\\t\\treturn textoExpr(e.base) .. \\\":\\\" .. tostring(e.metodo) .. \\\"(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\"\\n\\tend\\n\\tif e.k == \\\"membro\\\" then return textoExpr(e.base) .. \\\".\\\" .. tostring(e.nome) end\\n\\tif e.k == \\\"indice\\\" then return textoExpr(e.base) .. \\\"[\\\" .. textoExpr(e.chave) .. \\\"]\\\" end\\n\\tif e.k == \\\"tabela\\\" then\\n\\t\\tlocal campos = {}\\n\\t\\tfor _, campo in ipairs(e.campos or {}) do\\n\\t\\t\\tif campo.chave then\\n\\t\\t\\t\\ttable.insert(campos, \\\"[\\\" .. textoExpr(campo.chave) .. \\\"] = \\\" .. textoExpr(campo.valor))\\n\\t\\t\\telse\\n\\t\\t\\t\\ttable.insert(campos, textoExpr(campo.valor))\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn \\\"{\\\" .. table.concat(campos, \\\", \\\") .. \\\"}\\\"\\n\\tend\\n\\tif e.k == \\\"cor\\\" then\\n\\t\\treturn string.format(\\\"rgb(%s, %s, %s)\\\", tostring(e.r), tostring(e.g), tostring(e.b))\\n\\tend\\n\\tif e.k == \\\"par\\\" then\\n\\t\\tlocal partes = { tostring(e.x), tostring(e.y) }\\n\\t\\tif e.z then table.insert(partes, tostring(e.z)) end\\n\\t\\treturn \\\"(\\\" .. table.concat(partes, \\\", \\\") .. \\\")\\\"\\n\\tend\\n\\tif e.k == \\\"param\\\" then\\n\\t\\treturn tostring(e.nome) .. \\\" = \\\" .. textoExpr(e.valor)\\n\\tend\\n\\tif e.k == \\\"anim\\\" then\\n\\t\\tlocal cl = {}\\n\\t\\tif e.efeito and e.efeito ~= \\\"\\\" then table.insert(cl, tostring(e.efeito)) end\\n\\t\\tlocal ks = {}\\n\\t\\tfor nome in pairs(e.params or {}) do table.insert(ks, nome) end\\n\\t\\ttable.sort(ks)\\n\\t\\tfor _, nome in ipairs(ks) do\\n\\t\\t\\ttable.insert(cl, nome .. \\\" = \\\" .. textoExpr(e.params[nome]))\\n\\t\\tend\\n\\t\\treturn table.concat(cl, \\\" + \\\")\\n\\tend\\n\\treturn textoValor(e.v)\\nend\\n\\nlocal function textoProps(props)\\n\\tlocal linhas = {}\\n\\tfor k, v in pairs(props or {}) do\\n\\t\\ttable.insert(linhas, string.format(\\\"    %s = %s\\\", k, textoValor(v)))\\n\\tend\\n\\ttable.sort(linhas)\\n\\treturn table.concat(linhas, \\\"\\\\n\\\")\\nend\\n\\nlocal function textoCond(c)\\n\\tif not c then return \\\"\\\" end\\n\\tif c.tipo == \\\"logica\\\" then\\n\\t\\treturn textoCond(c.esq) .. \\\" \\\" .. c.op .. \\\" \\\" .. textoCond(c.dir)\\n\\telseif c.tipo == \\\"nao\\\" then\\n\\t\\treturn \\\"nao (\\\" .. textoCond(c.cond) .. \\\")\\\"\\n\\telseif c.tipo == \\\"comp\\\" then\\n\\t\\treturn textoExpr(c.esq) .. \\\" \\\" .. c.op .. \\\" \\\" .. textoExpr(c.dir)\\n\\telseif c.tipo == \\\"truthy\\\" then\\n\\t\\treturn textoExpr(c.valor)\\n\\telseif c.tipo == \\\"estado\\\" then\\n\\t\\treturn c.oq .. \\\"('\\\" .. c.el .. \\\"')\\\"\\n\\telseif c.tipo == \\\"num\\\" then\\n\\t\\treturn c.obj .. \\\" \\\" .. c.op .. \\\" \\\" .. tostring(c.val)\\n\\telseif c.tipo == \\\"tecla\\\" then\\n\\t\\treturn c.obj .. \\\" apertar \\\" .. c.tecla\\n\\telseif c.tipo == \\\"vida\\\" then\\n\\t\\treturn c.alvo .. \\\" \\\" .. (c.estado and \\\"vivo\\\" or \\\"morto\\\")\\n\\telseif c.tipo == \\\"dist\\\" then\\n\\t\\tif c.op == \\\"<\\\" then\\n\\t\\t\\tif c.raio then return c.a .. \\\" perto de \\\" .. c.b end\\n\\t\\t\\treturn \\\"distancia \\\" .. c.a .. \\\" de \\\" .. c.b .. \\\" menor que \\\" .. tostring(c.val)\\n\\t\\tend\\n\\t\\tif c.raio then return c.a .. \\\" longe de \\\" .. c.b end\\n\\t\\treturn \\\"distancia \\\" .. c.a .. \\\" de \\\" .. c.b .. \\\" maior que \\\" .. tostring(c.val)\\n\\telseif c.tipo == \\\"tocar\\\" then\\n\\t\\treturn c.a .. \\\" tocar \\\" .. c.b\\n\\telseif c.tipo == \\\"criado\\\" then\\n\\t\\treturn string.format(\\\"%q criado com sucesso\\\", c.nome)\\n\\tend\\n\\treturn \\\"\\\"\\nend\\n\\nlocal function sufixoAnim(anim)\\n\\tif not anim then return \\\"\\\" end\\n\\treturn \\\" animacao = \\\" .. textoExpr(anim)\\nend\\n\\nlocal function empilharComandos(corpo, recuo, linhas)\\n\\tfor _, cmd in ipairs(corpo or {}) do\\n\\t\\tif cmd.tipo == \\\"log\\\" then\\n\\t\\t\\tif cmd.args then\\n\\t\\t\\t\\tlocal args = {}\\n\\t\\t\\t\\tfor _, arg in ipairs(cmd.args) do table.insert(args, textoExpr(arg)) end\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"print(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\")\\n\\t\\t\\telseif cmd.caminho then\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"print(\\\" .. cmd.caminho .. \\\")\\\")\\n\\t\\t\\telseif cmd.forma == \\\"mostrar\\\" then\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"mostrar texto \\\" .. escaparTexto(cmd.texto))\\n\\t\\t\\telse\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"print(\\\" .. escaparTexto(cmd.texto) .. \\\")\\\")\\n\\t\\t\\tend\\n\\t\\telseif cmd.tipo == \\\"cena\\\" then\\n\\t\\t\\tlocal prefixo = cmd.acao == \\\"mudar\\\" and \\\"mudar cena\\\" or (cmd.acao .. \\\" cena\\\")\\n\\t\\t\\ttable.insert(linhas, recuo .. prefixo .. \\\" '\\\" .. cmd.alvo .. \\\"'\\\" .. sufixoAnim(cmd.anim))\\n\\t\\telseif cmd.tipo == \\\"visivel\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. cmd.acao .. \\\"('\\\" .. cmd.alvo .. \\\"')\\\" .. sufixoAnim(cmd.anim))\\n\\t\\telseif cmd.tipo == \\\"prop\\\" then\\n\\t\\t\\tfor k, v in pairs(cmd.props or {}) do\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. k .. \\\" = \\\" .. textoValor(v))\\n\\t\\t\\tend\\n\\t\\telseif cmd.tipo == \\\"animacao\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"executar animacao \\\" .. cmd.nome .. sufixoAnim(cmd.anim))\\n\\t\\telseif cmd.tipo == \\\"tween\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"animar(\\\" .. escaparTexto(cmd.alvo) .. \\\") \\\" .. textoExpr(cmd.valor))\\n\\t\\telseif cmd.tipo == \\\"acao\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"executar acao \\\" .. cmd.nome)\\n\\t\\telseif cmd.tipo == \\\"destruir\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"destruir \\\" .. cmd.oq .. \\\" \\\" .. cmd.alvo)\\n\\t\\telseif cmd.tipo == \\\"metodo\\\" then\\n\\t\\t\\t-- preserva o separador original (ponto ou dois pontos) e os argumentos\\n\\t\\t\\tlocal sep = cmd.sep or \\\".\\\"\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tfor _, v in ipairs(cmd.args or {}) do table.insert(args, textoExpr(v)) end\\n\\t\\t\\ttable.insert(linhas, recuo .. cmd.alvo .. sep .. cmd.metodo\\n\\t\\t\\t\\t.. \\\"(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\")\\n\\t\\telseif cmd.tipo == \\\"atrib\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. cmd.caminho .. \\\" \\\" .. cmd.op .. \\\" \\\"\\n\\t\\t\\t\\t.. (cmd.expr and textoExpr(cmd.expr) or textoValor(cmd.valor)))\\n\\t\\telseif cmd.tipo == \\\"atrib_indice\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. textoExpr(cmd.destino) .. \\\" \\\" .. cmd.op .. \\\" \\\" .. textoExpr(cmd.expr))\\n\\t\\telseif cmd.tipo == \\\"soma\\\" then\\n\\t\\t\\tif cmd.op == \\\"somar\\\" then\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"somar \\\" .. cmd.de .. \\\" a \\\" .. cmd.para)\\n\\t\\t\\telse\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"subtrair \\\" .. cmd.de .. \\\" de \\\" .. cmd.para)\\n\\t\\t\\tend\\n\\t\\telseif cmd.tipo == \\\"se\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"se \\\" .. textoCond(cmd.cond))\\n\\t\\t\\tempilharComandos(cmd.corpo, recuo .. \\\"    \\\", linhas)\\n\\t\\t\\tfor _, alternativa in ipairs(cmd.alternativas or {}) do\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"senao se \\\" .. textoCond(alternativa.cond))\\n\\t\\t\\t\\tempilharComandos(alternativa.corpo, recuo .. \\\"    \\\", linhas)\\n\\t\\t\\tend\\n\\t\\t\\tif cmd.senao then\\n\\t\\t\\t\\ttable.insert(linhas, recuo .. \\\"senao\\\")\\n\\t\\t\\t\\tempilharComandos(cmd.senao, recuo .. \\\"    \\\", linhas)\\n\\t\\t\\tend\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"fim\\\")\\n\\t\\telseif cmd.tipo == \\\"enquanto\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"enquanto \\\" .. textoCond(cmd.cond))\\n\\t\\t\\tempilharComandos(cmd.corpo, recuo .. \\\"    \\\", linhas)\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"fim\\\")\\n\\t\\telseif cmd.tipo == \\\"repita\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"repita\\\")\\n\\t\\t\\tempilharComandos(cmd.corpo, recuo .. \\\"    \\\", linhas)\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"ate \\\" .. textoCond(cmd.cond))\\n\\t\\telseif cmd.tipo == \\\"pare\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"pare\\\")\\n\\t\\telseif cmd.tipo == \\\"continuar\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"continuar\\\")\\n\\t\\telseif cmd.tipo == \\\"para\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"para \\\" .. cmd.nome .. \\\" de \\\" .. textoExpr(cmd.inicio)\\n\\t\\t\\t\\t.. \\\" ate \\\" .. textoExpr(cmd.limite) .. \\\" passo \\\" .. textoExpr(cmd.passo))\\n\\t\\t\\tempilharComandos(cmd.corpo, recuo .. \\\"    \\\", linhas)\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"fim\\\")\\n\\t\\telseif cmd.tipo == \\\"para_cada\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"para cada \\\" .. table.concat(cmd.nomes or {}, \\\", \\\")\\n\\t\\t\\t\\t.. \\\" em \\\" .. textoExpr(cmd.colecao))\\n\\t\\t\\tempilharComandos(cmd.corpo, recuo .. \\\"    \\\", linhas)\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"fim\\\")\\n\\t\\telseif cmd.tipo == \\\"espera\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"esperar \\\" .. tostring(cmd.valor))\\n\\t\\telseif cmd.tipo == \\\"dano\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"causar dano \\\" .. cmd.alvo .. \\\" \\\" .. tostring(cmd.valor))\\n\\t\\telseif cmd.tipo == \\\"curar\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"curar \\\" .. cmd.alvo .. \\\" \\\" .. tostring(cmd.valor))\\n\\t\\telseif cmd.tipo == \\\"matar\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"matar \\\" .. cmd.alvo)\\n\\t\\telseif cmd.tipo == \\\"respawnar\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"respawnar \\\" .. cmd.alvo)\\n\\t\\telseif cmd.tipo == \\\"teleportar\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"teleportar \\\" .. cmd.alvo .. \\\" \\\" .. textoValor(cmd.pos))\\n\\t\\telseif cmd.tipo == \\\"mover\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"mover \\\" .. cmd.alvo .. \\\" para \\\" .. textoValor(cmd.para) .. \\\" velocidade \\\" .. tostring(cmd.velocidade))\\n\\t\\telseif cmd.tipo == \\\"rotacionar\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"rotacionar \\\" .. cmd.alvo .. \\\" para \\\" .. textoValor(cmd.para) .. \\\" duracao \\\" .. tostring(cmd.duracao))\\n\\t\\telseif cmd.tipo == \\\"sortear\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"sortear \\\" .. cmd.nome .. \\\" entre \\\" .. tostring(cmd.min) .. \\\" e \\\" .. tostring(cmd.max))\\n\\t\\telseif cmd.tipo == \\\"som\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"tocar som \\\" .. cmd.id)\\n\\t\\telseif cmd.tipo == \\\"explodir\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"explodir \\\" .. cmd.alvo .. \\\" raio \\\" .. tostring(cmd.raio) .. \\\" dano \\\" .. tostring(cmd.dano))\\n\\t\\telseif cmd.tipo == \\\"seguir\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"seguir \\\" .. cmd.quem .. \\\" o \\\" .. cmd.alvo)\\n\\t\\telseif cmd.tipo == \\\"variavel\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"variavel \\\" .. cmd.nome .. (cmd.expr and (\\\" = \\\" .. textoExpr(cmd.expr)) or \\\"\\\"))\\n\\t\\telseif cmd.tipo == \\\"retornar\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. \\\"retornar\\\" .. (cmd.expr and (\\\" \\\" .. textoExpr(cmd.expr)) or \\\"\\\"))\\n\\t\\telseif cmd.tipo == \\\"expressao\\\" then\\n\\t\\t\\ttable.insert(linhas, recuo .. textoExpr(cmd.expr))\\n\\t\\tend\\n\\tend\\nend\\n\\nlocal function chavesOrdenadas(tab)\\n\\tlocal chaves = {}\\n\\tfor k in pairs(tab or {}) do table.insert(chaves, k) end\\n\\ttable.sort(chaves, function(a, b) return tostring(a) < tostring(b) end)\\n\\treturn chaves\\nend\\n\\nfunction Compilador.Descompilar(config)\\n\\tconfig = config or {}\\n\\tlocal L = {}\\n\\tif config.marcador then\\n\\t\\ttable.insert(L, \\\"YASHSCRIPT:\\\")\\n\\tend\\n\\n\\tfor _, inc in ipairs(config.incluir or {}) do\\n\\t\\ttable.insert(L, 'incluir \\\"' .. inc .. '\\\"')\\n\\tend\\n\\n\\tif config.site and next(config.site) then\\n\\t\\ttable.insert(L, \\\"site\\\")\\n\\t\\ttable.insert(L, textoProps(config.site))\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tif config.mundo and next(config.mundo) then\\n\\t\\ttable.insert(L, \\\"mundo\\\")\\n\\t\\ttable.insert(L, textoProps(config.mundo))\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.cenas)) do\\n\\t\\ttable.insert(L, \\\"criar cena '\\\" .. nome .. \\\"'\\\")\\n\\t\\ttable.insert(L, textoProps(config.cenas[nome]))\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.estilos)) do\\n\\t\\ttable.insert(L, \\\"criar estilo '\\\" .. nome .. \\\"'\\\")\\n\\t\\ttable.insert(L, textoProps(config.estilos[nome]))\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tlocal vistos = {}\\n\\tfor _, nome in ipairs(config.ordem_elementos or {}) do\\n\\t\\tlocal def = config.elementos[nome]\\n\\t\\tif def then\\n\\t\\t\\ttable.insert(L, \\\"criar \\\" .. def.tipo .. \\\" '\\\" .. nome .. \\\"'\\\")\\n\\t\\t\\ttable.insert(L, textoProps(def.props))\\n\\t\\t\\ttable.insert(L, \\\"fim\\\")\\n\\t\\t\\tvistos[nome] = true\\n\\t\\tend\\n\\tend\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.elementos)) do\\n\\t\\tif not vistos[nome] then\\n\\t\\t\\tlocal def = config.elementos[nome]\\n\\t\\t\\ttable.insert(L, \\\"criar \\\" .. def.tipo .. \\\" '\\\" .. nome .. \\\"'\\\")\\n\\t\\t\\ttable.insert(L, textoProps(def.props))\\n\\t\\t\\ttable.insert(L, \\\"fim\\\")\\n\\t\\tend\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.objetos)) do\\n\\t\\ttable.insert(L, \\\"criar objeto '\\\" .. nome .. \\\"'\\\")\\n\\t\\ttable.insert(L, textoProps(config.objetos[nome]))\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.formas)) do\\n\\t\\tlocal def = config.formas[nome]\\n\\t\\ttable.insert(L, \\\"criar \\\" .. def.tipo .. \\\" '\\\" .. nome .. \\\"'\\\")\\n\\t\\ttable.insert(L, textoProps(def.props))\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, tme in ipairs(config.timers or {}) do\\n\\t\\ttable.insert(L, \\\"a cada \\\" .. tostring(tme.intervalo))\\n\\t\\tlocal linhas = {}\\n\\t\\tempilharComandos(tme.corpo, \\\"    \\\", linhas)\\n\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.huds)) do\\n\\t\\ttable.insert(L, \\\"criar hud '\\\" .. nome .. \\\"'\\\")\\n\\t\\tif config.huds[nome].campo then\\n\\t\\t\\ttable.insert(L, \\\"    mostrar \\\" .. config.huds[nome].campo)\\n\\t\\tend\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.acoes)) do\\n\\t\\ttable.insert(L, \\\"criar acao '\\\" .. nome .. \\\"'\\\")\\n\\t\\tlocal linhas = {}\\n\\t\\tempilharComandos(config.acoes[nome], \\\"    \\\", linhas)\\n\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.funcoes)) do\\n\\t\\tlocal def = config.funcoes[nome]\\n\\t\\ttable.insert(L, \\\"criar funcao \\\" .. nome .. \\\"(\\\" .. table.concat(def.parametros or {}, \\\", \\\") .. \\\")\\\")\\n\\t\\tlocal linhas = {}\\n\\t\\tempilharComandos(def.corpo, \\\"    \\\", linhas)\\n\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, nome in ipairs(chavesOrdenadas(config.animacoes)) do\\n\\t\\ttable.insert(L, \\\"criar animacao '\\\" .. nome .. \\\"'\\\")\\n\\t\\tfor _, a in ipairs(config.animacoes[nome].lista or {}) do\\n\\t\\t\\ttable.insert(L, \\\"    animacao = \\\" .. textoExpr(a))\\n\\t\\tend\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\t-- `usar \\\"Nome\\\" = <caminho>` volta a ser `usar` na descompilacao\\n\\tfor _, al in ipairs(config.aliases or {}) do\\n\\t\\ttable.insert(L, \\\"usar \\\" .. escaparTexto(al.nome) .. \\\" = \\\" .. textoExpr(al.expr))\\n\\tend\\n\\n\\tlocal linhasCmd = {}\\n\\tempilharComandos(config.comandos, \\\"\\\", linhasCmd)\\n\\tfor _, l in ipairs(linhasCmd) do table.insert(L, l) end\\n\\n\\tfor _, ev in ipairs(config.eventos or {}) do\\n\\t\\tlocal cab\\n\\t\\tif ev.sujeito then\\n\\t\\t\\tcab = \\\"quando \\\" .. ev.sujeito .. \\\" \\\" .. ev.tipo\\n\\t\\t\\tif ev.alvo then cab = cab .. \\\" '\\\" .. ev.alvo .. \\\"'\\\" end\\n\\t\\telseif ev.tipo == \\\"carregar\\\" or ev.tipo == \\\"iniciar\\\" then\\n\\t\\t\\tcab = \\\"quando \\\" .. ev.tipo\\n\\t\\telse\\n\\t\\t\\tcab = \\\"quando \\\" .. ev.tipo .. \\\" '\\\" .. ev.alvo .. \\\"'\\\"\\n\\t\\tend\\n\\t\\ttable.insert(L, cab)\\n\\t\\tlocal linhas = {}\\n\\t\\tempilharComandos(ev.corpo, \\\"    \\\", linhas)\\n\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, c in ipairs(config.continuos or {}) do\\n\\t\\ttable.insert(L, \\\"se \\\" .. textoCond(c.cond))\\n\\t\\tlocal linhas = {}\\n\\t\\tempilharComandos(c.corpo, \\\"    \\\", linhas)\\n\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\tfor _, alternativa in ipairs(c.alternativas or {}) do\\n\\t\\t\\ttable.insert(L, \\\"senao se \\\" .. textoCond(alternativa.cond))\\n\\t\\t\\tlinhas = {}\\n\\t\\t\\tempilharComandos(alternativa.corpo, \\\"    \\\", linhas)\\n\\t\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\tend\\n\\t\\tif c.senao then\\n\\t\\t\\ttable.insert(L, \\\"senao\\\")\\n\\t\\t\\tlinhas = {}\\n\\t\\t\\tempilharComandos(c.senao, \\\"    \\\", linhas)\\n\\t\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\tend\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, c in ipairs(config.loops or {}) do\\n\\t\\ttable.insert(L, \\\"enquanto \\\" .. textoCond(c.cond))\\n\\t\\tlocal linhas = {}\\n\\t\\tempilharComandos(c.corpo, \\\"    \\\", linhas)\\n\\t\\tfor _, l in ipairs(linhas) do table.insert(L, l) end\\n\\t\\ttable.insert(L, \\\"fim\\\")\\n\\tend\\n\\n\\tfor _, p in ipairs(config.proibicoes or {}) do\\n\\t\\tlocal linha = \\\"proibir \\\" .. p.evt .. \\\" '\\\" .. p.alvo .. \\\"' de \\\"\\n\\t\\t\\t.. table.concat(p.comandos or {}, \\\" + \\\")\\n\\t\\tif p.cond then linha = linha .. \\\" se \\\" .. textoCond(p.cond) end\\n\\t\\tif p.somente then linha = linha .. \\\" somente \\\" .. escaparTexto(p.somente) end\\n\\t\\ttable.insert(L, linha)\\n\\tend\\n\\n\\treturn table.concat(L, \\\"\\\\n\\\") .. \\\"\\\\n\\\"\\nend\\n\\nfunction Compilador.Tokenizar(fonte)\\n\\tlocal ok, ret = pcall(tokenizar, string.gsub(fonte or \\\"\\\", \\\"\\\\r\\\\n\\\", \\\"\\\\n\\\"))\\n\\tif ok then return true, ret end\\n\\treturn false, { erro = ret.erro or \\\"erro\\\", linha = ret.linha or 0 }\\nend\\n\\nreturn Compilador\\n\""),
	Gerador = HttpService:JSONDecode("\"--[[\\n  YashScript V8.0 — Gerador de Luau\\n\\n  Recebe o PROGRAMA (a estrutura devolvida por compilador.Compilar) e devolve\\n  Luau puro, pronto para o Source de um Script / LocalScript / ModuleScript.\\n\\n    YashScript  ->  Compilar  ->  programa  ->  GerarLuau  ->  Luau\\n\\n  Regras desta camada:\\n    * nada de `_YashConfig`, nada de interpretador, nada de marcador;\\n    * cada construção do YashScript vira a instrução Luau equivalente;\\n    * o contexto (servidor / cliente / comum) é informado pelo PLUGIN e vem da\\n      classe do script alvo -- nunca do texto-fonte;\\n    * referências à árvore do Roblox são resolvidas semanticamente: em cliente,\\n      `StarterGui` vira `PlayerGui`; se o script já estiver dentro de um\\n      ScreenGui, a resolução parte do ancestral, não do serviço.\\n\\n  Uso:\\n    local Gerador = require(script.gerador)\\n    local ok, luau = Gerador.GerarLuau(programa, {\\n      contexto = \\\"cliente\\\",              -- \\\"servidor\\\" | \\\"cliente\\\" | \\\"comum\\\"\\n      ancestraGui = {\\\"ScreenGui\\\",\\\"Frame\\\"}, -- nomes do ScreenGui ate script.Parent\\n      modulo = false,                    -- true = ModuleScript (retorna tabela)\\n    })\\n    -- ok = false -> luau = { erro = \\\"mensagem\\\", linha = n }\\n]]\\n\\nlocal Gerador = { VERSAO = \\\"8.0\\\" }\\n\\nlocal JUNTAR = table.concat\\n\\n-----------------------------------------------------------------------\\n-- dicionarios de traducao\\n-----------------------------------------------------------------------\\n\\n-- Servicos do Roblox conhecidos pelo nome em portugues/ingles.\\n-- Valor = nome canonico; o gerador emite game:GetService(\\\"<canonico>\\\").\\nlocal SERVICOS = {\\n\\tworkspace = \\\"Workspace\\\",\\n\\treplicatedstorage = \\\"ReplicatedStorage\\\",\\n\\tserverstorage = \\\"ServerStorage\\\",\\n\\tserverscriptservice = \\\"ServerScriptService\\\",\\n\\tplayers = \\\"Players\\\",\\n\\tlighting = \\\"Lighting\\\",\\n\\trunservice = \\\"RunService\\\",\\n\\tuserinputservice = \\\"UserInputService\\\",\\n\\ttweenservice = \\\"TweenService\\\",\\n\\tsoundservice = \\\"SoundService\\\",\\n\\tdebris = \\\"Debris\\\",\\n\\tdebrisservice = \\\"Debris\\\",\\n\\tdebisservice = \\\"Debris\\\",\\n\\tcontextactionservice = \\\"ContextActionService\\\",\\n\\thttpservice = \\\"HttpService\\\",\\n\\tdatastoreservice = \\\"DataStoreService\\\",\\n\\tmarketplaceservice = \\\"MarketplaceService\\\",\\n\\tcollectionservice = \\\"CollectionService\\\",\\n\\tphysicsservice = \\\"PhysicsService\\\",\\n\\ttextchatservice = \\\"TextChatService\\\",\\n\\tchatwindowconfiguration = \\\"ChatWindowConfiguration\\\",\\n\\tstartergui = \\\"StarterGui\\\",\\n\\tstarterpack = \\\"StarterPack\\\",\\n}\\n\\n-- Construtores e namespaces globais do Luau/Roblox que podem ser usados em\\n-- expressoes (por exemplo Instance.new, Vector3.new e Enum.Material.Neon).\\n-- Eles sao encaminhados literalmente; nomes fora desta lista continuam\\n-- exigindo alias, local, funcao declarada ou servico conhecido.\\nlocal GLOBAIS_LUAU = {\\n\\tInstance = true, Enum = true, Vector2 = true, Vector3 = true,\\n\\tVector2int16 = true, Vector3int16 = true, CFrame = true, Color3 = true,\\n\\tUDim = true, UDim2 = true, BrickColor = true, TweenInfo = true,\\n\\tRay = true, RaycastParams = true, OverlapParams = true, Region3 = true,\\n\\tRegion3int16 = true, NumberRange = true, NumberSequence = true,\\n\\tNumberSequenceKeypoint = true, ColorSequence = true,\\n\\tColorSequenceKeypoint = true, PhysicalProperties = true, Rect = true,\\n\\tAxes = true, Faces = true, Font = true, DateTime = true, Random = true,\\n\\tSharedTable = true, task = true, math = true, string = true, table = true,\\n\\tutf8 = true, os = true, coroutine = true, debug = true, bit32 = true,\\n\\tbuffer = true,\\n}\\n\\nlocal FUNCOES_LUAU = {\\n\\tassert = true, error = true, ipairs = true, pairs = true, next = true,\\n\\tpcall = true, xpcall = true, select = true, tonumber = true,\\n\\ttostring = true, type = true, typeof = true, unpack = true, print = true,\\n\\twarn = true, rawget = true, rawset = true, rawequal = true, rawlen = true,\\n\\tgetmetatable = true, setmetatable = true, require = true,\\n}\\n\\n-- Onde cada servico realmente esta quando o codigo roda no CLIENTE.\\n-- `StarterGui` e `PlayerGui` nao sao o mesmo objeto em runtime, entao o\\n-- gerador traduz em vez de indexar direto.\\nlocal SERVICOS_CLIENTE = {\\n\\tstartergui = 'Players.LocalPlayer:WaitForChild(\\\"PlayerGui\\\")',\\n}\\n\\n-- Propriedades YashScript -> propriedade real do Roblox.\\n-- Adicionar uma traducao nova e UMA LINHA nesta tabela.\\nlocal PROPRIEDADES = {\\n\\tvisivel = \\\"Visible\\\",\\n\\ttexto = \\\"Text\\\",\\n\\tvida = \\\"Health\\\",\\n\\thealth = \\\"Health\\\",\\n\\tvida_maxima = \\\"MaxHealth\\\",\\n\\tmax_vida = \\\"MaxHealth\\\",\\n\\tmaxhealth = \\\"MaxHealth\\\",\\n\\tvelocidade = \\\"WalkSpeed\\\",\\n\\twalkspeed = \\\"WalkSpeed\\\",\\n\\tjumppower = \\\"JumpPower\\\",\\n\\tposition = \\\"Position\\\",\\n\\tsize = \\\"Size\\\",\\n\\tcframe = \\\"CFrame\\\",\\n\\tcurrentcamera = \\\"CurrentCamera\\\",\\n\\tname = \\\"Name\\\",\\n\\tparent = \\\"Parent\\\",\\n\\ttransparency = \\\"Transparency\\\",\\n\\tvisible = \\\"Visible\\\",\\n\\tenabled = \\\"Enabled\\\",\\n\\tancorado = \\\"Anchored\\\",\\n\\tanchored = \\\"Anchored\\\",\\n\\tcolisao = \\\"CanCollide\\\",\\n\\tcancollide = \\\"CanCollide\\\",\\n\\tmaterial = \\\"Material\\\",\\n\\tcolor = \\\"Color\\\",\\n\\trotation = \\\"Rotation\\\",\\n\\ttransparente = \\\"Transparency\\\",\\n\\tposicao_3d = \\\"Position\\\",\\n\\tcor_3d = \\\"Color\\\",\\n\\tplaceholder = \\\"PlaceholderText\\\",\\n\\ttransparencia = \\\"BackgroundTransparency\\\",\\n\\tcor = \\\"BackgroundColor3\\\",\\n\\tcor_fundo = \\\"BackgroundColor3\\\",\\n\\tcor_texto = \\\"TextColor3\\\",\\n\\tcor_borda = \\\"BorderColor3\\\",\\n\\tborda = \\\"BorderSizePixel\\\",\\n\\ttamanho_fonte = \\\"TextSize\\\",\\n\\tfonte = \\\"Font\\\",\\n\\timagem = \\\"Image\\\",\\n\\tativo = \\\"Active\\\",\\n\\tselecionavel = \\\"Selectable\\\",\\n\\tauto = \\\"AutoButtonColor\\\",\\n\\tlayout_order = \\\"LayoutOrder\\\",\\n\\tlayout = \\\"LayoutOrder\\\",\\n\\tanchor_point = \\\"AnchorPoint\\\",\\n\\tz_index = \\\"ZIndex\\\",\\n\\tgrupo = \\\"GroupColor3\\\",\\n\\trotacao = \\\"Rotation\\\",\\n\\testado = \\\"State\\\",\\n\\tmodal = \\\"Modal\\\",\\n\\texclusivo = \\\"Exclusive\\\",\\n\\treset = \\\"ResetOnSpawn\\\",\\n\\tencerrado = \\\"CloseOnEscape\\\",\\n\\ttamanho = \\\"Size\\\",\\n\\tposicao = \\\"Position\\\",\\n\\tdistancia_lateral = \\\"AbsolutePosition\\\",\\n\\ttamanho_absoluto = \\\"AbsoluteSize\\\",\\n}\\n\\n-- Propriedades que recebem UDim2 quando o valor e uma tupla (x, y[, z]).\\n-- Qualquer outra tupla vira Vector3.new.\\nlocal PROPS_UDIM2 = {\\n\\tposicao = true, tamanho = true,\\n\\tdistancia_lateral = true, tamanho_absoluto = true,\\n\\tposition = true, size = true,\\n}\\n\\n-- Propriedades cujo valor e booleano (aceitam os verbos do YashScript).\\nlocal PROPS_BOOL = {\\n\\tvisivel = true, ativo = true, selecionavel = true, auto = true,\\n\\tmodal = true, reset = true,\\n}\\n\\n-- Eventos YashScript -> evento Roblox.\\n-- `argumento = true` significa que o callback recebe o parametro do evento.\\n-- `repete = true` significa que o Roblox dispara o evento muitas vezes seguidas\\n-- (Touched): o gerador aplica o mesmo debounce de 0.4s do Runtime legado.\\nlocal EVENTOS = {\\n\\tclicar = { evento = \\\"MouseButton1Click\\\", argumento = false },\\n\\tmouse_em = { evento = \\\"MouseEnter\\\", argumento = false },\\n\\tmouse_sair = { evento = \\\"MouseLeave\\\", argumento = false },\\n\\ttocar = { evento = \\\"Touched\\\", argumento = true, repete = true },\\n\\tencostar = { evento = \\\"Touched\\\", argumento = true, repete = true },\\n}\\n\\n-- Eventos sem alvo: executam inline, sem Connect.\\nlocal EVENTOS_INLINE = {\\n\\tiniciar = true, carregar = true,\\n}\\n\\n-- Sujeitos logicos em `quando <sujeito> tocar <alvo>`: nao existem na arvore,\\n-- representam QUEM encosta. O gerador exige um Humanoid no que tocou (mesma\\n-- condicao que o Runtime legado usava para sujeito que nao era um objeto).\\nlocal SUJEITOS_LOGICOS = {\\n\\tjogador = true,\\n\\tplayer = true,\\n}\\n\\nlocal DEBOUNCE_TOQUE = 0.4\\n\\n-- Efeitos de animacao reconhecidos e seus sinonimos. O valor canonico e a\\n-- chave dos emissores de efeito (fade in, fade out, slide left, ...).\\nlocal EFEITOS = {\\n\\t[\\\"fade in\\\"] = \\\"fade in\\\", aparecer = \\\"fade in\\\",\\n\\t[\\\"fade out\\\"] = \\\"fade out\\\", desaparecer = \\\"fade out\\\", sumir = \\\"fade out\\\",\\n\\t[\\\"slide left\\\"] = \\\"slide left\\\", esquerda = \\\"slide left\\\",\\n\\t[\\\"slide esquerda\\\"] = \\\"slide left\\\",\\n\\t[\\\"slide right\\\"] = \\\"slide right\\\", direita = \\\"slide right\\\",\\n\\t[\\\"slide direita\\\"] = \\\"slide right\\\",\\n\\t[\\\"slide up\\\"] = \\\"slide up\\\", subir = \\\"slide up\\\", cima = \\\"slide up\\\",\\n\\t[\\\"slide cima\\\"] = \\\"slide up\\\",\\n\\t[\\\"slide down\\\"] = \\\"slide down\\\", descer = \\\"slide down\\\", baixo = \\\"slide down\\\",\\n\\t[\\\"slide baixo\\\"] = \\\"slide down\\\",\\n\\tpulsar = \\\"pulsar\\\", pulse = \\\"pulsar\\\",\\n\\tgirar = \\\"girar\\\", spin = \\\"girar\\\",\\n\\tcrescer = \\\"crescer\\\", aumentar = \\\"crescer\\\",\\n\\tdiminuir = \\\"diminuir\\\", encolher = \\\"diminuir\\\",\\n}\\n\\n-- Parametros extras que cada efeito aceita (alem de duracao/estilo/direcao).\\nlocal EFEITO_PARAMS = {\\n\\t[\\\"fade in\\\"] = {}, [\\\"fade out\\\"] = {},\\n\\t[\\\"slide left\\\"] = { delta = true }, [\\\"slide right\\\"] = { delta = true },\\n\\t[\\\"slide up\\\"] = { delta = true }, [\\\"slide down\\\"] = { delta = true },\\n\\tpulsar = { escala = true }, crescer = { escala = true },\\n\\tdiminuir = { escala = true }, girar = { graus = true },\\n}\\n\\n-- estilo de suavizacao -> Enum.EasingStyle\\nlocal ESTILOS_EASING = {\\n\\tlinear = \\\"Linear\\\",\\n\\tsuave = \\\"Sine\\\", sine = \\\"Sine\\\", senoidal = \\\"Sine\\\",\\n\\tquad = \\\"Quad\\\", quadratico = \\\"Quad\\\",\\n\\tcubico = \\\"Cubic\\\", cubic = \\\"Cubic\\\",\\n\\tquart = \\\"Quart\\\", quartico = \\\"Quart\\\",\\n\\tquint = \\\"Quint\\\", quintico = \\\"Quint\\\",\\n\\texponencial = \\\"Exponential\\\", expo = \\\"Exponential\\\",\\n\\tcircular = \\\"Circular\\\", circ = \\\"Circular\\\",\\n\\telastico = \\\"Elastic\\\", elastic = \\\"Elastic\\\",\\n\\tressalto = \\\"Bounce\\\", bounce = \\\"Bounce\\\",\\n\\tvoltar = \\\"Back\\\", back = \\\"Back\\\",\\n}\\n\\n-- direcao do easing -> Enum.EasingDirection\\nlocal DIRECOES_EASING = {\\n\\tentrada = \\\"In\\\", [\\\"in\\\"] = \\\"In\\\",\\n\\tsaida = \\\"Out\\\", [\\\"out\\\"] = \\\"Out\\\",\\n\\tentrada_saida = \\\"InOut\\\", inout = \\\"InOut\\\",\\n}\\n\\n-- palavras reservadas do Luau: nao podem virar identificador\\nlocal PALAVRAS_LUA = {\\n\\t[\\\"and\\\"] = true, [\\\"break\\\"] = true, [\\\"do\\\"] = true, [\\\"else\\\"] = true,\\n\\t[\\\"elseif\\\"] = true, [\\\"end\\\"] = true, [\\\"false\\\"] = true, [\\\"for\\\"] = true,\\n\\t[\\\"function\\\"] = true, [\\\"goto\\\"] = true, [\\\"if\\\"] = true, [\\\"in\\\"] = true,\\n\\t[\\\"local\\\"] = true, [\\\"nil\\\"] = true, [\\\"not\\\"] = true, [\\\"or\\\"] = true,\\n\\t[\\\"repeat\\\"] = true, [\\\"return\\\"] = true, [\\\"then\\\"] = true, [\\\"true\\\"] = true,\\n\\t[\\\"until\\\"] = true, [\\\"while\\\"] = true,\\n}\\n\\n-----------------------------------------------------------------------\\n-- utilidades de texto\\n-----------------------------------------------------------------------\\n\\nlocal function numeroLua(v)\\n\\tif type(v) ~= \\\"number\\\" then return \\\"0\\\" end\\n\\tif v ~= v or v == math.huge or v == -math.huge then return \\\"0\\\" end\\n\\tif v == math.floor(v) and math.abs(v) < 1e15 then\\n\\t\\treturn string.format(\\\"%d\\\", v)\\n\\tend\\n\\t-- Menor representacao decimal que volta EXATAMENTE ao mesmo numero.\\n\\t-- (%.6f truncava: 0.7142857 virava 0.714286 e 1e-7 virava 0.)\\n\\tlocal s = string.format(\\\"%.15g\\\", v)\\n\\tif tonumber(s) ~= v then s = string.format(\\\"%.17g\\\", v) end\\n\\t-- Luau aceita notacao cientifica; um flutuante inteiro precisa de ponto\\n\\tif not s:find(\\\"[%.eE]\\\") then s = s .. \\\".0\\\" end\\n\\treturn s\\nend\\n\\n-- Escape de texto em estilo Luau, de forma canonica e independente do host.\\n-- Deve ficar IDENTICO ao de compilador/compilador.lua: os dois participates do\\n-- ciclo compilar -> gerar -> descompilar -> compilar.\\nlocal function escaparTexto(s)\\n\\ts = tostring(s)\\n\\ts = s:gsub(\\\"\\\\\\\\\\\", \\\"\\\\\\\\\\\\\\\\\\\")\\n\\ts = s:gsub(\\\"\\\\\\\"\\\", \\\"\\\\\\\\\\\\\\\"\\\")\\n\\ts = s:gsub(\\\"\\\\n\\\", \\\"\\\\\\\\n\\\")\\n\\ts = s:gsub(\\\"\\\\r\\\", \\\"\\\\\\\\r\\\")\\n\\ts = s:gsub(\\\"\\\\t\\\", \\\"\\\\\\\\t\\\")\\n\\ts = s:gsub(\\\"[%z\\\\1-\\\\31\\\\127]\\\", function(c)\\n\\t\\treturn string.format(\\\"\\\\\\\\%03d\\\", string.byte(c))\\n\\tend)\\n\\treturn \\\"\\\\\\\"\\\" .. s .. \\\"\\\\\\\"\\\"\\nend\\n\\nlocal function textoLua(s)\\n\\treturn escaparTexto(s)\\nend\\n\\n-- Chaves em ordem estavel. Mesma politica do Compilador.Descompilar, para\\n-- que gerar e descompilar concordem sobre a ordem dos blocos de topo.\\nlocal function nomesOrdenados(tab)\\n\\tlocal nomes = {}\\n\\tfor nome in pairs(tab or {}) do table.insert(nomes, nome) end\\n\\ttable.sort(nomes, function(a, b) return tostring(a) < tostring(b) end)\\n\\treturn nomes\\nend\\n\\nlocal function identificadorValido(nome)\\n\\treturn type(nome) == \\\"string\\\"\\n\\t\\tand string.match(nome, \\\"^[%a_][%w_]*$\\\") ~= nil\\n\\t\\tand not PALAVRAS_LUA[nome]\\nend\\n\\nlocal function dividirCaminho(caminho)\\n\\tlocal partes = {}\\n\\tfor p in string.gmatch(tostring(caminho), \\\"[^%.]+\\\") do\\n\\t\\ttable.insert(partes, p)\\n\\tend\\n\\treturn partes\\nend\\n\\nlocal function recuo(n)\\n\\treturn string.rep(\\\"\\\\t\\\", n or 0)\\nend\\n\\n-- normaliza \\\"sim\\\"/\\\"verdadeiro\\\"/\\\"true\\\" -> true; \\\"nao\\\"/\\\"falso\\\"/\\\"false\\\" -> false\\nlocal function normalizarBool(expr)\\n\\tif expr == nil then return nil end\\n\\tif expr.k == \\\"bool\\\" then return expr.v end\\n\\tif expr.k == \\\"str\\\" then\\n\\t\\tlocal l = string.lower(string.gsub(tostring(expr.v), \\\"%s+\\\", \\\"\\\"))\\n\\t\\tif l == \\\"sim\\\" or l == \\\"verdadeiro\\\" or l == \\\"true\\\" then return true end\\n\\t\\tif l == \\\"nao\\\" or l == \\\"falso\\\" or l == \\\"false\\\" then return false end\\n\\tend\\n\\treturn nil\\nend\\n\\n-----------------------------------------------------------------------\\n-- Gerador\\n-----------------------------------------------------------------------\\n\\nlocal function GerarLuau(programa, opcoes)\\n\\tprograma = programa or {}\\n\\topcoes = opcoes or {}\\n\\n\\tlocal contexto = opcoes.contexto or \\\"comum\\\"\\n\\tif contexto ~= \\\"servidor\\\" and contexto ~= \\\"cliente\\\" and contexto ~= \\\"comum\\\" then\\n\\t\\treturn false, { erro = \\\"contexto invalido: \\\" .. tostring(contexto), linha = 0 }\\n\\tend\\n\\n\\tlocal modulo = opcoes.modulo == true\\n\\tlocal ancestraGui = opcoes.ancestraGui\\n\\n\\t-- estado da geracao -------------------------------------------------\\n\\t-- As linhas vao para uma PILHA de buffers. Cada bloco (corpo de `se`,\\n\\t-- callback de evento, corpo de `a cada`) e renderizado num buffer proprio\\n\\t-- com o recuo certo e so depois anexado onde pertence. Isso permite gerar\\n\\t-- TODO o codigo ANTES de montar o cabecalho, garantindo que um servico\\n\\t-- descoberto no meio de um corpo ja exista como `local` no topo.\\n\\tlocal linhas = {}          -- buffer raiz: o codigo ja montado\\n\\tlocal pilha = { { linhas = linhas, nivel = 0 } }\\n\\tlocal servicosUsados = {}  -- canonico -> nome da local\\n\\tlocal aliases = {}         -- nome YashScript -> nome Luau\\n\\tlocal objetosDados = {}     -- objetos lógicos declarados com `criar objeto`\\n\\tlocal LOCAIS_GERADOS = {   -- locais criadas pelo proprio gerador\\n\\t\\t_YashAlvo = true,\\n\\t\\t_YashRaiz = true,\\n\\t\\t_YashPersonagem = true,\\n\\t\\t_YashUltimoToque = true,\\n\\t\\t_YashAgora = true,\\n\\t\\t_YashDoSujeito = true,\\n\\t\\t_YashVis = true,\\n\\t\\t_YashTween = true,\\n\\t\\t_YashG = true,\\n\\t\\t_YashP = true,\\n\\t\\t_YashTamanho = true,\\n\\t\\t_YashMetade = true,\\n\\t\\t_YashHumanoide = true,\\n\\t\\t_YashAlvoVida = true,\\n\\t\\t_YashPlayer = true,\\n\\t\\t_YashPersonagemAlvo = true,\\n\\t\\t_YashPivotInicial = true,\\n\\t\\t_YashExplosao = true,\\n\\t\\t_YashSom = true,\\n\\t\\t_YashAcao = true,\\n\\t\\t_YashAcaoAlvo = true,\\n\\t\\t_YashTela = true,\\n\\t\\t_YashRootFrame = true,\\n\\t}\\n\\tlocal usadoRaiz = false    -- precisa da local do ScreenGui\\n\\n\\tlocal function buffer() return pilha[#pilha].linhas end\\n\\tlocal function nivel() return pilha[#pilha].nivel end\\n\\n\\tlocal function emitir(s)\\n\\t\\ttable.insert(buffer(), recuo(nivel()) .. s)\\n\\tend\\n\\n\\t-- anexa linhas ja indentadas ao buffer atual\\n\\tlocal function anexar(ls)\\n\\t\\tlocal b = buffer()\\n\\t\\tfor _, l in ipairs(ls) do table.insert(b, l) end\\n\\tend\\n\\n\\t-- renderiza fn() num buffer novo com o recuo informado e devolve as linhas.\\n\\t-- NAO anexa ao pai: quem chama decide onde o bloco entra.\\n\\tlocal function blocoNovo(nivelBase, fn)\\n\\t\\ttable.insert(pilha, { linhas = {}, nivel = nivelBase })\\n\\t\\tlocal ok, err = fn()\\n\\t\\tlocal filho = table.remove(pilha)\\n\\t\\tif not ok then return nil, err end\\n\\t\\treturn filho.linhas\\n\\tend\\n\\n\\t-- garante uma local para o servico e devolve o nome dela\\n\\tlocal function servico(nomeCanonico)\\n\\t\\tif servicosUsados[nomeCanonico] then return servicosUsados[nomeCanonico] end\\n\\t\\tservicosUsados[nomeCanonico] = nomeCanonico\\n\\t\\treturn nomeCanonico\\n\\tend\\n\\n\\t-----------------------------------------------------------------------\\n\\t-- resolucao de caminhos da arvore do Roblox\\n\\t-----------------------------------------------------------------------\\n\\n\\tlocal function navegar(codigo, partes, ini)\\n\\t\\tfor i = ini, #partes do\\n\\t\\t\\tlocal seg = partes[i]\\n\\t\\t\\tlocal canonico = SERVICOS[string.lower(seg)]\\n\\t\\t\\tif canonico and canonico ~= \\\"StarterGui\\\" then\\n\\t\\t\\t\\tcodigo = codigo .. ':GetService(\\\"' .. canonico .. '\\\")'\\n\\t\\t\\telse\\n\\t\\t\\t\\tcodigo = codigo .. ':WaitForChild(\\\"' .. seg .. '\\\")'\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\treturn codigo\\n\\tend\\n\\n\\t-- devolve a expressao Luau para uma lista de segmentos:\\n\\t--   {\\\"StarterGui\\\",\\\"ScreenGui\\\",\\\"Frame\\\",\\\"Jogar\\\"}\\n\\t-- `semArvoreGui` desliga a resolucao pela arvore do ScreenGui: e usado nos\\n\\t-- alvos/sujeitos de `tocar`, que nunca sao objetos de GUI.\\n\\tlocal function resolverCaminho(partes, semArvoreGui)\\n\\t\\tif #partes == 0 then return nil, \\\"caminho vazio\\\" end\\n\\n\\t\\tlocal primeiro = partes[1]\\n\\t\\tlocal baixo = string.lower(primeiro)\\n\\n\\t\\t-- 1) alias declarado com `usar`\\n\\t\\tif aliases[primeiro] then\\n\\t\\t\\tlocal codigo = aliases[primeiro]\\n\\t\\t\\tfor i = 2, #partes do codigo = codigo .. \\\".\\\" .. partes[i] end\\n\\t\\t\\treturn codigo\\n\\t\\tend\\n\\n\\t\\t-- 2) `game`\\n\\t\\tif baixo == \\\"game\\\" then\\n\\t\\t\\treturn navegar(\\\"game\\\", partes, 2)\\n\\t\\tend\\n\\n\\t\\t-- 2b) construtores e namespaces globais do ambiente Luau.\\n\\t\\tif GLOBAIS_LUAU[primeiro] then\\n\\t\\t\\treturn table.concat(partes, \\\".\\\")\\n\\t\\tend\\n\\n\\t\\t-- 3) servico conhecido\\n\\t\\tlocal canonico = SERVICOS[baixo]\\n\\t\\tif canonico then\\n\\t\\t\\t-- StarterGui em cliente nao e o mesmo objeto em runtime\\n\\t\\t\\tif contexto == \\\"cliente\\\" and SERVICOS_CLIENTE[baixo] then\\n\\t\\t\\t\\t-- o script ja esta dentro de um ScreenGui? resolve pelo ancestral\\n\\t\\t\\t\\tif ancestraGui and ancestraGui[1] and #partes >= 2\\n\\t\\t\\t\\t\\tand partes[2] == ancestraGui[1] then\\n\\t\\t\\t\\t\\tusadoRaiz = true\\n\\t\\t\\t\\t\\treturn navegar(\\\"_YashRaiz\\\", partes, 3)\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\t-- senao: PlayerGui\\n\\t\\t\\t\\tservico(\\\"Players\\\")\\n\\t\\t\\t\\treturn navegar(SERVICOS_CLIENTE[baixo], partes, 2)\\n\\t\\t\\tend\\n\\n\\t\\t\\t-- demais contextos: acesso pelo servico real\\n\\t\\t\\treturn navegar(servico(canonico), partes, 2)\\n\\t\\tend\\n\\n\\t\\t-- 4) nome da propria arvore do GUI (cliente dentro de um ScreenGui):\\n\\t\\t--    `Jogar` vira _YashRaiz:WaitForChild(...) sem precisar de `usar`.\\n\\t\\t--    Se o nome for um dos ancestrais do script, parte dele; senao,\\n\\t\\t--    procura como filho de script.Parent (o ultimo nome do ancestral).\\n\\t\\tif ancestraGui and #ancestraGui > 0 and not semArvoreGui then\\n\\t\\t\\tusadoRaiz = true\\n\\t\\t\\tlocal codigo = \\\"_YashRaiz\\\"\\n\\t\\t\\tlocal corte = nil\\n\\t\\t\\tfor i = 1, #ancestraGui do\\n\\t\\t\\t\\tif ancestraGui[i] == primeiro then\\n\\t\\t\\t\\t\\tcorte = i\\n\\t\\t\\t\\t\\tbreak\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\tif corte then\\n\\t\\t\\t\\tfor i = 2, corte do\\n\\t\\t\\t\\t\\tcodigo = codigo .. ':WaitForChild(\\\"' .. ancestraGui[i] .. '\\\")'\\n\\t\\t\\t\\tend\\n\\t\\t\\telse\\n\\t\\t\\t\\tfor i = 2, #ancestraGui do\\n\\t\\t\\t\\t\\tcodigo = codigo .. ':WaitForChild(\\\"' .. ancestraGui[i] .. '\\\")'\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tcodigo = codigo .. ':WaitForChild(\\\"' .. primeiro .. '\\\")'\\n\\t\\t\\tend\\n\\t\\t\\tfor i = 2, #partes do\\n\\t\\t\\t\\tcodigo = codigo .. ':WaitForChild(\\\"' .. partes[i] .. '\\\")'\\n\\t\\t\\tend\\n\\t\\t\\treturn codigo\\n\\t\\tend\\n\\n\\t\\treturn nil, '\\\"' .. primeiro .. '\\\" nao e um alias declarado (`usar \\\"'\\n\\t\\t\\t.. primeiro .. '\\\" = ...`) nem um servico do Roblox'\\n\\tend\\n\\n\\t-----------------------------------------------------------------------\\n\\t-- valores e expressoes\\n\\t-----------------------------------------------------------------------\\n\\n\\tlocal gerarValor\\n\\n\\tlocal function gerarTupla(v, propYash)\\n\\t\\tif propYash ~= nil and PROPS_UDIM2[string.lower(propYash)] then\\n\\t\\t\\treturn \\\"UDim2.fromOffset(\\\" .. numeroLua(v.x) .. \\\", \\\" .. numeroLua(v.y) .. \\\")\\\"\\n\\t\\tend\\n\\t\\treturn \\\"Vector3.new(\\\" .. numeroLua(v.x) .. \\\", \\\" .. numeroLua(v.y)\\n\\t\\t\\t.. \\\", \\\" .. numeroLua(v.z or 0) .. \\\")\\\"\\n\\tend\\n\\n\\t-- resolve um nome/caminho usado como valor (alias, servico, arvore ou uma\\n\\t-- das locais que o proprio gerador cria, como o parametro do callback)\\n\\tlocal function gerarReferencia(v, semArvoreGui)\\n\\t\\tlocal nome = nil\\n\\t\\tif v.k == \\\"ident\\\" then\\n\\t\\t\\tnome = v.v\\n\\t\\telseif v.k == \\\"caminho\\\" and #v.partes == 1 then\\n\\t\\t\\tnome = v.partes[1]\\n\\t\\tend\\n\\t\\tif nome then\\n\\t\\t\\tif aliases[nome] then return aliases[nome] end\\n\\t\\t\\tif LOCAIS_GERADOS[nome] then return nome end\\n\\t\\tend\\n\\t\\tif v.k == \\\"ident\\\" then return resolverCaminho({ v.v }, semArvoreGui) end\\n\\t\\tif v.k == \\\"caminho\\\" then return resolverCaminho(v.partes, semArvoreGui) end\\n\\t\\treturn nil, \\\"nao e uma referencia: \\\" .. tostring(v.v or v.k)\\n\\tend\\n\\n\\t-- valor simples, sem depender do destino\\n\\tfunction gerarValor(v, propYash)\\n\\t\\tif v == nil then return nil, \\\"valor ausente\\\" end\\n\\t\\tlocal k = v.k\\n\\n\\t\\tif k == \\\"binario\\\" then\\n\\t\\t\\tlocal esquerda, err = gerarValor(v.esq, propYash)\\n\\t\\t\\tif not esquerda then return nil, err end\\n\\t\\t\\tlocal direita, e = gerarValor(v.dir, propYash)\\n\\t\\t\\tif not direita then return nil, e end\\n\\t\\t\\tlocal op = v.op\\n\\t\\t\\tif op == \\\"!=\\\" then op = \\\"~=\\\"\\n\\t\\t\\telseif op == \\\"e\\\" then op = \\\"and\\\"\\n\\t\\t\\telseif op == \\\"ou\\\" then op = \\\"or\\\" end\\n\\t\\t\\treturn \\\"(\\\" .. esquerda .. \\\" \\\" .. op .. \\\" \\\" .. direita .. \\\")\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"unario\\\" then\\n\\t\\t\\tlocal valor, err = gerarValor(v.valor, propYash)\\n\\t\\t\\tif not valor then return nil, err end\\n\\t\\t\\treturn \\\"(\\\" .. v.op .. \\\" \\\" .. valor .. \\\")\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"num\\\" then return numeroLua(v.v) end\\n\\t\\tif k == \\\"str\\\" then return textoLua(v.v) end\\n\\t\\tif k == \\\"bool\\\" then return tostring(v.v) end\\n\\t\\tif k == \\\"nulo\\\" then return \\\"nil\\\" end\\n\\t\\tif k == \\\"par\\\" then return gerarTupla(v, propYash) end\\n\\t\\tif k == \\\"cor\\\" then\\n\\t\\t\\treturn \\\"Color3.fromRGB(\\\" .. numeroLua(v.r) .. \\\", \\\" .. numeroLua(v.g)\\n\\t\\t\\t\\t.. \\\", \\\" .. numeroLua(v.b) .. \\\")\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"ident\\\" then\\n\\t\\t\\tif aliases[v.v] then return aliases[v.v] end\\n\\t\\t\\tif LOCAIS_GERADOS[v.v] then return v.v end\\n\\t\\t\\tif FUNCOES_LUAU[v.v] or GLOBAIS_LUAU[v.v] then return v.v end\\n\\t\\t\\treturn gerarReferencia(v)\\n\\t\\tend\\n\\t\\tif k == \\\"caminho\\\" then\\n\\t\\t\\tif ({ math = true, string = true, table = true, utf8 = true })[string.lower((v.partes or {})[1] or \\\"\\\")] then\\n\\t\\t\\t\\treturn table.concat(v.partes, \\\".\\\")\\n\\t\\t\\tend\\n\\t\\t\\t-- Caminhos podem terminar numa propriedade, não apenas num filho.\\n\\t\\t\\t-- Nomes em português como `jogador.vida` são normalizados aqui e na\\n\\t\\t\\t-- atribuição, mantendo a resolução normal de caminhos desconhecidos.\\n\\t\\t\\tlocal partes = v.partes or {}\\n\\t\\t\\tif #partes > 1 then\\n\\t\\t\\t\\tif objetosDados[partes[1]] and aliases[partes[1]] then\\n\\t\\t\\t\\t\\treturn aliases[partes[1]] .. \\\".\\\" .. partes[#partes]\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tlocal prop = partes[#partes]\\n\\t\\t\\t\\tlocal canon = PROPRIEDADES[string.lower(prop)]\\n\\t\\t\\t\\tif canon then\\n\\t\\t\\t\\t\\tlocal basePartes = {}\\n\\t\\t\\t\\t\\tfor i = 1, #partes - 1 do basePartes[i] = partes[i] end\\n\\t\\t\\t\\t\\tlocal base, err = gerarReferencia({ k = \\\"caminho\\\", partes = basePartes })\\n\\t\\t\\t\\t\\tif not base then return nil, err end\\n\\t\\t\\t\\t\\treturn base .. \\\".\\\" .. canon\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\treturn gerarReferencia(v)\\n\\t\\tend\\n\\t\\tif k == \\\"chamada\\\" then\\n\\t\\t\\tlocal alvo, err = gerarValor(v.alvo)\\n\\t\\t\\tif not alvo then return nil, err end\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tfor _, arg in ipairs(v.args or {}) do\\n\\t\\t\\t\\tlocal valor, e = gerarValor(arg)\\n\\t\\t\\t\\tif not valor then return nil, e end\\n\\t\\t\\t\\ttable.insert(args, valor)\\n\\t\\t\\tend\\n\\t\\t\\treturn alvo .. \\\"(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"metodo_expr\\\" then\\n\\t\\t\\tlocal base, err = gerarValor(v.base)\\n\\t\\t\\tif not base then return nil, err end\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tfor _, arg in ipairs(v.args or {}) do\\n\\t\\t\\t\\tlocal valor, e = gerarValor(arg)\\n\\t\\t\\t\\tif not valor then return nil, e end\\n\\t\\t\\t\\ttable.insert(args, valor)\\n\\t\\t\\tend\\n\\t\\t\\treturn base .. \\\":\\\" .. v.metodo .. \\\"(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"membro\\\" then\\n\\t\\t\\tlocal base, err = gerarValor(v.base)\\n\\t\\t\\tif not base then return nil, err end\\n\\t\\t\\tlocal membro = PROPRIEDADES[string.lower(v.nome)] or v.nome\\n\\t\\t\\treturn base .. \\\".\\\" .. membro\\n\\t\\tend\\n\\t\\tif k == \\\"indice\\\" then\\n\\t\\t\\tlocal base, err = gerarValor(v.base)\\n\\t\\t\\tif not base then return nil, err end\\n\\t\\t\\tlocal chave, e = gerarValor(v.chave)\\n\\t\\t\\tif not chave then return nil, e end\\n\\t\\t\\treturn base .. \\\"[\\\" .. chave .. \\\"]\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"tabela\\\" then\\n\\t\\t\\tlocal campos = {}\\n\\t\\t\\tfor _, campo in ipairs(v.campos or {}) do\\n\\t\\t\\t\\tlocal valor, err = gerarValor(campo.valor)\\n\\t\\t\\t\\tif not valor then return nil, err end\\n\\t\\t\\t\\tif campo.chave then\\n\\t\\t\\t\\t\\tlocal chave, e = gerarValor(campo.chave)\\n\\t\\t\\t\\t\\tif not chave then return nil, e end\\n\\t\\t\\t\\t\\ttable.insert(campos, \\\"[\\\" .. chave .. \\\"] = \\\" .. valor)\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\ttable.insert(campos, valor)\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\treturn \\\"{\\\" .. table.concat(campos, \\\", \\\") .. \\\"}\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"param\\\" then\\n\\t\\t\\treturn nil, \\\"parametro nomeado ainda nao traduzido no caminho direto (\\\"\\n\\t\\t\\t\\t.. tostring(v.nome) .. \\\" = ...)\\\"\\n\\t\\tend\\n\\t\\tif k == \\\"anim\\\" then\\n\\t\\t\\treturn nil, \\\"animacao composta ainda nao traduzida no caminho direto\\\"\\n\\t\\tend\\n\\t\\treturn nil, \\\"valor nao suportado: \\\" .. tostring(k)\\n\\tend\\n\\n\\t-----------------------------------------------------------------------\\n\\t-- animacoes (TweenService)\\n\\t-----------------------------------------------------------------------\\n\\n\\t-- texto simples de um parametro (numero, palavra ou texto)\\n\\tlocal function textoParametro(expr)\\n\\t\\tif not expr then return nil end\\n\\t\\tif expr.k == \\\"num\\\" then return numeroLua(expr.v) end\\n\\t\\tif expr.k == \\\"str\\\" then return expr.v end\\n\\t\\tif expr.k == \\\"ident\\\" then return expr.v end\\n\\t\\treturn nil\\n\\tend\\n\\n\\t-- normaliza o nome de um efeito e devolve o canonico (ou nil se desconhecido)\\n\\tlocal function canonizarEfeito(nome)\\n\\t\\tif type(nome) ~= \\\"string\\\" then return nil end\\n\\t\\tlocal l = string.lower(nome)\\n\\t\\tl = string.gsub(l, \\\"%s+\\\", \\\" \\\")\\n\\t\\tl = string.gsub(l, \\\"^%s+\\\", \\\"\\\")\\n\\t\\tl = string.gsub(l, \\\"%s+$\\\", \\\"\\\")\\n\\t\\treturn EFEITOS[l]\\n\\tend\\n\\n\\t-- classifica o valor rico (parseValor) numa especificacao de tween:\\n\\t-- { efeito, animacao, duracao, estilo, direcao, goals, eparams }\\n\\tlocal function specDeAnim(v, onde)\\n\\t\\tif not v then return nil, \\\"animacao ausente em \\\" .. onde end\\n\\t\\tlocal spec = { goals = {}, eparams = {} }\\n\\t\\tlocal params\\n\\n\\t\\tif v.k == \\\"anim\\\" then\\n\\t\\t\\tif v.efeito ~= \\\"\\\" then spec.efeito = v.efeito end\\n\\t\\t\\tparams = v.params or {}\\n\\t\\telseif v.k == \\\"param\\\" then\\n\\t\\t\\tparams = { [v.nome] = v.valor }\\n\\t\\telseif v.k == \\\"ident\\\" or v.k == \\\"str\\\" then\\n\\t\\t\\tspec.efeito = v.v\\n\\t\\t\\tparams = {}\\n\\t\\telse\\n\\t\\t\\treturn nil, \\\"efeito, propriedade ou animacao esperado em \\\" .. onde\\n\\t\\tend\\n\\n\\t\\tfor nome, valor in pairs(params) do\\n\\t\\t\\tlocal l = string.lower(nome)\\n\\t\\t\\tif l == \\\"duracao\\\" then\\n\\t\\t\\t\\tif not valor or valor.k ~= \\\"num\\\" then\\n\\t\\t\\t\\t\\treturn nil, \\\"duracao em \\\" .. onde .. \\\" precisa ser um numero\\\"\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tspec.duracao = valor.v\\n\\t\\t\\telseif l == \\\"estilo\\\" then\\n\\t\\t\\t\\tlocal s = textoParametro(valor)\\n\\t\\t\\t\\tif not s then return nil, \\\"estilo em \\\" .. onde .. \\\" precisa ser uma palavra\\\" end\\n\\t\\t\\t\\tspec.estilo = s\\n\\t\\t\\telseif l == \\\"direcao\\\" then\\n\\t\\t\\t\\tlocal s = textoParametro(valor)\\n\\t\\t\\t\\tif not s then return nil, \\\"direcao em \\\" .. onde .. \\\" precisa ser uma palavra\\\" end\\n\\t\\t\\t\\tspec.direcao = s\\n\\t\\t\\telseif l == \\\"animacao\\\" then\\n\\t\\t\\t\\tlocal s = textoParametro(valor)\\n\\t\\t\\t\\tif not s then return nil, \\\"animacao em \\\" .. onde .. \\\" precisa ser um nome\\\" end\\n\\t\\t\\t\\tspec.animacao = s\\n\\t\\t\\telseif l == \\\"delta\\\" or l == \\\"escala\\\" or l == \\\"graus\\\" then\\n\\t\\t\\t\\tif not valor or valor.k ~= \\\"num\\\" then\\n\\t\\t\\t\\t\\treturn nil, l .. \\\" em \\\" .. onde .. \\\" precisa ser um numero\\\"\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tspec.eparams[l] = valor.v\\n\\t\\t\\telseif PROPRIEDADES[l] ~= nil or identificadorValido(nome) then\\n\\t\\t\\t\\ttable.insert(spec.goals, { propYash = nome, expr = valor })\\n\\t\\t\\telse\\n\\t\\t\\t\\treturn nil, \\\"propriedade invalida `\\\" .. tostring(nome) .. \\\"` em \\\" .. onde\\n\\t\\t\\tend\\n\\t\\tend\\n\\n\\t\\tif spec.animacao and (spec.efeito or #spec.goals > 0 or next(spec.eparams) ~= nil) then\\n\\t\\t\\treturn nil, \\\"`animacao = <nome>` em \\\" .. onde\\n\\t\\t\\t\\t.. \\\" nao pode misturar com efeito ou propriedades\\\"\\n\\t\\tend\\n\\t\\treturn spec\\n\\tend\\n\\n\\t-- TweenInfo textual + duracao efetiva (padroes do legado: 0.3, Quad, Out)\\n\\tlocal function infoDeSpec(spec, onde, durOverride)\\n\\t\\tlocal dur = durOverride or spec.duracao or 0.3\\n\\t\\tlocal estilo = \\\"Quad\\\"\\n\\t\\tif spec.estilo then\\n\\t\\t\\tlocal e = string.lower(string.gsub(spec.estilo, \\\"%s+\\\", \\\"\\\"))\\n\\t\\t\\tlocal achado = ESTILOS_EASING[e]\\n\\t\\t\\tif not achado then\\n\\t\\t\\t\\tif identificadorValido(spec.estilo) then\\n\\t\\t\\t\\t\\tachado = spec.estilo\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\treturn nil, \\\"estilo de animacao desconhecido `\\\" .. tostring(spec.estilo)\\n\\t\\t\\t\\t\\t\\t.. \\\"` em \\\" .. onde\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\testilo = achado\\n\\t\\tend\\n\\t\\tlocal direcao = \\\"Out\\\"\\n\\t\\tif spec.direcao then\\n\\t\\t\\tlocal d = string.lower(string.gsub(spec.direcao, \\\"%s+\\\", \\\"\\\"))\\n\\t\\t\\tlocal achado = DIRECOES_EASING[d]\\n\\t\\t\\tif not achado then\\n\\t\\t\\t\\treturn nil, \\\"direcao de animacao desconhecida `\\\" .. tostring(spec.direcao)\\n\\t\\t\\t\\t\\t.. \\\"` em \\\" .. onde\\n\\t\\t\\tend\\n\\t\\t\\tdirecao = achado\\n\\t\\tend\\n\\t\\treturn \\\"TweenInfo.new(\\\" .. numeroLua(dur) .. \\\", Enum.EasingStyle.\\\" .. estilo\\n\\t\\t\\t.. \\\", Enum.EasingDirection.\\\" .. direcao .. \\\")\\\", dur\\n\\tend\\n\\n\\t-- traduz as metas de propriedade em pares ordenados { prop, val }\\n\\tlocal function goalsExtras(spec, onde)\\n\\t\\tlocal gs = {}\\n\\t\\tfor _, g in ipairs(spec.goals) do\\n\\t\\t\\tif g.expr.k == \\\"str\\\" or g.expr.k == \\\"bool\\\" or g.expr.k == \\\"nulo\\\" then\\n\\t\\t\\t\\treturn nil, \\\"tween de `\\\" .. g.propYash .. \\\"` em \\\" .. onde\\n\\t\\t\\t\\t\\t.. \\\" nao aceita texto/verdadeiro/nulo (use numero, tupla, cor ou referencia)\\\"\\n\\t\\t\\tend\\n\\t\\t\\tlocal prop = PROPRIEDADES[string.lower(g.propYash)] or g.propYash\\n\\t\\t\\tlocal val, err = gerarValor(g.expr, g.propYash)\\n\\t\\t\\tif not val then\\n\\t\\t\\t\\treturn nil, \\\"propriedade `\\\" .. g.propYash .. \\\"` em \\\" .. onde .. \\\": \\\" .. tostring(err)\\n\\t\\t\\tend\\n\\t\\t\\ttable.insert(gs, { prop = prop, val = val })\\n\\t\\tend\\n\\t\\ttable.sort(gs, function(a, b) return a.prop < b.prop end)\\n\\t\\treturn gs\\n\\tend\\n\\n\\t-- emite Create + Play de um tween puro; exige `local _YashAlvo` ja emitido\\n\\tlocal function emitirGoalsPlay(info, gs)\\n\\t\\temitir(\\\"local _YashTween = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. info .. \\\", {\\\")\\n\\t\\tfor _, g in ipairs(gs) do\\n\\t\\t\\temitir(\\\"\\\\t\\\" .. g.prop .. \\\" = \\\" .. g.val .. \\\",\\\")\\n\\t\\tend\\n\\t\\temitir(\\\"})\\\")\\n\\t\\temitir(\\\"_YashTween:Play()\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\t-- efeito fade in: aparece suavemente a partir de transparente.\\n\\t-- LayerCollector (ScreenGui) nao tem transparencia: vira so Enabled = true.\\n\\tlocal function efeitoFadeIn(info)\\n\\t\\temitir(\\\"local _YashG = {}\\\")\\n\\t\\temitir(\\\"if _YashAlvo:IsA(\\\\\\\"LayerCollector\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.Enabled = true\\\")\\n\\t\\temitir(\\\"elseif _YashAlvo:IsA(\\\\\\\"CanvasGroup\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.Visible = true\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.GroupTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.GroupTransparency = 0\\\")\\n\\t\\temitir(\\\"elseif _YashAlvo:IsA(\\\\\\\"ImageLabel\\\\\\\") or _YashAlvo:IsA(\\\\\\\"ImageButton\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.Visible = true\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.BackgroundTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.ImageTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.BackgroundTransparency = 0\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.ImageTransparency = 0\\\")\\n\\t\\temitir(\\\"elseif _YashAlvo:IsA(\\\\\\\"TextLabel\\\\\\\") or _YashAlvo:IsA(\\\\\\\"TextButton\\\\\\\") or _YashAlvo:IsA(\\\\\\\"TextBox\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.Visible = true\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.BackgroundTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.TextTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.BackgroundTransparency = 0\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.TextTransparency = 0\\\")\\n\\t\\temitir(\\\"else\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.Visible = true\\\")\\n\\t\\temitir(\\\"\\\\t_YashAlvo.BackgroundTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.BackgroundTransparency = 0\\\")\\n\\t\\temitir(\\\"end\\\")\\n\\t\\temitir(\\\"if next(_YashG) ~= nil then\\\")\\n\\t\\temitir(\\\"\\\\tlocal _YashTween = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. info .. \\\", _YashG)\\\")\\n\\t\\temitir(\\\"\\\\t_YashTween:Play()\\\")\\n\\t\\temitir(\\\"end\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\t-- efeito fade out: some suavemente e desliga a visibilidade no fim\\n\\tlocal function efeitoFadeOut(info, dur)\\n\\t\\temitir(\\\"local _YashG = {}\\\")\\n\\t\\temitir(\\\"if _YashAlvo:IsA(\\\\\\\"LayerCollector\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t-- LayerCollector nao tem transparencia: some so no fim\\\")\\n\\t\\temitir(\\\"elseif _YashAlvo:IsA(\\\\\\\"CanvasGroup\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.GroupTransparency = 1\\\")\\n\\t\\temitir(\\\"elseif _YashAlvo:IsA(\\\\\\\"ImageLabel\\\\\\\") or _YashAlvo:IsA(\\\\\\\"ImageButton\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.BackgroundTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.ImageTransparency = 1\\\")\\n\\t\\temitir(\\\"elseif _YashAlvo:IsA(\\\\\\\"TextLabel\\\\\\\") or _YashAlvo:IsA(\\\\\\\"TextButton\\\\\\\") or _YashAlvo:IsA(\\\\\\\"TextBox\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.BackgroundTransparency = 1\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.TextTransparency = 1\\\")\\n\\t\\temitir(\\\"else\\\")\\n\\t\\temitir(\\\"\\\\t_YashG.BackgroundTransparency = 1\\\")\\n\\t\\temitir(\\\"end\\\")\\n\\t\\temitir(\\\"if next(_YashG) ~= nil then\\\")\\n\\t\\temitir(\\\"\\\\tlocal _YashTween = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. info .. \\\", _YashG)\\\")\\n\\t\\temitir(\\\"\\\\t_YashTween:Play()\\\")\\n\\t\\temitir(\\\"end\\\")\\n\\t\\temitir(\\\"task.delay(\\\" .. numeroLua(dur + 0.05) .. \\\", function()\\\")\\n\\t\\temitir(\\\"\\\\tif _YashAlvo:IsA(\\\\\\\"LayerCollector\\\\\\\") then\\\")\\n\\t\\temitir(\\\"\\\\t\\\\t_YashAlvo.Enabled = false\\\")\\n\\t\\temitir(\\\"\\\\telse\\\")\\n\\t\\temitir(\\\"\\\\t\\\\t_YashAlvo.Visible = false\\\")\\n\\t\\temitir(\\\"\\\\tend\\\")\\n\\t\\temitir(\\\"end)\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\tlocal SLIDES = {\\n\\t\\t[\\\"slide left\\\"] = { eixo = \\\"X\\\", sinal = -1 },\\n\\t\\t[\\\"slide right\\\"] = { eixo = \\\"X\\\", sinal = 1 },\\n\\t\\t[\\\"slide up\\\"] = { eixo = \\\"Y\\\", sinal = -1 },\\n\\t\\t[\\\"slide down\\\"] = { eixo = \\\"Y\\\", sinal = 1 },\\n\\t}\\n\\n\\t-- efeito slide: desloca a posicao em um eixo a partir do valor atual\\n\\tlocal function efeitoSlide(info, spec, eixo, sinal)\\n\\t\\tlocal delta = spec.eparams.delta or 100\\n\\t\\tlocal op = (sinal < 0) and \\\" - \\\" or \\\" + \\\"\\n\\t\\tlocal x = \\\"_YashP.X.Scale, _YashP.X.Offset\\\"\\n\\t\\tlocal y = \\\"_YashP.Y.Scale, _YashP.Y.Offset\\\"\\n\\t\\tif eixo == \\\"X\\\" then\\n\\t\\t\\tx = x .. op .. numeroLua(delta)\\n\\t\\telse\\n\\t\\t\\ty = y .. op .. numeroLua(delta)\\n\\t\\tend\\n\\t\\temitir(\\\"local _YashP = _YashAlvo.Position\\\")\\n\\t\\temitir(\\\"local _YashTween = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. info .. \\\", {\\\")\\n\\t\\temitir(\\\"\\\\tPosition = UDim2.new(\\\" .. x .. \\\", \\\" .. y .. \\\"),\\\")\\n\\t\\temitir(\\\"})\\\")\\n\\t\\temitir(\\\"_YashTween:Play()\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\t-- efeito pulsar: cresce e volta ao tamanho original\\n\\tlocal function efeitoPulsar(spec, onde, info, dur)\\n\\t\\tlocal escala = spec.eparams.escala or 1.2\\n\\t\\tlocal infoMeia, e = infoDeSpec(spec, onde, dur / 2)\\n\\t\\tif not infoMeia then return nil, e end\\n\\t\\tlocal m = numeroLua(escala)\\n\\t\\temitir(\\\"local _YashTamanho = _YashAlvo.Size\\\")\\n\\t\\temitir(\\\"local _YashTween = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. info .. \\\", {\\\")\\n\\t\\temitir(\\\"\\\\tSize = UDim2.new(_YashTamanho.X.Scale * \\\" .. m .. \\\", _YashTamanho.X.Offset * \\\"\\n\\t\\t\\t.. m .. \\\", _YashTamanho.Y.Scale * \\\" .. m .. \\\", _YashTamanho.Y.Offset * \\\" .. m .. \\\"),\\\")\\n\\t\\temitir(\\\"})\\\")\\n\\t\\temitir(\\\"_YashTween:Play()\\\")\\n\\t\\temitir(\\\"task.delay(\\\" .. numeroLua(dur / 2) .. \\\", function()\\\")\\n\\t\\temitir(\\\"\\\\tlocal _YashMetade = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. infoMeia .. \\\", {\\\")\\n\\t\\temitir(\\\"\\\\t\\\\tSize = _YashTamanho,\\\")\\n\\t\\temitir(\\\"\\\\t})\\\")\\n\\t\\temitir(\\\"\\\\t_YashMetade:Play()\\\")\\n\\t\\temitir(\\\"end)\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\t-- efeito girar: soma graus (padrao 360) na rotacao atual\\n\\tlocal function efeitoGirar(info, spec)\\n\\t\\tlocal graus = spec.eparams.graus or 360\\n\\t\\temitir(\\\"local _YashTween = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. info .. \\\", {\\\")\\n\\t\\temitir(\\\"\\\\tRotation = _YashAlvo.Rotation + \\\" .. numeroLua(graus) .. \\\",\\\")\\n\\t\\temitir(\\\"})\\\")\\n\\t\\temitir(\\\"_YashTween:Play()\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\t-- efeito crescer/diminuir: multiplica o tamanho atual por um fator\\n\\tlocal function efeitoEscala(info, spec, fator)\\n\\t\\tlocal m = numeroLua(fator)\\n\\t\\temitir(\\\"local _YashTamanho = _YashAlvo.Size\\\")\\n\\t\\temitir(\\\"local _YashTween = \\\" .. servico(\\\"TweenService\\\") .. \\\":Create(_YashAlvo, \\\"\\n\\t\\t\\t.. info .. \\\", {\\\")\\n\\t\\temitir(\\\"\\\\tSize = UDim2.new(_YashTamanho.X.Scale * \\\" .. m .. \\\", _YashTamanho.X.Offset * \\\"\\n\\t\\t\\t.. m .. \\\", _YashTamanho.Y.Scale * \\\" .. m .. \\\", _YashTamanho.Y.Offset * \\\" .. m .. \\\"),\\\")\\n\\t\\temitir(\\\"})\\\")\\n\\t\\temitir(\\\"_YashTween:Play()\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\t-- emite o corpo de um efeito (exige `local _YashAlvo` ja emitido)\\n\\tlocal function emitirEfeito(ref, spec, onde)\\n\\t\\tlocal canon = canonizarEfeito(spec.efeito)\\n\\t\\tif not canon then\\n\\t\\t\\treturn nil, \\\"efeito de animacao desconhecido `\\\" .. tostring(spec.efeito)\\n\\t\\t\\t\\t.. \\\"` em \\\" .. onde\\n\\t\\tend\\n\\t\\tfor nome in pairs(spec.eparams) do\\n\\t\\t\\tif not EFEITO_PARAMS[canon][nome] then\\n\\t\\t\\t\\treturn nil, \\\"o efeito `\\\" .. canon .. \\\"` nao aceita o parametro `\\\"\\n\\t\\t\\t\\t\\t.. nome .. \\\"` em \\\" .. onde\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tlocal info, extra = infoDeSpec(spec, onde)\\n\\t\\tif not info then return nil, extra end\\n\\t\\tlocal dur = extra\\n\\t\\temitir(\\\"local _YashAlvo = \\\" .. ref)\\n\\t\\tlocal sl = SLIDES[canon]\\n\\t\\tif sl then\\n\\t\\t\\treturn efeitoSlide(info, spec, sl.eixo, sl.sinal)\\n\\t\\telseif canon == \\\"fade in\\\" then\\n\\t\\t\\treturn efeitoFadeIn(info)\\n\\t\\telseif canon == \\\"fade out\\\" then\\n\\t\\t\\treturn efeitoFadeOut(info, dur)\\n\\t\\telseif canon == \\\"pulsar\\\" then\\n\\t\\t\\treturn efeitoPulsar(spec, onde, info, dur)\\n\\t\\telseif canon == \\\"girar\\\" then\\n\\t\\t\\treturn efeitoGirar(info, spec)\\n\\t\\telseif canon == \\\"crescer\\\" then\\n\\t\\t\\treturn efeitoEscala(info, spec, spec.eparams.escala or 1.25)\\n\\t\\telseif canon == \\\"diminuir\\\" then\\n\\t\\t\\treturn efeitoEscala(info, spec, spec.eparams.escala or 0.75)\\n\\t\\tend\\n\\t\\treturn nil, \\\"efeito nao implementado: \\\" .. canon\\n\\tend\\n\\n\\t-- nome da funcao Luau gerada para uma animacao criada\\n\\tlocal function nomeFnAnim(nome)\\n\\t\\tlocal limpo = string.gsub(tostring(nome), \\\"[^%w_]\\\", \\\"_\\\")\\n\\t\\tif string.match(limpo, \\\"^%d\\\") then limpo = \\\"_\\\" .. limpo end\\n\\t\\treturn \\\"_YashAnim_\\\" .. limpo\\n\\tend\\n\\n\\tlocal function nomeFnAcao(nome)\\n\\t\\tlocal limpo = string.gsub(tostring(nome), \\\"[^%w_]\\\", \\\"_\\\")\\n\\t\\tif string.match(limpo, \\\"^%d\\\") then limpo = \\\"_\\\" .. limpo end\\n\\t\\treturn \\\"_YashAcao_\\\" .. limpo\\n\\tend\\n\\n\\t-- devolve o nome da funcao se a animacao foi criada no programa, senao nil\\n\\tlocal function animacaoCriada(nome)\\n\\t\\tif programa.animacoes and programa.animacoes[nome] then\\n\\t\\t\\treturn nomeFnAnim(nome)\\n\\t\\tend\\n\\t\\treturn nil\\n\\tend\\n\\n\\t-- aplica uma especificacao de tween no ref (string Luau ja resolvida).\\n\\t-- animacao criada -> task.spawn; efeito -> emissor de efeito;\\n\\t-- senao -> tween puro de propriedades.\\n\\tlocal function aplicarSpecNoRef(ref, spec, onde)\\n\\t\\tif spec.animacao then\\n\\t\\t\\tlocal fn = animacaoCriada(spec.animacao)\\n\\t\\t\\tif not fn then\\n\\t\\t\\t\\treturn nil, \\\"animacao `\\\" .. spec.animacao .. \\\"` nao existe (crie com `criar animacao \\\\\\\"\\\"\\n\\t\\t\\t\\t\\t.. spec.animacao .. \\\"\\\\\\\"`) em \\\" .. onde\\n\\t\\t\\tend\\n\\t\\t\\temitir(\\\"task.spawn(function() \\\" .. fn .. \\\"(\\\" .. ref .. \\\") end)\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\t\\temitir(\\\"do\\\")\\n\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\tif spec.efeito then\\n\\t\\t\\t\\treturn emitirEfeito(ref, spec, onde)\\n\\t\\t\\tend\\n\\t\\t\\tif next(spec.eparams) ~= nil then\\n\\t\\t\\t\\treturn nil, \\\"`delta`/`escala`/`graus` so valem junto de um efeito em \\\" .. onde\\n\\t\\t\\tend\\n\\t\\t\\tif #spec.goals == 0 then\\n\\t\\t\\t\\treturn nil, \\\"tween sem propriedades para animar em \\\" .. onde\\n\\t\\t\\tend\\n\\t\\t\\tlocal gs, gerr = goalsExtras(spec, onde)\\n\\t\\t\\tif not gs then return nil, gerr end\\n\\t\\t\\tlocal info, ierr = infoDeSpec(spec, onde)\\n\\t\\t\\tif not info then return nil, ierr end\\n\\t\\t\\temitir(\\\"local _YashAlvo = \\\" .. ref)\\n\\t\\t\\treturn emitirGoalsPlay(info, gs)\\n\\t\\tend)\\n\\t\\tif not blk then return nil, e end\\n\\t\\tanexar(blk)\\n\\t\\temitir(\\\"end\\\")\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\t-----------------------------------------------------------------------\\n\\t-- condicoes\\n\\t-----------------------------------------------------------------------\\n\\n\\tlocal function gerarCondicao(c)\\n\\t\\tif c == nil then return nil, \\\"condicao ausente\\\" end\\n\\t\\tlocal t = c.tipo\\n\\n\\t\\tif t == \\\"logica\\\" then\\n\\t\\t\\tlocal esq, err = gerarCondicao(c.esq)\\n\\t\\t\\tif not esq then return nil, err end\\n\\t\\t\\tlocal op = (c.op == \\\"ou\\\" or c.op == \\\"or\\\") and \\\"or\\\" or \\\"and\\\"\\n\\t\\t\\tlocal dir, e = gerarCondicao(c.dir)\\n\\t\\t\\tif not dir then return nil, e end\\n\\t\\t\\treturn \\\"(\\\" .. esq .. \\\" \\\" .. op .. \\\" \\\" .. dir .. \\\")\\\"\\n\\t\\telseif t == \\\"nao\\\" then\\n\\t\\t\\tlocal expr, err = gerarCondicao(c.cond)\\n\\t\\t\\tif not expr then return nil, err end\\n\\t\\t\\treturn \\\"(not \\\" .. expr .. \\\")\\\"\\n\\t\\telseif t == \\\"comp\\\" then\\n\\t\\t\\tlocal esq, err = gerarValor(c.esq)\\n\\t\\t\\tif not esq then return nil, err end\\n\\t\\t\\tlocal dir, e = gerarValor(c.dir)\\n\\t\\t\\tif not dir then return nil, e end\\n\\t\\t\\tlocal op = (c.op == \\\"!=\\\") and \\\"~=\\\" or c.op\\n\\t\\t\\treturn \\\"(\\\" .. esq .. \\\" \\\" .. op .. \\\" \\\" .. dir .. \\\")\\\"\\n\\t\\telseif t == \\\"truthy\\\" then\\n\\t\\t\\tlocal valor, err = gerarValor(c.valor)\\n\\t\\t\\tif not valor then return nil, err end\\n\\t\\t\\treturn \\\"(\\\" .. valor .. \\\" ~= nil and \\\" .. valor .. \\\" ~= false)\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"num\\\" then\\n\\t\\t\\tlocal partes = dividirCaminho(c.obj)\\n\\t\\t\\tlocal ref, err = resolverCaminho(partes)\\n\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\tlocal op = (c.op == \\\"!=\\\") and \\\"~=\\\" or c.op\\n\\t\\t\\treturn \\\"(\\\" .. ref .. \\\" \\\" .. op .. \\\" \\\" .. numeroLua(c.val) .. \\\")\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"estado\\\" then\\n\\t\\t\\tlocal ref, err = gerarReferencia({ k = \\\"ident\\\", v = c.el })\\n\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\tlocal valor = (c.oq == \\\"visivel\\\") and \\\"true\\\" or \\\"false\\\"\\n\\t\\t\\t-- mesma regra do comando de visibilidade: LayerCollector (ScreenGui e\\n\\t\\t\\t-- afins) expoe Enabled; o restante da GUI expoe Visible\\n\\t\\t\\treturn \\\"((function() local _YashVis = \\\" .. ref\\n\\t\\t\\t\\t.. \\\" if _YashVis:IsA(\\\\\\\"LayerCollector\\\\\\\") then return _YashVis.Enabled\\\"\\n\\t\\t\\t\\t.. \\\" else return _YashVis.Visible end end)() == \\\" .. valor .. \\\")\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"tecla\\\" then\\n\\t\\t\\treturn \\\"(\\\" .. servico(\\\"UserInputService\\\") .. \\\":IsKeyDown(Enum.KeyCode.\\\"\\n\\t\\t\\t\\t.. string.upper(c.tecla) .. \\\"))\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"dist\\\" then\\n\\t\\t\\tlocal a, err = gerarValor(c.aExpr or { k = \\\"ident\\\", v = c.a })\\n\\t\\t\\tif not a then return nil, err end\\n\\t\\t\\tlocal b, e = gerarValor(c.bExpr or { k = \\\"ident\\\", v = c.b })\\n\\t\\t\\tif not b then return nil, e end\\n\\t\\t\\tlocal op = c.op or \\\"<\\\"\\n\\t\\t\\tlocal raio = numeroLua(c.val or (c.raio and 10) or 0)\\n\\t\\t\\treturn \\\"((\\\" .. a .. \\\":GetPivot().Position - \\\" .. b .. \\\":GetPivot().Position).Magnitude \\\"\\n\\t\\t\\t\\t.. op .. \\\" \\\" .. raio .. \\\")\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"vida\\\" then\\n\\t\\t\\tlocal ref, err = gerarValor(c.alvoExpr or { k = \\\"ident\\\", v = c.alvo })\\n\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\tlocal compara = c.estado and \\\"> 0\\\" or \\\"<= 0\\\"\\n\\t\\t\\treturn \\\"((function() if type(\\\" .. ref .. \\\") == \\\\\\\"table\\\\\\\" then return (\\\" .. ref .. \\\".vida or 0) \\\" .. compara .. \\\" end; local _YashHumanoide = (\\\" .. ref\\n\\t\\t\\t\\t.. \\\"):IsA(\\\\\\\"Humanoid\\\\\\\") and \\\" .. ref .. \\\" or (\\\"\\n\\t\\t\\t\\t.. ref .. \\\"):IsA(\\\\\\\"Player\\\\\\\") and \\\" .. ref\\n\\t\\t\\t\\t.. \\\".Character and \\\" .. ref .. \\\".Character:FindFirstChildOfClass(\\\\\\\"Humanoid\\\\\\\") or (\\\"\\n\\t\\t\\t\\t.. ref .. \\\"):FindFirstChildOfClass(\\\\\\\"Humanoid\\\\\\\"); return _YashHumanoide ~= nil and _YashHumanoide.Health \\\"\\n\\t\\t\\t\\t.. compara .. \\\" end)())\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"tocar\\\" then\\n\\t\\t\\tlocal a, err = gerarValor(c.aExpr or { k = \\\"ident\\\", v = c.a })\\n\\t\\t\\tif not a then return nil, err end\\n\\t\\t\\tlocal b, e = gerarValor(c.bExpr or { k = \\\"ident\\\", v = c.b })\\n\\t\\t\\tif not b then return nil, e end\\n\\t\\t\\treturn \\\"((function() for _, _YashParte in ipairs(\\\" .. a .. \\\":GetTouchingParts()) do \\\"\\n\\t\\t\\t\\t.. \\\"if _YashParte == \\\" .. b .. \\\" or _YashParte:IsDescendantOf(\\\" .. b\\n\\t\\t\\t\\t.. \\\") or \\\" .. b .. \\\":IsDescendantOf(_YashParte) then return true end end; return false end)())\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"criado\\\" then\\n\\t\\t\\tif (programa.objetos and programa.objetos[c.nome])\\n\\t\\t\\t\\tor (programa.formas and programa.formas[c.nome])\\n\\t\\t\\t\\tor (programa.elementos and programa.elementos[c.nome]) then return \\\"true\\\" end\\n\\t\\t\\tlocal name = textoLua(c.nome)\\n\\t\\t\\treturn \\\"(game:FindFirstChild(\\\" .. name .. \\\", true) ~= nil)\\\"\\n\\t\\tend\\n\\n\\t\\treturn nil, \\\"condicao ainda nao traduzida no caminho direto: \\\" .. tostring(t)\\n\\tend\\n\\n\\t-----------------------------------------------------------------------\\n\\t-- comandos\\n\\t-----------------------------------------------------------------------\\n\\n\\t-- alvo do evento cujo corpo esta sendo renderizado agora (nil fora de eventos).\\n\\t-- Permite que `cor = rgb(...)` solto dentro de `quando clicar Botao` saiba em\\n\\t-- qual objeto a propriedade deve ser aplicada.\\n\\tlocal alvoEvento = nil\\n\\tlocal dentroFuncao = false\\n\\tlocal eventoAtual = nil\\n\\tlocal traduzindoProibicao = false\\n\\n\\t-- base de um `alvo` ou `objeto.propriedade`, resolvendo alias / arvore /\\n\\t-- servico / local do proprio gerador. `prop` volta nil quando o alvo e uma\\n\\t-- local simples (`Valor -= 1`).\\n\\tlocal function resolverBase(caminho)\\n\\t\\tlocal partes = dividirCaminho(caminho)\\n\\t\\tif #partes == 0 then\\n\\t\\t\\treturn nil, nil, \\\"atribuicao sem destino: \\\" .. tostring(caminho)\\n\\t\\tend\\n\\t\\tif #partes == 1 then\\n\\t\\t\\tlocal base, err = gerarReferencia({ k = \\\"ident\\\", v = partes[1] })\\n\\t\\t\\tif not base then return nil, nil, err end\\n\\t\\t\\treturn base, nil, nil\\n\\t\\tend\\n\\t\\tlocal basePartes = {}\\n\\t\\tfor i = 1, #partes - 1 do table.insert(basePartes, partes[i]) end\\n\\t\\tlocal prop = partes[#partes]\\n\\t\\tlocal base, err\\n\\t\\tif #basePartes == 1 and aliases[basePartes[1]] then\\n\\t\\t\\tbase = aliases[basePartes[1]]\\n\\t\\telse\\n\\t\\t\\tbase, err = resolverCaminho(basePartes)\\n\\t\\tend\\n\\t\\tif not base then return nil, nil, err end\\n\\t\\treturn base, prop, nil\\n\\tend\\n\\n\\t-- <obj>.<prop> = <valor>\\n\\tlocal function gerarAtribuicao(caminho, expr)\\n\\t\\tlocal partesAtrib = dividirCaminho(caminho)\\n\\t\\tlocal base, prop, err = resolverBase(caminho)\\n\\t\\tif not base then return nil, err end\\n\\n\\t\\t-- largura / altura mexem em uma dimensao do Size\\n\\t\\tif prop == \\\"largura\\\" or prop == \\\"altura\\\" then\\n\\t\\t\\tif expr and expr.k == \\\"num\\\" then\\n\\t\\t\\t\\tlocal eixo = (prop == \\\"largura\\\") and \\\"X\\\" or \\\"Y\\\"\\n\\t\\t\\t\\tlocal outro = (eixo == \\\"X\\\") and \\\"Y\\\" or \\\"X\\\"\\n\\t\\t\\t\\temitir(base .. \\\".Size = UDim2.new(\\\" .. base .. \\\".Size.\\\" .. eixo\\n\\t\\t\\t\\t\\t.. \\\".Scale, \\\" .. numeroLua(expr.v) .. \\\", \\\" .. base .. \\\".Size.\\\"\\n\\t\\t\\t\\t\\t.. outro .. \\\".Scale, \\\" .. base .. \\\".Size.\\\" .. outro .. \\\".Offset)\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend\\n\\t\\t\\treturn nil, prop .. \\\" espera um numero\\\"\\n\\t\\tend\\n\\n\\t\\tlocal destino = prop and ((partesAtrib[1] and objetosDados[partesAtrib[1]])\\n\\t\\t\\tand prop or PROPRIEDADES[string.lower(prop)] or prop) or nil\\n\\t\\tlocal prefixo = destino and (base .. \\\".\\\" .. destino) or base\\n\\n\\t\\t-- CameraType e uma propriedade Enum; aceite os nomes mais usados como\\n\\t\\t-- valores YashScript para evitar exigir sintaxe Luau no menu/camera.\\n\\t\\tif string.lower(prop or \\\"\\\") == \\\"cameratype\\\" and expr and expr.k == \\\"ident\\\" then\\n\\t\\t\\tlocal tiposCamera = { scriptable = \\\"Scriptable\\\", custom = \\\"Custom\\\", attach = \\\"Attach\\\", track = \\\"Track\\\", watch = \\\"Watch\\\" }\\n\\t\\t\\tlocal tipoCamera = tiposCamera[string.lower(tostring(expr.v))]\\n\\t\\t\\tif tipoCamera then\\n\\t\\t\\t\\temitir(prefixo .. \\\" = Enum.CameraType.\\\" .. tipoCamera)\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend\\n\\t\\tend\\n\\n\\t\\t-- propriedade booleana aceita os verbos do YashScript\\n\\t\\tif destino and PROPS_BOOL[string.lower(prop)] then\\n\\t\\t\\tlocal b = normalizarBool(expr)\\n\\t\\t\\tif b ~= nil then\\n\\t\\t\\t\\temitir(prefixo .. \\\" = \\\" .. tostring(b))\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend\\n\\t\\tend\\n\\n\\t\\tlocal valor, verr = gerarValor(expr, prop)\\n\\t\\tif not valor then return nil, verr end\\n\\t\\temitir(prefixo .. \\\" = \\\" .. valor)\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\tlocal function gerarCorpo(corpo, linhaBase)\\n\\t\\tif not corpo or #corpo == 0 then return \\\"\\\" end\\n\\t\\tfor _, cmd in ipairs(corpo) do\\n\\t\\t\\tlocal r, err = gerarComando(cmd, linhaBase)\\n\\t\\t\\tif r == nil then return nil, err end\\n\\t\\tend\\n\\t\\treturn \\\"\\\"\\n\\tend\\n\\n\\tfunction gerarComando(cmd, linhaBase)\\n\\t\\tlocal l = linhaBase or 0\\n\\t\\tlocal t = cmd.tipo\\n\\t\\tif eventoAtual and not traduzindoProibicao and cmd.norm then\\n\\t\\t\\tlocal normCmd = string.lower(string.gsub(cmd.norm, \\\"[%s%(%)]\\\", \\\"\\\"))\\n\\t\\t\\tfor _, p in ipairs(programa.proibicoes or {}) do\\n\\t\\t\\t\\tlocal normEvt = p.evt == \\\"clicar\\\" and \\\"clicar\\\" or p.evt\\n\\t\\t\\t\\tlocal normAlvo = tostring(p.alvo or \\\"\\\")\\n\\t\\t\\t\\tfor _, proibido in ipairs(p.comandos or {}) do\\n\\t\\t\\t\\t\\tlocal alvoCompat = eventoAtual.alvo == normAlvo and eventoAtual.tipo == normEvt\\n\\t\\t\\t\\t\\tlocal normProibido = string.lower(string.gsub(tostring(proibido), \\\"[%s%(%)]\\\", \\\"\\\"))\\n\\t\\t\\t\\t\\tif alvoCompat and normCmd == normProibido then\\n\\t\\t\\t\\t\\t\\tif not p.cond then\\n\\t\\t\\t\\t\\t\\t\\tif p.somente then\\n\\t\\t\\t\\t\\t\\t\\t\\tlocal somente = tostring(p.somente)\\n\\t\\t\\t\\t\\t\\t\\t\\tif eventoAtual.alvo == somente then return \\\"\\\" end\\n\\t\\t\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\t\\tlocal cond, err = gerarCondicao(p.cond)\\n\\t\\t\\t\\t\\t\\t\\tif not cond then return nil, err end\\n\\t\\t\\t\\t\\t\\t\\temitir(\\\"if not (\\\" .. cond .. \\\") then\\\")\\n\\t\\t\\t\\t\\t\\t\\ttraduzindoProibicao = true\\n\\t\\t\\t\\t\\t\\t\\tlocal ok, e = gerarComando(cmd, l)\\n\\t\\t\\t\\t\\t\\t\\ttraduzindoProibicao = false\\n\\t\\t\\t\\t\\t\\t\\tif not ok then return nil, e end\\n\\t\\t\\t\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\tend\\n\\n\\t\\tif t == \\\"log\\\" then\\n\\t\\t\\tif cmd.args then\\n\\t\\t\\t\\tlocal args = {}\\n\\t\\t\\t\\tfor _, arg in ipairs(cmd.args) do\\n\\t\\t\\t\\t\\tlocal codigo, err = gerarValor(arg)\\n\\t\\t\\t\\t\\tif not codigo then return nil, err or \\\"argumento inválido em print\\\" end\\n\\t\\t\\t\\t\\ttable.insert(args, codigo)\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\temitir(\\\"print(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend\\n\\t\\t\\tlocal v, err\\n\\t\\t\\tif cmd.expr then\\n\\t\\t\\t\\tv, err = gerarValor(cmd.expr)\\n\\t\\t\\telseif cmd.texto then\\n\\t\\t\\t\\tv = textoLua(cmd.texto)\\n\\t\\t\\tend\\n\\t\\t\\tif not v then return nil, err or \\\"print sem valor\\\" end\\n\\t\\t\\temitir(\\\"print(\\\" .. v .. \\\")\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"atrib\\\" then\\n\\t\\t\\tif cmd.op == \\\"=\\\" then\\n\\t\\t\\t\\treturn gerarAtribuicao(cmd.caminho, cmd.expr)\\n\\t\\t\\tend\\n\\t\\t\\t-- += / -= viram operacao Luau direta\\n\\t\\t\\tlocal base, prop, err = resolverBase(cmd.caminho)\\n\\t\\t\\tif not base then return nil, err end\\n\\t\\t\\tlocal valor, verr = gerarValor(cmd.expr)\\n\\t\\t\\tif not valor then return nil, verr end\\n\\t\\t\\tlocal partesAtrib = dividirCaminho(cmd.caminho)\\n\\t\\t\\tlocal destino = prop and ((objetosDados[partesAtrib[1]]) and prop\\n\\t\\t\\t\\tor PROPRIEDADES[string.lower(prop)] or prop) or nil\\n\\t\\t\\tlocal prefixo = destino and (base .. \\\".\\\" .. destino) or base\\n\\t\\t\\tlocal op = (cmd.op == \\\"+=\\\") and \\\"+\\\" or \\\"-\\\"\\n\\t\\t\\temitir(prefixo .. \\\" = \\\" .. prefixo .. \\\" \\\" .. op .. \\\" \\\" .. valor)\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"atrib_indice\\\" then\\n\\t\\t\\tlocal tabela, err = gerarValor(cmd.destino.base)\\n\\t\\t\\tif not tabela then return nil, err end\\n\\t\\t\\tlocal indice, e = gerarValor(cmd.destino.chave)\\n\\t\\t\\tif not indice then return nil, e end\\n\\t\\t\\tlocal valor, verr = gerarValor(cmd.expr)\\n\\t\\t\\tif not valor then return nil, verr end\\n\\t\\t\\tlocal atribuir = cmd.op == \\\"=\\\" and (\\\"_YashTabela[_YashIndice] = \\\" .. valor)\\n\\t\\t\\t\\tor (\\\"_YashTabela[_YashIndice] = _YashTabela[_YashIndice] \\\"\\n\\t\\t\\t\\t\\t.. (cmd.op == \\\"+=\\\" and \\\"+\\\" or \\\"-\\\") .. \\\" \\\" .. valor)\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal bloco, be = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashTabela = \\\" .. tabela)\\n\\t\\t\\t\\temitir(\\\"local _YashIndice = \\\" .. indice)\\n\\t\\t\\t\\temitir(atribuir)\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not bloco then return nil, be end\\n\\t\\t\\tanexar(bloco)\\n\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"variavel\\\" then\\n\\t\\t\\tif cmd.expr then return gerarAtribuicao(cmd.nome, cmd.expr) end\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"retornar\\\" then\\n\\t\\t\\tif not dentroFuncao then return nil, \\\"'retornar' só pode ser usado dentro de uma função\\\" end\\n\\t\\t\\tif not cmd.expr then emitir(\\\"do return nil end\\\"); return \\\"\\\" end\\n\\t\\t\\tlocal valor, err = gerarValor(cmd.expr)\\n\\t\\t\\tif not valor then return nil, err end\\n\\t\\t\\temitir(\\\"do return \\\" .. valor .. \\\" end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"expressao\\\" then\\n\\t\\t\\tlocal valor, err = gerarValor(cmd.expr)\\n\\t\\t\\tif not valor then return nil, err end\\n\\t\\t\\temitir(valor)\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"visivel\\\" then\\n\\t\\t\\tlocal ref, err\\n\\t\\t\\tif cmd.expr then\\n\\t\\t\\t\\tref, err = gerarReferencia(cmd.expr)\\n\\t\\t\\telse\\n\\t\\t\\t\\tref, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo })\\n\\t\\t\\tend\\n\\t\\t\\tif not ref then return nil, err end\\n\\n\\t\\t\\t-- sufixo `animacao = ...`: efeito/propriedades aplicados junto da\\n\\t\\t\\t-- visibilidade (ex: mostrar(Painel) animacao = fade in)\\n\\t\\t\\tlocal spec = nil\\n\\t\\t\\tif cmd.anim ~= nil then\\n\\t\\t\\t\\tlocal s, serr = specDeAnim(cmd.anim, (cmd.acao or \\\"visivel\\\") .. \\\"(...)\\\")\\n\\t\\t\\t\\tif not s then return nil, serr end\\n\\t\\t\\t\\tspec = s\\n\\t\\t\\tend\\n\\n\\t\\t\\t-- fade in em mostrar / fade out em esconder ja cuidam da\\n\\t\\t\\t-- visibilidade sozinhos: o bloco base nao e emitido\\n\\t\\t\\tlocal canonEfeito = (spec and spec.efeito) and canonizarEfeito(spec.efeito) or nil\\n\\t\\t\\tlocal soEfeito = (canonEfeito == \\\"fade in\\\" and cmd.acao == \\\"mostrar\\\")\\n\\t\\t\\t\\tor (canonEfeito == \\\"fade out\\\" and cmd.acao == \\\"esconder\\\")\\n\\t\\t\\tif soEfeito then\\n\\t\\t\\t\\treturn aplicarSpecNoRef(ref, spec, (cmd.acao or \\\"visivel\\\") .. \\\"(...)\\\")\\n\\t\\t\\tend\\n\\n\\t\\t\\t-- ScreenGui/SurfaceGui/BillboardGui (LayerCollector) usam Enabled;\\n\\t\\t\\t-- o restante da GUI usa Visible. A classe so existe em runtime,\\n\\t\\t\\t-- entao o gerador emite a escolha em runtime.\\n\\t\\t\\tlocal function corpoVisibilidade(prop)\\n\\t\\t\\t\\treturn function()\\n\\t\\t\\t\\t\\tif cmd.acao == \\\"alternar\\\" then\\n\\t\\t\\t\\t\\t\\temitir(prop .. \\\" = not \\\" .. prop)\\n\\t\\t\\t\\t\\telseif cmd.acao == \\\"mostrar\\\" then\\n\\t\\t\\t\\t\\t\\temitir(prop .. \\\" = true\\\")\\n\\t\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\t\\temitir(prop .. \\\" = false\\\")\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashVis = \\\" .. ref)\\n\\t\\t\\t\\temitir(\\\"if _YashVis:IsA(\\\\\\\"LayerCollector\\\\\\\") then\\\")\\n\\t\\t\\t\\tlocal s1, e1 = blocoNovo(nivel() + 1, corpoVisibilidade(\\\"_YashVis.Enabled\\\"))\\n\\t\\t\\t\\tif not s1 then return nil, e1 end\\n\\t\\t\\t\\tanexar(s1)\\n\\t\\t\\t\\temitir(\\\"else\\\")\\n\\t\\t\\t\\tlocal s2, e2 = blocoNovo(nivel() + 1, corpoVisibilidade(\\\"_YashVis.Visible\\\"))\\n\\t\\t\\t\\tif not s2 then return nil, e2 end\\n\\t\\t\\t\\tanexar(s2)\\n\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, e end\\n\\t\\t\\tanexar(blk)\\n\\t\\t\\temitir(\\\"end\\\")\\n\\n\\t\\t\\tif spec then\\n\\t\\t\\t\\tlocal ok, e = aplicarSpecNoRef(ref, spec, (cmd.acao or \\\"visivel\\\") .. \\\"(...)\\\")\\n\\t\\t\\t\\tif not ok then return nil, e end\\n\\t\\t\\tend\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"cena\\\" then\\n\\t\\t\\tlocal nome = textoLua(cmd.alvo)\\n\\t\\t\\tlocal workspace = servico(\\\"Workspace\\\")\\n\\t\\t\\tlocal players = servico(\\\"Players\\\")\\n\\t\\t\\tlocal ativo = cmd.acao ~= \\\"esconder\\\"\\n\\t\\t\\tlocal mudaTudo = cmd.acao == \\\"mudar\\\"\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashCenaAtual = \\\" .. nome)\\n\\t\\t\\t\\temitir(\\\"for _, _YashInstancia in ipairs(\\\" .. workspace .. \\\":GetDescendants()) do\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\tif _YashInstancia:GetAttribute(\\\\\\\"YashCena\\\\\\\") then\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\tlocal _YashMostrarCena = _YashInstancia:GetAttribute(\\\\\\\"YashCena\\\\\\\") == _YashCenaAtual\\\")\\n\\t\\t\\t\\tif mudaTudo then\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t\\\\tif _YashInstancia:IsA(\\\\\\\"GuiObject\\\\\\\") then _YashInstancia.Visible = _YashMostrarCena\\\")\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t\\\\telseif _YashInstancia:IsA(\\\\\\\"BasePart\\\\\\\") then _YashInstancia.Transparency = _YashMostrarCena and 0 or 1; _YashInstancia.CanCollide = _YashMostrarCena end\\\")\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t\\\\tif _YashMostrarCena and _YashInstancia:IsA(\\\\\\\"GuiObject\\\\\\\") then _YashInstancia.Visible = \\\" .. tostring(ativo))\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t\\\\telseif _YashMostrarCena and _YashInstancia:IsA(\\\\\\\"BasePart\\\\\\\") then _YashInstancia.Transparency = \\\" .. (ativo and \\\"0\\\" or \\\"1\\\") .. \\\"; _YashInstancia.CanCollide = \\\" .. tostring(ativo) .. \\\" end\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\temitir(\\\"\\\\tend\\\")\\n\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\temitir(\\\"local _YashJogador = \\\" .. players .. \\\".LocalPlayer\\\")\\n\\t\\t\\t\\temitir(\\\"local _YashGui = _YashJogador and _YashJogador:FindFirstChildOfClass(\\\\\\\"PlayerGui\\\\\\\")\\\")\\n\\t\\t\\t\\temitir(\\\"if _YashGui then for _, _YashInstancia in ipairs(_YashGui:GetDescendants()) do\\\")\\n\\t\\t\\t\\tif mudaTudo then\\n\\t\\t\\t\\t\\temitir(\\\"\\\\tif _YashInstancia:GetAttribute(\\\\\\\"YashCena\\\\\\\") then _YashInstancia.Visible = (_YashInstancia:GetAttribute(\\\\\\\"YashCena\\\\\\\") == _YashCenaAtual) end\\\")\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\temitir(\\\"\\\\tif _YashInstancia:GetAttribute(\\\\\\\"YashCena\\\\\\\") == _YashCenaAtual then _YashInstancia.Visible = \\\" .. tostring(ativo) .. \\\" end\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\temitir(\\\"end end\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, e end\\n\\t\\t\\tanexar(blk); emitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"prop\\\" then\\n\\t\\t\\t-- `nome = valor` solto dentro de um evento: aplica no alvo do evento\\n\\t\\t\\tif not alvoEvento then\\n\\t\\t\\t\\treturn nil, \\\"propriedade solta (\\\" .. tostring(cmd.propNome)\\n\\t\\t\\t\\t\\t.. \\\" = ...) so faz sentido dentro de um evento com alvo\\\"\\n\\t\\t\\tend\\n\\t\\t\\tif cmd.propNome == \\\"animacao\\\" then\\n\\t\\t\\t\\tlocal onde = \\\"animacao = ... (no evento de \\\" .. alvoEvento .. \\\")\\\"\\n\\t\\t\\t\\tlocal spec, serr = specDeAnim(cmd.expr, onde)\\n\\t\\t\\t\\tif not spec then return nil, serr end\\n\\t\\t\\t\\tlocal ref, err = gerarReferencia({ k = \\\"ident\\\", v = alvoEvento })\\n\\t\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\t\\treturn aplicarSpecNoRef(ref, spec, onde)\\n\\t\\t\\tend\\n\\t\\t\\treturn gerarAtribuicao(alvoEvento .. \\\".\\\" .. cmd.propNome, cmd.expr)\\n\\t\\tend\\n\\n\\t\\tif t == \\\"tween\\\" then\\n\\t\\t\\tlocal ref, err = gerarReferencia(cmd.expr)\\n\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\tlocal onde = \\\"animar(\\\" .. textoLua(cmd.alvo) .. \\\")\\\"\\n\\t\\t\\tlocal spec, serr = specDeAnim(cmd.valor, onde)\\n\\t\\t\\tif not spec then return nil, serr end\\n\\t\\t\\treturn aplicarSpecNoRef(ref, spec, onde)\\n\\t\\tend\\n\\n\\t\\tif t == \\\"animacao\\\" then\\n\\t\\t\\tif not alvoEvento then\\n\\t\\t\\t\\treturn nil, \\\"executar animacao so faz sentido dentro de um evento com alvo\\\"\\n\\t\\t\\t\\t\\t.. \\\"; para animar outro objeto use animar(\\\\\\\"<Alvo>\\\\\\\") animacao = \\\"\\n\\t\\t\\t\\t\\t.. tostring(cmd.nome)\\n\\t\\t\\tend\\n\\t\\t\\tlocal fn = animacaoCriada(cmd.nome)\\n\\t\\t\\tif not fn then\\n\\t\\t\\t\\treturn nil, \\\"animacao `\\\" .. tostring(cmd.nome) .. \\\"` nao existe (crie com `criar animacao \\\\\\\"\\\"\\n\\t\\t\\t\\t\\t.. tostring(cmd.nome) .. \\\"\\\\\\\"`)\\\"\\n\\t\\t\\tend\\n\\t\\t\\tlocal ref, err = gerarReferencia({ k = \\\"ident\\\", v = alvoEvento })\\n\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\temitir(\\\"task.spawn(function() \\\" .. fn .. \\\"(\\\" .. ref .. \\\") end)\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"acao\\\" then\\n\\t\\t\\tlocal fn = programa.acoes and programa.acoes[cmd.nome] and nomeFnAcao(cmd.nome)\\n\\t\\t\\tif not fn then return nil, \\\"acao `\\\" .. tostring(cmd.nome) .. \\\"` nao existe\\\" end\\n\\t\\t\\tlocal alvo = \\\"nil\\\"\\n\\t\\t\\tif alvoEvento then\\n\\t\\t\\t\\tlocal ref, err = gerarReferencia({ k = \\\"ident\\\", v = alvoEvento })\\n\\t\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\t\\talvo = ref\\n\\t\\t\\tend\\n\\t\\t\\temitir(fn .. \\\"(\\\" .. alvo .. \\\")\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"metodo\\\" then\\n\\t\\t\\t-- O alvo pode ser um alias simples (`Botao`) ou um caminho\\n\\t\\t\\t-- (`Workspace.Casa`); nos dois casos a base e resolvida pela mesma\\n\\t\\t\\t-- regra de referencias usada no resto do gerador.\\n\\t\\t\\tlocal alvoPartes = dividirCaminho(cmd.alvo or \\\"\\\")\\n\\t\\t\\tlocal ref, err\\n\\t\\t\\tif #alvoPartes > 1 then\\n\\t\\t\\t\\tref, err = resolverCaminho(alvoPartes)\\n\\t\\t\\telse\\n\\t\\t\\t\\tref, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo })\\n\\t\\t\\tend\\n\\t\\t\\tif not ref then return nil, err end\\n\\t\\t\\tlocal metodo = cmd.metodo\\n\\t\\t\\tif metodo == \\\"destruir\\\" or metodo == \\\"remover\\\" then metodo = \\\"Destroy\\\" end\\n\\t\\t\\tlocal args = {}\\n\\t\\t\\tfor _, valor in ipairs(cmd.args or {}) do\\n\\t\\t\\t\\tlocal codigo, e = gerarValor(valor)\\n\\t\\t\\t\\tif not codigo then return nil, e end\\n\\t\\t\\t\\ttable.insert(args, codigo)\\n\\t\\t\\tend\\n\\t\\t\\t-- Chamadas de método passam diretamente para Luau, permitindo acessar\\n\\t\\t\\t-- métodos Roblox sem manter uma lista fechada no compilador.\\n\\t\\t\\temitir(ref .. \\\":\\\" .. metodo .. \\\"(\\\" .. table.concat(args, \\\", \\\") .. \\\")\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"espera\\\" then\\n\\t\\t\\temitir(\\\"task.wait(\\\" .. numeroLua(cmd.valor or 0) .. \\\")\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"dano\\\" or t == \\\"curar\\\" or t == \\\"matar\\\" then\\n\\t\\t\\tlocal alvo, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo }, true)\\n\\t\\t\\tif not alvo then return nil, err end\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashAlvoVida = \\\" .. alvo)\\n\\t\\t\\t\\temitir(\\\"if type(_YashAlvoVida) == \\\\\\\"table\\\\\\\" and type(_YashAlvoVida.vida) == \\\\\\\"number\\\\\\\" then\\\")\\n\\t\\t\\t\\tif t == \\\"dano\\\" then\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t_YashAlvoVida.vida = math.max(0, _YashAlvoVida.vida - \\\" .. numeroLua(cmd.valor) .. \\\")\\\")\\n\\t\\t\\t\\telseif t == \\\"curar\\\" then\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t_YashAlvoVida.vida = math.min(_YashAlvoVida.vida_maxima or math.huge, _YashAlvoVida.vida + \\\" .. numeroLua(cmd.valor) .. \\\")\\\")\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t_YashAlvoVida.vida = 0\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\temitir(\\\"else\\\")\\n\\t\\t\\t\\temitir(\\\"local _YashHumanoide = (_YashAlvoVida:IsA(\\\\\\\"Humanoid\\\\\\\") and _YashAlvoVida) or (_YashAlvoVida:IsA(\\\\\\\"Player\\\\\\\") and _YashAlvoVida.Character and _YashAlvoVida.Character:FindFirstChildOfClass(\\\\\\\"Humanoid\\\\\\\")) or _YashAlvoVida:FindFirstChildOfClass(\\\\\\\"Humanoid\\\\\\\")\\\")\\n\\t\\t\\t\\temitir(\\\"if _YashHumanoide then\\\")\\n\\t\\t\\t\\tif t == \\\"dano\\\" then\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t_YashHumanoide:TakeDamage(\\\" .. numeroLua(cmd.valor) .. \\\")\\\")\\n\\t\\t\\t\\telseif t == \\\"curar\\\" then\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t_YashHumanoide.Health = math.clamp(_YashHumanoide.Health + \\\" .. numeroLua(cmd.valor) .. \\\", 0, _YashHumanoide.MaxHealth)\\\")\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t_YashHumanoide.Health = 0\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, e end\\n\\t\\t\\tanexar(blk); emitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"respawnar\\\" then\\n\\t\\t\\tlocal alvo, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo }, true)\\n\\t\\t\\tif not alvo then return nil, err end\\n\\t\\t\\tlocal players = servico(\\\"Players\\\")\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashAlvoVida = \\\" .. alvo)\\n\\t\\t\\t\\temitir(\\\"local _YashPlayer = (_YashAlvoVida:IsA(\\\\\\\"Player\\\\\\\") and _YashAlvoVida) or \\\" .. players .. \\\":GetPlayerFromCharacter(_YashAlvoVida) or \\\" .. players .. \\\":FindFirstChild(_YashAlvoVida.Name)\\\")\\n\\t\\t\\t\\temitir(\\\"if _YashPlayer then _YashPlayer:LoadCharacter() end\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, e end\\n\\t\\t\\tanexar(blk); emitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"teleportar\\\" then\\n\\t\\t\\tlocal alvo, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo }, true)\\n\\t\\t\\tif not alvo then return nil, err end\\n\\t\\t\\temitir(alvo .. \\\":PivotTo(CFrame.new(\\\" .. numeroLua(cmd.pos.x) .. \\\", \\\" .. numeroLua(cmd.pos.y) .. \\\", \\\" .. numeroLua(cmd.pos.z or 0) .. \\\"))\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"mover\\\" or t == \\\"rotacionar\\\" then\\n\\t\\t\\tlocal alvo, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo }, true)\\n\\t\\t\\tif not alvo then return nil, err end\\n\\t\\t\\tlocal tweenService = servico(\\\"TweenService\\\")\\n\\t\\t\\tlocal duracao = cmd.duracao or (20 / math.max(tonumber(cmd.velocidade) or 20, 0.1))\\n\\t\\t\\tlocal cf\\n\\t\\t\\tif t == \\\"mover\\\" then\\n\\t\\t\\t\\tcf = \\\"CFrame.new(\\\" .. numeroLua(cmd.para.x) .. \\\", \\\" .. numeroLua(cmd.para.y) .. \\\", \\\" .. numeroLua(cmd.para.z or 0) .. \\\")\\\"\\n\\t\\t\\telse\\n\\t\\t\\t\\tcf = \\\"CFrame.new(_YashAlvo:GetPivot().Position) * CFrame.Angles(math.rad(\\\" .. numeroLua(cmd.para.x) .. \\\"), math.rad(\\\" .. numeroLua(cmd.para.y) .. \\\"), math.rad(\\\" .. numeroLua(cmd.para.z or 0) .. \\\"))\\\"\\n\\t\\t\\tend\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashAlvo = \\\" .. alvo)\\n\\t\\t\\t\\temitir(\\\"local _YashInicio = _YashAlvo:GetPivot()\\\")\\n\\t\\t\\t\\tif t == \\\"mover\\\" then\\n\\t\\t\\t\\t\\temitir(\\\"local _YashDestino = CFrame.new(\\\" .. numeroLua(cmd.para.x) .. \\\", \\\" .. numeroLua(cmd.para.y) .. \\\", \\\" .. numeroLua(cmd.para.z or 0) .. \\\") * _YashInicio.Rotation\\\")\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\temitir(\\\"local _YashDestino = \\\" .. cf)\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\temitir(\\\"if _YashAlvo:IsA(\\\\\\\"BasePart\\\\\\\") then\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\tlocal _YashTween = \\\" .. tweenService .. \\\":Create(_YashAlvo, TweenInfo.new(\\\" .. numeroLua(duracao) .. \\\"), { CFrame = _YashDestino })\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t_YashTween:Play()\\\")\\n\\t\\t\\t\\temitir(\\\"else\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\ttask.spawn(function()\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\tlocal _YashInicioTempo = os.clock()\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\twhile _YashAlvo.Parent and os.clock() - _YashInicioTempo < \\\" .. numeroLua(duracao) .. \\\" do\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\t\\\\tlocal _YashAlpha = math.clamp((os.clock() - _YashInicioTempo) / math.max(\\\" .. numeroLua(duracao) .. \\\", 0.001), 0, 1)\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\t\\\\t_YashAlvo:PivotTo(_YashInicio:Lerp(_YashDestino, _YashAlpha))\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\t\\\\ttask.wait()\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\tend\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\t\\\\tif _YashAlvo.Parent then _YashAlvo:PivotTo(_YashDestino) end\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\tend)\\\")\\n\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, e end\\n\\t\\t\\tanexar(blk); emitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"som\\\" then\\n\\t\\t\\tlocal soundService = servico(\\\"SoundService\\\")\\n\\t\\t\\tlocal debris = servico(\\\"Debris\\\")\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir('local _YashSom = Instance.new(\\\"Sound\\\")')\\n\\t\\t\\t\\temitir('_YashSom.SoundId = \\\"rbxassetid://' .. tostring(cmd.id) .. '\\\"')\\n\\t\\t\\t\\temitir(\\\"_YashSom.Parent = \\\" .. soundService)\\n\\t\\t\\t\\temitir(\\\"_YashSom:Play()\\\")\\n\\t\\t\\t\\temitir(debris .. \\\":AddItem(_YashSom, 5)\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, e end\\n\\t\\t\\tanexar(blk); emitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"destruir\\\" then\\n\\t\\t\\tlocal alvo, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo }, true)\\n\\t\\t\\tif not alvo then return nil, err end\\n\\t\\t\\temitir(alvo .. \\\":Destroy()\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"sortear\\\" then\\n\\t\\t\\tlocal nome, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.nome })\\n\\t\\t\\tif not nome then return nil, err end\\n\\t\\t\\temitir(nome .. \\\" = math.random(\\\" .. numeroLua(cmd.min) .. \\\", \\\" .. numeroLua(cmd.max) .. \\\")\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"soma\\\" then\\n\\t\\t\\tlocal destinoPartes = dividirCaminho(cmd.para)\\n\\t\\t\\tlocal fontePartes = dividirCaminho(cmd.de)\\n\\t\\t\\tlocal destinoExpr = #destinoPartes > 1 and { k = \\\"caminho\\\", partes = destinoPartes } or { k = \\\"ident\\\", v = destinoPartes[1] }\\n\\t\\t\\tlocal fonteExpr = #fontePartes > 1 and { k = \\\"caminho\\\", partes = fontePartes } or { k = \\\"ident\\\", v = fontePartes[1] }\\n\\t\\t\\tlocal destino, err = gerarValor(destinoExpr)\\n\\t\\t\\tif not destino then return nil, err end\\n\\t\\t\\tlocal fonte, e = gerarValor(fonteExpr)\\n\\t\\t\\tif not fonte then return nil, e end\\n\\t\\t\\tlocal op = cmd.op == \\\"somar\\\" and \\\"+\\\" or \\\"-\\\"\\n\\t\\t\\temitir(destino .. \\\" = \\\" .. destino .. \\\" \\\" .. op .. \\\" \\\" .. fonte)\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"explodir\\\" then\\n\\t\\t\\tlocal alvo, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo }, true)\\n\\t\\t\\tif not alvo then return nil, err end\\n\\t\\t\\tlocal workspace = servico(\\\"Workspace\\\")\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir('local _YashExplosao = Instance.new(\\\"Explosion\\\")')\\n\\t\\t\\t\\temitir(\\\"_YashExplosao.Position = \\\" .. alvo .. \\\":GetPivot().Position\\\")\\n\\t\\t\\t\\temitir(\\\"_YashExplosao.BlastRadius = \\\" .. numeroLua(cmd.raio or 8))\\n\\t\\t\\t\\temitir(\\\"_YashExplosao.BlastPressure = \\\" .. numeroLua(cmd.dano or 50))\\n\\t\\t\\t\\temitir(\\\"_YashExplosao.Parent = \\\" .. workspace)\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, e end\\n\\t\\t\\tanexar(blk); emitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"seguir\\\" then\\n\\t\\t\\tlocal quem, err = gerarReferencia({ k = \\\"ident\\\", v = cmd.quem }, true)\\n\\t\\t\\tif not quem then return nil, err end\\n\\t\\t\\tlocal alvo, e = gerarReferencia({ k = \\\"ident\\\", v = cmd.alvo }, true)\\n\\t\\t\\tif not alvo then return nil, e end\\n\\t\\t\\temitir(\\\"task.spawn(function()\\\")\\n\\t\\t\\tlocal blk, be = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashQuem = \\\" .. quem)\\n\\t\\t\\t\\temitir(\\\"local _YashPersonagemAlvo = _YashQuem:IsA(\\\\\\\"Player\\\\\\\") and (_YashQuem.Character or _YashQuem.CharacterAdded:Wait()) or _YashQuem\\\")\\n\\t\\t\\t\\temitir(\\\"local _YashHumanoide = _YashPersonagemAlvo:IsA(\\\\\\\"Humanoid\\\\\\\") and _YashPersonagemAlvo or _YashPersonagemAlvo:FindFirstChildOfClass(\\\\\\\"Humanoid\\\\\\\")\\\")\\n\\t\\t\\t\\temitir(\\\"while _YashPersonagemAlvo.Parent and \\\" .. alvo .. \\\".Parent do\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\tif _YashHumanoide then _YashHumanoide:MoveTo(\\\" .. alvo .. \\\":GetPivot().Position) else _YashPersonagemAlvo:PivotTo(\\\" .. alvo .. \\\":GetPivot()) end\\\")\\n\\t\\t\\t\\temitir(\\\"\\\\ttask.wait(0.2)\\\")\\n\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, be end\\n\\t\\t\\tanexar(blk); emitir(\\\"end)\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"clonar\\\" then\\n\\t\\t\\tlocal origParts = dividirCaminho(cmd.origem)\\n\\t\\t\\tlocal paiParts = dividirCaminho(cmd.pai)\\n\\t\\t\\tlocal origem, err = gerarReferencia({ k = #origParts > 1 and \\\"caminho\\\" or \\\"ident\\\", partes = origParts, v = origParts[1] })\\n\\t\\t\\tif not origem then return nil, err end\\n\\t\\t\\tlocal pai, e = gerarReferencia({ k = #paiParts > 1 and \\\"caminho\\\" or \\\"ident\\\", partes = paiParts, v = paiParts[1] })\\n\\t\\t\\tif not pai then return nil, e end\\n\\t\\t\\tlocal clone = cmd.nome and aliases[cmd.nome] or \\\"_YashInstanciaClonada\\\"\\n\\t\\t\\tif cmd.nome and not clone then return nil, \\\"variavel de destino do clonar nao foi declarada: \\\" .. tostring(cmd.nome) end\\n\\t\\t\\temitir(\\\"do\\\")\\n\\t\\t\\tlocal blk, be = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\temitir(\\\"local _YashCopiaTemp = \\\" .. origem .. \\\":Clone()\\\")\\n\\t\\t\\t\\temitir(\\\"if _YashCopiaTemp then\\\")\\n\\t\\t\\t\\tif cmd.nome then\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t\\\" .. clone .. \\\" = _YashCopiaTemp\\\")\\n\\t\\t\\t\\t\\temitir(\\\"\\\\t\\\" .. clone .. \\\".Name = \\\" .. textoLua(cmd.nome))\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\temitir(\\\"\\\\t_YashCopiaTemp.Parent = \\\" .. pai)\\n\\t\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\t\\treturn \\\"\\\"\\n\\t\\t\\tend)\\n\\t\\t\\tif not blk then return nil, be end\\n\\t\\t\\tanexar(blk); emitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"se\\\" then\\n\\t\\t\\tlocal cond, err = gerarCondicao(cmd.cond)\\n\\t\\t\\tif not cond then return nil, err end\\n\\t\\t\\temitir(\\\"if \\\" .. cond .. \\\" then\\\")\\n\\t\\t\\tlocal corpo, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\treturn gerarCorpo(cmd.corpo, l)\\n\\t\\t\\tend)\\n\\t\\t\\tif not corpo then return nil, e end\\n\\t\\t\\tanexar(corpo)\\n\\t\\t\\tfor _, alternativa in ipairs(cmd.alternativas or {}) do\\n\\t\\t\\t\\tlocal condAlternativa, errAlternativa = gerarCondicao(alternativa.cond)\\n\\t\\t\\t\\tif not condAlternativa then return nil, errAlternativa end\\n\\t\\t\\t\\temitir(\\\"elseif \\\" .. condAlternativa .. \\\" then\\\")\\n\\t\\t\\t\\tlocal ramo, erroRamo = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\t\\treturn gerarCorpo(alternativa.corpo, l)\\n\\t\\t\\t\\tend)\\n\\t\\t\\t\\tif not ramo then return nil, erroRamo end\\n\\t\\t\\t\\tanexar(ramo)\\n\\t\\t\\tend\\n\\t\\t\\tif cmd.senao and #cmd.senao > 0 then\\n\\t\\t\\t\\temitir(\\\"else\\\")\\n\\t\\t\\t\\tlocal sen, e2 = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\t\\treturn gerarCorpo(cmd.senao, l)\\n\\t\\t\\t\\tend)\\n\\t\\t\\t\\tif not sen then return nil, e2 end\\n\\t\\t\\t\\tanexar(sen)\\n\\t\\t\\tend\\n\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"enquanto\\\" then\\n\\t\\t\\tlocal cond, err = gerarCondicao(cmd.cond)\\n\\t\\t\\tif not cond then return nil, err end\\n\\t\\t\\temitir(\\\"while \\\" .. cond .. \\\" do\\\")\\n\\t\\t\\tlocal corpo, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\treturn gerarCorpo(cmd.corpo, l)\\n\\t\\t\\tend)\\n\\t\\t\\tif not corpo then return nil, e end\\n\\t\\t\\tanexar(corpo)\\n\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"repita\\\" then\\n\\t\\t\\tlocal cond, err = gerarCondicao(cmd.cond)\\n\\t\\t\\tif not cond then return nil, err end\\n\\t\\t\\temitir(\\\"repeat\\\")\\n\\t\\t\\tlocal corpo, e = blocoNovo(nivel() + 1, function()\\n\\t\\t\\t\\treturn gerarCorpo(cmd.corpo, l)\\n\\t\\t\\tend)\\n\\t\\t\\tif not corpo then return nil, e end\\n\\t\\t\\tanexar(corpo)\\n\\t\\t\\temitir(\\\"until \\\" .. cond)\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"pare\\\" then emitir(\\\"break\\\"); return \\\"\\\" end\\n\\t\\tif t == \\\"continuar\\\" then emitir(\\\"continue\\\"); return \\\"\\\" end\\n\\n\\t\\tif t == \\\"para\\\" then\\n\\t\\t\\tif not identificadorValido(cmd.nome) then return nil, \\\"nome inválido no laço 'para': \\\" .. tostring(cmd.nome) end\\n\\t\\t\\tlocal inicio, err = gerarValor(cmd.inicio)\\n\\t\\t\\tif not inicio then return nil, err end\\n\\t\\t\\tlocal limite, e = gerarValor(cmd.limite)\\n\\t\\t\\tif not limite then return nil, e end\\n\\t\\t\\tlocal passo, pe = gerarValor(cmd.passo)\\n\\t\\t\\tif not passo then return nil, pe end\\n\\t\\t\\tlocal aliasAnterior, localAnterior = aliases[cmd.nome], LOCAIS_GERADOS[cmd.nome]\\n\\t\\t\\taliases[cmd.nome] = cmd.nome\\n\\t\\t\\tLOCAIS_GERADOS[cmd.nome] = true\\n\\t\\t\\temitir(\\\"for \\\" .. cmd.nome .. \\\" = \\\" .. inicio .. \\\", \\\" .. limite .. \\\", \\\" .. passo .. \\\" do\\\")\\n\\t\\t\\tlocal corpo, ce = blocoNovo(nivel() + 1, function() return gerarCorpo(cmd.corpo, l) end)\\n\\t\\t\\taliases[cmd.nome], LOCAIS_GERADOS[cmd.nome] = aliasAnterior, localAnterior\\n\\t\\t\\tif not corpo then return nil, ce end\\n\\t\\t\\tanexar(corpo)\\n\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\tif t == \\\"para_cada\\\" then\\n\\t\\t\\tlocal colecao, err = gerarValor(cmd.colecao)\\n\\t\\t\\tif not colecao then return nil, err end\\n\\t\\t\\tlocal nomes = cmd.nomes or {}\\n\\t\\t\\tlocal anterior, locais = {}, {}\\n\\t\\t\\tfor _, nome in ipairs(nomes) do\\n\\t\\t\\t\\tif not identificadorValido(nome) then return nil, \\\"nome inválido no laço 'para cada': \\\" .. tostring(nome) end\\n\\t\\t\\t\\tanterior[nome], locais[nome] = aliases[nome], LOCAIS_GERADOS[nome]\\n\\t\\t\\t\\taliases[nome], LOCAIS_GERADOS[nome] = nome, true\\n\\t\\t\\tend\\n\\t\\t\\tlocal iterador = cmd.iterador == \\\"pairs\\\" and \\\"pairs\\\" or \\\"ipairs\\\"\\n\\t\\t\\tlocal variaveis = #nomes == 2 and table.concat(nomes, \\\", \\\") or (\\\"_, \\\" .. tostring(nomes[1]))\\n\\t\\t\\temitir(\\\"for \\\" .. variaveis .. \\\" in \\\" .. iterador .. \\\"(\\\" .. colecao .. \\\") do\\\")\\n\\t\\t\\tlocal corpo, ce = blocoNovo(nivel() + 1, function() return gerarCorpo(cmd.corpo, l) end)\\n\\t\\t\\tfor _, nome in ipairs(nomes) do aliases[nome], LOCAIS_GERADOS[nome] = anterior[nome], locais[nome] end\\n\\t\\t\\tif not corpo then return nil, ce end\\n\\t\\t\\tanexar(corpo)\\n\\t\\t\\temitir(\\\"end\\\")\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend\\n\\n\\t\\t-- construcoes legadas ainda nao migradas: erro explicito (fila de migracao)\\n\\t\\treturn nil, \\\"construcao ainda nao traduzida para Luau direto: \\\" .. tostring(t)\\n\\tend\\n\\n\\t-----------------------------------------------------------------------\\n\\t-- topo do programa\\n\\t-----------------------------------------------------------------------\\n\\n\\t-- Materializa as construções estáticas restantes em instâncias Luau nativas.\\n\\tlocal inicializadores = {}\\n\\tlocal varsCriadas = {}\\n\\tlocal function nomeInterno(prefixo, nome)\\n\\t\\tlocal limpo = string.gsub(tostring(nome), \\\"[^%w_]\\\", \\\"_\\\")\\n\\t\\tif string.match(limpo, \\\"^%d\\\") then limpo = \\\"_\\\" .. limpo end\\n\\t\\treturn prefixo .. limpo\\n\\tend\\n\\tlocal function legadoLua(v, prop, gui)\\n\\t\\tif type(v) == \\\"number\\\" then return numeroLua(v) end\\n\\t\\tif type(v) == \\\"boolean\\\" then return tostring(v) end\\n\\t\\tif type(v) == \\\"table\\\" then\\n\\t\\t\\tif v.t == \\\"cor\\\" then return \\\"Color3.fromRGB(\\\" .. numeroLua(v.r) .. \\\", \\\" .. numeroLua(v.g) .. \\\", \\\" .. numeroLua(v.b) .. \\\")\\\" end\\n\\t\\t\\tif v.t == \\\"par\\\" then\\n\\t\\t\\t\\tif gui then return \\\"UDim2.fromOffset(\\\" .. numeroLua(v.x) .. \\\", \\\" .. numeroLua(v.y) .. \\\")\\\" end\\n\\t\\t\\t\\treturn \\\"Vector3.new(\\\" .. numeroLua(v.x) .. \\\", \\\" .. numeroLua(v.y) .. \\\", \\\" .. numeroLua(v.z or 0) .. \\\")\\\"\\n\\t\\t\\tend\\n\\t\\t\\treturn nil\\n\\t\\tend\\n\\t\\tif type(v) ~= \\\"string\\\" then return nil end\\n\\t\\tlocal l = string.lower(v)\\n\\t\\tif l == \\\"verdadeiro\\\" or l == \\\"sim\\\" or l == \\\"true\\\" then return \\\"true\\\" end\\n\\t\\tif l == \\\"falso\\\" or l == \\\"nao\\\" or l == \\\"false\\\" then return \\\"false\\\" end\\n\\t\\tlocal cores = { white = \\\"Color3.new(1, 1, 1)\\\", preto = \\\"Color3.new(0, 0, 0)\\\", black = \\\"Color3.new(0, 0, 0)\\\", branco = \\\"Color3.new(1, 1, 1)\\\" }\\n\\t\\tif cores[l] and (prop == \\\"cor\\\" or prop == \\\"cor_texto\\\" or prop == \\\"cor_borda\\\" or prop == \\\"fundo\\\") then return cores[l] end\\n\\t\\tif prop == \\\"material\\\" then\\n\\t\\t\\tlocal materiais = { grama = \\\"Grass\\\", concreto = \\\"Concrete\\\", madeira = \\\"Wood\\\", metal = \\\"Metal\\\", vidro = \\\"Glass\\\", plastico = \\\"Plastic\\\", areia = \\\"Sand\\\", agua = \\\"Water\\\", pedra = \\\"Slate\\\", gelo = \\\"Ice\\\" }\\n\\t\\t\\treturn \\\"Enum.Material.\\\" .. (materiais[l] or v)\\n\\t\\tend\\n\\t\\tif prop == \\\"fonte\\\" then\\n\\t\\t\\tlocal fontes = { arial = \\\"Arial\\\", gothic = \\\"Gotham\\\", gotham = \\\"Gotham\\\", code = \\\"Code\\\", cartoony = \\\"Cartoon\\\", cartoon = \\\"Cartoon\\\", sci_fi = \\\"SciFi\\\", scifi = \\\"SciFi\\\", fantasy = \\\"Fantasy\\\" }\\n\\t\\t\\treturn \\\"Enum.Font.\\\" .. (fontes[l] or v)\\n\\t\\tend\\n\\t\\treturn textoLua(v)\\n\\tend\\n\\tlocal function mesclar(estilo, props)\\n\\t\\tlocal r = {}\\n\\t\\tfor k, v in pairs(estilo or {}) do r[k] = v end\\n\\t\\tfor k, v in pairs(props or {}) do r[k] = v end\\n\\t\\treturn r\\n\\tend\\n\\tlocal function cenaVisivel(nome)\\n\\t\\tlocal def = nome and programa.cenas and programa.cenas[nome]\\n\\t\\tlocal v = def and def.mostrar\\n\\t\\tif v == nil then return true end\\n\\t\\tif type(v) == \\\"boolean\\\" then return v end\\n\\t\\tif type(v) == \\\"string\\\" then\\n\\t\\t\\tlocal l = string.lower(v)\\n\\t\\t\\treturn not (l == \\\"falso\\\" or l == \\\"nao\\\" or l == \\\"false\\\")\\n\\t\\tend\\n\\t\\treturn v ~= false\\n\\tend\\n\\tlocal elementosOrdem = {}\\n\\tfor _, nome in ipairs(programa.ordem_elementos or {}) do\\n\\t\\tif programa.elementos and programa.elementos[nome] then table.insert(elementosOrdem, nome) end\\n\\tend\\n\\tlocal incluidos = {}\\n\\tfor _, nome in ipairs(elementosOrdem) do incluidos[nome] = true end\\n\\t-- sobras (sem ordem deterministica): pares() sem ordem deixaria a saida nao-deterministica\\n\\tfor _, nome in ipairs(nomesOrdenados(programa.elementos)) do\\n\\t\\tif not incluidos[nome] then table.insert(elementosOrdem, nome) end\\n\\tend\\n\\tlocal aliasesDeclarados = {}\\n\\tfor _, alias in ipairs(programa.aliases or {}) do aliasesDeclarados[alias.nome] = true end\\n\\tlocal nomesFuncoes = {}\\n\\tfor nome in pairs(programa.funcoes or {}) do\\n\\t\\tif aliasesDeclarados[nome] then return false, { erro = \\\"função conflita com alias usar: \\\" .. nome, linha = 0 } end\\n\\t\\tif not identificadorValido(nome) then return false, { erro = \\\"nome de função inválido para Luau: \\\" .. tostring(nome), linha = 0 } end\\n\\t\\tif SERVICOS[string.lower(nome)] then return false, { erro = \\\"nome de função conflita com serviço Roblox: \\\" .. nome, linha = 0 } end\\n\\t\\tfor _, declaracoesNomes in ipairs({ programa.elementos or {}, programa.formas or {}, programa.objetos or {}, programa.huds or {} }) do\\n\\t\\t\\tif declaracoesNomes[nome] then return false, { erro = \\\"nome de função conflita com objeto declarado: \\\" .. nome, linha = 0 } end\\n\\t\\tend\\n\\t\\tlocal interno = nomeInterno(\\\"_YashFunc_\\\", nome)\\n\\t\\tif aliases[nome] then return false, { erro = \\\"nome de função conflita com outro identificador: \\\" .. nome, linha = 0 } end\\n\\t\\taliases[nome] = interno\\n\\t\\tLOCAIS_GERADOS[interno] = true\\n\\t\\ttable.insert(nomesFuncoes, nome)\\n\\tend\\n\\ttable.sort(nomesFuncoes)\\n\\tlocal function coletarLocaisFuncao(corpo, nomes)\\n\\t\\tfor _, cmd in ipairs(corpo or {}) do\\n\\t\\t\\tif cmd.tipo == \\\"variavel\\\" or cmd.tipo == \\\"sortear\\\" then nomes[cmd.nome] = true end\\n\\t\\t\\tif cmd.tipo == \\\"clonar\\\" and cmd.nome then nomes[cmd.nome] = true end\\n\\t\\t\\tif cmd.corpo then coletarLocaisFuncao(cmd.corpo, nomes) end\\n\\t\\t\\tif cmd.senao then coletarLocaisFuncao(cmd.senao, nomes) end\\n\\t\\t\\tfor _, alternativa in ipairs(cmd.alternativas or {}) do\\n\\t\\t\\t\\tcoletarLocaisFuncao(alternativa.corpo, nomes)\\n\\t\\t\\tend\\n\\t\\tend\\n\\tend\\n\\tlocal function gerarCorpoComLocais(corpoAst, nivelCorpo, renderizar, contexto)\\n\\t\\tlocal nomesSet, nomes = {}, {}\\n\\t\\tcoletarLocaisFuncao(corpoAst, nomesSet)\\n\\t\\tlocal aliasesSalvos, locaisSalvos = {}, {}\\n\\t\\tfor nome in pairs(nomesSet) do\\n\\t\\t\\tif not identificadorValido(nome) then\\n\\t\\t\\t\\treturn nil, \\\"variável local inválida para Luau\\\" .. (contexto and \\\" em `\\\" .. contexto .. \\\"`\\\" or \\\"\\\") .. \\\": \\\" .. tostring(nome)\\n\\t\\t\\tend\\n\\t\\t\\taliasesSalvos[nome] = aliases[nome]\\n\\t\\t\\tlocaisSalvos[nome] = LOCAIS_GERADOS[nome]\\n\\t\\t\\taliases[nome] = nome\\n\\t\\t\\tLOCAIS_GERADOS[nome] = true\\n\\t\\t\\ttable.insert(nomes, nome)\\n\\t\\tend\\n\\t\\ttable.sort(nomes)\\n\\t\\tlocal corpo, err = blocoNovo(nivelCorpo, renderizar)\\n\\t\\tfor _, nome in ipairs(nomes) do\\n\\t\\t\\taliases[nome] = aliasesSalvos[nome]\\n\\t\\t\\tLOCAIS_GERADOS[nome] = locaisSalvos[nome]\\n\\t\\tend\\n\\t\\tif not corpo then return nil, err end\\n\\t\\tif #nomes > 0 then\\n\\t\\t\\ttable.insert(corpo, 1, string.rep(\\\"\\\\t\\\", nivelCorpo) .. \\\"local \\\" .. table.concat(nomes, \\\", \\\"))\\n\\t\\tend\\n\\t\\treturn corpo\\n\\tend\\n\\tlocal variaveisDeclaradas = {}\\n\\tlocal variaveisSortear = {}\\n\\tlocal variaveisClonar = {}\\n\\tlocal function coletarVariaveis(corpo)\\n\\t\\tfor _, cmd in ipairs(corpo or {}) do\\n\\t\\t\\tif cmd.tipo == \\\"variavel\\\" then variaveisDeclaradas[cmd.nome] = true end\\n\\t\\t\\tif cmd.tipo == \\\"sortear\\\" then variaveisSortear[cmd.nome] = true end\\n\\t\\t\\tif cmd.tipo == \\\"clonar\\\" and cmd.nome then variaveisClonar[cmd.nome] = true end\\n\\t\\t\\tif cmd.corpo then coletarVariaveis(cmd.corpo) end\\n\\t\\t\\tif cmd.senao then coletarVariaveis(cmd.senao) end\\n\\t\\t\\tfor _, alternativa in ipairs(cmd.alternativas or {}) do\\n\\t\\t\\t\\tcoletarVariaveis(alternativa.corpo)\\n\\t\\t\\tend\\n\\t\\tend\\n\\tend\\n\\tcoletarVariaveis(programa.comandos)\\n\\tfor _, ev in ipairs(programa.eventos or {}) do\\n\\t\\tif EVENTOS_INLINE[ev.tipo] then coletarVariaveis(ev.corpo) end\\n\\tend\\n\\tfor _, ev in ipairs(programa.continuos or {}) do\\n\\t\\tcoletarVariaveis(ev.corpo); coletarVariaveis(ev.senao)\\n\\t\\tfor _, alternativa in ipairs(ev.alternativas or {}) do coletarVariaveis(alternativa.corpo) end\\n\\tend\\n\\tfor _, ev in ipairs(programa.loops or {}) do coletarVariaveis(ev.corpo) end\\n\\tfor nome in pairs(programa.funcoes or {}) do\\n\\t\\tif variaveisDeclaradas[nome] then return false, { erro = \\\"função conflita com variável: \\\" .. nome, linha = 0 } end\\n\\tend\\n\\tlocal nomesDeclarados = {}\\n\\tfor nome in pairs(variaveisDeclaradas) do\\n\\t\\tif aliasesDeclarados[nome] then return false, { erro = \\\"variável conflita com alias usar: \\\" .. nome, linha = 0 } end\\n\\t\\tif not identificadorValido(nome) then return false, { erro = \\\"nome de variável inválido para Luau: \\\" .. tostring(nome), linha = 0 } end\\n\\t\\taliases[nome] = nome\\n\\t\\tLOCAIS_GERADOS[nome] = true\\n\\t\\ttable.insert(nomesDeclarados, nome)\\n\\tend\\n\\ttable.sort(nomesDeclarados)\\n\\tfor _, nome in ipairs(nomesDeclarados) do table.insert(inicializadores, \\\"local \\\" .. nome) end\\n\\tfor _, nome in ipairs(nomesFuncoes) do table.insert(inicializadores, \\\"local \\\" .. aliases[nome]) end\\n\\tlocal sortearNomes = {}\\n\\tfor nome in pairs(variaveisSortear) do\\n\\t\\tif not aliasesDeclarados[nome] and not aliases[nome] and identificadorValido(nome) then\\n\\t\\t\\taliases[nome] = nome\\n\\t\\t\\ttable.insert(sortearNomes, nome)\\n\\t\\tend\\n\\tend\\n\\tfor nome in pairs(variaveisClonar) do\\n\\t\\tif aliasesDeclarados[nome] then return false, { erro = \\\"nome de clone conflita com alias usar: \\\" .. nome, linha = 0 } end\\n\\t\\tif not aliases[nome] and identificadorValido(nome) then aliases[nome] = nome end\\n\\tend\\n\\ttable.sort(sortearNomes)\\n\\tlocal nomesTemporarios = {}\\n\\tfor nome in pairs(variaveisClonar) do if aliases[nome] == nome and not variaveisSortear[nome] then table.insert(nomesTemporarios, nome) end end\\n\\ttable.sort(nomesTemporarios)\\n\\tfor _, nome in ipairs(sortearNomes) do table.insert(nomesTemporarios, nome) end\\n\\tif #nomesTemporarios > 0 then table.insert(inicializadores, \\\"local \\\" .. table.concat(nomesTemporarios, \\\", \\\")) end\\n\\tfor _, nome in ipairs(nomesOrdenados(programa.objetos)) do\\n\\t\\tlocal var = nomeInterno(\\\"_YashDados_\\\", nome)\\n\\t\\tif varsCriadas[var] and varsCriadas[var] ~= nome then return false, { erro = \\\"nomes de objetos geram colisao interna: \\\" .. nome, linha = 0 } end\\n\\t\\tvarsCriadas[var] = nome\\n\\t\\taliases[nome] = var\\n\\t\\tobjetosDados[nome] = true\\n\\t\\tlocal campos = {}\\n\\t\\tlocal props = programa.objetos[nome] or {}\\n\\t\\tfor _, k in ipairs((function() local a = {}; for chave in pairs(props) do table.insert(a, chave) end; table.sort(a); return a end)()) do\\n\\t\\t\\tlocal valor = legadoLua(props[k], k, false)\\n\\t\\t\\tif valor ~= nil then table.insert(campos, \\\"\\\\t[\\\" .. textoLua(k) .. \\\"] = \\\" .. valor .. \\\",\\\") end\\n\\t\\tend\\n\\t\\ttable.insert(inicializadores, \\\"local \\\" .. var .. \\\" = {\\\\n\\\" .. table.concat(campos, \\\"\\\\n\\\") .. \\\"\\\\n}\\\")\\n\\tend\\n\\tlocal temGui = next(programa.elementos or {}) ~= nil or next(programa.huds or {}) ~= nil or (programa.site and next(programa.site) ~= nil)\\n\\tlocal hudServidor = contexto == \\\"servidor\\\" and next(programa.huds or {}) ~= nil\\n\\t\\tand next(programa.elementos or {}) == nil and (not programa.site or next(programa.site) == nil)\\n\\tif temGui then\\n\\t\\tservico(\\\"Players\\\")\\n\\t\\ttable.insert(inicializadores, 'local _YashTela = Instance.new(\\\"ScreenGui\\\")')\\n\\t\\ttable.insert(inicializadores, '_YashTela.Name = \\\"YashScriptGui\\\"')\\n\\t\\ttable.insert(inicializadores, '_YashTela.ResetOnSpawn = false')\\n\\t\\tif hudServidor then\\n\\t\\t\\ttable.insert(inicializadores, '_YashTela.Archivable = true')\\n\\t\\telseif contexto == \\\"servidor\\\" then\\n\\t\\t\\treturn false, { erro = \\\"criar elementos de interface requer LocalScript; no servidor, use criar hud\\\", linha = 0 }\\n\\t\\telse\\n\\t\\t\\ttable.insert(inicializadores, '_YashTela.Parent = Players.LocalPlayer:WaitForChild(\\\"PlayerGui\\\")')\\n\\t\\tend\\n\\t\\ttable.insert(inicializadores, 'local _YashRootFrame = Instance.new(\\\"Frame\\\")')\\n\\t\\ttable.insert(inicializadores, '_YashRootFrame.Name = \\\"Raiz\\\"')\\n\\t\\ttable.insert(inicializadores, '_YashRootFrame.Size = UDim2.fromScale(1, 1)')\\n\\t\\ttable.insert(inicializadores, '_YashRootFrame.BackgroundTransparency = 1')\\n\\t\\tlocal fundo = programa.site and programa.site.fundo\\n\\t\\tif fundo then table.insert(inicializadores, \\\"_YashRootFrame.BackgroundColor3 = \\\" .. (legadoLua(fundo, \\\"fundo\\\", true) or \\\"Color3.new(0, 0, 0)\\\")); table.insert(inicializadores, \\\"_YashRootFrame.BackgroundTransparency = 0\\\") end\\n\\t\\ttable.insert(inicializadores, '_YashRootFrame.Parent = _YashTela')\\n\\tend\\n\\tlocal classesGui = { painel = \\\"Frame\\\", texto = \\\"TextLabel\\\", botao = \\\"TextButton\\\", campo = \\\"TextBox\\\", imagem = \\\"ImageLabel\\\", elemento = \\\"Frame\\\" }\\n\\tlocal function emitirProps(var, props, gui)\\n\\t\\tlocal chaves = {}\\n\\t\\tfor k in pairs(props or {}) do table.insert(chaves, k) end\\n\\t\\ttable.sort(chaves)\\n\\t\\tfor _, prop in ipairs(chaves) do\\n\\t\\t\\tlocal valor = props[prop]\\n\\t\\t\\tif prop == \\\"pai\\\" or prop == \\\"estilo\\\" or prop == \\\"cena\\\" or prop == \\\"arredondamento\\\" or prop == \\\"mostrar\\\" or prop == \\\"inimigo\\\" or prop == \\\"vida\\\" or prop == \\\"velocidade\\\" then\\n\\t\\t\\t\\t-- metadados estruturais usados abaixo ou dados de gameplay\\n\\t\\t\\telseif gui and (prop == \\\"largura\\\" or prop == \\\"altura\\\") then\\n\\t\\t\\t\\t-- largura/altura são combinadas abaixo numa única atribuição Size.\\n\\t\\t\\telseif prop == \\\"posicao\\\" then\\n\\t\\t\\t\\tlocal cod = legadoLua(valor, prop, gui)\\n\\t\\t\\t\\tif cod then table.insert(inicializadores, var .. (gui and \\\".Position = \\\" or \\\".Position = \\\") .. cod) end\\n\\t\\t\\telseif prop == \\\"tamanho\\\" then\\n\\t\\t\\t\\tlocal cod = legadoLua(valor, prop, gui)\\n\\t\\t\\t\\tif cod then table.insert(inicializadores, var .. (gui and \\\".Size = \\\" or \\\".Size = \\\") .. cod) end\\n\\t\\t\\telse\\n\\t\\t\\t\\tlocal canon = (not gui and prop == \\\"cor\\\") and \\\"Color\\\" or PROPRIEDADES[string.lower(prop)]\\n\\t\\t\\t\\tlocal cod = legadoLua(valor, prop, gui)\\n\\t\\t\\t\\tif canon and cod then table.insert(inicializadores, var .. \\\".\\\" .. canon .. \\\" = \\\" .. cod) end\\n\\t\\t\\tend\\n\\t\\tend\\n\\tend\\n\\tfor _, nome in ipairs(elementosOrdem) do\\n\\t\\tlocal def = programa.elementos[nome]\\n\\t\\tlocal propsBase = def.props or {}\\n\\t\\tlocal estilo = propsBase.estilo and programa.estilos and programa.estilos[propsBase.estilo] or nil\\n\\t\\tlocal props = mesclar(estilo, propsBase)\\n\\t\\tlocal var = nomeInterno(\\\"_YashCriado_\\\", nome)\\n\\t\\taliases[nome] = var\\n\\t\\tlocal class = classesGui[def.tipo] or \\\"Frame\\\"\\n\\t\\ttable.insert(inicializadores, \\\"local \\\" .. var .. \\\" = Instance.new(\\\" .. textoLua(class) .. \\\")\\\")\\n\\t\\ttable.insert(inicializadores, var .. \\\".Name = \\\" .. textoLua(nome))\\n\\t\\tif class == \\\"Frame\\\" or class == \\\"TextLabel\\\" or class == \\\"TextButton\\\" or class == \\\"TextBox\\\" then\\n\\t\\t\\ttable.insert(inicializadores, var .. \\\".Size = UDim2.fromOffset(100, 40)\\\")\\n\\t\\t\\ttable.insert(inicializadores, var .. \\\".BackgroundColor3 = Color3.fromRGB(35, 35, 45)\\\")\\n\\t\\tend\\n\\t\\tif props.cena then table.insert(inicializadores, var .. \\\":SetAttribute(\\\\\\\"YashCena\\\\\\\", \\\" .. textoLua(props.cena) .. \\\")\\\") end\\n\\t\\tif props.cena and not cenaVisivel(props.cena) then table.insert(inicializadores, var .. \\\".Visible = false\\\") end\\n\\t\\temitirProps(var, props, true)\\n\\t\\tif props.arredondamento then\\n\\t\\t\\tlocal corner = nomeInterno(\\\"_YashCanto_\\\", nome)\\n\\t\\t\\ttable.insert(inicializadores, \\\"local \\\" .. corner .. ' = Instance.new(\\\"UICorner\\\")')\\n\\t\\t\\ttable.insert(inicializadores, corner .. \\\".CornerRadius = UDim.new(0, \\\" .. numeroLua(tonumber(props.arredondamento) or 8) .. \\\")\\\")\\n\\t\\t\\ttable.insert(inicializadores, corner .. \\\".Parent = \\\" .. var)\\n\\t\\tend\\n\\t\\tlocal pai = props.pai and aliases[props.pai] or \\\"_YashRootFrame\\\"\\n\\t\\tif props.largura or props.altura then\\n\\t\\t\\tlocal largura = tonumber(props.largura) or 100\\n\\t\\t\\tlocal altura = tonumber(props.altura) or 40\\n\\t\\t\\ttable.insert(inicializadores, var .. \\\".Size = UDim2.fromOffset(\\\" .. numeroLua(largura) .. \\\", \\\" .. numeroLua(altura) .. \\\")\\\")\\n\\t\\tend\\n\\t\\ttable.insert(inicializadores, var .. \\\".Parent = \\\" .. (pai or \\\"_YashRootFrame\\\"))\\n\\tend\\n\\tlocal nomesHuds = {}\\n\\tlocal hudsGerados = {}\\n\\tfor nome in pairs(programa.huds or {}) do table.insert(nomesHuds, nome) end\\n\\ttable.sort(nomesHuds)\\n\\tfor indice, nome in ipairs(nomesHuds) do\\n\\t\\tlocal def = programa.huds[nome]\\n\\t\\tlocal var = nomeInterno(\\\"_YashHud_\\\", nome)\\n\\t\\taliases[nome] = var\\n\\t\\ttable.insert(inicializadores, 'local ' .. var .. ' = Instance.new(\\\"TextLabel\\\")')\\n\\t\\ttable.insert(inicializadores, var .. \\\".Name = \\\" .. textoLua(nome))\\n\\t\\ttable.insert(inicializadores, var .. \\\".Position = UDim2.fromOffset(12, \\\" .. numeroLua((indice - 1) * 32 + 12) .. \\\")\\\")\\n\\t\\ttable.insert(inicializadores, var .. \\\".Size = UDim2.fromOffset(240, 28)\\\")\\n\\t\\ttable.insert(inicializadores, var .. '.BackgroundTransparency = 1')\\n\\t\\ttable.insert(inicializadores, var .. '.TextXAlignment = Enum.TextXAlignment.Left')\\n\\t\\ttable.insert(inicializadores, var .. '.Parent = _YashRootFrame')\\n\\t\\tlocal partes = dividirCaminho(def.campo or \\\"\\\")\\n\\t\\tlocal expr = #partes > 1 and { k = \\\"caminho\\\", partes = partes } or { k = \\\"ident\\\", v = partes[1] or \\\"\\\" }\\n\\t\\tlocal valor, err = gerarValor(expr)\\n\\t\\tif not valor then return false, { erro = \\\"hud `\\\" .. nome .. \\\"`: \\\" .. tostring(err), linha = 0 } end\\n\\t\\tif hudServidor then\\n\\t\\t\\ttable.insert(hudsGerados, { nome = nome, valor = valor })\\n\\t\\telse\\n\\t\\t\\ttable.insert(inicializadores, \\\"task.spawn(function() while \\\" .. var .. \\\".Parent do \\\" .. var .. \\\".Text = \\\" .. textoLua(nome .. \\\": \\\") .. \\\" .. tostring(\\\" .. valor .. \\\"); task.wait(0.1) end end)\\\")\\n\\t\\tend\\n\\tend\\n\\tif hudServidor then\\n\\t\\ttable.insert(inicializadores, \\\"local _YashCriarHUD = function(_YashJogador)\\\")\\n\\t\\ttable.insert(inicializadores, \\\"\\\\tlocal _YashTelaJogador = _YashTela:Clone()\\\")\\n\\t\\ttable.insert(inicializadores, \\\"\\\\t_YashTelaJogador.Parent = _YashJogador:WaitForChild(\\\\\\\"PlayerGui\\\\\\\")\\\")\\n\\t\\ttable.insert(inicializadores, \\\"\\\\ttask.spawn(function()\\\")\\n\\t\\ttable.insert(inicializadores, \\\"\\\\t\\\\twhile _YashTelaJogador.Parent do\\\")\\n\\t\\tfor _, hud in ipairs(hudsGerados) do\\n\\t\\t\\tlocal label = nomeInterno(\\\"_YashLabelHUD_\\\", hud.nome)\\n\\t\\t\\ttable.insert(inicializadores, \\\"\\\\t\\\\t\\\\tlocal \\\" .. label .. \\\" = _YashTelaJogador:FindFirstChild(\\\" .. textoLua(hud.nome) .. \\\", true)\\\")\\n\\t\\t\\ttable.insert(inicializadores, \\\"\\\\t\\\\t\\\\tif \\\" .. label .. \\\" then \\\" .. label .. \\\".Text = \\\" .. textoLua(hud.nome .. \\\": \\\") .. \\\" .. tostring(\\\" .. hud.valor .. \\\") end\\\")\\n\\t\\tend\\n\\t\\ttable.insert(inicializadores, \\\"\\\\t\\\\t\\\\ttask.wait(0.1)\\\")\\n\\t\\ttable.insert(inicializadores, \\\"\\\\t\\\\tend\\\")\\n\\t\\ttable.insert(inicializadores, \\\"\\\\tend)\\\")\\n\\t\\ttable.insert(inicializadores, \\\"end\\\")\\n\\t\\ttable.insert(inicializadores, \\\"for _, _YashJogador in ipairs(Players:GetPlayers()) do _YashCriarHUD(_YashJogador) end\\\")\\n\\t\\ttable.insert(inicializadores, \\\"Players.PlayerAdded:Connect(_YashCriarHUD)\\\")\\n\\tend\\n\\tlocal classesForma = { bloco = \\\"Block\\\", paralelepipedo = \\\"Block\\\", plataforma = \\\"Block\\\", esfera = \\\"Ball\\\", cilindro = \\\"Cylinder\\\", cunha = \\\"Wedge\\\" }\\n\\tlocal nomesForma = {}\\n\\tfor nome in pairs(programa.formas or {}) do table.insert(nomesForma, nome) end\\n\\ttable.sort(nomesForma)\\n\\tfor _, nome in ipairs(nomesForma) do\\n\\t\\tlocal def = programa.formas[nome]\\n\\t\\tlocal props = def.props or {}\\n\\t\\tlocal var = nomeInterno(\\\"_YashCriado_\\\", nome)\\n\\t\\taliases[nome] = var\\n\\t\\ttable.insert(inicializadores, 'local ' .. var .. ' = Instance.new(\\\"Part\\\")')\\n\\t\\ttable.insert(inicializadores, var .. \\\".Name = \\\" .. textoLua(nome))\\n\\t\\ttable.insert(inicializadores, var .. \\\".Shape = Enum.PartType.\\\" .. (classesForma[def.tipo] or \\\"Block\\\"))\\n\\t\\ttable.insert(inicializadores, var .. \\\".Anchored = true\\\")\\n\\t\\ttable.insert(inicializadores, var .. \\\".CanCollide = true\\\")\\n\\t\\tif props.cena then table.insert(inicializadores, var .. ':SetAttribute(\\\"YashCena\\\", ' .. textoLua(props.cena) .. \\\")\\\") end\\n\\t\\tif props.cena and not cenaVisivel(props.cena) then\\n\\t\\t\\ttable.insert(inicializadores, var .. \\\".Transparency = 1\\\")\\n\\t\\t\\ttable.insert(inicializadores, var .. \\\".CanCollide = false\\\")\\n\\t\\tend\\n\\t\\temitirProps(var, props, false)\\n\\t\\ttable.insert(inicializadores, var .. \\\".Parent = Workspace\\\")\\n\\t\\tservico(\\\"Workspace\\\")\\n\\tend\\n\\tif next(programa.mundo or {}) ~= nil then\\n\\t\\tlocal mundo = programa.mundo\\n\\t\\tservico(\\\"Lighting\\\")\\n\\t\\tlocal ordemMundo = { \\\"ceu\\\", \\\"neblina\\\", \\\"neblina_inicio\\\", \\\"neblina_fim\\\" }\\n\\t\\tlocal mapeia = { ceu = \\\"ColorShift_Top\\\", neblina = \\\"FogColor\\\", neblina_inicio = \\\"FogStart\\\", neblina_fim = \\\"FogEnd\\\" }\\n\\t\\tfor _, chave in ipairs(ordemMundo) do\\n\\t\\t\\tlocal prop = mapeia[chave]\\n\\t\\t\\tif mundo[chave] ~= nil then\\n\\t\\t\\t\\tlocal valor = legadoLua(mundo[chave], chave, false)\\n\\t\\t\\t\\tif valor then table.insert(inicializadores, \\\"Lighting.\\\" .. prop .. \\\" = \\\" .. valor) end\\n\\t\\t\\tend\\n\\t\\tend\\n\\t\\tif mundo.sol then table.insert(inicializadores, \\\"Lighting.ClockTime = 12\\\") end\\n\\tend\\n\\n\\t-- 1) declaracoes `usar` — sempre primeiro, sao declaracoes\\n\\tlocal declaracoes = {}\\n\\tfor _, v in ipairs(programa.aliases or {}) do\\n\\t\\tif not identificadorValido(v.nome) then\\n\\t\\t\\treturn false, { erro = '\\\"' .. tostring(v.nome)\\n\\t\\t\\t\\t.. '\\\" nao e um identificador valido para Luau (use letras, numeros '\\n\\t\\t\\t\\t.. 'e _ sem comecar por numero)', linha = v.linha or 0 }\\n\\t\\tend\\n\\t\\tlocal expr = v.expr\\n\\t\\tlocal codigo, err\\n\\t\\tif expr.k == \\\"caminho\\\" then\\n\\t\\t\\t-- Use o mesmo resolvedor de caminhos/propriedades dos outros valores:\\n\\t\\t\\t-- isso permite aliases para propriedades como workspace.CurrentCamera.\\n\\t\\t\\tcodigo, err = gerarValor(expr)\\n\\t\\telseif expr.k == \\\"ident\\\" and aliases[expr.v] then\\n\\t\\t\\tcodigo = aliases[expr.v]\\n\\t\\telse\\n\\t\\t\\tcodigo, err = gerarValor(expr)\\n\\t\\tend\\n\\t\\tif not codigo then\\n\\t\\t\\treturn false, { erro = \\\"`usar \\\" .. textoLua(v.nome) .. \\\" = ...`: \\\"\\n\\t\\t\\t\\t.. tostring(err or \\\"nao foi possivel resolver\\\"), linha = v.linha or 0 }\\n\\t\\tend\\n\\t\\taliases[v.nome] = v.nome\\n\\t\\ttable.insert(declaracoes, { nome = v.nome, codigo = codigo })\\n\\tend\\n\\n\\t-- 2) eventos\\n\\tlocal eventos = {}\\n\\tfor _, ev in ipairs(programa.eventos or {}) do\\n\\t\\tif EVENTOS_INLINE[ev.tipo] then\\n\\t\\t\\tif ev.sujeito then\\n\\t\\t\\t\\treturn false, { erro = \\\"evento `\\\" .. ev.tipo .. \\\"` nao aceita sujeito \\\"\\n\\t\\t\\t\\t\\t.. \\\"(`quando \\\" .. ev.sujeito .. \\\" \\\" .. ev.tipo .. \\\"`)\\\", linha = 0 }\\n\\t\\t\\tend\\n\\t\\t\\ttable.insert(eventos, { tipo = \\\"inline\\\", corpo = ev.corpo })\\n\\t\\telse\\n\\t\\t\\tlocal info = EVENTOS[ev.tipo]\\n\\t\\t\\tif not info then\\n\\t\\t\\t\\treturn false, { erro = \\\"evento ainda nao traduzido no caminho direto: \\\"\\n\\t\\t\\t\\t\\t.. tostring(ev.tipo), linha = 0 }\\n\\t\\t\\tend\\n\\t\\t\\tif not ev.alvo then\\n\\t\\t\\t\\treturn false, { erro = \\\"evento `\\\" .. ev.tipo .. \\\"` precisa de um alvo\\\", linha = 0 }\\n\\t\\t\\tend\\n\\t\\t\\t-- alvo de Touched nunca mora na GUI: resolve so por alias/servico\\n\\t\\t\\tlocal ref, err = gerarReferencia({ k = \\\"ident\\\", v = ev.alvo }, info.argumento == true)\\n\\t\\t\\tif not ref then\\n\\t\\t\\t\\treturn false, { erro = \\\"alvo do evento `\\\" .. ev.tipo .. \\\"`: \\\" .. tostring(err), linha = 0 }\\n\\t\\t\\tend\\n\\t\\t\\t-- sujeito: quem dispara o evento. Vale para eventos com argumento\\n\\t\\t\\t-- (Touched), onde da para distinguir o que encostou.\\n\\t\\t\\tlocal sujeito = nil\\n\\t\\t\\tif ev.sujeito then\\n\\t\\t\\t\\tif not info.argumento then\\n\\t\\t\\t\\t\\treturn false, { erro = \\\"evento `\\\" .. ev.tipo .. \\\"` nao aceita sujeito \\\"\\n\\t\\t\\t\\t\\t\\t.. \\\"(`quando \\\" .. ev.sujeito .. \\\" \\\" .. ev.tipo .. \\\"`)\\\", linha = 0 }\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tif SUJEITOS_LOGICOS[string.lower(ev.sujeito)] then\\n\\t\\t\\t\\t\\tsujeito = { tipo = \\\"logico\\\" }\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\tlocal sref, serr = gerarReferencia({ k = \\\"ident\\\", v = ev.sujeito }, true)\\n\\t\\t\\t\\t\\tif not sref then\\n\\t\\t\\t\\t\\t\\treturn false, { erro = \\\"sujeito do evento `\\\" .. ev.tipo .. \\\"`: \\\"\\n\\t\\t\\t\\t\\t\\t\\t.. tostring(serr) .. \\\" (e nao e um sujeito logico, como `jogador`)\\\", linha = 0 }\\n\\t\\t\\t\\t\\tend\\n\\t\\t\\t\\t\\tsujeito = { tipo = \\\"objeto\\\", ref = sref }\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\ttable.insert(eventos, { tipo = \\\"connect\\\", ref = ref, alvo = ev.alvo, info = info,\\n\\t\\t\\t\\tsujeito = sujeito, sujeitoNome = ev.sujeito, corpo = ev.corpo })\\n\\t\\tend\\n\\tend\\n\\n\\t-- 3) temporizadores\\n\\tlocal temporizadores = {}\\n\\tfor _, tmr in ipairs(programa.timers or {}) do\\n\\t\\ttable.insert(temporizadores, { intervalo = tmr.intervalo, corpo = tmr.corpo })\\n\\tend\\n\\n\\t-- Inclusões sem conteúdo são um erro de entrada claro. Compilar() expande\\n\\t-- arquivos quando o host fornece a tabela; o plugin Studio não possui\\n\\t-- acesso a arquivos arbitrários do computador.\\n\\tif #(programa.incluir or {}) > 0 then\\n\\t\\treturn false, { erro = \\\"arquivo incluido nao foi fornecido ao compilador: `\\\" .. tostring(programa.incluir[1])\\n\\t\\t\\t.. \\\"` (passe-o na tabela de arquivos de Compilar)\\\", linha = 0 }\\n\\tend\\n\\n\\t-- 5) renderiza os blocos. Feito ANTES do cabecalho de proposito: um servico\\n\\t--    (ou o ScreenGui) usado só dentro de um corpo ainda precisa da local.\\n\\tlocal blocos = {}\\n\\tlocal blocosDef = {}\\n\\tlocal nomesDef = {}\\n\\tlocal funcoesDef = {}\\n\\tlocal listaDef = {}\\n\\tfor nome in pairs(programa.acoes or {}) do table.insert(listaDef, { nome = nome, tipo = \\\"acao\\\" }) end\\n\\tfor nome in pairs(programa.animacoes or {}) do table.insert(listaDef, { nome = nome, tipo = \\\"animacao\\\" }) end\\n\\ttable.sort(listaDef, function(a, b)\\n\\t\\tif a.tipo ~= b.tipo then return a.tipo < b.tipo end\\n\\t\\treturn a.nome < b.nome\\n\\tend)\\n\\tfor _, item in ipairs(listaDef) do\\n\\t\\tlocal fn = item.tipo == \\\"acao\\\" and nomeFnAcao(item.nome) or nomeFnAnim(item.nome)\\n\\t\\tif nomesDef[fn] and nomesDef[fn] ~= item.tipo .. \\\":\\\" .. item.nome then\\n\\t\\t\\treturn false, { erro = \\\"funcoes `\\\" .. nomesDef[fn] .. \\\"` e `\\\" .. item.tipo .. \\\":\\\" .. item.nome .. \\\"` geram o mesmo nome interno `\\\" .. fn .. \\\"`\\\", linha = 0 }\\n\\t\\tend\\n\\t\\tnomesDef[fn] = item.tipo .. \\\":\\\" .. item.nome\\n\\t\\tfuncoesDef[item.tipo .. \\\":\\\" .. item.nome] = fn\\n\\tend\\n\\tif #listaDef > 0 then\\n\\t\\tlocal nomes = {}\\n\\t\\tfor _, item in ipairs(listaDef) do table.insert(nomes, funcoesDef[item.tipo .. \\\":\\\" .. item.nome]) end\\n\\t\\ttable.insert(blocosDef, { \\\"local \\\" .. table.concat(nomes, \\\", \\\") })\\n\\tend\\n\\n\\t-- comandos soltos de nivel superior: print(...), mostrar Cubo, ...\\n\\tif #(programa.comandos or {}) > 0 then\\n\\t\\tlocal corpo, err = blocoNovo(0, function()\\n\\t\\t\\treturn gerarCorpo(programa.comandos, 0)\\n\\t\\tend)\\n\\t\\tif not corpo then return false, { erro = err, linha = 0 } end\\n\\t\\tif #corpo > 0 then table.insert(blocos, corpo) end\\n\\tend\\n\\n\\t-- 5b) animacoes criadas: cada uma vira uma funcao local com os passos em\\n\\t--     sequencia (espera a duracao de um passo antes do proximo)\\n\\tlocal nomeAnims = {}\\n\\tif programa.animacoes then\\n\\t\\tfor nome in pairs(programa.animacoes) do\\n\\t\\t\\ttable.insert(nomeAnims, nome)\\n\\t\\tend\\n\\tend\\n\\ttable.sort(nomeAnims)\\n\\tlocal fnVistas = {}\\n\\tfor _, nome in ipairs(nomeAnims) do\\n\\t\\tlocal fnNome = nomeFnAnim(nome)\\n\\t\\tif fnVistas[fnNome] and fnVistas[fnNome] ~= nome then\\n\\t\\t\\treturn false, { erro = \\\"animacoes `\\\" .. fnVistas[fnNome] .. \\\"` e `\\\" .. nome\\n\\t\\t\\t\\t.. \\\"` geram o mesmo nome interno `\\\" .. fnNome .. \\\"`\\\", linha = 0 }\\n\\t\\tend\\n\\t\\tfnVistas[fnNome] = nome\\n\\t\\tlocal passos = programa.animacoes[nome].lista or {}\\n\\t\\tlocal corpo, err = blocoNovo(0, function()\\n\\t\\t\\tfor i, passo in ipairs(passos) do\\n\\t\\t\\t\\tlocal onde = \\\"animacao `\\\" .. nome .. \\\"` passo \\\" .. i\\n\\t\\t\\t\\tlocal spec, serr = specDeAnim(passo, onde)\\n\\t\\t\\t\\tif not spec then return nil, serr end\\n\\t\\t\\t\\tif spec.animacao then\\n\\t\\t\\t\\t\\treturn nil, \\\"animacao `\\\" .. nome .. \\\"` passo \\\" .. i\\n\\t\\t\\t\\t\\t\\t.. \\\" nao pode chamar outra animacao (`\\\" .. spec.animacao .. \\\"`)\\\"\\n\\t\\t\\t\\tend\\n\\t\\t\\t\\tlocal ok, e = aplicarSpecNoRef(\\\"inst\\\", spec, onde)\\n\\t\\t\\t\\tif not ok then return nil, e end\\n\\t\\t\\t\\tif i < #passos then\\n\\t\\t\\t\\t\\temitir(\\\"task.wait(\\\" .. numeroLua((spec.duracao or 0.3) + 0.05) .. \\\")\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\treturn \\\"\\\"\\n\\t\\tend)\\n\\t\\tif not corpo then return false, { erro = err, linha = 0 } end\\n\\t\\tlocal bloco = { fnNome .. \\\" = function(inst)\\\" }\\n\\t\\tfor _, linha in ipairs(corpo) do\\n\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\" .. linha)\\n\\t\\tend\\n\\t\\ttable.insert(bloco, \\\"end\\\")\\n\\t\\ttable.insert(blocosDef, bloco)\\n\\tend\\n\\n\\t-- ações nomeadas viram funções locais Luau e podem chamar umas às outras.\\n\\tlocal nomesAcoes = {}\\n\\tfor nome in pairs(programa.acoes or {}) do table.insert(nomesAcoes, nome) end\\n\\ttable.sort(nomesAcoes)\\n\\tfor _, nome in ipairs(nomesAcoes) do\\n\\t\\tlocal fn = funcoesDef[\\\"acao:\\\" .. nome]\\n\\t\\tlocal anterior = alvoEvento\\n\\t\\talvoEvento = \\\"_YashAcaoAlvo\\\"\\n\\t\\tlocal funcaoAnterior = dentroFuncao\\n\\t\\tdentroFuncao = true\\n\\t\\tlocal corpo, err = gerarCorpoComLocais(programa.acoes[nome], 1, function()\\n\\t\\t\\treturn gerarCorpo(programa.acoes[nome], 0)\\n\\t\\tend, \\\"ação \\\" .. nome)\\n\\t\\tdentroFuncao = funcaoAnterior\\n\\t\\talvoEvento = anterior\\n\\t\\tif not corpo then return false, { erro = \\\"acao `\\\" .. nome .. \\\"`: \\\" .. tostring(err), linha = 0 } end\\n\\t\\tlocal bloco = { fn .. \\\" = function(_YashAcaoAlvo)\\\" }\\n\\t\\tfor _, linha in ipairs(corpo) do table.insert(bloco, linha) end\\n\\t\\ttable.insert(bloco, \\\"end\\\")\\n\\t\\ttable.insert(blocosDef, bloco)\\n\\tend\\n\\n\\tfor _, nome in ipairs(nomesFuncoes) do\\n\\t\\tlocal definicao = programa.funcoes[nome]\\n\\t\\tlocal parametros = definicao.parametros or {}\\n\\t\\tlocal aliasesSalvos, locaisSalvos = {}, {}\\n\\t\\tfor _, parametro in ipairs(parametros) do\\n\\t\\t\\tif not identificadorValido(parametro) then\\n\\t\\t\\t\\treturn false, { erro = \\\"parâmetro inválido para Luau em `\\\" .. nome .. \\\"`: \\\" .. tostring(parametro), linha = 0 }\\n\\t\\t\\tend\\n\\t\\t\\taliasesSalvos[parametro] = aliases[parametro]\\n\\t\\t\\tlocaisSalvos[parametro] = LOCAIS_GERADOS[parametro]\\n\\t\\t\\taliases[parametro] = parametro\\n\\t\\t\\tLOCAIS_GERADOS[parametro] = true\\n\\t\\tend\\n\\t\\tlocal nomesLocaisSet, nomesLocais = {}, {}\\n\\t\\tcoletarLocaisFuncao(definicao.corpo, nomesLocaisSet)\\n\\t\\tfor nomeLocal in pairs(nomesLocaisSet) do\\n\\t\\t\\tif not identificadorValido(nomeLocal) then\\n\\t\\t\\t\\treturn false, { erro = \\\"variável local inválida para Luau em `\\\" .. nome .. \\\"`: \\\" .. tostring(nomeLocal), linha = 0 }\\n\\t\\t\\tend\\n\\t\\t\\taliasesSalvos[nomeLocal] = aliases[nomeLocal]\\n\\t\\t\\tlocaisSalvos[nomeLocal] = LOCAIS_GERADOS[nomeLocal]\\n\\t\\t\\taliases[nomeLocal] = nomeLocal\\n\\t\\t\\tLOCAIS_GERADOS[nomeLocal] = true\\n\\t\\t\\ttable.insert(nomesLocais, nomeLocal)\\n\\t\\tend\\n\\t\\ttable.sort(nomesLocais)\\n\\t\\tlocal antes = dentroFuncao\\n\\t\\tdentroFuncao = true\\n\\t\\tlocal corpo, err = blocoNovo(1, function() return gerarCorpo(definicao.corpo, 0) end)\\n\\t\\tdentroFuncao = antes\\n\\t\\tfor _, nomeLocal in ipairs(nomesLocais) do\\n\\t\\t\\taliases[nomeLocal] = aliasesSalvos[nomeLocal]\\n\\t\\t\\tLOCAIS_GERADOS[nomeLocal] = locaisSalvos[nomeLocal]\\n\\t\\tend\\n\\t\\tfor _, parametro in ipairs(parametros) do\\n\\t\\t\\taliases[parametro] = aliasesSalvos[parametro]\\n\\t\\t\\tLOCAIS_GERADOS[parametro] = locaisSalvos[parametro]\\n\\t\\tend\\n\\t\\tif not corpo then return false, { erro = \\\"função `\\\" .. nome .. \\\"`: \\\" .. tostring(err), linha = 0 } end\\n\\t\\tlocal bloco = { aliases[nome] .. \\\" = function(\\\" .. table.concat(parametros, \\\", \\\") .. \\\")\\\" }\\n\\t\\tif #nomesLocais > 0 then table.insert(bloco, \\\"\\\\tlocal \\\" .. table.concat(nomesLocais, \\\", \\\")) end\\n\\t\\tfor _, linha in ipairs(corpo) do table.insert(bloco, linha) end\\n\\t\\ttable.insert(bloco, \\\"end\\\")\\n\\t\\ttable.insert(blocosDef, bloco)\\n\\tend\\n\\n\\tfor _, ev in ipairs(eventos) do\\n\\t\\tif ev.tipo == \\\"connect\\\" then\\n\\t\\t\\tlocal arg = ev.info.argumento and \\\"_YashAlvo\\\" or \\\"\\\"\\n\\t\\t\\tlocal repete = ev.info.repete == true\\n\\t\\t\\tlocal corpo, err\\n\\t\\t\\tlocal anterior = alvoEvento\\n\\t\\t\\tlocal eventoAnterior = eventoAtual\\n\\t\\t\\talvoEvento = ev.alvo\\n\\t\\t\\teventoAtual = { tipo = ev.info.evento == \\\"MouseButton1Click\\\" and \\\"clicar\\\" or ev.info.evento, alvo = ev.alvo }\\n\\t\\t\\t-- a DSL usa o nome do evento, enquanto o gerador armazena o nome Roblox.\\n\\t\\t\\tfor nomeEvento, infoEvento in pairs(EVENTOS) do\\n\\t\\t\\t\\tif infoEvento.evento == ev.info.evento then eventoAtual.tipo = nomeEvento; break end\\n\\t\\t\\tend\\n\\t\\t\\tlocal funcaoAnterior = dentroFuncao\\n\\t\\t\\tdentroFuncao = true\\n\\t\\t\\tcorpo, err = gerarCorpoComLocais(ev.corpo, repete and 2 or 1, function()\\n\\t\\t\\t\\treturn gerarCorpo(ev.corpo, 0)\\n\\t\\t\\tend, \\\"evento \\\" .. tostring(ev.tipo))\\n\\t\\t\\tdentroFuncao = funcaoAnterior\\n\\t\\t\\talvoEvento = anterior\\n\\t\\t\\teventoAtual = eventoAnterior\\n\\t\\t\\tif not corpo then return false, { erro = err, linha = 0 } end\\n\\n\\t\\t\\tlocal bloco = {}\\n\\t\\t\\tlocal ind = repete and \\\"\\\\t\\\" or \\\"\\\"\\n\\t\\t\\tif repete then\\n\\t\\t\\t\\t-- ultimoToque vive num escopo proprio: cada evento tem o dele\\n\\t\\t\\t\\ttable.insert(bloco, \\\"do\\\")\\n\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\tlocal _YashUltimoToque = 0\\\")\\n\\t\\t\\tend\\n\\t\\t\\ttable.insert(bloco, ind .. ev.ref .. \\\".\\\" .. ev.info.evento\\n\\t\\t\\t\\t.. \\\":Connect(function(\\\" .. arg .. \\\")\\\")\\n\\t\\t\\tif repete and ev.sujeito then\\n\\t\\t\\t\\t-- mesma ordem do Runtime legado: primeiro o sujeito, depois o\\n\\t\\t\\t\\t-- debounce -- um toque que nao e do sujeito nao consome a janela\\n\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\tlocal _YashPersonagem = _YashAlvo:FindFirstAncestorOfClass(\\\\\\\"Model\\\\\\\")\\\")\\n\\t\\t\\t\\tif ev.sujeito.tipo == \\\"logico\\\" then\\n\\t\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\tif not (_YashPersonagem and _YashPersonagem:FindFirstChildOfClass(\\\\\\\"Humanoid\\\\\\\")) then return end\\\")\\n\\t\\t\\t\\telse\\n\\t\\t\\t\\t\\tlocal ref = ev.sujeito.ref\\n\\t\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\tlocal _YashDoSujeito = _YashAlvo:IsDescendantOf(\\\" .. ref\\n\\t\\t\\t\\t\\t\\t.. \\\") or \\\" .. ref .. \\\":IsDescendantOf(_YashAlvo)\\\")\\n\\t\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\t\\\\tor (_YashPersonagem and (_YashPersonagem:IsDescendantOf(\\\" .. ref\\n\\t\\t\\t\\t\\t\\t.. \\\") or \\\" .. ref .. \\\":IsDescendantOf(_YashPersonagem)))\\\")\\n\\t\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\tif not _YashDoSujeito then return end\\\")\\n\\t\\t\\t\\tend\\n\\t\\t\\tend\\n\\t\\t\\tif repete then\\n\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\tlocal _YashAgora = os.clock()\\\")\\n\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\tif _YashAgora - _YashUltimoToque < \\\"\\n\\t\\t\\t\\t\\t.. numeroLua(DEBOUNCE_TOQUE) .. \\\" then return end\\\")\\n\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\t\\\\t_YashUltimoToque = _YashAgora\\\")\\n\\t\\t\\tend\\n\\t\\t\\tfor _, linha in ipairs(corpo) do table.insert(bloco, linha) end\\n\\t\\t\\tif repete then\\n\\t\\t\\t\\ttable.insert(bloco, \\\"\\\\tend)\\\")\\n\\t\\t\\t\\ttable.insert(bloco, \\\"end\\\")\\n\\t\\t\\telse\\n\\t\\t\\t\\ttable.insert(bloco, \\\"end)\\\")\\n\\t\\t\\tend\\n\\t\\t\\ttable.insert(blocos, bloco)\\n\\t\\telse\\n\\t\\t\\t-- evento inline (iniciar / carregar): roda direto no topo\\n\\t\\t\\tlocal eventoAnterior = eventoAtual\\n\\t\\t\\teventoAtual = { tipo = ev.tipo, alvo = nil }\\n\\t\\t\\tlocal corpo, err = blocoNovo(0, function()\\n\\t\\t\\t\\treturn gerarCorpo(ev.corpo, 0)\\n\\t\\t\\tend)\\n\\t\\t\\teventoAtual = eventoAnterior\\n\\t\\t\\tif not corpo then return false, { erro = err, linha = 0 } end\\n\\t\\t\\ttable.insert(blocos, corpo)\\n\\t\\tend\\n\\tend\\n\\n\\t-- Condicionais de topo sao avaliadas uma vez na inicializacao; laços de\\n\\t-- topo permanecem ativos durante a vida do script.\\n\\tfor _, c in ipairs(programa.continuos or {}) do\\n\\t\\tlocal cond, err = gerarCondicao(c.cond)\\n\\t\\tif not cond then return false, { erro = err, linha = 0 } end\\n\\t\\tlocal corpo, e = blocoNovo(1, function() return gerarCorpo(c.corpo, 0) end)\\n\\t\\tif not corpo then return false, { erro = e, linha = 0 } end\\n\\t\\tlocal bloco = { \\\"if \\\" .. cond .. \\\" then\\\" }\\n\\t\\tfor _, linha in ipairs(corpo) do table.insert(bloco, linha) end\\n\\t\\tfor _, alternativa in ipairs(c.alternativas or {}) do\\n\\t\\t\\tlocal condAlt, errAlt = gerarCondicao(alternativa.cond)\\n\\t\\t\\tif not condAlt then return false, { erro = errAlt, linha = 0 } end\\n\\t\\t\\tlocal alt, errCorpo = blocoNovo(1, function() return gerarCorpo(alternativa.corpo, 0) end)\\n\\t\\t\\tif not alt then return false, { erro = errCorpo, linha = 0 } end\\n\\t\\t\\ttable.insert(bloco, \\\"elseif \\\" .. condAlt .. \\\" then\\\")\\n\\t\\t\\tfor _, linha in ipairs(alt) do table.insert(bloco, linha) end\\n\\t\\tend\\n\\t\\tif c.senao and #c.senao > 0 then\\n\\t\\t\\ttable.insert(bloco, \\\"else\\\")\\n\\t\\t\\tlocal sen, se = blocoNovo(1, function() return gerarCorpo(c.senao, 0) end)\\n\\t\\t\\tif not sen then return false, { erro = se, linha = 0 } end\\n\\t\\t\\tfor _, linha in ipairs(sen) do table.insert(bloco, linha) end\\n\\t\\tend\\n\\t\\ttable.insert(bloco, \\\"end\\\")\\n\\t\\ttable.insert(blocos, bloco)\\n\\tend\\n\\n\\t-- `enquanto` de topo: laço direto, sem intermediario\\n\\tfor _, lp in ipairs(programa.loops or {}) do\\n\\t\\tlocal cond, err = gerarCondicao(lp.cond)\\n\\t\\tif not cond then return false, { erro = err, linha = 0 } end\\n\\t\\tlocal corpo, e = blocoNovo(1, function()\\n\\t\\t\\treturn gerarCorpo(lp.corpo, 0)\\n\\t\\tend)\\n\\t\\tif not corpo then return false, { erro = e, linha = 0 } end\\n\\t\\tlocal bloco = { \\\"while \\\" .. cond .. \\\" do\\\" }\\n\\t\\tfor _, linha in ipairs(corpo) do table.insert(bloco, linha) end\\n\\t\\ttable.insert(bloco, \\\"end\\\")\\n\\t\\ttable.insert(blocos, bloco)\\n\\tend\\n\\n\\tfor _, tmr in ipairs(temporizadores) do\\n\\t\\tlocal funcaoAnterior = dentroFuncao\\n\\t\\tdentroFuncao = true\\n\\t\\tlocal corpo, err = gerarCorpoComLocais(tmr.corpo, 1, function()\\n\\t\\t\\treturn gerarCorpo(tmr.corpo, 0)\\n\\t\\tend, \\\"temporizador\\\")\\n\\t\\tdentroFuncao = funcaoAnterior\\n\\t\\tif not corpo then return false, { erro = err, linha = 0 } end\\n\\t\\tlocal bloco = { \\\"task.spawn(function()\\\" }\\n\\t\\tif corpo[1] and string.sub(corpo[1], 1, 7) == \\\"\\\\tlocal \\\" then\\n\\t\\t\\ttable.insert(bloco, corpo[1])\\n\\t\\t\\ttable.remove(corpo, 1)\\n\\t\\tend\\n\\t\\ttable.insert(bloco, \\\"\\\\twhile true do\\\")\\n\\t\\tfor _, linha in ipairs(corpo) do table.insert(bloco, \\\"\\\\t\\\" .. linha) end\\n\\t\\ttable.insert(bloco, \\\"\\\\t\\\\ttask.wait(\\\" .. numeroLua(tmr.intervalo) .. \\\")\\\")\\n\\t\\ttable.insert(bloco, \\\"\\\\tend\\\")\\n\\t\\ttable.insert(bloco, \\\"end)\\\")\\n\\t\\ttable.insert(blocos, bloco)\\n\\tend\\n\\n\\t-----------------------------------------------------------------------\\n\\t-- monta o texto final\\n\\t-----------------------------------------------------------------------\\n\\n\\tlocal cabecalho = {\\n\\t\\t\\\"-- Generated by YashScript v\\\" .. Gerador.VERSAO,\\n\\t\\t\\\"-- Fonte YashScript: atributo \\\\\\\"\\\" .. (opcoes.atributo or \\\"YashScript\\\") .. \\\"\\\\\\\" deste script.\\\",\\n\\t\\t\\\"-- Contexto: \\\" .. contexto .. (modulo and \\\" (ModuleScript)\\\" or \\\"\\\") .. \\\".\\\",\\n\\t}\\n\\tfor _, l in ipairs(cabecalho) do table.insert(linhas, l) end\\n\\n\\t-- local do ScreenGui quando o script vive dentro de um\\n\\tif usadoRaiz then\\n\\t\\ttable.insert(linhas, \\\"\\\")\\n\\t\\ttable.insert(linhas, 'local _YashRaiz = script:IsA(\\\"ScreenGui\\\") and script '\\n\\t\\t\\t.. 'or script:FindFirstAncestorWhichIsA(\\\"ScreenGui\\\")')\\n\\tend\\n\\n\\t-- locals dos servicos usados\\n\\tlocal ordem = {}\\n\\tfor canonico in pairs(servicosUsados) do table.insert(ordem, canonico) end\\n\\ttable.sort(ordem)\\n\\tif #ordem > 0 then\\n\\t\\ttable.insert(linhas, \\\"\\\")\\n\\t\\tfor _, canonico in ipairs(ordem) do\\n\\t\\t\\ttable.insert(linhas, 'local ' .. canonico .. ' = game:GetService(\\\"'\\n\\t\\t\\t\\t.. canonico .. '\\\")')\\n\\t\\tend\\n\\tend\\n\\tfor _, linha in ipairs(inicializadores) do table.insert(linhas, linha) end\\n\\n\\t-- aliases\\n\\tfor _, d in ipairs(declaracoes) do\\n\\t\\ttable.insert(linhas, \\\"\\\")\\n\\t\\ttable.insert(linhas, \\\"local \\\" .. d.nome .. \\\" = \\\" .. d.codigo)\\n\\tend\\n\\n\\t-- funções locais são definidas antes dos comandos executáveis para que\\n\\t-- chamadas no topo e referências entre ações sejam válidas.\\n\\tfor _, bloco in ipairs(blocosDef) do\\n\\t\\ttable.insert(linhas, \\\"\\\")\\n\\t\\tfor _, l in ipairs(bloco) do table.insert(linhas, l) end\\n\\tend\\n\\n\\t-- eventos e temporizadores (ja renderizados)\\n\\tfor _, bloco in ipairs(blocos) do\\n\\t\\ttable.insert(linhas, \\\"\\\")\\n\\t\\tfor _, l in ipairs(bloco) do table.insert(linhas, l) end\\n\\tend\\n\\n\\t-- ModuleScript: expoe os aliases como tabela\\n\\tif modulo then\\n\\t\\ttable.insert(linhas, \\\"\\\")\\n\\t\\tif #declaracoes > 0 or #nomesFuncoes > 0 then\\n\\t\\t\\tlocal partes = {}\\n\\t\\t\\tfor _, d in ipairs(declaracoes) do\\n\\t\\t\\t\\ttable.insert(partes, \\\"\\\\t\\\" .. d.nome .. \\\" = \\\" .. d.nome .. \\\",\\\")\\n\\t\\t\\tend\\n\\t\\t\\tfor _, nome in ipairs(nomesFuncoes) do\\n\\t\\t\\t\\ttable.insert(partes, \\\"\\\\t\\\" .. nome .. \\\" = \\\" .. aliases[nome] .. \\\",\\\")\\n\\t\\t\\tend\\n\\t\\t\\ttable.insert(linhas, \\\"return {\\\\n\\\" .. JUNTAR(partes, \\\"\\\\n\\\") .. \\\"\\\\n}\\\")\\n\\t\\telse\\n\\t\\t\\ttable.insert(linhas, \\\"return {}\\\")\\n\\t\\tend\\n\\tend\\n\\n\\treturn true, JUNTAR(linhas, \\\"\\\\n\\\") .. \\\"\\\\n\\\"\\nend\\n\\nGerador.GerarLuau = GerarLuau\\n\\nreturn Gerador\\n\""),
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
