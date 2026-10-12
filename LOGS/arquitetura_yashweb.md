# Arquitetura — YashWebEngine

## Visão geral
Plataforma web para criar jogos 2D usando YashScript no navegador, com login Google, editor visual de cenas e execução dos scripts em tempo real.

## Componentes principais

### 1. Frontend (React + TypeScript)
**Stack:** React 18, Vite, TailwindCSS, Zustand (estado global)

#### Módulos:
- **AuthModule**: Login/logout via Firebase Auth (Google Provider)
- **ProjectManager**: CRUD de projetos, lista, duplicar, excluir
- **SceneEditor**: Editor visual drag-and-drop de objetos 2D
  - Canvas interativo (Konva.js ou Fabric.js)
  - Paleta de ferramentas (blocos, sprites, textos, triggers)
  - Inspector de propriedades (posição, tamanho, cor, rotação, âncora)
  - Hierarquia de objetos (árvore de cena)
  - Timeline básica para animações simples
- **CodeEditor**: Monaco Editor com syntax highlighting customizado para YashScript
  - Autocomplete baseado nas tabelas do `data.js` atual
  - Lint inline mostrando erros do compilador
  - Painel lateral com documentação contextual
- **GameRunner**: Execução do jogo em iframe isolado
  - Recebe código Luau transpilado para JS
  - Loop de renderização (requestAnimationFrame)
  - Input handler (teclado, mouse, touch)
  - Sistema de eventos (colisão, trigger, update)
- **AssetManager**: Upload/gerenciamento de sprites, sons, fontes
  - Preview inline
  - Otimização automática (compressão imagens)

### 2. Backend (Node.js + Express)
**Stack:** Node 20+, Express, Firebase Admin SDK

#### Endpoints REST:
```
POST   /api/auth/login              # Troca token Firebase por sessão
GET    /api/projects                # Lista projetos do usuário
POST   /api/projects                # Cria projeto novo
GET    /api/projects/:id            # Busca projeto + cena + scripts
PUT    /api/projects/:id            # Salva alterações
DELETE /api/projects/:id            # Remove projeto
POST   /api/projects/:id/duplicate  # Duplica projeto

POST   /api/compile                 # Compila YashScript → Luau (via fengari)
POST   /api/transpile               # Transpila Luau → JS (parser próprio)

POST   /api/assets/upload           # Upload imagem/som → Cloud Storage
GET    /api/assets/:id              # Serve asset otimizado
```

#### Serviços internos:
- **CompilerService**: Wrapper do fengari que executa `compilador.lua` + `gerador.lua`
- **TranspilerService**: Converte Luau para JavaScript ES6+ (subset viável)
- **ValidationService**: Chega limites de tamanho, quotas, sanitiza inputs
- **CacheService**: Redis/Memcached para respostas frequentes

### 3. Banco de Dados (Firestore)
**Estrutura:**
```javascript
users/{uid}
├── email: string
├── displayName: string
├── photoURL: string
├── createdAt: timestamp
└── projects: [] // array de projectIds

projects/{projectId}
├── ownerId: string (uid)
├── name: string
├── description: string
├── thumbnail: string (URL)
├── scene: {
│     objects: [{
│       id: string,
│       type: "block"|"sprite"|"text"|"trigger",
│       x: number, y: number,
│       width: number, height: number,
│       rotation: number,
│       color: string,
│       spriteUrl?: string,
│       scriptId?: string
│     }],
│     camera: {x, y, zoom},
│     physics: {gravity, friction}
│   }
├── scripts: [{
│     id: string,
│     name: string,
│     code: string, // YashScript original
│     compiledLuau: string, // cache pós-compilação
│     transpiledJs: string  // cache pós-transpilação
│   }]
├── assets: [assetIds]
├── settings: {
│     resolution: {width, height},
│     fps: number,
│     backgroundColor: string
│   }
├── createdAt: timestamp
└── updatedAt: timestamp

assets/{assetId}
├── ownerId: string
├── projectId: string
├── type: "image"|"audio"|"font"
├── filename: string
├── url: string (Cloud Storage)
├── size: number
├── mimeType: string
└── uploadedAt: timestamp
```

