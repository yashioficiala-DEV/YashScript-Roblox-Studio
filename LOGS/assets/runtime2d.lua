local Runtime2D = {}

local Y2D = _G.Y2D
local function op(nome, ...)
	local f = Y2D[nome]
	if f then return f(...) end
end

local clock = 0
local threads = {}
local tweens = {}
local partes = {}
local guiObjs = {}
local overlaps = {}
local ponteiroX, ponteiroY = 0, 0
local ponteiroUltimo = nil
local mouseBotoes = {}

local function agora() return clock end

local function evento()
	local e = { conexoes = {} }
	function e:Connect(fn)
		table.insert(self.conexoes, fn)
		return { Disconnect = function() end }
	end
	function e:Once(fn)
		return self:Connect(fn)
	end
	function e:Wait()
		local ativo = true
		self:Connect(function() ativo = false end)
		while ativo do coroutine.yield({ espera = 1 / 60 }) end
	end
	function e:disparar(...)
		local args = table.pack(...)
		local copia = {}
		for i, f in ipairs(self.conexoes) do copia[i] = f end
		for _, f in ipairs(copia) do
			table.insert(threads, { co = coroutine.create(f), wake = clock, args = args })
		end
	end
	return e
end

local function novoThread(fn, ...)
	local args = table.pack(...)
	table.insert(threads, { co = coroutine.create(fn), wake = clock, args = (args.n > 0) and args or nil })
	return threads[#threads].co
end

local function spawn(fn, ...) novoThread(fn, ...) end
local function delay(t, fn, ...)
	local args = table.pack(...)
	table.insert(threads, { co = coroutine.create(fn), wake = clock + (t or 0), args = (args.n > 0) and args or nil })
end
local function wait(t)
	coroutine.yield({ espera = t or (1 / 60) })
end

local task = { wait = wait, spawn = spawn, delay = delay, defer = spawn }

-- ---- valores ----

local Vector3MT, Vector2MT, Color3MT = {}, {}, {}
Vector3MT.__index = Vector3MT
Vector2MT.__index = Vector2MT
Color3MT.__index = Color3MT
Vector3MT.__tostring = function(v) return v.x .. ", " .. v.y .. ", " .. v.z end
Vector2MT.__tostring = function(v) return v.x .. ", " .. v.y end
Color3MT.__tostring = function(c) return c.r .. ", " .. c.g .. ", " .. c.b end
Vector3MT.__add = function(a, b) return Vector3.new(a.x + b.x, a.y + b.y, a.z + b.z) end
Vector3MT.__sub = function(a, b) return Vector3.new(a.x - b.x, a.y - b.y, a.z - b.z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return Vector3.new(a.x * b, a.y * b, a.z * b) end
	if type(a) == "number" then return Vector3.new(b.x * a, b.y * a, b.z * a) end
	return Vector3.new(a.x * b.x, a.y * b.y, a.z * b.z)
end
Vector3MT.__unm = function(a) return Vector3.new(-a.x, -a.y, -a.z) end
Vector3MT.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
Vector2MT.__add = function(a, b) return Vector2.new(a.x + b.x, a.y + b.y) end
Vector2MT.__sub = function(a, b) return Vector2.new(a.x - b.x, a.y - b.y) end
Vector2MT.__mul = function(a, b)
	if type(b) == "number" then return Vector2.new(a.x * b, a.y * b) end
	return Vector2.new(a.x * b.x, a.y * b.y)
end
Color3MT.__eq = function(a, b) return a.r == b.r and a.g == b.g and a.b == b.b end
Color3MT.__mul = function(a, b)
	if type(b) == "number" then return Color3.new(a.r * b, a.g * b, a.b * b) end
	return Color3.new(a.r * b.r, a.g * b.g, a.b * b.b)
end

local Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0, _mt = Vector3MT }, Vector3MT) end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)
function Vector3MT:Lerp(o, a) return Vector3.new(self.x + (o.x - self.x) * a, self.y + (o.y - self.y) * a, self.z + (o.z - self.z) * a) end
function Vector3MT:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function Vector3MT:Cross(o) return Vector3.new(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x) end
Vector3MT.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
	if k == "Unit" then local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z); if m == 0 then return Vector3.new(0, 0, 0) end; return Vector3.new(v.x / m, v.y / m, v.z / m) end
	return rawget(Vector3MT, k)
end

local Vector2 = {}
function Vector2.new(x, y) return setmetatable({ x = x or 0, y = y or 0, _mt = Vector2MT }, Vector2MT) end
Vector2.zero = Vector2.new(0, 0)
function Vector2MT:Lerp(o, a) return Vector2.new(self.x + (o.x - self.x) * a, self.y + (o.y - self.y) * a) end

local Color3 = {}
function Color3.new(r, g, b) return setmetatable({ r = r or 0, g = g or 0, b = b or 0, _mt = Color3MT }, Color3MT) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v)
	local i = math.floor((h or 0) * 6)
	local f = (h or 0) * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return Color3.new(v, t, p) elseif i == 1 then return Color3.new(q, v, p)
	elseif i == 2 then return Color3.new(p, v, t) elseif i == 3 then return Color3.new(p, q, v)
	elseif i == 4 then return Color3.new(t, p, v) else return Color3.new(v, p, q) end
