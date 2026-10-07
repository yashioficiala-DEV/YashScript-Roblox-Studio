// Gera um harness Luau que roda o PLUGIN no DataModel do Studio com a API
// `plugin` mockada, validando a criacao/parenting da UI e disparando acoes.
//
// O plugin so usa a API `plugin` em 3 pontos (CreateToolbar,
// CreateDockWidgetPluginGui, GetSelected). O mock devolve Instances REAIS (um
// TextButton para o botao da toolbar e uma Folder para o dock), de modo que
// todo Instance.new, todo .Parent e todo :Activate() roda de verdade.
//
// As unicas substituicoes sao em Title/Enabled, que so existem no
// DockWidgetPluginGui; viram atributos na Folder mock.
//
// O fonte do plugin e o driver ficam no MESMO chunk: se a construcao da UI
// falhar, o erro (com linha) e a resposta.
//
// Uso:  node scripts/gerar_harness_ui.js > .tmp_harness.lua
const fs = require("fs");
const path = require("path");

const raiz = path.join(__dirname, "..");
function ler(rel) {
  return fs.readFileSync(path.join(raiz, rel), "utf8").replace(/\r\n/g, "\n");
}

let src = ler("plugin/_modelo_plugin.lua");

// fontes embutidas viram stubs curtos (a fonte do compilador e testada em outro lugar)
const STUB = {
  "@@COMPILADOR@@": '"-- stub"',
  "@@RUNTIME@@": '"-- stub"',
  "@@INICIAR@@": '"-- stub"',
};
for (const ph of Object.keys(STUB)) {
  if (!src.includes(ph)) throw new Error("placeholder ausente no modelo: " + ph);
  src = src.replace(ph, STUB[ph]);
}

