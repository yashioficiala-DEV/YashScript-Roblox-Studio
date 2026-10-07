// Gera um comando Luau que instala um modulo do pipeline V8 no Studio.
// Uso:  node scripts/gerar_instalar_um.js compilador|gerador
const fs = require("fs");
const path = require("path");

const raiz = path.join(__dirname, "..");
const qual = (process.argv[2] || "compilador").toLowerCase();

const ARQ = {
  compilador: "compilador/compilador.lua",
  gerador: "compilador/gerador.lua",
};
if (!ARQ[qual]) {
  console.error("modulo invalido: " + qual + " (use: compilador|gerador)");
  process.exit(2);
}

function ler(rel) {
  return fs.readFileSync(path.join(raiz, rel), "utf8").replace(/\r\n/g, "\n");
}
function luaLongString(s) {
  let nivel = 0;
  while (s.includes("]" + "=".repeat(nivel) + "]")) nivel++;
  const padrao = "=".repeat(nivel);
  return "[" + padrao + "[\n" + s + "\n]" + padrao + "]";
}

const fonte = ler(ARQ[qual]);
const nome = qual.charAt(0).toUpperCase() + qual.slice(1);

const codigo = `local rs = game:GetService("ReplicatedStorage")
local pasta = rs:FindFirstChild("Yash")
if not pasta then
	pasta = Instance.new("Folder")
	pasta.Name = "Yash"
	pasta.Parent = rs
end
local mod = pasta:FindFirstChild("${nome}")
if not mod or not mod:IsA("ModuleScript") then
	if mod then mod:Destroy() end
	mod = Instance.new("ModuleScript")
	mod.Name = "${nome}"
	mod.Parent = pasta
end
mod.Source = ${luaLongString(fonte)}
print("[YashScript] ${nome} instalado (" .. #mod.Source .. " bytes)")
return #mod.Source`;

fs.writeFileSync(path.join(raiz, ".tmp_instalar_" + qual + ".lua"), codigo, "utf8");
console.error("gerado .tmp_instalar_" + qual + ".lua (" + codigo.length + " bytes)");
process.stdout.write(codigo);
