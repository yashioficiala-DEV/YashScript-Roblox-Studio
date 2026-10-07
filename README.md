# YashScript — Linguagem de programação em português para Roblox Studio

YashScript V8.0 é um **plugin de Roblox Studio** com **editor avançado + compilador de Luau
direto**. Você escreve código em YashScript (uma linguagem amigável em português) dentro de
uma fonte separada no atributo `YashScript` do script, e o plugin gera **Luau puro** no `Source`.

```
fonte YashScript -> Compilador.Compilar -> programa -> Gerador.GerarLuau
```

O `Source` gerado é Luau comum: dá para abrir, ler, editar e versionar no Studio.
A fonte YashScript fica separada, no atributo `YashScript` do próprio script.

## Funcionalidades do editor

- Auto-par de brackets: `( ) [ ] { } " " ' '`
- Syntax highlighting (RichText) por tipo: eventos, comandos, variáveis, etc.
- Autocomplete/IntelliSense com dicionário completo da linguagem (painel informativo)
- Editor padrão: `Tab` insere tab, `Enter` quebra linha, setas livres (sem capturas de tecla)
- Estado "sujo" por script (`*` no nome) persistido na memória ao trocar de script
- Scroll horizontal automático quando a linha passa da tela
- Dicionário contextual (hover mostra documentação)

## Como o contexto funciona

O contexto vem da **CLASSE do alvo**, nunca do texto:

| Tipo do script | Contexto gerado |
| --- | --- |
| `Script` | servidor |
| `LocalScript` | cliente (StarterGui vira PlayerGui) |
| `ModuleScript` | comum, e o módulo retorna uma tabela |

O compilador e o gerador moram **dentro do plugin** (fonte embutida). Nenhum
ModuleScript extra é necessário: o script gerado é Luau puro e roda sozinho.

## Como usar

1. Escolha um `Script` / `LocalScript` / `ModuleScript` (pela lista ou pelo botão "Selecionado").
2. O plugin lê a fonte YashScript do atributo `YashScript` do script.
3. Edite no painel avançado e clique em **Gravar**.
4. O plugin faz Compilar → GerarLuau e escreve o **LUAU PURO** no `Source`.

## Instalação (3 maneiras)

### 1. Instalador automático (recomendado para usuários)

1. Feche o Roblox Studio **completamente**.
2. Baixe o arquivo `instalar.cmd` (do **Releases** ou da raiz do repositório).
3. Dê **dois cliques** nele. O instalador baixa a versão mais recente do GitHub,
   extrai e instala em `%LOCALAPPDATA%\Roblox\Plugins\YashScript\plugin.lua`.
4. Abra o Roblox Studio e procure o YashScript na Toolbox (guia Plugins) ou na toolbar.

**O instalador também é desinstalador:** rode o `instalar.cmd` de novo com o plugin
já instalado e escolha:
- `1` — **Atualizar** para a versão mais recente
- `2` — **Desinstalar** (remove o plugin do PC)
- `3` — Sair

### 2. Via ZIP

1. Baixe o pacote `YashScript-Instalador.zip` (veja **Releases**).
2. Extraia os arquivos.
3. Feche o Roblox Studio **completamente**.
4. Copie a pasta `YashScript` para a pasta de plugins do Roblox:

   ```
   %LOCALAPPDATA%\Roblox\Plugins\
   ```

   Ou seja, o resultado final precisa ser:

   ```
   %LOCALAPPDATA%\Roblox\Plugins\YashScript\plugin.lua
   ```

5. Abra o Roblox Studio. O plugin aparece na **Toolbox** na guia **Plugins**.
6. Clique no botão da toolbar do YashScript.

### 2. Pelo repositório (para desenvolvedores)

Clone o repositório e instale com o script de build:

```powershell
npm install
node scripts\verificar_tudo.js
```

Isso empacota o plugin a partir das fontes e instala em
`%LOCALAPPDATA%\Roblox\Plugins\YashScript\plugin.lua`.

> **Importante:** depois de instalar/reinstalar o `plugin.lua`, **feche e reabra o Roblox Studio**
> para o plugin carregar o código novo.

## Desenvolvimento

| Script | O que faz |
| --- | --- |
| `node scripts/verificar_tudo.js` | Roda todas as verificação (lint, empacotar, instalar, sintaxe, testes, propagação). |
| `node scripts/empacotar_plugin.js` | Gera `plugin/plugin.lua` a partir de `_modelo_plugin.lua` + fontes. |
| `node scripts/instalar_plugin.js` | Copia `plugin/plugin.lua` para a pasta de plugins do Studio. |
| `node scripts/analisar.js` | Lint (luau-analyze) das fontes. |
| `node testes/rodar.js` | Testes do compilador (round-trip). |
| `node testes/rodar_modo_jogo.js` | Testes no modo jogo. |
| `node scripts/verificar_exemplos.js` | Valida os exemplos em `LOGS/`. |

### Estrutura

```
compilador/
  compilador.lua      Compilador YashScript (fonte pura, sem placeholders)
  gerador.lua         Gerador de Luau (fonte pura)
plugin/
  _modelo_plugin.lua  Modelo do plugin com placeholders @@COMPILADOR@@ / @@GERADOR@@
  plugin.lua          Plugin completo gerado (o que é instalado)
instalador/
  instalar.cmd        Instalador + desinstalador automático do plugin
scripts/              Ferramentas de build, lint, testes e instalação
testes/               Testes e exemplos
minijogo/             Exemplos de jogo (servidor + cliente)
LOGS/                 Documentação, exemplos (.yash) e notas de desenvolvimento
```

> **Atualização para usuários:** basta rodar o `instalar.cmd` de novo e escolher `1`.

## Suporte

Para dúvidas, correções ou sugestões, abra uma *issue* no repositório.