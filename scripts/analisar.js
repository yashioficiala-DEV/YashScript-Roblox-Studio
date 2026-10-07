// Lint dos fontes do YashScript usando luau-analyze.
// Filtra o ruido que nao e problema real:
//   - "Unknown global/type": o analisador nao tem as definicoes do Roblox
//     (game, Enum, Color3, Vector3, Instance, task, warn, script, plugin...)
//   - SyntaxError do modelo do plugin: ele usa placeholders @@FONTE@@ que so
//     existem depois do empacotamento.
//
// Uso:  node scripts/analisar.js
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const LUAU = process.env.LUAU_ANALYZE
  || "C:\\Users\\yashi\\AppData\\Local\\luau\\bin\\luau-analyze.exe";

const RAIZ = path.join(__dirname, "..");

const ARQUIVOS = [
  path.join("compilador", "compilador.lua"),
  path.join("plugin", "_modelo_plugin.lua"),
];

const RUIDO = [
  "Unknown global " + "'",   // Unknown global 'Enum' etc (sem definicoes Roblox)
  "Unknown type " + "'",     // Unknown type 'Vector3' etc
  "Attribute name is missing",
  "Invalid attribute",
  "Expected " + "'function' declaration after attribute",
];

function ehRuido(msg) {
  for (const r of RUIDO) {
    if (msg.indexOf(r) >= 0) return true;
  }
  return false;
}

function analisar(rel) {
  const abs = path.join(RAIZ, rel);
  if (!fs.existsSync(abs)) return { arquivo: rel, erros: [], ausentes: true };
  let saida = "";
  try {
    saida = execFileSync(LUAU, [abs], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (e) {
    saida = (e.stdout || "") + (e.stderr || "");
  }
  const erros = [];
  const re = /^(.+?)\((\d+),(\d+)\):\s*(\w+):\s*(.+)$/gm;
  let m;
  while ((m = re.exec(saida)) !== null) {
    const msg = m[5].trim();
    if (ehRuido(msg)) continue;
    erros.push({ linha: Number(m[2]), col: Number(m[3]), nivel: m[4], msg });
  }
  return { arquivo: rel, erros };
}

let total = 0;
for (const rel of ARQUIVOS) {
  const r = analisar(rel);
  if (r.ausentes) {
    console.log("[ausente] " + rel);
    continue;
  }
  if (r.erros.length === 0) {
    console.log("[limpo]   " + rel);
  } else {
    console.log("[" + r.erros.length + "] " + rel);
    for (const e of r.erros) {
      console.log(
        "  " + String(e.linha).padStart(5) + ":" + String(e.col).padEnd(3)
        + " " + e.nivel + ": " + e.msg
      );
    }
  }
  total += r.erros.length;
}

console.log("");
console.log("=== " + total + " problema(s) real(is) ===");
process.exit(total === 0 ? 0 : 1);