end
function Color3.fromHex(s) return Color3.new(0, 0, 0) end
Color3.new(0, 0, 0)
function Color3MT:Lerp(o, a) return Color3.new(self.r + (o.r - self.r) * a, self.g + (o.g - self.g) * a, self.b + (o.b - self.b) * a) end

local function ehVector3(v) return type(v) == "table" and v._mt == Vector3MT end
local function ehColor3(v) return type(v) == "table" and v._mt == Color3MT end

local UDim, UDim2 = {}, {}
local UDim2MT = {}
function UDim.new(s, o) return { Scale = s or 0, Offset = o or 0 } end
function UDim2.new(sx, ox, sy, oy) return setmetatable({ X = UDim.new(sx, ox), Y = UDim.new(sy, oy) }, UDim2MT) end
function UDim2.fromScale(sx, sy) return UDim2.new(sx, 0, sy, 0) end
function UDim2.fromOffset(ox, oy) return UDim2.new(0, ox, 0, oy) end
function UDim2MT.__tostring(u) return "{" .. u.X.Scale .. "," .. u.X.Offset .. "},{" .. u.Y.Scale .. "," .. u.Y.Offset .. "}" end
function UDim2MT:Lerp(o, a)
	return UDim2.new(
		self.X.Scale + (o.X.Scale - self.X.Scale) * a, self.X.Offset + (o.X.Offset - self.X.Offset) * a,
		self.Y.Scale + (o.Y.Scale - self.Y.Scale) * a, self.Y.Offset + (o.Y.Offset - self.Y.Offset) * a)
end
local function ehUDim2(u) return type(u) == "table" and getmetatable(u) == UDim2MT end

local CFrameMT = {}
local function rad(g) return g * math.pi / 180 end
local function deg(r) return r * 180 / math.pi end
local CFrame = {}
function CFrame.new(a, b, c)
	local cf = { _p = Vector3.new(0, 0, 0), _r = 0 }
	if ehVector3(a) then
		cf._p = a
		if ehVector3(b) then
			local dx, dy = b.x - a.x, b.y - a.y
			if dx ~= 0 or dy ~= 0 then cf._r = math.atan2(dy, dx) end
		end
	else
		cf._p = Vector3.new(a, b, c)
	end
	return setmetatable(cf, CFrameMT)
end
function CFrame.Angles(rx, ry, rz)
	local r = rz or 0
	if r == 0 and ry and ry ~= 0 then r = ry end
	if r == 0 and rx and rx ~= 0 then r = rx end
	return setmetatable({ _p = Vector3.new(0, 0, 0), _r = r }, CFrameMT)
end
function CFrame.lookAt(a, b) return CFrame.new(a, b) end
CFrame.identity = CFrame.new(0, 0, 0)
CFrameMT.__index = function(cf, k)
	if k == "Position" or k == "p" then return cf._p end
	if k == "Rotation" then return setmetatable({ _p = Vector3.new(0, 0, 0), _r = cf._r }, CFrameMT) end
	if k == "X" then return cf._p.x end
	if k == "Y" then return cf._p.y end
	if k == "Z" then return cf._p.z end
	return rawget(CFrameMT, k)
end
CFrameMT.__mul = function(a, b)
	if getmetatable(a) == CFrameMT and getmetatable(b) == CFrameMT then
		return setmetatable({ _p = a._p + b._p, _r = a._r + b._r }, CFrameMT)
	elseif getmetatable(a) == CFrameMT and ehVector3(b) then
		local c, s = math.cos(a._r), math.sin(a._r)
		return Vector3.new(a._p.x + b.x * c - b.y * s, a._p.y + b.x * s + b.y * c, a._p.z + b.z)
	end
	return a
end
CFrameMT.__add = function(a, b) return setmetatable({ _p = a._p + b, _r = a._r }, CFrameMT) end
CFrameMT.__sub = function(a, b) return setmetatable({ _p = a._p - b, _r = a._r }, CFrameMT) end
function CFrameMT:Lerp(o, a)
	return setmetatable({ _p = self._p:Lerp(o._p, a), _r = self._r + (o._r - self._r) * a }, CFrameMT)
end
function CFrameMT:ToWorldSpace(o) return self * o end
local function ehCFrame(v) return type(v) == "table" and getmetatable(v) == CFrameMT end

-- ---- Enum ----

local Enum = setmetatable({}, {
	__index = function(t, tipo)
		local cache = {}
		local tt = setmetatable({}, {
			__index = function(_, nome)
				local item = rawget(cache, nome)
				if not item then
					item = { Name = nome, EnumType = tipo, Value = 0 }
					rawset(cache, nome, item)
				end
				return item
			end,
		})
		rawset(t, tipo, tt)
		return tt
	end,
})

-- ---- classes de instancia ----

local EVENTOS = {
	Touched = true, TouchEnded = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
	MouseButton2Click = true, MouseEnter = true, MouseLeave = true, Changed = true, Activated = true,
	InputBegan = true, InputEnded = true, InputChanged = true, Died = true, ChildAdded = true,
	ChildRemoved = true, DescendantAdded = true, Heartbeat = true, RenderStepped = true, Stepped = true,
	PlayerAdded = true, CharacterAdded = true, Equipped = true, Unequipped = true,
}

