// Replica a matematica de aplicarLayout() para conferir geometria sem abrir o Studio.
const MARGEM = 6, GAP = 4, H_TOPO = 22, H_CABECALHO = 20, H_BOTAO = 22, H_ROTULO = 16;
const H_CONSOLE_MAX = 170, LARGURA_LISTA = 132;
const LINHAS = [["Gravar"], ["Selecionado", "Validar"], ["Ler", "Modulos"]];

function layout(H, consoleAberto, listaAberta) {
  const hConsole = consoleAberto ? H_CONSOLE_MAX : H_CABECALHO;
  const hBotoes = LINHAS.length * H_BOTAO + (LINHAS.length - 1) * GAP;
  const rodape = MARGEM + hConsole + GAP + hBotoes + GAP + H_ROTULO + GAP;
  const topoY = H_TOPO + 8;
  const centroH = -(topoY + rodape);

  const r = {};
  r.titulo = [4, 4 + H_TOPO];
  r.listaCabecalho = [topoY, topoY + H_CABECALHO];
  if (listaAberta) {
    const listaTop = topoY + H_CABECALHO + 2;
    r.lista = [listaTop, listaTop + (H + centroH - H_CABECALHO - 2)];
    r.editor = [topoY, topoY + (H + centroH)];
  } else {
    r.lista = null;
    r.editor = [topoY, topoY + (H + centroH)];
  }
  const rotuloTop = H - (MARGEM + hConsole + GAP + hBotoes + GAP + H_ROTULO);
  r.rotuloAlvo = [rotuloTop, rotuloTop + H_ROTULO];

  let y = MARGEM + hConsole + GAP + hBotoes;
  r.botoes = [];
  for (const linha of LINHAS) {
    const top = H - y;
    r.botoes.push([linha.join("/"), top, top + H_BOTAO]);
    y -= GAP + H_BOTAO;
  }
  const consoleTop = H - MARGEM - hConsole;
  r.console = [consoleTop, H - MARGEM];
  return r;
}

function checar(H, consoleAberto, listaAberta) {
  const r = layout(H, consoleAberto, listaAberta);
  console.log(`\n--- H=${H} console=${consoleAberto ? "aberto" : "fechado"} lista=${listaAberta ? "aberta" : "recolhida"} ---`);
  const linhas = Object.entries(r).filter(([, v]) => v && !Array.isArray(v[0]));
  for (const [nome, v] of Object.entries(r)) {
    if (nome === "botoes" || !v) continue;
    const [a, b] = v;
    console.log(`  ${nome.padEnd(14)} ${a.toFixed(0).padStart(4)} .. ${b.toFixed(0).padStart(4)}  (h=${(b - a).toFixed(0)})`);
  }
  for (const [nome, a, b] of r.botoes) {
    console.log(`  botao ${nome.padEnd(18)} ${a.toFixed(0).padStart(4)} .. ${b.toFixed(0).padStart(4)}`);
  }
  // checagens
  const erros = [];
  const all = [["titulo", ...r.titulo], ...Object.entries(r).filter(([k]) => k !== "botoes" && k !== "titulo" && r[k]).map(([k, v]) => [k, ...v]), ...r.botoes];
  for (const [nome, a, b] of all) {
    if (b - a <= 0) erros.push(`${nome}: altura<=0`);
    if (a < -0.01) erros.push(`${nome}: topo acima de 0`);
    if (b > H + 0.01) erros.push(`${nome}: base abaixo de H (${b.toFixed(0)}>${H})`);
  }
  if (r.console[0] < H_TOPO + 8) erros.push("console invade o topo");
  if (r.editor[1] > r.rotuloAlvo[0] + 0.01) erros.push("editor invade o rodape");
  console.log(erros.length ? "  ERROS: " + erros.join("; ") : "  ok: nada estoura nem sobrepoe");
}

for (const H of [420, 640, 900]) {
  for (const c of [false, true]) {
    for (const l of [true, false]) checar(H, c, l);
  }
}
