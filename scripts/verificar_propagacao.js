// Confere se uma correcao do modelo chegou ate o plugin gerado e instalado.
//   Uso:  node scripts/verificar_propagacao.js
const fs = require("fs");

const ALVOS = [
  ["modelo", "plugin/_modelo_plugin.lua"],
  ["gerado", "plugin/plugin.lua"],
  ["instalado", "C:/Users/yashi/AppData/Local/Roblox/Plugins/YashScript/plugin.lua"],
];

// esperado = [modelo, gerado, instalado]; null = apenas informativo
// o modelo mantem placeholders @@; gerado e instalado nao podem ter nenhum.
const CHECKS = [
  ["widget.GuiObject (BUG)", /widget\.GuiObject/g, [0, 0, 0]],
  ['root.Name = "Raiz" (fix)', /root\.Name = "Raiz"/g, [1, 1, 1]],
  ["V6.5 (obsoleto)", /V6\.5/g, [0, 0, 0]],
  ["V7.0", /V7\.0/g, null],
  ["placeholders @@", /@@[A-Z_]+@@/g, [null, 0, 0]],
  ["EXEMPLO_ (morto)", /EXEMPLO_/g, [0, 0, 0]],
];

const textos = ALVOS.map(([, arq]) =>
  fs.existsSync(arq) ? fs.readFileSync(arq, "utf8") : null
);

const cab = "arquivo".padEnd(11) + CHECKS.map((c) => c[0].slice(0, 13).padEnd(15)).join("");
console.log(cab);

let falhas = 0;
textos.forEach((s, idx) => {
  if (s === null) {
    console.log(ALVOS[idx][0].padEnd(11) + "[ausente]");
    falhas++;
    return;
  }
  const celulas = CHECKS.map(([, re, esperado]) => {
    const n = (s.match(re) || []).length;
    if (esperado && esperado[idx] !== null && n !== esperado[idx]) falhas++;
    return String(n).padEnd(15);
  });
  console.log(ALVOS[idx][0].padEnd(11) + celulas.join(""));
});

if (textos[1] !== null && textos[2] !== null && textos[1] !== textos[2]) {
  console.error("O plugin instalado difere do artefato plugin/plugin.lua");
  falhas++;
} else if (textos[1] !== null && textos[2] !== null) {
  console.log("plugin gerado e instalado: idênticos");
}

console.log("");
console.log(falhas === 0 ? "propagacao ok" : falhas + " divergencia(s)");
process.exit(falhas === 0 ? 0 : 1);
