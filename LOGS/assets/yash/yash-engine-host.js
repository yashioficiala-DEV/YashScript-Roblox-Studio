(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.YashEngineHost = factory();
})(typeof self !== "undefined" ? self : this, function () {

  var FORMAS = {
    ret: "retangulo", rect: "retangulo", retangulo: "retangulo", bloco: "retangulo", plataforma: "retangulo", parede: "retangulo", quadrado: "retangulo",
    circ: "circulo", circulo: "circulo", esfera: "circulo", bola: "circulo",
    tri: "triangulo", triangulo: "triangulo",
    poli: "poligono", poligono: "poligono",
    linha: "linha",
    texto: "texto",
    sprite: "sprite",
    hud: "texto",
    objeto: "logico", logico: "logico"
  };
  var SEM_RENDER = { logico: 1 };

  function num(v) { return typeof v === "number" ? v : (v == null ? 0 : Number(v) || 0); }
  function verdade(v) { return v != null && v !== false; }
  function ehVetor(v) { return !!v && v.__y === "vetor"; }
  function ehCor(v) { return !!v && v.__y === "cor"; }
  function ehHandle(v) { return !!v && v.__y === "handle"; }

  function corStr(v) {
    if (ehCor(v)) return "rgb(" + Math.round(num(v.r)) + ", " + Math.round(num(v.g)) + ", " + Math.round(num(v.b)) + ")";
    if (typeof v === "string") return v;
    return "#7aa2ff";
  }
  function texto(v) {
    if (v == null) return "nulo";
    if (v === true) return "verdadeiro";
    if (v === false) return "falso";
    if (typeof v === "number") return String(v);
    if (typeof v === "string") return v;
    if (ehVetor(v)) return "(" + v.x + ", " + v.y + ", " + v.z + ")";
    if (ehCor(v)) return "rgb(" + Math.round(v.r) + ", " + Math.round(v.g) + ", " + Math.round(v.b) + ")";
    if (ehHandle(v)) return "<" + v.forma + " '" + v.nome + "'>";
    if (Array.isArray(v)) return "[" + v.map(texto).join(", ") + "]";
    return String(v);
  }
  function aabbLocal(a, b) {
    if (!a || !b) return false;
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  }

  function Host(engine, opts) {
    opts = opts || {};
    this.engine = engine;
    this.registrar = opts.registrar || function () { if (typeof console !== "undefined") console.log.apply(console, arguments); };
    this.aabb = opts.aabb || aabbLocal;
    this._id = 0;
    this.porNome = {};
    this.porObj = [];
    this.naoSuportados = [];
    this.avisos = [];
  }
  Host.prototype._aviso = function (m) { this.avisos.push(m); this.registrar("[aviso] " + m); };
  Host.prototype._entidade = function (h) {
    if (!h || !h.obj) return null;
    if (h.obj._dead) { return null; }
    return h.obj;
  };

  Host.prototype.imprimir = function () {
    this.registrar(Array.prototype.slice.call(arguments).map(texto).join(" "));
  };

  Host.prototype.criar = function (forma, nome) {
    var tipo = FORMAS[forma] || "retangulo";
    var id = ++this._id;
    var o = {
      id: id, tipo: tipo, nome: nome, forma: forma,
      x: 0, y: 0, w: 32, h: 32, cor: "#7aa2ff",
      vx: 0, vy: 0, rot: 0, z: 0, estatico: false, espaco: "mundo"
    };
    if (forma === "hud") { o.espaco = "tela"; o.tipo = "texto"; o.w = 160; o.h = 24; }
    if (SEM_RENDER[tipo]) { o.visivel = false; o.estatico = true; o.semColisao = true; o.w = 0; o.h = 0; }
    var handle = { __y: "handle", id: id, forma: forma, tipo: tipo, nome: nome, props: {}, obj: o };
    if (this.porNome[nome]) this._aviso("nome de entidade duplicado: '" + nome + "' (o anterior deixa de ser acessível por nome)");
    this.porNome[nome] = handle;
    this.porObj.push(handle);
    this.engine.objs.push(o);
    return handle;
  };

  Host.prototype.definir = function (h, chave, val) {
    var o = this._entidade(h);
    if (!o) { if (h) this._aviso("escrita em entidade inexistente/destruída: '" + (h.nome || "?") + "." + chave + "'"); return; }
    switch (chave) {
      case "posicao": case "position": if (ehVetor(val)) { o.x = num(val.x); o.y = num(val.y); } break;
      case "x": o.x = num(val); break;
      case "y": o.y = num(val); break;
      case "tamanho": case "size":
        if (ehVetor(val)) { o.w = num(val.x); o.h = num(val.y); } else { o.w = num(val); o.h = num(val); }
        break;
      case "largura": case "w": o.w = num(val); break;
      case "altura": case "h": o.h = num(val); break;
      case "cor": case "color": o.cor = corStr(val); break;
      case "alpha": o.alpha = num(val); break;
      case "rot": case "rotacao": o.rot = num(val); break;
      case "forma": case "tipo": o.tipo = FORMAS[val] || val; break;
      case "texto": o.tipo = "texto"; o.texto = String(val); break;
      case "tamanho_texto": case "textsize": o.tamanho = num(val); break;
      case "cor_texto": o.corTexto = corStr(val); break;
      case "z": o.z = num(val); break;
      case "visivel": o.visivel = verdade(val); break;
      case "estatico": o.estatico = verdade(val); break;
      case "gravidade": o.gravidade = verdade(val); break;
      case "friccao": o.friccao = num(val); break;
      case "restituicao": o.restituicao = num(val); o.quicar = num(val) > 0; break;
      case "velocidade": case "velocity":
        if (ehVetor(val)) { o.vx = num(val.x); o.vy = num(val.y); } else { o.vx = num(val); }
        break;
      case "pontos": o.pontos = val; o.tipo = "poligono"; break;
      case "espessura": o.espessura = num(val); break;
      case "espaco": o.espaco = val; break;
      case "nome": this._renomear(h, String(val)); break;
      case "tag": o.tag = val; break;
      case "sem_colisao": o.semColisao = verdade(val); break;
      case "imagem": case "url": o.tipo = "sprite"; if (this.engine.imagem) this.engine.imagem(o, String(val)); break;
      case "material": break;
      default: h.props[chave] = val;
    }
  };

  Host.prototype._renomear = function (h, novo) {
    if (this.porNome[h.nome] === h) delete this.porNome[h.nome];
    if (this.porNome[novo] && this.porNome[novo] !== h) this._aviso("nome de entidade duplicado: '" + novo + "'");
    h.nome = novo; h.obj.nome = novo; this.porNome[novo] = h;
  };

  Host.prototype.obter = function (h, prop) {
    if (!h) return null;
    var o = this._entidade(h);
    if (!o) return null;
    switch (prop) {
      case "posicao": case "position": return { __y: "vetor", x: o.x, y: o.y, z: 0 };
      case "x": return o.x;
      case "y": return o.y;
      case "tamanho": case "size": return { __y: "vetor", x: o.w, y: o.h, z: 0 };
      case "largura": case "w": return o.w;
      case "altura": case "h": return o.h;
      case "cor": case "color": return o.cor;
      case "velocidade": case "velocity": return { __y: "vetor", x: o.vx, y: o.vy, z: 0 };
      case "no_chao": return !!o.noChao;
      case "forma": return o.forma;
      case "tipo": return o.tipo;
      case "nome": return o.nome;
    }
    if (prop in h.props) return h.props[prop];
    if (prop in o) return o[prop];
    return null;
  };

  Host.prototype.metodo = function (h, nome, args) {
    var o = this._entidade(h);
    if (!o) { if (h) this._aviso("método '" + nome + "' em entidade inexistente/destruída: '" + (h.nome || "?") + "'"); return null; }
    switch (nome) {
      case "mover": o.x += num(args[0]); o.y += num(args[1]); return null;
      case "posicionar": o.x = num(args[0]); o.y = num(args[1]); return null;
      case "impulso": o.vx += num(args[0]); o.vy += num(args[1]); return null;
      case "destruir": o._dead = true; return null;
      case "sobrepor": case "sobreposicao": return this.aabb(o, args[0] && args[0].obj);
      case "no_chao": return !!o.noChao;
      case "tocar": return this.engine.audio ? this.engine.audio.tocar(String(args[0]), num(args[1]) || 1, verdade(args[2])) : null;
      case "parar": if (this.engine.audio) this.engine.audio.parar(num(args[0])); return null;
    }
    this._aviso("método não suportado: '" + nome + "'");
    return null;
  };

  Host.prototype.comando = function (verbo, args, info) {
    var vals = [];
    for (var i = 0; i < args.length; i++) if (!(args[i] && args[i].sep)) vals.push(args[i]);
    var linhaTxt = (info && info.linha) ? " (linha " + info.linha + ")" : "";
    switch (verbo) {
      case "mostrar":
        this.registrar(vals.filter(function (v) { return !(v && (v.tipo === "nativo" || v.tipo === "funcao")); }).map(texto).join(" "));
        return;
      case "mover": {
        var alvoM = ehHandle(vals[0]) ? vals[0] : this.porNome[vals[0]];
        var oM = alvoM && this._entidade(alvoM);
        if (!oM || !ehVetor(vals[1])) { this._aviso("comando 'mover' com alvo ou destino inválido" + linhaTxt); return; }
        if (typeof vals[2] === "number") {
          var dxm = vals[1].x - oM.x, dym = vals[1].y - oM.y, mm = Math.sqrt(dxm * dxm + dym * dym) || 1;
          oM.vx = dxm / mm * vals[2]; oM.vy = dym / mm * vals[2];
        } else { oM.x = vals[1].x; oM.y = vals[1].y; }
        return;
      }
      case "posicionar": {
        var alvoP = ehHandle(vals[0]) ? vals[0] : this.porNome[vals[0]];
        var oP = alvoP && this._entidade(alvoP);
        if (!oP || !ehVetor(vals[1])) { this._aviso("comando 'posicionar' com alvo ou destino inválido" + linhaTxt); return; }
        oP.x = vals[1].x; oP.y = vals[1].y; return;
      }
      case "tocar": if (this.engine.audio) this.engine.audio.tocar(String(vals[0]), vals[1] == null ? 1 : num(vals[1]), verdade(vals[2])); return;
      case "mundo": this.engine.mundo(num(vals[0]), num(vals[1])); return;
      case "gravidade": this.engine.gravity = num(vals[0]); return;
      case "fundo": this.engine.fundo = corStr(vals[0]); return;
      case "camera": this.engine.camera.x = num(vals[0]); this.engine.camera.y = num(vals[1]); if (vals[2] != null) this.engine.camera.zoom = num(vals[2]); return;
      case "zoom": this.engine.camera.zoom = num(vals[0]); return;
      case "seguir": this.engine.camera.alvo = (ehHandle(vals[0]) ? vals[0].obj : (this.porNome[vals[0]] ? this.porNome[vals[0]].obj : null)); if (vals[1] != null) this.engine.camera.suave = num(vals[1]); return;
    }
    this.naoSuportados.push({ verbo: verbo, linha: info && info.linha });
    this.registrar("[comando não suportado: " + verbo + "]" + linhaTxt);
  };

  Host.prototype.incluir = function (caminho) {
    this._aviso("'incluir " + caminho + "' não é suportado no navegador nesta versão; o arquivo não foi carregado e o programa continua sem ele");
    return null;
  };

  return Host;
});
