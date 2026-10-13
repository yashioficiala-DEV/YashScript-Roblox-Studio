const fs = require("fs");
const c = fs.readFileSync("compilador/compilador.lua", "utf8");
const json = JSON.stringify(c);
const luaStr = '"' + json.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
console.log("contains @@GERADOR@@:", luaStr.includes("@@GERADOR@@"));
console.log("contains @@COMPILADOR@@:", luaStr.includes("@@COMPILADOR@@"));