local GUI_CLASSES = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true,
	CanvasGroup = true, ScrollingFrame = true, ViewportFrame = true, VideoFrame = true, LayerCollector = true,
}
local LAYER_CLASSES = { ScreenGui = true, BillboardGui = true, SurfaceGui = true }
local PART_CLASSES = { Part = true, Ball = true, Cylinder = true, Wedge = true, WedgePart = true, MeshPart = true, TrussPart = true, CornerWedgePart = true, SpawnLocation = true }
local CONTAINER_CLASSES = { Model = true, Folder = true, WorldRoot = true, Workspace = true, Players = true, Player = true, PlayerGui = true, SoundService = true, ReplicatedStorage = true, ServerStorage = true, ServerScriptService = true, Lighting = true, Debris = true, HumanoidModel = true }

local function ehParte(c) return PART_CLASSES[c] == true end
local function ehGui(c) return GUI_CLASSES[c] == true end
local function ehLayer(c) return LAYER_CLASSES[c] == true end

local ANCESTRAIS = {
	Part = { "BasePart", "PVInstance" }, Ball = { "BasePart", "PVInstance" }, Cylinder = { "BasePart", "PVInstance" },
	Wedge = { "BasePart", "PVInstance" }, WedgePart = { "BasePart", "PVInstance" }, MeshPart = { "BasePart", "PVInstance" },
	TrussPart = { "BasePart", "PVInstance" }, CornerWedgePart = { "BasePart", "PVInstance" }, SpawnLocation = { "BasePart", "PVInstance" },
	Frame = { "GuiObject", "GuiBase2d" }, TextLabel = { "GuiObject", "GuiBase2d" }, TextButton = { "GuiObject", "GuiBase2d" },
	TextBox = { "GuiObject", "GuiBase2d" }, ImageLabel = { "GuiObject", "GuiBase2d" }, ImageButton = { "GuiObject", "GuiBase2d" },
	CanvasGroup = { "GuiObject", "GuiBase2d" }, ScrollingFrame = { "GuiObject", "GuiBase2d" }, ViewportFrame = { "GuiObject", "GuiBase2d" },
	VideoFrame = { "GuiObject", "GuiBase2d" }, ScreenGui = { "LayerCollector", "GuiBase2d" },
	BillboardGui = { "LayerCollector", "GuiBase2d" }, SurfaceGui = { "LayerCollector", "GuiBase2d" },
	Model = { "PVInstance" }, SpawnLocation = { "BasePart", "PVInstance" },
}

local InstMT
local methods = {}

local function ehGuiObj(o) return o._id ~= nil and ehGui(o._className) and not ehLayer(o._className) end

local function visEfetivo(o)
	if o._props.Visible == false then return false end
	local p = o._parent
	while p do
		if p._props.Visible == false then return false end
		if ehLayer(p._className) and p._props.Enabled == false then return false end
		p = p._parent
	end
	return true
end

local function px(u, base)
	if not u then return 0 end
	return (u.Scale or 0) * base + (u.Offset or 0)
end

local function viewW() return (Y2D.largura and Y2D.largura()) or 800 end
local function viewH() return (Y2D.altura and Y2D.altura()) or 600 end

local function guiBox(o)
	local p = o._parent
	local bx, by, bw, bh
	if p and ehGuiObj(p) then
		bx, by, bw, bh = guiBox(p)
	else
		bx, by, bw, bh = 0, 0, viewW(), viewH()
	end
	local pos = o._props.Position or UDim2.new()
	local size = o._props.Size or UDim2.fromOffset(100, 40)
	local ax = bx + px(pos.X, bw)
	local ay = by + px(pos.Y, bh)
	local aw = px(size.X, bw)
	local ah = px(size.Y, bh)
	return ax, ay, aw, ah
end

local function syncParte(o)
	if not o._id then return end
	local pos = o._props.Position or Vector3.new(0, 0, 0)
	local size = o._props.Size or Vector3.new(4, 1, 2)
	local rot = o._props.Rotation
	if ehVector3(rot) then rot = rot.z end
	op("espaco", o._id, "mundo")
	op("pos", o._id, pos.x - size.x / 2, pos.y - size.y / 2)
	op("tam", o._id, size.x, size.y)
	local sh = o._props.Shape
	if sh and (sh.Name == "Ball" or sh.Name == "Cylinder") then op("forma", o._id, "circ") else op("forma", o._id, "ret") end
	op("rot", o._id, rot or 0)
	op("nome", o._id, tostring(o._props.Name or o._className))
	local c = o._props.Color
	if c then op("cor", o._id, c.r, c.g, c.b, 1 - (o._props.Transparency or 0)) end
	op("estatico", o._id, o._props.Anchored and true or false)
	op("sem_colisao", o._id, not (o._props.CanCollide ~= false))
	op("visivel", o._id, visEfetivo(o))
end

local function syncGui(o)
	if not o._id then return end
	local ax, ay, aw, ah = guiBox(o)
	op("espaco", o._id, "tela")
	op("pos", o._id, ax, ay)
	op("tam", o._id, aw, ah)
	op("nome", o._id, tostring(o._props.Name or o._className))
	local bg = o._props.BackgroundColor3
	if bg then op("cor", o._id, bg.r, bg.g, bg.b, 1 - (o._props.BackgroundTransparency or 0)) end
	if o._props.Text ~= nil then op("rotulo", o._id, tostring(o._props.Text), o._props.TextSize or 18) end
	local tc = o._props.TextColor3
	if tc then op("corTexto", o._id, tc.r, tc.g, tc.b, 1 - (o._props.TextTransparency or 0)) end
	op("visivel", o._id, visEfetivo(o))
	op("z", o._id, o._props.ZIndex or 1)
