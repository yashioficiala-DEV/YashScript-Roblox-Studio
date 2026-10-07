--[[ YASHDASH - gerado a partir do YashScript. ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local YashMod = ReplicatedStorage:WaitForChild("Yash")
local Runtime = require(YashMod:WaitForChild("Runtime"))

--YASHC1--
local function cor(r, g, b) return { t = "cor", r = r, g = g, b = b } end
local function par(x, y, z) if z == nil then return { t = "par", x = x, y = y } end return { t = "par", x = x, y = y, z = z } end

local _YashConfig = {
    acoes = {
        derrota = {{
                cond = {
                    obj = "heroi.terminou",
                    op = "=",
                    tipo = "num",
                    val = 0
                },
                corpo = {{
                        caminho = "heroi.terminou",
                        norm = "heroi.terminou =",
                        op = "=",
                        tipo = "atrib",
                        valor = 1
                    }, {
                        forma = "print",
                        norm = "print",
                        texto = "DERROTA! Tente de novo",
                        tipo = "log"
                    }},
                tipo = "se"
            }},
        pegouA = {{
                caminho = "heroi.pontos",
                norm = "heroi.pontos +=",
                op = "+=",
                tipo = "atrib",
                valor = 1
            }, {
                caminho = "heroi.pontos",
                forma = "print",
                norm = "print",
                tipo = "log"
            }, {
                alvo = "moedaA",
                metodo = "destruir",
                norm = "moedaA.destruir()",
                tipo = "metodo"
            }},
        pegouB = {{
                caminho = "heroi.pontos",
                norm = "heroi.pontos +=",
                op = "+=",
                tipo = "atrib",
                valor = 1
            }, {
                caminho = "heroi.pontos",
                forma = "print",
                norm = "print",
                tipo = "log"
            }, {
                alvo = "moedaB",
                metodo = "destruir",
                norm = "moedaB.destruir()",
                tipo = "metodo"
            }},
        pegouC = {{
                caminho = "heroi.pontos",
                norm = "heroi.pontos +=",
                op = "+=",
                tipo = "atrib",
                valor = 1
            }, {
                caminho = "heroi.pontos",
                forma = "print",
                norm = "print",
                tipo = "log"
            }, {
                alvo = "moedaC",
                metodo = "destruir",
                norm = "moedaC.destruir()",
                tipo = "metodo"
            }},
        vitoria = {{
                cond = {
                    obj = "heroi.terminou",
                    op = "=",
                    tipo = "num",
                    val = 0
                },
                corpo = {{
                        caminho = "heroi.terminou",
                        norm = "heroi.terminou =",
                        op = "=",
                        tipo = "atrib",
                        valor = 1
                    }, {
                        forma = "print",
                        norm = "print",
                        texto = "VITORIA! 3 moedas coletadas antes do tempo!",
                        tipo = "log"
                    }},
                tipo = "se"
            }}
    },
    animacoes = {
        
    },
    cenas = {
        
    },
    continuos = {{
            cond = {
                obj = "heroi.pontos",
                op = ">=",
                tipo = "num",
                val = 3
            },
            corpo = {{
                    nome = "vitoria",
                    norm = "executar acao vitoria",
                    tipo = "acao"
                }}
        }, {
            cond = {
                obj = "heroi.tempo",
                op = "<=",
                tipo = "num",
                val = 0
            },
            corpo = {{
                    nome = "derrota",
                    norm = "executar acao derrota",
                    tipo = "acao"
                }}
        }, {
            cond = {
                obj = "heroi.vidas",
                op = "<=",
                tipo = "num",
                val = 0
            },
            corpo = {{
                    nome = "derrota",
                    norm = "executar acao derrota",
                    tipo = "acao"
                }}
        }},
    elementos = {
        
    },
    estilos = {
        
    },
    eventos = {{
            alvo = "moedaA",
            corpo = {{
                    nome = "pegouA",
                    norm = "executar acao pegouA",
                    tipo = "acao"
                }},
            sujeito = "heroi",
            tipo = "tocar"
        }, {
            alvo = "moedaB",
            corpo = {{
                    nome = "pegouB",
                    norm = "executar acao pegouB",
                    tipo = "acao"
                }},
            sujeito = "heroi",
            tipo = "tocar"
        }, {
            alvo = "moedaC",
            corpo = {{
                    nome = "pegouC",
                    norm = "executar acao pegouC",
                    tipo = "acao"
                }},
            sujeito = "heroi",
            tipo = "tocar"
        }, {
            alvo = "perigo",
            corpo = {{
                    caminho = "heroi.vidas",
                    norm = "heroi.vidas -=",
                    op = "-=",
                    tipo = "atrib",
                    valor = 1
                }, {
                    caminho = "heroi.pontos",
                    norm = "heroi.pontos -=",
                    op = "-=",
                    tipo = "atrib",
                    valor = 1
                }, {
                    caminho = "heroi.vidas",
                    forma = "print",
                    norm = "print",
                    tipo = "log"
                }, {
                    alvo = "perigo",
                    norm = "mover perigo para (0, 6, 0) velocidade 40",
                    para = par(0, 6, 0),
                    tipo = "mover",
                    velocidade = 40
                }, {
                    norm = "esperar 1",
                    tipo = "espera",
                    valor = 1
                }, {
                    alvo = "perigo",
                    norm = "mover perigo para (0, 3, 0) velocidade 20",
                    para = par(0, 3, 0),
                    tipo = "mover",
                    velocidade = 20
                }},
            sujeito = "heroi",
            tipo = "tocar"
        }, {
            corpo = {{
                    cond = {
                        nome = "heroi",
                        tipo = "criado"
                    },
                    corpo = {{
                            forma = "print",
                            norm = "print",
                            texto = "YASHDASH pronto - pegue as 3 moedas e desvie do perigo vermelho",
                            tipo = "log"
                        }},
                    tipo = "se"
                }},
            tipo = "iniciar"
        }},
    formas = {
        chao = {
            props = {
                cor = cor(74, 132, 94),
                material = "grama",
                posicao = par(0, -1, 0),
                tamanho = par(80, 2, 80)
            },
            tipo = "plataforma"
        },
        moedaA = {
            props = {
                cor = cor(255, 214, 0),
                material = "metal",
                posicao = par(13, 2, 13),
                tamanho = par(2.5, 2.5, 2.5)
            },
            tipo = "esfera"
        },
        moedaB = {
            props = {
                cor = cor(255, 214, 0),
                material = "metal",
                posicao = par(-13, 2, 13),
                tamanho = par(2.5, 2.5, 2.5)
            },
            tipo = "esfera"
        },
        moedaC = {
            props = {
                cor = cor(255, 214, 0),
                material = "metal",
                posicao = par(0, 2, -15),
                tamanho = par(2.5, 2.5, 2.5)
            },
            tipo = "esfera"
        },
        paredeDir = {
            props = {
                cor = cor(150, 150, 158),
                material = "concreto",
                posicao = par(19, 3, 0),
                tamanho = par(2, 6, 34)
            },
            tipo = "bloco"
        },
        paredeEsq = {
            props = {
                cor = cor(150, 150, 158),
                material = "concreto",
                posicao = par(-19, 3, 0),
                tamanho = par(2, 6, 34)
            },
            tipo = "bloco"
        },
        perigo = {
            props = {
                controlavel = true,
                cor = cor(224, 48, 48),
                material = "neon",
                posicao = par(0, 3, 0),
                tamanho = par(3, 3, 3),
                velocidade = 10,
                vida = 3
            },
            tipo = "esfera"
        }
    },
    huds = {
        
    },
    incluir = {
        
    },
    marcador = "YASHSCRIPT:",
    mundo = {
        ceu = cor(112, 176, 255),
        neblina = cor(205, 226, 250),
        neblina_fim = 180,
        neblina_inicio = 45
    },
    objetos = {
        heroi = {
            pontos = 0,
            tempo = 30,
            terminou = 0,
            vidas = 3
        }
    },
    ordem_elementos = {
        
    },
    principal = false,
    proibicoes = {
        
    },
    site = {
        
    },
    timers = {{
            corpo = {{
                    cond = {
                        obj = "heroi.terminou",
                        op = "=",
                        tipo = "num",
                        val = 0
                    },
                    corpo = {{
                            caminho = "heroi.tempo",
                            norm = "heroi.tempo -=",
                            op = "-=",
                            tipo = "atrib",
                            valor = 1
                        }},
                    tipo = "se"
                }},
            intervalo = 1
        }}
}
--YASHC2--
Runtime.montarMundo(_YashConfig)
