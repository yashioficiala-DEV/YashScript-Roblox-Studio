// Testa o caminho WebGL sem placa de vídeo: usa um contexto falso que grava as
// chamadas, para provar que matrizes, malhas e o desenho 3D rodam sem exceção.
var path = require("path");
var YashWeb = require(path.join("..", "..", "LOGS", "assets", "engine.js"));

var total = 0, falhas = 0;
function ok(nome, cond, extra) {
  total++;
  if (cond) console.log("  ok  " + nome);
  else { falhas++; console.log("FALHA " + nome + (extra != null ? " -> " + extra : "")); }
}

function mockGL() {
  var gl = {
    _drawE: 0, _drawA: 0,
    VERTEX_SHADER: 1, FRAGMENT_SHADER: 2, COMPILE_STATUS: 3, LINK_STATUS: 4,
    ARRAY_BUFFER: 5, ELEMENT_ARRAY_BUFFER: 6, STATIC_DRAW: 7, FLOAT: 8,
    UNSIGNED_SHORT: 9, UNSIGNED_INT: 10, DEPTH_TEST: 11, CULL_FACE: 12, BACK: 13,
    COLOR_BUFFER_BIT: 14, DEPTH_BUFFER_BIT: 15, TRIANGLES: 16, LINES: 17
  };
  ["createProgram", "createShader", "attachShader", "shaderSource", "compileShader",
    "linkProgram", "useProgram", "bindBuffer", "bufferData", "enable", "enableVertexAttribArray",
    "vertexAttribPointer", "uniformMatrix4fv", "uniform3fv", "clearColor", "clear", "viewport",
    "cullFace", "deleteShader"].forEach(function (k) { gl[k] = function () { return {}; }; });
  gl.getShaderParameter = function () { return true; };
  gl.getProgramParameter = function () { return true; };
  gl.getShaderInfoLog = function () { return ""; };
  gl.getAttribLocation = function () { return 0; };
  gl.getUniformLocation = function () { return {}; };
  gl.createBuffer = function () { return {}; };
  gl.getExtension = function () { return null; };
  gl.drawElements = function () { gl._drawE++; };
  gl.drawArrays = function () { gl._drawA++; };
  return gl;
}
function canvasComGL(gl) {
  return { width: 800, height: 600, getContext: function () { return gl; } };
}

console.log("matemática 3D:");
var m = YashWeb.mat;
var id = m.modelo([0, 0, 0], [0, 0, 0], [1, 1, 1]);
var p = m.persp(0.9, 1.5, 1, 100);
var pm = m.mul(p, id);
ok("perspective * identidade preserva a projection", pm[0] === p[0] && pm[5] === p[5] && pm[15] === p[15]);
var olho = m.lookAt([0, 0, 5], [0, 0, 0], [0, 1, 0]);
ok("lookAt leva a camera para tras (-Z na translacao)", olho.length === 16 && olho[14] === -5);

console.log("malhas:");
var box = YashWeb.malhas.box();
ok("box tem 24 vertices e 36 indices", box.pos.length === 72 && box.idx.length === 36);
var esq = YashWeb.malhas.esfera(12, 8);
ok("esfera gera indices multiplos de 3", esq.idx.length % 3 === 0 && esq.pos.length === esq.norm.length);
var pl = YashWeb.malhas.plano();
ok("plano tem normal apontando para +Y", pl.norm[1] === 1);
var cil = YashWeb.malhas.cilindro(16);
ok("cilindro fecha com tampas (indices extras)", cil.idx.length > 16 * 6);

console.log("pose 3D (campo do estúdio -> mundo):");
var posBox = YashWeb.pose3d({ tipo: "box3d", x: 100, y: 100, w: 40, h: 40, profundidade: 60, z: 0, rot: 0 });
ok("centro do box cai em (x+w/2, ... , y+h/2)", posBox.pos[0] === 120 && posBox.pos[2] === 120);
ok("altura (Y) usa a profundidade", posBox.esc[1] === 60);
var posPl = YashWeb.pose3d({ tipo: "plano3d", x: 0, y: 0, w: 200, h: 200, profundidade: 8 });
ok("plano fica raso no eixo Y", posPl.esc[1] === 1);

