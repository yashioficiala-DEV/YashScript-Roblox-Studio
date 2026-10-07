--[[ YashScript V7.0 - gerado pelo plugin. Edite pelo plugin. ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local YashMod = ReplicatedStorage:WaitForChild("Yash")
local Runtime = require(YashMod:WaitForChild("Runtime"))

--YASHC1--
local function cor(r, g, b) return { t = "cor", r = r, g = g, b = b } end
local function par(x, y, z) if z == nil then return { t = "par", x = x, y = y } end return { t = "par", x = x, y = y, z = z } end
local _YashConfig = {
	acoes = {
		
	},
	animacoes = {
		
	},
	cenas = {
		Principal = {
			mostrar = true
		},
		TelaSobre = {
			mostrar = false
		}
	},
	continuos = {
		
	},
	elementos = {
		Janela = {
			props = {
				altura = 300,
				cena = "Principal",
				estilo = "botao-padrao",
				largura = 400,
				posicao = par(100, 100)
			},
			tipo = "painel"
		},
		btn = {
			props = {
				altura = 40,
				estilo = "botao-padrao",
				largura = 120,
				pai = "Janela",
				posicao = par(140, 200),
				texto = "Clique"
			},
			tipo = "botao"
		},
		btnSobre = {
			props = {
				altura = 40,
				estilo = "botao-padrao",
				largura = 120,
				pai = "Janela",
				posicao = par(140, 150),
				texto = "Sobre"
			},
			tipo = "botao"
		},
		titulo = {
			props = {
				estilo = "textos",
				pai = "Janela",
				posicao = par(20, 20),
				tamanho_fonte = 20,
				texto = "Ola Mundo"
			},
			tipo = "texto"
		}
	},
	estilos = {
		["botao-padrao"] = {
			arredondamento = 20,
			borda = 2,
			cor = cor(20, 20, 20),
			cor_borda = cor(80, 80, 80),
			cor_texto = "white",
			transicao = "0.15s ease"
		},
		textos = {
			cor_texto = "white",
			tamanho_fonte = 20
		}
	},
	eventos = {{
			alvo = "btn",
			corpo = {{
					norm = "mostrar texto",
					texto = "Voce clicou",
					tipo = "log"
				}, {
					props = {
						animacao = {
							efeito = "fade in",
							escala = 5,
							t = "anim"
						}
					},
					tipo = "prop"
				}},
			tipo = "clicar"
		}, {
			alvo = "btnSobre",
			corpo = {{
					acao = "mudar",
					alvo = "TelaSobre",
					anim = {
						duracao = 0.5,
						efeito = "fade in",
						t = "anim"
					},
					norm = "mudar cena TelaSobre",
					tipo = "cena"
				}},
			tipo = "clicar"
		}, {
			alvo = "btn",
			corpo = {{
					props = {
						cor_borda = cor(255, 255, 255)
					},
					tipo = "prop"
				}, {
					props = {
						borda = 2
					},
					tipo = "prop"
				}},
			tipo = "mouse_em"
		}, {
			alvo = "btn",
			corpo = {{
					props = {
						cor_borda = cor(80, 80, 80)
					},
					tipo = "prop"
				}, {
					props = {
						borda = 1
					},
					tipo = "prop"
				}},
			tipo = "mouse_sair"
		}, {
			corpo = {{
					norm = "mostrar texto",
					texto = "Pagina pronta",
					tipo = "log"
				}},
			tipo = "carregar"
		}},
	formas = {
		
	},
	huds = {
		
	},
	incluir = {
		
	},
	mundo = {
		
	},
	objetos = {
		
	},
	ordem_elementos = {"Janela", "titulo", "btn", "btnSobre"},
	principal = true,
	proibicoes = {
		
	},
	site = {
		fonte = "Arial",
		fundo = cor(0, 0, 0)
	},
	timers = {
		
	}
}
--YASHC2--
Runtime.executar(_YashConfig)
