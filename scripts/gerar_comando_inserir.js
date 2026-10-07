// Gera um comando Luau de Edit que instala o pipeline direto V8 em ReplicatedStorage.
const fs = require("fs");
const path = require("path");
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
const partes = [
  `local ReplicatedStorage = game:GetService("ReplicatedStorage")`,
  `local Yash = ReplicatedStorage:FindFirstChild("Yash")`,
  `if Yash then Yash:Destroy() end`,
  `Yash = Instance.new("Folder")`,
  `Yash.Name = "Yash"`,
  `Yash.Parent = ReplicatedStorage`,
  `local function novoModulo(nome, codigo)`,
  `\tlocal m = Instance.new("ModuleScript")`,
  `\tm.Name = nome`,
  `\tm.Source = codigo`,
  `\tm.Parent = Yash`,
  `\treturn m`,
  `end`,
  `novoModulo("Compilador", ${luaStr(ler("compilador/compilador.lua"))})`,
  `novoModulo("Gerador", ${luaStr(ler("compilador/gerador.lua"))})`,
  `print("[YashScript] pipeline V8 instalado em ReplicatedStorage.Yash")`,
];
fs.writeFileSync(path.join(raiz, "testes", "inserir_estrutura.lua"), partes.join("\n") + "\n", "utf8");
console.log("testes/inserir_estrutura.lua gerado (" + partes.join("\n").length + " bytes)");
