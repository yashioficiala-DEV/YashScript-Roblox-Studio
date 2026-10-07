// Localiza os binários do Luau (luau-analyze e luau) no sistema.
// Procura, nesta ordem:
//   1. variável de ambiente (LUAU_ANALYZE / LUAU_CLI)
//   2. pasta de ferramentas do usuário (%LOCALAPPDATA%\luau\bin)
//   3. PATH do sistema
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

function noPath(nome) {
  try {
    const cmd = process.platform === "win32" ? "where" : "which";
    const saida = execSync(cmd + ' "' + nome + '"', { encoding: "utf8" });
    const linha = saida.split(/\r?\n/).find((l) => l && l.trim());
    if (linha && fs.existsSync(linha.trim())) return linha.trim();
  } catch (e) {
    // nao esta no PATH
  }
  return null;
}

function localizar(envVar, nome) {
  const cands = [];
  if (envVar && process.env[envVar]) cands.push(process.env[envVar]);
  if (process.env.LOCALAPPDATA) {
    cands.push(path.join(process.env.LOCALAPPDATA, "luau", "bin", nome));
    cands.push(path.join(process.env.LOCALAPPDATA, "luau", "bin", nome.replace(/\.exe$/i, "")));
  }
  cands.push(noPath(nome));
  cands.push(noPath(nome.replace(/\.exe$/i, "")));
  for (const c of cands) {
    if (c && fs.existsSync(c)) return c;
  }
  return null;
}

module.exports = {
  analisador: function () {
    return localizar("LUAU_ANALYZE", "luau-analyze.exe");
  },
  cli: function (analisador) {
    if (process.env.LUAU_CLI && fs.existsSync(process.env.LUAU_CLI)) return process.env.LUAU_CLI;
    if (analisador) {
      const irm = path.join(path.dirname(analisador), "luau.exe");
      if (fs.existsSync(irm)) return irm;
    }
    return localizar("LUAU_CLI", "luau.exe");
  },
};