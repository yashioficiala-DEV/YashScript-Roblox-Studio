// ---------------------------------------------------------------------------
// YASHDASH - Coletor de Moedas
// Mini-jogo completo escrito em YashScript V7 e compilado exatamente como o
// plugin faz ao clicar em "Gravar" (compilador + serializador + prembulo).
//
//   node scripts\minijogo.js            -> compila e mostra o resultado
//   node scripts\minijogo.js --salvar   -> grava minijogo/servidor.lua e
//                                           minijogo/cliente.lua
// ---------------------------------------------------------------------------
const fs = require("fs");
const path = require("path");

const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;

const raiz = path.join(__dirname, "..");
const ler = (rel) => fs.readFileSync(path.join(raiz, rel), "utf8");

const MARCA_INI = "--YASHC1--";
const MARCA_FIM = "--YASHC2--";
const PREAMBULO =
	'local function cor(r, g, b) return { t = "cor", r = r, g = g, b = b } end\n'
	+ 'local function par(x, y, z) if z == nil then return { t = "par", x = x, y = y } end return { t = "par", x = x, y = y, z = z } end\n';

// ===========================================================================
// FONTE YASHSCRIPT - SERVIDOR (Script)
// ===========================================================================
const SERVIDOR = `YASHSCRIPT:

mundo
    ceu = rgb(112, 176, 255)
    neblina = rgb(205, 226, 250)
    neblina_inicio = 45
    neblina_fim = 180
fim

criar plataforma 'chao'
    posicao = (0, -1, 0)
    tamanho = (80, 2, 80)
    cor = rgb(74, 132, 94)
    material = grama
fim

criar bloco 'paredeEsq'
    posicao = (-19, 3, 0)
    tamanho = (2, 6, 34)
    cor = rgb(150, 150, 158)
    material = concreto
fim

criar bloco 'paredeDir'
    posicao = (19, 3, 0)
    tamanho = (2, 6, 34)
    cor = rgb(150, 150, 158)
    material = concreto
fim

criar esfera 'moedaA'
    posicao = (13, 2, 13)
    tamanho = (2.5, 2.5, 2.5)
    cor = rgb(255, 214, 0)
    material = metal
fim

criar esfera 'moedaB'
    posicao = (-13, 2, 13)
    tamanho = (2.5, 2.5, 2.5)
    cor = rgb(255, 214, 0)
    material = metal
fim

criar esfera 'moedaC'
    posicao = (0, 2, -15)
    tamanho = (2.5, 2.5, 2.5)
    cor = rgb(255, 214, 0)
    material = metal
fim

criar esfera 'perigo'
    posicao = (0, 3, 0)
    tamanho = (3, 3, 3)
    cor = rgb(224, 48, 48)
    material = neon
    vida = 3
    controlavel = sim
    velocidade = 10
fim

criar objeto 'heroi'
    pontos = 0
    tempo = 30
    vidas = 3
    terminou = 0
fim

criar acao 'vitoria'
    se heroi.terminou = 0 entao
        heroi.terminou = 1
        print("VITORIA! 3 moedas coletadas antes do tempo!")
    fim
fim

criar acao 'derrota'
    se heroi.terminou = 0 entao
        heroi.terminou = 1
        print("DERROTA! Tente de novo")
    fim
fim

criar acao 'pegouA'
    heroi.pontos += 1
    print(heroi.pontos)
    moedaA.destruir()
fim

criar acao 'pegouB'
    heroi.pontos += 1
    print(heroi.pontos)
    moedaB.destruir()
fim

criar acao 'pegouC'
    heroi.pontos += 1
    print(heroi.pontos)
    moedaC.destruir()
fim

a cada 1
    se heroi.terminou = 0 entao
        heroi.tempo -= 1
    fim
fim

quando heroi tocar moedaA
    executar acao 'pegouA'
fim

quando heroi tocar moedaB
    executar acao 'pegouB'
fim

quando heroi tocar moedaC
    executar acao 'pegouC'
fim

quando heroi tocar perigo
    heroi.vidas -= 1
    heroi.pontos -= 1
    print(heroi.vidas)
    mover perigo para (0, 6, 0) velocidade 40
    esperar 1
    mover perigo para (0, 3, 0) velocidade 20
fim

quando iniciar
    se "heroi" criado com sucesso entao
        print("YASHDASH pronto - pegue as 3 moedas e desvie do perigo vermelho")
    fim
fim

se heroi.pontos >= 3
    executar acao 'vitoria'
fim

se heroi.tempo <= 0
    executar acao 'derrota'
fim

se heroi.vidas <= 0
    executar acao 'derrota'
fim
`;