### 4. Armazenamento de Assets (Firebase Cloud Storage)
- Buckets separados por usuário/projeto
- Regras de acesso: leitura pública apenas para thumbnails; upload requer autenticação
- CDN automático via Firebase Hosting

### 5. Motor de Jogo 2D (JavaScript puro)
**Executa dentro do iframe sandboxed.**

#### Core systems:
```javascript
class Engine {
  constructor(canvas, sceneData, scripts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.objects = []; // instâncias a partir de sceneData.objects
    this.scripts = {}; // Map<scriptId, Function> (transpilado)
    this.input = new InputHandler();
    this.physics = new PhysicsSystem(sceneData.physics);
    this.renderer = new Renderer(this.ctx);
    this.camera = new Camera(sceneData.camera);
  }

  start() {
    this.loadObjects();
    this.bindScripts();
    this.loop();
  }

  loop() {
    const dt = this.calculateDeltaTime();
    
    this.processInput();
    this.updatePhysics(dt);
    this.executeScripts('update', dt);
    this.checkCollisions();
    this.render();
    
    requestAnimationFrame(() => this.loop());
  }

  bindScripts() {
    // Cada script tem hooks: onStart, onUpdate, onCollision, etc.
    for (const obj of this.objects) {
      if (obj.scriptId && this.scripts[obj.scriptId]) {
        const fn = this.scripts[obj.scriptId];
        obj.onStart = () => fn.onStart?.(obj, this);
        obj.onUpdate = (dt) => fn.onUpdate?.(obj, dt, this);
        obj.onCollision = (other) => fn.onCollision?.(obj, other, this);
      }
    }
  }
}

class PhysicsSystem {
  constructor(config) {
    this.gravity = config.gravity || 0;
    this.friction = config.friction || 0.98;
  }

  update(objects, dt) {
    for (const obj of objects) {
      obj.vy += this.gravity * dt;
      obj.x += obj.vx * dt;
      obj.y += obj.vy * dt;
      
      obj.vx *= this.friction;
      obj.vy *= this.friction;
    }
  }

  checkAABB(a, b) {
    return !(a.x + a.width < b.x || 
             a.x > b.x + b.width || 
             a.y + a.height < b.y || 
             a.y > b.y + b.height);
  }
}

class Renderer {
  constructor(ctx) {
    this.ctx = ctx;
  }

  draw(objects, camera) {
    this.ctx.save();
    this.ctx.translate(-camera.x, -camera.y);
    this.ctx.scale(camera.zoom, camera.zoom);

    for (const obj of objects) {
      switch(obj.type) {
        case 'block':
          this.drawRect(obj);
          break;
        case 'sprite':
          this.drawSprite(obj);
          break;
        case 'text':
          this.drawText(obj);
          break;
      }
    }

    this.ctx.restore();
  }
}
```

#### API exposta aos scripts (equivalente às funções globais do Luau):
```javascript
// Disponível dentro dos scripts transpilados
const ys = {
  mover(obj, dx, dy) { /* ... */ },
  girar(obj, angulo) { /* ... */ },
  escala(obj, sx, sy) { /* ... */ },
  cor(obj, hex) { /* ... */ },
  imprimir(...args) { console.log(...args); },
  esperar(segundos) { return new Promise(r => setTimeout(r, segundos*1000)); },
  teclaApertada(tecla) { return input.keys[tecla]; },
  mousePosicao() { return {x: input.mouse.x, y: input.mouse.y}; },
  criarBloco(props) { /* retorna nova instância */ },
  destruirObjeto(obj) { /* remove da cena */ },
  som(url) { /* toca áudio */ },
  // ... todas as funções mapeadas de gerador.lua
};
```

### 6. Pipeline de Compilação

