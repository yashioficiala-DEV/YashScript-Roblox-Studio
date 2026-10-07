// Instala o artefato plugin/plugin.lua na pasta de plugins do Roblox Studio.
//   Uso:  node scripts/instalar_plugin.js
// Mantido separado do empacotamento para poder empacotar sem gravar no Studio.
const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

const raiz = path.join(__dirname, "..");
const artefato = path.join(raiz, "plugin", "plugin.lua");
const destinoDir = path.join(os.homedir(), "AppData", "Local", "Roblox", "Plugins", "YashScript");
const destino = path.join(destinoDir, "plugin.lua");

if (!fs.existsSync(artefato)) {
  console.error("ERRO: plugin/plugin.lua ausente. Rode antes: node scripts/empacotar_plugin.js");
  process.exit(1);
}

const conteudo = fs.readFileSync(artefato);
fs.mkdirSync(destinoDir, { recursive: true });
fs.writeFileSync(destino, conteudo);

// confere de verdade: relê e compara os bytes
const relido = fs.readFileSync(destino);
if (Buffer.compare(conteudo, relido) !== 0) {
  console.error("ERRO: o arquivo instalado nao confere com o artefato");
  process.exit(1);
}

console.log("plugin instalado em " + destinoDir);
console.log("  " + relido.length + " bytes, SHA256 " + crypto.createHash("sha256").update(relido).digest("hex").toUpperCase());