// ===========================================================================
// FONTE YASHSCRIPT - CLIENTE (LocalScript)
// ===========================================================================
const CLIENTE = `YASHSCRIPT:

criar objeto 'placar'
    moedas = 0
    tempo = 30
    vidas = 3
    terminou = 0
fim

criar painel 'placarTexto'
    largura = 320
    altura = 74
    posicao = (20, 20)
    cor = rgb(12, 14, 22)
    transparencia = 25
    estilo = "caixa"
fim

criar texto 'titulo'
    pai = "placarTexto"
    texto = "YASHDASH"
    posicao = (14, 8)
    tamanho_fonte = 24
    cor = rgb(255, 214, 0)
    estilo = "branco"
fim

criar texto 'instrucoes'
    pai = "placarTexto"
    texto = "Pegue as 3 moedas amarelas. Desvie da esfera vermelha. 30 segundos!"
    posicao = (14, 38)
    tamanho_fonte = 14
    cor = rgb(226, 232, 240)
    estilo = "branco"
fim

a cada 1
    se placar.terminou = 0 entao
        placar.tempo -= 1
        placar.moedas += 1
    fim
fim

quando iniciar
    se "placar" criado com sucesso entao
        print("YASHDASH: interface carregada")
    fim
fim
`;

// ===========================================================================
// COMPILACAO (mesmo caminho do plugin)
// ===========================================================================
function compilar(fonteYash) {
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);

	lua.lua_newtable(L);
	lua.lua_pushstring(L, to_luastring("compilador"));
	lua.lua_pushstring(L, to_luastring(ler("compilador/compilador.lua")));
	lua.lua_settable(L, -3);
	lua.lua_setglobal(L, to_luastring("ENTRADA"));

	const harness = `
local f = assert(load(ENTRADA.compilador, "compilador"))
local comp = f()
local fonte = [==[${fonteYash}]==]
local ok, res = comp.Compilar(fonte, {})
if not ok then
	SAIDA = "!! ERRO linha " .. tostring(res.linha) .. ": " .. tostring(res.erro)
	return
end
local plano = comp.Descompilar(res)
if not plano then
	SAIDA = "!! ERRO ao descompilar"
	return
end
local ok2, res2 = comp.Compilar(plano, {})
if not ok2 then
	SAIDA = "!! ERRO no round-trip linha " .. tostring(res2.linha) .. ": " .. tostring(res2.erro)
	return
end
local igual = comp.Serializar(res) == comp.Serializar(res2)
SAIDA = "OK|" .. comp.Serializar(res) .. "|" .. tostring(igual)
`;
	lua.lua_newtable(L);
	lua.lua_pushstring(L, to_luastring("SAIDA"));
	lua.lua_pushnil(L);
	lua.lua_settable(L, -3);
	lua.lua_setglobal(L, to_luastring("SAIDA"));

	if (lauxlib.luaL_loadstring(L, to_luastring(harness)) !== lua.LUA_OK) {
		throw new Error("harness: " + lua.lua_tolstring(L, -1, null));
	}
	if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
		throw new Error("exec: " + lua.lua_tolstring(L, -1, null));
	}
	lua.lua_getglobal(L, to_luastring("SAIDA"));
	return Buffer.from(lua.lua_tolstring(L, -1, null)).toString("utf8");
}

let roundTrip = null;

function montarLuau(fonteYash, chamada, classe) {
	const saida = compilar(fonteYash);
	if (saida.indexOf("!!") === 0) {
		throw new Error(classe + ": " + saida);
	}
	const partes = saida.split("|");
	const literal = partes[1].replace(/^return\s+/, "");
	roundTrip = partes[2];

	return [
		"--[[ YASHDASH - gerado a partir do YashScript. ]]",
		'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
		'local YashMod = ReplicatedStorage:WaitForChild("Yash")',
		'local Runtime = require(YashMod:WaitForChild("Runtime"))',
		"",
		MARCA_INI,
		PREAMBULO,
		"local _YashConfig = " + literal,
		MARCA_FIM,
		"Runtime." + chamada + "(_YashConfig)",
		"",
	].join("\n").replace(/\t/g, "    ");
}

// ===========================================================================
const salvar = process.argv.includes("--salvar");
const servidor = montarLuau(SERVIDOR, "montarMundo", "servidor");
const cliente = montarLuau(CLIENTE, "executar", "cliente");

console.log("[OK] servidor compila (" + Buffer.byteLength(servidor) + " bytes, Runtime.montarMundo) round-trip=" + roundTrip);
console.log("[OK] cliente  compila (" + Buffer.byteLength(cliente) + " bytes, Runtime.executar)");

if (salvar) {
	const dir = path.join(raiz, "minijogo");
	if (!fs.existsSync(dir)) fs.mkdirSync(dir);
	fs.writeFileSync(path.join(dir, "servidor.lua"), servidor, "utf8");
	fs.writeFileSync(path.join(dir, "cliente.lua"), cliente, "utf8");
	fs.writeFileSync(path.join(dir, "servidor.fonte"), SERVIDOR, "utf8");
	fs.writeFileSync(path.join(dir, "cliente.fonte"), CLIENTE, "utf8");
	console.log("gravado em minijogo/");
} else {
	const erros = [];
	for (const nome of ["moedaA", "moedaB", "moedaC"]) {
		if (servidor.indexOf(nome) < 0) erros.push(nome);
	}
	if (erros.length) console.log("[!] ausentes no Luau: " + erros.join(", "));
	else console.log("[OK] formas, acoes e eventos presentes no Luau gerado");
}