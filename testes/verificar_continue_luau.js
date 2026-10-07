// Gera scripts representativos e valida sintaxe e execução com ferramentas Luau reais.
// A VM Fengari testa o parser YashScript; luau-analyze/luau executam o Luau gerado.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const raiz = path.join(__dirname, "..");
const s = (v) => to_luastring(v, true);
const ler = (rel) => fs.readFileSync(path.join(raiz, rel), "utf8").replace(/^\uFEFF/, "");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function executarFonte(fonte, nome, nResultados) {
  const st = lauxlib.luaL_loadbuffer(L, s(fonte), null, s(nome));
  if (st !== lua.LUA_OK) throw new Error("erro de sintaxe em " + nome + ": " + to_jsstring(lua.lua_tolstring(L, -1)));
  if (lua.lua_pcall(L, 0, nResultados, 0) !== lua.LUA_OK) {
    throw new Error("erro ao executar " + nome + ": " + to_jsstring(lua.lua_tolstring(L, -1)));
  }
}

executarFonte(ler("compilador/compilador.lua"), "compilador", 1);
lua.lua_setglobal(L, s("Compilador"));
executarFonte(ler("compilador/gerador.lua"), "gerador", 1);
lua.lua_setglobal(L, s("Gerador"));
lua.lua_pushstring(L, s(ler("LOGS/continue.yash")));
lua.lua_setglobal(L, s("Fonte"));

const wrapper = `
local ok, programa = Compilador.Compilar(Fonte)
if not ok then error(programa.erro .. " (linha " .. tostring(programa.linha) .. ")") end
local gerou, codigo = Gerador.GerarLuau(programa, { contexto = "comum", modulo = false })
if not gerou then error(codigo.erro) end
return codigo
`;
executarFonte(wrapper, "validar continuar", 1);
const luau = to_jsstring(lua.lua_tolstring(L, -1));
if (!luau.includes("continue")) throw new Error("o Luau gerado não contém continue");

const analyzer = process.env.LUAU_ANALYZE
  || "C:\\Users\\yashi\\AppData\\Local\\luau\\bin\\luau-analyze.exe";
if (!fs.existsSync(analyzer)) throw new Error("luau-analyze não encontrado: " + analyzer);
const luauCli = process.env.LUAU_CLI
  || path.join(path.dirname(analyzer), "luau.exe");
