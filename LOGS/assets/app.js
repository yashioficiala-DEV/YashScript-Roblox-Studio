/* ==========================================================================
   YashScript — app do site
   Sem dependências externas. Funciona em file:// e no Vercel.
   ========================================================================== */
(function () {
  "use strict";

  var Y = window.YASH;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function stripTags(s) { return String(s || "").replace(/<[^>]*>/g, ""); }
  function noAcc(s) { return String(s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, ""); }
  function slug(words) {
    var raw = Array.isArray(words) ? words.join("-") : String(words || "");
    var t = raw.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    if (t) return t;
    var h = 0; for (var i = 0; i < raw.length; i++) h = (h * 31 + raw.charCodeAt(i)) >>> 0;
    return "s" + h.toString(36);
  }

  /* ------------------------------------------------------------ highlight */
  var KEYWORDS = toSet(("YASHSCRIPT se senao enquanto repita ate para cada passo em pare continuar fim e ou nao entao usar criar quando retornar devolver variavel var let incluir funcao com como sim verdadeiro falso nulo " +
    "local function end then do return if else elseif for in while until break goto").split(" "));
  var COMMANDS = toSet(("causar dano curar matar respawnar teleportar mover rotacionar seguir tocar som encostar explodir destruir remover sortear somar subtrair clonar proibir esperar aguardar mostrar esconder alternar mudar animar executar chamar print viajar parar interromper rodar reproduzir apertar soltar tecla".split(" ")));
  var BOOLS = toSet(["verdadeiro", "falso", "sim", "nao", "nulo", "true", "false", "nil", "and", "or", "not", "e", "ou"]);
  var PROPS = toSet(Y.tables.propriedades.map(function (p) { return p[0]; }));
  var SERVICES = toSet([].concat(
    Y.tables.servicos.map(function (s) { return s[0]; }),
    Y.tables.servicos.map(function (s) { return s[1]; }),
    ["workspace", "Workspace", "game", "script", "PlayerGui", "StarterGui"]
  ));

  function toSet(arr) { var s = {}; arr.forEach(function (x) { s[String(x).toLowerCase()] = 1; }); return s; }

  function classify(word) {
    var l = word.toLowerCase();
    if (BOOLS[l]) return "tok-bool";
    if (KEYWORDS[l]) return "tok-key";
    if (COMMANDS[l]) return "tok-cmd";
    if (PROPS[l]) return "tok-prop";
    if (SERVICES[l]) return "tok-svc";
    if (/^[A-Z]/.test(word) && Y.tables.globais.indexOf(word) >= 0) return "tok-svc";
    return "";
  }

  function span(cls, text) {
    return cls ? '<span class="' + cls + '">' + esc(text) + "</span>" : esc(text);
  }

  var WORD_RE = /[\p{L}_][\p{L}\p{N}_]*/u;
  var NUM_RE = /^(?:0[xX][0-9a-fA-F]+|\d*\.?\d+(?:[eE][+-]?\d+)?)/;

  function highlight(src) {
    src = String(src || "");
    var out = "", i = 0, n = src.length;
    while (i < n) {
      var c = src[i];
      if (c === "#") {
        var j = src.indexOf("\n", i); if (j < 0) j = n;
        out += span("tok-com", src.slice(i, j)); i = j; continue;
      }
      if (c === '"' || c === "'") { var sres = readString(src, i); out += sres.html; i = sres.end; continue; }
      if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(src[i + 1] || ""))) {
        var m = NUM_RE.exec(src.slice(i)); var tok = m ? m[0] : c;
        out += span("tok-num", tok); i += tok.length; continue;
      }
      if (/[\p{L}_]/u.test(c)) {
        var wm = WORD_RE.exec(src.slice(i)); var w = wm[0];
        out += span(classify(w), w); i += w.length; continue;
      }
      out += span("tok-punct", c); i++;
    }
    return out;
  }

  function readString(src, start) {
    var q = src[start], j = start + 1, inner = "", html = '<span class="tok-str">' + esc(q);
    while (j < src.length) {
      var c = src[j];
      if (c === "\\" && j + 1 < src.length) { inner += c + src[j + 1]; j += 2; continue; }
      if (c === q) break;
      if (q === '"' && c === "{" && src[j + 1] === "{") { inner += "{{"; j += 2; continue; }
      if (q === '"' && c === "}" && src[j + 1] === "}") { inner += "}}"; j += 2; continue; }
      if (q === '"' && c === "{") {
        html += esc(inner); inner = "";
        var depth = 1, k = j + 1, expr = "";
        while (k < src.length && depth > 0) {
          var d = src[k];
          if (d === "{") { depth++; expr += d; k++; continue; }
          if (d === "}") { depth--; if (depth === 0) break; expr += d; k++; continue; }
          expr += d; k++;
        }
        html += '<span class="tok-key">{</span>' + highlight(expr) + '<span class="tok-key">}</span>';
        j = k + 1; continue;
      }
      inner += c; j++;
    }
    html += esc(inner) + esc(q) + "</span>";
    return { end: j + 1, html: html };
  }

  function codeBlock(code, label) {
    return '<pre><button class="copybtn" type="button" data-copy>Copiar</button><code>' +
      highlight(code) + "</code></pre>";
  }

  /* ------------------------------------------------------------ theme */
  function initTheme() {
    var saved = null; try { saved = localStorage.getItem("ys-theme"); } catch (e) {}
    if (saved) document.documentElement.setAttribute("data-theme", saved);
    var btns = $$("[data-theme-toggle]");
    btns.forEach(function (b) {
      b.addEventListener("click", function () {
        var cur = document.documentElement.getAttribute("data-theme") === "light" ? "dark" : "light";
        document.documentElement.setAttribute("data-theme", cur);
        try { localStorage.setItem("ys-theme", cur); } catch (e) {}
      });
    });
  }

  /* ------------------------------------------------------------ guia */
  function renderGuia() {
    var host = $("#guia-host"); if (!host) return;
    host.innerHTML = Y.guia.map(function (g) {
      return '<section class="doc" id="guia-' + g.id + '" style="margin-bottom:40px">' +
        "<h2>" + esc(g.titulo) + "</h2>" +
        '<p class="muted">' + esc(g.resumo) + "</p>" + g.html + "</section>";
    }).join("");
    attachCopy(host);
  }

  /* ------------------------------------------------------------ referência */
  var refActiveCat = "Todas", refQuery = "";
  function renderReferencia() {
    var host = $("#ref-host"); if (!host) return;
    var cats = presentCats();
    var chips = ['<button class="chip active" data-cat="Todas" type="button">Todas</button>']
      .concat(cats.map(function (c) {
        var n = Y.entries.filter(function (e) { return e.c === c; }).length;
        return '<button class="chip" data-cat="' + esc(c) + '" type="button">' + esc(c) + " (" + n + ")</button>";
      })).join("");

    host.innerHTML =
      '<div class="ref-toolbar"><div class="dict-search" style="max-width:420px;flex:1">' +
      '<span aria-hidden="true">⌕</span><input id="ref-filter" type="search" placeholder="Filtrar palavras, comandos e propriedades…" autocomplete="off"></div></div>' +
      '<div class="ref-cats" id="ref-chips">' + chips + "</div>" +
      '<div class="result-count" id="ref-count"></div>' +
      '<div class="ref-list" id="ref-list"></div>';

    $("#ref-chips").addEventListener("click", function (ev) {
      var b = ev.target.closest("[data-cat]"); if (!b) return;
      refActiveCat = b.getAttribute("data-cat");
      $$("#ref-chips .chip").forEach(function (x) { x.classList.toggle("active", x === b); });
      paintRef();
    });
    $("#ref-filter").addEventListener("input", function (ev) { refQuery = ev.target.value; paintRef(); });
    paintRef();
  }

  function presentCats() {
    var seen = {}, out = [];
    Y.ordemCategorias.forEach(function (c) { seen[c] = 1; });
    Y.entries.forEach(function (e) { if (!seen[e.c]) { seen[e.c] = 1; out.push(e.c); } });
    // categorias conhecidas primeiro, na ordem definida
    var order = Y.ordemCategorias.concat(out);
    return order.filter(function (c, i) { return order.indexOf(c) === i && Y.entries.some(function (e) { return e.c === c; }); });
  }

  function paintRef() {
    var host = $("#ref-list"); if (!host) return;
    var q = noAcc(refQuery);
    var list = Y.entries.filter(function (e) {
      if (refActiveCat !== "Todas" && e.c !== refActiveCat) return false;
      if (!q) return true;
      var hay = noAcc(e.w.join(" ") + " " + e.c + " " + stripTags(e.d) + " " + e.s + " " + (e.note || ""));
      return hay.indexOf(q) >= 0;
    });
    $("#ref-count").textContent = list.length + (list.length === 1 ? " verbete" : " verbetes");
    if (!list.length) { host.innerHTML = '<p class="empty">Nenhum verbete encontrado.</p>'; return; }
    host.innerHTML = list.map(function (e) {
      var id = "ref-" + slug(e.w);
      var kws = e.w.map(function (w) { return "<b>" + esc(w) + "</b>"; }).join('<span class="tok-punct"> · </span>');
      return '<article class="ref-item" id="' + id + '" data-cat="' + esc(e.c) + '">' +
        '<div class="top"><span class="cat">' + esc(e.c) + "</span></div>" +
        '<h3 class="kw">' + kws + "</h3>" +
        '<p class="desc">' + e.d + "</p>" +
        '<div class="usar">Como usar</div>' + codeBlock(e.s) +
        '<div class="usar">Exemplo</div>' + codeBlock(e.e) +
        (e.note ? '<div class="note">' + e.note + "</div>" : "") +
        "</article>";
    }).join("");
    attachCopy(host);
  }

  /* ------------------------------------------------------------ tabelas */
  var TABLE_DEFS = [
    { key: "servicos", title: "Serviços Roblox", desc: "Nome em português/inglês e o serviço canônico emitido por game:GetService().", cols: ["No YashScript", "Serviço Roblox"] },
    { key: "propriedades", title: "Propriedades", desc: "Propriedade escrita em português → propriedade real do Roblox.", cols: ["YashScript", "Roblox"] },
    { key: "materiais", title: "Materiais", desc: "Nome do material → Enum.Material.", cols: ["Nome", "Enum.Material"] },
    { key: "fontes", title: "Fontes", desc: "Nome da fonte → Enum.Font.", cols: ["Nome", "Enum.Font"] },
    { key: "teclas", title: "Teclas", desc: "Nome amigável da tecla → Enum.KeyCode.", cols: ["Tecla", "Enum.KeyCode"] },
    { key: "efeitos", title: "Efeitos de animação", desc: "Sinônimos de efeito → efeito canônico usado por animar.", cols: ["Nome", "Efeito"] },
    { key: "easings", title: "Estilos de suavização", desc: "Nome → Enum.EasingStyle.", cols: ["Nome", "EasingStyle"] },
    { key: "direcoes", title: "Direções de suavização", desc: "Nome → Enum.EasingDirection.", cols: ["Nome", "EasingDirection"] }
  ];

  function renderTabelas() {
    var host = $("#tables-host"); if (!host) return;
    var html = TABLE_DEFS.map(function (def) {
      var rows = Y.tables[def.key] || [];
      var filter = rows.length > 14
        ? '<div class="dict-search" style="max-width:340px;padding:8px 12px;margin-top:12px"><span aria-hidden="true">⌕</span><input type="search" placeholder="Filtrar…" data-tbl-filter="' + def.key + '" autocomplete="off"></div>'
        : "";
      var body = rows.map(function (r) {
        return '<tr><td><code>' + esc(r[0]) + "</code></td><td><code>" + esc(r[1]) + "</code></td></tr>";
      }).join("");
      return '<section class="tablecard" id="tab-' + def.key + '"><header><h3>' + esc(def.title) +
        " <span class=\"muted\" style=\"font-weight:400\">(" + rows.length + ")</span></h3><p>" + esc(def.desc) + "</p>" + filter + "</header>" +
        '<div class="tablewrap"><table><thead><tr><th>' + esc(def.cols[0]) + "</th><th>" + esc(def.cols[1]) +
        "</th></tr></thead><tbody>" + body + "</tbody></table></div></section>";
    }).join("");

    var chips = function (title, arr) {
      return '<section class="tablecard"><header><h3>' + esc(title) + '</h3></header><div style="padding:16px 20px;display:flex;flex-wrap:wrap;gap:8px">' +
        arr.map(function (x) { return '<span class="pill"><code>' + esc(x) + "</code></span>"; }).join("") + "</div></section>";
    };
    html += chips("Construtores e namespaces globais do Luau/Roblox", Y.tables.globais);
    html += chips("Funções globais disponíveis", Y.tables.funcoes);
    host.innerHTML = html;

    $$("[data-tbl-filter]").forEach(function (inp) {
      inp.addEventListener("input", function () {
        var q = noAcc(inp.value);
        var card = inp.closest(".tablecard");
        $$("tbody tr", card).forEach(function (tr) {
          tr.style.display = noAcc(tr.textContent).indexOf(q) >= 0 ? "" : "none";
        });
      });
    });
  }

  /* ------------------------------------------------------------ exemplos */
  function renderExemplos() {
    var host = $("#examples-host"); if (!host) return;
    host.innerHTML = Y.exemplos.map(function (ex) {
      return '<section class="example" id="ex-' + ex.id + '"><header>' +
        "<h3>" + esc(ex.titulo) + '</h3><span class="badge ' + esc(ex.contexto) + '">' + esc(ex.contexto) + "</span></header>" +
        '<p class="desc">' + esc(ex.descricao) + "</p>" + codeBlock(ex.codigo) + "</section>";
    }).join("");
    attachCopy(host);
  }

  /* ------------------------------------------------------------ limitações */
  function renderLimitacoes() {
    var host = $("#limits-host"); if (!host) return;
    var L = Y.limitacoes;
    host.innerHTML =
      '<div class="doc"><h3>Limitações conhecidas</h3><p class="muted">Verificadas contra o gerador atual. Vale conferir antes de usar.</p></div>' +
      '<div class="grid cols-2" style="margin:16px 0 40px">' + L.conhecidas.map(function (c) {
        return '<div class="card"><h3>' + esc(c.t) + "</h3><p>" + c.d + "</p></div>";
      }).join("") + "</div>" +
      '<div class="doc"><h3>Removido da linguagem em V8</h3><p class="muted">Estas construções eram aceitas mas não produziam nada no Luau gerado. Agora dão erro explícito.</p>' +
      "<ul>" + L.removidas.map(function (r) { return "<li><code>" + esc(r.split(" — ")[0].trim()) + "</code>" + (r.split(" — ")[1] ? " — " + esc(r.split(" — ")[1]) : "") + "</li>"; }).join("") +
      "</ul></div>";
  }

  /* ------------------------------------------------------------ copy */
  function attachCopy(scope) {
    $$("pre", scope).forEach(function (pre) {
      if ($("[data-copy]", pre)) return;
      var b = document.createElement("button");
      b.className = "copybtn"; b.type = "button"; b.setAttribute("data-copy", "");
      b.textContent = "Copiar";
      pre.insertBefore(b, pre.firstChild);
    });
  }
  document.addEventListener("click", function (ev) {
    var b = ev.target.closest("[data-copy]"); if (!b) return;
    var code = b.parentNode.querySelector("code");
    var text = code ? code.textContent : "";
    var done = function () { b.textContent = "Copiado!"; b.classList.add("done"); setTimeout(function () { b.textContent = "Copiar"; b.classList.remove("done"); }, 1400); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, function () { fallback(text, done); });
    else fallback(text, done);
  });
  function fallback(text, done) {
    var ta = document.createElement("textarea"); ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(ta); done();
  }

  /* ------------------------------------------------------------ routing */
  var VIEWS = ["inicio", "guia", "referencia", "tabelas", "exemplos", "limitacoes"];
  function route() {
    var h = location.hash.replace(/^#\/?/, "");
    var parts = h.split("/");
    var view = VIEWS.indexOf(parts[0]) >= 0 ? parts[0] : "inicio";
    var param = parts[1] || "";
    VIEWS.forEach(function (v) { var el = $("#view-" + v); if (el) el.classList.toggle("active", v === view); });
    $$(".mainnav a, .mobilenav a").forEach(function (a) {
      a.classList.toggle("active", a.getAttribute("href") === "#/" + view);
    });
    if (view === "referencia" && param) {
      var el = document.getElementById("ref-" + param);
      if (el) {
        $$(".ref-item.selected").forEach(function (x) { x.classList.remove("selected"); });
        el.classList.add("selected");
        setTimeout(function () { el.scrollIntoView({ block: "center" }); }, 60);
      }
    } else {
      try { window.scrollTo({ top: 0, behavior: "auto" }); } catch (e) {}
    }
    closeMobile();
  }
  window.addEventListener("hashchange", route);

  /* ------------------------------------------------------------ palette */
  var idx = [];
  function buildIndex() {
    Y.entries.forEach(function (e) {
      idx.push({ t: e.w.join(" / "), s: e.c, d: stripTags(e.d), go: "#/referencia/" + slug(e.w) });
    });
    Y.guia.forEach(function (g) { idx.push({ t: g.titulo, s: "Guia", d: g.resumo, go: "#/guia" , anchor: "guia-" + g.id }); });
    idx.push({ t: "Tabelas de referência", s: "Tabela", d: "Serviços, propriedades, materiais, fontes, teclas, efeitos e easing.", go: "#/tabelas" });
    idx.push({ t: "Exemplos", s: "Exemplos", d: "Scripts prontos: fundamentos, laços, funções, menu/câmera e mais.", go: "#/exemplos" });
    idx.push({ t: "Limitações conhecidas", s: "Guia", d: "O que evitar e o que foi removido em V8.", go: "#/limitacoes" });
  }
  var palActive = 0, palResults = [];
  function openPalette() { var o = $("#overlay"); o.classList.add("open"); var i = $("#pal-input"); i.value = ""; paintPalette(""); i.focus(); }
  function closePalette() { $("#overlay").classList.remove("open"); }
  function paintPalette(q) {
    q = noAcc(q);
    palResults = !q ? idx.slice(0, 40) : idx.filter(function (it) {
      return (noAcc(it.t) + " " + noAcc(it.s) + " " + noAcc(it.d)).indexOf(q) >= 0;
    }).slice(0, 60);
    palActive = 0;
    var host = $("#pal-list");
    if (!palResults.length) { host.innerHTML = '<p class="pal-empty">Nada encontrado para “' + esc(q) + '”.</p>'; return; }
    host.innerHTML = palResults.map(function (it, i) {
      return '<button class="pal-item' + (i === 0 ? " active" : "") + '" type="button" data-i="' + i + '">' +
        '<span class="t">' + esc(it.t) + '</span><span class="d">' + esc(it.d) + '</span><span class="c">' + esc(it.s) + "</span></button>";
    }).join("");
  }
  function palGo(i) {
    var it = palResults[i]; if (!it) return;
    closePalette();
    if (location.hash === it.go) { route(); } else { location.hash = it.go; }
    if (it.anchor) setTimeout(function () { var el = document.getElementById(it.anchor); if (el) el.scrollIntoView(); }, 80);
  }
  function initPalette() {
    buildIndex();
    $("#overlay").addEventListener("click", function (ev) { if (ev.target.id === "overlay") closePalette(); });
    $("#pal-input").addEventListener("input", function (ev) { paintPalette(ev.target.value); });
    $("#pal-list").addEventListener("click", function (ev) {
      var b = ev.target.closest("[data-i]"); if (b) palGo(parseInt(b.getAttribute("data-i"), 10));
    });
    $("#pal-input").addEventListener("keydown", function (ev) {
      if (ev.key === "ArrowDown" || ev.key === "ArrowUp") {
        ev.preventDefault();
        palActive = Math.max(0, Math.min(palResults.length - 1, palActive + (ev.key === "ArrowDown" ? 1 : -1)));
        $$("#pal-list .pal-item").forEach(function (el, i) { el.classList.toggle("active", i === palActive); });
        var a = $("#pal-list .pal-item.active"); if (a) a.scrollIntoView({ block: "nearest" });
      } else if (ev.key === "Enter") { ev.preventDefault(); palGo(palActive); }
      else if (ev.key === "Escape") { closePalette(); }
    });
    document.addEventListener("keydown", function (ev) {
      var typing = /^(INPUT|TEXTAREA|SELECT)$/.test((document.activeElement || {}).tagName || "");
      if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "k") { ev.preventDefault(); openPalette(); return; }
      if (ev.key === "/" && !typing) { ev.preventDefault(); openPalette(); return; }
      if (ev.key === "Escape") closePalette();
    });
    $$("[data-search-open]").forEach(function (b) { b.addEventListener("click", openPalette); });
  }

  /* ------------------------------------------------------------ mobile nav */
  function closeMobile() { var m = $("#mobilenav"); if (m) m.classList.remove("open"); }
  function initMobile() {
    var btn = $("#menubtn"); var m = $("#mobilenav");
    if (btn && m) btn.addEventListener("click", function () { m.classList.toggle("open"); });
  }

  /* ------------------------------------------------------------ boot */
  document.addEventListener("DOMContentLoaded", function () {
    initTheme();
    $$("pre[data-static]").forEach(function (pre) {
      var c = pre.querySelector("code"); if (c) c.innerHTML = highlight(c.textContent);
    });
    renderGuia(); renderReferencia(); renderTabelas(); renderExemplos(); renderLimitacoes();
    initPalette(); initMobile();
    route();
  });
})();