end

local function sync(o)
	if ehParte(o._className) then syncParte(o)
	elseif ehGuiObj(o) then syncGui(o) end
end

function methods.Destroy(o)
	for i = #(o._children or {}), 1, -1 do methods.Destroy(o._children[i]) end
	if o._id then op("remover", o._id) end
	o._id = nil
	o._morto = true
	for i = #partes, 1, -1 do if partes[i] == o then table.remove(partes, i) end end
	for i = #guiObjs, 1, -1 do if guiObjs[i] == o then table.remove(guiObjs, i) end end
	if o._parent then
		for i = #o._parent._children, 1, -1 do if o._parent._children[i] == o then table.remove(o._parent._children, i) end end
	end
	o._parent = nil
end

function methods.IsA(o, classe)
	if classe == "Instance" then return true end
	if classe == o._className then return true end
	local anc = ANCESTRAIS[o._className]
	if anc then for _, a in ipairs(anc) do if a == classe then return true end end end
	if classe == "PVInstance" and (ehParte(o._className) or o._className == "Model") then return true end
	if classe == "GuiBase2d" and (ehGui(o._className) or ehLayer(o._className)) then return true end
	if classe == "GuiObject" and ehGui(o._className) then return true end
	if classe == "BasePart" and ehParte(o._className) then return true end
	if classe == "LayerCollector" and ehLayer(o._className) then return true end
	return false
end

function methods.FindFirstChild(o, nome)
	for _, c in ipairs(o._children or {}) do if c._props and c._props.Name == nome then return c end end
	return nil
end
function methods.FindFirstChildOfClass(o, classe)
	for _, c in ipairs(o._children or {}) do if c._className == classe then return c end end
	return nil
end
function methods.FindFirstAncestorOfClass(o, classe)
	local p = o._parent
	while p do
		if p._className == classe then return p end
		p = p._parent
	end
	return nil
end
function methods.FindFirstAncestor(o, nome)
	local p = o._parent
	while p do
		if p._props and p._props.Name == nome then return p end
		p = p._parent
	end
	return nil
end
function methods.GetChildren(o)
	local c = {}
	for i, v in ipairs(o._children or {}) do c[i] = v end
	return c
end
function methods.GetDescendants(o)
	local c = {}
	local function rec(n) for _, v in ipairs(n._children or {}) do table.insert(c, v); rec(v) end end
	rec(o)
	return c
end
function methods.WaitForChild(o, nome) return methods.FindFirstChild(o, nome) end
function methods.Clone(o) return o end
function methods.GetAttribute(o, k) return o._props[k] end
function methods.SetAttribute(o, k, v) o._props[k] = v end
function methods.GetPivot(o)
	local pos = o._props.Position
	if ehVector3(pos) then
		local rot = o._props.Rotation
		if ehVector3(rot) then rot = rot.z end
		return CFrame.Angles(0, 0, rad(rot or 0)) + pos
	end
	local ax, ay = guiBox(o)
	return CFrame.new(ax, ay, 0)
end
function methods.PivotTo(o, cf)
	if ehParte(o._className) then
		if ehCFrame(cf) then
			local old = o._props.Size or Vector3.new(4, 1, 2)
			o._props.Position = Vector3.new(cf._p.x, cf._p.y, cf._p.z)
			o._props.CFrame = cf
			syncParte(o)
		end
	elseif ehGuiObj(o) then
		if ehCFrame(cf) then
			o._props.Position = UDim2.fromOffset(cf._p.x, cf._p.y)
			syncGui(o)
		end
	end
end
function methods.SetPrimaryPartCFrame(o, cf) return methods.PivotTo(o, cf) end
function methods.MoveTo(o, v) o._props.Position = v; sync(o) end
function methods.TakeDamage(o, n)
	local h = o._props.Health or 100
	o._props.Health = h - (n or 0)
	local hum = o._props.Humanoid
	if hum then hum:TakeDamage(n) end
end
function methods.BreakJoints(o) end
function methods.MakeJointsVisible(o) end

local function setParent(o, p)
	if o._parent then
		for i = #o._parent._children, 1, -1 do if o._parent._children[i] == o then table.remove(o._parent._children, i) end end
	end
	o._parent = p
	if p then
		p._children = p._children or {}
		table.insert(p._children, o)
		if o._id then sync(o) end
		local function ressinc(n)
			for _, c in ipairs(n._children or {}) do if c._id then sync(c) end; ressinc(c) end
		end
		if o._id then ressinc(o) end
	end
end

local function getChave(o, k)
	if k == "ClassName" then return o._className end
	if k == "Parent" then return o._parent end
	if k == "AbsolutePosition" and ehGuiObj(o) then local ax, ay = guiBox(o); return Vector2.new(ax, ay) end
	if k == "AbsoluteSize" and ehGuiObj(o) then local _, _, aw, ah = guiBox(o); return Vector2.new(aw, ah) end
	if k == "Humanoid" then
		for _, c in ipairs(o._children or {}) do if c._className == "Humanoid" then return c end end
		return nil
	end
	if k == "PrimaryPart" then
		for _, c in ipairs(o._children or {}) do if ehParte(c._className) then return c end end
		return nil
	end
	if k == "CFrame" and ehParte(o._className) then
		local pos = o._props.Position or Vector3.new(0, 0, 0)
		local rot = o._props.Rotation
		if ehVector3(rot) then rot = rot.z end
		return CFrame.Angles(0, 0, rad(rot or 0)) + pos
	end
	if k == "Velocity" or k == "AssemblyLinearVelocity" then return o._props.Velocity or Vector3.new(0, 0, 0) end
	return o._props[k]