console.log("render WebGL com contexto falso:");
var gl = mockGL();
var r3 = new YashWeb.Renderer3D(canvasComGL(gl));
ok("renderer detecta WebGL valido", r3.ativo === true && r3.gl === gl);
var objs = [
  { tipo: "box3d", x: 50, y: 50, w: 40, h: 40, profundidade: 40, cor: "#5b8bff" },
  { tipo: "esfera3d", x: 150, y: 50, w: 40, h: 40, profundidade: 40, cor: "#ff785a" },
  { tipo: "plano3d", x: 0, y: 0, w: 300, h: 300, profundidade: 8, cor: "#3c5a46" }
];
var lancou = null;
try { r3.draw(objs, "#0e1220", { cam: r3.cam, autoEnquadrar: true }); } catch (e) { lancou = e; }
ok("desenha sem lancar excecao", lancou === null, lancou && lancou.stack);
ok("emite um drawElements por no 3D (3)", gl._drawE === 3, "obtido " + gl._drawE);
ok("emite o chao (grade) em drawArrays", gl._drawA >= 1, "obtido " + gl._drawA);

console.log("navegação e picking 3D:");
// cena isolada com um box: a camera (auto-frame) aponta para o centro dele, cai na tela no meio
var umBox = [{ tipo: "box3d", x: 50, y: 50, w: 40, h: 40, profundidade: 40, cor: "#5b8bff" }];
var nav = new YashWeb.Renderer3D(canvasComGL(mockGL()));
nav.draw(umBox, "#0e1220", { cam: nav.cam });
var alvoBox = YashWeb.pose3d(umBox[0]).pos;
var sp = nav.projectar(alvoBox);
ok("projectar devolve ponto na tela", sp && isFinite(sp.x) && isFinite(sp.y));
ok("centro do box cai no meio da viewport (camera enquadra o alvo)", sp && Math.abs(sp.x - 400) < 3 && Math.abs(sp.y - 300) < 3, sp && (sp.x + "," + sp.y));
var alvoTela = nav.hitTest(umBox, sp.x, sp.y);
ok("hitTest seleciona o no sob o cursor", alvoTela === umBox[0]);
ok("hitTest em canto vazio nao pega nada", nav.hitTest(umBox, 5, 5) === null);
var yawAntes = nav.cam.yaw;
nav.orbitar(40, 0);
ok("orbitar muda o yaw e fixa a camera", nav.cam.yaw !== yawAntes && nav.cam.pinned === true);
var distAntes = nav.cam.dist;
nav.zoom(2);
ok("zoom aproxima/afasta (dist muda)", nav.cam.dist !== distAntes);
nav.vista("cima");
ok("vista('cima') inclina a camera para baixo", nav.cam.pitch > 1);
nav.enquadrar();
ok("enquadrar solta a camera (auto-frame de novo)", nav.cam.pinned === false);
nav.draw(umBox, "#0e1220", { cam: nav.cam }); // repinta com a camera nova
var noChao = nav.chaoEm(sp.x, sp.y, nav.alturaBase(umBox[0]));
ok("chaoEm devolve um ponto do plano sob o cursor", noChao && isFinite(noChao[0]) && isFinite(noChao[2]));

console.log("fallback sem WebGL:");
var semGl = new YashWeb.Renderer3D({ width: 10, height: 10, getContext: function () { return null; } });
ok("sem WebGL o renderer fica inativo", semGl.ativo === false);
var ctxFalso = new YashWeb.Renderer3D({ width: 10, height: 10, getContext: function () { return { }; } });
ok("contexto que nao e WebGL e rejeitado", ctxFalso.ativo === false);

console.log("\n" + total + " ok, " + falhas + " falhas");
process.exit(falhas ? 1 : 0);
