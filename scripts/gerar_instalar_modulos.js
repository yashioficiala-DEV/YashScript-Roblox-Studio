// Gera um comando Luau que instala os módulos do YashScript no Studio.
// Uso:  node scripts/gerar_instalar_modulos.js > .tmp_instalar.lua
// Depois, cole/ execute o conteudo no Studio (ou via MCP execute_luau).
const fs = require("fs");
const path = require("path");

const raiz = path.join(__dirname, "..");
function ler(rel) {
  return fs.readFileSync(path.join(raiz, rel), "utf8").replace(/\r\n/g, "\n");
}

// string literal Lua com aspas longas [[...]] (nivel = quantidade de "=")
function luaLongString(s) {
  let nivel = 0;
  while (s.includes("]" + "=".repeat(nivel) + "]")) nivel++;
  const padrao = "=" + "=".repeat(nivel);
  return "[" + padrao + "[\n" + s + "\n]" + padrao + "]";
}

const comp = ler("compilador/compilador.lua");
const ger = ler("compilador/gerador.lua");

const codigo = `-- Instala/atualiza os modulos YashScript a partir dos fontes do repo.
local MODULOS = {
	Compilador = ${luaLongString(comp)},
	Gerador = ${luaLongString(ger)},
}

local pasta = game:GetService("ReplicatedStorage"):FindFirstChild("Yash")
if not pasta then
	pasta = Instance.new("Folder")
	pasta.Name = "Yash"
	pasta.Parent = game:GetService("ReplicatedStorage")
end

local relatorio = {}
for nome, fonte in pairs(MODULOS) do
	local mod = pasta:FindFirstChild(nome)
	if not mod or not mod:IsA("ModuleScript") then
		if mod then mod:Destroy() end
		mod = Instance.new("ModuleScript")
		mod.Name = nome
		mod.Parent = pasta
	end
	mod.Source = fonte
	relatorio[#relatorio + 1] = nome .. " (" .. #fonte .. " bytes)"
end

print("[YashScript] modulos instalados: " .. table.concat(relatorio, ", "))
return relatorio
`;

fs.writeFileSync(path.join(raiz, ".tmp_instalar.lua"), codigo, "utf8");
console.error("gerado .tmp_instalar.lua (" + codigo.length + " bytes)");
process.stdout.write(codigo);