if (!fs.existsSync(luauCli)) throw new Error("CLI Luau não encontrado: " + luauCli);
const temp = path.join(os.tmpdir(), "yashscript-continue-" + process.pid + ".luau");
try {
  fs.writeFileSync(temp, luau, "utf8");
  const r = spawnSync(analyzer, [temp], { encoding: "utf8" });
  const output = (r.stdout || "") + (r.stderr || "");
  if (r.error) throw r.error;
  if (/SyntaxError\s*:/i.test(output)) throw new Error(output.trim());
  const execucao = spawnSync(luauCli, [temp], { encoding: "utf8" });
  const saidaExecucao = (execucao.stdout || "").trim();
  if (execucao.error) throw execucao.error;
  if (execucao.status !== 0) throw new Error((execucao.stderr || saidaExecucao || "execução Luau falhou").trim());
  if (saidaExecucao !== "4") throw new Error("resultado do laço com continuar esperado 4, recebido: " + saidaExecucao);
  console.log("[OK] continuar compila e executa no Luau; resultado = 4");

  lua.lua_pushstring(L, s(ler("LOGS/repeticoes.yash") + "print(Resultado())\n"));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar repita/ate", 1);
  const codigoRepita = to_jsstring(lua.lua_tolstring(L, -1));
  if (!codigoRepita.includes("repeat") || !codigoRepita.includes("until ")) {
    throw new Error("repita/ate não gerou repeat/until Luau");
  }
  const tempRepita = path.join(os.tmpdir(), "yashscript-repita-" + process.pid + ".luau");
  try {
    fs.writeFileSync(tempRepita, codigoRepita, "utf8");
    const lintRepita = spawnSync(analyzer, [tempRepita], { encoding: "utf8" });
    const diagRepita = (lintRepita.stdout || "") + (lintRepita.stderr || "");
    if (lintRepita.error) throw lintRepita.error;
    if (/SyntaxError\s*:/i.test(diagRepita)) throw new Error(diagRepita.trim());
    const execRepita = spawnSync(luauCli, [tempRepita], { encoding: "utf8" });
    if (execRepita.error) throw execRepita.error;
    if (execRepita.status !== 0) throw new Error((execRepita.stderr || "execução de repita/ate falhou").trim());
    if ((execRepita.stdout || "").replace(/\r/g, "").trim() !== "36") {
      throw new Error("resultado de repita/ate esperado 36, recebido: " + (execRepita.stdout || "").trim());
    }
    console.log("[OK] repita/ate gera e executa como repeat/until no Luau; resultado = 36");
  } finally {
    try { fs.unlinkSync(tempRepita); } catch {}
  }

  const fonteApis = `
variavel Peca = Instance.new("Part")
Peca.Name = "Teste"
Peca.Position = Vector3.new(1, 2, 3)
Peca.Material = Enum.Material.Neon
Peca.Parent = workspace
print(Peca.Name, typeof(Peca.Position), Peca.Material)
`;
  lua.lua_pushstring(L, s(fonteApis));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar globais Roblox/Luau", 1);
  const codigoApis = to_jsstring(lua.lua_tolstring(L, -1));
  for (const nome of ["Instance.new", "Vector3.new", "Enum.Material.Neon", "typeof("]) {
    if (!codigoApis.includes(nome)) throw new Error("global Roblox/Luau não foi preservado: " + nome);
  }
  const tempApis = path.join(os.tmpdir(), "yashscript-globais-luau-" + process.pid + ".luau");
  try {
    const harnessApis = `
local workspaceMock = {}
game = { GetService = function(_, nome) if nome == "Workspace" then return workspaceMock end end }
workspace = workspaceMock
Enum = { Material = { Neon = "Neon" } }
Instance = { new = function(className) return { ClassName = className } end }
Vector3 = { new = function(x, y, z) return { __type = "Vector3", X = x, Y = y, Z = z } end }
typeof = function(v) return type(v) == "table" and v.__type or type(v) end
` + codigoApis;
    fs.writeFileSync(tempApis, harnessApis, "utf8");
    const lintApis = spawnSync(analyzer, [tempApis], { encoding: "utf8" });
    const diagApis = (lintApis.stdout || "") + (lintApis.stderr || "");
    if (lintApis.error) throw lintApis.error;
    if (/SyntaxError\s*:/i.test(diagApis)) throw new Error(diagApis.trim());
    const execApis = spawnSync(luauCli, [tempApis], { encoding: "utf8" });
    if (execApis.error) throw execApis.error;
    if (execApis.status !== 0) throw new Error((execApis.stderr || "execução de APIs Luau falhou").trim());
    if ((execApis.stdout || "").replace(/\s+/g, " ").trim() !== "Teste Vector3 Neon") {
      throw new Error("resultado de APIs Luau incorreto: " + (execApis.stdout || "").trim());
    }
    console.log("[OK] Instance, Vector3, Enum, workspace e typeof funcionam em expressões YashScript");
  } finally {
    try { fs.unlinkSync(tempApis); } catch {}
  }

  const fonteCondicionais = ler("LOGS/condicionais.yash")
    + "quando iniciar\n    variavel ExibidoTopo = 0\n"
    + "    se 1 == 2\n        ExibidoTopo = 10\n"
    + "    senao se 1 == 1\n        ExibidoTopo = 20\n"
    + "    senao\n        ExibidoTopo = 30\n    fim\n"
    + "    print(ExibidoTopo, Escolher(4), \"nível \" .. Escolher(2))\nfim\n";
  lua.lua_pushstring(L, s(fonteCondicionais));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar senao se", 1);
  const codigoCondicionais = to_jsstring(lua.lua_tolstring(L, -1));
  if (!codigoCondicionais.includes("elseif")) throw new Error("senao se não gerou elseif");
  const tempCondicionais = path.join(os.tmpdir(), "yashscript-elseif-" + process.pid + ".luau");
  try {
    fs.writeFileSync(tempCondicionais, codigoCondicionais, "utf8");
    const lintCondicionais = spawnSync(analyzer, [tempCondicionais], { encoding: "utf8" });
    const diagCondicionais = (lintCondicionais.stdout || "") + (lintCondicionais.stderr || "");
    if (lintCondicionais.error) throw lintCondicionais.error;
    if (/SyntaxError\s*:/i.test(diagCondicionais)) throw new Error(diagCondicionais.trim());
    const execCondicionais = spawnSync(luauCli, [tempCondicionais], { encoding: "utf8" });
    if (execCondicionais.error) throw execCondicionais.error;
    if (execCondicionais.status !== 0) throw new Error((execCondicionais.stderr || "execução de senao se falhou").trim());
    const resultadoCondicionais = (execCondicionais.stdout || "").replace(/\r/g, "").trim().replace(/\s+/g, " ");
    if (resultadoCondicionais !== "20 40 nível 20") throw new Error("resultado de senao se/print esperado '20 40 nível 20', recebido: " + resultadoCondicionais);
    console.log("[OK] senao se e print com expressões aninhadas executam no Luau");
  } finally {
    try { fs.unlinkSync(tempCondicionais); } catch {}
  }

  const fonteEscopos = ler("LOGS/escopos_funcao.yash")
    + "\nquando iniciar\n    print(Proxima(), Proxima(), UsarMesmoNome(), SomarGlobal(2))\nfim\n";
  lua.lua_pushstring(L, s(fonteEscopos));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar escopo de função", 1);
  const codigoEscopos = to_jsstring(lua.lua_tolstring(L, -1));
  const tempEscopos = path.join(os.tmpdir(), "yashscript-escopos-funcao-" + process.pid + ".luau");
  try {
    fs.writeFileSync(tempEscopos, codigoEscopos, "utf8");
    const lintEscopos = spawnSync(analyzer, [tempEscopos], { encoding: "utf8" });
    const diagEscopos = (lintEscopos.stdout || "") + (lintEscopos.stderr || "");
    if (lintEscopos.error) throw lintEscopos.error;
    if (/SyntaxError\s*:/i.test(diagEscopos)) throw new Error(diagEscopos.trim());
    const execEscopos = spawnSync(luauCli, [tempEscopos], { encoding: "utf8" });
    if (execEscopos.error) throw execEscopos.error;
    if (execEscopos.status !== 0) throw new Error((execEscopos.stderr || "execução dos escopos falhou").trim());
    const resultadoEscopos = (execEscopos.stdout || "").replace(/\r/g, "").trim().replace(/\s+/g, " ");
    if (resultadoEscopos !== "1 1 acao-finalizada 1 1 7 101") throw new Error("resultado de escopos esperado '1 1 acao-finalizada 1 1 7 101', recebido: " + resultadoEscopos + "\n" + codigoEscopos);
    console.log("[OK] variáveis locais de função são isoladas em execução Luau real");
  } finally {
    try { fs.unlinkSync(tempEscopos); } catch {}
  }

  lua.lua_pushstring(L, s(ler("LOGS/escopos_evento.yash")));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar escopo de eventos", 1);
  const codigoEventos = to_jsstring(lua.lua_tolstring(L, -1));
  const locaisEvento = (codigoEventos.match(/local Temporario/g) || []).length;
  if (locaisEvento !== 2) throw new Error("cada callback deveria declarar seu próprio Temporario");
  const tempEventos = path.join(os.tmpdir(), "yashscript-escopos-evento-" + process.pid + ".luau");
  try {
    const harnessEventos = `
local _callbacks = {}
local _workspace = {}
local function novaPeca()
  return { MouseButton1Click = { Connect = function(_, callback) table.insert(_callbacks, callback) end } }
end
_workspace.Botao = novaPeca()
_workspace.Outro = novaPeca()
_workspace.WaitForChild = function(self, nome) return self[nome] end
game = { GetService = function() return _workspace end }
` + codigoEventos + "\n_callbacks[1]()\n_callbacks[2]()\n";
    fs.writeFileSync(tempEventos, harnessEventos, "utf8");
    const lintEventos = spawnSync(analyzer, [tempEventos], { encoding: "utf8" });
    const diagEventos = (lintEventos.stdout || "") + (lintEventos.stderr || "");
    if (lintEventos.error) throw lintEventos.error;
    if (/SyntaxError\s*:/i.test(diagEventos)) throw new Error(diagEventos.trim());
    const execEventos = spawnSync(luauCli, [tempEventos], { encoding: "utf8" });
    if (execEventos.error) throw execEventos.error;
    if (execEventos.status !== 0) throw new Error((execEventos.stderr || "execução dos callbacks falhou").trim() + "\n" + codigoEventos);
    const resultadoEventos = (execEventos.stdout || "").replace(/\r/g, "").trim().replace(/\s+/g, " ");
    if (resultadoEventos !== "1 1") throw new Error("callbacks esperados 1 1 sem continuar após retornar, recebido: " + resultadoEventos);
    console.log("[OK] callbacks locais reiniciam e retornar encerra o handler no Luau");
  } finally {
    try { fs.unlinkSync(tempEventos); } catch {}
  }

  lua.lua_pushstring(L, s(ler("LOGS/retorno_temporizador.yash")));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar retorno do temporizador", 1);
  const codigoTemporizador = to_jsstring(lua.lua_tolstring(L, -1));
  const tempTemporizador = path.join(os.tmpdir(), "yashscript-retorno-temporizador-" + process.pid + ".luau");
  try {
    const harnessTemporizador = `
local esperaChamadas = 0
task = {
  spawn = function(callback) callback() end,
  wait = function() esperaChamadas += 1; if esperaChamadas > 0 then error("retornar não encerrou o temporizador") end end,
}
` + codigoTemporizador;
    fs.writeFileSync(tempTemporizador, harnessTemporizador, "utf8");
    const lintTemporizador = spawnSync(analyzer, [tempTemporizador], { encoding: "utf8" });
    const diagTemporizador = (lintTemporizador.stdout || "") + (lintTemporizador.stderr || "");
    if (lintTemporizador.error) throw lintTemporizador.error;
    if (/SyntaxError\s*:/i.test(diagTemporizador)) throw new Error(diagTemporizador.trim());
    const execTemporizador = spawnSync(luauCli, [tempTemporizador], { encoding: "utf8" });
    if (execTemporizador.error) throw execTemporizador.error;
    if (execTemporizador.status !== 0) throw new Error((execTemporizador.stderr || "temporizador não encerrou").trim());
    if ((execTemporizador.stdout || "").replace(/\r/g, "").trim() !== "1") {
      throw new Error("temporizador deveria executar uma vez e retornar");
    }
    console.log("[OK] retornar encerra a task.spawn do temporizador no Luau");
  } finally {
    try { fs.unlinkSync(tempTemporizador); } catch {}
  }

  // --- chamada de metodo como instrucao avulsa, executada no Luau real ---
  lua.lua_pushstring(L, s("usar \"Peca\" = Workspace.Peca\nPeca:Somar(2, 3)\ncriar funcao Finalizar()\n    Peca.destruir()\nfim\nFinalizar()\n"));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar chamada de metodo", 1);
  const codigoMetodo = to_jsstring(lua.lua_tolstring(L, -1));
  if (!codigoMetodo.includes(":Somar(2, 3)")) {
    throw new Error("Peca:Somar(2, 3) nao virou chamada de metodo Luau:\n" + codigoMetodo);
  }
  if (!/Peca:Destroy\(\)/.test(codigoMetodo)) {
    throw new Error("Peca.destruir() nao virou Peca:Destroy():\n" + codigoMetodo);
  }
  const tempMetodo = path.join(os.tmpdir(), "yashscript-metodo-" + process.pid + ".luau");
  try {
    const harnessMetodo = [
      "local registro = {}",
      "local _workspace = {",
      "  Peca = {",
      "    Somar = function(self, a, b) table.insert(registro, 'somar:' .. (a + b)) end,",
      "    Destroy = function(self) table.insert(registro, 'destruir') end,",
      "    IsA = function() return false end,",
      "  },",
      "  WaitForChild = function(self, nome) return self[nome] end,",
      "}",
      "game = { GetService = function() return _workspace end }",
      "",
    ].join("\n") + codigoMetodo + '\nprint(table.concat(registro, " "))\n';
    fs.writeFileSync(tempMetodo, harnessMetodo, "utf8");
    const lintMetodo = spawnSync(analyzer, [tempMetodo], { encoding: "utf8" });
    const diagMetodo = (lintMetodo.stdout || "") + (lintMetodo.stderr || "");
    if (lintMetodo.error) throw lintMetodo.error;
    if (/SyntaxError\s*:/i.test(diagMetodo)) throw new Error(diagMetodo.trim());
    const execMetodo = spawnSync(luauCli, [tempMetodo], { encoding: "utf8" });
    if (execMetodo.error) throw execMetodo.error;
    if (execMetodo.status !== 0) {
      throw new Error((execMetodo.stderr || "execucao das chamadas de metodo falhou").trim() + "\n" + codigoMetodo);
    }
    const resultadoMetodo = (execMetodo.stdout || "").replace(/\r/g, "").trim();
    if (resultadoMetodo !== "somar:5 destruir") {
      throw new Error('chamadas de metodo esperadas "somar:5 destruir", recebido: ' + resultadoMetodo);
    }
    console.log("[OK] chamada de metodo avulsa (dois pontos e ponto) executa no Luau");
  } finally {
    try { fs.unlinkSync(tempMetodo); } catch {}
  }


  // --- escapes de texto: o Luau gerado tem de ser valido e imprimir igual ---
  lua.lua_pushstring(L, s("YASHSCRIPT:\nvariavel A = \"aspas \\\" barra \\\\ quebra \\n tab\\t fim\"\nprint(A)\n"));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar escapes", 1);
  const codigoEsc = to_jsstring(lua.lua_tolstring(L, -1));
  // uma quebra de linha REAL dentro do literal quebraria o arquivo inteiro
  if (/=\s*"[^"\n]*\n[^"]*"/.test(codigoEsc)) {
    throw new Error("literal de texto com quebra de linha real no Luau gerado:\n" + codigoEsc);
  }
  const tempEsc = path.join(os.tmpdir(), "yashscript-escapes-" + process.pid + ".luau");
  try {
    fs.writeFileSync(tempEsc, codigoEsc, "utf8");
    const lintEsc = spawnSync(analyzer, [tempEsc], { encoding: "utf8" });
    const diagEsc = (lintEsc.stdout || "") + (lintEsc.stderr || "");
    if (lintEsc.error) throw lintEsc.error;
    if (/SyntaxError\s*:/i.test(diagEsc)) throw new Error(diagEsc.trim());
    const execEsc = spawnSync(luauCli, [tempEsc], { encoding: "utf8" });
    if (execEsc.error) throw execEsc.error;
    if (execEsc.status !== 0) throw new Error((execEsc.stderr || "execucao dos escapes falhou").trim());
    // print() acrescenta a quebra de linha final
    const esperadoEsc = 'aspas " barra \\ quebra \n tab\t fim\n';
    const obtidoEsc = (execEsc.stdout || "").replace(/\r\n/g, "\n");
    if (obtidoEsc !== esperadoEsc) {
      throw new Error(
        "texto nao sobreviveu ao ciclo. esperado " + JSON.stringify(esperadoEsc)
        + ", obtido " + JSON.stringify(obtidoEsc)
      );
    }
    console.log("[OK] escapes de texto sobrevivem ao ciclo e geram Luau valido no Luau");
  } finally {
    try { fs.unlinkSync(tempEsc); } catch {}
  }

  // --- expoente cientifico ---
  lua.lua_pushstring(L, s("YASHSCRIPT:\nvariavel A = 1e-7\nvariavel B = 2.5E+3\nvariavel C = 0.0000001\nprint(type(A), B, C == A)\n"));
  lua.lua_setglobal(L, s("Fonte"));
  executarFonte(wrapper, "validar expoente", 1);
  const codigoExp = to_jsstring(lua.lua_tolstring(L, -1));
  if (/\band\b/.test(codigoExp)) {
    throw new Error("expoente foi lido como operador 'e':\n" + codigoExp);
  }
  const tempExp = path.join(os.tmpdir(), "yashscript-expoente-" + process.pid + ".luau");
  try {
    fs.writeFileSync(tempExp, codigoExp, "utf8");
    const lintExp = spawnSync(analyzer, [tempExp], { encoding: "utf8" });
    const diagExp = (lintExp.stdout || "") + (lintExp.stderr || "");
    if (lintExp.error) throw lintExp.error;
    if (/SyntaxError\s*:/i.test(diagExp)) throw new Error(diagExp.trim());
    const execExp = spawnSync(luauCli, [tempExp], { encoding: "utf8" });
    if (execExp.error) throw execExp.error;
    if (execExp.status !== 0) throw new Error((execExp.stderr || "execucao do expoente falhou").trim());
    // print() do Luau separa argumentos com tab
    const obtidoExp = (execExp.stdout || "").trim().split(/\s+/);
    if (obtidoExp.length !== 3 || obtidoExp[0] !== "number" || obtidoExp[1] !== "2500" || obtidoExp[2] !== "true") {
      throw new Error('expoente esperado [number, 2500, true], obtido: ' + JSON.stringify(obtidoExp));
    }
    console.log("[OK] expoente cientifico (1e-7, 2.5E+3) le como numero no Luau");
  } finally {
    try { fs.unlinkSync(tempExp); } catch {}
  }

} finally {
  try { fs.unlinkSync(temp); } catch {}
}
