// Gera testes/inserir_demo_*.lua — scripts Luau de Edit que simulam o output
// do plugin em execuções MCP menores:
//   1) inserir_demo_rt.lua     -> instala ReplicatedStorage.Yash.Runtime
//   2) inserir_demo_main.lua   -> cria StarterPlayerScripts.MainYash (GUI)
//   3) inserir_demo_mundo.lua  -> cria ServerScriptService.MundoYash (mundo 3D)
// Formato gerado (YASHC + literal config) idêntico ao do plugin.
// Blobs são emitidos em linhas curtas (table.concat) para transporte via MCP.
const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const raiz = path.join(__dirname, "..");
function ler(rel) { return fs.readFileSync(path.join(raiz, rel), "utf8").replace(/\r\n/g, "\n"); }
function luaStr(s) {
  return '"' + s
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\t/g, "\\t") + '"';
}
function chunkLua(texto, varName) {
  const out = [`local ${varName} = {}`, `local ${varName}_n = 0`];
  for (let i = 0; i < texto.length; i += 100) {
    out.push(`${varName}_n = ${varName}_n + 1; ${varName}[${varName}_n] = ${luaStr(texto.slice(i, i + 100))}`);
  }
  out.push(`local ${varName}_S = table.concat(${varName})`);
  return out.join("\n");
}

// compila um .yash dentro do fengari e serializa a config
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function rodar(code) {
  const st = lauxlib.luaL_loadstring(L, to_luastring(code));
  if (st !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tolstring(L, -1, 0)));
  const r = lua.lua_pcall(L, 0, -1, 0);
  if (r !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tolstring(L, -1, 0)));
  const n = lua.lua_gettop(L);
  const res = [];
  for (let i = 1; i <= n; i++) {
    const t = lua.lua_type(L, i);
    if (t === lua.LUA_TSTRING) res.push(to_jsstring(lua.lua_tolstring(L, i, 0)));
    else if (t === lua.LUA_TNUMBER) res.push(lua.lua_tonumber(L, i));
  }
  lua.lua_settop(L, 0);
  return res.length === 1 ? res[0] : res;
}

const compilerSrc = ler("compilador/compilador.lua");
rodar("local c = " + JSON.stringify(compilerSrc) + " ; _G.compFonte = c");
rodar(`local f = assert(load(_G.compFonte))(); _G.comp = f`);

function compilarYash(nomeArquivo, arquivosAdicionais) {
  const src = ler("testes/exemplos/" + nomeArquivo);
  const add = arquivosAdicionais || {};
  const chaves = Object.keys(add).map(k => `["${k}"] = ${luaStr(add[k])}`).join(", ");
  const literal = rodar(`local c = _G.comp
local ok, res = c.Compilar(${luaStr(src)}, { ${chaves} })
if not ok then error(tostring(res.erro)) end
return c.Serializar(res)`).toString().replace(/^return\s+/, "");
  const servidor = rodar(`local c = _G.comp
local ok, res = c.Compilar(${luaStr(src)}, { ${chaves} })
if not ok then error(tostring(res.erro)) end
return res.regime == "servidor"`) === true || rodar(`local c = _G.comp
local ok, res = c.Compilar(${luaStr(src)}, { ${chaves} })
if not ok then error(tostring(res.erro)) end
return res.regime == "servidor"`) === true;
  return { literal, servidor };
}

function textoGerado(literal) {
  const helpers =
    "local function cor(r, g, b) return { t = \"cor\", r = r, g = g, b = b } end\n"
    + "local function par(x, y, z) if z == nil then return { t = \"par\", x = x, y = y } end return { t = \"par\", x = x, y = y, z = z } end\n";
  return "--[[ YashScript V7.0 - gerado pelo plugin. Edite pelo plugin. ]]\n"
    + "local ReplicatedStorage = game:GetService(\"ReplicatedStorage\")\n"
    + "local YashMod = ReplicatedStorage:WaitForChild(\"Yash\")\n"
    + "local Runtime = require(YashMod:WaitForChild(\"Runtime\"))\n"
    + "\n--YASHC1--\n"
    + helpers
    + "local _YashConfig = " + literal + "\n"
    + "--YASHC2--\n";
}

// ------------------------------------------------------------------
// Runtime único (V7.0)
// ------------------------------------------------------------------
const partesRt = [];
partesRt.push(`local ReplicatedStorage = game:GetService("ReplicatedStorage")`);
partesRt.push(`local Yash = ReplicatedStorage:FindFirstChild("Yash")`);
partesRt.push(`if not Yash then Yash = Instance.new("Folder"); Yash.Name = "Yash"; Yash.Parent = ReplicatedStorage end`);
partesRt.push(chunkLua(ler("compilador/runtime.lua"), "BlobRt"));
partesRt.push(`local rt = Yash:FindFirstChild("Runtime")`);
partesRt.push(`if not rt then rt = Instance.new("ModuleScript"); rt.Name = "Runtime"; rt.Parent = Yash end`);
partesRt.push(`rt.Source = BlobRt_S`);
partesRt.push(`print("[MCP] Runtime instalado (" .. utf8.len(rt.Source) .. " chars)")`);
fs.writeFileSync(path.join(raiz, "testes", "inserir_demo_rt.lua"), partesRt.join("\n") + "\n", "utf8");