**Fluxo completo:**
```
Usuário escreve YashScript
         ↓
[Frontend] Envia POST /api/compile {code: "..."}
         ↓
[Backend] CompilerService.executa(compilador.lua, gerador.lua) via fengari
         ↓
Retorna Luau válido
         ↓
[Backend] TranspilerService.luauParaJS(luauCode)
         ↓
Retorna JavaScript ES6+
         ↓
[Frontend] Injeta JS no iframe sandboxed
         ↓
[Engine] Executa scripts em runtime
```

#### Transpiler Luau → JS (desafio crítico)
Precisa converter:
- Sintaxe Lua (`local`, `function`, `end`, `then`, `nil`) → JS equivalente
- Tabelas `{}` → Objects/Arrays JS
- Índices `[1-based]` → `[0-based]`
- Operadores (`..` concatenação → `+`)
- Loops (`for i=1,n do` → `for(let i=0;i<n;i++)`)
- Condicionais (`if...elseif...else...end` → `if...else if...else...{}`)
- Métodos (`:` sugar → `.call()` explícito ou wrapper)
- Global functions (`print`, `wait`, etc.) → namespace `ys.*`

**Exemplo:**
```lua
-- Luau input
local jogador = workspace.Jogador
jogador.Velocidade = Vector3.new(10, 0, 5)
while true do
  jogador.Position = jogador.Position + jogador.Velocidade * wait(0.1)
end
```

```javascript
// JS output
const jogador = ys.workspace.Jogador;
jogador.Velocidade = new ys.Vector3(10, 0, 5);
while (true) {
  jogador.Position = jogador.Position.add(jogador.Velocidade.multiply(await ys.wait(0.1)));
}
```

## Decisões técnicas justificadas

### Por que Firebase?
- OAuth Google nativo (zero configuração extra)
- Firestore escalona automaticamente
- Cloud Functions integradas (deploy junto com frontend)
- Free tier generoso para MVP
- Alternativa considerada: Supabase (Postgres + Auth próprio) — mais controle mas setup maior

### Por que transpilar Luau→JS em vez de interpretar no servidor?
- Latência zero durante gameplay (tudo roda client-side)
- Escalabilidade horizontal infinita (cada jogador usa CPU local)
- Funciona offline após primeira carga
- Interpretação server-side inviabilizaria multiplayer fluido

### Por que iframe sandboxed para GameRunner?
- Isolamento total de segurança (scripts maliciosos não acessam DOM principal)
- Permite reload instantâneo sem afetar editor
- Compatível com CSP restritiva

### Estrutura monorepo proposta
```
YashScript-Roblox-Studio/
├── packages/
│   ├── compiler/          # compilador.lua, gerador.lua (já existe)
│   ├── engine/            # Motor 2D JavaScript standalone
│   │   ├── src/
│   │   │   ├── core.ts
│   │   │   ├── physics.ts
│   │   │   ├── renderer.ts
│   │   │   └── api.ts
│   │   └── package.json
│   ├── transpiler/        # Luau → JS parser/converter
│   │   ├── src/
│   │   │   ├── lexer.ts
│   │   │   ├── parser.ts
│   │   │   ├── ast.ts
│   │   │   └── generator.ts
│   │   └── package.json
│   ├── web-app/           # Frontend React
│   │   ├── src/
│   │   │   ├── components/
│   │   │   ├── pages/
│   │   │   ├── services/
│   │   │   └── store/
│   │   └── vite.config.ts
│   └── api-server/        # Backend Express
│       ├── src/
│       │   ├── routes/
│       │   ├── services/
│       │   ├── middleware/
│       │   └── db/
│       └── tsconfig.json
├── LOGS/                  # Documentação existente
├── testes/                # Testes atuais (manter compatibilidade)
└── turbo.json             # Orquestração monorepo
```

## Roadmap de implementação

### Fase 1: Fundação (2 semanas)
- [ ] Setup monorepo com TurboRepo
- [ ] Configurar Firebase project (Auth, Firestore, Storage)
- [ ] Implementar módulo Auth no frontend (login/logout Google)
- [ ] Criar schema inicial do Firestore
- [ ] Backend básico: endpoints de CRUD de projetos

