const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;
const raiz = path.join(__dirname, "..");
function ler(rel) { return fs.readFileSync(path.join(raiz, rel), "utf8"); }

const compiladorFonte = ler("compilador/compilador.lua");
const mainFonte = ler("testes/exemplos/main.yash");
const visualFonte = ler("testes/exemplos/visual.yash");

const casos = [
  ["quando clicar bom", `
quando clicar 'btn'
    mostrar texto "Voce clicou"
    animacao = fade in + escala = +5
fim
`, {}],
  ["quando mouse_em", `
quando mouse_em 'btn'
    cor_borda = rgb(255,255,255)
    borda     = 2
fim
`, {}],
  ["quando mouse_sair", `
quando mouse_sair 'btn'
    cor_borda = rgb(80,80,80)
    borda     = 1
fim
`, {}],
  ["quando carregar", `
quando carregar
    mostrar texto "Pagina pronta"
fim
`, {}],
  ["4 eventos juntos", `
quando clicar 'btn'
    mostrar texto "Voce clicou"
    animacao = fade in + escala = +5
fim
quando mouse_em 'btn'
    cor_borda = rgb(255,255,255)
    borda     = 2
fim
quando mouse_sair 'btn'
    cor_borda = rgb(80,80,80)
    borda     = 1
fim
quando carregar
    mostrar texto "Pagina pronta"
fim
`, {}],
  ["painel/texto/botao", `
principal
criar painel 'Janela'
    largura = 400
    altura  = 300
    posicao = (100, 100)
    cena    = "Principal"
    estilo  = "botao-padrao"
fim
criar texto 'titulo'
    pai     = "Janela"
    texto   = "Ola Mundo"
    posicao = (20, 20)
    tamanho_fonte = 20
    estilo  = "textos"
fim
criar botao 'btn'
    pai     = "Janela"
    texto   = "Clique"
    estilo  = "botao-padrao"
    largura = 120
    altura  = 40
    posicao = (140, 200)
fim
`, {}],
  ["main.yash sem incluir", mainFonte.replace(/incluir "visual.yash"/, ""), {}],
  ["main com incluir",
    mainFonte.replace(/\n?principal\n\nincluir "visual.yash"\n/, ""), { ["visual.yash"]: visualFonte }],
];

const enc = (s) => JSON.stringify(s).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");

function montarEntrada() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_newtable(L);
  lua.lua_pushstring(L, to_luastring("compiladorFonte"));
  lua.lua_pushstring(L, to_luastring(compiladorFonte));
  lua.lua_settable(L, -3);
  lua.lua_setglobal(L, to_luastring("ENTRADA"));
  return L;
}

for (const caso of casos) {
  const [nome, fonte] = caso;
  const arquivos = caso[2] || {};
  const L = montarEntrada();
  let arqLua = "local arquivos = {}\n";
  for (const [k, v] of Object.entries(arquivos)) arqLua += `arquivos[${enc(k)}] = ${enc(v)}\n`;
  const script = `
  local ENTRADA = _G.ENTRADA
  local carregar = loadstring or load
  local c = assert(carregar(ENTRADA.compiladorFonte))()
  ${arqLua}
  local ok, res = c.Compilar(${enc(fonte)}, arquivos)
  print(ok and "OK" or ("ERRO: " .. tostring(res.erro) .. " (linha " .. tostring(res.linha) .. ")"))
  `;
  process.stdout.write("[" + nome + "] ");
  const st = lauxlib.luaL_loadstring(L, to_luastring(script));
  if (st !== lua.LUA_OK) { console.error("load err", nome); continue; }
  try {
    const r = lua.lua_pcall(L, 0, 0, 0);
    if (r !== lua.LUA_OK) {
      console.error("pcall err", nome, lua.lua_tolstring(L, -1, 0).toString());
    }
  } catch (e) {
    console.error("JS exception", nome, e.message);
  }
}