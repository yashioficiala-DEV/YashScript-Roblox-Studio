// Gera uma Release no GitHub com o instalador do YashScript.
//   Uso:  node scripts/gerar_release.js [versao]
//   versao opcional: ex. "v8.0" (usa tag "v8.0"). Se omitida, lê do header
//   de plugin/_modelo_plugin.lua ("YashScript V8.0" -> "v8.0").
//
// Fluxo:
//   1) (re)empacota o plugin a partir das fontes
//   2) (re)monta dist/YashScript-Instalador.zip (plugin.lua + instalar.cmd + LEIA-ME.txt)
//   3) cria a Release no repo remoto via gh CLI, anexando o zip
//
// Pré-requisitos: gh instalado e autenticado (gh auth login).
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const raiz = path.join(__dirname, "..");

function versaoDoHeader() {
  const modelo = fs.readFileSync(path.join(raiz, "plugin", "_modelo_plugin.lua"), "utf8");
  const m = modelo.match(/YashScript V([0-9]+\.[0-9]+)/);
  if (!m) throw new Error("nao achei 'YashScript Vx.y' no header de plugin/_modelo_plugin.lua");
  return "v" + m[1];
}

function roda(args) {
  return execFileSync(args[0], args.slice(1), { cwd: raiz, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

function montarZip(zipPath) {
  const area = path.join(path.dirname(zipPath), "_varios");
  const pasta = path.join(area, "YashScript");
  fs.mkdirSync(pasta, { recursive: true });
  fs.cpSync(path.join(raiz, "plugin", "plugin.lua"), path.join(pasta, "plugin.lua"));
  fs.cpSync(path.join(raiz, "instalador", "instalar.cmd"), path.join(pasta, "instalar.cmd"));
  fs.cpSync(path.join(raiz, "dist", "LEIA-ME.txt"), path.join(pasta, "LEIA-ME.txt"));
  try { roda(["powershell", "-NoProfile", "-Command", `Compress-Archive -Path '${pasta}' -DestinationPath '${zipPath}' -Force`]); }
  finally { fs.rmSync(area, { recursive: true, force: true }); }
}

try {
  let versao = process.argv[2];
  if (!versao) versao = versaoDoHeader();
  const tag = versao.startsWith("v") ? versao : "v" + versao;
  const zip = path.join(raiz, "dist", "YashScript-Instalador.zip");

  console.log("==> Versao: " + tag);

  console.log("==> (re)empacotando o plugin a partir das fontes...");
  roda([process.execPath, path.join(raiz, "scripts", "empacotar_plugin.js")]);

  console.log("==> (re)montando " + path.relative(raiz, zip) + "...");
  if (fs.existsSync(zip)) fs.rmSync(zip);
  montarZip(zip);
  console.log("    zip: " + fs.statSync(zip).size + " bytes");

  console.log("==> verificando gh...");
  roda(["gh", "--version"]);
  try { roda(["gh", "auth", "status"]); }
  catch (e) {
    console.error("ERRO: gh nao esta autenticado. Rode: gh auth login");
    process.exit(1);
  }

  console.log("==> criando release " + tag + "...");
  const notas = [
    "# YashScript " + tag,
    "",
    "Plugin de Roblox Studio — editor avançado + compilador Luau direto.",
    "",
    "## Instalar",
    "- Baixe o arquivo `YashScript-Instalador.zip` abaixo,",
    "- **feche o Roblox Studio**,",
    "- extraia e rode `instalar.cmd` (ou copie a pasta `YashScript` para `%LOCALAPPDATA%\\Roblox\\Plugins\\`),",
    "- abra o Roblox Studio e procure o YashScript na Toolbox (guia Plugins).",
    "",
    "Rode o `instalar.cmd` de novo para **atualizar** ou **desinstalar**.",
    "Veja o README do repositório para instruções completas.",
  ].join("\n");

  const saida = roda(["gh", "release", "create", tag, zip, "--title", "YashScript " + tag, "--notes", notas]);
  console.log(saida.trim());

  console.log("\nRelease criada!");
} catch (e) {
  const s = (e.stdout || "") + (e.stderr || "");
  console.error(s.trim() || e.message);
  process.exit(1);
}