end

local function setProp(o, k, v)
	if k == "Parent" then setParent(o, v); return end
	if k == "Name" then o._props.Name = v; if o._id then op("nome", o._id, tostring(v)) end; return end
	if k == "Position" or k == "Orientation" then
		o._props.Position = v
		if k == "Orientation" then o._props.Rotation = v end
		sync(o); return
	end
	if k == "Rotation" then o._props.Rotation = v; o._props.CFrame = nil; sync(o); return end
	if k == "CFrame" then
		if ehCFrame(v) then
			o._props.CFrame = v
			o._props.Position = v._p
			o._props.Rotation = deg(v._r)
			sync(o)
		end
		return
	end
	if k == "Size" then o._props.Size = v; sync(o); return end
	if k == "Color" or k == "Color3" then o._props.Color = v; sync(o); return end
	if k == "BackgroundColor3" then o._props.BackgroundColor3 = v; sync(o); return end
	if k == "TextColor3" then o._props.TextColor3 = v; sync(o); return end
	if k == "Transparency" or k == "BackgroundTransparency" or k == "TextTransparency" or k == "ImageTransparency" then
		o._props[k] = v; sync(o); return
	end
	if k == "Text" or k == "TextSize" or k == "Font" or k == "TextScaled" or k == "TextWrapped" or k == "TextXAlignment" or k == "TextYAlignment" then
		o._props[k] = v
		if o._id and o._props.Text ~= nil then op("rotulo", o._id, tostring(o._props.Text), o._props.TextSize or 18) end
		return
	end
	if k == "Visible" or k == "Enabled" then o._props[k] = v; sync(o); return end
	if k == "Shape" then o._props.Shape = v; sync(o); return end
	if k == "Anchored" then o._props.Anchored = v; sync(o); return end
	if k == "CanCollide" then o._props.CanCollide = v; sync(o); return end
	if k == "ZIndex" or k == "ZIndexBehavior" then o._props.ZIndex = v; sync(o); return end
	if k == "Image" then o._props.Image = v; if o._id then op("forma", o._id, "sprite"); op("imagem", o._id, v) end; return end
	if k == "Velocity" or k == "AssemblyLinearVelocity" then
		o._props.Velocity = v
		if o._id then op("velocidade", o._id, v.x, v.y) end
		return
	end
	if k == "SoundId" then o._props.SoundId = v; return end
	if k == "Volume" or k == "Looped" or k == "Playing" or k == "Pitch" or k == "PlaybackSpeed" then
		o._props[k] = v
		if k == "Playing" and o._className == "Sound" then
			if v then methods.Play(o) else methods.Stop(o) end
		end
		return
	end
	if k == "Material" or k == "Reflectance" or k == "Anchored" or k == "Locked" or k == "CastShadow"
		or k == "TopSurface" or k == "BottomSurface" or k == "LeftSurface" or k == "RightSurface" then
		o._props[k] = v; return
	end
	o._props[k] = v
end

InstMT = {
	__index = function(o, k)
		if methods[k] then return methods[k] end
		if EVENTOS[k] then
			local e = o._events[k]
			if not e then e = evento(); o._events[k] = e end
			return e
		end
		return getChave(o, k)
	end,
	__newindex = function(o, k, v) setProp(o, k, v) end,
}

-- ---- defaults por classe ----

local function def(cls, extra)
	local p = { Name = cls, Transparency = 0, BackgroundTransparency = 0, TextTransparency = 0, Visible = true, Enabled = true, ZIndex = 1 }
	if extra then for k, v in pairs(extra) do p[k] = v end end
	return p
end

