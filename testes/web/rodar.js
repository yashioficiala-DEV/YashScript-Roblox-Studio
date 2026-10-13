var fs = require("fs");
var path = require("path");
var cp = require("child_process");

var dir = __dirname;
var arquivos = fs.readdirSync(dir).filter(function (f) { return /\.test\.js$/.test(f); }).sort();

var falhas = 0;
arquivos.forEach(function (f) {
  console.log("\n===== " + f + " =====");
  var r = cp.spawnSync(process.execPath, [path.join(dir, f)], { stdio: "inherit" });
  if (r.status !== 0) falhas++;
});
console.log("\n===== resumo: " + (arquivos.length - falhas) + "/" + arquivos.length + " arquivos verdes =====");
process.exit(falhas ? 1 : 0);