// DockWidgetPluginGui nao existe no DataModel: Title/Enabled viram atributos.
// ORDEM IMPORTA: o toggle precisa ser tratado antes da atribuicao generica.
const trocas = [
  [/widget\.Enabled = not widget\.Enabled/g, "_mockSetEnabled(not _mockGetEnabled())"],
  [/widget\.Enabled = (.+)$/gm, "_mockSetEnabled($1)"],
  [/widget\.Title = ("[^"]*")/g, '_widgetDir:SetAttribute("Title", $1)'],
];
for (const [re, para] of trocas) {
  const n = (src.match(re) || []).length;
  if (n === 0) throw new Error("nada substituido: " + re.source);
  src = src.replace(re, para);
  console.error("troca " + re.source + ": " + n + " ocorrencia(s)");
}

const mocks = `-- HARNESS de UI do plugin YashScript (gerado; temporario)
local _widgetDir
local _botaoToolbar
local _paiTeste = Instance.new("Folder")
_paiTeste.Name = "__HARNESS_UI__"
_paiTeste.Parent = game:GetService("ReplicatedStorage")

local function _mockSetEnabled(v) _widgetDir:SetAttribute("Enabled", v == true) end
local function _mockGetEnabled() return _widgetDir:GetAttribute("Enabled") == true end

plugin = {
	CreateToolbar = function()
		return {
			CreateButton = function()
				_botaoToolbar = Instance.new("TextButton")
				_botaoToolbar.Name = "BotaoToolbar"
				return _botaoToolbar
			end,
		}
	end,
	CreateDockWidgetPluginGui = function(nome)
		_widgetDir = Instance.new("Folder")
		_widgetDir.Name = nome
		_widgetDir.Parent = _paiTeste
		_widgetDir:SetAttribute("Enabled", false)
		return _widgetDir
	end,
	GetSelected = function() return {} end,
}

DockWidgetPluginGuiInfo = { new = function() return {} end }
`;

const YASH = "servidor\\nprincipal\\n\\nmundo\\n    ceu = rgb(135,206,235)\\nfim\\n\\ncriar plataforma 'chao'\\n    posicao = (0, -1, 0)\\n    tamanho = (60, 2, 60)\\n    cor = rgb(80,120,90)\\nfim\\n";

const driver = `
-- ------------------------------------------------------------------
-- driver: inspeciona a arvore e dispara as acoes do painel
-- (mesmo chunk do plugin, portanto enxerga seus locals)
-- ------------------------------------------------------------------
local relatorio = {}
local function add(k, v) relatorio[#relatorio + 1] = k .. " = " .. tostring(v) end

add("plugin carregou", "ok")
add("widget mock", _widgetDir and _widgetDir:GetFullName() or "AUSENTE")
add("botao toolbar", _botaoToolbar and _botaoToolbar.Name or "AUSENTE")
if not _widgetDir then return relatorio end

local achados = {}
for _, d in ipairs(_widgetDir:GetDescendants()) do achados[d.Name] = d end
add("descendentes no dock", #_widgetDir:GetDescendants())

local esperado = {
	Raiz = "Frame", titulo = "TextLabel", listaRolagem = "ScrollingFrame",
	editorRolagem = "ScrollingFrame", editor = "TextBox",
	rotuloAlvo = "TextLabel", status = "TextLabel",
}
local ordem = { "Raiz", "titulo", "listaRolagem", "editorRolagem", "editor", "rotuloAlvo", "status" }
for _, nome in ipairs(ordem) do
	local inst = achados[nome]
	if not inst then
		add("FALTA " .. nome, "nao encontrado")
	elseif inst.ClassName ~= esperado[nome] then
		add("CLASSE ERRADA " .. nome, inst.ClassName .. " (esperado " .. esperado[nome] .. ")")
	elseif not inst:IsDescendantOf(_widgetDir) then
		add("ORFAO " .. nome, "sem parent")
	else
		add("ok " .. nome, inst.ClassName)
	end
end

-- nenhum filho pode estar fora do dock
for _, d in ipairs(_widgetDir:GetDescendants()) do
	if not d:IsDescendantOf(_widgetDir) then add("ORFAO", d:GetFullName()) end
end

local raiz, status, editor, lista =
	achados.Raiz, achados.status, achados.editor, achados.listaRolagem

local function acharBotao(nome)
	if raiz then
		for _, d in ipairs(raiz:GetChildren()) do
			if d:IsA("TextButton") and d.Name == nome then return d end
		end
	end
	return nil
end
for _, nome in ipairs({ "Gravar", "Selecionado", "Validar", "Ler", "Modulos" }) do
	local b = acharBotao(nome)
	if not b then
		add("FALTA botao", nome)
	else
		add("ok botao", nome .. " -> texto '" .. b.Text .. "'")
	end
end

local function acionar(b, rotulo)
	if not b then
		add("acao " .. rotulo, "botao ausente")
		return
	end
	local ok, err = pcall(function() b:Activate() end)
	add("acao " .. rotulo, ok and "ativado" or ("ERRO: " .. tostring(err)))
end

local function contarLista()
	if not lista then return -1 end
	local n = 0
	for _, c in ipairs(lista:GetChildren()) do
		if c:IsA("TextButton") then n = n + 1 end
	end
	return n
end

-- 1) abrir o painel pelo botao da toolbar
add("Enabled inicial", tostring(_mockGetEnabled()))
if _botaoToolbar then
	acionar(_botaoToolbar, "toolbar (abrir painel)")
	add("Enabled apos toolbar", tostring(_mockGetEnabled()))
	add("itens na lista", contarLista())
	add("CanvasSize da lista", lista and tostring(lista.CanvasSize.Y) or "?")
	acionar(_botaoToolbar, "toolbar (fechar painel)")
	add("Enabled apos fechar", tostring(_mockGetEnabled()))
	acionar(_botaoToolbar, "toolbar (reabrir)")
	add("Enabled final", tostring(_mockGetEnabled()))
end

-- 2) Validar sem texto
local bValidar = acharBotao("Validar")
acionar(bValidar, "Validar (vazio)")
add("status", status and status.Text or "?")

-- 3) escrever yash valido e Validar
if editor then
	editor.Text = "${YASH}"
	add("editor.Text", #editor.Text .. " chars")
	acionar(bValidar, "Validar (yash servidor)")
	add("status", status and status.Text or "?")
	-- e um yash invalido, para ver o caminho de erro
	editor.Text = "criar naoexiste"
	acionar(bValidar, "Validar (yash invalido)")
	add("status", status and status.Text or "?")
	editor.Text = "${YASH}"
end

-- 4) Selecionado sem selecao -> aviso
acionar(acharBotao("Selecionado"), "Selecionado")
add("status", status and status.Text or "?")

-- 5) Gravar sem alvo -> aviso
local bGravar = acharBotao("Gravar")
acionar(bGravar, "Gravar (sem alvo)")
add("status", status and status.Text or "?")

-- 6) acao real ponta a ponta: criar Script, clicar na lista, gravar
local sss = game:GetService("ServerScriptService")
local teste = sss:FindFirstChild("HarnessTeste")
if teste then teste:Destroy() end
teste = Instance.new("Script")
teste.Name = "HarnessTeste"
teste.Parent = sss
teste.Source = "-- script de teste do harness"
add("criou Script de teste", teste:GetFullName())

repovoarLista()
add("itens na lista apos recriar", contarLista())
local clicou = false
if lista then
	for _, d in ipairs(lista:GetChildren()) do
		if d:IsA("TextButton") and d.Name == "Item_HarnessTeste" then
			acionar(d, "clique na lista (Item_HarnessTeste)")
			clicou = true
			break
		end
	end
end
if not clicou then add("clique na lista", "Item_HarnessTeste nao apareceu") end
add("status apos clicar na lista", status and status.Text or "?")
add("rotuloAlvo", achados.rotuloAlvo and achados.rotuloAlvo.Text or "?")

-- o script livre nao tem yash: o painel deve avisar e nao quebrar
add("editor apos script livre", editor and (#editor.Text .. " chars") or "?")

if editor then
	editor.Text = "${YASH}"
	acionar(bGravar, "Gravar (com alvo)")
	add("status", status and status.Text or "?")
	local src = teste.Source
	add("fonte gravada", #src .. " bytes")
	add("usa montarMundo", src:find("montarMundo", 1, true) and "sim" or "NAO")
	add("usa .executar", src:find(".executar", 1, true) and "sim" or "nao")
	add("atributo YashScript", teste:GetAttribute("YashScript") ~= nil and "sim" or "nao")
	add("marcador YASHC1", src:find("--YASHC1--", 1, true) and "sim" or "nao")
	add("Runtime via WaitForChild", src:find("WaitForChild", 1, true) and "sim" or "nao")
end

-- 7) ler de volta o yash a partir do script gravado
if lista then
	for _, d in ipairs(lista:GetChildren()) do
		if d:IsA("TextButton") and d.Name == "Item_HarnessTeste" then
			acionar(d, "ler de volta")
			break
		end
	end
	add("status apos ler", status and status.Text or "?")
	add("yash recuperado", editor and (#editor.Text .. " chars") or "?")
	if editor then
		add("recuperado contem 'criar plataforma'", editor.Text:find("criar plataforma", 1, true) and "sim" or "nao")
		add("yash identico ao original", editor.Text == "${YASH}" and "sim" or "diferente (round-trip)")
	end
end

-- 8) Ler sem alvo apos trocar de alvo para nil
alvo = nil
add("Ler sem alvo", (function()
	local b = acharBotao("Ler")
	if not b then return "botao ausente" end
	local ok = pcall(function() b:Activate() end)
	return ok and "ativado" or "ERRO"
end)())
add("status", status and status.Text or "?")

-- 9) instalar Runtime -- NAO DESTRUTIVO: guarda a fonte real e restaura depois
local yashReal = game:GetService("ReplicatedStorage"):FindFirstChild("Yash")
local rtReal = yashReal and yashReal:FindFirstChild("Runtime")
local rtFonteReal = rtReal and rtReal.Source
add("Runtime real antes", rtFonteReal and (#rtFonteReal .. " bytes") or "AUSENTE")

acionar(acharBotao("Modulos"), "Instalar Runtime")
add("status", status and status.Text or "?")

local yash = game:GetService("ReplicatedStorage"):FindFirstChild("Yash")
add("Yash existe", yash ~= nil)
if yash then
	local kids = yash:GetChildren()
	add("Yash filhos", #kids)
	for _, c in ipairs(kids) do
		local s = c.Source
		add("Yash/" .. c.Name, c.ClassName .. " " .. (type(s) == "string" and (#s .. " bytes") or tostring(s)))
	end
end

-- restaura a fonte real do Runtime (o harness instalou o stub)
if rtFonteReal and rtReal and rtReal.Source ~= rtFonteReal then
	rtReal.Source = rtFonteReal
	add("Runtime restaurado", rtReal.Source == rtFonteReal and "sim" or "FALHOU")
elseif rtFonteReal then
	add("Runtime restaurado", "ja estava igual")
end

-- limpeza: para o loop de sincronia e destroi o que foi criado
alvo = nil
blocoGravando = true
pcall(function() teste:Destroy() end)
pcall(function() _paiTeste:Destroy() end)
add("limpeza", "ok")

return relatorio
`;

const final = mocks + "\n-- ===== FONTE DO PLUGIN =====\n" + src + driver;

fs.writeFileSync(path.join(raiz, ".tmp_harness.lua"), final, "utf8");
console.error("gerado .tmp_harness.lua (" + final.length + " bytes)");
process.stdout.write(final);
