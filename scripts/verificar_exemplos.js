// Compila e gera Luau de cada exemplo .yash de LOGS/ pelo pipeline real.
//   Uso:  node scripts/verificar_exemplos.js [filtro]
// Garante que a documentacao em LOGS/ continue compativel com o V8.
const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const raiz = path.join(__dirname, "..");
const LOGS = path.join(raiz, "LOGS");
const ler = (p) => fs.readFileSync(p, "utf8").replace(/\r\n/g, "\n");
const s = (t) => to_luastring(t, true);

const CONTEXTO = {
  "colecoes.yash": "cliente",
  "continue.yash": "cliente",
  "funcoes.yash": "cliente",
  "fundamentos.yash": "cliente",
  "menu_camera.yash": "cliente",
  "repeticoes.yash": "cliente",
};

const filtro = process.argv[2] || null;
const casos = fs
  .readdirSync(LOGS)
  .filter((f) => f.endsWith(".yash"))
  .filter((f) => (filtro ? f.includes(filtro) : true))
  // O contexto vem da CLASSE do script no Studio, nao do texto. Esta
  // ferramenta nao tem classe, entao os exemplos declaram aqui o que
  // o cabecalho `YASHSCRIPT:` usava declarar (e que nunca teve efeito).
  .map((f) => f + "\0" + (CONTEXTO[f] || "comum") + "\0" + ler(path.join(LOGS, f)));

if (casos.length === 0) {
  console.error("ERRO: nenhum exemplo .yash encontrado em LOGS");
  process.exit(1);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// monta a tabela V { COMPILADOR, GERADOR, CASOS } e publica
lua.lua_newtable(L);
const campo = (chave, valor) => {
  lua.lua_pushstring(L, s(chave));
  if (typeof valor === "string") {
    lua.lua_pushstring(L, s(valor));
  } else {
    lua.lua_newtable(L);
    valor.forEach((v, i) => {
      lua.lua_pushstring(L, s(v));
      lua.lua_rawseti(L, -2, i + 1);
    });
  }
  lua.lua_settable(L, -3);
};
campo("COMPILADOR", ler(path.join(raiz, "compilador/compilador.lua")));
campo("GERADOR", ler(path.join(raiz, "compilador/gerador.lua")));
campo("CASOS", casos);
lua.lua_setglobal(L, s("V"));

// NUL separa nome do fonte, contexto e codigo.
const fonte = `
local comp = assert((loadstring or load)(V.COMPILADOR))()
local ger = assert((loadstring or load)(V.GERADOR))()
for _, bruto in ipairs(V.CASOS) do
  local sep1 = bruto:find("\\0", 1, true)
  local sep2 = bruto:find("\\0", sep1 + 1, true)
  local nome = bruto:sub(1, sep1 - 1)
  local ctx = bruto:sub(sep1 + 1, sep2 - 1)
  local codigo = bruto:sub(sep2 + 1)
  local ok, prog = comp.Compilar(codigo, {})
  if not ok then
    print("FALHA " .. nome .. " [compilar]: " .. tostring(prog.erro))
  else
    local ok2, r = ger.GerarLuau(prog, { contexto = ctx, modulo = (prog.modulo == true) })
    if not ok2 then
      print("FALHA " .. nome .. " [gerar]: " .. tostring(r.erro) .. " (linha " .. tostring(r.linha) .. ")")
    else
      print("ok    " .. nome .. " [" .. ctx .. "] -> " .. #r .. " bytes de Luau")
    end
  end
end
`;
const st = lauxlib.luaL_loadstring(L, s(fonte));
if (st !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1), true));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1), true));
