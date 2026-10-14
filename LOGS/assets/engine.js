(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.YashWeb = factory();
})(typeof self !== "undefined" ? self : this, function () {
  var GRAUS = Math.PI / 180;
  var PREVENT = { arrowleft: 1, arrowright: 1, arrowup: 1, arrowdown: 1, " ": 1 };
  var BOTOES = { 0: "left", 1: "middle", 2: "right" };
  var Global = typeof globalThis !== "undefined" ? globalThis : (typeof self !== "undefined" ? self : null);
  var AudioNativo = Global && typeof Global.Audio === "function" ? Global.Audio : null;

  function aabb(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  }
  function limitar(v, min, max) { return v < min ? min : v > max ? max : v; }
  function aleatorio(a, b) { return a + Math.random() * (b - a); }
  function tem(o, k) { return o && o[k] != null; }
  function ehTela(o) { return o.espaco === "tela"; }

  function integrar(objs, gravity, dt) {
    for (var i = 0; i < objs.length; i++) {
      var o = objs[i];
      if (o.estatico || o._dead || ehTela(o)) continue;
      if (o.gravidade !== false) o.vy += gravity * dt;
      if (o.friccao) { var f = Math.pow(1 - limitar(o.friccao, 0, 1), dt * 60); o.vx *= f; o.vy *= f; }
      if (o.velMax) { o.vx = limitar(o.vx, -o.velMax, o.velMax); o.vy = limitar(o.vy, -o.velMax, o.velMax); }
      o.x += o.vx * dt;
      o.y += o.vy * dt;
      o.noChao = false;
      o._hit = false;
    }
  }

  function resolver(objs, world) {
    for (var i = 0; i < objs.length; i++) {
      var d = objs[i];
      if (d.estatico || d._dead || ehTela(d)) continue;
      for (var j = 0; j < objs.length; j++) {
        var s = objs[j];
        if (s === d || d._dead || s._dead) continue;
        if (!s.estatico || s.semColisao || ehTela(s)) continue;
        if (!aabb(d, s)) continue;
        var ox = Math.min(d.x + d.w, s.x + s.w) - Math.max(d.x, s.x);
        var oy = Math.min(d.y + d.h, s.y + s.h) - Math.max(d.y, s.y);
        var r = d.quicar ? (tem(d, "restituicao") ? d.restituicao : 1) : (tem(d, "restituicao") ? d.restituicao : 0);
        if (ox < oy) {
          if (d.x + d.w / 2 < s.x + s.w / 2) d.x -= ox; else d.x += ox;
          d.vx = -d.vx * r;
        } else {
          if (d.y + d.h / 2 < s.y + s.h / 2) { d.y -= oy; d.noChao = true; }
          else d.y += oy;
          d.vy = -d.vy * r;
        }
        d._hit = true;
      }
      if (world) {
        var rr = d.quicar ? (tem(d, "restituicao") ? d.restituicao : 1) : (tem(d, "restituicao") ? d.restituicao : 0);
        if (d.x < 0) { d.x = 0; d.vx = -d.vx * rr; }
        if (d.x + d.w > world.w) { d.x = world.w - d.w; d.vx = -d.vx * rr; }
        if (d.y < 0) { d.y = 0; d.vy = -d.vy * rr; }
        if (d.y + d.h > world.h) { d.y = world.h - d.h; d.vy = -d.vy * rr; d.noChao = true; }
      }
    }
  }

  function cor3d(hex, fator) {
    var h = (typeof hex === "string" && hex.charAt(0) === "#") ? hex.slice(1) : "7799ff";
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var r = parseInt(h.slice(0, 2), 16) || 120, g = parseInt(h.slice(2, 4), 16) || 150, b = parseInt(h.slice(4, 6), 16) || 255;
    function c(v) { return Math.max(0, Math.min(255, Math.round(v * fator))); }
    return "rgb(" + c(r) + "," + c(g) + "," + c(b) + ")";
  }

  // desenha um volume isométrico simples (sem WebGL): basta para o estúdio mostrar 3D
  function iso(ctx, o) {
    var d = Math.max(4, Number(o.profundidade) || 40);
    var ox = d * 0.5, oy = d * 0.5;
    var x = o.x, y = o.y, w = o.w, h = o.h;
    ctx.strokeStyle = "rgba(0,0,0,.35)"; ctx.lineWidth = 1;
    // face lateral direita
    ctx.fillStyle = cor3d(o.cor, 0.7);
    ctx.beginPath();
    ctx.moveTo(x + w, y); ctx.lineTo(x + w + ox, y - oy);
    ctx.lineTo(x + w + ox, y + h - oy); ctx.lineTo(x + w, y + h);
    ctx.closePath(); ctx.fill(); ctx.stroke();
    // face superior
    ctx.fillStyle = cor3d(o.cor, 1.18);
    ctx.beginPath();
    ctx.moveTo(x, y); ctx.lineTo(x + ox, y - oy);
    ctx.lineTo(x + w + ox, y - oy); ctx.lineTo(x + w, y);
    ctx.closePath(); ctx.fill(); ctx.stroke();
    // face frontal
    ctx.fillStyle = cor3d(o.cor, 0.9);
    ctx.fillRect(x, y, w, h); ctx.strokeRect(x, y, w, h);
  }

  function desenhar(ctx, o) {
    if (o._dead || o.visivel === false) return;
    var cx = o.x + o.w / 2, cy = o.y + o.h / 2;
    ctx.save();
    if (o.alpha != null) ctx.globalAlpha = o.alpha;
    if (o.rot) { ctx.translate(cx, cy); ctx.rotate(o.rot * GRAUS); ctx.translate(-cx, -cy); }
    ctx.fillStyle = o.cor || "#7aa2ff";
    if (o.tipo === "circulo") {
      ctx.beginPath();
      ctx.arc(cx, cy, Math.min(o.w, o.h) / 2, 0, Math.PI * 2);
      ctx.fill();
    } else if (o.tipo === "triangulo") {
      ctx.beginPath();
      ctx.moveTo(cx, o.y);
      ctx.lineTo(o.x + o.w, o.y + o.h);
      ctx.lineTo(o.x, o.y + o.h);
      ctx.closePath();
      ctx.fill();
    } else if (o.tipo === "poligono" && o.pontos && o.pontos.length >= 2) {
      ctx.beginPath();
      ctx.moveTo(o.x + o.pontos[0][0], o.y + o.pontos[0][1]);
      for (var k = 1; k < o.pontos.length; k++) ctx.lineTo(o.x + o.pontos[k][0], o.y + o.pontos[k][1]);
      ctx.closePath();
      ctx.fill();
    } else if (o.tipo === "linha") {
      ctx.strokeStyle = o.cor || "#7aa2ff";
      ctx.lineWidth = o.espessura || 2;
      ctx.beginPath();
      ctx.moveTo(o.x, o.y);
      ctx.lineTo(o.x + o.w, o.y + o.h);
      ctx.stroke();
    } else if (o.tipo === "texto") {
      ctx.font = (o.tamanho || 20) + "px system-ui, sans-serif";
      ctx.textBaseline = "top";
      ctx.fillText(o.texto != null ? String(o.texto) : "", o.x, o.y);
    } else if (o.tipo === "sprite") {
      if (o._img && o._img.complete !== false && o._img.naturalWidth !== 0) {
        try { ctx.drawImage(o._img, o.x, o.y, o.w, o.h); } catch (e) { ctx.fillRect(o.x, o.y, o.w, o.h); }
      } else {
        ctx.globalAlpha = (o.alpha == null ? 1 : o.alpha) * 0.3;
        ctx.fillRect(o.x, o.y, o.w, o.h);
      }
    } else if (o.tipo === "box3d" || o.tipo === "plano3d" || o.tipo === "cilindro3d" || o.tipo === "modelo3d") {
      iso(ctx, o);
    } else if (o.tipo === "esfera3d") {
      var d = Math.max(0, Number(o.profundidade) || 0);
      var g = ctx.createRadialGradient(cx - o.w * 0.2, cy - o.h * 0.25, Math.min(o.w, o.h) * 0.1, cx, cy, Math.max(o.w, o.h) / 2);
      g.addColorStop(0, cor3d(o.cor, 1.25));
      g.addColorStop(1, cor3d(o.cor, 0.6));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.ellipse(cx, cy, o.w / 2, o.h / 2, 0, 0, Math.PI * 2);
      ctx.fill();
      if (d > 0) {
        ctx.strokeStyle = "rgba(255,255,255,.25)";
        ctx.beginPath();
        ctx.ellipse(cx, cy, o.w / 2, (d / 2) * 0.5, 0, 0, Math.PI * 2);
        ctx.stroke();
      }
    } else {
      ctx.fillRect(o.x, o.y, o.w, o.h);
    }
    if (o.texto != null && o.tipo !== "texto") {
      ctx.globalAlpha = o.alphaTexto == null ? 1 : o.alphaTexto;
      ctx.fillStyle = o.corTexto || "#ffffff";
      ctx.font = (o.tamanho || 18) + "px system-ui, sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(o.texto), cx, cy);
    }
    ctx.restore();
  }

  function render(ctx, objs, fundo, camera) {
    var cv = ctx.canvas;
    if (ctx.setTransform) ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = fundo || "#0e1220";
    ctx.fillRect(0, 0, cv.width, cv.height);
    var cam = camera || { x: cv.width / 2, y: cv.height / 2, zoom: 1 };
    var mundo = [], tela = [];
    for (var i = 0; i < objs.length; i++) (ehTela(objs[i]) ? tela : mundo).push(objs[i]);
    if (mundo.length) {
      ctx.save();
      ctx.translate(cv.width / 2, cv.height / 2);
      if (cam.zoom && cam.zoom !== 1) ctx.scale(cam.zoom, cam.zoom);
      ctx.translate(-cam.x, -cam.y);
      ordenar(mundo).forEach(function (o) { desenhar(ctx, o); });
      ctx.restore();
    }
    ordenar(tela).forEach(function (o) { desenhar(ctx, o); });
  }

  function ordenar(lista) {
    var ordenado = false;
    for (var i = 0; i < lista.length; i++) if (lista[i].z) { ordenado = true; break; }
    if (!ordenado) return lista;
    return lista.slice().sort(function (a, b) { return (a.z || 0) - (b.z || 0); });
  }

  function Input() {
    this.down = new Set();
    this.apertou = new Set();
    this.soltou = new Set();
    this.mouse = { x: 0, y: 0, botao: { left: false, middle: false, right: false }, roda: 0 };
    this.toques = [];
    this._bound = false;
  }
  Input.prototype.atach = function () {
    if (this._bound || typeof window === "undefined") return;
    this._bound = true;
    var self = this;
    function baixa(k) { if (!self.down.has(k)) self.apertou.add(k); self.down.add(k); }
    function sobe(k) { if (self.down.has(k)) self.soltou.add(k); self.down.delete(k); }
    window.addEventListener("keydown", function (e) {
      var tg = e.target; if (tg && tg.tagName && (tg.tagName === "INPUT" || tg.tagName === "TEXTAREA" || tg.tagName === "SELECT")) return;
      var k = e.key ? e.key.toLowerCase() : "";
      if (k) baixa(k);
      if (k === " ") baixa("space");
      var c = e.code ? e.code.toLowerCase() : "";
      if (c) { baixa(c); if (c.indexOf("key") === 0) baixa(c.slice(3)); }
      if (PREVENT[k]) e.preventDefault();
    });
    window.addEventListener("keyup", function (e) {
      var tg = e.target; if (tg && tg.tagName && (tg.tagName === "INPUT" || tg.tagName === "TEXTAREA" || tg.tagName === "SELECT")) return;
      var k = e.key ? e.key.toLowerCase() : "";
      if (k) sobe(k);
      if (k === " ") sobe("space");
      var c = e.code ? e.code.toLowerCase() : "";
      if (c) { sobe(c); if (c.indexOf("key") === 0) sobe(c.slice(3)); }
    });
    window.addEventListener("mousemove", function (e) { self.mouse.x = e.clientX; self.mouse.y = e.clientY; });
    window.addEventListener("mousedown", function (e) { var b = BOTOES[e.button]; if (b) self.mouse.botao[b] = true; });
    window.addEventListener("mouseup", function (e) { var b = BOTOES[e.button]; if (b) self.mouse.botao[b] = false; });
    window.addEventListener("wheel", function (e) { self.mouse.roda += e.deltaY < 0 ? 1 : -1; }, { passive: true });
    window.addEventListener("touchstart", function (e) { self._toques(e, "start"); }, { passive: true });
    window.addEventListener("touchmove", function (e) { self._toques(e, "move"); }, { passive: true });
    window.addEventListener("touchend", function (e) { self._toques(e, "end"); }, { passive: true });
  };
  Input.prototype._toques = function (e, tipo) {
    this.toques = [];
    var lista = e.changedTouches || [];
    for (var i = 0; i < lista.length; i++) this.toques.push({ x: lista[i].clientX, y: lista[i].clientY, tipo: tipo });
  };
  Input.prototype.tecla = function (k) { return this.down.has(String(k).toLowerCase()); };
  Input.prototype.fimDoQuadro = function () { this.apertou.clear(); this.soltou.clear(); this.mouse.roda = 0; };

  function AudioSistema() { this._id = 0; this._ativos = {}; }
  AudioSistema.prototype.tocar = function (url, vol, loop) {
    if (!url) return null;
    var a = this._elemento(url);
    if (!a) return null;
    var self = this, id = ++this._id;
    a.volume = limitar(vol == null ? 1 : vol, 0, 1);
    a.loop = !!loop;
    this._ativos[id] = a;
    a.addEventListener("ended", function () { delete self._ativos[id]; });
    var p = a.play();
    if (p && p.catch) p.catch(function (e) { if (typeof console !== "undefined") console.warn("audio bloqueado ou arquivo invalid:", url, e && e.name); });
    return id;
  };
  AudioSistema.prototype._elemento = function (url) {
    try { return AudioNativo ? new AudioNativo(url) : null; } catch (e) { return null; }
  };
  AudioSistema.prototype.parar = function (id) { var a = this._ativos[id]; if (a) { try { a.pause(); } catch (e) {} delete this._ativos[id]; } };
  AudioSistema.prototype.pararTudo = function () { for (var k in this._ativos) this.parar(k); };

  function Engine(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.world = { w: canvas.width, h: canvas.height };
    this.objs = [];
    this.fundo = "#0e1220";
    this.gravity = 1400;
    this.camera = { x: canvas.width / 2, y: canvas.height / 2, zoom: 1, alvo: null, suave: 0 };
    this.input = new Input();
    this.audio = new AudioSistema();
    this.imagens = {};
    this.hooks = {};
    this.running = false;
    this.fps = 0;
    this.onTick = null;
    this._last = 0; this._acc = 0; this._frames = 0;
    this._loop = this.loop.bind(this);
    this.api = this.makeApi();
  }
  Engine.prototype.carregar = function (scene) {
    scene = scene || {};
    this.world = { w: scene.largura || this.canvas.width, h: scene.altura || this.canvas.height };
    this.canvas.width = this.world.w; this.canvas.height = this.world.h;
    this.fundo = scene.fundo || "#0e1220";
    this.gravity = scene.gravidade == null ? 1400 : scene.gravidade;
    this.objs = (scene.objetos || []).map(function (o) {
      return Object.assign({ estatico: false, vx: 0, vy: 0, rot: 0, z: 0, espaco: "mundo" }, o);
    });
    var cam = scene.camera;
    if (cam) {
      if (cam.x != null) this.camera.x = cam.x;
      if (cam.y != null) this.camera.y = cam.y;
      if (cam.zoom != null) this.camera.zoom = cam.zoom;
      if (cam.alvoId != null) this.camera.alvo = this.objs.filter(function (o) { return o.id === cam.alvoId; })[0] || null;
    } else {
      this.camera.x = this.world.w / 2; this.camera.y = this.world.h / 2;
    }
    return this;
  };
  Engine.prototype.mundo = function (w, h) { this.world.w = w; this.world.h = h; return this; };
  Engine.prototype.imagem = function (o, url) {
    if (!url || typeof Image === "undefined") { if (url) o.url = url; return null; }
    o.url = url; o.tipo = "sprite";
    if (this.imagens[url]) { if (this.imagens[url].complete) o._img = this.imagens[url]; else this.imagens[url].addEventListener("load", function () { o._img = this; }); return this.imagens[url]; }
    var img = new Image(); img.crossOrigin = "anonymous";
    img.addEventListener("load", function () { o._img = img; });
    img.addEventListener("error", function () { o._img = null; });
    img.src = url; this.imagens[url] = img; return img;
  };
  Engine.prototype.script = function (fn) { this.hooks = (fn ? fn(this.api, this, this.objs) : null) || {}; return this; };
  Engine.prototype.iniciar = function () {
    this.input.atach();
    if (this.hooks.iniciar) this.hooks.iniciar(this);
    this.running = true; this._last = 0;
    requestAnimationFrame(this._loop);
    return this;
  };
  Engine.prototype.parar = function () { this.running = false; return this; };
  Engine.prototype.loop = function (t) {
    if (!this.running) return;
    if (!this._last) this._last = t;
    var dt = (t - this._last) / 1000; this._last = t;
    if (dt > 1 / 30) dt = 1 / 30;
    this._acc += dt; this._frames++;
    if (this._acc >= 0.5) { this.fps = Math.round(this._frames / this._acc); this._acc = 0; this._frames = 0; }
    this.update(dt);
    if (this.onTick) this.onTick(this.fps, this);
    requestAnimationFrame(this._loop);
  };
  Engine.prototype.update = function (dt) {
    if (this.hooks.atualizar) this.hooks.atualizar(dt, this);
    integrar(this.objs, this.gravity, dt);
    var seen = {};
    for (var i = 0; i < this.objs.length; i++) {
      var a = this.objs[i];
      if (a.estatico || a._dead) continue;
      for (var j = 0; j < this.objs.length; j++) {
        var b = this.objs[j];
        if (b === a || b._dead || a._dead) continue;
        if (!aabb(a, b)) continue;
        var key = (i < j ? i + ":" + j : j + ":" + i);
        if (seen[key]) continue;
        seen[key] = 1;
        if (this.hooks.colisao) this.hooks.colisao(a, b, this);
      }
    }
    resolver(this.objs, this.world);
    if (this.camera.alvo && !this.camera.alvo._dead) {
      var al = this.camera.alvo;
      var tx = al.x + al.w / 2, ty = al.y + al.h / 2;
      var k = this.camera.suave > 0 ? Math.min(1, this.camera.suave * dt) : 1;
      this.camera.x += (tx - this.camera.x) * k;
      this.camera.y += (ty - this.camera.y) * k;
    }
    this.objs = this.objs.filter(function (o) { return !o._dead; });
    render(this.ctx, this.objs, this.fundo, this.camera);
    this.input.fimDoQuadro();
  };
  Engine.prototype.makeApi = function () {
    var self = this;
    return {
      engine: self,
      imprimir: function () { console.log.apply(console, arguments); },
      tecla: function (k) { return self.input.tecla(k); },
      teclaApertada: function (k) { return self.input.apertou.has(String(k).toLowerCase()); },
      mouse: function () { return { x: self.input.mouse.x, y: self.input.mouse.y }; },
      mouseBotao: function (b) { return !!self.input.mouse.botao[b || "left"]; },
      roda: function () { return self.input.mouse.roda; },
      achar: function (tag) { return self.objs.filter(function (o) { return o.tag === tag && !o._dead; }); },
      porId: function (id) { return self.objs.filter(function (o) { return o.id === id && !o._dead; })[0]; },
      criar: function (props) { var n = Object.assign({ estatico: false, vx: 0, vy: 0, rot: 0, z: 0, espaco: "mundo" }, props); self.objs.push(n); return n; },
      destruir: function (o) { if (o) o._dead = true; },
      mover: function (o, dx, dy) { o.x += dx; o.y += dy; },
      posicionar: function (o, x, y) { o.x = x; o.y = y; },
      tamanho: function (o, w, h) { o.w = w; if (h != null) o.h = h; },
      velocidade: function (o, vx, vy) { o.vx = vx; if (vy != null) o.vy = vy; },
      impulso: function (o, vx, vy) { o.vx += vx; o.vy += vy; },
      cor: function (o, c) { o.cor = c; },
      alpha: function (o, a) { o.alpha = a; },
      texto: function (o, s, tam) { o.tipo = "texto"; o.texto = s; if (tam != null) o.tamanho = tam; },
      rotulo: function (o, s, tam) { o.texto = s; if (tam != null) o.tamanho = tam; },
      corTexto: function (o, c, a) { o.corTexto = c; if (a != null) o.alphaTexto = a; },
      rot: function (o, g) { o.rot = g; },
      forma: function (o, tipo) { o.tipo = tipo; },
      pontos: function (o, pts) { o.pontos = pts; o.tipo = "poligono"; },
      espessura: function (o, e) { o.espessura = e; },
      imagem: function (o, url) { return self.imagem(o, url); },
      visivel: function (o, v) { o.visivel = v; },
      espaco: function (o, e) { o.espaco = e; },
      z: function (o, z) { o.z = z; },
      friccao: function (o, f) { o.friccao = f; },
      restituicao: function (o, r) { o.restituicao = r; },
      gravidade: function (o, on) { o.gravidade = on; },
      sobreposicao: function (a, b) { return aabb(a, b); },
      no_chao: function (o) { return !!o.noChao; },
      limitar: limitar,
      aleatorio: aleatorio,
      largura: function () { return self.world.w; },
      altura: function () { return self.world.h; },
      mundo: function (w, h) { self.mundo(w, h); },
      camera: function (x, y, z) { self.camera.x = x; self.camera.y = y; if (z != null) self.camera.zoom = z; },
      seguir: function (o, s) { self.camera.alvo = o; if (s != null) self.camera.suave = s; },
      zoom: function (z) { self.camera.zoom = z; },
      tocar: function (url, v, l) { return self.audio.tocar(url, v, l); },
      pararSom: function (id) { self.audio.parar(id); },
      esperar: function (seg, fn) { return setTimeout(fn, (seg || 0) * 1000); },
      objetos: function () { return self.objs; }
    };
  };

  return {
    Engine: Engine,
    Input: Input,
    aabb: aabb,
    integrate: integrar,
    integrar: integrar,
    resolver: resolver,
    render: render,
    desenhar: desenhar,
    limitar: limitar,
    aleatorio: aleatorio,
    version: "0.2.0"
  };
});
