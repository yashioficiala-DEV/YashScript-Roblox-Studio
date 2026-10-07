--[[ YASHDASH - gerado a partir do YashScript. ]]
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
        
    },
    continuos = {
        
    },
    elementos = {
        instrucoes = {
            props = {
                cor = cor(226, 232, 240),
                estilo = "branco",
                pai = "placarTexto",
                posicao = par(14, 38),
                tamanho_fonte = 14,
                texto = "Pegue as 3 moedas amarelas. Desvie da esfera vermelha. 30 segundos!"
            },
            tipo = "texto"
        },
        placarTexto = {
            props = {
                altura = 74,
                cor = cor(12, 14, 22),
                estilo = "caixa",
                largura = 320,
                posicao = par(20, 20),
                transparencia = 25
            },
            tipo = "painel"
        },
        titulo = {
            props = {
                cor = cor(255, 214, 0),
                estilo = "branco",
                pai = "placarTexto",
                posicao = par(14, 8),
                tamanho_fonte = 24,
                texto = "YASHDASH"
            },
            tipo = "texto"
        }
    },
    estilos = {
        
    },
    eventos = {{
            corpo = {{
                    cond = {
                        nome = "placar",
                        tipo = "criado"
                    },
                    corpo = {{
                            forma = "print",
                            norm = "print",
                            texto = "YASHDASH: interface carregada",
                            tipo = "log"
                        }},
                    tipo = "se"
                }},
            tipo = "iniciar"
        }},
    formas = {
        
    },
    huds = {
        
    },
    incluir = {
        
    },
    marcador = "YASHSCRIPT:",
    mundo = {
        
    },
    objetos = {
        placar = {
            moedas = 0,
            tempo = 30,
            terminou = 0,
            vidas = 3
        }
    },
    ordem_elementos = {"placarTexto", "titulo", "instrucoes"},
    principal = false,
    proibicoes = {
        
    },
    site = {
        
    },
    timers = {{
            corpo = {{
                    cond = {
                        obj = "placar.terminou",
                        op = "=",
                        tipo = "num",
                        val = 0
                    },
                    corpo = {{
                            caminho = "placar.tempo",
                            norm = "placar.tempo -=",
                            op = "-=",
                            tipo = "atrib",
                            valor = 1
                        }, {
                            caminho = "placar.moedas",
                            norm = "placar.moedas +=",
                            op = "+=",
                            tipo = "atrib",
                            valor = 1
                        }},
                    tipo = "se"
                }},
            intervalo = 1
        }}
}
--YASHC2--
Runtime.executar(_YashConfig)
