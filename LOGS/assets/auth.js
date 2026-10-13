(function (global) {
  "use strict";

  var CFG = global.FIREBASE_CONFIG || {};
  var NUVEM = !!(CFG.apiKey && CFG.projectId);
  var SDK = "https://www.gstatic.com/firebasejs/10.14.1/";

  var K_USER = "yash.conta.v1";
  var K_PROJ = "yash.projetos.v1";
  var K_SKIP = "yash.gate.skip";
  var K_VER = "yash.app.ver";
  var K_PERFIL = "yash.perfil.v1";
  var K_NOME = "yash.nomeamento.v1";
  var APP_VER = "2026.10.13.1";

  var modo = NUVEM ? "firebase" : "local";
  var usuario = null;
  var pronto = false;
  var cbsMudanca = [];
  var cbsPronto = [];
  var authRef = null;
  var dbRef = null;
  var fbfn = null;
  var _gate = null;
  var nomeFeito = {};

  function agora() { return Date.now(); }
  function novoId(pre) { return (pre || "id") + "_" + Math.random().toString(36).slice(2, 10) + agora().toString(36); }
  function ler(k, d) { try { var s = localStorage.getItem(k); return s ? JSON.parse(s) : d; } catch (e) { return d; } }
  function gravar(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  function clonar(o) { return o ? JSON.parse(JSON.stringify(o)) : o; }
  function comPrazo(p, ms, rotulo) {
    var relogio = null;
    var prazo = new Promise(function (_, rej) {
      relogio = setTimeout(function () {
        var e = new Error((rotulo || "A operacao") + " não respondeu. A nuvem está sem conexão no momento — tente de novo em instantes.");
        e.code = "nuvem-sem-resposta";
        rej(e);
      }, ms);
    });
    return Promise.race([p, prazo]).then(function (v) { clearTimeout(relogio); return v; }, function (e) { clearTimeout(relogio); throw e; });
  }
  function pesoJSON(o) { try { return JSON.stringify(o).length; } catch (e) { return 0; } }
  function ehTempLocal() { return !!(usuario && usuario.tipo === "temporario" && usuario.uid && usuario.uid.indexOf("temp_") === 0); }
  function nuvemAtiva() { return NUVEM && modo === "firebase" && !!fbfn && !ehTempLocal(); }
  function estado() { return { modo: modo, nuvem: NUVEM, pronto: pronto, usuario: usuario ? clonar(usuario) : null }; }
  function emitir() { var st = estado(); for (var i = 0; i < cbsMudanca.length; i++) { try { cbsMudanca[i](st); } catch (e) { console.error(e); } } }
  function marcarPronto() { if (pronto) return; pronto = true; var c = cbsPronto; cbsPronto = []; for (var i = 0; i < c.length; i++) { try { c[i](estado()); } catch (e) {} } }
  function usuarioNorm(u) { if (!u) return null; if (u.bannerTipo !== "imagem") u.bannerTipo = "cor"; return u; }
  function base(extra) {
    return Object.assign({
      nome: "Jogador", email: "", foto: "", bannerTipo: "cor", bannerCor: "#5b8bff",
      bannerFoto: "", tipo: "google", expiraEm: 0, criadoEm: agora()
    }, extra || {});
  }
  function expirado(u) { return !!(u && u.tipo === "temporario" && u.expiraEm && u.expiraEm < agora()); }
  function diasRestantes(u) { if (!u || !u.expiraEm) return 0; return Math.max(0, Math.ceil((u.expiraEm - agora()) / 86400000)); }

  function migrarLocal() {
    var v = null;
    try { v = localStorage.getItem(K_VER); } catch (e) {}
    if (v === APP_VER) return false;
    try { localStorage.setItem(K_VER, APP_VER); } catch (e) {}
    return true;
  }
  function limparSessao(reload) {
    usuario = null;
    try { if (NUVEM && fbfn && authRef) fbfn.ca.signOut(authRef).catch(function () {}); } catch (e) {}
    try { localStorage.removeItem(K_USER); localStorage.removeItem(K_SKIP); localStorage.removeItem(K_VER); localStorage.removeItem(K_PERFIL); } catch (e) {}
    try { sessionStorage.removeItem(K_SKIP); } catch (e) {}
    var dbs = ["firebaseLocalStorageDb", "firebase-heartbeat-database", "firebase-installations-database"];
    for (var i = 0; i < dbs.length; i++) { try { if (global.indexedDB) indexedDB.deleteDatabase(dbs[i]); } catch (e) {} }
    if (reload === false) return;
    setTimeout(function () { try { location.reload(); } catch (e) {} }, 180);
  }
  function mostrarRecuperacao(motivo) {
    try {
      if (!document.body || document.getElementById("ys-recuperar")) return;
      var box = el("div", { id: "ys-recuperar", role: "alert", style: "position:fixed;left:12px;right:12px;bottom:12px;z-index:2147483000;display:flex;gap:10px;align-items:center;flex-wrap:wrap;background:#171b26;color:#eef1f7;border:1px solid #2c3446;border-radius:12px;padding:12px 14px;font:14px/1.35 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.45)" });
      box.appendChild(el("span", { style: "flex:1 1 220px;min-width:160px", text: "O login demorou para responder. Você pode recuperar sem apagar seus projetos da nuvem:" }));
      box.appendChild(el("button", { type: "button", style: "cursor:pointer;border:0;border-radius:8px;padding:8px 12px;font:inherit;background:#5b8bff;color:#fff;font-weight:600", text: "Limpar sessão e recarregar", onclick: function () { api.limparSessao(); } }));
      box.appendChild(el("button", { type: "button", style: "cursor:pointer;border:1px solid #2c3446;border-radius:8px;padding:8px 12px;font:inherit;background:#232a3a;color:#eef1f7", text: "Só recarregar", onclick: function () { location.reload(); } }));
      box.appendChild(el("button", { type: "button", style: "cursor:pointer;border:1px solid #2c3446;border-radius:8px;padding:8px 12px;font:inherit;background:transparent;color:#9aa6bd", text: "Fechar", onclick: function () { if (box.parentNode) box.parentNode.removeChild(box); } }));
      document.body.appendChild(box);
    } catch (e) {}
  }
  function mensagemErro(e) {
    var c = (e && e.code) || "";
    var m = {
      "auth/popup-closed-by-user": "Login cancelado.",
      "auth/cancelled-popup-request": "Login cancelado.",
      "auth/popup-blocked": "O navegador bloqueou a janela de login. Libere pop-ups e tente de novo.",
      "auth/network-request-failed": "Falha de rede. Verifique sua conexão.",
      "auth/operation-not-allowed": "Este tipo de login não está habilitado no Firebase.",
      "auth/admin-restricted-operation": "O login por conta temporária está desativado no momento. Entre com o Google para continuar.",
      "auth/internal-error": "Falha ao falar com o serviço de login. Tente novamente.",
      "auth/unauthorized-domain": "Domínio não autorizado no Firebase. Adicione este domínio em Authentication > Domínios autorizados.",
      "permission-denied": "As regras do Firebase bloquearam a gravação. Libere a leitura/escrita em Firestore > Regras para o usuário autenticado.",
      "unavailable": "Não foi possível falar com a nuvem agora. Seus dados ficaram salvos neste navegador — tente de novo quando voltar a internet."
    };
    if (m[c]) return m[c];
    var s = (e && e.message) || String(e);
    if (/Firebase/i.test(s)) return "Não foi possível entrar (" + (c || "erro") + "). Tente novamente ou use o Google.";
    return s;
  }

  function lerImagem(file, maxW, maxH, mime, quality) {
    return new Promise(function (resolve, reject) {
      if (!file) return reject(new Error("Nenhum arquivo selecionado."));
      if (file.size > 5 * 1024 * 1024) return reject(new Error("Imagem muito grande (máx. 5MB)."));
      if (file.type && file.type.indexOf("image/") !== 0) return reject(new Error("Envie uma imagem PNG ou JPG."));
      var fr = new FileReader();
      fr.onerror = function () { reject(new Error("Falha ao ler o arquivo.")); };
      fr.onload = function () {
        var img = new Image();
        img.onerror = function () { reject(new Error("Imagem inválida.")); };
        img.onload = function () {
          var esc = Math.min(1, (maxW || img.width) / img.width, (maxH || img.height) / img.height);
          var w = Math.max(1, Math.round(img.width * esc));
          var h = Math.max(1, Math.round(img.height * esc));
          var c = document.createElement("canvas"); c.width = w; c.height = h;
          c.getContext("2d").drawImage(img, 0, 0, w, h);
          var out;
          try { out = c.toDataURL(mime || "image/png", quality == null ? 0.85 : quality); }
          catch (e) { return reject(new Error("Não foi possível processar a imagem.")); }
          if (out.length > 600000) return reject(new Error("Imagem ficou grande demais, escolha uma menor."));
          resolve(out);
        };
        img.src = fr.result;
      };
      fr.readAsDataURL(file);
    });
  }

  function localEntrar(tipo) {
    usuario = usuarioNorm(Object.assign({ uid: novoId(tipo === "temporario" ? "temp" : "local") },
      tipo === "temporario"
        ? base({ nome: "Conta temporária", tipo: "temporario", expiraEm: agora() + 7 * 86400000 })
        : base({ nome: "Visitante", tipo: "google" })));
    gravar(K_USER, usuario);
    emitir();
    return usuario;
  }
  function localSair() { usuario = null; gravar(K_USER, null); emitir(); }
  function localListar() {
    return ler(K_PROJ, []).filter(function (p) { return usuario && p.donoId === usuario.uid; })
      .sort(function (a, b) { return (b.atualizadoEm || 0) - (a.atualizadoEm || 0); });
  }
  function localCriar(nome) {
    var arr = ler(K_PROJ, []);
    var p = { id: novoId("proj"), donoId: usuario.uid, nome: nome || "Projeto sem nome", codigo: "", criadoEm: agora(), atualizadoEm: agora() };
    arr.push(p); gravar(K_PROJ, arr); return p;
  }
  function localCarregar(id) {
    var p = ler(K_PROJ, []).filter(function (x) { return x.id === id; })[0];
    return (p && usuario && p.donoId === usuario.uid) ? p : null;
  }
  function localSalvar(id, dados) {
    var arr = ler(K_PROJ, []);
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === id && usuario && arr[i].donoId === usuario.uid) {
        Object.assign(arr[i], dados, { atualizadoEm: agora() }); gravar(K_PROJ, arr); return arr[i];
      }
    }
    return null;
  }
  function localExcluir(id) { gravar(K_PROJ, ler(K_PROJ, []).filter(function (p) { return !(p.id === id && usuario && p.donoId === usuario.uid); })); }

  function jaNomeou() { try { return localStorage.getItem(K_NOME) === "1"; } catch (e) { return false; } }
  function marcarNomeou() { try { localStorage.setItem(K_NOME, "1"); } catch (e) {} }
  function talvezPedirNome() {
    if (!usuario || nomeFeito[usuario.uid]) return;
    nomeFeito[usuario.uid] = true;
    if (jaNomeou()) return;
    try { if (global.YashUI && YashUI.pedirNomeConta) YashUI.pedirNomeConta(); } catch (e) {}
  }
  function carregarFirebase() {
    return Promise.all([
      import(SDK + "firebase-app.js"),
      import(SDK + "firebase-auth.js"),
      import(SDK + "firebase-firestore.js")
    ]).then(function (mods) {
      fbfn = { ca: mods[1], cs: mods[2] };
      var app = mods[0].initializeApp(CFG);
      authRef = fbfn.ca.getAuth(app);
      dbRef = fbfn.cs.getFirestore(app);
      return fbfn.ca.setPersistence(authRef, fbfn.ca.browserLocalPersistence);
    });
  }
  function perfilRef(uid) { return fbfn.cs.doc(dbRef, "usuarios", uid); }
  function perfilDeUser(user) {
    return base({
      nome: user.displayName || (user.isAnonymous ? "Conta temporária" : "Jogador"),
      email: user.email || "", foto: user.photoURL || "",
      tipo: user.isAnonymous ? "temporario" : "google",
      expiraEm: user.isAnonymous ? agora() + 7 * 86400000 : 0
    });
  }
  function lerPerfilCache(uid) {
    var c = ler(K_PERFIL, null);
    return (c && c.uid === uid && c.dados) ? c.dados : null;
  }
  function gravarPerfilCache(uid, dados) {
    try { gravar(K_PERFIL, { uid: uid, dados: dados }); } catch (e) {}
  }
  function aplicarUsuario(user, dados) {
    if (dados.tipo === "temporario" && dados.expiraEm && dados.expiraEm < agora()) {
      return fbfn.ca.signOut(authRef).then(function () { return null; });
    }
    if (dados.tipo === "temporario") dados.expiraEm = dados.expiraEm || (agora() + 7 * 86400000);
    usuario = usuarioNorm(Object.assign({ uid: user.uid, email: user.email || "" }, dados));
    gravarPerfilCache(user.uid, usuario);
    return usuario;
  }
  function carregarPerfil(user) {
    return comPrazo(fbfn.cs.getDoc(perfilRef(user.uid)), 8000, "Ler o perfil na nuvem").then(function (snap) {
      if (!snap.exists()) {
        var dados = perfilDeUser(user);
        dados.nomeEscolhido = false;
        return comPrazo(fbfn.cs.setDoc(perfilRef(user.uid), dados), 8000, "Criar o perfil na nuvem").then(function () { return dados; });
      }
      return snap.data();
    }).then(function (dados) {
      if (usuario && usuario.uid === user.uid && dados.atualizadoEm && usuario.atualizadoEm && dados.atualizadoEm < usuario.atualizadoEm) return usuario;
      return aplicarUsuario(user, dados);
    }, function (e) {
      console.warn("Perfil na nuvem indisponível; mantendo os dados já salvos neste navegador:", e);
      var guardado = (usuario && usuario.uid === user.uid) ? usuario : lerPerfilCache(user.uid);
      return aplicarUsuario(user, guardado ? Object.assign(perfilDeUser(user), guardado) : perfilDeUser(user));
    });
  }
  function fbcriar(nome) {
    var dados = { donoId: usuario.uid, nome: nome || "Projeto sem nome", codigo: "", criadoEm: agora(), atualizadoEm: agora() };
    return comPrazo(fbfn.cs.addDoc(fbfn.cs.collection(dbRef, "projetos"), dados), 8000, "Criar o projeto").then(function (ref) { return Object.assign({ id: ref.id }, dados); });
  }
  function fblistar() {
    var q = fbfn.cs.query(fbfn.cs.collection(dbRef, "projetos"), fbfn.cs.where("donoId", "==", usuario.uid));
    return comPrazo(fbfn.cs.getDocs(q), 8000, "Listar seus projetos").then(function (snap) {
      var arr = []; snap.forEach(function (d) { var x = d.data(); x.id = d.id; arr.push(x); });
      arr.sort(function (a, b) { return (b.atualizadoEm || 0) - (a.atualizadoEm || 0); }); return arr;
    });
  }
  function fbcarregar(id) {
    return comPrazo(fbfn.cs.getDoc(fbfn.cs.doc(dbRef, "projetos", id)), 8000, "Abrir o projeto").then(function (snap) {
      if (!snap.exists()) return null;
      var p = snap.data(); p.id = snap.id;
      return (!usuario || p.donoId !== usuario.uid) ? null : p;
    });
  }
  function fbsalvar(id, dados) {
    var ref = fbfn.cs.doc(dbRef, "projetos", id);
    return comPrazo(fbfn.cs.getDoc(ref).then(function (snap) {
      if (!snap.exists()) throw new Error("Projeto não encontrado.");
      return comPrazo(fbfn.cs.updateDoc(ref, Object.assign({}, dados, { atualizadoEm: agora() })), 8000, "Salvar o projeto");
    }), 15000, "Salvar o projeto").then(function () {
      return Object.assign({ id: id }, dados, { atualizadoEm: agora() });
    });
  }
  function fbexcluir(id) { return comPrazo(fbfn.cs.deleteDoc(fbfn.cs.doc(dbRef, "projetos", id)), 8000, "Excluir o projeto"); }

  function inicioFirebase() {
    return carregarFirebase().then(function () {
      fbfn.ca.getRedirectResult(authRef).catch(function (e) { console.warn("getRedirectResult:", e); });
      fbfn.ca.onAuthStateChanged(authRef, function (user) {
        if (!user) {
          var lt = usuarioNorm(ler(K_USER, null));
          if (lt && lt.tipo === "temporario" && lt.uid && lt.uid.indexOf("temp_") === 0 && !expirado(lt)) usuario = lt;
          else usuario = null;
          marcarPronto(); emitir(); return;
        }
        var cache = lerPerfilCache(user.uid);
        if (cache && cache.tipo === "temporario" && cache.expiraEm && cache.expiraEm < agora()) cache = null;
        var dados = cache || perfilDeUser(user);
        usuario = usuarioNorm(Object.assign({ uid: user.uid, email: user.email || "" }, dados));
        marcarPronto(); emitir();
        carregarPerfil(user).then(function () {
          if (usuario && usuario.uid === user.uid) emitir();
        }, function (e) { console.warn("Perfil em segundo plano falhou:", e); });
      });
    });
  }

  var api = {
    ehNuvem: NUVEM,
    nuvemAtiva: nuvemAtiva,
    estado: estado,
    usuarioAtual: function () { return usuario ? clonar(usuario) : null; },
    estaLogado: function () { return !!usuario; },
    diasRestantes: function () { return diasRestantes(usuario); },
    aoPronto: function (cb) { if (pronto) cb(estado()); else cbsPronto.push(cb); },
    aoMudar: function (cb) { cbsMudanca.push(cb); if (pronto) cb(estado()); },
    lerImagem: lerImagem,
    mensagemErro: mensagemErro,
    versao: APP_VER,
    limparSessao: function () { limparSessao(true); },
    recuperar: function () { mostrarRecuperacao("manual"); },

    entrarComGoogle: function () {
      if (!NUVEM || modo !== "firebase") { localEntrar("google"); return Promise.resolve(usuario); }
      if (!fbfn) return Promise.reject(new Error("Conexão ainda carregando, tente novamente."));
      return fbfn.ca.signInWithPopup(authRef, new fbfn.ca.GoogleAuthProvider()).then(function (res) {
        var user = res && res.user;
        if (!usuario && user) return carregarPerfil(user).then(function () { emitir(); return usuario; });
        return usuario;
      }).catch(function (e) {
        if (e && (e.code === "auth/popup-blocked" || e.code === "auth/operation-not-supported-in-this-environment")) {
          return fbfn.ca.signInWithRedirect(authRef, new fbfn.ca.GoogleAuthProvider()).then(function () { return null; });
        }
        throw e;
      });
    },
    entrarTemporario: function () {
      if (!NUVEM || modo !== "firebase" || !fbfn) { localEntrar("temporario"); return Promise.resolve(usuario); }
      return fbfn.ca.signInAnonymously(authRef).then(function () { return usuario; }, function (e) {
        var c = (e && e.code) || "";
        if (c === "auth/admin-restricted-operation" || c === "auth/operation-not-allowed") return localEntrar("temporario");
        throw e;
      });
    },
    sair: function () { if (!nuvemAtiva()) { localSair(); return Promise.resolve(); } return fbfn.ca.signOut(authRef); },
    atualizarPerfil: function (patch) {
      if (!usuario) return Promise.reject(new Error("Sem conta."));
      var salvo = usuarioNorm(Object.assign({}, usuario, patch || {}, { atualizadoEm: agora() }));
      var envia = Object.assign({}, patch || {}, { atualizadoEm: salvo.atualizadoEm });
      if (nuvemAtiva() && pesoJSON(envia) > 900000) {
        return Promise.reject(new Error("Foto e banner juntos passam do tamanho que a nuvem aceita. Use imagens menores."));
      }
      usuario = salvo;
      gravar(K_USER, usuario);
      gravarPerfilCache(usuario.uid, usuario);
      emitir();
      if (!nuvemAtiva()) return Promise.resolve(usuario);
      return comPrazo(fbfn.cs.setDoc(perfilRef(usuario.uid), clonar(envia), { merge: true }), 8000, "Salvar na nuvem")
        .then(function () { return usuario; }, function (e) {
          console.warn("Falha ao sincronizar o perfil com o Firestore:", e);
          throw e;
        });
    },
    listarProjetos: function () { return usuario ? (nuvemAtiva() ? fblistar() : Promise.resolve(localListar())) : Promise.resolve([]); },
    criarProjeto: function (nome) { return usuario ? (nuvemAtiva() ? fbcriar(nome) : Promise.resolve(localCriar(nome))) : Promise.reject(new Error("Sem conta.")); },
    carregarProjeto: function (id) { return nuvemAtiva() ? fbcarregar(id) : Promise.resolve(localCarregar(id)); },
    salvarProjeto: function (id, dados) { return usuario ? (nuvemAtiva() ? fbsalvar(id, dados) : Promise.resolve(localSalvar(id, dados))) : Promise.reject(new Error("Sem conta.")); },
    excluirProjeto: function (id) { return usuario ? (nuvemAtiva() ? fbexcluir(id) : Promise.resolve(localExcluir(id))) : Promise.reject(new Error("Sem conta.")); },
    marcarPular: function () { try { sessionStorage.setItem(K_SKIP, "1"); } catch (e) {} },
    pulou: function () { try { return sessionStorage.getItem(K_SKIP) === "1"; } catch (e) { return false; } }
  };
  global.YashAuth = api;

  migrarLocal();
  if (NUVEM) {
    inicioFirebase().catch(function (e) {
      console.error("Firebase indisponível, usando modo local:", e);
      modo = "local";
      usuario = usuarioNorm(ler(K_USER, null));
      if (expirado(usuario)) { usuario = null; gravar(K_USER, null); }
      setTimeout(function () { marcarPronto(); emitir(); }, 0);
    });
  } else {
    usuario = usuarioNorm(ler(K_USER, null));
    if (expirado(usuario)) { usuario = null; gravar(K_USER, null); }
    setTimeout(function () { marcarPronto(); emitir(); }, 0);
  }

  setTimeout(function () { if (!pronto) mostrarRecuperacao("timeout"); }, 12000);

  function el(tag, attrs, kids) {
    var n = document.createElement(tag);
    if (attrs) for (var k in attrs) {
      var v = attrs[k];
      if (v == null) continue;
      if (k === "class") n.className = v;
      else if (k === "text") n.textContent = v;
      else if (k === "html") n.innerHTML = v;
      else if (k.indexOf("on") === 0 && typeof v === "function") n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v);
    }
    (kids || []).forEach(function (c) { if (c == null) return; n.appendChild(typeof c === "string" ? document.createTextNode(c) : c); });
    return n;
  }
  function avatarEl(u, size) {
    var s = size || 32;
    if (u && u.foto) return el("span", { class: "ys-avatar", style: "width:" + s + "px;height:" + s + "px" }, [el("img", { src: u.foto, alt: "" })]);
    var ini = (u && u.nome ? u.nome.trim().charAt(0) : "?").toUpperCase();
    return el("span", { class: "ys-avatar ys-avatar-ini", style: "width:" + s + "px;height:" + s + "px;font-size:" + Math.round(s * 0.44) + "px", text: ini });
  }

  var YashUI = {
    avatarEl: avatarEl,

    avisar: function (msg, tipo) {
      try {
        var t = el("div", { class: "ys-toast " + (tipo || ""), text: msg });
        document.body.appendChild(t);
        setTimeout(function () { if (t.parentNode) t.parentNode.removeChild(t); }, 5000);
      } catch (e) {}
    },

    exigirLogin: function (opcoes) {
      opcoes = opcoes || {};
      if (usuario) return Promise.resolve(usuario);
      return new Promise(function (resolve) {
        if (_gate) { _gate.resolvers.push(resolve); return; }
        var gate = { resolvers: [resolve], feito: false };
        _gate = gate;
        var bg = el("div", { class: "ys-modal-bg ys-gate" });
        var err = el("div", { class: "ys-gate-err" });
        var gbtn = NUVEM
          ? el("button", { class: "ys-gbtn", type: "button" }, [el("span", { class: "ys-gicon", text: "G" }), el("span", { text: "Entrar com Google" })])
          : el("button", { class: "ys-gbtn", type: "button" }, [el("span", { text: "Entrar neste navegador" })]);
        var tbtn = el("button", { class: "ys-btn ys-btn-temp", type: "button", text: "Conta temporária (7 dias)" });
        var pular = opcoes.permitirPular ? el("button", { class: "ys-link", type: "button", text: "Continuar sem entrar" }) : null;
        var trava = !pronto;
        gbtn.disabled = tbtn.disabled = trava;
        var notaModo = !NUVEM ? el("div", { class: "ys-gate-nota", text: "Modo local: a nuvem (Firebase) ainda não foi configurada." }) : null;
        var card = el("div", { class: "ys-gate-card" }, [
          el("div", { class: "ys-gate-logo", text: "Y" }),
          el("h2", { text: "Entrar no YashScript" }),
          el("p", { class: "ys-gate-sub", text: "Entre com o Google para salvar seus projetos na nuvem. Sua conta fica guardada neste navegador." }),
          gbtn, tbtn, notaModo, err, pular,
          el("a", { class: "ys-link ys-gate-voltar", href: "index.html", text: "← Voltar ao site" })
        ]);
        bg.appendChild(card);
        document.body.appendChild(bg);

        function concluir(u) {
          if (gate.feito) return;
          gate.feito = true;
          if (bg.parentNode) bg.parentNode.removeChild(bg);
          if (_gate === gate) _gate = null;
          gate.resolvers.forEach(function (r) { r(u); });
        }
        YashAuth.aoMudar(function (st) { if (st.usuario) concluir(st.usuario); });
        YashAuth.aoPronto(function () { gbtn.disabled = tbtn.disabled = false; });

        gbtn.onclick = function () { err.textContent = ""; gbtn.disabled = true; YashAuth.entrarComGoogle().then(function (u) { if (!u) gbtn.disabled = false; }, function (e) { err.textContent = mensagemErro(e); gbtn.disabled = false; }); };
        tbtn.onclick = function () { err.textContent = ""; tbtn.disabled = true; YashAuth.entrarTemporario().then(function (u) { if (!u) tbtn.disabled = false; }, function (e) { err.textContent = mensagemErro(e); tbtn.disabled = false; }); };
        if (pular) pular.onclick = function () { YashAuth.marcarPular(); concluir(null); };
      });
    },

    pedirNomeConta: function () {
      if (!usuario) return;
      nomeFeito[usuario.uid] = true;
      marcarNomeou();
      if (document.querySelector(".ys-nome-modal")) return;
      var u = usuario;
      var bg = el("div", { class: "ys-modal-bg ys-nome-modal" });
      var err = el("div", { class: "ys-form-err" });
      var inp = el("input", { class: "ys-input", type: "text", maxlength: "32", placeholder: "Como você quer ser chamado?", value: (u.nome && u.nome !== "Jogador") ? u.nome : "" });
      var av = el("div", { class: "ys-avatar-big" });
      function pintar() { av.innerHTML = ""; av.appendChild(avatarEl({ foto: u.foto, nome: inp.value || u.nome }, 76)); }
      inp.oninput = pintar;
      var salvar = el("button", { class: "ys-btn ys-btn-primary", type: "button", text: "Salvar nome" });
      var pular = el("button", { class: "ys-btn", type: "button", text: "Usar o nome do Google" });
      function fechar() { if (bg.parentNode) bg.parentNode.removeChild(bg); }
      function nomeSalvo(e) {
        fechar();
        YashUI.avisar("Nome guardado neste navegador. " + mensagemErro(e), "erro");
      }
      salvar.onclick = function () {
        var nome = (inp.value || "").trim();
        if (nome.length < 2) { err.textContent = "Escolha um nome com pelo menos 2 letras."; inp.focus(); return; }
        salvar.disabled = pular.disabled = true; err.textContent = "";
        YashAuth.atualizarPerfil({ nome: nome.slice(0, 32), nomeEscolhido: true }).then(fechar, nomeSalvo);
      };
      pular.onclick = function () {
        pular.disabled = salvar.disabled = true; err.textContent = "";
        YashAuth.atualizarPerfil({ nome: u.nome || "Jogador", nomeEscolhido: true }).then(fechar, nomeSalvo);
      };
      var card = el("div", { class: "ys-modal ys-nome" }, [
        el("div", { class: "ys-gate-logo", text: "Y" }),
        el("h2", { text: "Bem-vindo(a)!" }),
        el("p", { class: "ys-gate-sub", text: "Escolha o nome que vai aparecer na sua conta." }),
        av,
        el("label", { class: "ys-field" }, [el("span", { text: "Nome da conta" }), inp]),
        err,
        el("div", { class: "ys-modal-actions" }, [pular, salvar])
      ]);
      bg.appendChild(card);
      document.body.appendChild(bg);
      pintar();
      setTimeout(function () { try { inp.focus(); } catch (e) {} }, 50);
    },

    abrirPerfil: function () {
      if (!usuario) return;
      if (document.querySelector(".ys-perfil-modal")) return;
      var u = usuario;
      var ed = { nome: u.nome || "", foto: u.foto || "", bannerTipo: u.bannerTipo || "cor", bannerCor: u.bannerCor || "#5b8bff", bannerFoto: u.bannerFoto || "" };
      var bg = el("div", { class: "ys-modal-bg ys-perfil-modal" });
      var err = el("div", { class: "ys-form-err" });

      var banner = el("div", { class: "ys-banner-edit" });
      function pintarBanner() {
        if (ed.bannerTipo === "imagem" && ed.bannerFoto) banner.style.background = "center/cover no-repeat url('" + ed.bannerFoto + "')";
        else { banner.style.background = ""; banner.style.backgroundColor = ed.bannerCor; }
      }
      var av = el("div", { class: "ys-avatar-big" });
      function pintarAvatar() { av.innerHTML = ""; av.appendChild(avatarEl({ foto: ed.foto, nome: ed.nome }, 76)); }

      var inpFoto = el("input", { type: "file", accept: "image/png,image/jpeg", style: "display:none" });
      var inpBanner = el("input", { type: "file", accept: "image/png,image/jpeg", style: "display:none" });
      inpFoto.onchange = function () {
        var f = inpFoto.files && inpFoto.files[0]; if (!f) return;
        lerImagem(f, 160, 160, "image/png", 1).then(function (d) { ed.foto = d; pintarAvatar(); }, function (e) { err.textContent = e.message; });
      };
      inpBanner.onchange = function () {
        var f = inpBanner.files && inpBanner.files[0]; if (!f) return;
        lerImagem(f, 900, 300, "image/jpeg", 0.7).then(function (d) { ed.bannerTipo = "imagem"; ed.bannerFoto = d; pintarBanner(); radBanner(); }, function (e) { err.textContent = e.message; });
      };

      var nomeInp = el("input", { class: "ys-input", type: "text", maxlength: "32", value: ed.nome });
      nomeInp.oninput = function () { ed.nome = nomeInp.value; pintarAvatar(); };

      var radCor = el("input", { type: "radio", name: "ysban" });
      var radImg = el("input", { type: "radio", name: "ysban" });
      var corInp = el("input", { type: "color", value: ed.bannerCor });
      corInp.oninput = function () { ed.bannerTipo = "cor"; ed.bannerCor = corInp.value; pintarBanner(); radBanner(); };
      function radBanner() { radCor.checked = ed.bannerTipo === "cor"; radImg.checked = ed.bannerTipo === "imagem"; }
      radCor.onchange = function () { ed.bannerTipo = "cor"; pintarBanner(); };
      radImg.onchange = function () { ed.bannerTipo = "imagem"; if (!ed.bannerFoto) inpBanner.click(); pintarBanner(); };

      var salvar = el("button", { class: "ys-btn ys-btn-primary", type: "button", text: "Salvar" });
      var cancelar = el("button", { class: "ys-btn", type: "button", text: "Cancelar" });
      function fechar() { if (bg.parentNode) bg.parentNode.removeChild(bg); }
      cancelar.onclick = fechar;
      bg.addEventListener("click", function (e) { if (e.target === bg) fechar(); });
      salvar.onclick = function () {
        salvar.disabled = true; err.textContent = ""; salvar.textContent = "Salvando…";
        YashAuth.atualizarPerfil({ nome: ed.nome.trim() || "Jogador", foto: ed.foto, bannerTipo: ed.bannerTipo, bannerCor: ed.bannerCor, bannerFoto: ed.bannerFoto })
          .then(function () { fechar(); YashUI.avisar("Perfil salvo.", "ok"); },
                function (e) { fechar(); YashUI.avisar("Perfil salvo neste navegador. " + mensagemErro(e), "erro"); });
      };

      var card = el("div", { class: "ys-modal ys-perfil" }, [
        banner,
        el("div", { class: "ys-perfil-head" }, [
          av,
          el("div", { class: "ys-perfil-head-btns" }, [
            el("button", { class: "ys-btn ys-btn-sm", type: "button", text: "Alterar foto", onclick: function () { inpFoto.click(); } }),
            el("button", { class: "ys-btn ys-btn-sm", type: "button", text: "Alterar banner", onclick: function () { inpBanner.click(); } })
          ])
        ]),
        el("label", { class: "ys-field" }, [el("span", { text: "Apelido" }), nomeInp]),
        el("div", { class: "ys-field" }, [
          el("span", { text: "Banner" }),
          el("div", { class: "ys-banner-opts" }, [
            el("label", { class: "ys-opt" }, [radCor, el("span", { text: "Cor" }), corInp]),
            el("label", { class: "ys-opt" }, [radImg, el("span", { text: "Imagem" })])
          ])
        ]),
        err,
        el("div", { class: "ys-modal-actions" }, [cancelar, salvar]),
        inpFoto, inpBanner
      ]);
      bg.appendChild(card);
      document.body.appendChild(bg);
      pintarBanner(); pintarAvatar(); radBanner();
    },

    chip: function (container, opcoes) {
      opcoes = opcoes || {};
      function render() {
        container.innerHTML = "";
        var u = YashAuth.usuarioAtual();
        if (!u) {
          var b = el("button", { class: "ys-btn ys-btn-primary", type: "button", text: "Entrar", onclick: function () { YashUI.exigirLogin(opcoes).then(function () {}); } });
          container.appendChild(b); return;
        }
        var wrap = el("div", { class: "ys-pwrap" });
        var btn = el("button", { class: "ys-chip", type: "button" });
        btn.appendChild(avatarEl(u, 30));
        btn.appendChild(el("span", { class: "ys-chip-nome", text: u.nome }));
        if (u.tipo === "temporario") btn.appendChild(el("span", { class: "ys-chip-tag", text: diasRestantes(u) + "d" }));
        var menu = el("div", { class: "ys-menu" });
        menu.hidden = true;
        menu.appendChild(el("div", { class: "ys-menu-head" }, [
          avatarEl(u, 40),
          el("div", { class: "ys-menu-id" }, [
            el("div", { class: "ys-menu-nome", text: u.nome }),
            el("div", { class: "ys-menu-email", text: u.email || (u.tipo === "temporario" ? "conta temporária · " + diasRestantes(u) + " dias restantes" : "conta local") })
          ])
        ]));
        function mi(txt, fn) { return el("button", { class: "ys-mi", type: "button", text: txt, onclick: function (e) { e.stopPropagation(); menu.hidden = true; fn(); } }); }
        menu.appendChild(mi("Meu perfil", function () { YashUI.abrirPerfil(); }));
        if (opcoes.aoProjetos) menu.appendChild(mi("Meus projetos", opcoes.aoProjetos));
        menu.appendChild(el("div", { class: "ys-menu-sep" }));
        menu.appendChild(mi("Sair", function () { YashAuth.sair(); }));
        menu.appendChild(mi("Limpar sessão e recarregar", function () { limparSessao(true); }));
        btn.onclick = function (e) { e.stopPropagation(); menu.hidden = !menu.hidden; };
        wrap.appendChild(btn); wrap.appendChild(menu);
        container.appendChild(wrap);
      }
      YashAuth.aoMudar(render);
    }
  };
  global.YashUI = YashUI;
  api.aoMudar(function (st) { if (st.usuario) talvezPedirNome(); });

  document.addEventListener("click", function () {
    var ms = document.querySelectorAll(".ys-menu");
    for (var i = 0; i < ms.length; i++) ms[i].hidden = true;
  });
})(window);
