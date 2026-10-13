(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.YashLexer = factory();
})(typeof self !== "undefined" ? self : this, function () {
  var ACENTOS = "áàâãäåéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ";
  var SIMB2 = ["==", "!=", "<=", ">=", "~=", "..", "//"];
  var SIMB1 = "=+-*/%^()[]{},.:<>";

  function ehLetra(c) { return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c === "_" || ACENTOS.indexOf(c) >= 0; }
  function ehDig(c) { return c >= "0" && c <= "9"; }

  function tokenizar(fonte) {
    fonte = String(fonte == null ? "" : fonte);
    var toks = [], i = 0, n = fonte.length, linha = 1;
    function push(t, v) { toks.push({ t: t, v: v, l: linha }); }
    function erro(msg) { throw { erro: msg, linha: linha }; }

    while (i < n) {
      var c = fonte[i];
      if (c === "\r") { i++; continue; }
      if (c === " " || c === "\t") { i++; continue; }
      if (c === "\n") { push("new", "\n"); linha++; i++; continue; }
      if (c === "#") { while (i < n && fonte[i] !== "\n") i++; continue; }
      if (c === '"' || c === "'") {
        var q = c, s = "", j = i + 1;
        while (j < n) {
          var d = fonte[j];
          if (d === "\\") { var e = fonte[j + 1]; s += e === "n" ? "\n" : e === "t" ? "\t" : e === "r" ? "\r" : e; j += 2; continue; }
          if (d === q) break;
          if (d === "\n") erro("string sem fechar");
          s += d; j++;
        }
        if (j >= n) erro("string sem fechar");
        push("str", s); i = j + 1; continue;
      }
      if (ehDig(c) || (c === "." && ehDig(fonte[i + 1] || ""))) {
        var k = i, num = "";
        if (c === ".") { num = "0."; k++; while (k < n && ehDig(fonte[k])) num += fonte[k++]; }
        else {
          while (k < n && ehDig(fonte[k])) num += fonte[k++];
          if (fonte[k] === "." && ehDig(fonte[k + 1] || "")) { num += "."; k++; while (k < n && ehDig(fonte[k])) num += fonte[k++]; }
          if (fonte[k] === "e" || fonte[k] === "E") {
            var m = k + 1; if (fonte[m] === "+" || fonte[m] === "-") m++;
            if (ehDig(fonte[m] || "")) { num += fonte.slice(k, m); k = m; while (k < n && ehDig(fonte[k])) num += fonte[k++]; }
          }
        }
        push("num", parseFloat(num)); i = k; continue;
      }
      if (ehLetra(c)) {
        var w = "";
        while (i < n && (ehLetra(fonte[i]) || ehDig(fonte[i]))) w += fonte[i++];
        push("word", w); continue;
      }
      var dois = fonte.substr(i, 2);
      if (SIMB2.indexOf(dois) >= 0) { push("sym", dois); i += 2; continue; }
      if (SIMB1.indexOf(c) >= 0) { push("sym", c); i++; continue; }
      erro("caractere inesperado '" + c + "'");
    }
    push("eof", "");
    return toks;
  }

  return { tokenizar: tokenizar };
});