local CINZA = Color3.fromRGB(163, 162, 165)
local DEFAULTS = {
	Part = def("Part", { Size = Vector3.new(4, 1, 2), Color = CINZA, Anchored = false, CanCollide = true }),
	Ball = def("Ball", { Size = Vector3.new(2, 2, 2), Color = CINZA, Shape = Enum.PartType.Ball, CanCollide = true }),
	Cylinder = def("Cylinder", { Size = Vector3.new(2, 2, 2), Color = CINZA, Shape = Enum.PartType.Cylinder, CanCollide = true }),
	Wedge = def("Wedge", { Size = Vector3.new(2, 2, 2), Color = CINZA, CanCollide = true }),
	MeshPart = def("MeshPart", { Size = Vector3.new(4, 1, 2), Color = CINZA, CanCollide = true }),
	Frame = def("Frame", { Size = UDim2.fromOffset(100, 100), BackgroundColor3 = Color3.fromRGB(35, 40, 58) }),
	CanvasGroup = def("CanvasGroup", { Size = UDim2.fromOffset(100, 100), BackgroundColor3 = Color3.fromRGB(35, 40, 58) }),
	ScrollingFrame = def("ScrollingFrame", { Size = UDim2.fromOffset(100, 100), BackgroundColor3 = Color3.fromRGB(35, 40, 58) }),
	TextLabel = def("TextLabel", { Size = UDim2.fromOffset(100, 40), BackgroundColor3 = Color3.fromRGB(35, 40, 58), BackgroundTransparency = 1, Text = "", TextSize = 18, TextColor3 = Color3.fromRGB(255, 255, 255) }),
	TextBox = def("TextBox", { Size = UDim2.fromOffset(100, 40), BackgroundColor3 = Color3.fromRGB(35, 40, 58), Text = "", TextSize = 18, TextColor3 = Color3.fromRGB(255, 255, 255) }),
	TextButton = def("TextButton", { Size = UDim2.fromOffset(120, 44), BackgroundColor3 = Color3.fromRGB(46, 52, 74), Text = "", TextSize = 18, TextColor3 = Color3.fromRGB(255, 255, 255) }),
	ImageLabel = def("ImageLabel", { Size = UDim2.fromOffset(100, 100), BackgroundTransparency = 1, Image = "" }),
	ImageButton = def("ImageButton", { Size = UDim2.fromOffset(100, 100), BackgroundTransparency = 1, Image = "" }),
	ScreenGui = def("ScreenGui", { Enabled = true, ResetOnSpawn = false }),
	SurfaceGui = def("SurfaceGui", { Enabled = true }),
	BillboardGui = def("BillboardGui", { Enabled = true }),
	Sound = def("Sound", { Volume = 0.5, Looped = false, Playing = false, SoundId = "" }),
	Camera = def("Camera", { FieldOfView = 70 }),
	Humanoid = def("Humanoid", { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50 }),
	Model = def("Model"),
	Folder = def("Folder"),
	Player = def("Player"),
	PlayerGui = def("PlayerGui"),
	Debris = def("Debris"),
}

local function geraId(o)
	local s = o._props.Size
	local c = o._props.Color or (o._props.BackgroundColor3) or Color3.fromRGB(255, 255, 255)
	local cls = o._className
	if ehParte(cls) then
		local p = o._props.Position or Vector3.new(0, 0, 0)
		o._id = Y2D.criar("ret", p.x - s.x / 2, p.y - s.y / 2, s.x, s.y, c.r, c.g, c.b, 1)
		table.insert(partes, o)
		syncParte(o)
	elseif ehGuiObj(cls) then
		o._id = Y2D.criar("ret", 0, 0, 100, 40, c.r, c.g, c.b, 1 - (o._props.BackgroundTransparency or 0))
		table.insert(guiObjs, o)
		syncGui(o)
	end
end

local function copiaProps(src)
	local p = {}
	for k, v in pairs(src) do p[k] = v end
	return p
end

local function novaInstancia(classe)
	return setmetatable({ _props = copiaProps(DEFAULTS[classe] or def(classe)), _children = {}, _events = {}, _className = classe }, InstMT)
end

local Instance = {}
function Instance.new(classe, parent)
	local o = novaInstancia(classe)
	geraId(o)
	if parent then setParent(o, parent) end
	return o
end

-- ---- services ----

local workspace = setmetatable({ _props = { Name = "Workspace" }, _children = {}, _events = {}, _className = "Workspace" }, InstMT)

local players = setmetatable({ _props = { Name = "Players" }, _children = {}, _events = {}, _className = "Players" }, InstMT)
local localPlayer = setmetatable({ _props = { Name = "LocalPlayer" }, _children = {}, _events = {}, _className = "Player" }, InstMT)
local playerGui = setmetatable({ _props = { Name = "PlayerGui" }, _children = {}, _events = {}, _className = "PlayerGui" }, InstMT)
localPlayer._children = { playerGui }
playerGui._parent = localPlayer
players.LocalPlayer = localPlayer
players.PlayerAdded = evento()

local camera = novaInstancia("Camera")
workspace.CurrentCamera = camera
workspace._children = { camera }

local runService = setmetatable({ _className = "RunService", _props = { Name = "RunService" }, _children = {}, _events = {} }, InstMT)
runService.Heartbeat = evento()
runService.RenderStepped = evento()
runService.Stepped = evento()
runService.PreRender = runService.RenderStepped

local userInput = setmetatable({ _className = "UserInputService", _props = { Name = "UserInputService" }, _children = {}, _events = {} }, InstMT)
userInput.InputBegan = evento()
userInput.InputEnded = evento()
userInput.InputChanged = evento()
userInput.TouchStarted = userInput.InputBegan

local EasingStyle = { Linear = true, Quad = true, Sine = true, Back = true, Bounce = true, Elastic = true, Cubic = true, Quart = true, Quint = true }

local TweenService = setmetatable({ _className = "TweenService" }, { __index = {} })
function TweenService.Create(_, obj, info, props)
	local t = { obj = obj, props = props, info = info, dur = (info and info.Time) or 0.3, tempo = 0, iniciais = {} }
	for k, v in pairs(props) do t.iniciais[k] = obj[k] end
	local tw = {}
	function tw:Play() table.insert(tweens, t); return tw end
	function tw:Cancel() for i = #tweens, 1, -1 do if tweens[i] == t then table.remove(tweens, i) end end end
	function tw:Pause() tw._pausado = true end
	return tw
end

local TweenInfo = {}
function TweenInfo.new(tempo, estilo, direcao) return { Time = tempo or 1, EasingStyle = estilo or Enum.EasingStyle.Linear, EasingDirection = direcao } end

