// Patch pontual de arquivos de texto, com verificacao.
// Uso: node scripts/patch.js <arquivo> <arquivo-json-de-substituicoes>
// Cada substituicao: { "de": <texto exato>, "para": <texto> } (ou array para replaceAll)
const fs = require("fs");
const path = require("path");

const [, , alvo, jsonPath] = process.argv;
if (!alvo || !jsonPath) {
  console.error("uso: node scripts/patch.js <arquivo> <json>");
  process.exit(2);
}

const abs = path.resolve(alvo);
let src = fs.readFileSync(abs, "utf8");
const subs = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

let aplicadas = 0;
let falhas = 0;

for (const [i, s] of subs.entries()) {
  const de = s.de;
  const para = s.para;
  if (typeof de !== "string" || de === "") {
    console.error("[" + i + "] 'de' invalido");
    falhas++;
    continue;
  }
  if (s.todas) {
    const partes = src.split(de);
    const n = partes.length - 1;
    if (n === 0) {
      console.error("[" + i + "] nao encontrado (todas): " + JSON.stringify(de.slice(0, 60)));
      falhas++;
      continue;
    }
    src = partes.join(para);
    console.log("[" + i + "] ok (" + n + "x) " + JSON.stringify(de.slice(0, 60)));
    aplicadas += n;
  } else {
    if (src.indexOf(de) < 0) {
      console.error("[" + i + "] nao encontrado: " + JSON.stringify(de.slice(0, 60)));
      falhas++;
      continue;
    }
    if (src.indexOf(de) !== src.lastIndexOf(de)) {
      console.error("[" + i + "] AMBIGUO (aparece mais de uma vez): " + JSON.stringify(de.slice(0, 60)));
      falhas++;
      continue;
    }
    src = src.replace(de, para);
    console.log("[" + i + "] ok " + JSON.stringify(de.slice(0, 60)));
    aplicadas++;
  }
}

if (falhas > 0) {
  console.error("\n" + falhas + " substituicao(oes) falharam - nada gravado.");
  process.exit(1);
}

fs.writeFileSync(abs, src, "utf8");
console.log("\ngravado: " + abs + " (" + aplicadas + " substituicao(oes))");