// ------------------------------------------------------------------
// 1) GUI principal (main.yash) -> MainYash (LocalScript)
// ------------------------------------------------------------------
const visSrc = ler("testes/exemplos/visual.yash");
const resMain = compilarYash("main.yash", { ["visual.yash"]: visSrc });
const literalMain = resMain.literal;
const luauMain = textoGerado(literalMain) + "Runtime.executar(_YashConfig)\n";

const partesMain = [];
partesMain.push(`local ReplicatedStorage = game:GetService("ReplicatedStorage")`);
partesMain.push(`local StarterPlayerScripts = game:GetService("StarterPlayerScripts")`);
partesMain.push(chunkLua(luauMain, "BlobMain"));
partesMain.push(`local Main = StarterPlayerScripts:FindFirstChild("MainYash")`);
partesMain.push(`if not Main then Main = Instance.new("LocalScript"); Main.Name = "MainYash"; Main.Parent = StarterPlayerScripts end`);
partesMain.push(`Main.Source = BlobMain_S`);
partesMain.push(`print("[MCP] MainYash (GUI) gerado (" .. utf8.len(Main.Source) .. " chars)")`);
fs.writeFileSync(path.join(raiz, "testes", "inserir_demo_main.lua"), partesMain.join("\n") + "\n", "utf8");
fs.writeFileSync(path.join(raiz, "testes", "luau_gerado_exemplo.lua"), luauMain, "utf8");

// ------------------------------------------------------------------
// 2) Jogo (jogo.yash) -> MundoYash (Script) + MainYash funcional
// ------------------------------------------------------------------
const resJogo = compilarYash("jogo.yash");
const literalJogo = resJogo.literal;

// MainYash do jogo (LocalScript cliente) — mesmo config, chama executar
const luauJogoCliente = textoGerado(literalJogo) + "Runtime.executar(_YashConfig)\n";
const partesJogoMain = [];
partesJogoMain.push(`local ReplicatedStorage = game:GetService("ReplicatedStorage")`);
partesJogoMain.push(`local StarterPlayerScripts = game:GetService("StarterPlayerScripts")`);
partesJogoMain.push(chunkLua(luauJogoCliente, "BlobJogoMain"));
partesJogoMain.push(`local Main = StarterPlayerScripts:FindFirstChild("MainYash")`);
partesJogoMain.push(`if not Main then Main = Instance.new("LocalScript"); Main.Name = "MainYash"; Main.Parent = StarterPlayerScripts end`);
partesJogoMain.push(`Main.Source = BlobJogoMain_S`);
partesJogoMain.push(`print("[MCP] MainYash (jogo/cliente) gerado (" .. utf8.len(Main.Source) .. " chars)")`);
fs.writeFileSync(path.join(raiz, "testes", "inserir_demo_jogo_main.lua"), partesJogoMain.join("\n") + "\n", "utf8");

// MundoYash do jogo (Script servidor) — mesmo config, chama montarMundo
const luauJogoMundo = textoGerado(literalJogo) + "Runtime.montarMundo(_YashConfig)\n";
const partesJogoMundo = [];
partesJogoMundo.push(`local ReplicatedStorage = game:GetService("ReplicatedStorage")`);
partesJogoMundo.push(`local ServerScriptService = game:GetService("ServerScriptService")`);
partesJogoMundo.push(chunkLua(luauJogoMundo, "BlobJogoMundo"));
partesJogoMundo.push(`local Mundo = ServerScriptService:FindFirstChild("MundoYash")`);
partesJogoMundo.push(`if not Mundo then Mundo = Instance.new("Script"); Mundo.Name = "MundoYash"; Mundo.Parent = ServerScriptService end`);
partesJogoMundo.push(`Mundo.Source = BlobJogoMundo_S`);
partesJogoMundo.push(`print("[MCP] MundoYash (servidor) gerado (" .. utf8.len(Mundo.Source) .. " chars)")`);
fs.writeFileSync(path.join(raiz, "testes", "inserir_demo_mundo.lua"), partesJogoMundo.join("\n") + "\n", "utf8");

console.log("inserir_demo_rt.lua        (" + partesRt.join("\n").split("\n").length + " linhas)");
console.log("inserir_demo_main.lua      (GUI, " + partesMain.join("\n").split("\n").length + " linhas)");
console.log("inserir_demo_jogo_main.lua (cliente, " + partesJogoMain.join("\n").split("\n").length + " linhas)");
console.log("inserir_demo_mundo.lua     (servidor, " + partesJogoMundo.join("\n").split("\n").length + " linhas)");
console.log("config main: " + literalMain.length + " chars | config jogo: " + literalJogo.length + " chars");