local ReplicatedStorage = setmetatable({ _children = {}, _props = { Name = "ReplicatedStorage" }, _events = {}, _className = "ReplicatedStorage" }, InstMT)
function ReplicatedStorage:WaitForChild(nome)
	local c = methods.FindFirstChild(self, nome)
	if c then return c end
	local f = novaInstancia("Folder"); f._props.Name = nome; setParent(f, self); return f
end

local SoundService = setmetatable({ _children = {}, _props = { Name = "SoundService" }, _events = {}, _className = "SoundService" }, InstMT)
local Lighting = setmetatable({ _children = {}, _props = { Name = "Lighting" }, _events = {}, _className = "Lighting" }, InstMT)

local Debris = setmetatable({ _className = "Debris" }, { __index = {} })
function Debris.AddItem(_, item, tempo)
	delay(tempo or 5, function() methods.Destroy(item) end)
end

local services = {
	Workspace = workspace, Players = players, RunService = runService, UserInputService = userInput,
	TweenService = TweenService, ReplicatedStorage = ReplicatedStorage, SoundService = SoundService,
	Lighting = Lighting, Debris = Debris,
}

local game = setmetatable({ _className = "DataModel", _props = {}, _events = {} }, { __index = function(_, k) return services[k] end })
function game:GetService(nome)
	if services[nome] then return services[nome] end
	local s = setmetatable({ _props = { Name = nome }, _children = {}, _events = {}, _className = nome }, InstMT)
	services[nome] = s
	return s
end

-- ---- som ----

local function idSom(s)
	local n = tostring(s or ""):match("(%d+)%s*$")
	return n or s
end

function methods.Play(o)
	o._props.Playing = true
	o._somId = op("tocar", idSom(o._props.SoundId), o._props.Volume or 0.5, o._props.Looped and true or false)
end
function methods.Stop(o)
	o._props.Playing = false
	if o._somId then op("parar_som", o._somId) end
end
function methods.Pause(o) methods.Stop(o) end
function methods.Resume(o) methods.Play(o) end

-- ---- interpolacao ----

local function suavizar(t, estilo)
	if estilo == Enum.EasingStyle.Sine then return math.sin(t * math.pi / 2) end
	if estilo == Enum.EasingStyle.Quad then return t * t end
	if estilo == Enum.EasingStyle.Cubic then return t * t * t end
	if estilo == Enum.EasingStyle.Quart then return t * t * t * t end
	if estilo == Enum.EasingStyle.Quint then return t * t * t * t * t end
	if estilo == Enum.EasingStyle.Back then local c = 1.70158; return t * t * ((c + 1) * t - c) end
	if estilo == Enum.EasingStyle.Bounce then return 1 - (1 - t) * (1 - t) end
	if estilo == Enum.EasingStyle.Elastic then return t == 0 and 0 or (t == 1 and 1 or 1 - 2 ^ (-10 * t) * math.cos(t * 20)) end
	return t
end

local function lerp(a, b, t) return a + (b - a) * t end

local function interpolar(ini, alvo, e)
	if ehVector3(ini) and ehVector3(alvo) then return Vector3.new(lerp(ini.x, alvo.x, e), lerp(ini.y, alvo.y, e), lerp(ini.z, alvo.z, e)) end
	if ehColor3(ini) and ehColor3(alvo) then return Color3.new(lerp(ini.r, alvo.r, e), lerp(ini.g, alvo.g, e), lerp(ini.b, alvo.b, e)) end
	if ehUDim2(ini) and ehUDim2(alvo) then return ini:Lerp(alvo, e) end
	if ehCFrame(ini) and ehCFrame(alvo) then return ini:Lerp(alvo, e) end
	if type(ini) == "number" and type(alvo) == "number" then return lerp(ini, alvo, e) end
	return nil
end

local function passoTw(dt)
	for i = #tweens, 1, -1 do
		local tw = tweens[i]
		if tw._pausado then
			table.remove(tweens, i)
		else
			tw.tempo = tw.tempo + dt
			local k = tw.dur > 0 and math.min(1, tw.tempo / tw.dur) or 1
			local e = suavizar(k, (tw.info and tw.info.EasingStyle) or Enum.EasingStyle.Linear)
			for prop, alvo in pairs(tw.props) do
				local ini = tw.iniciais[prop]
				local v = interpolar(ini, alvo, e)
				if v ~= nil then tw.obj[prop] = v elseif k >= 1 then tw.obj[prop] = alvo end
			end
			if k >= 1 then table.remove(tweens, i) end
		end
	end
end

-- ---- toque ----

local function caixa(o)
	local pa, sa = o._props.Position, o._props.Size
	if not (ehVector3(pa) and ehVector3(sa)) then return nil end
	return pa.x - sa.x / 2, pa.y - sa.y / 2, sa.x, sa.y
end

local function overlap(a, b)
	local ax, ay, aw, ah = caixa(a)
	local bx, by, bw, bh = caixa(b)
	if not (ax and bx) then return false end
	return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function passoToque()
	local novos = {}
	for i = 1, #partes do
		local a = partes[i]
		if not a._morto then
			for j = i + 1, #partes do
				local b = partes[j]
				if not b._morto and overlap(a, b) then
					local chave = tostring(a) .. ":" .. tostring(b)
					novos[chave] = true
					if not overlaps[chave] then
						local ea, eb = a._events.Touched, b._events.Touched
						if ea then ea:disparar(b) end
						if eb then eb:disparar(a) end
					end
				end
			end
		end
	end
	overlaps = novos
