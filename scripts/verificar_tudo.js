// Verificacao completa do projeto YashScript.
//   Uso:  node scripts/verificar_tudo.js
const { execFileSync } = require("child_process");
const path = require("path");

const raiz = path.join(__dirname, "..");

const ETAPAS = [
  ["lint (luau-analyze)", "scripts/analisar.js"],
  ["empacotar plugin", "scripts/empacotar_plugin.js"],
  ["instalar plugin", "scripts/instalar_plugin.js"],
  ["sintaxe dos fontes", "scripts/verificar_sintaxe.js|compilador/compilador.lua|compilador/gerador.lua"],
  ["sintaxe do plugin gerado", "scripts/verificar_sintaxe.js|plugin/plugin.lua"],
  ["propagacao ate o instalado", "scripts/verificar_propagacao.js"],
  ["testes do compilador", "testes/rodar.js"],
  ["execução e escopos no Luau", "testes/verificar_continue_luau.js"],
  ["testes modo jogo", "testes/rodar_modo_jogo.js"],
  ["exemplos do LOGS", "scripts/verificar_exemplos.js"],
];

let falhas = 0;
for (const [nome, spec] of ETAPAS) {
  const [script, ...args] = spec.split("|");
  process.stdout.write("\n=== " + nome + " ===\n");
  try {
    const saida = execFileSync(process.execPath, [path.join(raiz, script), ...args], {
      cwd: raiz,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    const linhas = saida.trim().split("\n");
    console.log(linhas.slice(-6).join("\n"));
  } catch (e) {
    const s = (e.stdout || "") + (e.stderr || "");
    console.log(s.trim().split("\n").slice(-12).join("\n"));
    console.log(">>> FALHOU: " + nome);
    falhas++;
  }
}

console.log("\n" + "=".repeat(50));
console.log(falhas === 0 ? "TUDO OK" : falhas + " etapa(s) falharam");
process.exit(falhas === 0 ? 0 : 1);