### Fase 2: Compilador na Web (1 semana)
- [ ] Empacotar fengari como dependency npm
- [ ] Endpoint `/api/compile` funcional
- [ ] Cache de resultados compilados no Firestore
- [ ] Validação de sintaxe antes de enviar ao backend

### Fase 3: Transpiler Luau→JS (3 semanas — maior risco)
- [ ] Lexer/parser Luau subset (sem metatables complexos)
- [ ] AST transformer Lua→JS
- [ ] Generator de código JavaScript ES6+
- [ ] Testes unitários cobrindo todos os exemplos `.yash` existentes
- [ ] Runtime helpers (`ys.*` API bridge)

### Fase 4: Engine 2D MVP (2 semanas)
- [ ] Canvas renderer básico (retângulos coloridos)
- [ ] Physics system (gravidade, fricção, AABB collisions)
- [ ] Input handler (keyboard/mouse events)
- [ ] Script binding lifecycle (onStart/onUpdate/onCollision)
- [ ] Game loop otimizado (60fps target)

### Fase 5: Scene Editor (3 semanas)
- [ ] Konva.js integration (canvas interativo)
- [ ] Drag-and-drop de objetos
- [ ] Property inspector bidirecional
- [ ] Hierarquia de cena (tree view)
- [ ] Undo/Redo stack
- [ ] Save/load cenas completas

### Fase 6: Code Editor Integration (1 semana)
- [ ] Monaco Editor setup
- [ ] Custom YashScript language definition
- [ ] Autocomplete das tabelas (`data.js` exportado como JSON)
- [ ] Inline error reporting (link com `/api/compile`)
- [ ] Split-view: editor de código + preview da cena

### Fase 7: Polish & Deploy (2 semanas)
- [ ] Asset manager UI (upload sprites/sons)
- [ ] Thumbnail generation automática
- [ ] Responsividade mobile básica
- [ ] Performance profiling (lazy loading, code splitting)
- [ ] CI/CD pipeline (GitHub Actions → Vercel)
- [ ] Documentação pública (atualizar site existente)

**Total estimado: ~14 semanas** (considerando dedicação parcial)

## Riscos identificados

### Alto impacto
1. **Complexidade do transpiler Luau→JS**
   - Mitigação: começar com subset mínimo (sem closures anônimas, sem múltiplos returns)
   - Plano B: usar fengari WASM no cliente (experimental, performance incerta)

2. **Performance do motor 2D em dispositivos móveis**
   - Mitigação: WebGL renderer alternativo (PixiJS) se Canvas2D engasgar
   - Profile contínuo desde fase 4

3. **Custos de armazenamento Firestore/Storage em escala**
   - Mitigação: compressão agressiva de assets, TTL para snapshots antigos
   - Monitoramento via alerts do Firebase Console

### Médio impacto
4. **Segurança de scripts arbitrários rodando no browser**
   - Mitigação: iframe sandboxed + CSP estrita + review manual de termos de uso
   
5. **Compatibilidade entre versões do compilador (.lua)**
   - Mitigação: versionamento semântico nos projetos salvos, migração automática

## Métricas de sucesso

- **Time-to-first-game**: < 5 minutos desde signup até protótipo jogável
- **Latência de compilação**: < 2s round-trip (YashScript → JS pronto pra executar)
- **FPS mínimo garantido**: 30fps em Chrome mobile mid-range (Snapdragon 6xx)
- **Taxa de conclusão de tutorial**: > 60% usuários completam primeiro projeto guiado

---

Próximos passos imediatos:
1. Confirmar decisões acima (Firebase vs alternativas)
2. Definir escopo reduzido do transpiler (quais features Luau suportar inicialmente)
3. Prototipar prova-de-conceito da engine 2D fora do contexto web (HTML standalone)
4. Estimar custo mensal projetado para free tier limits