end

-- ---- loop ----

local function passo(dt)
	clock = clock + dt
	local prontos = {}
	for i = #threads, 1, -1 do
		local th = threads[i]
		table.remove(threads, i)
		if th.wake <= clock then table.insert(prontos, th) else table.insert(threads, th) end
	end
	for _, th in ipairs(prontos) do
		if coroutine.status(th.co) ~= "dead" then
			local ok, r
			if th.args then
				ok, r = coroutine.resume(th.co, table.unpack(th.args, 1, th.args.n))
				th.args = nil
			else
				ok, r = coroutine.resume(th.co)
			end
			if ok then
				if r and r.espera then
					th.wake = clock + r.espera
					table.insert(threads, th)
				elseif coroutine.status(th.co) ~= "dead" then
					th.wake = clock
					table.insert(threads, th)
				end
			else
				op("imprimir", "Erro no script: " .. tostring(r))
			end
		end
	end
	runService.Heartbeat:disparar(dt)
	runService.RenderStepped:disparar(dt)
	runService.Stepped:disparar(dt)
	passoTw(dt)
	passoToque()
end

-- ---- input ----

local function hitGui(x, y)
	local ordenado = {}
	for i, o in ipairs(guiObjs) do if not o._morto then ordenado[i] = o end end
	table.sort(ordenado, function(a, b) return (a._props.ZIndex or 1) < (b._props.ZIndex or 1) end)
	for i = #ordenado, 1, -1 do
		local o = ordenado[i]
		local ax, ay, aw, ah = guiBox(o)
		if visEfetivo(o) and x >= ax and x <= ax + aw and y >= ay and y <= ay + ah then return o end
	end
	return nil
end

local function atualizarMouse(x, y)
	ponteiroX, ponteiroY = x, y
	local alvo = hitGui(x, y)
	if alvo ~= ponteiroUltimo then
		if ponteiroUltimo and ponteiroUltimo._events.MouseLeave then ponteiroUltimo._events.MouseLeave:disparar() end
		if alvo and alvo._events.MouseEnter then alvo._events.MouseEnter:disparar() end
		ponteiroUltimo = alvo
	end
end

local function apertarMouse(x, y, esquerdo)
	atualizarMouse(x, y)
	local alvo = hitGui(x, y)
	if alvo then
		local ev = esquerdo ~= false and alvo._events.MouseButton1Down or alvo._events.MouseButton2Down
		if ev then ev:disparar() end
	end
end

local function soltarMouse(x, y, esquerdo)
	local alvo = hitGui(x, y)
	if alvo then
		local ev = esquerdo ~= false and alvo._events.MouseButton1Click or alvo._events.MouseButton2Click
		if ev then ev:disparar() end
	end
end

-- ---- instalacao ----

local V3 = Vector3
local function vetor3(x, y, z) return V3.new(x, y, z) end

function Runtime2D.instalar()
	_G.game = game
	_G.workspace = workspace
	_G.Workspace = workspace
	_G.Instance = Instance
	_G.Vector3 = Vector3
	_G.Vector2 = Vector2
	_G.Color3 = Color3
	_G.UDim = UDim
	_G.UDim2 = UDim2
	_G.CFrame = CFrame
	_G.Enum = Enum
	_G.task = task
	_G.wait = wait
	_G.spawn = spawn
	_G.delay = delay
	_G.TweenInfo = TweenInfo
	_G.game = game
	_G.print = function(...)
		local t = {}
		for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
		op("imprimir", table.concat(t, " "))
	end
	_G.warn = _G.print
	_G.os.clock = agora
	_G.os.time = function() return math.floor(clock) end
end

function Runtime2D.rodar(codigo)
	local chunk, err = (loadstring or load)(codigo)
	if not chunk then return false, err end
	novoThread(chunk)
	return true
end

function Runtime2D.passo(dt) passo(dt) end

function Runtime2D.tecla(nome, baixo)
	local ev = baixo and userInput.InputBegan or userInput.InputEnded
	ev:disparar({ KeyCode = Enum.KeyCode[nome], UserInputType = Enum.UserInputType.Keyboard })
end

function Runtime2D.mouse(x, y) atualizarMouse(x, y) end
function Runtime2D.mover(x, y) atualizarMouse(x, y) end
function Runtime2D.botao(x, y, baixo, esquerdo) if baixo then apertarMouse(x, y, esquerdo) else soltarMouse(x, y, esquerdo) end end
function Runtime2D.roda(x, y, delta) end
function Runtime2D.toque(x, y, estado) if estado == "inicio" then apertarMouse(x, y, true) else soltarMouse(x, y, true) end end

function Runtime2D.limpar()
	threads = {}
	tweens = {}
	partes = {}
	guiObjs = {}
	overlaps = {}
	for _, o in ipairs(workspace._children or {}) do if o ~= camera then methods.Destroy(o) end end
	workspace._children = { camera }
	for _, o in ipairs(playerGui._children or {}) do methods.Destroy(o) end
	playerGui._children = {}
	runService.Heartbeat = evento()
	runService.RenderStepped = evento()
	runService.Stepped = evento()
	userInput.InputBegan = evento()
	userInput.InputEnded = evento()
end

return Runtime2D
