const http = require("http"), fs = require("fs"), path = require("path");
const raiz = path.join(__dirname, "LOGS");
const tipos = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".lua": "text/plain; charset=utf-8", ".json": "application/json; charset=utf-8", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".webp": "image/webp", ".woff2": "font/woff2", ".map": "application/json" };
const porta = Number(process.env.PORTA) || 8080;
http.createServer(function (req, res) {
  let u = decodeURIComponent((req.url || "/").split("?")[0].split("#")[0]);
  if (u === "/") u = "/index.html";
  const alvo = path.join(raiz, u);
  const tenta = [alvo];
  if (!path.extname(alvo)) tenta.push(alvo + ".html");
  for (const t of tenta) {
    if (t.indexOf(raiz) === 0 && fs.existsSync(t) && fs.statSync(t).isFile()) {
      res.writeHead(200, { "content-type": tipos[path.extname(t).toLowerCase()] || "application/octet-stream", "cache-control": "no-store" });
      fs.createReadStream(t).pipe(res);
      return;
    }
  }
  res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
  res.end("404 - " + u);
}).listen(porta, function () {
  console.log("YashScript LOCAL no ar:");
  console.log("  Site:        http://localhost:" + porta + "/");
  console.log("  Playground:  http://localhost:" + porta + "/playground.html");
});
