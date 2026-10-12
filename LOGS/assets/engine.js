(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.YashWeb = factory();
})(typeof self !== "undefined" ? self : this, function () {
  var PREVENT = { arrowleft: 1, arrowright: 1, arrowup: 1, arrowdown: 1, " ": 1 };

  function aabb(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  }
  function limitar(v, min, max) { return v < min ? min : v > max ? max : v; }
  function aleatorio(a, b) { return a + Math.random() * (b - a); }

  function integrate(objs, gravity, dt) {
    for (var i = 0; i < objs.length; i++) {
      var o = objs[i];
      if (o.estatico || o._dead) continue;
      if (o.gravidade !== false) o.vy += gravity * dt;
      o.x += o.vx * dt;
      o.y += o.vy * dt;
      o.noChao = false;
      o._hit = false;
    }
  }

  function resolver(objs, world) {
    for (var i = 0; i < objs.length; i++) {
      var d = objs[i];
      if (d.estatico || d._dead) continue;
      for (var j = 0; j < objs.length; j++) {
        var s = objs[j];
        if (s === d || d._dead || s._dead) continue;
        if (!s.estatico || s.semColisao) continue;
        if (!aabb(d, s)) continue;
        var ox = Math.min(d.x + d.w, s.x + s.w) - Math.max(d.x, s.x);
        var oy = Math.min(d.y + d.h, s.y + s.h) - Math.max(d.y, s.y);
        if (ox < oy) {
          if (d.x + d.w / 2 < s.x + s.w / 2) d.x -= ox; else d.x += ox;
          if (d.quicar) d.vx = -d.vx; else d.vx = 0;
        } else {
          if (d.y + d.h / 2 < s.y + s.h / 2) { d.y -= oy; d.noChao = true; }
          else d.y += oy;
          if (d.quicar) d.vy = -d.vy; else d.vy = 0;
        }
        d._hit = true;
      }
      if (world) {
        if (d.x < 0) { d.x = 0; if (d.quicar) d.vx = -d.vx; else d.vx = 0; }
        if (d.x + d.w > world.w) { d.x = world.w - d.w; if (d.quicar) d.vx = -d.vx; else d.vx = 0; }
        if (d.y < 0) { d.y = 0; if (d.quicar) d.vy = -d.vy; else d.vy = 0; }
        if (d.y + d.h > world.h) { d.y = world.h - d.h; if (d.quicar) d.vy = -d.vy; else d.vy = 0; d.noChao = true; }
      }
    }
  }

  function render(ctx, objs, fundo) {
    ctx.fillStyle = fundo || "#0e1220";
    ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
    for (var i = 0; i < objs.length; i++) {
      var o = objs[i];
      if (o._dead || o.visivel === false) continue;
      if (o.tipo === "circulo") {
        ctx.fillStyle = o.cor || "#ffffff";
        ctx.beginPath();
        ctx.arc(o.x + o.w / 2, o.y + o.h / 2, Math.min(o.w, o.h) / 2, 0, Math.PI * 2);
        ctx.fill();
      } else if (o.tipo === "texto") {
        ctx.fillStyle = o.cor || "#ffffff";
        ctx.font = (o.tamanho || 20) + "px system-ui, sans-serif";
        ctx.textBaseline = "top";
        ctx.fillText(o.texto || "", o.x, o.y);
      } else {
        ctx.fillStyle = o.cor || "#7aa2ff";
        ctx.fillRect(o.x, o.y, o.w, o.h);
      }
    }
  }

  function Input() { this.down = new Set(); this._bound = false; }
  Input.prototype.atach = function () {
    if (this._bound || typeof window === "undefined") return;
    this._bound = true;
    var self = this;
    window.addEventListener("keydown", function (e) {
      var k = e.key.toLowerCase();
      self.down.add(k);
      if (k === " ") self.down.add("space");
      var c = e.code ? e.code.toLowerCase() : "";
      if (c) { self.down.add(c); if (c.indexOf("key") === 0) self.down.add(c.slice(3)); }
      if (PREVENT[k]) e.preventDefault();
    });
    window.addEventListener("keyup", function (e) {
      var k = e.key.toLowerCase();
      self.down.delete(k);
      if (k === " ") self.down.delete("space");
      var c = e.code ? e.code.toLowerCase() : "";
      if (c) { self.down.delete(c); if (c.indexOf("key") === 0) self.down.delete(c.slice(3)); }
    });
  };
  Input.prototype.tecla = function (k) { return this.down.has(String(k).toLowerCase()); };

  function Engine(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.world = { w: canvas.width, h: canvas.height };
    this.objs = [];
    this.fundo = "#0e1220";
    this.gravity = 1400;
    this.input = new Input();
    this.hooks = {};
    this.running = false;
    this.fps = 0;
    this.onTick = null;
    this._last = 0;
    this._acc = 0;
    this._frames = 0;
    this._loop = this.loop.bind(this);
    this.api = this.makeApi();
  }
  Engine.prototype.carregar = function (scene) {
    this.world = { w: scene.largura || this.canvas.width, h: scene.altura || this.canvas.height };
    this.canvas.width = this.world.w;
    this.canvas.height = this.world.h;
    this.fundo = scene.fundo || "#0e1220";
    this.gravity = scene.gravidade == null ? 1400 : scene.gravidade;
    this.objs = (scene.objetos || []).map(function (o) {
      return Object.assign({ estatico: false, vx: 0, vy: 0 }, o);
    });
    return this;
  };
  Engine.prototype.script = function (fn) {
    var r = fn ? fn(this.api, this, this.objs) : null;
    this.hooks = r || {};
    return this;
  };
  Engine.prototype.iniciar = function () {
    this.input.atach();
    if (this.hooks.iniciar) this.hooks.iniciar(this);
    this.running = true;
    this._last = 0;
    requestAnimationFrame(this._loop);
    return this;
  };
  Engine.prototype.parar = function () { this.running = false; return this; };
  Engine.prototype.loop = function (t) {
    if (!this.running) return;
    if (!this._last) this._last = t;
    var dt = (t - this._last) / 1000;
    this._last = t;
    if (dt > 1 / 30) dt = 1 / 30;
    this._acc += dt;
    this._frames++;
    if (this._acc >= 0.5) { this.fps = Math.round(this._frames / this._acc); this._acc = 0; this._frames = 0; }
    this.update(dt);
    if (this.onTick) this.onTick(this.fps, this);
    requestAnimationFrame(this._loop);
  };
  Engine.prototype.update = function (dt) {
    if (this.hooks.atualizar) this.hooks.atualizar(dt, this);
    integrate(this.objs, this.gravity, dt);
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
    this.objs = this.objs.filter(function (o) { return !o._dead; });
    render(this.ctx, this.objs, this.fundo);
  };
  Engine.prototype.makeApi = function () {
    var self = this;
    return {
      engine: self,
      imprimir: function () { console.log.apply(console, arguments); },
      tecla: function (k) { return self.input.tecla(k); },
      achar: function (tag) { return self.objs.filter(function (o) { return o.tag === tag && !o._dead; }); },
      porId: function (id) { return self.objs.filter(function (o) { return o.id === id && !o._dead; })[0]; },
      mover: function (o, dx, dy) { o.x += dx; o.y += dy; },
      velocidade: function (o, vx, vy) { o.vx = vx; if (vy != null) o.vy = vy; },
      impulso: function (o, vx, vy) { o.vx += vx; o.vy += vy; },
      cor: function (o, c) { o.cor = c; },
      texto: function (o, s) { o.texto = s; },
      criar: function (props) { var n = Object.assign({ estatico: false, vx: 0, vy: 0 }, props); self.objs.push(n); return n; },
      destruir: function (o) { if (o) o._dead = true; },
      sobreposicao: function (a, b) { return aabb(a, b); },
      no_chao: function (o) { return !!o.noChao; },
      limitar: limitar,
      aleatorio: aleatorio,
      largura: function () { return self.world.w; },
      altura: function () { return self.world.h; },
      esperar: function (seg, fn) { return setTimeout(fn, (seg || 0) * 1000); },
      objetos: function () { return self.objs; }
    };
  };

  return {
    Engine: Engine,
    Input: Input,
    aabb: aabb,
    integrate: integrate,
    resolver: resolver,
    render: render,
    limitar: limitar,
    aleatorio: aleatorio,
    version: "0.1.0"
  };
});
