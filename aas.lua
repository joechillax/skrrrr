-- JoesAAS 5.12 | standalone source | October 2026
-- Built against the supplied client export. See JoesAAS-README.md for limits and validation.
-- Fluent UI from dawid-scripts/Fluent. Settings save and restore automatically; each feature uses its own toggle.
local environment = (type(getgenv) == "function" and getgenv()) or _G
local previous = environment.JoesAAS or environment.AnimeSuite
if previous and type(previous.stop) == "function" then pcall(previous.stop) end
if game.GameId ~= 10502841145 then
    warn("JoesAAS: this build targets the exported game's universe, not this experience.")
    return
end
local A = {version="5.12"}
environment.JoesAAS = A
environment.AnimeSuite = A -- Compatibility with older running versions.
A.Core = (function()
local Core = {}
Core.defaultPriority={'MaxTac','Tower','TimeTrial','Dungeon','Gate','Combat','BossRush'}
Core.priorityLabels={MaxTac='MaxTac',Tower='Tower',TimeTrial='Time Trials',Dungeon='Dungeon',Gate='Gate',Combat='Raid / Defense',BossRush='Boss Rush'}
function Core.copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}; for k,v in pairs(t) do out[k] = Core.copy(v) end; return out
end
function Core.keys(t)
    local out = {}; for k in pairs(t or {}) do out[#out+1] = k end
    table.sort(out, function(a,b) return tostring(a)<tostring(b) end); return out
end
function Core.contains(list, value)
    for _,v in ipairs(list or {}) do if tostring(v)==tostring(value) then return true end end
    return false
end
function Core.trueKeys(values)
    local result={}
    for key,value in pairs(type(values)=='table' and values or {}) do
        if type(key)=='string' and value==true then result[key]=true end
    end
    return result
end
function Core.clipBytes(text,limit)
    text=tostring(text); local n=math.min(#text,limit)
    while n>0 and n<#text do
        local b=text:byte(n+1)
        if b<128 or b>191 then break end
        n=n-1
    end
    return text:sub(1,n)
end
function Core.merge(defaults, saved)
    local result = Core.copy(defaults)
    if type(saved)~='table' then return result end
    for k,v in pairs(defaults) do
        if type(saved[k])==type(v) then
            if type(v)=='table' then result[k]=Core.copy(saved[k]) else result[k]=saved[k] end
        end
    end
    return result
end
function Core.singleSelection(selection)
    local result={}
    for _,key in ipairs(Core.keys(selection)) do
        if type(key)=='string' and selection[key]==true then result[key]=true; break end
    end
    return result
end
function Core.equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not Core.equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function Core.priorityOrder(saved)
    local result,seen={},{}
    for _,key in ipairs(type(saved)=='table' and saved or {}) do
        if Core.priorityLabels[key] and not seen[key] then result[#result+1]=key; seen[key]=true end
    end
    for _,key in ipairs(Core.defaultPriority) do if not seen[key] then result[#result+1]=key end end
    return result
end
function Core.portalMode(key,cfg)
    if cfg and cfg.GateOnly~=true then return nil end
    if tostring(key):lower():find('maxtac',1,true)
        or (cfg and (tostring(cfg.AchievementModeKey):find('^MaxTacCall') or tostring(cfg.Name):lower():find('maxtac',1,true))) then return 'MaxTac' end
    return 'Gate'
end
function Core.renameEligible(id,pet,named,petStats)
    if type(id)~='string' or type(pet)~='table' then return false,'unexpected inventory format' end
    if not petStats or type(petStats.GetRarity)~='function' then return false,'rarity API missing' end
    local rarity=petStats.GetRarity(pet)
    if rarity~='Astral' then return false,'not Astral',rarity end
    -- Match NamedStateUtil.IsNamed: only a table is a naming record.
    if type(named)=='table' and type(named[id])=='table' then return false,'existing named record',rarity end
    -- Pet.Name is catalog data; the game stores custom names in NamedPets.
    if petStats and petStats.IsDynamicById and petStats.IsDynamicById(pet.PetId) then return false,'percentage pet',rarity end
    return true,'eligible',rarity
end
function Core.activityKeys(choices,mode)
    local keys=Core.keys(choices)
    local function trialRank(key)
        local label=(tostring(key)..' '..tostring(choices[key].Name or '')):lower()
        for rank,name in ipairs({'insane','hard','medium','easy'}) do
            if label:find('%f[%a]'..name..'%f[%A]') then return rank end
        end
        return 5
    end
    table.sort(keys,function(a,b)
        local x,y
        if mode=='TimeTrial' then x,y=trialRank(a),trialRank(b)
        else x,y=tonumber(choices[a].WorldId) or math.huge,tonumber(choices[b].WorldId) or math.huge end
        if x~=y then return x<y end
        local an,bn=tostring(choices[a].Name or a),tostring(choices[b].Name or b)
        if an~=bn then return an<bn end
        return tostring(a)<tostring(b)
    end)
    return keys
end
function Core.chooseTarget(items,mode)
    table.sort(items,function(a,b)
        if mode=='Highest HP' and a.health~=b.health then return a.health>b.health end
        if mode=='Lowest HP' and a.health~=b.health then return a.health<b.health end
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.id<b.id
    end)
    return items[1]
end
function Core.webhookRetry(status,headers,body,attempt)
    if status>=200 and status<300 then return 'done',0 end
    if status==429 then
        local delay=tonumber(body and body.retry_after)
        for k,v in pairs(headers or {}) do
            if tostring(k):lower()=='retry-after' then delay=tonumber(v) or delay end
        end
        return 'retry',math.max(1,delay or 5)
    end
    if status==0 or status>=500 then return 'retry',math.min(120,2^attempt) end
    return 'stop',0
end
return Core

end)()
A.fluentSource = [====[
--[[
    Fluent Interface Suite
    This script is not intended to be modified.
    To view the source code, see the 'src' folder on GitHub!

    Author: dawid
    License: MIT
    GitHub: https://github.com/dawid-scripts/Fluent
--]]

local a,b={{1,'ModuleScript',{'MainModule'},{{18,'ModuleScript',{'Creator'}},{28,'ModuleScript',{'Icons'}},{47,'ModuleScript',{'Themes'},{{50,'ModuleScript',{'Dark'}},{52,'ModuleScript',{'Light'}},{51,'ModuleScript',{'Darker'}},{53,'ModuleScript',{'Rose'}},{49,'ModuleScript',{'Aqua'}},{48,'ModuleScript',{'Amethyst'}}}},{19,'ModuleScript',{'Elements'},{{21,'ModuleScript',{'Colorpicker'}},{27,'ModuleScript',{'Toggle'}},{23,'ModuleScript',{'Input'}},{20,'ModuleScript',{'Button'}},{25,'ModuleScript',{'Paragraph'}},{22,'ModuleScript',{'Dropdown'}},{26,'ModuleScript',{'Slider'}},{24,'ModuleScript',{'Keybind'}}}},{29,'Folder',{'Packages'},{{30,'ModuleScript',{'Flipper'},{{33,'ModuleScript',{'GroupMotor'}},{46,'ModuleScript',{'isMotor.spec'}},{39,'ModuleScript',{'Signal'}},{40,'ModuleScript',{'Signal.spec'}},{45,'ModuleScript',{'isMotor'}},{36,'ModuleScript',{'Instant.spec'}},{44,'ModuleScript',{'Spring.spec'}},{42,'ModuleScript',{'SingleMotor.spec'}},{38,'ModuleScript',{'Linear.spec'}},{31,'ModuleScript',{'BaseMotor'}},{43,'ModuleScript',{'Spring'}},{35,'ModuleScript',{'Instant'}},{37,'ModuleScript',{'Linear'}},{41,'ModuleScript',{'SingleMotor'}},{34,'ModuleScript',{'GroupMotor.spec'}},{32,'ModuleScript',{'BaseMotor.spec'}}}}}},{2,'ModuleScript',{'Acrylic'},{{3,'ModuleScript',{'AcrylicBlur'}},{5,'ModuleScript',{'CreateAcrylic'}},{6,'ModuleScript',{'Utils'}},{4,'ModuleScript',{'AcrylicPaint'}}}},{7,'Folder',{'Components'},{{9,'ModuleScript',{'Button'}},{12,'ModuleScript',{'Notification'}},{13,'ModuleScript',{'Section'}},{17,'ModuleScript',{'Window'}},{14,'ModuleScript',{'Tab'}},{10,'ModuleScript',{'Dialog'}},{8,'ModuleScript',{'Assets'}},{16,'ModuleScript',{'TitleBar'}},{15,'ModuleScript',{'Textbox'}},{11,'ModuleScript',{'Element'}}}}}}}local aa={function()local c,d,e,f,g=b(1)local h,i,j,k,l,m=game:GetService'Lighting',game:GetService'RunService',game:GetService'Players'.LocalPlayer,game:GetService'UserInputService',game:GetService'TweenService',game:GetService'Workspace'.CurrentCamera local n,o=j:GetMouse(),d local p,q,r,s=e(o.Creator),e(o.Elements),e(o.Acrylic),o.Components local t,u,v=e(s.Notification),p.New,protectgui or(syn and syn.protect_gui)or function()end local w=u('ScreenGui',{Parent=i:IsStudio()and j.PlayerGui or game:GetService'CoreGui'})v(w)t:Init(w)local x={Version='1.1.0',OpenFrames={},Options={},Themes=e(o.Themes).Names,Window=nil,WindowFrame=nil,Unloaded=false,Theme='Dark',DialogOpen=false,UseAcrylic=false,Acrylic=false,Transparency=true,MinimizeKeybind=nil,MinimizeKey=Enum.KeyCode.LeftControl,GUI=w}function x.SafeCallback(y,z,...)if not z then return end local A,B=pcall(z,...)if not A then local C,D=B:find':%d+: 'if not D then return x:Notify{Title='Interface',Content='Callback error',SubContent=B,Duration=5}end return x:Notify{Title='Interface',Content='Callback error',SubContent=B:sub(D+1),Duration=5}end end function x.Round(y,z,A)if A==0 then return math.floor(z)end z=tostring(z)return z:find'%.'and tonumber(z:sub(1,z:find'%.'+A))or z end local y=e(o.Icons).assets function x.GetIcon(z,A)if A~=nil and y['lucide-'..A]then return y['lucide-'..A]end return nil end local z={}z.__index=z z.__namecall=function(A,B,...)return z[B](...)end for A,B in ipairs(q)do z['Add'..B.__type]=function(C,D,E)B.Container=C.Container B.Type=C.Type B.ScrollFrame=C.ScrollFrame B.Library=x return B:New(D,E)end end x.Elements=z function x.CreateWindow(C,D)assert(D.Title,'Window - Missing Title')if x.Window then print'You cannot create more than one window.'return end x.MinimizeKey=D.MinimizeKey x.UseAcrylic=D.Acrylic if D.Acrylic then r.init()end local E=e(s.Window){Parent=w,Size=D.Size,Title=D.Title,SubTitle=D.SubTitle,TabWidth=D.TabWidth}x.Window=E x:SetTheme(D.Theme)return E end function x.SetTheme(C,D)if x.Window and table.find(x.Themes,D)then x.Theme=D p.UpdateTheme()end end function x.Destroy(C)if x.Window then x.Unloaded=true if x.UseAcrylic then x.Window.AcrylicPaint.Model:Destroy()end p.Disconnect()x.GUI:Destroy()end end function x.ToggleAcrylic(C,D)if x.Window then if x.UseAcrylic then x.Acrylic=D x.Window.AcrylicPaint.Model.Transparency=D and 0.98 or 1 if D then r.Enable()else r.Disable()end end end end function x.ToggleTransparency(C,D)if x.Window then x.Window.AcrylicPaint.Frame.Background.BackgroundTransparency=D and 0.35 or 0 end end function x.Notify(C,D)return t:New(D)end if getgenv then getgenv().Fluent=x end return x end,function()local c,d,e,f,g=b(2)local h={AcrylicBlur=e(d.AcrylicBlur),CreateAcrylic=e(d.CreateAcrylic),AcrylicPaint=e(d.AcrylicPaint)}function h.init()local i=Instance.new'DepthOfFieldEffect'i.FarIntensity=0 i.InFocusRadius=0.1 i.NearIntensity=1 local j={}function h.Enable()for k,l in pairs(j)do l.Enabled=false end i.Parent=game:GetService'Lighting'end function h.Disable()for k,l in pairs(j)do l.Enabled=l.enabled end i.Parent=nil end local k=function()local k=function(k)if k:IsA'DepthOfFieldEffect'then j[k]={enabled=k.Enabled}end end for l,m in pairs(game:GetService'Lighting':GetChildren())do k(m)end if game:GetService'Workspace'.CurrentCamera then for n,o in pairs(game:GetService'Workspace'.CurrentCamera:GetChildren())do k(o)end end end k()h.Enable()end return h end,function()local c,d,e,f,g=b(3)local h,i,j,k=e(d.Parent.Parent.Creator),e(d.Parent.CreateAcrylic),unpack(e(d.Parent.Utils))local l=function(l)local m={}l=l or 0.001 local n,o={topLeft=Vector2.new(),topRight=Vector2.new(),bottomRight=Vector2.new()},i()o.Parent=workspace local p,q=function(p,q)n.topLeft=q n.topRight=q+Vector2.new(p.X,0)n.bottomRight=q+p end,function()local p=game:GetService'Workspace'.CurrentCamera if p then p=p.CFrame end local q=p if not q then q=CFrame.new()end local r,s,t,u=q,n.topLeft,n.topRight,n.bottomRight local v,w,x=j(s,l),j(t,l),j(u,l)local y,z=(w-v).Magnitude,(w-x).Magnitude o.CFrame=CFrame.fromMatrix((v+x)/2,r.XVector,r.YVector,r.ZVector)o.Mesh.Scale=Vector3.new(y,z,0)end local r,s=function(r)local s=k()local t,u=r.AbsoluteSize-Vector2.new(s,s),r.AbsolutePosition+Vector2.new(s/2,s/2)p(t,u)task.spawn(q)end,function()local r=game:GetService'Workspace'.CurrentCamera if not r then return end table.insert(m,r:GetPropertyChangedSignal'CFrame':Connect(q))table.insert(m,r:GetPropertyChangedSignal'ViewportSize':Connect(q))table.insert(m,r:GetPropertyChangedSignal'FieldOfView':Connect(q))task.spawn(q)end o.Destroying:Connect(function()for t,u in m do pcall(function()u:Disconnect()end)end end)s()return r,o end return function(m)local n,o,p={},l(m)local q=h.New('Frame',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})h.AddSignal(q:GetPropertyChangedSignal'AbsolutePosition',function()o(q)end)h.AddSignal(q:GetPropertyChangedSignal'AbsoluteSize',function()o(q)end)n.AddParent=function(r)h.AddSignal(r:GetPropertyChangedSignal'Visible',function()n.SetVisibility(r.Visible)end)end n.SetVisibility=function(r)p.Transparency=r and 0.98 or 1 end n.Frame=q n.Model=p return n end end,function()local c,d,e,f,g=b(4)local h,i=e(d.Parent.Parent.Creator),e(d.Parent.AcrylicBlur)local j=h.New return function(k)local l={}l.Frame=j('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=0.9,BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0},{j('ImageLabel',{Image='rbxassetid://8992230677',ScaleType='Slice',SliceCenter=Rect.new(Vector2.new(99,99),Vector2.new(99,99)),AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.new(1,120,1,116),Position=UDim2.new(0.5,0,0.5,0),BackgroundTransparency=1,ImageColor3=Color3.fromRGB(0,0,0),ImageTransparency=0.7}),j('UICorner',{CornerRadius=UDim.new(0,8)}),j('Frame',{BackgroundTransparency=0.45,Size=UDim2.fromScale(1,1),Name='Background',ThemeTag={BackgroundColor3='AcrylicMain'}},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('Frame',{BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=0.4,Size=UDim2.fromScale(1,1)},{j('UICorner',{CornerRadius=UDim.new(0,8)}),j('UIGradient',{Rotation=90,ThemeTag={Color='AcrylicGradient'}})}),j('ImageLabel',{Image='rbxassetid://9968344105',ImageTransparency=0.98,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency=1},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('ImageLabel',{Image='rbxassetid://9968344227',ImageTransparency=0.9,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ThemeTag={ImageTransparency='AcrylicNoise'}},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('Frame',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=2},{j('UICorner',{CornerRadius=UDim.new(0,8)}),j('UIStroke',{Transparency=0.5,Thickness=1,ThemeTag={Color='AcrylicBorder'}})})})local m if e(d.Parent.Parent).UseAcrylic then m=i()m.Frame.Parent=l.Frame l.Model=m.Model l.AddParent=m.AddParent l.SetVisibility=m.SetVisibility end return l end end,function()local c,d,e,f,g=b(5)local h=d.Parent.Parent local i=e(h.Creator)local j=function()local j=i.New('Part',{Name='Body',Color=Color3.new(0,0,0),Material=Enum.Material.Glass,Size=Vector3.new(1,1,0),Anchored=true,CanCollide=false,Locked=true,CastShadow=false,Transparency=0.98},{i.New('SpecialMesh',{MeshType=Enum.MeshType.Brick,Offset=Vector3.new(0,0,-1E-6)})})return j end return j end,function()local c,d,e,f,g=b(6)local h,i=function(h,i,j,k,l)return(h-i)*(l-k)/(j-i)+k end,function(h,i)local j=game:GetService'Workspace'.CurrentCamera:ScreenPointToRay(h.X,h.Y)return j.Origin+j.Direction*i end local j=function()local j=game:GetService'Workspace'.CurrentCamera.ViewportSize.Y return h(j,0,2560,8,56)end return{i,j}end,[8]=function()local c,d,e,f,g=b(8)return{Close='rbxassetid://9886659671',Min='rbxassetid://9886659276',Max='rbxassetid://9886659406',Restore='rbxassetid://9886659001'}end,[9]=function()local c,d,e,f,g=b(9)local h=d.Parent.Parent local i,j=e(h.Packages.Flipper),e(h.Creator)local k,l=j.New,i.Spring.new return function(m,n,o)o=o or false local p={}p.Title=k('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',TextColor3=Color3.fromRGB(200,200,200),TextSize=14,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ThemeTag={TextColor3='Text'}})p.HoverFrame=k('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ThemeTag={BackgroundColor3='Hover'}},{k('UICorner',{CornerRadius=UDim.new(0,4)})})p.Frame=k('TextButton',{Size=UDim2.new(0,0,0,32),Parent=n,ThemeTag={BackgroundColor3='DialogButton'}},{k('UICorner',{CornerRadius=UDim.new(0,4)}),k('UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Transparency=0.65,ThemeTag={Color='DialogButtonBorder'}}),p.HoverFrame,p.Title})local q,r=j.SpringMotor(1,p.HoverFrame,'BackgroundTransparency',o)j.AddSignal(p.Frame.MouseEnter,function()r(0.97)end)j.AddSignal(p.Frame.MouseLeave,function()r(1)end)j.AddSignal(p.Frame.MouseButton1Down,function()r(1)end)j.AddSignal(p.Frame.MouseButton1Up,function()r(0.97)end)return p end end,[10]=function()local c,d,e,f,g=b(10)local h,i,j,k=game:GetService'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(),game:GetService'Workspace'.CurrentCamera,d.Parent.Parent local l,m=e(k.Packages.Flipper),e(k.Creator)local n,o,p,q=l.Spring.new,l.Instant.new,m.New,{Window=nil}function q.Init(r,s)q.Window=s return q end function q.Create(r)local s={Buttons=0}s.TintFrame=p('TextButton',{Text='',Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=1,Parent=q.Window.Root},{p('UICorner',{CornerRadius=UDim.new(0,8)})})local t,u=m.SpringMotor(1,s.TintFrame,'BackgroundTransparency',true)s.ButtonHolder=p('Frame',{Size=UDim2.new(1,-40,1,-40),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),BackgroundTransparency=1},{p('UIListLayout',{Padding=UDim.new(0,10),FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder})})s.ButtonHolderFrame=p('Frame',{Size=UDim2.new(1,0,0,70),Position=UDim2.new(0,0,1,-70),ThemeTag={BackgroundColor3='DialogHolder'}},{p('Frame',{Size=UDim2.new(1,0,0,1),ThemeTag={BackgroundColor3='DialogHolderLine'}}),s.ButtonHolder})s.Title=p('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),Text='Dialog',TextColor3=Color3.fromRGB(240,240,240),TextSize=22,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,22),Position=UDim2.fromOffset(20,25),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})s.Scale=p('UIScale',{Scale=1})local v,w=m.SpringMotor(1.1,s.Scale,'Scale')s.Root=p('CanvasGroup',{Size=UDim2.fromOffset(300,165),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),GroupTransparency=1,Parent=s.TintFrame,ThemeTag={BackgroundColor3='Dialog'}},{p('UICorner',{CornerRadius=UDim.new(0,8)}),p('UIStroke',{Transparency=0.5,ThemeTag={Color='DialogBorder'}}),s.Scale,s.Title,s.ButtonHolderFrame})local x,y=m.SpringMotor(1,s.Root,'GroupTransparency')function s.Open(z)e(k).DialogOpen=true s.Scale.Scale=1.1 u(0.75)y(0)w(1)end function s.Close(z)e(k).DialogOpen=false u(1)y(1)w(1.1)s.Root.UIStroke:Destroy()task.wait(0.15)s.TintFrame:Destroy()end function s.Button(z,A,B)s.Buttons=s.Buttons+1 A=A or'Button'B=B or function()end local C=e(k.Components.Button)('',s.ButtonHolder,true)C.Title.Text=A for D,E in next,s.ButtonHolder:GetChildren()do if E:IsA'TextButton'then E.Size=UDim2.new(1/s.Buttons,-(((s.Buttons-1)*10)/s.Buttons),0,32)end end m.AddSignal(C.Frame.MouseButton1Click,function()e(k):SafeCallback(B)pcall(function()s:Close()end)end)return C end return s end return q end,[11]=function()local c,d,e,f,g=b(11)local h=d.Parent.Parent local i,j=e(h.Packages.Flipper),e(h.Creator)local k,l=j.New,i.Spring.new return function(m,n,o,p)local q={}q.TitleLabel=k('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Medium,Enum.FontStyle.Normal),Text=m,TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,14),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})q.DescLabel=k('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=n,TextColor3=Color3.fromRGB(200,200,200),TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),ThemeTag={TextColor3='SubText'}})q.LabelHolder=k('Frame',{AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-28,0,0)},{k('UIListLayout',{SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center}),k('UIPadding',{PaddingBottom=UDim.new(0,13),PaddingTop=UDim.new(0,13)}),q.TitleLabel,q.DescLabel})q.Border=k('UIStroke',{Transparency=0.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=Color3.fromRGB(0,0,0),ThemeTag={Color='ElementBorder'}})q.Frame=k('TextButton',{Size=UDim2.new(1,0,0,0),BackgroundTransparency=0.89,BackgroundColor3=Color3.fromRGB(130,130,130),Parent=o,AutomaticSize=Enum.AutomaticSize.Y,Text='',LayoutOrder=7,ThemeTag={BackgroundColor3='Element',BackgroundTransparency='ElementTransparency'}},{k('UICorner',{CornerRadius=UDim.new(0,4)}),q.Border,q.LabelHolder})function q.SetTitle(r,s)q.TitleLabel.Text=s end function q.SetDesc(r,s)if s==nil then s=''end if s==''then q.DescLabel.Visible=false else q.DescLabel.Visible=true end q.DescLabel.Text=s end function q.Destroy(r)q.Frame:Destroy()end q:SetTitle(m)q:SetDesc(n)if p then local r,s,t=h.Themes,j.SpringMotor(j.GetThemeProperty'ElementTransparency',q.Frame,'BackgroundTransparency',false,true)j.AddSignal(q.Frame.MouseEnter,function()t(j.GetThemeProperty'ElementTransparency'-j.GetThemeProperty'HoverChange')end)j.AddSignal(q.Frame.MouseLeave,function()t(j.GetThemeProperty'ElementTransparency')end)j.AddSignal(q.Frame.MouseButton1Down,function()t(j.GetThemeProperty'ElementTransparency'+j.GetThemeProperty'HoverChange')end)j.AddSignal(q.Frame.MouseButton1Up,function()t(j.GetThemeProperty'ElementTransparency'-j.GetThemeProperty'HoverChange')end)end return q end end,[12]=function()local c,d,e,f,g=b(12)local h=d.Parent.Parent local i,j,k=e(h.Packages.Flipper),e(h.Creator),e(h.Acrylic)local l,m,n,o=i.Spring.new,i.Instant.new,j.New,{}function o.Init(p,q)o.Holder=n('Frame',{Position=UDim2.new(1,-30,1,-30),Size=UDim2.new(0,310,1,-30),AnchorPoint=Vector2.new(1,1),BackgroundTransparency=1,Parent=q},{n('UIListLayout',{HorizontalAlignment=Enum.HorizontalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Bottom,Padding=UDim.new(0,20)})})end function o.New(p,q)q.Title=q.Title or'Title'q.Content=q.Content or'Content'q.SubContent=q.SubContent or''q.Duration=q.Duration or nil q.Buttons=q.Buttons or{}local r={Closed=false}r.AcrylicPaint=k.AcrylicPaint()r.Title=n('TextLabel',{Position=UDim2.new(0,14,0,17),Text=q.Title,RichText=true,TextColor3=Color3.fromRGB(255,255,255),TextTransparency=0,FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',TextSize=13,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-12,0,12),TextWrapped=true,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})r.ContentLabel=n('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=q.Content,TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,14),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,TextWrapped=true,ThemeTag={TextColor3='Text'}})r.SubContentLabel=n('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=q.SubContent,TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,14),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,TextWrapped=true,ThemeTag={TextColor3='SubText'}})r.LabelHolder=n('Frame',{AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Position=UDim2.fromOffset(14,40),Size=UDim2.new(1,-28,0,0)},{n('UIListLayout',{SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,3)}),r.ContentLabel,r.SubContentLabel})r.CloseButton=n('TextButton',{Text='',Position=UDim2.new(1,-14,0,13),Size=UDim2.fromOffset(20,20),AnchorPoint=Vector2.new(1,0),BackgroundTransparency=1},{n('ImageLabel',{Image=e(d.Parent.Assets).Close,Size=UDim2.fromOffset(16,16),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,ThemeTag={ImageColor3='Text'}})})r.Root=n('Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,1,0),Position=UDim2.fromScale(1,0)},{r.AcrylicPaint.Frame,r.Title,r.CloseButton,r.LabelHolder})if q.Content==''then r.ContentLabel.Visible=false end if q.SubContent==''then r.SubContentLabel.Visible=false end r.Holder=n('Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,0,200),Parent=o.Holder},{r.Root})local s=i.GroupMotor.new{Scale=1,Offset=60}s:onStep(function(t)r.Root.Position=UDim2.new(t.Scale,t.Offset,0,0)end)j.AddSignal(r.CloseButton.MouseButton1Click,function()r:Close()end)function r.Open(t)local u=r.LabelHolder.AbsoluteSize.Y r.Holder.Size=UDim2.new(1,0,0,58+u)s:setGoal{Scale=l(0,{frequency=5}),Offset=l(0,{frequency=5})}end function r.Close(t)if not r.Closed then r.Closed=true task.spawn(function()s:setGoal{Scale=l(1,{frequency=5}),Offset=l(60,{frequency=5})}task.wait(0.4)if e(h).UseAcrylic then r.AcrylicPaint.Model:Destroy()end r.Holder:Destroy()end)end end r:Open()if q.Duration then task.delay(q.Duration,function()r:Close()end)end return r end return o end,[13]=function()local c,d,e,f,g=b(13)local h=d.Parent.Parent local i=e(h.Creator)local j=i.New return function(k,l)local m={}m.Layout=j('UIListLayout',{Padding=UDim.new(0,5)})m.Container=j('Frame',{Size=UDim2.new(1,0,0,26),Position=UDim2.fromOffset(0,24),BackgroundTransparency=1},{m.Layout})m.Root=j('Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,0,26),LayoutOrder=7,Parent=l},{j('TextLabel',{RichText=true,Text=k,TextTransparency=0,FontFace=Font.new('rbxassetid://12187365364',Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),TextSize=18,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-16,0,18),Position=UDim2.fromOffset(0,2),ThemeTag={TextColor3='Text'}}),m.Container})i.AddSignal(m.Layout:GetPropertyChangedSignal'AbsoluteContentSize',function()m.Container.Size=UDim2.new(1,0,0,m.Layout.AbsoluteContentSize.Y)m.Root.Size=UDim2.new(1,0,0,m.Layout.AbsoluteContentSize.Y+25)end)return m end end,[14]=function()local c,d,e,f,g=b(14)local h=d.Parent.Parent local i,j=e(h.Packages.Flipper),e(h.Creator)local k,l,m,n,o=j.New,i.Spring.new,i.Instant.new,h.Components,{Window=nil,Tabs={},Containers={},SelectedTab=0,TabCount=0}function o.Init(p,q)o.Window=q return o end function o.GetCurrentTabPos(p)local q,r=o.Window.TabHolder.AbsolutePosition.Y,o.Tabs[o.SelectedTab].Frame.AbsolutePosition.Y return r-q end function o.New(p,q,r,s)local t,u=e(h),o.Window local v=t.Elements o.TabCount=o.TabCount+1 local w,x=o.TabCount,{Selected=false,Name=q,Type='Tab'}if t:GetIcon(r)then r=t:GetIcon(r)end if r==''or nil then r=nil end x.Frame=k('TextButton',{Size=UDim2.new(1,0,0,34),BackgroundTransparency=1,Parent=s,ThemeTag={BackgroundColor3='Tab'}},{k('UICorner',{CornerRadius=UDim.new(0,6)}),k('TextLabel',{AnchorPoint=Vector2.new(0,0.5),Position=r and UDim2.new(0,30,0.5,0)or UDim2.new(0,12,0.5,0),Text=q,RichText=true,TextColor3=Color3.fromRGB(255,255,255),TextTransparency=0,FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-12,1,0),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}}),k('ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Size=UDim2.fromOffset(16,16),Position=UDim2.new(0,8,0.5,0),BackgroundTransparency=1,Image=r and r or nil,ThemeTag={ImageColor3='Text'}})})local y=k('UIListLayout',{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})x.ContainerFrame=k('ScrollingFrame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Parent=u.ContainerHolder,Visible=false,BottomImage='rbxassetid://6889812791',MidImage='rbxassetid://6889812721',TopImage='rbxassetid://6276641225',ScrollBarImageColor3=Color3.fromRGB(255,255,255),ScrollBarImageTransparency=0.95,ScrollBarThickness=3,BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0),ScrollingDirection=Enum.ScrollingDirection.Y},{y,k('UIPadding',{PaddingRight=UDim.new(0,10),PaddingLeft=UDim.new(0,1),PaddingTop=UDim.new(0,1),PaddingBottom=UDim.new(0,1)})})j.AddSignal(y:GetPropertyChangedSignal'AbsoluteContentSize',function()x.ContainerFrame.CanvasSize=UDim2.new(0,0,0,y.AbsoluteContentSize.Y+2)end)x.Motor,x.SetTransparency=j.SpringMotor(1,x.Frame,'BackgroundTransparency')j.AddSignal(x.Frame.MouseEnter,function()x.SetTransparency(x.Selected and 0.85 or 0.89)end)j.AddSignal(x.Frame.MouseLeave,function()x.SetTransparency(x.Selected and 0.89 or 1)end)j.AddSignal(x.Frame.MouseButton1Down,function()x.SetTransparency(0.92)end)j.AddSignal(x.Frame.MouseButton1Up,function()x.SetTransparency(x.Selected and 0.85 or 0.89)end)j.AddSignal(x.Frame.MouseButton1Click,function()o:SelectTab(w)end)o.Containers[w]=x.ContainerFrame o.Tabs[w]=x x.Container=x.ContainerFrame x.ScrollFrame=x.Container function x.AddSection(z,A)local B,C={Type='Section'},e(n.Section)(A,x.Container)B.Container=C.Container B.ScrollFrame=x.Container setmetatable(B,v)return B end setmetatable(x,v)return x end function o.SelectTab(p,q)local r=o.Window o.SelectedTab=q for s,t in next,o.Tabs do t.SetTransparency(1)t.Selected=false end o.Tabs[q].SetTransparency(0.89)o.Tabs[q].Selected=true r.TabDisplay.Text=o.Tabs[q].Name r.SelectorPosMotor:setGoal(l(o:GetCurrentTabPos(),{frequency=6}))task.spawn(function()r.ContainerPosMotor:setGoal(l(110,{frequency=10}))r.ContainerBackMotor:setGoal(l(1,{frequency=10}))task.wait(0.15)for u,v in next,o.Containers do v.Visible=false end o.Containers[q].Visible=true r.ContainerPosMotor:setGoal(l(94,{frequency=5}))r.ContainerBackMotor:setGoal(l(0,{frequency=8}))end)end return o end,[15]=function()local c,d,e,f,g=b(15)local h,i=game:GetService'TextService',d.Parent.Parent local j,k=e(i.Packages.Flipper),e(i.Creator)local l=k.New return function(m,n)n=n or false local o={}o.Input=l('TextBox',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',TextColor3=Color3.fromRGB(200,200,200),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Position=UDim2.fromOffset(10,0),ThemeTag={TextColor3='Text',PlaceholderColor3='SubText'}})o.Container=l('Frame',{BackgroundTransparency=1,ClipsDescendants=true,Position=UDim2.new(0,6,0,0),Size=UDim2.new(1,-12,1,0)},{o.Input})o.Indicator=l('Frame',{Size=UDim2.new(1,-4,0,1),Position=UDim2.new(0,2,1,0),AnchorPoint=Vector2.new(0,1),BackgroundTransparency=n and 0.5 or 0,ThemeTag={BackgroundColor3=n and'InputIndicator'or'DialogInputLine'}})o.Frame=l('Frame',{Size=UDim2.new(0,0,0,30),BackgroundTransparency=n and 0.9 or 0,Parent=m,ThemeTag={BackgroundColor3=n and'Input'or'DialogInput'}},{l('UICorner',{CornerRadius=UDim.new(0,4)}),l('UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Transparency=n and 0.5 or 0.65,ThemeTag={Color=n and'InElementBorder'or'DialogButtonBorder'}}),o.Indicator,o.Container})local p=function()local p,q=2,o.Container.AbsoluteSize.X if not o.Input:IsFocused()or o.Input.TextBounds.X<=q-2*p then o.Input.Position=UDim2.new(0,p,0,0)else local r=o.Input.CursorPosition if r~=-1 then local s=string.sub(o.Input.Text,1,r-1)local t=h:GetTextSize(s,o.Input.TextSize,o.Input.Font,Vector2.new(math.huge,math.huge)).X local u=o.Input.Position.X.Offset+t if u<p then o.Input.Position=UDim2.fromOffset(p-t,0)elseif u>q-p-1 then o.Input.Position=UDim2.fromOffset(q-t-p-1,0)end end end end task.spawn(p)k.AddSignal(o.Input:GetPropertyChangedSignal'Text',p)k.AddSignal(o.Input:GetPropertyChangedSignal'CursorPosition',p)k.AddSignal(o.Input.Focused,function()p()o.Indicator.Size=UDim2.new(1,-2,0,2)o.Indicator.Position=UDim2.new(0,1,1,0)o.Indicator.BackgroundTransparency=0 k.OverrideTag(o.Frame,{BackgroundColor3=n and'InputFocused'or'DialogHolder'})k.OverrideTag(o.Indicator,{BackgroundColor3='Accent'})end)k.AddSignal(o.Input.FocusLost,function()p()o.Indicator.Size=UDim2.new(1,-4,0,1)o.Indicator.Position=UDim2.new(0,2,1,0)o.Indicator.BackgroundTransparency=0.5 k.OverrideTag(o.Frame,{BackgroundColor3=n and'Input'or'DialogInput'})k.OverrideTag(o.Indicator,{BackgroundColor3=n and'InputIndicator'or'DialogInputLine'})end)return o end end,[16]=function()local c,d,e,f,g=b(16)local h,i=d.Parent.Parent,e(d.Parent.Assets)local j,k=e(h.Creator),e(h.Packages.Flipper)local l,m=j.New,j.AddSignal return function(n)local o,p,q={},e(h),function(o,p,q,r)local s={Callback=r or function()end}s.Frame=l('TextButton',{Size=UDim2.new(0,34,1,-8),AnchorPoint=Vector2.new(1,0),BackgroundTransparency=1,Parent=q,Position=p,Text='',ThemeTag={BackgroundColor3='Text'}},{l('UICorner',{CornerRadius=UDim.new(0,7)}),l('ImageLabel',{Image=o,Size=UDim2.fromOffset(16,16),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Name='Icon',ThemeTag={ImageColor3='Text'}})})local t,u=j.SpringMotor(1,s.Frame,'BackgroundTransparency')m(s.Frame.MouseEnter,function()u(0.94)end)m(s.Frame.MouseLeave,function()u(1,true)end)m(s.Frame.MouseButton1Down,function()u(0.96)end)m(s.Frame.MouseButton1Up,function()u(0.94)end)m(s.Frame.MouseButton1Click,s.Callback)s.SetCallback=function(v)s.Callback=v end return s end o.Frame=l('Frame',{Size=UDim2.new(1,0,0,42),BackgroundTransparency=1,Parent=n.Parent},{l('Frame',{Size=UDim2.new(1,-16,1,0),Position=UDim2.new(0,16,0,0),BackgroundTransparency=1},{l('UIListLayout',{Padding=UDim.new(0,5),FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum.SortOrder.LayoutOrder}),l('TextLabel',{RichText=true,Text=n.Title,FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}}),l('TextLabel',{RichText=true,Text=n.SubTitle,TextTransparency=0.4,FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})}),l('Frame',{BackgroundTransparency=0.5,Size=UDim2.new(1,0,0,1),Position=UDim2.new(0,0,1,0),ThemeTag={BackgroundColor3='TitleBarLine'}})})o.CloseButton=q(i.Close,UDim2.new(1,-4,0,4),o.Frame,function()p.Window:Dialog{Title='Close',Content='Are you sure you want to unload the interface?',Buttons={{Title='Yes',Callback=function()p:Destroy()end},{Title='No'}}}end)o.MaxButton=q(i.Max,UDim2.new(1,-40,0,4),o.Frame,function()n.Window.Maximize(not n.Window.Maximized)end)o.MinButton=q(i.Min,UDim2.new(1,-80,0,4),o.Frame,function()p.Window:Minimize()end)return o end end,[17]=function()local c,d,e,f,g=b(17)local h,i,j,k=game:GetService'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(),game:GetService'Workspace'.CurrentCamera,d.Parent.Parent local l,m,n,o,p=e(k.Packages.Flipper),e(k.Creator),e(k.Acrylic),e(d.Parent.Assets),d.Parent local q,r,s=l.Spring.new,l.Instant.new,m.New return function(t)local u,v,w,x,y,z=e(k),{Minimized=false,Maximized=false,Size=t.Size,CurrentPos=0,Position=UDim2.fromOffset(j.ViewportSize.X/2-t.Size.X.Offset/2,j.ViewportSize.Y/2-t.Size.Y.Offset/2)},false local A,B=false local C=false v.AcrylicPaint=n.AcrylicPaint()local D,E=s('Frame',{Size=UDim2.fromOffset(4,0),BackgroundColor3=Color3.fromRGB(76,194,255),Position=UDim2.fromOffset(0,17),AnchorPoint=Vector2.new(0,0.5),ThemeTag={BackgroundColor3='Accent'}},{s('UICorner',{CornerRadius=UDim.new(0,2)})}),s('Frame',{Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,Position=UDim2.new(1,-20,1,-20)})v.TabHolder=s('ScrollingFrame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ScrollBarImageTransparency=1,ScrollBarThickness=0,BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0),ScrollingDirection=Enum.ScrollingDirection.Y},{s('UIListLayout',{Padding=UDim.new(0,4)})})local F=s('Frame',{Size=UDim2.new(0,t.TabWidth,1,-66),Position=UDim2.new(0,12,0,54),BackgroundTransparency=1,ClipsDescendants=true},{v.TabHolder,D})v.TabDisplay=s('TextLabel',{RichText=true,Text='Tab',TextTransparency=0,FontFace=Font.new('rbxassetid://12187365364',Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),TextSize=28,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-16,0,28),Position=UDim2.fromOffset(t.TabWidth+26,56),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})v.ContainerHolder=s('CanvasGroup',{Size=UDim2.new(1,-t.TabWidth-32,1,-102),Position=UDim2.fromOffset(t.TabWidth+26,90),BackgroundTransparency=1})v.Root=s('Frame',{BackgroundTransparency=1,Size=v.Size,Position=v.Position,Parent=t.Parent},{v.AcrylicPaint.Frame,v.TabDisplay,v.ContainerHolder,F,E})v.TitleBar=e(d.Parent.TitleBar){Title=t.Title,SubTitle=t.SubTitle,Parent=v.Root,Window=v}if e(k).UseAcrylic then v.AcrylicPaint.AddParent(v.Root)end local G,H=l.GroupMotor.new{X=v.Size.X.Offset,Y=v.Size.Y.Offset},l.GroupMotor.new{X=v.Position.X.Offset,Y=v.Position.Y.Offset}v.SelectorPosMotor=l.SingleMotor.new(17)v.SelectorSizeMotor=l.SingleMotor.new(0)v.ContainerBackMotor=l.SingleMotor.new(0)v.ContainerPosMotor=l.SingleMotor.new(94)G:onStep(function(I)v.Root.Size=UDim2.new(0,I.X,0,I.Y)end)H:onStep(function(I)v.Root.Position=UDim2.new(0,I.X,0,I.Y)end)local I,J=0,0 v.SelectorPosMotor:onStep(function(K)D.Position=UDim2.new(0,0,0,K+17)local L=tick()local M=L-J if I~=nil then v.SelectorSizeMotor:setGoal(q((math.abs(K-I)/(M*60))+16))I=K end J=L end)v.SelectorSizeMotor:onStep(function(K)D.Size=UDim2.new(0,4,0,K)end)v.ContainerBackMotor:onStep(function(K)v.ContainerHolder.GroupTransparency=K end)v.ContainerPosMotor:onStep(function(K)v.ContainerHolder.Position=UDim2.fromOffset(t.TabWidth+26,K)end)local K,L v.Maximize=function(M,N,O)v.Maximized=M v.TitleBar.MaxButton.Frame.Icon.Image=M and o.Restore or o.Max if M then K=v.Size.X.Offset L=v.Size.Y.Offset end local P,Q=M and j.ViewportSize.X or K,M and j.ViewportSize.Y or L G:setGoal{X=l[O and'Instant'or'Spring'].new(P,{frequency=6}),Y=l[O and'Instant'or'Spring'].new(Q,{frequency=6})}v.Size=UDim2.fromOffset(P,Q)if not N then H:setGoal{X=q(M and 0 or v.Position.X.Offset,{frequency=6}),Y=q(M and 0 or v.Position.Y.Offset,{frequency=6})}end end m.AddSignal(v.TitleBar.Frame.InputBegan,function(M)if M.UserInputType==Enum.UserInputType.MouseButton1 or M.UserInputType==Enum.UserInputType.Touch then w=true y=M.Position z=v.Root.Position if v.Maximized then z=UDim2.fromOffset(i.X-(i.X*((K-100)/v.Root.AbsoluteSize.X)),i.Y-(i.Y*(L/v.Root.AbsoluteSize.Y)))end M.Changed:Connect(function()if M.UserInputState==Enum.UserInputState.End then w=false end end)end end)m.AddSignal(v.TitleBar.Frame.InputChanged,function(M)if M.UserInputType==Enum.UserInputType.MouseMovement or M.UserInputType==Enum.UserInputType.Touch then x=M end end)m.AddSignal(E.InputBegan,function(M)if M.UserInputType==Enum.UserInputType.MouseButton1 or M.UserInputType==Enum.UserInputType.Touch then A=true B=M.Position end end)m.AddSignal(h.InputChanged,function(M)if M==x and w then local N=M.Position-y v.Position=UDim2.fromOffset(z.X.Offset+N.X,z.Y.Offset+N.Y)H:setGoal{X=r(v.Position.X.Offset),Y=r(v.Position.Y.Offset)}if v.Maximized then v.Maximize(false,true,true)end end if(M.UserInputType==Enum.UserInputType.MouseMovement or M.UserInputType==Enum.UserInputType.Touch)and A then local N,O=M.Position-B,v.Size local P=Vector3.new(O.X.Offset,O.Y.Offset,0)+Vector3.new(1,1,0)*N local Q=Vector2.new(math.clamp(P.X,470,2048),math.clamp(P.Y,380,2048))G:setGoal{X=l.Instant.new(Q.X),Y=l.Instant.new(Q.Y)}end end)m.AddSignal(h.InputEnded,function(M)if A==true or M.UserInputType==Enum.UserInputType.Touch then A=false v.Size=UDim2.fromOffset(G:getValue().X,G:getValue().Y)end end)m.AddSignal(v.TabHolder.UIListLayout:GetPropertyChangedSignal'AbsoluteContentSize',function()v.TabHolder.CanvasSize=UDim2.new(0,0,0,v.TabHolder.UIListLayout.AbsoluteContentSize.Y)end)m.AddSignal(h.InputBegan,function(M)if type(u.MinimizeKeybind)=='table'and u.MinimizeKeybind.Type=='Keybind'and not h:GetFocusedTextBox()then if M.KeyCode.Name==u.MinimizeKeybind.Value then v:Minimize()end elseif M.KeyCode==u.MinimizeKey and not h:GetFocusedTextBox()then v:Minimize()end end)function v.Minimize(M)v.Minimized=not v.Minimized v.Root.Visible=not v.Minimized if not C then C=true local N=u.MinimizeKeybind and u.MinimizeKeybind.Value or u.MinimizeKey.Name u:Notify{Title='Interface',Content='Press '..N..' to toggle the inteface.',Duration=6}end end function v.Destroy(M)if e(k).UseAcrylic then v.AcrylicPaint.Model:Destroy()end v.Root:Destroy()end local M=e(p.Dialog):Init(v)function v.Dialog(N,O)local P=M:Create()P.Title.Text=O.Title local Q=s('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=O.Content,TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,Size=UDim2.new(1,-40,1,0),Position=UDim2.fromOffset(20,60),BackgroundTransparency=1,Parent=P.Root,ClipsDescendants=false,ThemeTag={TextColor3='Text'}})s('UISizeConstraint',{MinSize=Vector2.new(300,165),MaxSize=Vector2.new(620,math.huge),Parent=P.Root})P.Root.Size=UDim2.fromOffset(Q.TextBounds.X+40,165)if Q.TextBounds.X+40>v.Size.X.Offset-120 then P.Root.Size=UDim2.fromOffset(v.Size.X.Offset-120,165)Q.TextWrapped=true P.Root.Size=UDim2.fromOffset(v.Size.X.Offset-120,Q.TextBounds.Y+150)end for R,S in next,O.Buttons do P:Button(S.Title,S.Callback)end P:Open()end local N=e(p.Tab):Init(v)function v.AddTab(O,P)return N:New(P.Title,P.Icon,v.TabHolder)end function v.SelectTab(O,P)N:SelectTab(1)end m.AddSignal(v.TabHolder:GetPropertyChangedSignal'CanvasPosition',function()I=N:GetCurrentTabPos()+16 J=0 v.SelectorPosMotor:setGoal(r(N:GetCurrentTabPos()))end)return v end end,[18]=function()local c,d,e,f,g=b(18)local h=d.Parent local i,j,k=e(h.Themes),e(h.Packages.Flipper),{Registry={},Signals={},TransparencyMotors={},DefaultProperties={ScreenGui={ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},Frame={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),BorderSizePixel=0},ScrollingFrame={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),ScrollBarImageColor3=Color3.new(0,0,0)},TextLabel={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0,0,0),BackgroundTransparency=1,TextSize=14},TextButton={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),AutoButtonColor=false,Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0,0,0),TextSize=14},TextBox={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),ClearTextOnFocus=false,Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0,0,0),TextSize=14},ImageLabel={BackgroundTransparency=1,BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),BorderSizePixel=0},ImageButton={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),AutoButtonColor=false},CanvasGroup={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),BorderSizePixel=0}}}local l=function(l,m)if m.ThemeTag then k.AddThemeObject(l,m.ThemeTag)end end function k.AddSignal(m,n)table.insert(k.Signals,m:Connect(n))end function k.Disconnect()for m=#k.Signals,1,-1 do local n=table.remove(k.Signals,m)n:Disconnect()end end function k.GetThemeProperty(m)if i[e(h).Theme][m]then return i[e(h).Theme][m]end return i.Dark[m]end function k.UpdateTheme()for m,n in next,k.Registry do for o,p in next,n.Properties do m[o]=k.GetThemeProperty(p)end end for o,p in next,k.TransparencyMotors do p:setGoal(j.Instant.new(k.GetThemeProperty'ElementTransparency'))end end function k.AddThemeObject(m,n)local o=#k.Registry+1 local p={Object=m,Properties=n,Idx=o}k.Registry[m]=p k.UpdateTheme()return m end function k.OverrideTag(m,n)k.Registry[m].Properties=n k.UpdateTheme()end function k.New(m,n,o)local p=Instance.new(m)for q,r in next,k.DefaultProperties[m]or{}do p[q]=r end for s,t in next,n or{}do if s~='ThemeTag'then p[s]=t end end for u,v in next,o or{}do v.Parent=p end l(p,n)return p end function k.SpringMotor(m,n,o,p,s)p=p or false s=s or false local t=j.SingleMotor.new(m)t:onStep(function(u)n[o]=u end)if s then table.insert(k.TransparencyMotors,t)end local u=function(u,v)v=v or false if not p then if not v then if o=='BackgroundTransparency'and e(h).DialogOpen then return end end end t:setGoal(j.Spring.new(u,{frequency=8}))end return t,u end return k end,[19]=function()local c,d,e,f,g=b(19)local h={}for i,j in next,d:GetChildren()do table.insert(h,e(j))end return h end,[20]=function()local c,d,e,f,g=b(20)local h=d.Parent.Parent local i=e(h.Creator)local j,k,l=i.New,h.Components,{}l.__index=l l.__type='Button'function l.New(m,n)assert(n.Title,'Button - Missing Title')n.Callback=n.Callback or function()end local o=e(k.Element)(n.Title,n.Description,m.Container,true)local p=j('ImageLabel',{Image='rbxassetid://10709791437',Size=UDim2.fromOffset(16,16),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),BackgroundTransparency=1,Parent=o.Frame,ThemeTag={ImageColor3='Text'}})i.AddSignal(o.Frame.MouseButton1Click,function()m.Library:SafeCallback(n.Callback)end)return o end return l end,[21]=function()local c,d,e,f,g=b(21)local h,i,j,k=game:GetService'UserInputService',game:GetService'TouchInputService',game:GetService'RunService',game:GetService'Players'local l,m=j.RenderStepped,k.LocalPlayer local n,o=m:GetMouse(),d.Parent.Parent local p=e(o.Creator)local s,t,u=p.New,o.Components,{}u.__index=u u.__type='Colorpicker'function u.New(v,w,x)local y=v.Library assert(x.Title,'Colorpicker - Missing Title')assert(x.Default,'AddColorPicker: Missing default value.')local z={Value=x.Default,Transparency=x.Transparency or 0,Type='Colorpicker',Title=type(x.Title)=='string'and x.Title or'Colorpicker',Callback=x.Callback or function(z)end}function z.SetHSVFromRGB(A,B)local C,D,E=Color3.toHSV(B)z.Hue=C z.Sat=D z.Vib=E end z:SetHSVFromRGB(z.Value)local A=e(t.Element)(x.Title,x.Description,v.Container,true)z.SetTitle=A.SetTitle z.SetDesc=A.SetDesc local B=s('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=z.Value,Parent=A.Frame},{s('UICorner',{CornerRadius=UDim.new(0,4)})})local aa,ab=s('ImageLabel',{Size=UDim2.fromOffset(26,26),Position=UDim2.new(1,-10,0.5,0),AnchorPoint=Vector2.new(1,0.5),Parent=A.Frame,Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40)},{s('UICorner',{CornerRadius=UDim.new(0,4)}),B}),function()local C=e(t.Dialog):Create()C.Title.Text=z.Title C.Root.Size=UDim2.fromOffset(430,330)local D,E,F,G,H,I=z.Hue,z.Sat,z.Vib,z.Transparency,function()local D=e(t.Textbox)()D.Frame.Parent=C.Root D.Frame.Size=UDim2.new(0,90,0,32)return D end,function(D,E)return s('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Medium,Enum.FontStyle.Normal),Text=D,TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,32),Position=E,BackgroundTransparency=1,Parent=C.Root,ThemeTag={TextColor3='Text'}})end local J,K=function()local J=Color3.fromHSV(D,E,F)return{R=math.floor(J.r*255),G=math.floor(J.g*255),B=math.floor(J.b*255)}end,s('ImageLabel',{Size=UDim2.new(0,18,0,18),ScaleType=Enum.ScaleType.Fit,AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Image='http://www.roblox.com/asset/?id=4805639000'})local L,M=s('ImageLabel',{Size=UDim2.fromOffset(180,160),Position=UDim2.fromOffset(20,55),Image='rbxassetid://4155801252',BackgroundColor3=z.Value,BackgroundTransparency=0,Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(0,4)}),K}),s('Frame',{BackgroundColor3=z.Value,Size=UDim2.fromScale(1,1),BackgroundTransparency=z.Transparency},{s('UICorner',{CornerRadius=UDim.new(0,4)})})local N,O=s('ImageLabel',{Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,Position=UDim2.fromOffset(112,220),Size=UDim2.fromOffset(88,24),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(0,4)}),s('UIStroke',{Thickness=2,Transparency=0.75}),M}),s('Frame',{BackgroundColor3=z.Value,Size=UDim2.fromScale(1,1),BackgroundTransparency=0},{s('UICorner',{CornerRadius=UDim.new(0,4)})})local P,Q=s('ImageLabel',{Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,Position=UDim2.fromOffset(20,220),Size=UDim2.fromOffset(88,24),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(0,4)}),s('UIStroke',{Thickness=2,Transparency=0.75}),O}),{}for R=0,1,0.1 do table.insert(Q,ColorSequenceKeypoint.new(R,Color3.fromHSV(R,1,1)))end local R,S=s('UIGradient',{Color=ColorSequence.new(Q),Rotation=90}),s('Frame',{Size=UDim2.new(1,0,1,-10),Position=UDim2.fromOffset(0,5),BackgroundTransparency=1})local T,U,V=s('ImageLabel',{Size=UDim2.fromOffset(14,14),Image='http://www.roblox.com/asset/?id=12266946128',Parent=S,ThemeTag={ImageColor3='DialogInput'}}),s('Frame',{Size=UDim2.fromOffset(12,190),Position=UDim2.fromOffset(210,55),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(1,0)}),R,S}),H()V.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,55)I('Hex',UDim2.fromOffset(x.Transparency and 360 or 340,55))local W=H()W.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,95)I('Red',UDim2.fromOffset(x.Transparency and 360 or 340,95))local X=H()X.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,135)I('Green',UDim2.fromOffset(x.Transparency and 360 or 340,135))local Y=H()Y.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,175)I('Blue',UDim2.fromOffset(x.Transparency and 360 or 340,175))local Z if x.Transparency then Z=H()Z.Frame.Position=UDim2.fromOffset(260,215)I('Alpha',UDim2.fromOffset(360,215))end local _,aa,ab if x.Transparency then local ac=s('Frame',{Size=UDim2.new(1,0,1,-10),Position=UDim2.fromOffset(0,5),BackgroundTransparency=1})aa=s('ImageLabel',{Size=UDim2.fromOffset(14,14),Image='http://www.roblox.com/asset/?id=12266946128',Parent=ac,ThemeTag={ImageColor3='DialogInput'}})ab=s('Frame',{Size=UDim2.fromScale(1,1)},{s('UIGradient',{Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)},Rotation=270}),s('UICorner',{CornerRadius=UDim.new(1,0)})})_=s('Frame',{Size=UDim2.fromOffset(12,190),Position=UDim2.fromOffset(230,55),Parent=C.Root,BackgroundTransparency=1},{s('UICorner',{CornerRadius=UDim.new(1,0)}),s('ImageLabel',{Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(1,0)})}),ab,ac})end local ac=function()L.BackgroundColor3=Color3.fromHSV(D,1,1)T.Position=UDim2.new(0,-1,D,-6)K.Position=UDim2.new(E,0,1-F,0)O.BackgroundColor3=Color3.fromHSV(D,E,F)V.Input.Text='#'..Color3.fromHSV(D,E,F):ToHex()W.Input.Text=J().R X.Input.Text=J().G Y.Input.Text=J().B if x.Transparency then ab.BackgroundColor3=Color3.fromHSV(D,E,F)O.BackgroundTransparency=G aa.Position=UDim2.new(0,-1,1-G,-6)Z.Input.Text=e(o):Round((1-G)*100,0)..'%'end end p.AddSignal(V.Input.FocusLost,function(ad)if ad then local ae,af=pcall(Color3.fromHex,V.Input.Text)if ae and typeof(af)=='Color3'then D,E,F=Color3.toHSV(af)end end ac()end)p.AddSignal(W.Input.FocusLost,function(ad)if ad then local ae=J()local af,ag=pcall(Color3.fromRGB,W.Input.Text,ae.G,ae.B)if af and typeof(ag)=='Color3'then if tonumber(W.Input.Text)<=255 then D,E,F=Color3.toHSV(ag)end end end ac()end)p.AddSignal(X.Input.FocusLost,function(ad)if ad then local ae=J()local af,ag=pcall(Color3.fromRGB,ae.R,X.Input.Text,ae.B)if af and typeof(ag)=='Color3'then if tonumber(X.Input.Text)<=255 then D,E,F=Color3.toHSV(ag)end end end ac()end)p.AddSignal(Y.Input.FocusLost,function(ad)if ad then local ae=J()local af,ag=pcall(Color3.fromRGB,ae.R,ae.G,Y.Input.Text)if af and typeof(ag)=='Color3'then if tonumber(Y.Input.Text)<=255 then D,E,F=Color3.toHSV(ag)end end end ac()end)if x.Transparency then p.AddSignal(Z.Input.FocusLost,function(ad)if ad then pcall(function()local ae=tonumber(Z.Input.Text)if ae>=0 and ae<=100 then G=1-ae*0.01 end end)end ac()end)end p.AddSignal(L.InputBegan,function(ad)if ad.UserInputType==Enum.UserInputType.MouseButton1 or ad.UserInputType==Enum.UserInputType.Touch then while h:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local ae=L.AbsolutePosition.X local af=ae+L.AbsoluteSize.X local ag,ah=math.clamp(n.X,ae,af),L.AbsolutePosition.Y local ai=ah+L.AbsoluteSize.Y local aj=math.clamp(n.Y,ah,ai)E=(ag-ae)/(af-ae)F=1-((aj-ah)/(ai-ah))ac()l:Wait()end end end)p.AddSignal(U.InputBegan,function(ad)if ad.UserInputType==Enum.UserInputType.MouseButton1 or ad.UserInputType==Enum.UserInputType.Touch then while h:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local ae=U.AbsolutePosition.Y local af=ae+U.AbsoluteSize.Y local ag=math.clamp(n.Y,ae,af)D=((ag-ae)/(af-ae))ac()l:Wait()end end end)if x.Transparency then p.AddSignal(_.InputBegan,function(ad)if ad.UserInputType==Enum.UserInputType.MouseButton1 then while h:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local ae=_.AbsolutePosition.Y local af=ae+_.AbsoluteSize.Y local ag=math.clamp(n.Y,ae,af)G=1-((ag-ae)/(af-ae))ac()l:Wait()end end end)end ac()C:Button('Done',function()z:SetValue({D,E,F},G)end)C:Button'Cancel'C:Open()end function z.Display(ac)z.Value=Color3.fromHSV(z.Hue,z.Sat,z.Vib)B.BackgroundColor3=z.Value B.BackgroundTransparency=z.Transparency u.Library:SafeCallback(z.Callback,z.Value)u.Library:SafeCallback(z.Changed,z.Value)end function z.SetValue(ac,ad,ae)local af=Color3.fromHSV(ad[1],ad[2],ad[3])z.Transparency=ae or 0 z:SetHSVFromRGB(af)z:Display()end function z.SetValueRGB(ac,ad,ae)z.Transparency=ae or 0 z:SetHSVFromRGB(ad)z:Display()end function z.OnChanged(ac,ad)z.Changed=ad ad(z.Value)end function z.Destroy(ac)A:Destroy()y.Options[w]=nil end p.AddSignal(A.Frame.MouseButton1Click,function()ab()end)z:Display()y.Options[w]=z return z end return u end,[22]=function()local aa,ab,ac,ad,ae=b(22)local af,ag,ah,ai,aj=game:GetService'TweenService',game:GetService'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(),game:GetService'Workspace'.CurrentCamera,ab.Parent.Parent local c,d=ac(aj.Creator),ac(aj.Packages.Flipper)local e,f,g=c.New,aj.Components,{}g.__index=g g.__type='Dropdown'function g.New(h,i,j)local k,l,m=h.Library,{Values=j.Values,Value=j.Default,Multi=j.Multi,Buttons={},Opened=false,Type='Dropdown',Callback=j.Callback or function()end},ac(f.Element)(j.Title,j.Description,h.Container,false)m.DescLabel.Size=UDim2.new(1,-170,0,14)l.SetTitle=m.SetTitle l.SetDesc=m.SetDesc local n,o=e('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),Text='Value',TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,-30,0,14),Position=UDim2.new(0,8,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,TextTruncate=Enum.TextTruncate.AtEnd,ThemeTag={TextColor3='Text'}}),e('ImageLabel',{Image='rbxassetid://10709790948',Size=UDim2.fromOffset(16,16),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-8,0.5,0),BackgroundTransparency=1,ThemeTag={ImageColor3='SubText'}})local p,s=e('TextButton',{Size=UDim2.fromOffset(160,30),Position=UDim2.new(1,-10,0.5,0),AnchorPoint=Vector2.new(1,0.5),BackgroundTransparency=0.9,Parent=m.Frame,ThemeTag={BackgroundColor3='DropdownFrame'}},{e('UICorner',{CornerRadius=UDim.new(0,5)}),e('UIStroke',{Transparency=0.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,ThemeTag={Color='InElementBorder'}}),o,n}),e('UIListLayout',{Padding=UDim.new(0,3)})local t=e('ScrollingFrame',{Size=UDim2.new(1,-5,1,-10),Position=UDim2.fromOffset(5,5),BackgroundTransparency=1,BottomImage='rbxassetid://6889812791',MidImage='rbxassetid://6889812721',TopImage='rbxassetid://6276641225',ScrollBarImageColor3=Color3.fromRGB(255,255,255),ScrollBarImageTransparency=0.95,ScrollBarThickness=4,BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0)},{s})local u=e('Frame',{Size=UDim2.fromScale(1,0.6),ThemeTag={BackgroundColor3='DropdownHolder'}},{t,e('UICorner',{CornerRadius=UDim.new(0,7)}),e('UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,ThemeTag={Color='DropdownBorder'}}),e('ImageLabel',{BackgroundTransparency=1,Image='http://www.roblox.com/asset/?id=5554236805',ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(23,23,277,277),Size=UDim2.fromScale(1,1)+UDim2.fromOffset(30,30),Position=UDim2.fromOffset(-15,-15),ImageColor3=Color3.fromRGB(0,0,0),ImageTransparency=0.1})})local v=e('Frame',{BackgroundTransparency=1,Size=UDim2.fromOffset(170,300),Parent=h.Library.GUI,Visible=false},{u,e('UISizeConstraint',{MinSize=Vector2.new(170,0)})})table.insert(k.OpenFrames,v)local w,x=function()local w=0 if ai.ViewportSize.Y-p.AbsolutePosition.Y<v.AbsoluteSize.Y-5 then w=v.AbsoluteSize.Y-5-(ai.ViewportSize.Y-p.AbsolutePosition.Y)+40 end v.Position=UDim2.fromOffset(p.AbsolutePosition.X-1,p.AbsolutePosition.Y-5-w)end,0 local y,z=function()if#l.Values>10 then v.Size=UDim2.fromOffset(x,392)else v.Size=UDim2.fromOffset(x,s.AbsoluteContentSize.Y+10)end end,function()t.CanvasSize=UDim2.fromOffset(0,s.AbsoluteContentSize.Y)end w()y()c.AddSignal(p:GetPropertyChangedSignal'AbsolutePosition',w)c.AddSignal(p.MouseButton1Click,function()l:Open()end)c.AddSignal(ag.InputBegan,function(A)if A.UserInputType==Enum.UserInputType.MouseButton1 or A.UserInputType==Enum.UserInputType.Touch then local B,C=u.AbsolutePosition,u.AbsoluteSize if ah.X<B.X or ah.X>B.X+C.X or ah.Y<(B.Y-20-1)or ah.Y>B.Y+C.Y then l:Close()end end end)local A=h.ScrollFrame function l.Open(B)l.Opened=true A.ScrollingEnabled=false v.Visible=true af:Create(u,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.fromScale(1,1)}):Play()end function l.Close(B)l.Opened=false A.ScrollingEnabled=true u.Size=UDim2.fromScale(1,0.6)v.Visible=false end function l.Display(B)local C,D=l.Values,''if j.Multi then for E,F in next,C do if l.Value[F]then D=D..F..', 'end end D=D:sub(1,#D-2)else D=l.Value or''end n.Text=(D==''and'--'or D)end function l.GetActiveValues(B)if j.Multi then local C={}for D,E in next,l.Value do table.insert(C,D)end return C else return l.Value and 1 or 0 end end function l.BuildDropdownList(B)local C,D=l.Values,{}for E,F in next,t:GetChildren()do if not F:IsA'UIListLayout'then F:Destroy()end end local G=0 for H,I in next,C do local J={}G=G+1 local K,L=e('Frame',{Size=UDim2.fromOffset(4,14),BackgroundColor3=Color3.fromRGB(76,194,255),Position=UDim2.fromOffset(-1,16),AnchorPoint=Vector2.new(0,0.5),ThemeTag={BackgroundColor3='Accent'}},{e('UICorner',{CornerRadius=UDim.new(0,2)})}),e('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=I,TextColor3=Color3.fromRGB(200,200,200),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Position=UDim2.fromOffset(10,0),Name='ButtonLabel',ThemeTag={TextColor3='Text'}})local M,N=(e('TextButton',{Size=UDim2.new(1,-5,0,32),BackgroundTransparency=1,ZIndex=23,Text='',Parent=t,ThemeTag={BackgroundColor3='DropdownOption'}},{K,L,e('UICorner',{CornerRadius=UDim.new(0,6)})}))if j.Multi then N=l.Value[I]else N=l.Value==I end local O,P=c.SpringMotor(1,M,'BackgroundTransparency')local Q,R=c.SpringMotor(1,K,'BackgroundTransparency')local S=d.SingleMotor.new(6)S:onStep(function(T)K.Size=UDim2.new(0,4,0,T)end)c.AddSignal(M.MouseEnter,function()P(N and 0.85 or 0.89)end)c.AddSignal(M.MouseLeave,function()P(N and 0.89 or 1)end)c.AddSignal(M.MouseButton1Down,function()P(0.92)end)c.AddSignal(M.MouseButton1Up,function()P(N and 0.85 or 0.89)end)function J.UpdateButton(T)if j.Multi then N=l.Value[I]if N then P(0.89)end else N=l.Value==I P(N and 0.89 or 1)end S:setGoal(d.Spring.new(N and 14 or 6,{frequency=6}))R(N and 0 or 1)end L.InputBegan:Connect(function(T)if T.UserInputType==Enum.UserInputType.MouseButton1 or T.UserInputType==Enum.UserInputType.Touch then local U=not N if l:GetActiveValues()==1 and not U and not j.AllowNull then else if j.Multi then N=U l.Value[I]=N and true or nil else N=U l.Value=N and I or nil for V,W in next,D do W:UpdateButton()end end J:UpdateButton()l:Display()k:SafeCallback(l.Callback,l.Value)k:SafeCallback(l.Changed,l.Value)end end end)J:UpdateButton()l:Display()D[M]=J end x=0 for J,K in next,D do if J.ButtonLabel then if J.ButtonLabel.TextBounds.X>x then x=J.ButtonLabel.TextBounds.X end end end x=x+30 z()y()end function l.SetValues(B,C)if C then l.Values=C end l:BuildDropdownList()end function l.OnChanged(B,C)l.Changed=C C(l.Value)end function l.SetValue(B,C)if l.Multi then local D={}for E,F in next,C do if table.find(l.Values,E)then D[E]=true end end l.Value=D else if not C then l.Value=nil elseif table.find(l.Values,C)then l.Value=C end end l:BuildDropdownList()k:SafeCallback(l.Callback,l.Value)k:SafeCallback(l.Changed,l.Value)end function l.Destroy(B)m:Destroy()k.Options[i]=nil end l:BuildDropdownList()l:Display()local B={}if type(j.Default)=='string'then local C=table.find(l.Values,j.Default)if C then table.insert(B,C)end elseif type(j.Default)=='table'then for C,D in next,j.Default do local E=table.find(l.Values,D)if E then table.insert(B,E)end end elseif type(j.Default)=='number'and l.Values[j.Default]~=nil then table.insert(B,j.Default)end if next(B)then for C=1,#B do local D=B[C]if j.Multi then l.Value[l.Values[D]]=true else l.Value=l.Values[D]end if not j.Multi then break end end l:BuildDropdownList()l:Display()end k.Options[i]=l return l end return g end,[23]=function()local aa,ab,ac,ad,ae=b(23)local af=ab.Parent.Parent local ag=ac(af.Creator)local ah,ai,aj,c=ag.New,ag.AddSignal,af.Components,{}c.__index=c c.__type='Input'function c.New(d,e,f)local g=d.Library assert(f.Title,'Input - Missing Title')f.Callback=f.Callback or function()end local h,i={Value=f.Default or'',Numeric=f.Numeric or false,Finished=f.Finished or false,Callback=f.Callback or function(h)end,Type='Input'},ac(aj.Element)(f.Title,f.Description,d.Container,false)h.SetTitle=i.SetTitle h.SetDesc=i.SetDesc local j=ac(aj.Textbox)(i.Frame,true)j.Frame.Position=UDim2.new(1,-10,0.5,0)j.Frame.AnchorPoint=Vector2.new(1,0.5)j.Frame.Size=UDim2.fromOffset(160,30)j.Input.Text=f.Default or''j.Input.PlaceholderText=f.Placeholder or''local k=j.Input function h.SetValue(l,m)if f.MaxLength and#m>f.MaxLength then m=m:sub(1,f.MaxLength)end if h.Numeric then if(not tonumber(m))and m:len()>0 then m=h.Value end end h.Value=m k.Text=m g:SafeCallback(h.Callback,h.Value)g:SafeCallback(h.Changed,h.Value)end if h.Finished then ai(k.FocusLost,function(l)if not l then return end h:SetValue(k.Text)end)else ai(k:GetPropertyChangedSignal'Text',function()h:SetValue(k.Text)end)end function h.OnChanged(l,m)h.Changed=m m(h.Value)end function h.Destroy(l)i:Destroy()g.Options[e]=nil end g.Options[e]=h return h end return c end,[24]=function()local aa,ab,ac,ad,ae=b(24)local af,ag=game:GetService'UserInputService',ab.Parent.Parent local ah=ac(ag.Creator)local ai,aj,c=ah.New,ag.Components,{}c.__index=c c.__type='Keybind'function c.New(d,e,f)local g=d.Library assert(f.Title,'KeyBind - Missing Title')assert(f.Default,'KeyBind - Missing default value.')local h,i,j={Value=f.Default,Toggled=false,Mode=f.Mode or'Toggle',Type='Keybind',Callback=f.Callback or function(h)end,ChangedCallback=f.ChangedCallback or function(h)end},false,ac(aj.Element)(f.Title,f.Description,d.Container,true)h.SetTitle=j.SetTitle h.SetDesc=j.SetDesc local k=ai('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),Text=f.Default,TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Center,Size=UDim2.new(0,0,0,14),Position=UDim2.new(0,0,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})local l=ai('TextButton',{Size=UDim2.fromOffset(0,30),Position=UDim2.new(1,-10,0.5,0),AnchorPoint=Vector2.new(1,0.5),BackgroundTransparency=0.9,Parent=j.Frame,AutomaticSize=Enum.AutomaticSize.X,ThemeTag={BackgroundColor3='Keybind'}},{ai('UICorner',{CornerRadius=UDim.new(0,5)}),ai('UIPadding',{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)}),ai('UIStroke',{Transparency=0.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,ThemeTag={Color='InElementBorder'}}),k})function h.GetState(m)if af:GetFocusedTextBox()and h.Mode~='Always'then return false end if h.Mode=='Always'then return true elseif h.Mode=='Hold'then if h.Value=='None'then return false end local n=h.Value if n=='MouseLeft'or n=='MouseRight'then return n=='MouseLeft'and af:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)or n=='MouseRight'and af:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)else return af:IsKeyDown(Enum.KeyCode[h.Value])end else return h.Toggled end end function h.SetValue(m,n,o)n=n or h.Key o=o or h.Mode k.Text=n h.Value=n h.Mode=o end function h.OnClick(m,n)h.Clicked=n end function h.OnChanged(m,n)h.Changed=n n(h.Value)end function h.DoClick(m)g:SafeCallback(h.Callback,h.Toggled)g:SafeCallback(h.Clicked,h.Toggled)end function h.Destroy(m)j:Destroy()g.Options[e]=nil end ah.AddSignal(l.InputBegan,function(m)if m.UserInputType==Enum.UserInputType.MouseButton1 or m.UserInputType==Enum.UserInputType.Touch then i=true k.Text='...'wait(0.2)local n n=af.InputBegan:Connect(function(o)local p if o.UserInputType==Enum.UserInputType.Keyboard then p=o.KeyCode.Name elseif o.UserInputType==Enum.UserInputType.MouseButton1 then p='MouseLeft'elseif o.UserInputType==Enum.UserInputType.MouseButton2 then p='MouseRight'end local s s=af.InputEnded:Connect(function(t)if t.KeyCode.Name==p or p=='MouseLeft'and t.UserInputType==Enum.UserInputType.MouseButton1 or p=='MouseRight'and t.UserInputType==Enum.UserInputType.MouseButton2 then i=false k.Text=p h.Value=p g:SafeCallback(h.ChangedCallback,t.KeyCode or t.UserInputType)g:SafeCallback(h.Changed,t.KeyCode or t.UserInputType)n:Disconnect()s:Disconnect()end end)end)end end)ah.AddSignal(af.InputBegan,function(m)if not i and not af:GetFocusedTextBox()then if h.Mode=='Toggle'then local n=h.Value if n=='MouseLeft'or n=='MouseRight'then if n=='MouseLeft'and m.UserInputType==Enum.UserInputType.MouseButton1 or n=='MouseRight'and m.UserInputType==Enum.UserInputType.MouseButton2 then h.Toggled=not h.Toggled h:DoClick()end elseif m.UserInputType==Enum.UserInputType.Keyboard then if m.KeyCode.Name==n then h.Toggled=not h.Toggled h:DoClick()end end end end end)g.Options[e]=h return h end return c end,[25]=function()local aa,ab,ac,ad,ae=b(25)local af=ab.Parent.Parent local ag,ah,ai,aj=af.Components,ac(af.Packages.Flipper),ac(af.Creator),{}aj.__index=aj aj.__type='Paragraph'function aj.New(c,d)assert(d.Title,'Paragraph - Missing Title')d.Content=d.Content or''local e=ac(ag.Element)(d.Title,d.Content,aj.Container,false)e.Frame.BackgroundTransparency=0.92 e.Border.Transparency=0.6 return e end return aj end,[26]=function()local aa,ab,ac,ad,ae=b(26)local af,ag=game:GetService'UserInputService',ab.Parent.Parent local ah=ac(ag.Creator)local ai,aj,c=ah.New,ag.Components,{}c.__index=c c.__type='Slider'function c.New(d,e,f)local g=d.Library assert(f.Title,'Slider - Missing Title.')assert(f.Default,'Slider - Missing default value.')assert(f.Min,'Slider - Missing minimum value.')assert(f.Max,'Slider - Missing maximum value.')assert(f.Rounding,'Slider - Missing rounding value.')local h,i,j={Value=nil,Min=f.Min,Max=f.Max,Rounding=f.Rounding,Callback=f.Callback or function(h)end,Type='Slider'},false,ac(aj.Element)(f.Title,f.Description,d.Container,false)j.DescLabel.Size=UDim2.new(1,-170,0,14)h.SetTitle=j.SetTitle h.SetDesc=j.SetDesc local k=ai('ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,-7,0.5,0),Size=UDim2.fromOffset(14,14),Image='http://www.roblox.com/asset/?id=12266946128',ThemeTag={ImageColor3='Accent'}})local l,m,n=ai('Frame',{BackgroundTransparency=1,Position=UDim2.fromOffset(7,0),Size=UDim2.new(1,-14,1,0)},{k}),ai('Frame',{Size=UDim2.new(0,0,1,0),ThemeTag={BackgroundColor3='Accent'}},{ai('UICorner',{CornerRadius=UDim.new(1,0)})}),ai('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text='Value',TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Right,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Size=UDim2.new(0,100,0,14),Position=UDim2.new(0,-4,0.5,0),AnchorPoint=Vector2.new(1,0.5),ThemeTag={TextColor3='SubText'}})local o=ai('Frame',{Size=UDim2.new(1,0,0,4),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),BackgroundTransparency=0.4,Parent=j.Frame,ThemeTag={BackgroundColor3='SliderRail'}},{ai('UICorner',{CornerRadius=UDim.new(1,0)}),ai('UISizeConstraint',{MaxSize=Vector2.new(150,math.huge)}),n,m,l})ah.AddSignal(k.InputBegan,function(p)if p.UserInputType==Enum.UserInputType.MouseButton1 or p.UserInputType==Enum.UserInputType.Touch then i=true end end)ah.AddSignal(k.InputEnded,function(p)if p.UserInputType==Enum.UserInputType.MouseButton1 or p.UserInputType==Enum.UserInputType.Touch then i=false end end)ah.AddSignal(af.InputChanged,function(p)if i and(p.UserInputType==Enum.UserInputType.MouseMovement or p.UserInputType==Enum.UserInputType.Touch)then local s=math.clamp((p.Position.X-l.AbsolutePosition.X)/l.AbsoluteSize.X,0,1)h:SetValue(h.Min+((h.Max-h.Min)*s))end end)function h.OnChanged(p,s)h.Changed=s s(h.Value)end function h.SetValue(p,s)p.Value=g:Round(math.clamp(s,h.Min,h.Max),h.Rounding)k.Position=UDim2.new((p.Value-h.Min)/(h.Max-h.Min),-7,0.5,0)m.Size=UDim2.fromScale((p.Value-h.Min)/(h.Max-h.Min),1)n.Text=tostring(p.Value)g:SafeCallback(h.Callback,p.Value)g:SafeCallback(h.Changed,p.Value)end function h.Destroy(p)j:Destroy()g.Options[e]=nil end h:SetValue(f.Default)g.Options[e]=h return h end return c end,[27]=function()local aa,ab,ac,ad,ae=b(27)local af,ag=game:GetService'TweenService',ab.Parent.Parent local ah=ac(ag.Creator)local ai,aj,c=ah.New,ag.Components,{}c.__index=c c.__type='Toggle'function c.New(d,e,f)local g=d.Library assert(f.Title,'Toggle - Missing Title')local h,i={Value=f.Default or false,Callback=f.Callback or function(h)end,Type='Toggle'},ac(aj.Element)(f.Title,f.Description,d.Container,true)i.DescLabel.Size=UDim2.new(1,-54,0,14)h.SetTitle=i.SetTitle h.SetDesc=i.SetDesc local j,k=ai('ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Size=UDim2.fromOffset(14,14),Position=UDim2.new(0,2,0.5,0),Image='http://www.roblox.com/asset/?id=12266946128',ImageTransparency=0.5,ThemeTag={ImageColor3='ToggleSlider'}}),ai('UIStroke',{Transparency=0.5,ThemeTag={Color='ToggleSlider'}})local l=ai('Frame',{Size=UDim2.fromOffset(36,18),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),Parent=i.Frame,BackgroundTransparency=1,ThemeTag={BackgroundColor3='Accent'}},{ai('UICorner',{CornerRadius=UDim.new(0,9)}),k,j})function h.OnChanged(m,n)h.Changed=n n(h.Value)end function h.SetValue(m,n)n=not not n h.Value=n ah.OverrideTag(k,{Color=h.Value and'Accent'or'ToggleSlider'})ah.OverrideTag(j,{ImageColor3=h.Value and'ToggleToggled'or'ToggleSlider'})af:Create(j,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=UDim2.new(0,h.Value and 19 or 2,0.5,0)}):Play()af:Create(l,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{BackgroundTransparency=h.Value and 0 or 1}):Play()j.ImageTransparency=h.Value and 0 or 0.5 g:SafeCallback(h.Callback,h.Value)g:SafeCallback(h.Changed,h.Value)end function h.Destroy(m)i:Destroy()g.Options[e]=nil end ah.AddSignal(i.Frame.MouseButton1Click,function()h:SetValue(not h.Value)end)h:SetValue(h.Value)g.Options[e]=h return h end return c end,[28]=function()local aa,ab,ac,ad,ae=b(28)return{assets={['lucide-accessibility']='rbxassetid://10709751939',['lucide-activity']='rbxassetid://10709752035',['lucide-air-vent']='rbxassetid://10709752131',['lucide-airplay']='rbxassetid://10709752254',['lucide-alarm-check']='rbxassetid://10709752405',['lucide-alarm-clock']='rbxassetid://10709752630',['lucide-alarm-clock-off']='rbxassetid://10709752508',['lucide-alarm-minus']='rbxassetid://10709752732',['lucide-alarm-plus']='rbxassetid://10709752825',['lucide-album']='rbxassetid://10709752906',['lucide-alert-circle']='rbxassetid://10709752996',['lucide-alert-octagon']='rbxassetid://10709753064',['lucide-alert-triangle']='rbxassetid://10709753149',['lucide-align-center']='rbxassetid://10709753570',['lucide-align-center-horizontal']='rbxassetid://10709753272',['lucide-align-center-vertical']='rbxassetid://10709753421',['lucide-align-end-horizontal']='rbxassetid://10709753692',['lucide-align-end-vertical']='rbxassetid://10709753808',['lucide-align-horizontal-distribute-center']='rbxassetid://10747779791',['lucide-align-horizontal-distribute-end']='rbxassetid://10747784534',['lucide-align-horizontal-distribute-start']='rbxassetid://10709754118',['lucide-align-horizontal-justify-center']='rbxassetid://10709754204',['lucide-align-horizontal-justify-end']='rbxassetid://10709754317',['lucide-align-horizontal-justify-start']='rbxassetid://10709754436',['lucide-align-horizontal-space-around']='rbxassetid://10709754590',['lucide-align-horizontal-space-between']='rbxassetid://10709754749',['lucide-align-justify']='rbxassetid://10709759610',['lucide-align-left']='rbxassetid://10709759764',['lucide-align-right']='rbxassetid://10709759895',['lucide-align-start-horizontal']='rbxassetid://10709760051',['lucide-align-start-vertical']='rbxassetid://10709760244',['lucide-align-vertical-distribute-center']='rbxassetid://10709760351',['lucide-align-vertical-distribute-end']='rbxassetid://10709760434',['lucide-align-vertical-distribute-start']='rbxassetid://10709760612',['lucide-align-vertical-justify-center']='rbxassetid://10709760814',['lucide-align-vertical-justify-end']='rbxassetid://10709761003',['lucide-align-vertical-justify-start']='rbxassetid://10709761176',['lucide-align-vertical-space-around']='rbxassetid://10709761324',['lucide-align-vertical-space-between']='rbxassetid://10709761434',['lucide-anchor']='rbxassetid://10709761530',['lucide-angry']='rbxassetid://10709761629',['lucide-annoyed']='rbxassetid://10709761722',['lucide-aperture']='rbxassetid://10709761813',['lucide-apple']='rbxassetid://10709761889',['lucide-archive']='rbxassetid://10709762233',['lucide-archive-restore']='rbxassetid://10709762058',['lucide-armchair']='rbxassetid://10709762327',['lucide-arrow-big-down']='rbxassetid://10747796644',['lucide-arrow-big-left']='rbxassetid://10709762574',['lucide-arrow-big-right']='rbxassetid://10709762727',['lucide-arrow-big-up']='rbxassetid://10709762879',['lucide-arrow-down']='rbxassetid://10709767827',['lucide-arrow-down-circle']='rbxassetid://10709763034',['lucide-arrow-down-left']='rbxassetid://10709767656',['lucide-arrow-down-right']='rbxassetid://10709767750',['lucide-arrow-left']='rbxassetid://10709768114',['lucide-arrow-left-circle']='rbxassetid://10709767936',['lucide-arrow-left-right']='rbxassetid://10709768019',['lucide-arrow-right']='rbxassetid://10709768347',['lucide-arrow-right-circle']='rbxassetid://10709768226',['lucide-arrow-up']='rbxassetid://10709768939',['lucide-arrow-up-circle']='rbxassetid://10709768432',['lucide-arrow-up-down']='rbxassetid://10709768538',['lucide-arrow-up-left']='rbxassetid://10709768661',['lucide-arrow-up-right']='rbxassetid://10709768787',['lucide-asterisk']='rbxassetid://10709769095',['lucide-at-sign']='rbxassetid://10709769286',['lucide-award']='rbxassetid://10709769406',['lucide-axe']='rbxassetid://10709769508',['lucide-axis-3d']='rbxassetid://10709769598',['lucide-baby']='rbxassetid://10709769732',['lucide-backpack']='rbxassetid://10709769841',['lucide-baggage-claim']='rbxassetid://10709769935',['lucide-banana']='rbxassetid://10709770005',['lucide-banknote']='rbxassetid://10709770178',['lucide-bar-chart']='rbxassetid://10709773755',['lucide-bar-chart-2']='rbxassetid://10709770317',['lucide-bar-chart-3']='rbxassetid://10709770431',['lucide-bar-chart-4']='rbxassetid://10709770560',['lucide-bar-chart-horizontal']='rbxassetid://10709773669',['lucide-barcode']='rbxassetid://10747360675',['lucide-baseline']='rbxassetid://10709773863',['lucide-bath']='rbxassetid://10709773963',['lucide-battery']='rbxassetid://10709774640',['lucide-battery-charging']='rbxassetid://10709774068',['lucide-battery-full']='rbxassetid://10709774206',['lucide-battery-low']='rbxassetid://10709774370',['lucide-battery-medium']='rbxassetid://10709774513',['lucide-beaker']='rbxassetid://10709774756',['lucide-bed']='rbxassetid://10709775036',['lucide-bed-double']='rbxassetid://10709774864',['lucide-bed-single']='rbxassetid://10709774968',['lucide-beer']='rbxassetid://10709775167',['lucide-bell']='rbxassetid://10709775704',['lucide-bell-minus']='rbxassetid://10709775241',['lucide-bell-off']='rbxassetid://10709775320',['lucide-bell-plus']='rbxassetid://10709775448',['lucide-bell-ring']='rbxassetid://10709775560',['lucide-bike']='rbxassetid://10709775894',['lucide-binary']='rbxassetid://10709776050',['lucide-bitcoin']='rbxassetid://10709776126',['lucide-bluetooth']='rbxassetid://10709776655',['lucide-bluetooth-connected']='rbxassetid://10709776240',['lucide-bluetooth-off']='rbxassetid://10709776344',['lucide-bluetooth-searching']='rbxassetid://10709776501',['lucide-bold']='rbxassetid://10747813908',['lucide-bomb']='rbxassetid://10709781460',['lucide-bone']='rbxassetid://10709781605',['lucide-book']='rbxassetid://10709781824',['lucide-book-open']='rbxassetid://10709781717',['lucide-bookmark']='rbxassetid://10709782154',['lucide-bookmark-minus']='rbxassetid://10709781919',['lucide-bookmark-plus']='rbxassetid://10709782044',['lucide-bot']='rbxassetid://10709782230',['lucide-box']='rbxassetid://10709782497',['lucide-box-select']='rbxassetid://10709782342',['lucide-boxes']='rbxassetid://10709782582',['lucide-briefcase']='rbxassetid://10709782662',['lucide-brush']='rbxassetid://10709782758',['lucide-bug']='rbxassetid://10709782845',['lucide-building']='rbxassetid://10709783051',['lucide-building-2']='rbxassetid://10709782939',['lucide-bus']='rbxassetid://10709783137',['lucide-cake']='rbxassetid://10709783217',['lucide-calculator']='rbxassetid://10709783311',['lucide-calendar']='rbxassetid://10709789505',['lucide-calendar-check']='rbxassetid://10709783474',['lucide-calendar-check-2']='rbxassetid://10709783392',['lucide-calendar-clock']='rbxassetid://10709783577',['lucide-calendar-days']='rbxassetid://10709783673',['lucide-calendar-heart']='rbxassetid://10709783835',['lucide-calendar-minus']='rbxassetid://10709783959',['lucide-calendar-off']='rbxassetid://10709788784',['lucide-calendar-plus']='rbxassetid://10709788937',['lucide-calendar-range']='rbxassetid://10709789053',['lucide-calendar-search']='rbxassetid://10709789200',['lucide-calendar-x']='rbxassetid://10709789407',['lucide-calendar-x-2']='rbxassetid://10709789329',['lucide-camera']='rbxassetid://10709789686',['lucide-camera-off']='rbxassetid://10747822677',['lucide-car']='rbxassetid://10709789810',['lucide-carrot']='rbxassetid://10709789960',['lucide-cast']='rbxassetid://10709790097',['lucide-charge']='rbxassetid://10709790202',['lucide-check']='rbxassetid://10709790644',['lucide-check-circle']='rbxassetid://10709790387',['lucide-check-circle-2']='rbxassetid://10709790298',['lucide-check-square']='rbxassetid://10709790537',['lucide-chef-hat']='rbxassetid://10709790757',['lucide-cherry']='rbxassetid://10709790875',['lucide-chevron-down']='rbxassetid://10709790948',['lucide-chevron-first']='rbxassetid://10709791015',['lucide-chevron-last']='rbxassetid://10709791130',['lucide-chevron-left']='rbxassetid://10709791281',['lucide-chevron-right']='rbxassetid://10709791437',['lucide-chevron-up']='rbxassetid://10709791523',['lucide-chevrons-down']='rbxassetid://10709796864',['lucide-chevrons-down-up']='rbxassetid://10709791632',['lucide-chevrons-left']='rbxassetid://10709797151',['lucide-chevrons-left-right']='rbxassetid://10709797006',['lucide-chevrons-right']='rbxassetid://10709797382',['lucide-chevrons-right-left']='rbxassetid://10709797274',['lucide-chevrons-up']='rbxassetid://10709797622',['lucide-chevrons-up-down']='rbxassetid://10709797508',['lucide-chrome']='rbxassetid://10709797725',['lucide-circle']='rbxassetid://10709798174',['lucide-circle-dot']='rbxassetid://10709797837',['lucide-circle-ellipsis']='rbxassetid://10709797985',['lucide-circle-slashed']='rbxassetid://10709798100',['lucide-citrus']='rbxassetid://10709798276',['lucide-clapperboard']='rbxassetid://10709798350',['lucide-clipboard']='rbxassetid://10709799288',['lucide-clipboard-check']='rbxassetid://10709798443',['lucide-clipboard-copy']='rbxassetid://10709798574',['lucide-clipboard-edit']='rbxassetid://10709798682',['lucide-clipboard-list']='rbxassetid://10709798792',['lucide-clipboard-signature']='rbxassetid://10709798890',['lucide-clipboard-type']='rbxassetid://10709798999',['lucide-clipboard-x']='rbxassetid://10709799124',['lucide-clock']='rbxassetid://10709805144',['lucide-clock-1']='rbxassetid://10709799535',['lucide-clock-10']='rbxassetid://10709799718',['lucide-clock-11']='rbxassetid://10709799818',['lucide-clock-12']='rbxassetid://10709799962',['lucide-clock-2']='rbxassetid://10709803876',['lucide-clock-3']='rbxassetid://10709803989',['lucide-clock-4']='rbxassetid://10709804164',['lucide-clock-5']='rbxassetid://10709804291',['lucide-clock-6']='rbxassetid://10709804435',['lucide-clock-7']='rbxassetid://10709804599',['lucide-clock-8']='rbxassetid://10709804784',['lucide-clock-9']='rbxassetid://10709804996',['lucide-cloud']='rbxassetid://10709806740',['lucide-cloud-cog']='rbxassetid://10709805262',['lucide-cloud-drizzle']='rbxassetid://10709805371',['lucide-cloud-fog']='rbxassetid://10709805477',['lucide-cloud-hail']='rbxassetid://10709805596',['lucide-cloud-lightning']='rbxassetid://10709805727',['lucide-cloud-moon']='rbxassetid://10709805942',['lucide-cloud-moon-rain']='rbxassetid://10709805838',['lucide-cloud-off']='rbxassetid://10709806060',['lucide-cloud-rain']='rbxassetid://10709806277',['lucide-cloud-rain-wind']='rbxassetid://10709806166',['lucide-cloud-snow']='rbxassetid://10709806374',['lucide-cloud-sun']='rbxassetid://10709806631',['lucide-cloud-sun-rain']='rbxassetid://10709806475',['lucide-cloudy']='rbxassetid://10709806859',['lucide-clover']='rbxassetid://10709806995',['lucide-code']='rbxassetid://10709810463',['lucide-code-2']='rbxassetid://10709807111',['lucide-codepen']='rbxassetid://10709810534',['lucide-codesandbox']='rbxassetid://10709810676',['lucide-coffee']='rbxassetid://10709810814',['lucide-cog']='rbxassetid://10709810948',['lucide-coins']='rbxassetid://10709811110',['lucide-columns']='rbxassetid://10709811261',['lucide-command']='rbxassetid://10709811365',['lucide-compass']='rbxassetid://10709811445',['lucide-component']='rbxassetid://10709811595',['lucide-concierge-bell']='rbxassetid://10709811706',['lucide-connection']='rbxassetid://10747361219',['lucide-contact']='rbxassetid://10709811834',['lucide-contrast']='rbxassetid://10709811939',['lucide-cookie']='rbxassetid://10709812067',['lucide-copy']='rbxassetid://10709812159',['lucide-copyleft']='rbxassetid://10709812251',['lucide-copyright']='rbxassetid://10709812311',['lucide-corner-down-left']='rbxassetid://10709812396',['lucide-corner-down-right']='rbxassetid://10709812485',['lucide-corner-left-down']='rbxassetid://10709812632',['lucide-corner-left-up']='rbxassetid://10709812784',['lucide-corner-right-down']='rbxassetid://10709812939',['lucide-corner-right-up']='rbxassetid://10709813094',['lucide-corner-up-left']='rbxassetid://10709813185',['lucide-corner-up-right']='rbxassetid://10709813281',['lucide-cpu']='rbxassetid://10709813383',['lucide-croissant']='rbxassetid://10709818125',['lucide-crop']='rbxassetid://10709818245',['lucide-cross']='rbxassetid://10709818399',['lucide-crosshair']='rbxassetid://10709818534',['lucide-crown']='rbxassetid://10709818626',['lucide-cup-soda']='rbxassetid://10709818763',['lucide-curly-braces']='rbxassetid://10709818847',['lucide-currency']='rbxassetid://10709818931',['lucide-database']='rbxassetid://10709818996',['lucide-delete']='rbxassetid://10709819059',['lucide-diamond']='rbxassetid://10709819149',['lucide-dice-1']='rbxassetid://10709819266',['lucide-dice-2']='rbxassetid://10709819361',['lucide-dice-3']='rbxassetid://10709819508',['lucide-dice-4']='rbxassetid://10709819670',['lucide-dice-5']='rbxassetid://10709819801',['lucide-dice-6']='rbxassetid://10709819896',['lucide-dices']='rbxassetid://10723343321',['lucide-diff']='rbxassetid://10723343416',['lucide-disc']='rbxassetid://10723343537',['lucide-divide']='rbxassetid://10723343805',['lucide-divide-circle']='rbxassetid://10723343636',['lucide-divide-square']='rbxassetid://10723343737',['lucide-dollar-sign']='rbxassetid://10723343958',['lucide-download']='rbxassetid://10723344270',['lucide-download-cloud']='rbxassetid://10723344088',['lucide-droplet']='rbxassetid://10723344432',['lucide-droplets']='rbxassetid://10734883356',['lucide-drumstick']='rbxassetid://10723344737',['lucide-edit']='rbxassetid://10734883598',['lucide-edit-2']='rbxassetid://10723344885',['lucide-edit-3']='rbxassetid://10723345088',['lucide-egg']='rbxassetid://10723345518',['lucide-egg-fried']='rbxassetid://10723345347',['lucide-electricity']='rbxassetid://10723345749',['lucide-electricity-off']='rbxassetid://10723345643',['lucide-equal']='rbxassetid://10723345990',['lucide-equal-not']='rbxassetid://10723345866',['lucide-eraser']='rbxassetid://10723346158',['lucide-euro']='rbxassetid://10723346372',['lucide-expand']='rbxassetid://10723346553',['lucide-external-link']='rbxassetid://10723346684',['lucide-eye']='rbxassetid://10723346959',['lucide-eye-off']='rbxassetid://10723346871',['lucide-factory']='rbxassetid://10723347051',['lucide-fan']='rbxassetid://10723354359',['lucide-fast-forward']='rbxassetid://10723354521',['lucide-feather']='rbxassetid://10723354671',['lucide-figma']='rbxassetid://10723354801',['lucide-file']='rbxassetid://10723374641',['lucide-file-archive']='rbxassetid://10723354921',['lucide-file-audio']='rbxassetid://10723355148',['lucide-file-audio-2']='rbxassetid://10723355026',['lucide-file-axis-3d']='rbxassetid://10723355272',['lucide-file-badge']='rbxassetid://10723355622',['lucide-file-badge-2']='rbxassetid://10723355451',['lucide-file-bar-chart']='rbxassetid://10723355887',['lucide-file-bar-chart-2']='rbxassetid://10723355746',['lucide-file-box']='rbxassetid://10723355989',['lucide-file-check']='rbxassetid://10723356210',['lucide-file-check-2']='rbxassetid://10723356100',['lucide-file-clock']='rbxassetid://10723356329',['lucide-file-code']='rbxassetid://10723356507',['lucide-file-cog']='rbxassetid://10723356830',['lucide-file-cog-2']='rbxassetid://10723356676',['lucide-file-diff']='rbxassetid://10723357039',['lucide-file-digit']='rbxassetid://10723357151',['lucide-file-down']='rbxassetid://10723357322',['lucide-file-edit']='rbxassetid://10723357495',['lucide-file-heart']='rbxassetid://10723357637',['lucide-file-image']='rbxassetid://10723357790',['lucide-file-input']='rbxassetid://10723357933',['lucide-file-json']='rbxassetid://10723364435',['lucide-file-json-2']='rbxassetid://10723364361',['lucide-file-key']='rbxassetid://10723364605',['lucide-file-key-2']='rbxassetid://10723364515',['lucide-file-line-chart']='rbxassetid://10723364725',['lucide-file-lock']='rbxassetid://10723364957',['lucide-file-lock-2']='rbxassetid://10723364861',['lucide-file-minus']='rbxassetid://10723365254',['lucide-file-minus-2']='rbxassetid://10723365086',['lucide-file-output']='rbxassetid://10723365457',['lucide-file-pie-chart']='rbxassetid://10723365598',['lucide-file-plus']='rbxassetid://10723365877',['lucide-file-plus-2']='rbxassetid://10723365766',['lucide-file-question']='rbxassetid://10723365987',['lucide-file-scan']='rbxassetid://10723366167',['lucide-file-search']='rbxassetid://10723366550',['lucide-file-search-2']='rbxassetid://10723366340',['lucide-file-signature']='rbxassetid://10723366741',['lucide-file-spreadsheet']='rbxassetid://10723366962',['lucide-file-symlink']='rbxassetid://10723367098',['lucide-file-terminal']='rbxassetid://10723367244',['lucide-file-text']='rbxassetid://10723367380',['lucide-file-type']='rbxassetid://10723367606',['lucide-file-type-2']='rbxassetid://10723367509',['lucide-file-up']='rbxassetid://10723367734',['lucide-file-video']='rbxassetid://10723373884',['lucide-file-video-2']='rbxassetid://10723367834',['lucide-file-volume']='rbxassetid://10723374172',['lucide-file-volume-2']='rbxassetid://10723374030',['lucide-file-warning']='rbxassetid://10723374276',['lucide-file-x']='rbxassetid://10723374544',['lucide-file-x-2']='rbxassetid://10723374378',['lucide-files']='rbxassetid://10723374759',['lucide-film']='rbxassetid://10723374981',['lucide-filter']='rbxassetid://10723375128',['lucide-fingerprint']='rbxassetid://10723375250',['lucide-flag']='rbxassetid://10723375890',['lucide-flag-off']='rbxassetid://10723375443',['lucide-flag-triangle-left']='rbxassetid://10723375608',['lucide-flag-triangle-right']='rbxassetid://10723375727',['lucide-flame']='rbxassetid://10723376114',['lucide-flashlight']='rbxassetid://10723376471',['lucide-flashlight-off']='rbxassetid://10723376365',['lucide-flask-conical']='rbxassetid://10734883986',['lucide-flask-round']='rbxassetid://10723376614',['lucide-flip-horizontal']='rbxassetid://10723376884',['lucide-flip-horizontal-2']='rbxassetid://10723376745',['lucide-flip-vertical']='rbxassetid://10723377138',['lucide-flip-vertical-2']='rbxassetid://10723377026',['lucide-flower']='rbxassetid://10747830374',['lucide-flower-2']='rbxassetid://10723377305',['lucide-focus']='rbxassetid://10723377537',['lucide-folder']='rbxassetid://10723387563',['lucide-folder-archive']='rbxassetid://10723384478',['lucide-folder-check']='rbxassetid://10723384605',['lucide-folder-clock']='rbxassetid://10723384731',['lucide-folder-closed']='rbxassetid://10723384893',['lucide-folder-cog']='rbxassetid://10723385213',['lucide-folder-cog-2']='rbxassetid://10723385036',['lucide-folder-down']='rbxassetid://10723385338',['lucide-folder-edit']='rbxassetid://10723385445',['lucide-folder-heart']='rbxassetid://10723385545',['lucide-folder-input']='rbxassetid://10723385721',['lucide-folder-key']='rbxassetid://10723385848',['lucide-folder-lock']='rbxassetid://10723386005',['lucide-folder-minus']='rbxassetid://10723386127',['lucide-folder-open']='rbxassetid://10723386277',['lucide-folder-output']='rbxassetid://10723386386',['lucide-folder-plus']='rbxassetid://10723386531',['lucide-folder-search']='rbxassetid://10723386787',['lucide-folder-search-2']='rbxassetid://10723386674',['lucide-folder-symlink']='rbxassetid://10723386930',['lucide-folder-tree']='rbxassetid://10723387085',['lucide-folder-up']='rbxassetid://10723387265',['lucide-folder-x']='rbxassetid://10723387448',['lucide-folders']='rbxassetid://10723387721',['lucide-form-input']='rbxassetid://10723387841',['lucide-forward']='rbxassetid://10723388016',['lucide-frame']='rbxassetid://10723394389',['lucide-framer']='rbxassetid://10723394565',['lucide-frown']='rbxassetid://10723394681',['lucide-fuel']='rbxassetid://10723394846',['lucide-function-square']='rbxassetid://10723395041',['lucide-gamepad']='rbxassetid://10723395457',['lucide-gamepad-2']='rbxassetid://10723395215',['lucide-gauge']='rbxassetid://10723395708',['lucide-gavel']='rbxassetid://10723395896',['lucide-gem']='rbxassetid://10723396000',['lucide-ghost']='rbxassetid://10723396107',['lucide-gift']='rbxassetid://10723396402',['lucide-gift-card']='rbxassetid://10723396225',['lucide-git-branch']='rbxassetid://10723396676',['lucide-git-branch-plus']='rbxassetid://10723396542',['lucide-git-commit']='rbxassetid://10723396812',['lucide-git-compare']='rbxassetid://10723396954',['lucide-git-fork']='rbxassetid://10723397049',['lucide-git-merge']='rbxassetid://10723397165',['lucide-git-pull-request']='rbxassetid://10723397431',['lucide-git-pull-request-closed']='rbxassetid://10723397268',['lucide-git-pull-request-draft']='rbxassetid://10734884302',['lucide-glass']='rbxassetid://10723397788',['lucide-glass-2']='rbxassetid://10723397529',['lucide-glass-water']='rbxassetid://10723397678',['lucide-glasses']='rbxassetid://10723397895',['lucide-globe']='rbxassetid://10723404337',['lucide-globe-2']='rbxassetid://10723398002',['lucide-grab']='rbxassetid://10723404472',['lucide-graduation-cap']='rbxassetid://10723404691',['lucide-grape']='rbxassetid://10723404822',['lucide-grid']='rbxassetid://10723404936',['lucide-grip-horizontal']='rbxassetid://10723405089',['lucide-grip-vertical']='rbxassetid://10723405236',['lucide-hammer']='rbxassetid://10723405360',['lucide-hand']='rbxassetid://10723405649',['lucide-hand-metal']='rbxassetid://10723405508',['lucide-hard-drive']='rbxassetid://10723405749',['lucide-hard-hat']='rbxassetid://10723405859',['lucide-hash']='rbxassetid://10723405975',['lucide-haze']='rbxassetid://10723406078',['lucide-headphones']='rbxassetid://10723406165',['lucide-heart']='rbxassetid://10723406885',['lucide-heart-crack']='rbxassetid://10723406299',['lucide-heart-handshake']='rbxassetid://10723406480',['lucide-heart-off']='rbxassetid://10723406662',['lucide-heart-pulse']='rbxassetid://10723406795',['lucide-help-circle']='rbxassetid://10723406988',['lucide-hexagon']='rbxassetid://10723407092',['lucide-highlighter']='rbxassetid://10723407192',['lucide-history']='rbxassetid://10723407335',['lucide-home']='rbxassetid://10723407389',['lucide-hourglass']='rbxassetid://10723407498',['lucide-ice-cream']='rbxassetid://10723414308',['lucide-image']='rbxassetid://10723415040',['lucide-image-minus']='rbxassetid://10723414487',['lucide-image-off']='rbxassetid://10723414677',['lucide-image-plus']='rbxassetid://10723414827',['lucide-import']='rbxassetid://10723415205',['lucide-inbox']='rbxassetid://10723415335',['lucide-indent']='rbxassetid://10723415494',['lucide-indian-rupee']='rbxassetid://10723415642',['lucide-infinity']='rbxassetid://10723415766',['lucide-info']='rbxassetid://10723415903',['lucide-inspect']='rbxassetid://10723416057',['lucide-italic']='rbxassetid://10723416195',['lucide-japanese-yen']='rbxassetid://10723416363',['lucide-joystick']='rbxassetid://10723416527',['lucide-key']='rbxassetid://10723416652',['lucide-keyboard']='rbxassetid://10723416765',['lucide-lamp']='rbxassetid://10723417513',['lucide-lamp-ceiling']='rbxassetid://10723416922',['lucide-lamp-desk']='rbxassetid://10723417016',['lucide-lamp-floor']='rbxassetid://10723417131',['lucide-lamp-wall-down']='rbxassetid://10723417240',['lucide-lamp-wall-up']='rbxassetid://10723417356',['lucide-landmark']='rbxassetid://10723417608',['lucide-languages']='rbxassetid://10723417703',['lucide-laptop']='rbxassetid://10723423881',['lucide-laptop-2']='rbxassetid://10723417797',['lucide-lasso']='rbxassetid://10723424235',['lucide-lasso-select']='rbxassetid://10723424058',['lucide-laugh']='rbxassetid://10723424372',['lucide-layers']='rbxassetid://10723424505',['lucide-layout']='rbxassetid://10723425376',['lucide-layout-dashboard']='rbxassetid://10723424646',['lucide-layout-grid']='rbxassetid://10723424838',['lucide-layout-list']='rbxassetid://10723424963',['lucide-layout-template']='rbxassetid://10723425187',['lucide-leaf']='rbxassetid://10723425539',['lucide-library']='rbxassetid://10723425615',['lucide-life-buoy']='rbxassetid://10723425685',['lucide-lightbulb']='rbxassetid://10723425852',['lucide-lightbulb-off']='rbxassetid://10723425762',['lucide-line-chart']='rbxassetid://10723426393',['lucide-link']='rbxassetid://10723426722',['lucide-link-2']='rbxassetid://10723426595',['lucide-link-2-off']='rbxassetid://10723426513',['lucide-list']='rbxassetid://10723433811',['lucide-list-checks']='rbxassetid://10734884548',['lucide-list-end']='rbxassetid://10723426886',['lucide-list-minus']='rbxassetid://10723426986',['lucide-list-music']='rbxassetid://10723427081',['lucide-list-ordered']='rbxassetid://10723427199',['lucide-list-plus']='rbxassetid://10723427334',['lucide-list-start']='rbxassetid://10723427494',['lucide-list-video']='rbxassetid://10723427619',['lucide-list-x']='rbxassetid://10723433655',['lucide-loader']='rbxassetid://10723434070',['lucide-loader-2']='rbxassetid://10723433935',['lucide-locate']='rbxassetid://10723434557',['lucide-locate-fixed']='rbxassetid://10723434236',['lucide-locate-off']='rbxassetid://10723434379',['lucide-lock']='rbxassetid://10723434711',['lucide-log-in']='rbxassetid://10723434830',['lucide-log-out']='rbxassetid://10723434906',['lucide-luggage']='rbxassetid://10723434993',['lucide-magnet']='rbxassetid://10723435069',['lucide-mail']='rbxassetid://10734885430',['lucide-mail-check']='rbxassetid://10723435182',['lucide-mail-minus']='rbxassetid://10723435261',['lucide-mail-open']='rbxassetid://10723435342',['lucide-mail-plus']='rbxassetid://10723435443',['lucide-mail-question']='rbxassetid://10723435515',['lucide-mail-search']='rbxassetid://10734884739',['lucide-mail-warning']='rbxassetid://10734885015',['lucide-mail-x']='rbxassetid://10734885247',['lucide-mails']='rbxassetid://10734885614',['lucide-map']='rbxassetid://10734886202',['lucide-map-pin']='rbxassetid://10734886004',['lucide-map-pin-off']='rbxassetid://10734885803',['lucide-maximize']='rbxassetid://10734886735',['lucide-maximize-2']='rbxassetid://10734886496',['lucide-medal']='rbxassetid://10734887072',['lucide-megaphone']='rbxassetid://10734887454',['lucide-megaphone-off']='rbxassetid://10734887311',['lucide-meh']='rbxassetid://10734887603',['lucide-menu']='rbxassetid://10734887784',['lucide-message-circle']='rbxassetid://10734888000',['lucide-message-square']='rbxassetid://10734888228',['lucide-mic']='rbxassetid://10734888864',['lucide-mic-2']='rbxassetid://10734888430',['lucide-mic-off']='rbxassetid://10734888646',['lucide-microscope']='rbxassetid://10734889106',['lucide-microwave']='rbxassetid://10734895076',['lucide-milestone']='rbxassetid://10734895310',['lucide-minimize']='rbxassetid://10734895698',['lucide-minimize-2']='rbxassetid://10734895530',['lucide-minus']='rbxassetid://10734896206',['lucide-minus-circle']='rbxassetid://10734895856',['lucide-minus-square']='rbxassetid://10734896029',['lucide-monitor']='rbxassetid://10734896881',['lucide-monitor-off']='rbxassetid://10734896360',['lucide-monitor-speaker']='rbxassetid://10734896512',['lucide-moon']='rbxassetid://10734897102',['lucide-more-horizontal']='rbxassetid://10734897250',['lucide-more-vertical']='rbxassetid://10734897387',['lucide-mountain']='rbxassetid://10734897956',['lucide-mountain-snow']='rbxassetid://10734897665',['lucide-mouse']='rbxassetid://10734898592',['lucide-mouse-pointer']='rbxassetid://10734898476',['lucide-mouse-pointer-2']='rbxassetid://10734898194',['lucide-mouse-pointer-click']='rbxassetid://10734898355',['lucide-move']='rbxassetid://10734900011',['lucide-move-3d']='rbxassetid://10734898756',['lucide-move-diagonal']='rbxassetid://10734899164',['lucide-move-diagonal-2']='rbxassetid://10734898934',['lucide-move-horizontal']='rbxassetid://10734899414',['lucide-move-vertical']='rbxassetid://10734899821',['lucide-music']='rbxassetid://10734905958',['lucide-music-2']='rbxassetid://10734900215',['lucide-music-3']='rbxassetid://10734905665',['lucide-music-4']='rbxassetid://10734905823',['lucide-navigation']='rbxassetid://10734906744',['lucide-navigation-2']='rbxassetid://10734906332',['lucide-navigation-2-off']='rbxassetid://10734906144',['lucide-navigation-off']='rbxassetid://10734906580',['lucide-network']='rbxassetid://10734906975',['lucide-newspaper']='rbxassetid://10734907168',['lucide-octagon']='rbxassetid://10734907361',['lucide-option']='rbxassetid://10734907649',['lucide-outdent']='rbxassetid://10734907933',['lucide-package']='rbxassetid://10734909540',['lucide-package-2']='rbxassetid://10734908151',['lucide-package-check']='rbxassetid://10734908384',['lucide-package-minus']='rbxassetid://10734908626',['lucide-package-open']='rbxassetid://10734908793',['lucide-package-plus']='rbxassetid://10734909016',['lucide-package-search']='rbxassetid://10734909196',['lucide-package-x']='rbxassetid://10734909375',['lucide-paint-bucket']='rbxassetid://10734909847',['lucide-paintbrush']='rbxassetid://10734910187',['lucide-paintbrush-2']='rbxassetid://10734910030',['lucide-palette']='rbxassetid://10734910430',['lucide-palmtree']='rbxassetid://10734910680',['lucide-paperclip']='rbxassetid://10734910927',['lucide-party-popper']='rbxassetid://10734918735',['lucide-pause']='rbxassetid://10734919336',['lucide-pause-circle']='rbxassetid://10735024209',['lucide-pause-octagon']='rbxassetid://10734919143',['lucide-pen-tool']='rbxassetid://10734919503',['lucide-pencil']='rbxassetid://10734919691',['lucide-percent']='rbxassetid://10734919919',['lucide-person-standing']='rbxassetid://10734920149',['lucide-phone']='rbxassetid://10734921524',['lucide-phone-call']='rbxassetid://10734920305',['lucide-phone-forwarded']='rbxassetid://10734920508',['lucide-phone-incoming']='rbxassetid://10734920694',['lucide-phone-missed']='rbxassetid://10734920845',['lucide-phone-off']='rbxassetid://10734921077',['lucide-phone-outgoing']='rbxassetid://10734921288',['lucide-pie-chart']='rbxassetid://10734921727',['lucide-piggy-bank']='rbxassetid://10734921935',['lucide-pin']='rbxassetid://10734922324',['lucide-pin-off']='rbxassetid://10734922180',['lucide-pipette']='rbxassetid://10734922497',['lucide-pizza']='rbxassetid://10734922774',['lucide-plane']='rbxassetid://10734922971',['lucide-play']='rbxassetid://10734923549',['lucide-play-circle']='rbxassetid://10734923214',['lucide-plus']='rbxassetid://10734924532',['lucide-plus-circle']='rbxassetid://10734923868',['lucide-plus-square']='rbxassetid://10734924219',['lucide-podcast']='rbxassetid://10734929553',['lucide-pointer']='rbxassetid://10734929723',['lucide-pound-sterling']='rbxassetid://10734929981',['lucide-power']='rbxassetid://10734930466',['lucide-power-off']='rbxassetid://10734930257',['lucide-printer']='rbxassetid://10734930632',['lucide-puzzle']='rbxassetid://10734930886',['lucide-quote']='rbxassetid://10734931234',['lucide-radio']='rbxassetid://10734931596',['lucide-radio-receiver']='rbxassetid://10734931402',['lucide-rectangle-horizontal']='rbxassetid://10734931777',['lucide-rectangle-vertical']='rbxassetid://10734932081',['lucide-recycle']='rbxassetid://10734932295',['lucide-redo']='rbxassetid://10734932822',['lucide-redo-2']='rbxassetid://10734932586',['lucide-refresh-ccw']='rbxassetid://10734933056',['lucide-refresh-cw']='rbxassetid://10734933222',['lucide-refrigerator']='rbxassetid://10734933465',['lucide-regex']='rbxassetid://10734933655',['lucide-repeat']='rbxassetid://10734933966',['lucide-repeat-1']='rbxassetid://10734933826',['lucide-reply']='rbxassetid://10734934252',['lucide-reply-all']='rbxassetid://10734934132',['lucide-rewind']='rbxassetid://10734934347',['lucide-rocket']='rbxassetid://10734934585',['lucide-rocking-chair']='rbxassetid://10734939942',['lucide-rotate-3d']='rbxassetid://10734940107',['lucide-rotate-ccw']='rbxassetid://10734940376',['lucide-rotate-cw']='rbxassetid://10734940654',['lucide-rss']='rbxassetid://10734940825',['lucide-ruler']='rbxassetid://10734941018',['lucide-russian-ruble']='rbxassetid://10734941199',['lucide-sailboat']='rbxassetid://10734941354',['lucide-save']='rbxassetid://10734941499',['lucide-scale']='rbxassetid://10734941912',['lucide-scale-3d']='rbxassetid://10734941739',['lucide-scaling']='rbxassetid://10734942072',['lucide-scan']='rbxassetid://10734942565',['lucide-scan-face']='rbxassetid://10734942198',['lucide-scan-line']='rbxassetid://10734942351',['lucide-scissors']='rbxassetid://10734942778',['lucide-screen-share']='rbxassetid://10734943193',['lucide-screen-share-off']='rbxassetid://10734942967',['lucide-scroll']='rbxassetid://10734943448',['lucide-search']='rbxassetid://10734943674',['lucide-send']='rbxassetid://10734943902',['lucide-separator-horizontal']='rbxassetid://10734944115',['lucide-separator-vertical']='rbxassetid://10734944326',['lucide-server']='rbxassetid://10734949856',['lucide-server-cog']='rbxassetid://10734944444',['lucide-server-crash']='rbxassetid://10734944554',['lucide-server-off']='rbxassetid://10734944668',['lucide-settings']='rbxassetid://10734950309',['lucide-settings-2']='rbxassetid://10734950020',['lucide-share']='rbxassetid://10734950813',['lucide-share-2']='rbxassetid://10734950553',['lucide-sheet']='rbxassetid://10734951038',['lucide-shield']='rbxassetid://10734951847',['lucide-shield-alert']='rbxassetid://10734951173',['lucide-shield-check']='rbxassetid://10734951367',['lucide-shield-close']='rbxassetid://10734951535',['lucide-shield-off']='rbxassetid://10734951684',['lucide-shirt']='rbxassetid://10734952036',['lucide-shopping-bag']='rbxassetid://10734952273',['lucide-shopping-cart']='rbxassetid://10734952479',['lucide-shovel']='rbxassetid://10734952773',['lucide-shower-head']='rbxassetid://10734952942',['lucide-shrink']='rbxassetid://10734953073',['lucide-shrub']='rbxassetid://10734953241',['lucide-shuffle']='rbxassetid://10734953451',['lucide-sidebar']='rbxassetid://10734954301',['lucide-sidebar-close']='rbxassetid://10734953715',['lucide-sidebar-open']='rbxassetid://10734954000',['lucide-sigma']='rbxassetid://10734954538',['lucide-signal']='rbxassetid://10734961133',['lucide-signal-high']='rbxassetid://10734954807',['lucide-signal-low']='rbxassetid://10734955080',['lucide-signal-medium']='rbxassetid://10734955336',['lucide-signal-zero']='rbxassetid://10734960878',['lucide-siren']='rbxassetid://10734961284',['lucide-skip-back']='rbxassetid://10734961526',['lucide-skip-forward']='rbxassetid://10734961809',['lucide-skull']='rbxassetid://10734962068',['lucide-slack']='rbxassetid://10734962339',['lucide-slash']='rbxassetid://10734962600',['lucide-slice']='rbxassetid://10734963024',['lucide-sliders']='rbxassetid://10734963400',['lucide-sliders-horizontal']='rbxassetid://10734963191',['lucide-smartphone']='rbxassetid://10734963940',['lucide-smartphone-charging']='rbxassetid://10734963671',['lucide-smile']='rbxassetid://10734964441',['lucide-smile-plus']='rbxassetid://10734964188',['lucide-snowflake']='rbxassetid://10734964600',['lucide-sofa']='rbxassetid://10734964852',['lucide-sort-asc']='rbxassetid://10734965115',['lucide-sort-desc']='rbxassetid://10734965287',['lucide-speaker']='rbxassetid://10734965419',['lucide-sprout']='rbxassetid://10734965572',['lucide-square']='rbxassetid://10734965702',['lucide-star']='rbxassetid://10734966248',['lucide-star-half']='rbxassetid://10734965897',['lucide-star-off']='rbxassetid://10734966097',['lucide-stethoscope']='rbxassetid://10734966384',['lucide-sticker']='rbxassetid://10734972234',['lucide-sticky-note']='rbxassetid://10734972463',['lucide-stop-circle']='rbxassetid://10734972621',['lucide-stretch-horizontal']='rbxassetid://10734972862',['lucide-stretch-vertical']='rbxassetid://10734973130',['lucide-strikethrough']='rbxassetid://10734973290',['lucide-subscript']='rbxassetid://10734973457',['lucide-sun']='rbxassetid://10734974297',['lucide-sun-dim']='rbxassetid://10734973645',['lucide-sun-medium']='rbxassetid://10734973778',['lucide-sun-moon']='rbxassetid://10734973999',['lucide-sun-snow']='rbxassetid://10734974130',['lucide-sunrise']='rbxassetid://10734974522',['lucide-sunset']='rbxassetid://10734974689',['lucide-superscript']='rbxassetid://10734974850',['lucide-swiss-franc']='rbxassetid://10734975024',['lucide-switch-camera']='rbxassetid://10734975214',['lucide-sword']='rbxassetid://10734975486',['lucide-swords']='rbxassetid://10734975692',['lucide-syringe']='rbxassetid://10734975932',['lucide-table']='rbxassetid://10734976230',['lucide-table-2']='rbxassetid://10734976097',['lucide-tablet']='rbxassetid://10734976394',['lucide-tag']='rbxassetid://10734976528',['lucide-tags']='rbxassetid://10734976739',['lucide-target']='rbxassetid://10734977012',['lucide-tent']='rbxassetid://10734981750',['lucide-terminal']='rbxassetid://10734982144',['lucide-terminal-square']='rbxassetid://10734981995',['lucide-text-cursor']='rbxassetid://10734982395',['lucide-text-cursor-input']='rbxassetid://10734982297',['lucide-thermometer']='rbxassetid://10734983134',['lucide-thermometer-snowflake']='rbxassetid://10734982571',['lucide-thermometer-sun']='rbxassetid://10734982771',['lucide-thumbs-down']='rbxassetid://10734983359',['lucide-thumbs-up']='rbxassetid://10734983629',['lucide-ticket']='rbxassetid://10734983868',['lucide-timer']='rbxassetid://10734984606',['lucide-timer-off']='rbxassetid://10734984138',['lucide-timer-reset']='rbxassetid://10734984355',['lucide-toggle-left']='rbxassetid://10734984834',['lucide-toggle-right']='rbxassetid://10734985040',['lucide-tornado']='rbxassetid://10734985247',['lucide-toy-brick']='rbxassetid://10747361919',['lucide-train']='rbxassetid://10747362105',['lucide-trash']='rbxassetid://10747362393',['lucide-trash-2']='rbxassetid://10747362241',['lucide-tree-deciduous']='rbxassetid://10747362534',['lucide-tree-pine']='rbxassetid://10747362748',['lucide-trees']='rbxassetid://10747363016',['lucide-trending-down']='rbxassetid://10747363205',['lucide-trending-up']='rbxassetid://10747363465',['lucide-triangle']='rbxassetid://10747363621',['lucide-trophy']='rbxassetid://10747363809',['lucide-truck']='rbxassetid://10747364031',['lucide-tv']='rbxassetid://10747364593',['lucide-tv-2']='rbxassetid://10747364302',['lucide-type']='rbxassetid://10747364761',['lucide-umbrella']='rbxassetid://10747364971',['lucide-underline']='rbxassetid://10747365191',['lucide-undo']='rbxassetid://10747365484',['lucide-undo-2']='rbxassetid://10747365359',['lucide-unlink']='rbxassetid://10747365771',['lucide-unlink-2']='rbxassetid://10747397871',['lucide-unlock']='rbxassetid://10747366027',['lucide-upload']='rbxassetid://10747366434',['lucide-upload-cloud']='rbxassetid://10747366266',['lucide-usb']='rbxassetid://10747366606',['lucide-user']='rbxassetid://10747373176',['lucide-user-check']='rbxassetid://10747371901',['lucide-user-cog']='rbxassetid://10747372167',['lucide-user-minus']='rbxassetid://10747372346',['lucide-user-plus']='rbxassetid://10747372702',['lucide-user-x']='rbxassetid://10747372992',['lucide-users']='rbxassetid://10747373426',['lucide-utensils']='rbxassetid://10747373821',['lucide-utensils-crossed']='rbxassetid://10747373629',['lucide-venetian-mask']='rbxassetid://10747374003',['lucide-verified']='rbxassetid://10747374131',['lucide-vibrate']='rbxassetid://10747374489',['lucide-vibrate-off']='rbxassetid://10747374269',['lucide-video']='rbxassetid://10747374938',['lucide-video-off']='rbxassetid://10747374721',['lucide-view']='rbxassetid://10747375132',['lucide-voicemail']='rbxassetid://10747375281',['lucide-volume']='rbxassetid://10747376008',['lucide-volume-1']='rbxassetid://10747375450',['lucide-volume-2']='rbxassetid://10747375679',['lucide-volume-x']='rbxassetid://10747375880',['lucide-wallet']='rbxassetid://10747376205',['lucide-wand']='rbxassetid://10747376565',['lucide-wand-2']='rbxassetid://10747376349',['lucide-watch']='rbxassetid://10747376722',['lucide-waves']='rbxassetid://10747376931',['lucide-webcam']='rbxassetid://10747381992',['lucide-wifi']='rbxassetid://10747382504',['lucide-wifi-off']='rbxassetid://10747382268',['lucide-wind']='rbxassetid://10747382750',['lucide-wrap-text']='rbxassetid://10747383065',['lucide-wrench']='rbxassetid://10747383470',['lucide-x']='rbxassetid://10747384394',['lucide-x-circle']='rbxassetid://10747383819',['lucide-x-octagon']='rbxassetid://10747384037',['lucide-x-square']='rbxassetid://10747384217',['lucide-zoom-in']='rbxassetid://10747384552',['lucide-zoom-out']='rbxassetid://10747384679'}}end,[30]=function()local aa,ab,ac,ad,ae=b(30)local af={SingleMotor=ac(ab.SingleMotor),GroupMotor=ac(ab.GroupMotor),Instant=ac(ab.Instant),Linear=ac(ab.Linear),Spring=ac(ab.Spring),isMotor=ac(ab.isMotor)}return af end,[31]=function()local aa,ab,ac,ad,ae=b(31)local af,ag,ah,ai=game:GetService'RunService',ac(ab.Parent.Signal),function()end,{}ai.__index=ai function ai.new()return setmetatable({_onStep=ag.new(),_onStart=ag.new(),_onComplete=ag.new()},ai)end function ai.onStep(aj,c)return aj._onStep:connect(c)end function ai.onStart(aj,c)return aj._onStart:connect(c)end function ai.onComplete(aj,c)return aj._onComplete:connect(c)end function ai.start(aj)if not aj._connection then aj._connection=af.RenderStepped:Connect(function(c)aj:step(c)end)end end function ai.stop(aj)if aj._connection then aj._connection:Disconnect()aj._connection=nil end end ai.destroy=ai.stop ai.step=ah ai.getValue=ah ai.setGoal=ah function ai.__tostring(aj)return'Motor'end return ai end,[32]=function()local aa,ab,ac,ad,ae=b(32)return function()local af,ag=game:GetService'RunService',ac(ab.Parent.BaseMotor)describe('connection management',function()local ah=ag.new()it('should hook up connections on :start()',function()ah:start()expect(typeof(ah._connection)).to.equal'RBXScriptConnection'end)it('should remove connections on :stop() or :destroy()',function()ah:stop()expect(ah._connection).to.equal(nil)end)end)it('should call :step() with deltaTime',function()local ah,ai=(ag.new())function ah.step(aj,...)ai={...}ah:stop()end ah:start()local aj=af.RenderStepped:Wait()af.RenderStepped:Wait()expect(ai).to.be.ok()expect(ai[1]).to.equal(aj)end)end end,[33]=function()local aa,ab,ac,ad,ae=b(33)local af,ag,ah=ac(ab.Parent.BaseMotor),ac(ab.Parent.SingleMotor),ac(ab.Parent.isMotor)local ai=setmetatable({},af)ai.__index=ai local aj=function(aj)if ah(aj)then return aj end local c=typeof(aj)if c=='number'then return ag.new(aj,false)elseif c=='table'then return ai.new(aj,false)end error(('Unable to convert %q to motor; type %s is unsupported'):format(aj,c),2)end function ai.new(c,d)assert(c,'Missing argument #1: initialValues')assert(typeof(c)=='table','initialValues must be a table!')assert(not c.step,[[initialValues contains disallowed property "step". Did you mean to put a table of values here?]])local e=setmetatable(af.new(),ai)if d~=nil then e._useImplicitConnections=d else e._useImplicitConnections=true end e._complete=true e._motors={}for f,g in pairs(c)do e._motors[f]=aj(g)end return e end function ai.step(c,d)if c._complete then return true end local e=true for f,g in pairs(c._motors)do local h=g:step(d)if not h then e=false end end c._onStep:fire(c:getValue())if e then if c._useImplicitConnections then c:stop()end c._complete=true c._onComplete:fire()end return e end function ai.setGoal(c,d)assert(not d.step,[[goals contains disallowed property "step". Did you mean to put a table of goals here?]])c._complete=false c._onStart:fire()for e,f in pairs(d)do local g=assert(c._motors[e],('Unknown motor for key %s'):format(e))g:setGoal(f)end if c._useImplicitConnections then c:start()end end function ai.getValue(c)local d={}for e,f in pairs(c._motors)do d[e]=f:getValue()end return d end function ai.__tostring(c)return'Motor(Group)'end return ai end,[34]=function()local aa,ab,ac,ad,ae=b(34)return function()local af,ag,ah=ac(ab.Parent.GroupMotor),ac(ab.Parent.Instant),ac(ab.Parent.Spring)it('should complete when all child motors are complete',function()local ai=af.new({A=1,B=2},false)expect(ai._complete).to.equal(true)ai:setGoal{A=ag.new(3),B=ah.new(4,{frequency=7.5,dampingRatio=1})}expect(ai._complete).to.equal(false)ai:step(1.6666666666666665E-2)expect(ai._complete).to.equal(false)for aj=1,30 do ai:step(1.6666666666666665E-2)end expect(ai._complete).to.equal(true)end)it('should start when the goal is set',function()local ai,aj=af.new({A=0},false),false ai:onStart(function()aj=not aj end)ai:setGoal{A=ag.new(1)}expect(aj).to.equal(true)ai:setGoal{A=ag.new(1)}expect(aj).to.equal(false)end)it('should properly return all values',function()local ai=af.new({A=1,B=2},false)local aj=ai:getValue()expect(aj.A).to.equal(1)expect(aj.B).to.equal(2)end)it('should error when a goal is given to GroupMotor.new',function()local ai=pcall(function()af.new(ag.new(0))end)expect(ai).to.equal(false)end)it([[should error when a single goal is provided to GroupMotor:step]],function()local ai=pcall(function()af.new{a=1}:setGoal(ag.new(0))end)expect(ai).to.equal(false)end)end end,[35]=function()local aa,ab,ac,ad,ae=b(35)local af={}af.__index=af function af.new(ag)return setmetatable({_targetValue=ag},af)end function af.step(ag)return{complete=true,value=ag._targetValue}end return af end,[36]=function()local aa,ab,ac,ad,ae=b(36)return function()local af=ac(ab.Parent.Instant)it('should return a completed state with the provided value',function()local ag=af.new(1.23)local ah=ag:step(0.1,{value=0,complete=false})expect(ah.complete).to.equal(true)expect(ah.value).to.equal(1.23)end)end end,[37]=function()local aa,ab,ac,ad,ae=b(37)local af={}af.__index=af function af.new(ag,ah)assert(ag,'Missing argument #1: targetValue')ah=ah or{}return setmetatable({_targetValue=ag,_velocity=ah.velocity or 1},af)end function af.step(ag,ah,ai)local aj,c,d=ah.value,ag._velocity,ag._targetValue local e=ai*c local f=e>=math.abs(d-aj)aj=aj+e*(d>aj and 1 or-1)if f then aj=ag._targetValue c=0 end return{complete=f,value=aj,velocity=c}end return af end,[38]=function()local aa,ab,ac,ad,ae=b(38)return function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Linear)describe('completed state',function()local ah,ai=af.new(0,false),ag.new(1,{velocity=1})ah:setGoal(ai)for aj=1,60 do ah:step(1.6666666666666665E-2)end it('should complete',function()expect(ah._state.complete).to.equal(true)end)it('should be exactly the goal value when completed',function()expect(ah._state.value).to.equal(1)end)end)describe('uncompleted state',function()local ah,ai=af.new(0,false),ag.new(1,{velocity=1})ah:setGoal(ai)for aj=1,59 do ah:step(1.6666666666666665E-2)end it('should be uncomplete',function()expect(ah._state.complete).to.equal(false)end)end)describe('negative velocity',function()local ah,ai=af.new(1,false),ag.new(0,{velocity=1})ah:setGoal(ai)for aj=1,60 do ah:step(1.6666666666666665E-2)end it('should complete',function()expect(ah._state.complete).to.equal(true)end)it('should be exactly the goal value when completed',function()expect(ah._state.value).to.equal(0)end)end)end end,[39]=function()local aa,ab,ac,ad,ae=b(39)local af={}af.__index=af function af.new(ag,ah)return setmetatable({signal=ag,connected=true,_handler=ah},af)end function af.disconnect(ag)if ag.connected then ag.connected=false for ah,ai in pairs(ag.signal._connections)do if ai==ag then table.remove(ag.signal._connections,ah)return end end end end local ag={}ag.__index=ag function ag.new()return setmetatable({_connections={},_threads={}},ag)end function ag.fire(ah,...)for ai,aj in pairs(ah._connections)do aj._handler(...)end for c,d in pairs(ah._threads)do coroutine.resume(d,...)end ah._threads={}end function ag.connect(ah,aj)local c=af.new(ah,aj)table.insert(ah._connections,c)return c end function ag.wait(ah)table.insert(ah._threads,coroutine.running())return coroutine.yield()end return ag end,[40]=function()local aa,ab,ac,ad,ae=b(40)return function()local af=ac(ab.Parent.Signal)it('should invoke all connections, instantly',function()local ag,ah,aj=(af.new())ag:connect(function(c)ah=c end)ag:connect(function(c)aj=c end)ag:fire'hello'expect(ah).to.equal'hello'expect(aj).to.equal'hello'end)it('should return values when :wait() is called',function()local ag=af.new()spawn(function()ag:fire(123,'hello')end)local ah,aj=ag:wait()expect(ah).to.equal(123)expect(aj).to.equal'hello'end)it('should properly handle disconnections',function()local ag,ah=af.new(),false local aj=ag:connect(function()ah=true end)aj:disconnect()ag:fire()expect(ah).to.equal(false)end)end end,[41]=function()local aa,ab,ac,ad,ae=b(41)local af=ac(ab.Parent.BaseMotor)local ag=setmetatable({},af)ag.__index=ag function ag.new(ah,aj)assert(ah,'Missing argument #1: initialValue')assert(typeof(ah)=='number','initialValue must be a number!')local c=setmetatable(af.new(),ag)if aj~=nil then c._useImplicitConnections=aj else c._useImplicitConnections=true end c._goal=nil c._state={complete=true,value=ah}return c end function ag.step(ah,aj)if ah._state.complete then return true end local c=ah._goal:step(ah._state,aj)ah._state=c ah._onStep:fire(c.value)if c.complete then if ah._useImplicitConnections then ah:stop()end ah._onComplete:fire()end return c.complete end function ag.getValue(ah)return ah._state.value end function ag.setGoal(ah,aj)ah._state.complete=false ah._goal=aj ah._onStart:fire()if ah._useImplicitConnections then ah:start()end end function ag.__tostring(ah)return'Motor(Single)'end return ag end,[42]=function()local aa,ab,ac,ad,ae=b(42)return function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Instant)it('should assign new state on step',function()local ah=af.new(0,false)ah:setGoal(ag.new(5))ah:step(1.6666666666666665E-2)expect(ah._state.complete).to.equal(true)expect(ah._state.value).to.equal(5)end)it([[should invoke onComplete listeners when the goal is completed]],function()local ah,aj=af.new(0,false),false ah:onComplete(function()aj=true end)ah:setGoal(ag.new(5))ah:step(1.6666666666666665E-2)expect(aj).to.equal(true)end)it('should start when the goal is set',function()local ah,aj=af.new(0,false),false ah:onStart(function()aj=not aj end)ah:setGoal(ag.new(5))expect(aj).to.equal(true)ah:setGoal(ag.new(5))expect(aj).to.equal(false)end)end end,[43]=function()local aa,ab,ac,ad,ae=b(43)local af,ag,ah,aj=0.001,0.001,0.0001,{}aj.__index=aj function aj.new(c,d)assert(c,'Missing argument #1: targetValue')d=d or{}return setmetatable({_targetValue=c,_frequency=d.frequency or 4,_dampingRatio=d.dampingRatio or 1},aj)end function aj.step(c,d,e)local f,g,h,i,j=c._dampingRatio,c._frequency*2*math.pi,c._targetValue,d.value,d.velocity or 0 local k,l,m,n=i-h,(math.exp(-f*g*e))if f==1 then m=(k*(1+g*e)+j*e)*l+h n=(j*(1-g*e)-k*(g*g*e))*l elseif f<1 then local o=math.sqrt(1-f*f)local p,s,t=math.cos(g*o*e),(math.sin(g*o*e))if o>ah then t=s/o else local u=e*g t=u+((u*u)*(o*o)*(o*o)/20-o*o)*(u*u*u)/6 end local u if g*o>ah then u=s/(g*o)else local v=g*o u=e+((e*e)*(v*v)*(v*v)/20-v*v)*(e*e*e)/6 end m=(k*(p+f*t)+j*u)*l+h n=(j*(p-t*f)-k*(t*g))*l else local o=math.sqrt(f*f-1)local p,s=-g*(f-o),-g*(f+o)local t=(j-k*p)/(2*g*o)local u=k-t local v,w=u*math.exp(p*e),t*math.exp(s*e)m=v+w+h n=v*p+w*s end local o=math.abs(n)<af and math.abs(m-h)<ag return{complete=o,value=o and h or m,velocity=n}end return aj end,[44]=function()local aa,ab,ac,ad,ae=b(44)return function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Spring)describe('completed state',function()local ah,aj=af.new(0,false),ag.new(1,{frequency=2,dampingRatio=0.75})ah:setGoal(aj)for c=1,100 do ah:step(1.6666666666666665E-2)end it('should complete',function()expect(ah._state.complete).to.equal(true)end)it('should be exactly the goal value when completed',function()expect(ah._state.value).to.equal(1)end)end)it('should inherit velocity',function()local ah=af.new(0,false)ah._state={complete=false,value=0,velocity=-5}local aj=ag.new(1,{frequency=2,dampingRatio=1})ah:setGoal(aj)ah:step(1.6666666666666665E-2)expect(ah._state.velocity<0).to.equal(true)end)end end,[45]=function()local aa,ab,ac,ad,ae=b(45)local af=function(af)local ag=tostring(af):match'^Motor%((.+)%)$'if ag then return true,ag else return false end end return af end,[46]=function()local aa,ab,ac,ad,ae=b(46)return function()local af,ag,ah=ac(ab.Parent.isMotor),ac(ab.Parent.SingleMotor),ac(ab.Parent.GroupMotor)local aj,c=ag.new(0),ah.new{}it('should properly detect motors',function()expect(af(aj)).to.equal(true)expect(af(c)).to.equal(true)end)it("shouldn't detect things that aren't motors",function()expect(af{}).to.equal(false)end)it('should return the proper motor type',function()local d,e=af(aj)local f,g=af(c)expect(e).to.equal'Single'expect(g).to.equal'Group'end)end end,[47]=function()local aa,ab,ac,ad,ae=b(47)local af={Names={'Dark','Darker','Light','Aqua','Amethyst','Rose'}}for ag,ah in next,ab:GetChildren()do local aj=ac(ah)af[aj.Name]=aj end return af end,[48]=function()local aa,ab,ac,ad,ae=b(48)return{Name='Amethyst',Accent=Color3.fromRGB(97,62,167),AcrylicMain=Color3.fromRGB(20,20,20),AcrylicBorder=Color3.fromRGB(110,90,130),AcrylicGradient=ColorSequence.new(Color3.fromRGB(85,57,139),Color3.fromRGB(40,25,65)),AcrylicNoise=0.92,TitleBarLine=Color3.fromRGB(95,75,110),Tab=Color3.fromRGB(160,140,180),Element=Color3.fromRGB(140,120,160),ElementBorder=Color3.fromRGB(60,50,70),InElementBorder=Color3.fromRGB(100,90,110),ElementTransparency=0.87,ToggleSlider=Color3.fromRGB(140,120,160),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(140,120,160),DropdownFrame=Color3.fromRGB(170,160,200),DropdownHolder=Color3.fromRGB(60,45,80),DropdownBorder=Color3.fromRGB(50,40,65),DropdownOption=Color3.fromRGB(140,120,160),Keybind=Color3.fromRGB(140,120,160),Input=Color3.fromRGB(140,120,160),InputFocused=Color3.fromRGB(20,10,30),InputIndicator=Color3.fromRGB(170,150,190),Dialog=Color3.fromRGB(60,45,80),DialogHolder=Color3.fromRGB(45,30,65),DialogHolderLine=Color3.fromRGB(40,25,60),DialogButton=Color3.fromRGB(60,45,80),DialogButtonBorder=Color3.fromRGB(95,80,110),DialogBorder=Color3.fromRGB(85,70,100),DialogInput=Color3.fromRGB(70,55,85),DialogInputLine=Color3.fromRGB(175,160,190),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(140,120,160),HoverChange=0.04}end,[49]=function()local aa,ab,ac,ad,ae=b(49)return{Name='Aqua',Accent=Color3.fromRGB(60,165,165),AcrylicMain=Color3.fromRGB(20,20,20),AcrylicBorder=Color3.fromRGB(50,100,100),AcrylicGradient=ColorSequence.new(Color3.fromRGB(60,140,140),Color3.fromRGB(40,80,80)),AcrylicNoise=0.92,TitleBarLine=Color3.fromRGB(60,120,120),Tab=Color3.fromRGB(140,180,180),Element=Color3.fromRGB(110,160,160),ElementBorder=Color3.fromRGB(40,70,70),InElementBorder=Color3.fromRGB(80,110,110),ElementTransparency=0.84,ToggleSlider=Color3.fromRGB(110,160,160),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(110,160,160),DropdownFrame=Color3.fromRGB(160,200,200),DropdownHolder=Color3.fromRGB(40,80,80),DropdownBorder=Color3.fromRGB(40,65,65),DropdownOption=Color3.fromRGB(110,160,160),Keybind=Color3.fromRGB(110,160,160),Input=Color3.fromRGB(110,160,160),InputFocused=Color3.fromRGB(20,10,30),InputIndicator=Color3.fromRGB(130,170,170),Dialog=Color3.fromRGB(40,80,80),DialogHolder=Color3.fromRGB(30,60,60),DialogHolderLine=Color3.fromRGB(25,50,50),DialogButton=Color3.fromRGB(40,80,80),DialogButtonBorder=Color3.fromRGB(80,110,110),DialogBorder=Color3.fromRGB(50,100,100),DialogInput=Color3.fromRGB(45,90,90),DialogInputLine=Color3.fromRGB(130,170,170),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(110,160,160),HoverChange=0.04}end,[50]=function()local aa,ab,ac,ad,ae=b(50)return{Name='Dark',Accent=Color3.fromRGB(96,205,255),AcrylicMain=Color3.fromRGB(60,60,60),AcrylicBorder=Color3.fromRGB(90,90,90),AcrylicGradient=ColorSequence.new(Color3.fromRGB(40,40,40),Color3.fromRGB(40,40,40)),AcrylicNoise=0.9,TitleBarLine=Color3.fromRGB(75,75,75),Tab=Color3.fromRGB(120,120,120),Element=Color3.fromRGB(120,120,120),ElementBorder=Color3.fromRGB(35,35,35),InElementBorder=Color3.fromRGB(90,90,90),ElementTransparency=0.87,ToggleSlider=Color3.fromRGB(120,120,120),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(120,120,120),DropdownFrame=Color3.fromRGB(160,160,160),DropdownHolder=Color3.fromRGB(45,45,45),DropdownBorder=Color3.fromRGB(35,35,35),DropdownOption=Color3.fromRGB(120,120,120),Keybind=Color3.fromRGB(120,120,120),Input=Color3.fromRGB(160,160,160),InputFocused=Color3.fromRGB(10,10,10),InputIndicator=Color3.fromRGB(150,150,150),Dialog=Color3.fromRGB(45,45,45),DialogHolder=Color3.fromRGB(35,35,35),DialogHolderLine=Color3.fromRGB(30,30,30),DialogButton=Color3.fromRGB(45,45,45),DialogButtonBorder=Color3.fromRGB(80,80,80),DialogBorder=Color3.fromRGB(70,70,70),DialogInput=Color3.fromRGB(55,55,55),DialogInputLine=Color3.fromRGB(160,160,160),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(120,120,120),HoverChange=0.07}end,[51]=function()local aa,ab,ac,ad,ae=b(51)return{Name='Darker',Accent=Color3.fromRGB(72,138,182),AcrylicMain=Color3.fromRGB(30,30,30),AcrylicBorder=Color3.fromRGB(60,60,60),AcrylicGradient=ColorSequence.new(Color3.fromRGB(25,25,25),Color3.fromRGB(15,15,15)),AcrylicNoise=0.94,TitleBarLine=Color3.fromRGB(65,65,65),Tab=Color3.fromRGB(100,100,100),Element=Color3.fromRGB(70,70,70),ElementBorder=Color3.fromRGB(25,25,25),InElementBorder=Color3.fromRGB(55,55,55),ElementTransparency=0.82,DropdownFrame=Color3.fromRGB(120,120,120),DropdownHolder=Color3.fromRGB(35,35,35),DropdownBorder=Color3.fromRGB(25,25,25),Dialog=Color3.fromRGB(35,35,35),DialogHolder=Color3.fromRGB(25,25,25),DialogHolderLine=Color3.fromRGB(20,20,20),DialogButton=Color3.fromRGB(35,35,35),DialogButtonBorder=Color3.fromRGB(55,55,55),DialogBorder=Color3.fromRGB(50,50,50),DialogInput=Color3.fromRGB(45,45,45),DialogInputLine=Color3.fromRGB(120,120,120)}end,[52]=function()local aa,ab,ac,ad,ae=b(52)return{Name='Light',Accent=Color3.fromRGB(0,103,192),AcrylicMain=Color3.fromRGB(200,200,200),AcrylicBorder=Color3.fromRGB(120,120,120),AcrylicGradient=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255)),AcrylicNoise=0.96,TitleBarLine=Color3.fromRGB(160,160,160),Tab=Color3.fromRGB(90,90,90),Element=Color3.fromRGB(255,255,255),ElementBorder=Color3.fromRGB(180,180,180),InElementBorder=Color3.fromRGB(150,150,150),ElementTransparency=0.65,ToggleSlider=Color3.fromRGB(40,40,40),ToggleToggled=Color3.fromRGB(255,255,255),SliderRail=Color3.fromRGB(40,40,40),DropdownFrame=Color3.fromRGB(200,200,200),DropdownHolder=Color3.fromRGB(240,240,240),DropdownBorder=Color3.fromRGB(200,200,200),DropdownOption=Color3.fromRGB(150,150,150),Keybind=Color3.fromRGB(120,120,120),Input=Color3.fromRGB(200,200,200),InputFocused=Color3.fromRGB(100,100,100),InputIndicator=Color3.fromRGB(80,80,80),Dialog=Color3.fromRGB(255,255,255),DialogHolder=Color3.fromRGB(240,240,240),DialogHolderLine=Color3.fromRGB(228,228,228),DialogButton=Color3.fromRGB(255,255,255),DialogButtonBorder=Color3.fromRGB(190,190,190),DialogBorder=Color3.fromRGB(140,140,140),DialogInput=Color3.fromRGB(250,250,250),DialogInputLine=Color3.fromRGB(160,160,160),Text=Color3.fromRGB(0,0,0),SubText=Color3.fromRGB(40,40,40),Hover=Color3.fromRGB(50,50,50),HoverChange=0.16}end,[53]=function()local aa,ab,ac,ad,ae=b(53)return{Name='Rose',Accent=Color3.fromRGB(180,55,90),AcrylicMain=Color3.fromRGB(40,40,40),AcrylicBorder=Color3.fromRGB(130,90,110),AcrylicGradient=ColorSequence.new(Color3.fromRGB(190,60,135),Color3.fromRGB(165,50,70)),AcrylicNoise=0.92,TitleBarLine=Color3.fromRGB(140,85,105),Tab=Color3.fromRGB(180,140,160),Element=Color3.fromRGB(200,120,170),ElementBorder=Color3.fromRGB(110,70,85),InElementBorder=Color3.fromRGB(120,90,90),ElementTransparency=0.86,ToggleSlider=Color3.fromRGB(200,120,170),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(200,120,170),DropdownFrame=Color3.fromRGB(200,160,180),DropdownHolder=Color3.fromRGB(120,50,75),DropdownBorder=Color3.fromRGB(90,40,55),DropdownOption=Color3.fromRGB(200,120,170),Keybind=Color3.fromRGB(200,120,170),Input=Color3.fromRGB(200,120,170),InputFocused=Color3.fromRGB(20,10,30),InputIndicator=Color3.fromRGB(170,150,190),Dialog=Color3.fromRGB(120,50,75),DialogHolder=Color3.fromRGB(95,40,60),DialogHolderLine=Color3.fromRGB(90,35,55),DialogButton=Color3.fromRGB(120,50,75),DialogButtonBorder=Color3.fromRGB(155,90,115),DialogBorder=Color3.fromRGB(100,70,90),DialogInput=Color3.fromRGB(135,55,80),DialogInputLine=Color3.fromRGB(190,160,180),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(200,120,170),HoverChange=0.04}end}do local ab,ac,ad,ae,af,ag,ah,aj,c,e,f,g,h,i,j,k=task,setmetatable,error,newproxy,getmetatable,next,table,unpack,coroutine,script,type,require,pcall,getfenv,setfenv,rawget local l,m,n,o,p,s,t,u,v,w,x=ah.insert,ah.remove,ah.freeze or function(l)return l end,ab and ab.defer or function(l,...)local m=c.create(l)c.resume(m,...)return m end,'0.0.0-venv',{},{},{},{},{},{}local y,z={GetChildren=function(y)local z,A=x[y],{}for B in ag,z do l(A,B)end return A end,FindFirstChild=function(y,z)if not z then ad('Argument 1 missing or nil',2)end for A in ag,x[y]do if A.Name==z then return A end end return end,GetFullName=function(y)local z,A=y.Name,y.Parent while A do z=A.Name..'.'..z A=A.Parent end return'VirtualEnv.'..z end},{}for A,B in ag,y do z[A]=function(C,...)if not x[C]then ad("Expected ':' not '.' calling member function "..A,1)end return B(C,...)end end local C=function(C,D,E)local F,G,H,I,J=ac({},{__mode='k'}),function(F)ad(F..' is not a valid (virtual) member of '..C..' "'..D..'"',1)end,function(F)ad('Unable to assign (virtual) property '..F..'. Property is read only',1)end,(ae(true))local K=af(I)K.__index=function(L,M)if M=='ClassName'then return C elseif M=='Name'then return D elseif M=='Parent'then return E elseif C=='StringValue'and M=='Value'then return J else local N=z[M]if N then return N end end for N in ag,F do if N.Name==M then return N end end G(M)end K.__newindex=function(L,M,N)if M=='ClassName'then H(M)elseif M=='Name'then D=N elseif M=='Parent'then if N==I then return end if E~=nil then x[E][I]=nil end E=N if N~=nil then x[N][I]=true end elseif C=='StringValue'and M=='Value'then J=N else G(M)end end K.__tostring=function()return D end x[I]=F if E~=nil then x[E][I]=true end return I end local function D(E,F)local G,H,I,J=E[1],E[2],E[3],E[4]local K=m(I,1)local L=C(H,K,F)s[G]=L if I then for M,N in ag,I do L[M]=N end end if J then for M,N in ag,J do D(N,L)end end return L end local E={}for F,G in ag,a do l(E,D(G))end for H,I in ag,aa do local J=s[H]t[J]=I local K=J.ClassName if K=='LocalScript'or K=='Script'then l(v,J)end end local J=function(J)local K,L=J.ClassName,u[J]if L and K=='ModuleScript'then return aj(L)end local M=t[J]if not M then return end if K=='LocalScript'or K=='Script'then M()return else local N={M()}u[J]=N return aj(N)end end function b(K)local L=s[K]local M=t[L]if not M then return end local N,O,P,Q,R,S,T=false,n{Version=p,Script=e,Shared=w,GetScript=function()return e end,GetShared=function()return w end},L,function(N,...)if x[N]and N.ClassName=='ModuleScript'and t[N]then return J(N)end return g(N,...)end local U,V=function(U,...)if not N then T()end if f(U)=='number'and U>=0 then if U==0 then return S else U=U+1 local V,W=h(i,U)if V and W==R then return S end end end return i(U,...)end,function(U,V,...)if not N then T()end if f(U)=='number'and U>=0 then if U==0 then return j(S,V)else U=U+1 local W,X=h(i,U)if W and X==R then return j(S,V)end end end return j(U,V,...)end function T()R=i(0)local W={maui=O,script=P,require=Q,getfenv=U,setfenv=V}S=ac({},{__index=function(X,Y)local Z=k(S,Y)if Z~=nil then return Z end local _=W[Y]if _~=nil then return _ end return R[Y]end})j(M,S)N=true end return O,P,Q,U,V end for K,L in ag,v do o(J,L)end do local M for N,O in ag,E do if O.ClassName=='ModuleScript'and O.Name=='MainModule'then M=O break end end if M then return J(M)end end end
]====]
local bootOK, bootError = pcall(function()

-- ===== runtime =====
(function()
return function(A)
    local Core=A.Core
    A.S={Players=game:GetService('Players'),RS=game:GetService('ReplicatedStorage'),
        Run=game:GetService('RunService'),HTTP=game:GetService('HttpService'),
        UIS=game:GetService('UserInputService'),Gui=game:GetService('GuiService')}
    A.player=A.S.Players.LocalPlayer
    A.logs={}; A.status={}; A.connections={}; A.tasks={}; A.cache={}; A.cooldowns={}
    A.alive=true; A.running=false; A.epoch=0
    A.defaults={version=5,priority=Core.copy(Core.defaultPriority),world='0',mobsByWorld={},mobSelectionModeByWorld={},target='Nearest',farm=false,trialFollow=false,trialAutoJoin=false,trialJoinSelection={},
        towerAutoJoin=false,towerSelection={},raidAutoJoin=false,raidSelection={},defenseAutoJoin=false,defenseSelection={},
        gateAutoJoin=false,gateSelection={},gateRanks={S=true,A=true,B=true,C=true,D=true,E=true},
        maxTacAutoJoin=false,maxTacSelection={},maxTacRanks={Low=true,Medium=true,High=true,Extreme=true,Psycho=true},
        dungeonAutoJoin=false,dungeonSelection={},bossRushAutoJoin=false,bossRushSelection={},
        rename=false,petName='',petPassiveAuto=false,accessoryCurseAuto=false,swordPassiveAuto=false,titanPassiveAuto=false,shadowPassiveAuto=false,
        webhook=false,webhookURL='',pingId='',ping=false,sendDisconnect=true,
        webhookEvents={Disconnect=true,Mode=true,Progress=true,Error=true,Inventory=true},
        pingEvents={Disconnect=true,Error=true,Mode=false,Progress=false,Inventory=false},
        blackScreen=false,moveStyle='Walk',distance=5,saveSecrets=false,ripperdocAuto=false,ripperdocSlots={},
        autoLeaveStuck=true,stuckSeconds=10,trialDungeonStuckSeconds=20,fixerAutoClaim=false,fixerAutoDeploy=false,fixerPreference='Board order',guildAutoClaim=false,overclockAuto=false,overclockSelection={},
        cyberPlanAuto=false,cyberPlanOrder={},cyberPlanTargets={},loadoutAuto=false,loadoutStat='Power'}
    A.legacyFolder='AnimeSuite_'..tostring(game.GameId)..'_'..tostring(A.player.UserId)
    A.folder='JoesAAS/'..tostring(game.GameId)..'_'..tostring(A.player.UserId)
    A.file=A.folder..'/settings.json'
    function A.log(kind,text)
        text=tostring(text)
        text=text:gsub('https://[^%s]+/api/webhooks/[^%s]+','[webhook redacted]')
        local line=os.date('%H:%M:%S')..' ['..kind..'] '..text
        A.logs[#A.logs+1]=line; if #A.logs>150 then table.remove(A.logs,1) end
        print('[JoesAAS] '..line)
    end
    function A.connect(signal,fn)
        local c=signal:Connect(function(...)
            if A.alive then
                local ok,err=pcall(fn,...)
                if not ok then A.status.Event=tostring(err); A.log('Event',err) end
            end
        end)
        A.connections[#A.connections+1]=c; return c
    end
    function A.safeLoad(path)
        if type(readfile)~='function' then return nil end
        local ok,value=pcall(function() return A.S.HTTP:JSONDecode(readfile(path)) end)
        if ok and type(value)=='table' then return value end
    end
    function A.validate(saved)
        local s=Core.merge(A.defaults,saved)
        local legacyMobs=type(saved)=='table' and next(saved)~=nil and (tonumber(saved.version) or 0)<5
        if type(saved)=='table' and saved.dungeonFollow==true then s.trialFollow=true end
        local n=tonumber(s.distance); s.distance=(n and n==n and n<math.huge) and n or 5
        s.distance=math.clamp(s.distance,2,20)
        for _,key in ipairs({'stuckSeconds','trialDungeonStuckSeconds'}) do
            local value=tonumber(s[key])
            s[key]=(value and value==value and value<math.huge) and math.clamp(value,1,3600) or A.defaults[key]
        end
        if not Core.contains({'Nearest','Highest HP','Lowest HP'},s.target) then s.target='Nearest' end
        if not Core.contains({'Board order','Big Jobs first'},s.fixerPreference) then s.fixerPreference='Board order' end
        if not Core.contains({'Walk','Teleport'},s.moveStyle) then s.moveStyle='Walk' end
        for _,k in ipairs({'webhookEvents','pingEvents','trialJoinSelection','towerSelection','raidSelection','defenseSelection','dungeonSelection','gateSelection','gateRanks','maxTacSelection','maxTacRanks','bossRushSelection','ripperdocSlots'}) do
            for id,v in pairs(s[k]) do if type(id)~='string' or type(v)~='boolean' then s[k][id]=nil end end
        end
        for world,selection in pairs(s.mobsByWorld) do
            if type(world)~='string' or type(selection)~='table' then s.mobsByWorld[world]=nil else
                for id,value in pairs(selection) do if type(id)~='string' or type(value)~='boolean' then selection[id]=nil end end
            end
        end
        s.raidSelection=Core.singleSelection(s.raidSelection)
        s.defenseSelection=Core.singleSelection(s.defenseSelection)
        if s.raidAutoJoin and s.defenseAutoJoin then s.defenseAutoJoin=false end
        -- Separate the previous combined Gate / MaxTac profile.
        local movedMaxTac=false
        for key,value in pairs(Core.copy(s.gateSelection)) do
            if Core.portalMode(key)=='MaxTac' then
                movedMaxTac=true
                if s.maxTacSelection[key]==nil then s.maxTacSelection[key]=value end
                if value and s.gateAutoJoin and (not saved or saved.maxTacAutoJoin==nil) then s.maxTacAutoJoin=true end
                s.gateSelection[key]=nil
            end
        end
        if movedMaxTac then
            local remaining=false
            for _,selected in pairs(s.gateSelection) do if selected then remaining=true; break end end
            if not remaining then s.gateAutoJoin=false end
        end
        for _,rank in ipairs({'Low','Medium','High','Extreme','Psycho'}) do
            if type(saved)=='table' and type(saved.gateRanks)=='table' and type(saved.gateRanks[rank])=='boolean'
                and saved.maxTacRanks==nil then s.maxTacRanks[rank]=saved.gateRanks[rank] end
            s.gateRanks[rank]=nil
        end
        for rank in pairs(s.maxTacRanks) do if A.defaults.maxTacRanks[rank]==nil then s.maxTacRanks[rank]=nil end end
        s.priority=Core.priorityOrder(s.priority)
        s.overclockSelection=Core.trueKeys(s.overclockSelection)
        local order,seen={},{}
        for _,key in ipairs(s.cyberPlanOrder) do
            if type(key)=='string' and key:match('^%a+:%w+$') and not seen[key] then order[#order+1]=key; seen[key]=true end
        end
        s.cyberPlanOrder=order
        for key,target in pairs(s.cyberPlanTargets) do
            if type(key)~='string' or type(target)~='number' or target~=target or target<0 or target>50 then s.cyberPlanTargets[key]=nil
            else s.cyberPlanTargets[key]=math.floor(target) end
        end
        if not Core.contains({'Power','Damage','Yen','XP','Drop','Luck','Kill','CritChance','CritDamage','ShinyChance'},s.loadoutStat) then s.loadoutStat='Power' end
        for world,mode in pairs(s.mobSelectionModeByWorld) do
            if type(world)~='string' or (mode~='all' and mode~='selected') then s.mobSelectionModeByWorld[world]=nil end
        end
        for world,selection in pairs(s.mobsByWorld) do
            if not s.mobSelectionModeByWorld[world] then
                s.mobSelectionModeByWorld[world]=legacyMobs and next(selection)==nil and 'all' or 'selected'
            end
        end
        -- Preserve an old profile's implicit all-mobs choice in its saved world only.
        -- New worlds require a selection or the explicit select-all action.
        if legacyMobs and not s.mobSelectionModeByWorld[tostring(s.world)] then
            s.mobSelectionModeByWorld[tostring(s.world)]='all'
        end
        s.version=5; return s
    end
    function A.setCombatEnabled(mode,value)
        local own=mode=='Raid' and 'raidAutoJoin' or 'defenseAutoJoin'
        local other=mode=='Raid' and 'defenseAutoJoin' or 'raidAutoJoin'
        A.settings[own]=value==true
        if value then A.settings[other]=false end
        if A.settingsChanged then A.settingsChanged() end
        if A.refreshUI then A.refreshUI() end
        if A.coordinateActivities then A.coordinateActivities() end
    end
    -- Copy previous settings once; never overwrite a new-folder file.
    if type(makefolder)=='function' and type(readfile)=='function' and type(writefile)=='function' then
        pcall(makefolder,'JoesAAS'); pcall(makefolder,A.folder)
        if not A.safeLoad(A.folder..'/migration.json') then
            local function copyLegacy(name)
                local destination=A.folder..'/'..name
                if pcall(readfile,destination) then return end
                local ok,bytes=pcall(readfile,A.legacyFolder..'/'..name)
                if not ok then return end
                writefile(destination,bytes)
                assert(readfile(destination)==bytes,'Migration read-back failed: '..name)
            end
            local ok,err=pcall(function()
                for _,name in ipairs({'settings.json','settings.json.bak'}) do copyLegacy(name) end
                writefile(A.folder..'/migration.json',A.S.HTTP:JSONEncode({complete=true}))
            end)
            assert(ok,'Could not preserve previous saves: '..tostring(err)..'. Old files are untouched; rerun to retry.')
        end
    end
    local saved=A.safeLoad(A.file..'.tmp') or A.safeLoad(A.file) or A.safeLoad(A.file..'.bak')
    A.settings=A.validate(saved)
    local lastSaved,saveDue,saveRetry,saveBusy,saveReady,nextCheck=nil,nil,0,false,false,0
    local function settingsSnapshot()
        local snapshot=Core.copy(A.settings)
        if not snapshot.saveSecrets then snapshot.webhookURL='' end
        return snapshot
    end
    function A.finishStartup()
        saveReady=true; A.saveSettings(true)
        A.setRunning(true)
        if A.flushJoinDiagnostics then A.flushJoinDiagnostics(true) end
    end
    function A.saveSettings(force)
        if not saveReady or saveBusy then return false end
        local snapshot=settingsSnapshot()
        if Core.equal(snapshot,lastSaved) then saveDue=nil; return true end
        if not force and os.clock()<saveRetry then return false end
        if type(writefile)~='function' or type(readfile)~='function' or type(makefolder)~='function' then
            A.status.Settings='Autosave unavailable: executor file APIs missing; settings are session-only.'
            saveRetry=os.clock()+30; return false
        end
        saveBusy=true
        local ok,err=pcall(function()
            pcall(makefolder,A.folder)
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            local staged=A.file..'.tmp'
            writefile(staged,encoded)
            assert(Core.equal(A.safeLoad(staged),snapshot),'Staged settings read-back failed')
            local prior=A.safeLoad(A.file)
            if prior then
                if not snapshot.saveSecrets then prior.webhookURL='' end
                writefile(A.file..'.bak',A.S.HTTP:JSONEncode(prior))
            end
            writefile(A.file,encoded)
            assert(Core.equal(A.safeLoad(A.file),snapshot),'Settings read-back failed')
            -- A valid staged file recovers a save interrupted before the main write.
            local cleared=false
            if type(delfile)=='function' then cleared=pcall(delfile,staged) end
            if not cleared or A.safeLoad(staged) then pcall(writefile,staged,'') end
        end)
        saveBusy=false
        if ok then
            lastSaved=snapshot; saveDue=nil; saveRetry=0
            A.status.Settings='Settings saved automatically; restored next execution.'
        else
            saveRetry=os.clock()+10; A.status.Settings='Autosave failed; retrying: '..tostring(err)
            A.log('Settings',A.status.Settings)
        end
        return ok
    end
    function A.settingsChanged(delay)
        if not saveReady or not A.alive or A.stopping then return end
        if delay and delay>0 then saveDue=os.clock()+delay else A.saveSettings() end
    end
    function A.module(kind,name)
        local key=kind..':'..name
        if A.cache[key] then return A.cache[key] end
        local folder=kind=='Config' and A.Library.Config or kind=='Client' and A.Library.Client
            or kind=='Utils' and A.Library.Utils or A.Library.Packages
        if not folder or not folder:FindFirstChild(name) then return nil end
        local getter=kind=='Config' and A.Library.getConfig or kind=='Client' and A.Library.getClient
            or kind=='Utils' and A.Library.getUtil or A.Library.getPackage
        local ok,result=pcall(getter,name)
        if ok and type(result)=='table' then A.cache[key]=result; return result end
        A.status[key]='Module unavailable'; return nil
    end
    function A.config(name) return A.module('Config',name) end
    function A.util(name) return A.module('Utils',name) end
    function A.client(name) return A.module('Client',name) end
    function A.data()
        if A.container and A.container.Ready and type(A.container.Data)=='table' then return A.container.Data end
        return nil
    end
    function A.number(value)
        if type(value)=='number' then return value==value and value or 0 end
        local big=A.util('BigNum')
        if big and type(big.ToFiniteNumber)=='function' then
            local ok,n=pcall(function()
                local parsed=big.TryFrom and big.TryFrom(value) or (big.Decode and big.Decode(value))
                return parsed and big.ToFiniteNumber(parsed)
            end)
            if ok and type(n)=='number' and n==n then return n end
        end
        local p=A.util('NumberParser'); return p and p.Parse(value) or tonumber(value) or 0
    end
    function A.balance(key)
        local data=A.data(); if not data then return 0 end
        return math.max(0,A.number(data[key]))
    end
    function A.ready(key,seconds)
        local now=os.clock(); if (A.cooldowns[key] or 0)>now then return false end
        A.cooldowns[key]=now+(seconds or 1); return true
    end
    function A.bridge(name)
        -- Do not create guessed bridges; only use the game's declared registry.
        local known=A.Library.Network.Bridges.KnownNames
        if type(known)~='table' or known[name]~=true then return nil end
        local key='Bridge:'..name
        if not A.cache[key] then A.cache[key]=A.Library.getBridge(name) end
        return A.cache[key]
    end
    function A.fire(name,...)
        if not A.alive then return false end
        local first=select(1,...)
        if not A.running and not (name=='RangeToggle' and first==false) then return false end
        local epoch=A.epoch
        local b=A.bridge(name)
        if not A.alive or A.epoch~=epoch or (not A.running and not (name=='RangeToggle' and first==false)) then return false end
        if not b then A.status[name]='Bridge unavailable'; return false end
        local ok,err=pcall(b.Fire,b,...)
        if not ok then A.log('Remote',name..': '..tostring(err)) end
        return ok
    end
    function A.on(name,fn)
        local b=A.bridge(name); if b then return A.connect(b,fn) end
    end
    function A.job(name,interval,fn,always)
        A.tasks[name]={name=name,interval=interval,fn=fn,always=always,next=0,busy=false,failures=0}
    end
    function A.cleanupStep(name,fn)
        local ok,err=pcall(fn)
        if not ok then A.status.Cleanup=name..': '..tostring(err); A.log('Cleanup',A.status.Cleanup) end
        return ok
    end
    function A.setRunning(value)
        A.running=value; A.epoch=A.epoch+1
        A.status.Gameplay=value and 'Ready: each feature uses its own toggle' or 'Stopped or disconnected; rerun after reconnecting'
        if not value then
            A.cleanupStep('settings',function() A.saveSettings(true) end)
            for _,name in ipairs({'stopPassiveQueues','stopFarmMovement','stopTrialMovement','stopDungeonMovement','watchTarget'}) do
                if A[name] then A.cleanupStep(name,function() A[name](nil) end) end
            end
            if A.rangeOwned then A.cleanupStep('range',function() A.fire('RangeToggle',false) end); A.rangeOwned=false end
        end
        A.log('Run',value and 'Started enabled features.' or 'Paused automation.')
    end
    function A.stop()
        if not A.alive then return end
        A.stopping=true
        -- Stop new work before cleanup; one broken dependency must not retain the old instance.
        A.running=false; A.epoch=A.epoch+1
        if A.flushJoinDiagnostics then A.cleanupStep('diagnostics',A.flushJoinDiagnostics) end
        A.setRunning(false)
        A.alive=false
        if A.restoreRendering then A.cleanupStep('rendering',A.restoreRendering) end
        for _,name in ipairs({'cleanupTrialMovement','cleanupDungeonMovement'}) do
            if A[name] then A.cleanupStep(name,A[name]) end
        end
        for _,c in ipairs(A.connections) do pcall(function() c:Disconnect() end) end
        A.connections={}
        if A.fluent then A.cleanupStep('Fluent',function() A.fluent:Destroy() end) end
        for _,name in ipairs({'gui','overlay','touchGui'}) do
            if A[name] then A.cleanupStep(name,function() A[name]:Destroy() end) end
        end
    end
    function A.schedule()
        function A.runJob(job)
            if not A.alive or job.busy or not (job.always or A.running) then return end
            job.busy=true; job.next=os.clock()+job.interval
            local epoch=A.epoch
            task.spawn(function()
                if not A.alive or (not job.always and (not A.running or A.epoch~=epoch)) then job.busy=false; return end
                local ok,err=pcall(job.fn)
                job.busy=false
                if ok then job.failures=0 else
                    job.failures=job.failures+1
                    job.next=os.clock()+math.min(120,2^job.failures)
                    A.status[job.name]=tostring(err)
                    A.log('Error',job.name..': '..tostring(err))
                    if job.failures==3 and A.notify then A.notify('Error',job.name..' failed repeatedly; backing off.') end
                end
            end)
        end
        task.spawn(function()
            while A.alive do
                local now=os.clock()
                for _,job in pairs(A.tasks) do
                    if not job.busy and now>=job.next and (job.always or A.running) then
                        A.runJob(job)
                    end
                end
                task.wait(0.2)
            end
        end)
    end
    local root=A.S.RS:WaitForChild('SimpleWorld',20)
    assert(root and root:FindFirstChild('Library'),'SimpleWorld.Library not found; wait for the game to load.')
    A.Library=require(root.Library)
    local package=A.module('Packages','DataContainer')
    assert(package and package.New,'PlayerData interface unavailable')
    A.container=package.New('PlayerData')
    A.job('Settings autosave',0.2,function()
        local now=os.clock()
        if saveDue then
            if now<saveDue or now<saveRetry then return end
        elseif now<nextCheck or now<saveRetry then return end
        nextCheck=now+2; A.saveSettings()
    end,true)
    A.job('Connection cleanup',60,function()
        local live={}
        for _,c in ipairs(A.connections) do
            local ok,connected=pcall(function() if c.Connected~=nil then return c.Connected end; return c.IsConnected end)
            if not ok or connected~=false then live[#live+1]=c end
        end
        A.connections=live
    end,true)
    A.log('Startup','Standalone suite loaded. Settings ready.')
end

end)()(A);

-- ===== notifications =====
(function()
return function(A)
    A.outbox={}
    for _,entry in ipairs(A.safeLoad(A.folder..'/outbox.json') or {}) do
        if type(entry)=='table' and not entry.attachment and A.settings.webhookEvents[entry.kind]~=nil then
            A.outbox[#A.outbox+1]=entry
            if #A.outbox>=50 then break end
        end
    end
    A.httpRequest=(type(request)=='function' and request) or (type(http_request)=='function' and http_request)
        or (type(http)=='table' and type(http.request)=='function' and http.request)
        or (type(syn)=='table' and type(syn.request)=='function' and syn.request)
    A.webhookNext=0
    local env=(type(getgenv)=='function' and getgenv()) or _G
    env.AnimeSuiteHTTP=env.AnimeSuiteHTTP or {busy=false}
    local transport=env.AnimeSuiteHTTP
    transport.results=transport.results or {}
    transport.resultOrder=transport.resultOrder or {}
    local function takeResult(key)
        local response=transport.results[key]
        if response then
            transport.results[key]=nil
            for i=#transport.resultOrder,1,-1 do if transport.resultOrder[i]==key then table.remove(transport.resultOrder,i) end end
        end
        return response
    end
    local function fingerprint(url)
        local n=0; for i=1,#url do n=(n*31+url:byte(i))%2147483647 end; return tostring(n)
    end
    local function persist()
        if type(writefile)=='function' and type(makefolder)=='function' then
            local ok,err=pcall(function() pcall(makefolder,A.folder); writefile(A.folder..'/outbox.json',A.S.HTTP:JSONEncode(A.outbox)) end)
            if not ok then A.status.Webhook='Outbox save failed: '..tostring(err); A.log('Webhook',A.status.Webhook) end
            return ok
        end
        return false
    end
    local urgency={Disconnect=3,Error=2}
    function A.httpTurn(lane)
        if transport.busy then return false end
        local events=A.settings.webhook and os.clock()>=A.webhookNext and #A.outbox>0
        if lane=='Index' then
            if events then
                for _,entry in ipairs(A.outbox) do if urgency[entry.kind] then return false end end
                if transport.lastLane=='Index' then return false end
            end
        elseif lane=='Normal' and events then
            for _,entry in ipairs(A.outbox) do if urgency[entry.kind] then return true end end
            local index=A.indexDeliveryState
            if index and not index.blocked and index.cursor<=#index.pages and os.clock()>=index.next
                and transport.lastLane=='Normal' then return false end
        end
        return true
    end
    local function removeEntry(entry)
        for i,value in ipairs(A.outbox) do if value==entry then table.remove(A.outbox,i); return end end
    end
    function A.http(options,completeOnStop)
        if not A.httpRequest then return false,'HTTP request API unavailable' end
        local key=options.Method..'|'..options.Url..'|'..tostring(options.Body)
        local completed=takeResult(key)
        if completed then return table.unpack(completed,1,completed.n) end
        local operation=transport.operation
        if operation and operation.key~=key then return false,'Waiting for another HTTP request',true end
        if not operation then
            if transport.busy then return false,'HTTP already in flight',true end
            options.Timeout=15
            operation={key=key,at=os.clock()}; transport.operation=operation
            transport.busy=true; transport.at=operation.at
            task.spawn(function()
                operation.response=table.pack(pcall(A.httpRequest,options))
                transport.results[key]=operation.response
                transport.resultOrder[#transport.resultOrder+1]=key
                while #transport.resultOrder>64 do transport.results[table.remove(transport.resultOrder,1)]=nil end
                transport.operation=nil; transport.at=nil
                transport.busy=false
            end)
        end
        local deadline=os.clock()+15
        while (A.alive or completeOnStop) and not operation.response and os.clock()<deadline do task.wait(0.05) end
        if not operation.response then return false,'HTTP result unknown; waiting for the original request',true end
        if not A.alive and not completeOnStop then return false,'Stopped; original HTTP result retained',true end
        takeResult(key)
        return table.unpack(operation.response,1,operation.response.n)
    end
    function A.notify(kind,message,force)
        local s=A.settings
        if not s.webhook then A.status.Webhook='Webhook disabled: enable it in this tab'; return end
        if not force and s.webhookEvents[kind]==false then return end
        if kind=='Disconnect' and not s.sendDisconnect then return end
        s.webhookURL=s.webhookURL:match('^%s*(.-)%s*$')
        if not s.webhookURL:match('^https://discord%.com/api/webhooks/%d+/[%w_%-]+')
            and not s.webhookURL:match('^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+') then
            A.status.Webhook='Enter a Discord webhook URL'; return
        end
        if #A.outbox>=50 then table.remove(A.outbox,1) end
        local ping=s.ping and kind~='Test' and s.pingEvents[kind]~=false and s.pingId:match('^%d+$') and s.pingId or nil
        message=A.Core.clipBytes(message,1500)
        if kind=='Progress' then
            for _,entry in ipairs(A.outbox) do
                if entry.kind==kind and entry.message==message and os.time()-(entry.time or 0)<30 then return entry end
            end
        end
        A.outbox[#A.outbox+1]={kind=kind,message=message,time=os.time(),attempt=0,
            target=fingerprint(s.webhookURL),ping=ping}
        persist(); A.webhookNext=kind=='Disconnect' and 0 or A.webhookNext
        A.status.Webhook='Queued '..kind..' ('..#A.outbox..' waiting)'
        return A.outbox[#A.outbox]
    end
    A.job('Webhook delivery',1,function()
        if not A.alive or not A.settings.webhook or #A.outbox==0 or os.clock()<A.webhookNext then return end
        if transport.busy then
            A.status.Webhook='Waiting for executor HTTP request to finish'..(transport.at and (' ('..math.floor(os.clock()-transport.at)..'s)') or '')
            return
        end
        if not A.httpTurn('Normal') then return end
        local entry=A.outbox[1]
        for _,value in ipairs(A.outbox) do
            if (urgency[value.kind] or 0)>(urgency[entry.kind] or 0) then entry=value end
        end
        if type(entry)~='table' or type(entry.message)~='string' or entry.target~=fingerprint(A.settings.webhookURL) then
            removeEntry(entry); persist(); return
        end
        local payload={content=entry.ping and ('<@'..entry.ping..'>') or '',
            embeds={{title='JoesAAS / '..tostring(entry.kind),description=entry.message,
                footer={text='Place '..tostring(game.PlaceId)..' | event '..tostring(entry.time)}}}}
        local contentType='application/json'; local data=A.S.HTTP:JSONEncode(payload)
        -- Empty Lua tables may encode as objects. Discord requires arrays here.
        local mentions='"allowed_mentions":{"parse":[],"users":'
            ..(entry.ping and ('['..A.S.HTTP:JSONEncode(entry.ping)..']') or '[]')..'}'
        data=data:sub(1,-2)..','..mentions..'}'
        local url=A.settings.webhookURL:gsub('([?&])wait=[^&]*','%1wait=true')
        if not url:find('wait=',1,true) then url=url..(url:find('?',1,true) and '&' or '?')..'wait=true' end
        local ok,response,unresolved=A.http({Url=url,Method='POST',Headers={['Content-Type']=contentType},Body=data})
        if not A.alive then return end
        if unresolved then A.status.Webhook=tostring(response); return end
        local status=ok and type(response)=='table' and tonumber(response.StatusCode or response.Status) or 0
        local body; if ok and type(response)=='table' then
            local parsed,value=pcall(A.S.HTTP.JSONDecode,A.S.HTTP,response.Body or '')
            if parsed and type(value)=='table' then body=value end
        end
        entry.attempt=(tonumber(entry.attempt) or 0)+1
        local action,delay=A.Core.webhookRetry(status or 0,ok and type(response)=='table' and response.Headers or {},body,entry.attempt)
        if action=='done' then
            removeEntry(entry); transport.lastLane='Normal'; A.status.Webhook='Delivered '..tostring(entry.kind); A.webhookNext=os.clock()+2
        elseif action=='stop' then
            removeEntry(entry); transport.lastLane='Normal'; A.status.Webhook='Rejected with HTTP '..tostring(status)..'; check webhook URL'
            -- Keep the user's toggle intact; report the rejection instead of silently disabling it.
        elseif entry.attempt>=8 and status~=429 then
            removeEntry(entry); transport.lastLane='Normal'; A.status.Webhook='Failed after 8 attempts; event dropped'
        else
            A.webhookNext=os.clock()+delay; A.status.Webhook='Retry in '..math.ceil(delay)..'s (HTTP '..tostring(status)..')'
        end
        if action~='done' then
            local detail=type(response)=='table' and tostring(response.Body or ''):sub(1,500) or tostring(response):sub(1,500)
            detail=detail:gsub('https://[^%s"<>]+/api/webhooks/[^%s"<>]+','[webhook redacted]')
            A.status.Webhook=A.status.Webhook..' | '..detail
            A.log('Webhook',A.status.Webhook)
        end
        A.webhookDiagnostic={at=os.time(),kind=entry.kind,httpStatus=status,attempt=entry.attempt,
            result=A.status.Webhook,transportAvailable=type(A.httpRequest)=='function'}
        if type(writefile)=='function' then
            pcall(function() writefile(A.folder..'/webhook-diagnostics.json',A.S.HTTP:JSONEncode(A.webhookDiagnostic)) end)
        end
        persist()
    end,true)
    local sent=false
    function A.isDisconnectMessage(message)
        local text=tostring(message or ''):lower()
        for _,phrase in ipairs({'disconnected','lost connection','connection lost','kicked from','shut down','shutdown','reconnect','same account launched','internet connection'}) do
            if text:find(phrase,1,true) then return true end
        end
        return false
    end
    local function disconnected(message)
        if not sent and A.isDisconnectMessage(message) then
            sent=true; A.notify('Disconnect','Client connection/error message: '..tostring(message))
            A.status.Gameplay='Disconnected: rerun the script after reconnecting'
            A.setRunning(false)
            if A.runJob and A.tasks['Webhook delivery'] then A.runJob(A.tasks['Webhook delivery']) end
        end
    end
    local connected=false
    local ok,signal=pcall(function() return A.S.Gui.ErrorMessageChanged end)
    if ok and signal then
        local hooked=pcall(A.connect,signal,disconnected); connected=hooked or connected
    end
    local modernOK,modern=pcall(function() return A.S.Gui.UiMessageChanged end)
    if modernOK and modern then
        local hooked=pcall(A.connect,modern,function(kind,message)
            if tostring(kind):lower():find('error',1,true) then disconnected(message) end
        end)
        connected=hooked or connected
    end
    A.status.Disconnect=connected and 'Error-message listener connected' or 'Error-message signals unavailable in this executor'
    A.job('Disconnect fallback',2,function()
        if not sent and (A.settings.webhook and A.settings.sendDisconnect) then
            local readOK,message=pcall(function() return A.S.Gui:GetErrorMessage() end)
            if readOK and type(message)=='string' and message~='' then disconnected(message) end
        end
    end,true)
    A.connect(A.player.OnTeleport,function(state)
        if state==Enum.TeleportState.Started then A.notify('Mode','Teleporting to another server. Run the suite again after arrival.') end
    end)
end

end)()(A);

-- ===== discovery =====
(function()
return function(A)
    local C=A.Core
    A.catalog={worlds={},enemies={}}
    function A.unlocked(id)
        local cfg=A.config('WorldConfig'); local d=A.data()
        return d and cfg and cfg:IsUnlocked(tonumber(id),d) or false
    end
    function A.currentWorld()
        local ctrl=A.client('WorldController')
        return ctrl and ctrl:GetCurrentWorld() or (A.data() or {}).CurrentWorld
    end
    function A.discover()
        local cat=A.catalog
        A.catalogRevision=(A.catalogRevision or 0)+1
        local world=A.config('WorldConfig'); if world then cat.worlds=world:GetAllWorlds() end
        local enemy=A.config('EnemyConfig'); if enemy then cat.enemies=enemy:GetAllEnemies() end
        cat.enemyLookup={}
        for key,entry in pairs(cat.enemies) do
            local world=tostring(entry.World or entry.WorldId)
            cat.enemyLookup[world]=cat.enemyLookup[world] or {}
            for _,name in ipairs({key,entry.Name or key,entry.ModelName or key}) do
                cat.enemyLookup[world][name]={key=key,info=entry}
            end
        end
        A.catalogReady=world~=nil and enemy~=nil and next(cat.worlds)~=nil and next(cat.enemies)~=nil
        A.status.Discovery=string.format('%d worlds / %d enemies',#C.keys(cat.worlds),#C.keys(cat.enemies))
        if A.refreshUI then A.refreshUI() end
    end
    A.discover()
    -- Config catalogs are static once loaded. Retry incomplete startup only.
    A.job('Catalog recovery',5,function() if not A.catalogReady then A.discover() end end,true)
    A.on('WorldChanged',function(id)
        A.confirmedWorld=tonumber(id); A.status.World=tostring(id)
    end)
end

end)()(A);

-- ===== run_identity =====
(function()
return function(A)
    local fields={Raid='RaidKey',Defense='DefenseKey',Tower='TowerKey',TimeTrial='TrialKey',Dungeon='DungeonKey',BossRush='RushKey'}
    local folders={Raid='RaidArenas',Defense='DefenseArenas',Tower='TowerArenas',TimeTrial='TimeTrialArenas',Dungeon='DungeonArenas',BossRush='BossRushArenas'}
    local known,order={},{}
    local function remember(prefix,instance,key)
        local id=prefix..':'..instance
        if not known[id] then order[#order+1]=id end
        known[id]=key
        while #order>64 do known[table.remove(order,1)]=nil end
    end
    A.rememberRun=remember
    function A.runKey(raw)
        if type(raw)~='string' then return nil end
        local prefix,instance=raw:match('^([^:]+):(.+)$')
        if prefix=='Trial' then return instance end
        if prefix=='Dungeon' then return instance end
        if not fields[prefix] then return nil end
        if known[prefix..':'..instance] then return known[prefix..':'..instance] end
        local root=workspace:FindFirstChild(folders[prefix])
        local arena=root and root:FindFirstChild(instance)
        local key=arena and arena:GetAttribute(fields[prefix])
        if type(key)=='string' then remember(prefix,instance,key) end
        return key
    end
    for prefix,field in pairs(fields) do
        local name,keyField=prefix,field
        A.on(name..'State',function(packet)
            if type(packet)=='table' and type(packet.InstanceKey)=='string' and type(packet[keyField])=='string' then
                remember(name,packet.InstanceKey,packet[keyField])
            end
        end)
        if name~='Tower' and name~='TimeTrial' and name~='Dungeon' then
            A.on(name..'MapReady',function(instance,key)
                if type(instance)=='string' and type(key)=='string' then remember(name,instance,key) end
            end)
        end
    end
    function A.endPacket(first,second)
        return type(second)=='table' and second or (type(first)=='table' and first or nil)
    end
    -- Missing identifiers cannot prove a different run; explicit foreign identifiers always do.
    function A.runEventMatches(prefix,packet,raw,key)
        raw=raw or A.player:GetAttribute('VisibilityContext')
        local context,instance
        if type(raw)=='string' then context,instance=raw:match('^([^:]+):(.+)$') end
        if not context then return false end
        if context=='Trial' then context='TimeTrial' end
        if context~=prefix then return false end
        if type(packet)~='table' then return true end
        key=key or A.runKey(raw)
        if packet.InstanceKey and packet.InstanceKey~=instance then return false end
        local declared=packet[fields[prefix]]
        if (prefix=='TimeTrial' or prefix=='Dungeon') and declared and declared~=instance then return false end
        if key and declared and declared~=key then return false end
        return true
    end
end

end)()(A);

-- ===== pet_inventory =====
(function()
return function(A)
    local pets,equipped,sequence=nil,nil,nil
    local listeners={}
    local function publish(ids)
        for _,fn in ipairs(listeners) do
            local ok,err=pcall(fn,ids)
            if not ok then A.log('Pet inventory listener',err) end
        end
    end
    function A.onPetInventory(fn) listeners[#listeners+1]=fn end
    local function nativeSnapshot()
        local inventory=A.client('InventoryController')
        local delta=A.util('PetInventoryDeltaUtil')
        local ok,snapshot=pcall(function()
            return inventory and inventory.HasSynced and inventory:HasSynced() and delta and delta.Get and delta.Get()
        end)
        return ok and type(snapshot)=='table' and snapshot or nil
    end
    function A.petData()
        local data=A.data()
        if data and not pets then
            local snapshot=nativeSnapshot()
            if snapshot then pets=A.Core.copy(snapshot) end
        end
        if not data or (not pets and not equipped) then return data end
        local view={}; for key,value in pairs(data) do view[key]=value end
        if pets then view.Pets=pets end
        if equipped then view.EquippedPets=equipped end
        return view
    end
    A.on('InventoryUpdated',function(packet)
        if type(packet)~='table' then return end
        local seq=tonumber(packet.Seq)
        if seq and sequence and seq<=sequence then return end
        local changed={}
        if type(packet.Full)=='table' then
            pets=A.Core.copy(packet.Full)
            if seq then sequence=seq end
            publish(nil); return
        end
        if not pets then
            local data=A.data()
            local snapshot=nativeSnapshot() or (data and data.Pets)
            if type(snapshot)~='table' then return end
            -- Work on our own snapshot; never mutate the game's inventory cache.
            pets=A.Core.copy(snapshot)
        end
        for id,value in pairs(type(packet.Changed)=='table' and packet.Changed or {}) do
            pets[id]=A.Core.copy(value); changed[id]=true
        end
        for _,id in ipairs(type(packet.Removed)=='table' and packet.Removed or {}) do
            pets[id]=nil; changed[id]=true
        end
        if seq then sequence=seq end
        publish(changed)
    end)
    A.on('EquippedUpdated',function(snapshot)
        if type(snapshot)=='table' then equipped=A.Core.copy(snapshot) end
    end)
    if A.container and type(A.container.OnChange)=='function' then
        local ok,connection=pcall(A.container.OnChange,A.container,{'Pets'},function(_,_,path)
            local data=A.data()
            if pets and data and type(data.Pets)=='table' then
                if type(path)=='table' and path[1] then pets[path[1]]=A.Core.copy(data.Pets[path[1]])
                else pets=A.Core.copy(data.Pets) end
            end
            publish(type(path)=='table' and path[1] and {[path[1]]=true} or nil)
        end)
        if ok and connection then A.connections[#A.connections+1]=connection end
        local equipOK,equipConnection=pcall(A.container.OnChange,A.container,{'EquippedPets'},function()
            local data=A.data()
            equipped=data and type(data.EquippedPets)=='table' and A.Core.copy(data.EquippedPets) or nil
        end)
        if equipOK and equipConnection then A.connections[#A.connections+1]=equipConnection end
    end
end

end)()(A);

-- ===== requests =====
(function()
return function(A)
    local env=(type(getgenv)=='function' and getgenv()) or _G
    env.JoesAASRequests=env.JoesAASRequests or {}
    local active=env.JoesAASRequests
    function A.requestInFlight(name) return active[name] and active[name].busy==true end
    function A.invoke(name,args,callback)
        if not A.alive or not A.running or A.requestInFlight(name) then return nil end
        local remote=A.Library.Network.Functions:FindFirstChild(name)
        if not remote then return nil end
        local request={busy=true,at=os.clock(),epoch=A.epoch}
        active[name]=request
        -- Resume immediately like task.spawn, but retain a handle for controlled yield tests.
        request.thread=coroutine.create(function()
            local result=table.pack(pcall(remote.InvokeServer,remote,table.unpack(args,1,args.n)))
            request.busy=false
            if active[name]==request then active[name]=nil end
            if A.alive and A.running and A.epoch==request.epoch then
                local ok,err=pcall(callback,table.unpack(result,1,result.n))
                if not ok then A.log('Request',name..': '..tostring(err)) end
            end
        end)
        local ok,err=coroutine.resume(request.thread)
        if not ok then request.busy=false; A.log('Request',name..': '..tostring(err)) end
        return request
    end
end

end)()(A);

-- ===== spending =====
(function()
return function(A)
    local C=A.Core
    A.sessionNamed={}
    local eligibility,acceptedUntil,serverConfirmed={},{},{}
    local candidates,dirty,reconcileAt={},nil,0
    local function inspect(id,pet,named,stats)
        local row=eligibility[id]
        local record=type(named)=='table' and named[id]
        if not row or row.pet~=pet or row.petId~=(type(pet)=='table' and pet.PetId)
            or row.inventoryRarity~=(type(pet)=='table' and pet.Rarity) or row.named~=record
            or row.stats~=stats or row.rarityFn~=(stats and stats.GetRarity) or os.clock()-row.at>=30 then
            local ok,eligible,reason,rarity=pcall(C.renameEligible,id,pet,named,stats)
            row={pet=pet,petId=type(pet)=='table' and pet.PetId,inventoryRarity=type(pet)=='table' and pet.Rarity,
                named=record,stats=stats,rarityFn=stats and stats.GetRarity,at=os.clock(),eligible=ok and eligible==true,
                reason=ok and reason or 'eligibility unavailable; will recheck',rarity=rarity or 'unknown'}
            eligibility[id]=row
        end
        return row.eligible,row.reason,row.rarity
    end
    local function invalidate(ids)
        if ids then
            for id in pairs(ids) do eligibility[id]=nil; if dirty then dirty[id]=true end end
        else eligibility={}; dirty=nil; reconcileAt=0 end
        if not A.alive then return end
        A.renameInventoryEvents=(A.renameInventoryEvents or 0)+1
        A.renameLastInventoryEvent=os.clock()
        if A.tasks.Renaming then A.tasks.Renaming.next=0 end
    end
    A.onPetInventory(invalidate)
    function A.renameDiagnostics()
        local d=A.petData() or {}; local stats=A.util('PetStatsUtil')
        local report={version=A.version,status=A.status.Rename,inventoryType=type(d.Pets),namedType=type(d.NamedPets),total=0,reasons={},rarities={},samples={},
            inventoryEvents=A.renameInventoryEvents or 0,lastInventoryEvent=A.renameLastInventoryEvent}
        local named=type(d.NamedPets)=='table' and d.NamedPets or {}
        local sampled={}
        for _,id in ipairs(C.keys(type(d.Pets)=='table' and d.Pets or {})) do
            local pet=d.Pets[id]; report.total=report.total+1
            local eligible,reason,rarity=inspect(id,pet,named,stats)
            reason=A.sessionNamed[id] and 'renamed this session' or reason
            report.reasons[reason]=(report.reasons[reason] or 0)+1
            rarity=tostring(rarity)
            report.rarities[rarity]=(report.rarities[rarity] or 0)+1
            if #report.samples<40 and (sampled[reason] or 0)<5 then
                sampled[reason]=(sampled[reason] or 0)+1
                report.samples[#report.samples+1]={id=tostring(id),idType=type(id),petType=type(pet),
                    petId=type(pet)=='table' and tostring(pet.PetId) or '',rarity=rarity,reason=reason,
                    inventoryRarity=type(pet)=='table' and tostring(pet.Rarity) or '',
                    namedRecordType=type(named[id]),
                    fields=type(pet)=='table' and C.keys(pet) or {}}
            end
        end
        return report
    end
    local lastDiagnostic,nextDiagnostic=nil,0
    local function saveDiagnostic()
        if A.status.Rename==lastDiagnostic or os.clock()<nextDiagnostic then return end
        nextDiagnostic=os.clock()+60
        local ok,err=pcall(function()
            assert(type(writefile)=='function','File writing unavailable')
            writefile(A.folder..'/rename-diagnostics.json',A.S.HTTP:JSONEncode(A.renameDiagnostics()))
        end)
        if ok then lastDiagnostic=A.status.Rename end
        A.status['Rename report']=ok and ('Saved '..A.folder..'/rename-diagnostics.json')
            or ('Could not save rename report: '..tostring(err))
    end
    local pending,retries,retryAfter={},{},{}
    local nextRename=0
    A.renamePending=nil
    local function isConfirmed(id)
        local d=A.petData()
        return serverConfirmed[id]==true or (d and type(d.NamedPets)=='table' and type(d.NamedPets[id])=='table')
    end
    local function finish(id,success,reason)
        if success then
            A.sessionNamed[id]=true
            if isConfirmed(id) then retries[id]=nil; acceptedUntil[id]=nil
            else acceptedUntil[id]=os.clock()+30 end
            A.status.Rename='Named Astral: '..id
            if A.settings.webhook then A.notify('Inventory','Renamed an unnamed Astral pet: '..id) end
        else
            if (retries[id] or 0)>=3 then retryAfter[id]=os.clock()+120 end
            A.status.Rename='Rename failed for '..id..': '..tostring(reason)
            A.log('Rename',A.status.Rename)
        end
        pending[id]=nil; A.renamePending=nil
    end
    A.on('NameRenameResult',function(accepted,reason,payload)
        local id=A.renamePending
        if not id then return end
        if type(payload)=='table' and ((payload.UniqueId and payload.UniqueId~=id)
            or (payload.Kind and payload.Kind~='Pet')) then return end
        -- An uncorrelated rejection may belong to another script or the game's UI.
        if accepted==true and type(payload)=='table' and (payload.Kind==nil or payload.Kind=='Pet')
            and payload.UniqueId==id then finish(id,true)
        elseif type(payload)=='table' and payload.UniqueId==id then
            if reason=='same_name' then serverConfirmed[id]=true; finish(id,true)
            else finish(id,false,reason) end
        end
    end)
    local function renameStep()
        local d=A.petData()
        if not d then A.status.Rename='Waiting for player data'; return end
        local id=A.renamePending
        if id then
            if isConfirmed(id) then finish(id,true)
            elseif os.clock()-pending[id]>=20 then
                finish(id,false,'No confirmation; will retry, up to 3 attempts per pet'); dirty=nil; return
            else A.status.Rename='Waiting for confirmation: '..id; return end
        end
        if not A.settings.rename then return end
        local cfg=A.config('NamedConfig'); local stats=A.util('PetStatsUtil')
        if type(d.Pets)~='table' then A.status.Rename='Pet inventory unavailable'; return end
        if not cfg or not stats or type(stats.GetRarity)~='function' then
            A.status.Rename='Naming configuration unavailable'; return
        end
        if cfg.WorldId and not A.unlocked(cfg.WorldId) then
            A.status.Rename='Unlock naming world '..tostring(cfg.WorldId)..' first'; return
        end
        local name=cfg:Normalize(A.settings.petName)
        local valid,reason=cfg:Validate(name)
        if not valid then A.status.Rename=cfg:GetErrorMessage(reason); return end
        local skipped,total={},0
        for petId,deadline in pairs(acceptedUntil) do
            if isConfirmed(petId) then acceptedUntil[petId]=nil; retries[petId]=nil
            elseif os.clock()>=deadline then
                acceptedUntil[petId]=nil; A.sessionNamed[petId]=nil
                if (retries[petId] or 0)>=3 then retryAfter[petId]=os.clock()+120 end
            end
        end
        for petId in pairs(eligibility) do if d.Pets[petId]==nil then eligibility[petId]=nil end end
        if not dirty or os.clock()>=reconcileAt then
            candidates={}
            for petId,pet in pairs(d.Pets) do
                local eligible=inspect(petId,pet,d.NamedPets or {},stats)
                if eligible then candidates[petId]=true end
            end
            dirty={}; reconcileAt=os.clock()+5
        else
            for petId in pairs(dirty) do
                local pet=d.Pets[petId]
                candidates[petId]=pet~=nil and inspect(petId,pet,d.NamedPets or {},stats)==true or nil
            end
            dirty={}
        end
        for petId,row in pairs(eligibility) do
            if d.Pets[petId] then
                total=total+1
                if not row.eligible then skipped[row.reason]=(skipped[row.reason] or 0)+1 end
            end
        end
        -- Removed pets must not leave session state or retry timers behind.
        for petId in pairs(A.sessionNamed) do
            if d.Pets[petId]==nil then A.sessionNamed[petId]=nil; serverConfirmed[petId]=nil; acceptedUntil[petId]=nil; A.cooldowns['rename:'..petId]=nil end
        end
        for petId in pairs(retries) do
            if d.Pets[petId]==nil then retries[petId]=nil; retryAfter[petId]=nil; A.cooldowns['rename:'..petId]=nil end
        end
        for _,petId in ipairs(C.keys(candidates)) do
            -- A partially replicated or malformed entry must not block the rest.
            local canRename,skip=inspect(petId,d.Pets[petId],d.NamedPets or {},stats)
            if retryAfter[petId] and os.clock()>=retryAfter[petId] then
                retries[petId]=nil; retryAfter[petId]=nil
            end
            if A.sessionNamed[petId] then canRename=false; skip='renamed this session' end
            if (retries[petId] or 0)>=3 then canRename=false; skip='retry paused for 120s after 3 unconfirmed attempts' end
            if canRename then
                local cost=cfg:GetCost('Pet','Astral'); local balance=A.balance(cfg.ItemId)
                if type(cost)~='number' or cost<0 then A.status.Rename='Naming cost unavailable'; return end
                if balance<cost then
                    A.status.Rename=string.format('Need %s %s per Astral; have %s',tostring(cost),cfg.ItemId,tostring(balance)); return
                end
                -- Live inventory events can wake this job faster than its normal interval.
                -- The server limit is shared across pets, so throttle all naming requests.
                if os.clock()<nextRename then
                    A.tasks.Renaming.next=nextRename
                    A.status.Rename='Waiting between naming requests'; return
                end
                if A.ready('rename:'..petId,25) then
                    nextRename=os.clock()+1
                    -- Set pending before Fire: responses may arrive synchronously.
                    retries[petId]=(retries[petId] or 0)+1
                    pending[petId]=os.clock(); A.renamePending=petId
                    A.status.Rename='Requesting Astral rename: '..petId
                    if not A.fire('NameRenameRequest',{Kind='Pet',UniqueId=petId,Name=name}) then
                        finish(petId,false,'Bridge send failed')
                    end
                    return
                end
                skip='retry cooling down'
            end
            skipped[skip]=(skipped[skip] or 0)+1
        end
        local details={}
        for _,reason in ipairs(C.keys(skipped)) do details[#details+1]=skipped[reason]..' '..reason end
        A.status.Rename='Scanned '..total..' pets. '..table.concat(details,', ')
    end
    function A.retryRenaming()
        if A.renamePending then return end
        retries={}; retryAfter={}; eligibility={}; dirty=nil; reconcileAt=0
        for key in pairs(A.cooldowns) do if key:find('^rename:') then A.cooldowns[key]=nil end end
        A.tasks.Renaming.next=0
        A.status.Rename='Retry enabled; checking unnamed Astral pets'
    end
    A.job('Renaming',1,function()
        if not A.settings.rename and not A.renamePending then return end
        local ok,err=pcall(renameStep)
        if not ok then A.status.Rename='Rename error: '..tostring(err); A.log('Rename',A.status.Rename) end
        if not A.renamePending and not tostring(A.status.Rename):find('^Named Astral:') then saveDiagnostic() end
    end)
    -- Naming records are separate from both native inventory feeds.
    if A.container and type(A.container.OnChange)=='function' then
        local ok,connection=pcall(A.container.OnChange,A.container,{'NamedPets'},function(_,_,path) invalidate(type(path)=='table' and path[1] and {[path[1]]=true} or nil) end)
        if ok and connection then A.connections[#A.connections+1]=connection end
    end
end

end)()(A);

-- ===== passive_queue =====
(function()
return function(A)
    -- All five systems use the same lifecycle; the native controller owns rolling.
    local pending,nextWrite,timer,timerId={},0,false,0
    local pump
    local function arm(seconds)
        timer=true; timerId=timerId+1
        local id=timerId
        task.delay(seconds,function() if timerId==id then pump() end end)
    end
    pump=function()
        timer=false; timerId=timerId+1
        if next(pending)==nil then return end
        if os.clock()<nextWrite then arm(nextWrite-os.clock()); return end
        local kind,entry=next(pending); pending[kind]=nil
        local environment=(type(getgenv)=='function' and getgenv()) or _G
        if (A.alive or environment.JoesAAS==A) and (#entry.keys==0 or entry.valid()) then
            local ok,err=pcall(entry.util.SetQueue,entry.util,kind,entry.keys)
            nextWrite=os.clock()+0.3
            if not ok then A.log('Passive queue',err) end
        end
        if next(pending)~=nil then arm(math.max(0.01,nextWrite-os.clock())) end
    end
    local function writeQueue(util,kind,keys,valid)
        pending[kind]={util=util,keys=keys,valid=valid}
        if not timer or os.clock()>=nextWrite then pump() end
    end
    A.passiveQueues={}
    function A.stopPassiveQueues()
        for kind,queue in pairs(A.passiveQueues) do
            local ok,err=pcall(queue.stop)
            if not ok then A.log('Passive cleanup',kind..': '..tostring(err)) end
        end
    end
    function A.createPassiveQueue(spec)
        local TARGET=spec.target
        local title=spec.title
        local gap=spec.gap or 0.6
        local controller,queueUI,queueUtil,cfg,discount
        local owned,current,phase=false,nil,'idle'
        local rows,byId,passives,retryAfter,failures={},{},{},{},{}
        local dirty,nextScan,passiveReady=true,0,false
        local deadline,nextAction,nextState,advanceUntil=0,0,0,0
        local amount,lastRaw,cost,blockedAmount=nil,nil,nil,nil
        local function kick()
            if A.tasks[title] then A.tasks[title].next=0 end
        end
        local function wake() dirty=true; kick() end
        local function passiveId(value) return type(value)=='table' and value.Id or value end
        local function replacePassives(snapshot)
            passiveReady=true
            local previous=passives; passives={}
            for id,value in pairs(snapshot) do
                passives[id]=passiveId(value) or false
                if (previous[id]==TARGET)~=(passives[id]==TARGET) then dirty=true end
            end
            for id,value in pairs(previous) do if value==TARGET and passives[id]~=TARGET then dirty=true end end
        end
        local function complete(row,data)
            local key=row.passiveKey or row.id
            local value=passives[key]
            if value==nil and row.legacyKey then value=passives[row.legacyKey] end
            if value==nil then value=spec.retained(data,row) end
            return passiveId(value)==TARGET
        end
        local function stopNative()
            local stopOK,stopError=pcall(function() if controller then controller:StopAutoRoll() end end)
            local queueOK,queueError=pcall(function()
                if queueUtil then
                    if spec.explicitClear then queueUtil:Clear(spec.kind) end
                    writeQueue(queueUtil,spec.kind,{},function() return false end)
                end
            end)
            -- Native loops sleep for 0.5s; queue timeouts share a six-second flag.
            -- An old timeout must expire before a later queue handoff can start.
            nextAction=math.max(nextAction,os.clock()+gap,advanceUntil)
            if not stopOK or not queueOK then error(tostring(stopError or queueError)) end
        end
        local function stop()
            if not owned then return end
            owned=false; current=nil; phase='idle'; dirty=true; blockedAmount=nil
            lastRaw=nil; amount=nil; passiveReady=false; passives={}
            local ok,err=pcall(stopNative)
            A.status[title]=ok and 'OFF' or ('Stop failed: '..tostring(err))
            if not ok then A.log(title,err) end
        end
        local function clearing(wait)
            stopNative(); phase='clearing'; deadline=os.clock()+8
            nextAction=math.max(nextAction,os.clock()+(wait or gap))
        end
        local function apply(packet)
            if not owned and not A.settings[spec.setting] then dirty=true; passiveReady=false; return end
            if type(packet)~='table' then return end
            if type(packet[spec.passiveField])=='table' then replacePassives(spec.snapshot(packet)) end
            if spec.patch~=false and type(packet.ChangedKey)=='string' then
                local id=packet.ChangedKey
                local value=passiveId(packet.ChangedEntry) or false
                if (passives[id]==TARGET)~=(value==TARGET) then dirty=true end
                passives[id]=value
            end
            if type(packet.ItemCost)=='table' then cost=A.Core.copy(packet.ItemCost) end
            if type(packet.ItemAmount)=='number' and packet.ItemAmount==packet.ItemAmount and packet.ItemAmount<math.huge then
                amount=math.max(0,packet.ItemAmount)
            end
            kick()
        end
        if spec.state then A.on(spec.state,apply) end
        A.on(spec.result,function(accepted,reason,packet)
            if spec.unwrap then accepted,reason,packet=spec.unwrap(accepted,reason,packet) end
            apply(packet)
            if not owned or not current then return end
            local key=type(packet)=='table' and packet.ChangedKey
            local matches=key==current.id or key==(current.passiveKey or current.id) or key==current.legacyKey
            if key and not matches then return end
            if accepted==true then failures[current.id]=nil; return end
            if reason=='rate_limited' or reason=='processing' then return end
            if reason=='not_enough_items' then
                blockedAmount=amount or 0; clearing(); phase='funds'
            elseif spec.invalid[reason] and key and matches then
                retryAfter[current.id]=os.clock()+60; current=nil; clearing(5.1); dirty=true
            else
                -- Unkeyed failures cannot safely be assigned to an individual item.
                -- Reconcile first; repeated refusals must not block all other copies.
                if queueUI.Config.GetActiveKey()==current.id then
                    failures[current.id]=(failures[current.id] or 0)+1
                    if failures[current.id]>=3 then
                        retryAfter[current.id]=os.clock()+60; failures[current.id]=nil; current=nil; dirty=true
                    end
                end
                clearing(5.1); nextAction=math.max(nextAction,os.clock()+10)
                A.status[title]='Paused after '..tostring(reason)..'; will reconcile and retry'
            end
        end)
        if spec.observe then spec.observe(wake) end
        if A.container and type(A.container.OnChange)=='function' then
            local observed={}
            for _,field in ipairs({spec.inventoryField,spec.passiveField,'RollQueues','AutoRollStates'}) do
                if not observed[field] then
                    observed[field]=true
                    local ok,connection=pcall(A.container.OnChange,A.container,{field},function()
                        if not owned and not A.settings[spec.setting] then dirty=true; passiveReady=false; return end
                        if field==spec.inventoryField and field~=spec.passiveField then dirty=true end
                        if field==spec.passiveField then
                            local data=A.data()
                            if field==spec.inventoryField and spec.inventoryChanged and spec.inventoryChanged(data) then dirty=true end
                            local snapshot=spec.snapshot(data)
                            if type(snapshot)=='table' then replacePassives(snapshot) end
                        end
                        kick()
                    end)
                    if ok and connection then A.connections[#A.connections+1]=connection end
                end
            end
        end
        local function setup()
            cfg=A.config(spec.config)
            controller=A.client(spec.controller); queueUtil=A.util('AutoRollStateUtil')
            discount=spec.discount and A.util('VipDiscountUtil') or nil
            if not cfg or cfg.Enabled==false or not controller or not queueUtil or not spec.prepare()
                or type(controller.GetQueueUi)~='function' or type(controller.StopAutoRoll)~='function'
                or type(controller.BeginQueueAdvance)~='function' or type(queueUtil.SetQueue)~='function'
                or (spec.explicitClear and type(queueUtil.Clear)~='function')
                or (spec.sync and type(controller.SyncPlayerData)~='function')
                or (spec.discount and (not discount or type(discount.GetDiscountedGachaCost)~='function')) then
                A.status[title]='Waiting for native roll APIs'; return false
            end
            local group=spec.curse and cfg.Curses or cfg.Passives
            local divine=type(group)=='table' and group.Divine
            local order=cfg.Rarity_Order
            local count=0
            if spec.curse then
                count=type(divine)=='table' and divine.Id==TARGET and 1 or 0
            elseif type(divine)=='table' then
                for _ in pairs(divine) do count=count+1 end
                divine=divine[TARGET]
            end
            -- Rarity-only native stopping is safe only with this exact sole Divine.
            if not (count==1 and type(divine)=='table' and divine.Id==TARGET and divine.Rarity=='Divine'
                and type(order)=='table' and order[#order]=='Divine'
                and (not spec.curse or cfg.AutoStopRarity=='Divine')) then
                A.status[title]='Roll configuration changed; native stop needs review'; return false
            end
            queueUI=controller:GetQueueUi()
            if not queueUI or type(queueUI.Config)~='table' or type(queueUI.Config.IsBusy)~='function'
                or type(queueUI.Config.GetActiveKey)~='function' then
                A.status[title]='Native passive queue unavailable'; return false
            end
            cost=cost or A.Core.copy(cfg.ItemCost)
            return true
        end
        local function rebuild(data)
            rows={}; byId={}
            if spec.inventoryChanged then spec.inventoryChanged(data) end
            for _,row in ipairs(spec.rows(data)) do
                byId[row.id]=row
                if not complete(row,data) then rows[#rows+1]=row end
            end
            table.sort(rows,function(a,b)
                if a.dynamic~=b.dynamic then return a.dynamic end
                if a.dynamic and a.bonus~=b.bonus then return a.bonus>b.bonus end
                if a.power~=b.power then return a.power>b.power end
                if (a.level or 0)~=(b.level or 0) then return (a.level or 0)>(b.level or 0) end
                return a.id<b.id
            end)
            for id in pairs(retryAfter) do if not byId[id] then retryAfter[id]=nil; failures[id]=nil end end
            for id in pairs(failures) do if not byId[id] then failures[id]=nil end end
            dirty=false; nextScan=os.clock()+30
        end
        local function requestState()
            if os.clock()<nextState then return end
            nextState=os.clock()+5
            if spec.stateRequest then A.fire(spec.stateRequest,cfg.SystemKey) end
        end
        local function awaitingReset(data)
            local saved=type(data.AutoRollStates)=='table' and data.AutoRollStates[spec.kind]
            local queue=type(data.RollQueues)=='table' and data.RollQueues[spec.kind]
            return queueUI.Config.IsBusy() or (type(saved)=='table' and saved.Active==true and saved.Key~=nil)
                or (type(queue)=='table' and #queue>0)
        end
        local function step()
            if not A.alive or not A.running then return end
            if not A.settings[spec.setting] then stop(); A.status[title]='OFF'; return end
            local data=spec.data()
            if not data or type(data[spec.inventoryField])~='table' then
                if owned then stop() end
                A.status[title]='Waiting for '..spec.plural..' inventory'; return
            end
            if not owned then
                if not setup() then return end
                if not A.alive or not A.running or not A.settings[spec.setting] then return end
                if queueUI.Config.GetActiveKey() or queueUI.Config.IsBusy() then advanceUntil=os.clock()+6.1 end
                owned=true; dirty=true; if spec.sync then controller:SyncPlayerData() end
                if not A.alive or not A.running or not A.settings[spec.setting] then stop(); return end
                local snapshot=spec.snapshot(data)
                if type(snapshot)=='table' then replacePassives(snapshot) end
                clearing(1.1); requestState()
            end
            if not A.alive or not A.running or not A.settings[spec.setting] then stop(); return end
            if not passiveReady then
                requestState(); A.status[title]='ON — waiting for the current passive inventory'; return
            end
            if current and not spec.owns(data,current) then dirty=true end
            if dirty or os.clock()>=nextScan then rebuild(data) end
            if current and (not byId[current.id] or complete(current,data)) then
                local deleted=not byId[current.id]
                current=nil; clearing(deleted and 5.1 or gap)
            end
            local raw=type(cost)=='table' and data[cost.ItemId]
            if raw~=lastRaw then
                lastRaw=raw
                local n=tonumber(raw)
                amount=n and n==n and n<math.huge and math.max(0,n) or 0
                if blockedAmount and amount<blockedAmount then blockedAmount=amount end
            end
            if not current then
                for _,row in ipairs(rows) do
                    if not complete(row,data) and (retryAfter[row.id] or 0)<=os.clock() then current=row; break end
                end
            end
            if not current then
                if phase=='clearing' and awaitingReset(data) then
                    if os.clock()>=deadline and os.clock()>=nextAction then clearing(1); requestState() end
                    A.status[title]='ON — waiting for native queue reset'; return
                end
                A.status[title]=#rows==0 and 'ON — all eligible '..spec.plural..' have '..spec.targetName..'; watching inventory'
                    or 'ON — invalid items cooling down; watching inventory'
                return
            end
            local label=tostring(current.name)..' • '..tostring(#rows-1)..' waiting'
            if cfg.WorldId and not A.unlocked(cfg.WorldId) then
                if phase~='world' then clearing(); phase='world' end
                A.status[title]='ON — unlock World '..tostring(cfg.WorldId)..' first'; return
            elseif phase=='world' then phase='clearing' end
            local price=type(cost)=='table' and tonumber(cost.Amount)
            if not price or price<1 or price~=price or price==math.huge or type(cost.ItemId)~='string' then
                if phase~='cost' then clearing(); phase='cost' end
                requestState(); A.status[title]='Roll cost unavailable'; return
            end
            if spec.discount then price=discount:GetDiscountedGachaCost(price) end
            if not A.alive or not A.running or not A.settings[spec.setting] then stop(); return end
            if type(price)~='number' or price<1 or price~=price or price==math.huge then
                if phase~='cost' then clearing(); phase='cost' end
                A.status[title]='Discounted roll cost unavailable'; return
            elseif phase=='cost' then phase='clearing' end
            if (amount or 0)<price or (blockedAmount and (amount or 0)<=blockedAmount) then
                if phase~='funds' then clearing(); phase='funds' end
                A.status[title]='ON — paused: need '..tostring(price)..' '..cost.ItemId..' per roll; '..label
                return
            elseif phase=='funds' then blockedAmount=nil; phase='clearing' end
            if os.clock()<nextAction then A.status[title]='ON — waiting for the previous roller to stop; '..label; return end
            local busy=queueUI.Config.IsBusy()
            local active=queueUI.Config.GetActiveKey()
            local saved=type(data.AutoRollStates)=='table' and data.AutoRollStates[spec.kind]
            local savedKey=type(saved)=='table' and saved.Active==true and saved.Key or nil
            local nativeQueue=type(data.RollQueues)=='table' and data.RollQueues[spec.kind] or {}
            if phase=='clearing' then
                if busy or savedKey or (type(nativeQueue)=='table' and #nativeQueue>0) then
                    if os.clock()>=deadline then clearing(1); requestState() end
                    A.status[title]='ON — waiting for native queue reset; '..label; return
                end
                -- Only one key is ever handed to the server. The rest stays locally sorted.
                if spec.sync then controller:SyncPlayerData() end
                if not A.alive or not A.running or not A.settings[spec.setting] then stop(); return end
                phase='starting'; deadline=os.clock()+12
                advanceUntil=os.clock()+6.1
                writeQueue(queueUtil,spec.kind,{current.id},function() return owned and A.alive and A.running and A.settings[spec.setting] end)
            elseif phase=='starting' then
                if busy then advanceUntil=math.max(advanceUntil,os.clock()+6.1) end
                -- The native container/result listeners select the queued item. Do not
                -- call that yielding selection method concurrently with its listeners.
                if savedKey==current.id and busy and active==current.id then
                    phase='rolling'; advanceUntil=math.max(advanceUntil,os.clock()+6.1)
                elseif type(nativeQueue)=='table' and nativeQueue[1]==current.id and not busy and not savedKey then
                    advanceUntil=os.clock()+6.1
                    controller:BeginQueueAdvance()
                elseif os.clock()>=deadline then
                    retryAfter[current.id]=os.clock()+60; current=nil; dirty=true; clearing(5.1)
                    A.status[title]='Native queue did not confirm; item deferred for 60 seconds'; return
                end
            elseif phase=='rolling' then
                if active~=current.id or (savedKey and savedKey~=current.id)
                    or (type(nativeQueue)=='table' and #nativeQueue>0) then
                    clearing(5.1)
                    A.status[title]='Native item selection changed; restoring the current item'; return
                end
                if not busy then
                    -- A Divine roll notification alone is not proof that it was retained.
                    requestState(); clearing(5.1); return
                end
            end
            A.status[title]='ON — '..(phase=='rolling' and 'rolling ' or 'starting ')..label
        end
        A.passiveQueues[spec.kind]={stop=stop,wake=kick,active=function()
            return phase=='starting' or phase=='rolling' or phase=='clearing'
        end}
        A.job(title,0.25,function()
            local ok,err=pcall(step)
            if not ok then stop(); error(err) end
        end)
    end
end

end)()(A);

-- ===== pet_passives =====
(function()
return function(A)
    local stats
    local rarities={Common=true,Uncommon=true,Rare=true,Epic=true,Legendary=true,Mythical=true,Secret=true,Divine=true,Astral=true}
    A.createPassiveQueue({kind='PetPassive',title='Pet passives',setting='petPassiveAuto',
        target='DivinePredator',targetName='Divine Predator',plural='pets',
        config='PetPassiveConfig',controller='PetPassiveController',discount=true,sync=true,
        inventoryField='Pets',passiveField='PetPassives',data=A.petData,
        invalid={pet_not_owned=true},state='PetPassiveState',stateRequest='PetPassiveStateRequest',result='PetPassiveResult',
        observe=A.onPetInventory,
        snapshot=function(data) return data and data.PetPassives end,
        retained=function(data,row) return type(data.PetPassives)=='table' and data.PetPassives[row.id] end,
        owns=function(data,row) return type(data.Pets[row.id])=='table' end,
        prepare=function()
            stats=A.util('PetStatsUtil')
            return stats and type(stats.GetPetData)=='function' and type(stats.GetRarity)=='function'
                and type(stats.IsDynamic)=='function' and type(stats.GetBaseMultiplier)=='function'
        end,
        rows=function(data)
            local out={}
            for id,pet in pairs(data.Pets) do
                if type(id)=='string' and id~='' and type(pet)=='table' then
                    local ok,row=pcall(function()
                        local catalog=stats.GetPetData(pet)
                        if type(catalog)~='table' then return nil end
                        local dynamic=stats.IsDynamic(pet)==true
                        if not dynamic and not rarities[stats.GetRarity(pet)] then return nil end
                        local power=tonumber(stats.GetBaseMultiplier(pet))
                        if not power or power~=power or power<0 or power==math.huge then return nil end
                        local bonus=dynamic and type(catalog.DynamicMultiplier)=='table' and tonumber(catalog.DynamicMultiplier.BonusPercent) or 0
                        if not bonus or bonus~=bonus or math.abs(bonus)==math.huge then bonus=0 end
                        return {id=id,dynamic=dynamic,power=power,bonus=bonus or 0,name=stats.GetName and stats.GetName(pet) or pet.PetId}
                    end)
                    if ok and row then
                        out[#out+1]=row
                    end
                end
            end
            return out
        end,
    })
    A.stopPetPassives=A.passiveQueues.PetPassive.stop
end

end)()(A);

-- ===== equipment_passives =====
(function()
return function(A)
    local rarities={Common=true,Uncommon=true,Rare=true,Epic=true,Legendary=true,Mythical=true,Secret=true,Divine=true,Astral=true}
    local function number(value)
        local n=tonumber(value)
        return n and n==n and n>=0 and n<math.huge and n or nil
    end
    local function copies(value)
        local n=number(value)
        return n and math.floor(n) or 0
    end
    local function row(id,item,power,extra)
        power=number(power)
        if type(id)~='string' or id=='' or type(item)~='table' or not rarities[item.Rarity] or not power then return nil end
        local result=extra or {}
        result.id=id; result.name=item.Name or id; result.dynamic=false; result.power=power
        return result
    end
    local function add(out,value) if value then out[#out+1]=value end end
    local function mapSpec(spec)
        spec.data=A.data
        spec.result=spec.kind..'Result'
        spec.snapshot=function(data) return data and data[spec.passiveField] end
        spec.retained=function(data,item)
            local values=data[spec.passiveField]
            if type(values)~='table' then return nil end
            local value=values[item.passiveKey or item.id]
            if value==nil and item.legacyKey then value=values[item.legacyKey] end
            return value
        end
        if not spec.curse then
            spec.discount=true; spec.sync=true
            spec.state=spec.kind..'State'; spec.stateRequest=spec.kind..'StateRequest'
        end
        return spec
    end
    local accessories
    A.createPassiveQueue(mapSpec({kind='AccessoryCurse',title='Accessory curses',setting='accessoryCurseAuto',
        config='AccessoryCurseConfig',controller='AccessoryCurseController',target='CalamityCurse',targetName='Calamity Curse',
        plural='accessories',inventoryField='Accessories',passiveField='AccessoryCurses',curse=true,patch=false,
        gap=0.7,explicitClear=true,invalid={accessory_not_owned=true},
        unwrap=function(result)
            if type(result)~='table' then return nil,nil,nil end
            return result.Success,result.Reason,result.Payload
        end,
        prepare=function()
            accessories=A.config('AccessoryConfig')
            return accessories and type(accessories.GetItem)=='function'
        end,
        owns=function(data,item) return type(data.Accessories[item.id])=='table' end,
        rows=function(data)
            local out={}
            for uid,owned in pairs(data.Accessories) do
                if type(owned)=='table' then
                    local item=accessories:GetItem(owned.Id)
                    local stats=type(item)=='table' and item.Multiplier
                    -- Rank native base Power; accessories without Power follow those that have it.
                    add(out,row(uid,item,type(stats)=='table' and (stats.Power or 0)))
                end
            end
            return out
        end,
    }))
    local swords,keys
    A.createPassiveQueue(mapSpec({kind='SwordPassive',title='Sword passives',setting='swordPassiveAuto',
        config='SwordPassiveConfig',controller='SwordPassiveController',target='SunBreathing',targetName='Sun Breathing',
        plural='swords',inventoryField='ActiveSwords',passiveField='SwordPassives',invalid={sword_not_owned=true},
        prepare=function()
            swords=A.config('SwordConfig'); keys=A.util('SwordCopyKeyUtil')
            return swords and type(swords.GetSword)=='function' and keys and type(keys.Encode)=='function'
                and type(keys.ToPassiveKey)=='function' and type(keys.Owns)=='function' and type(keys.CountCopies)=='function'
        end,
        owns=function(data,item) return keys.Owns(data,item.id)==true end,
        rows=function(data)
            local out={}
            for world,owned in pairs(data.ActiveSwords) do
                local banner=type(world)=='string' and swords:GetSword(world)
                if type(banner)=='table' and type(banner.Items)=='table' and type(owned)=='table' then
                    for rarity,levels in pairs(owned) do
                        local item=banner.Items[rarity]
                        if type(item)=='table' and rarities[rarity] then
                            local function levelRows(level)
                                local count=copies(keys.CountCopies(data,world,rarity,level))
                                for index=1,count do
                                    local id=keys.Encode(world,rarity,level,index)
                                    add(out,row(id,{Name=item.Name,Rarity=rarity},item.Multiplier,
                                        {level=level,passiveKey=keys.ToPassiveKey(id),
                                            legacyKey=index==1 and (world..'_'..rarity..'_'..level) or nil}))
                                end
                            end
                            if type(levels)=='number' then levelRows(0)
                            elseif type(levels)=='table' then
                                for level in pairs(levels) do
                                    local n=number(level)
                                    if type(level)=='string' and n and n==math.floor(n) and tostring(n)==level then levelRows(n) end
                                end
                            end
                        end
                    end
                end
            end
            return out
        end,
    }))
    local titans,titanConfig
    A.createPassiveQueue(mapSpec({kind='TitanPassive',title='Titan passives',setting='titanPassiveAuto',
        config='TitanPassiveConfig',controller='TitanPassiveController',target='Rumbling',targetName='Rumbling',
        plural='titans',inventoryField='ActiveTitans',passiveField='TitanPassives',invalid={titan_not_owned=true},
        prepare=function()
            titans=A.config('TitansConfig'); titanConfig=A.config('TitanPassiveConfig')
            return titans and type(titans.GetTitan)=='function' and titanConfig and type(titanConfig.BuildKey)=='function'
        end,
        owns=function(data,item)
            local owned=data.ActiveTitans[item.world]
            return type(owned)=='table' and item.index<=copies(owned[item.rarity])
        end,
        rows=function(data)
            local out={}
            for world,owned in pairs(data.ActiveTitans) do
                local banner=type(world)=='string' and titans:GetTitan(world)
                if type(banner)=='table' and type(banner.Items)=='table' and type(owned)=='table' then
                    for rarity,count in pairs(owned) do
                        local item=banner.Items[rarity]
                        if type(item)=='table' and rarities[rarity] then
                            for index=1,copies(count) do
                                add(out,row(titanConfig:BuildKey(world,rarity,index),{Name=item.Name,Rarity=rarity},item.Multiplier,
                                    {world=world,rarity=rarity,index=index}))
                            end
                        end
                    end
                end
            end
            return out
        end,
    }))
    local shadows,skin,fingerprints=nil,nil,{}
    local shadowSpec=mapSpec({kind='ShadowPassive',title='Shadow passives',setting='shadowPassiveAuto',
        config='ShadowPassiveConfig',controller='ShadowPassiveController',target='GrandMarshal',targetName='Grand Marshal',
        plural='shadows',inventoryField='ShadowCopies',passiveField='ShadowCopies',patch=false,
        invalid={shadow_not_owned=true,skin_cosmetic_only=true},
        prepare=function()
            shadows=A.config('ShadowsConfig'); skin=A.util('SkinRarityUtil')
            return shadows and type(shadows.GetShadow)=='function' and skin and type(skin.IsSkinEntry)=='function'
        end,
        owns=function(data,item)
            local owned=data.ShadowCopies[item.id]
            return type(owned)=='table' and owned.ShadowKey==item.shadowKey
        end,
        rows=function(data)
            local out={}
            for uid,owned in pairs(data.ShadowCopies) do
                if type(owned)=='table' then
                    local item=shadows:GetShadow(owned.ShadowKey)
                    if type(item)=='table' and not skin.IsSkinEntry(item) then
                        -- Shadows grant damage percentage, not a base Power multiplier.
                        add(out,row(uid,item,item.DamagePercent,{shadowKey=owned.ShadowKey}))
                    end
                end
            end
            return out
        end,
    })
    shadowSpec.snapshot=function(data)
        if not data or type(data.ShadowCopies)~='table' then return nil end
        local out={}
        for uid,owned in pairs(data.ShadowCopies) do
            if type(owned)=='table' then out[uid]=owned.Passive or false end
        end
        return out
    end
    shadowSpec.retained=function(data,item)
        local owned=data.ShadowCopies[item.id]
        return type(owned)=='table' and owned.Passive
    end
    shadowSpec.inventoryChanged=function(data)
        if not data or type(data.ShadowCopies)~='table' then return false end
        local changed=false; local updated={}
        for uid,owned in pairs(data.ShadowCopies) do
            updated[uid]=type(owned)=='table' and owned.ShadowKey or false
            if updated[uid]~=fingerprints[uid] then changed=true end
        end
        for uid in pairs(fingerprints) do if updated[uid]==nil then changed=true end end
        fingerprints=updated
        return changed
    end
    A.createPassiveQueue(shadowSpec)
end

end)()(A);

-- ===== farming =====
(function()
return function(A)
    local C=A.Core
    local movingHuman,resolveEnemy
    local walkTarget,walkDestination,walkAt,lastDistance,lastProgress=nil,nil,0,nil,0
    local streamBusy,nextStream=false,0
    local function requestGround(position,target,world)
        if streamBusy or os.clock()<nextStream or type(A.player.RequestStreamAroundAsync)~='function' then return end
        streamBusy=true; nextStream=os.clock()+10; local epoch=A.epoch
        task.spawn(function()
            if A.alive and A.running and A.epoch==epoch and A.currentTarget==target
                and tostring(A.settings.world)==tostring(world) then
                pcall(A.player.RequestStreamAroundAsync,A.player,position)
            end
            streamBusy=false
        end)
    end
    function A.mobAllowed(world,id)
        local key=tostring(world)
        local selected=A.settings.mobsByWorld[key]
        local mode=A.settings.mobSelectionModeByWorld[key]
        if mode=='all' then return true end
        if mode=='selected' then return type(selected)=='table' and selected[id]==true end
        return type(selected)=='table' and selected[id]==true
    end
    function A.setMobSelection(world,values,all)
        world=tostring(world)
        A.settings.mobsByWorld[world]=C.trueKeys(values)
        A.settings.mobSelectionModeByWorld[world]=all and 'all' or 'selected'
        -- A deliberate selection edit cancels an excluded target; HP changes never do.
        if A.currentTarget and not all then
            local key=resolveEnemy and resolveEnemy(A.currentTarget.Name,world)
            if not key or not A.mobAllowed(world,key) then A.watchTarget(nil); A.stopFarmMovement() end
        end
        if A.tasks.Farm then A.tasks.Farm.next=0 end
    end
    function A.stopFarmMovement()
        if movingHuman then pcall(function() movingHuman:Move(Vector3.zero) end); movingHuman=nil end
        walkTarget=nil; walkDestination=nil; lastDistance=nil; lastProgress=0
    end
    function A.inMode()
        local ctrl=A.client('TeleportController')
        return (ctrl and ctrl:IsInGamemode()) or false
    end
    function A.travel(world)
        local wanted=tonumber(world)
        if not wanted then A.status.Farm='Choose a valid world'; return false end
        local current=tonumber(A.currentWorld())
        local context=A.player:GetAttribute('VisibilityContext')
        local contextWorld=type(context)=='string' and tonumber(context:match('^World:(%d+)$')) or nil
        local attributeWorld=tonumber(A.player:GetAttribute('CurrentWorldId'))
        local ctrl=A.client('TeleportController')
        local loading=ctrl and ctrl.IsLoading and ctrl:IsLoading()
        -- Never treat a local/controller value alone as proof of server world membership.
        local verified=(contextWorld==wanted or attributeWorld==wanted or A.confirmedWorld==wanted)
            and (current==nil or current==wanted)
            and (contextWorld==nil or contextWorld==wanted)
            and (attributeWorld==nil or attributeWorld==wanted)
        if verified and not loading and not A.inMode() then
            A.worldTransition=nil; return true
        end
        A.worldTransition=wanted; A.watchTarget(nil)
        local character=A.player.Character
        local human=character and character:FindFirstChildOfClass('Humanoid')
        if human then human:Move(Vector3.zero) end
        if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false end
        if A.inMode() then A.status.Farm='Waiting for the current mode to finish'; return false end
        if not A.unlocked(wanted) then A.status.Farm='World locked: '..wanted; return false end
        A.status.Farm='Waiting for registered World '..wanted..' (current '..tostring(contextWorld or attributeWorld or current or 'unknown')..')'
        if loading then return false end
        if A.ready('travel',5) then
            if not A.fire('RequestChangeWorld',wanted) then A.status.Farm='World teleport request failed' end
        end
        return false
    end
    resolveEnemy=function(name,world)
        local lookup=A.catalog.enemyLookup and A.catalog.enemyLookup[tostring(world)]
        local row=lookup and lookup[name]
        if row then return row.key,row.info end
        for key,e in pairs(A.catalog.enemies) do
            if ((e.World or e.WorldId)==nil or tostring(e.World or e.WorldId)==tostring(world)) and (key==name or e.Name==name or e.ModelName==name) then return key,e end
        end
    end
    local function enemyHealth(enemy)
        if enemy:GetAttribute('EnemyDead')==true then return false end
        local big=A.util('BigNum'); local real=enemy:GetAttribute('HealthReal')
        if real~=nil and big then
            local ok,alive,health=pcall(function()
                local value=big.Decode(real)
                if value==nil then return nil end
                return big.IsPositive(value),big.Log10(value)
            end)
            if ok and alive~=nil then return alive,health end
        end
        local hum=enemy:FindFirstChildOfClass('Humanoid')
        if not hum then return nil end
        return hum.Health>0,math.log10(math.max(hum.Health,1e-300))
    end
    A.enemyHealth=enemyHealth
    function A.findEnemies(world)
        local folders={}
        local root=workspace:FindFirstChild('Worlds')
        local w=root and root:FindFirstChild(tostring(world))
        local f=w and w:FindFirstChild('Enemies'); if f then folders[#folders+1]=f end
        local items={}; local char=A.player.Character; local hrp=char and char:FindFirstChild('HumanoidRootPart')
        if not hrp then return items end
        for _,folder in ipairs(folders) do
            for _,enemy in ipairs(folder:GetChildren()) do
                local part=enemy:FindFirstChild('HumanoidRootPart')
                local id,info=resolveEnemy(enemy.Name,world)
                local allowed=id and A.mobAllowed(world,id)
                local alive,health=enemyHealth(enemy)
                if allowed and part and alive==true
                    and enemy:GetAttribute('EnemyDead')~=true and enemy:GetAttribute('IsClientVisualClone')~=true
                    and not A.S.Players:GetPlayerFromCharacter(enemy) and id then
                    items[#items+1]={model=enemy,part=part,health=health,distance=(part.Position-hrp.Position).Magnitude,
                        id=enemy:GetFullName(),label=info and info.Name or enemy.Name}
                end
            end
        end
        return items
    end
    A.targetConnections={}
    function A.watchTarget(target)
        if A.currentTarget==target then return end
        for _,c in ipairs(A.targetConnections) do pcall(function() c:Disconnect() end) end
        A.targetConnections={}; A.currentTarget=target
        A.targetWorld=target and tostring(A.settings.world) or nil
        if not target then return end
        local function died()
            if not A.alive or not A.running or A.currentTarget~=target then return end
            if target.Parent and enemyHealth(target)~=false then return end
            A.watchTarget(nil)
            task.defer(function()
                if A.alive and A.running and A.runJob then
                    A.runJob(A.tasks.Farm)
                end
            end)
        end
        local hum=target:FindFirstChildOfClass('Humanoid')
        if hum then
            A.targetConnections[#A.targetConnections+1]=hum.Died:Connect(died)
            A.targetConnections[#A.targetConnections+1]=hum:GetPropertyChangedSignal('Health'):Connect(died)
        end
        A.targetConnections[#A.targetConnections+1]=target:GetAttributeChangedSignal('HealthReal'):Connect(died)
        A.targetConnections[#A.targetConnections+1]=target:GetAttributeChangedSignal('EnemyDead'):Connect(function()
            if target:GetAttribute('EnemyDead') then died() end
        end)
        A.targetConnections[#A.targetConnections+1]=target.AncestryChanged:Connect(function(_,parent) if not parent then died() end end)
    end
    A.job('Farm',0.2,function()
        if not A.data() then A.status.Farm='Waiting for player data'; return end
        local char=A.player.Character; local hrp=char and char:FindFirstChild('HumanoidRootPart')
        local hum=char and char:FindFirstChildOfClass('Humanoid')
        if not hrp or not hum or hum.Health<=0 then A.stopFarmMovement(); A.status.Farm='Waiting for respawn'; return end
        if not A.settings.farm or (A.activityBlocksFarm and A.activityBlocksFarm()) or A.inMode() or (A.trialContext and A.trialContext()) then
            A.watchTarget(nil)
            A.stopFarmMovement()
            if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false; hum:Move(Vector3.zero) end
            return
        end
        local targetMode=A.settings.target; local world=A.settings.world
        if not A.travel(world) then return end
        local ctrl=A.client('TeleportController'); if ctrl and ctrl:IsLoading() then return end
        local chosen
        local target=A.currentTarget
        if target and (A.targetWorld~=tostring(world) or not target.Parent or enemyHealth(target)==false) then
            A.watchTarget(nil); target=nil
        end
        if target then
            -- Selection and HP ranking changes only affect the NEXT target.
            local part=target:FindFirstChild('HumanoidRootPart')
            if not part then A.status.Farm='Target locked; waiting for its root part'; return end
            chosen={model=target,part=part,label=target.Name,distance=(part.Position-hrp.Position).Magnitude}
        else
            chosen=C.chooseTarget(A.findEnemies(world),targetMode)
            if not chosen then A.stopFarmMovement(); A.status.Farm='Waiting for a live selected enemy'; return end
            A.watchTarget(chosen.model)
        end
        if hrp.Anchored or hum.Sit then A.stopFarmMovement(); A.status.Farm='Waiting for game character release'; return end
        local destination=chosen.part.Position+Vector3.new(0,0,A.settings.distance)
        if chosen.distance>A.settings.distance+2 then
            if A.settings.moveStyle=='Teleport' then
                A.stopFarmMovement()
                if type(workspace.Raycast)=='function' and RaycastParams then
                    local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances={char,chosen.model}
                    local hit=workspace:Raycast(destination+Vector3.new(0,8,0),Vector3.new(0,-24,0),params)
                    if not hit then
                        requestGround(destination,chosen.model,world)
                        A.status.Farm='Waiting for streamed ground near the selected target'; return
                    end
                    destination=Vector3.new(destination.X,hit.Position.Y+hum.HipHeight+hrp.Size.Y/2,destination.Z)
                end
                hrp.CFrame=CFrame.new(destination,chosen.part.Position)
            else
                if movingHuman~=hum or walkTarget~=chosen.model then
                    A.stopFarmMovement(); movingHuman=hum; walkTarget=chosen.model; lastProgress=os.clock()
                end
                if not lastDistance or chosen.distance<lastDistance-1 then lastProgress=os.clock(); lastDistance=chosen.distance end
                if os.clock()-lastProgress>=6 then
                    destination=destination+Vector3.new(math.sin(os.clock())>=0 and 3 or -3,0,0)
                    hum:Move(Vector3.new(.2,0,0),false); lastProgress=os.clock(); lastDistance=chosen.distance
                end
                if not walkDestination or (destination-walkDestination).Magnitude>1 or os.clock()-walkAt>=2 then
                    walkAt=os.clock(); walkDestination=destination; hum:MoveTo(destination)
                end
            end
        else A.stopFarmMovement() end
        -- The game's range system owns damage validation; no fabricated damage/hits.
        local d=A.data()
        if d.RangeState~=true and A.ready('rangeOn',4) then
            if A.fire('RangeToggle',true) then A.rangeOwned=true end
        end
        A.status.Farm='Target: '..chosen.label
    end)
end

end)()(A);

-- ===== trial_follow =====
(function()
return function(A)
    local function install(kind,bridge,folder,toggle,label,keyField)
        local activeKey,target,loadingSince,endedKey
        local mapReady,state={},{}
        local streamBusy,nextStream=false,0
        local generationBusy=false
        local stalledSince,lastReportAt=nil,0
        local function getContext()
            local context=A.player:GetAttribute('VisibilityContext')
            return type(context)=='string' and context:match('^'..kind..':(.+)$') or nil
        end
        local movingHuman,movementRoot,movementKey,anchor
        local function stopMovement()
            if movingHuman then pcall(function() movingHuman:Move(Vector3.zero,false) end) end
            movingHuman=nil; movementRoot=nil; movementKey=nil; anchor=nil
        end
        local function followMovement()
            if not A.running or not A.settings[toggle] or (A.activityExitPending and A.activityExitPending()) then stopMovement(); return end
            local key=getContext()
            if not key or endedKey==key then stopMovement(); return end
            local character=A.player.Character
            local root=character and character:FindFirstChild('HumanoidRootPart')
            local human=character and character:FindFirstChildOfClass('Humanoid')
            if not root or not human or human.Health<=0 or root.Anchored or human.Sit then
                stopMovement(); return
            end
            if movingHuman~=human or movementRoot~=root or movementKey~=key then
                stopMovement(); movingHuman=human; movementRoot=root; movementKey=key
            end
            -- Recenter after a room teleport; small steps should never pull back to the old room.
            if not anchor or (root.Position-anchor).Magnitude>6 then anchor=root.Position end
            local phase=os.clock()*2
            local dx=anchor.X+math.cos(phase)*0.75-root.Position.X
            local dz=anchor.Z+math.sin(phase)*0.75-root.Position.Z
            local length=math.sqrt(dx*dx+dz*dz)
            if length>0.05 then
                human:Move(Vector3.new(dx/length*0.2,0,dz/length*0.2),false)
            else human:Move(Vector3.zero,false) end
        end
        A[kind=='Trial' and 'trialContext' or 'dungeonContext']=getContext
        A['stop'..kind..'Movement']=stopMovement
        local renderName='JoesAAS'..kind..'Movement'
        local renderBound=false
        if A.S.Run.BindToRenderStep then
            local ok=pcall(function()
                A.S.Run:BindToRenderStep(renderName,Enum.RenderPriority.Input.Value+1,function()
                    if A.alive then followMovement() end
                end)
            end)
            renderBound=ok
        end
        if not renderBound then A.connect(A.S.Run.Heartbeat,followMovement) end
        A['cleanup'..kind..'Movement']=function()
            stopMovement()
            if renderBound then A.S.Run:UnbindFromRenderStep(renderName); renderBound=false end
        end
        A.on(bridge..'MapReady',function(key,room,generation,position,token)
            if type(key)~='string' or (getContext() and getContext()~=key) then return end
            mapReady={key=key,room=tonumber(room) or 1,generation=generation,position=position,token=token,at=os.clock()}
            state={[keyField]=key,Room=tonumber(room) or 1}
            endedKey=nil
        end)
        A.on(bridge..'State',function(packet)
            if type(packet)~='table' or packet.Refused or not A.runEventMatches(bridge,packet) then return end
            if packet.Full or (packet[keyField] and packet[keyField]~=state[keyField]) then state={} end
            for k,v in pairs(packet) do if k~='Full' and k~='Cleared' then state[k]=v end end
            for _,k in ipairs(type(packet.Cleared)=='table' and packet.Cleared or {}) do state[k]=nil end
        end)
        A.on(bridge..'Ended',function(first,second)
            if not A.runEventMatches(bridge,A.endPacket(first,second)) then return end
            stopMovement(); endedKey=getContext(); target=nil; mapReady={}; state={}
        end)
        if kind=='Dungeon' then
            A.on('DungeonRoomReady',function(key,room,_,__,cycle,generation,token)
                if key~=getContext() or cycle~=true or type(generation)~='number' or type(token)~='string' then return end
                if mapReady.key==key and mapReady.generation==generation and mapReady.token==token then return end
                mapReady={key=key,room=tonumber(room) or 1,generation=generation,token=token,at=os.clock(),cycle=true}
                state.Room=mapReady.room; endedKey=nil; target=nil; stopMovement()
            end)
        end
        local function roomSpawn(arena,index)
            local rooms=arena and arena:FindFirstChild('Rooms')
            if kind=='Dungeon' then
                local cfg=A.config('DungeonConfig')
                local entry=cfg and type(cfg.GetDungeon)=='function' and cfg:GetDungeon(getContext())
                local count=entry and tonumber(entry.TemplateRoomCount)
                if count and count>0 then index=((index-1)%count)+1 end
            end
            local room=rooms and rooms:FindFirstChild('Room'..tostring(index))
            local spawn=room and room:FindFirstChild('Spawn',true)
            return spawn and spawn:IsA('BasePart') and spawn or nil
        end
        local function recoverLoading(key,arena)
            local room=state[keyField]==key and state.Room or (mapReady.key==key and mapReady.room)
            local spawn=room and roomSpawn(arena,room)
            local position=spawn and spawn.Position or (mapReady.key==key and mapReady.position)
            if position and not streamBusy and os.clock()>=nextStream then
                nextStream=os.clock()+10; streamBusy=true
                task.spawn(function()
                    if A.alive and A.running and A.settings[toggle] and getContext()==key then
                        local ok,err=pcall(function() A.player:RequestStreamAroundAsync(position) end)
                        A.status[label..' streaming']=ok and 'Requested current room streaming' or ('Streaming request failed: '..tostring(err))
                    end
                    streamBusy=false
                end)
            end
            if kind=='Dungeon' and mapReady.key==key and not generationBusy and (mapReady.attempts or 0)<3
                -- The native generator can wait 25s for its template. Let that call
                -- finish before using the same controller for recovery.
                and os.clock()-mapReady.at>=27 and os.clock()>=(mapReady.nextAck or 0)
                and type(mapReady.generation)=='number' and type(mapReady.token)=='string'
                and (not room or room==mapReady.room) then
                local ctrl=A.client('DungeonController')
                if ctrl and type(ctrl.GenerateRoomsThrough)=='function' then
                    local request=mapReady
                    request.attempts=(request.attempts or 0)+1; request.nextAck=os.clock()+10
                    generationBusy=true; local epoch=A.epoch
                    task.spawn(function()
                        if A.alive and A.running and A.epoch==epoch and A.settings[toggle] and getContext()==key and mapReady==request
                            and (state.Room==nil or state.Room==request.room) then
                            local ok,generated=true,roomSpawn(arena,request.room)~=nil
                            if not generated then ok,generated=pcall(ctrl.GenerateRoomsThrough,ctrl,key,request.room,request.cycle==true) end
                            if ok and generated==true and A.alive and A.running and A.epoch==epoch and A.settings[toggle]
                                and getContext()==key and mapReady==request
                            and (state.Room==nil or state.Room==request.room) then
                                request.acknowledged=true
                                A.fire(bridge..'ClientReady',key,request.generation,request.token)
                            end
                        end
                        generationBusy=false
                    end)
                end
            end
            if kind=='Trial' and mapReady.key==key and (mapReady.attempts or 0)<3 and os.clock()-mapReady.at>=3
                and os.clock()>=(mapReady.nextAck or 0)
                and type(mapReady.generation)=='number' and type(mapReady.token)=='string'
                and (not room or room==mapReady.room) and roomSpawn(arena,mapReady.room) then
                -- Bounded retries of the acknowledgement issued for this exact loaded room.
                mapReady.acknowledged=true; mapReady.attempts=(mapReady.attempts or 0)+1
                mapReady.nextAck=os.clock()+10
                A.fire(bridge..'ClientReady',key,mapReady.generation,mapReady.token)
            end
        end
        local function stalled(message,key,root,arena,enemies)
            A.status[label..' follow']=message
            stalledSince=stalledSince or os.clock()
            if os.clock()-stalledSince<5 then return end
            if root and not endedKey then recoverLoading(key,arena) end
            if os.clock()-lastReportAt<60 then return end
            lastReportAt=os.clock()
            pcall(function()
                if type(writefile)~='function' then return end
                local samples={}
                for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
                    if #samples>=12 then break end
                    local h=enemy:FindFirstChildOfClass('Humanoid')
                    samples[#samples+1]={name=enemy.Name,health=h and h.Health,real=tostring(enemy:GetAttribute('HealthReal')),
                        dead=enemy:GetAttribute('EnemyDead'),clone=enemy:GetAttribute('IsClientVisualClone'),
                        context=enemy:GetAttribute('VisibilityContext'),hasRoot=enemy:FindFirstChild('HumanoidRootPart')~=nil}
                end
                local ctrl=A.client('TeleportController')
                writefile(A.folder..'/'..kind:lower()..'-diagnostics.json',A.S.HTTP:JSONEncode({version=A.version,reason=message,
                    context=A.player:GetAttribute('VisibilityContext'),room=state[keyField]==key and state.Room,
                    serverEnemies=state[keyField]==key and state.EnemyCount,anchored=root and root.Anchored,
                    loading=ctrl and ctrl:IsLoading(),mapReady=mapReady.key==key,readyRetried=mapReady.acknowledged==true,readyAttempts=mapReady.attempts or 0,
                    movementDriver=renderBound and 'after input' or 'heartbeat',
                    characterPosition=root and {x=root.Position.X,y=root.Position.Y,z=root.Position.Z},
                    hasArena=arena~=nil,hasEnemiesFolder=enemies~=nil,enemies=samples}))
            end)
        end
        A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),function()
            if getContext()~=movementKey then stopMovement() end
            if getContext()~=activeKey then target=nil; loadingSince=nil; endedKey=nil end
        end)
        A.job(label..' follow',0.2,function()
            if not A.settings[toggle] then target=nil; loadingSince=nil; stalledSince=nil; return end
            if A.activityExitPending and A.activityExitPending() then target=nil; stopMovement(); return end
            local key=getContext()
            if key~=activeKey then activeKey=key; target=nil; loadingSince=nil; stalledSince=nil end
            if not key then A.status[label..' follow']='Waiting to enter a '..label; return end
            if endedKey==key then A.status[label..' follow']=label..' ended; waiting for return teleport'; return end
            local character=A.player.Character
            local root=character and character:FindFirstChild('HumanoidRootPart')
            local human=character and character:FindFirstChildOfClass('Humanoid')
            if not root or not human or human.Health<=0 then
                target=nil; loadingSince=nil; A.status[label..' follow']='Waiting for your character to respawn'; return
            end
            local arenas=workspace:FindFirstChild(folder)
            local arena=arenas and arenas:FindFirstChild(key)
            local enemies=arena and arena:FindFirstChild('Enemies')
            if not enemies then target=nil; loadingSince=nil; stalled('Waiting for your '..label..' arena to load',key,root,arena,enemies); return end
            local function eligible(enemy)
                if enemy.Parent~=enemies or enemy:GetAttribute('IsClientVisualClone')==true then return end
                local context=enemy:GetAttribute('VisibilityContext')
                if context~=nil and context~='' and context~=kind..':'..key then return end
                if A.enemyHealth(enemy)~=true then return end
                return enemy:FindFirstChild('HumanoidRootPart')
            end
            local part=target and eligible(target)
            if not part then
                target=nil; local closest
                for _,enemy in ipairs(enemies:GetChildren()) do
                    local candidate=eligible(enemy)
                    if candidate then
                        local distance=(candidate.Position-root.Position).Magnitude
                        if not closest or distance<closest then target=enemy; part=candidate; closest=distance end
                    end
                end
            end
            if not part then loadingSince=nil; stalled('Waiting for living enemies in your '..label,key,root,arena,enemies); return end
            if root.Anchored then loadingSince=nil; stalled('Character anchored by game; waiting for release',key,root,arena,enemies); return end
            local ctrl=A.client('TeleportController')
            local loading=ctrl and ctrl:IsLoading()
            if loading then
                loadingSince=loadingSince or os.clock()
                recoverLoading(key,arena)
                if os.clock()-loadingSince<3 then A.status[label..' follow']='Waiting for '..label..' loading'; return end
                -- Recover only with a living target in our exact arena and a usable character.
                -- Do not modify the game's loading flag or join/room-ready handshake.
            else loadingSince=nil end
            stalledSince=nil
            local offset=math.min(A.settings.distance,3)
            if (part.Position-root.Position).Magnitude>offset+0.5 then
                root.CFrame=CFrame.new(part.Position+Vector3.new(0,0,offset),part.Position)
                anchor=nil
            end
            A.status[label..' follow']=(loading and 'Following own '..label..' despite stale loading flag: ' or 'Following '..label..' mob: ')..target.Name
        end)
    end
    install('Trial','TimeTrial','TimeTrialArenas','trialFollow','Trial','TrialKey')
    install('Dungeon','Dungeon','DungeonArenas','trialFollow','Dungeon','DungeonKey')
end

end)()(A);

-- ===== join_diagnostics =====
(function()
return function(A)
    local path=A.folder..'/join-diagnostics.json'
    local saved=A.safeLoad(path)
    local events,openings={},{}
    local dirty=true
    local fields={mode=true,key=true,reason=true,accepted=true,selected=true,duration=true,rank=true,
        source=true,action=true,sent=true,retry=true,autoRetry=true,timeTrialTransfer=true}
    local function clean(input)
        local result={}
        for key,value in pairs(type(input)=='table' and input or {}) do
            if fields[key] then
                if type(value)=='string' then result[key]=value:sub(1,240)
                elseif type(value)=='boolean' then result[key]=value
                elseif type(value)=='number' and value==value and math.abs(value)<1e12 then result[key]=value end
            end
        end
        return result
    end
    if type(saved)=='table' and saved.schema==1 and saved.userId==A.player.UserId and saved.gameId==game.GameId then
        for _,event in ipairs(type(saved.events)=='table' and saved.events or {}) do
            if #events>=400 then break end
            if type(event)=='table' and type(event.kind)=='string' then
                events[#events+1]={time=tonumber(event.time),kind=event.kind:sub(1,60),details=clean(event.details),
                    context=type(event.context)=='string' and event.context:sub(1,120) or nil,loading=event.loading==true}
            end
        end
    end
    local lastStatus
    function A.joinTrace(kind,details)
        if kind=='status' then
            local reason=details and details.reason
            if reason==lastStatus then return end
            lastStatus=reason
        end
        local ctrl=A.client('TeleportController')
        local ok,loading=pcall(function() return ctrl and ctrl:IsLoading() end)
        local event={time=os.time(),kind=kind,details=clean(details),
            context=A.player:GetAttribute('VisibilityContext'),loading=ok and loading==true,running=A.running}
        events[#events+1]=event; if #events>400 then table.remove(events,1) end
        if kind=='opening' then
            openings[#openings+1]={time=event.time,mode=event.details.mode,key=event.details.key,
                selected=event.details.selected,rank=event.details.rank,duration=event.details.duration}
            if #openings>40 then table.remove(openings,1) end
        end
        dirty=true
    end
    function A.flushJoinDiagnostics(force)
        if not dirty and not force then return true end
        if type(writefile)~='function' then A.status['Join diagnostics']='File writing unavailable: '..path; return false end
        local ctrl=A.client('TeleportController')
        local stateOK,gameState=pcall(function() return {loading=ctrl and ctrl:IsLoading()==true,inMode=A.inMode()} end)
        local coordinatorOK,coordinator=pcall(function() return A.joinSnapshot and A.joinSnapshot() or {} end)
        local activityJob=A.tasks.Activities
        local snapshot={schema=1,version=A.version,userId=A.player.UserId,gameId=game.GameId,
            savedAt=os.time(),context=A.player:GetAttribute('VisibilityContext'),running=A.running,
            activities=A.status.Activities,error=A.status['Activity error'],events=events,openings=openings,
            stuck=A.stuckSnapshot and A.stuckSnapshot() or {},nativeAutoGates=A.nativeAutoGates and A.nativeAutoGates() or {},
            coordinator=coordinatorOK and coordinator or {error=tostring(coordinator):sub(1,240)},
            gameState=stateOK and gameState or {error=tostring(gameState):sub(1,240)},
            eventError=A.status.Event,activityJobFailures=activityJob and activityJob.failures,settings={}}
        for _,key in ipairs({'towerAutoJoin','towerSelection','trialAutoJoin','trialJoinSelection','dungeonAutoJoin',
            'dungeonSelection','gateAutoJoin','gateSelection','gateRanks','maxTacAutoJoin','maxTacSelection','maxTacRanks','priority','raidAutoJoin','raidSelection',
            'defenseAutoJoin','defenseSelection','bossRushAutoJoin','bossRushSelection',
            'autoLeaveStuck','stuckSeconds','trialDungeonStuckSeconds'}) do snapshot.settings[key]=A.settings[key] end
        local ok,err=pcall(function()
            if type(makefolder)=='function' then pcall(makefolder,'JoesAAS'); pcall(makefolder,A.folder) end
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            writefile(path,encoded)
            if type(readfile)=='function' then assert(readfile(path)==encoded,'Diagnostic read-back failed') end
        end)
        A.status['Join diagnostics']=ok and ('Saved: '..path) or ('Save failed: '..path..' - '..tostring(err))
        if ok then dirty=false end
        return ok
    end
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),function() A.joinTrace('context',{}) end)
    A.job('Join diagnostics',5,A.flushJoinDiagnostics,true)
    A.joinTrace('script started',{})
    A.flushJoinDiagnostics(true)
end

end)()(A);

-- ===== activities =====
(function()
return function(A)
    local definitions={
        MaxTac={config='RaidConfig',method='GetAllRaids',toggle='maxTacAutoJoin',selection='maxTacSelection',ranks='maxTacRanks'},
        Tower={config='TowerConfig',method='GetAllTowers',toggle='towerAutoJoin',selection='towerSelection'},
        TimeTrial={config='TimeTrialConfig',method='GetAllTrials',toggle='trialAutoJoin',selection='trialJoinSelection'},
        Gate={config='RaidConfig',method='GetAllRaids',toggle='gateAutoJoin',selection='gateSelection',ranks='gateRanks'},
        Raid={config='RaidConfig',method='GetAllRaids',toggle='raidAutoJoin',selection='raidSelection'},
        Defense={config='DefenseConfig',method='GetAllDefenses',toggle='defenseAutoJoin',selection='defenseSelection'},
        Dungeon={config='DungeonConfig',method='GetAllDungeons',toggle='dungeonAutoJoin',selection='dungeonSelection'},
        BossRush={config='BossRushConfig',method='GetAllRushes',toggle='bossRushAutoJoin',selection='bossRushSelection'}
    }
    local order={'MaxTac','Tower','TimeTrial','Dungeon','Gate','Raid','Defense','BossRush'}
    local protected={MaxTac=true,Tower=true,TimeTrial=true,Dungeon=true}
    local available,backoff={},{}
    local pending,leaving,locked,returning,returningContext,waitingReason,stuckExit
    local stuckBackoff={}
    local stuckRetry
    local leaveAt,leaveAttempts=0,0
    local choiceCache={}
    for _,mode in ipairs(order) do available[mode]={} end
    local prioritySignature,normalizedPriority=nil,nil
    local function priorityList()
        local signature=table.concat(A.settings.priority,'|')
        if signature~=prioritySignature then
            prioritySignature=signature; normalizedPriority=A.Core.priorityOrder(A.settings.priority)
        end
        return normalizedPriority
    end
    function A.activityOrder()
        local result={}
        for _,mode in ipairs(priorityList()) do
            if mode=='Combat' then result[#result+1]='Raid'; result[#result+1]='Defense'
            else result[#result+1]=mode end
        end
        return result
    end
    local function priority(mode)
        mode=(mode=='Raid' or mode=='Defense') and 'Combat' or mode
        for i,key in ipairs(priorityList()) do if key==mode then return 8-i end end
        return 0
    end
    function A.priorityText()
        local labels={}
        for _,key in ipairs(priorityList()) do labels[#labels+1]=A.Core.priorityLabels[key] end
        return table.concat(labels,' > ')..' > Mob Autofarm'
    end
    function A.moveActivityPriority(mode,delta)
        local list=A.Core.priorityOrder(A.settings.priority)
        for i,key in ipairs(list) do
            if key==mode then
                local destination=math.clamp(i+delta,1,#list)
                list[i],list[destination]=list[destination],list[i]; break
            end
        end
        A.settings.priority=list; A.settingsChanged()
        if A.refreshUI then A.refreshUI() end
        A.coordinateActivities()
    end
    function A.resetActivityPriority()
        A.settings.priority=A.Core.copy(A.Core.defaultPriority); A.settingsChanged()
        if A.refreshUI then A.refreshUI() end
        A.coordinateActivities()
    end
    function A.activityChoices(mode)
        local def=definitions[mode]; if not def then return {} end
        local cfg=A.config(def.config)
        local cached=choiceCache[mode]
        if cached and cached.config==cfg and cached.getter==(cfg and cfg[def.method]) and cached.revision==A.catalogRevision then return cached.value end
        local choices=cfg and type(cfg[def.method])=='function' and cfg[def.method](cfg) or {}
        if mode=='BossRush' then
            local rows={}
            for key,rush in pairs(choices) do
                if type(rush.Modes)=='table' then
                    for variant,entry in pairs(rush.Modes) do
                        if (variant=='V1' or variant=='V2') and type(entry)=='table' then
                            rows[key..':'..variant]={Name=entry.Name or rush.Name or key,WorldId=rush.WorldId,
                                Cost=entry.Cost,RushKey=key,ModeId=variant,RequiresChallenge=entry.RequiresChallenge}
                        end
                    end
                end
            end
            choiceCache[mode]={config=cfg,getter=cfg and cfg[def.method],revision=A.catalogRevision,value=rows}
            return rows
        end
        if mode=='Gate' or mode=='MaxTac' or mode=='Raid' then
            local filtered={}
            for key,value in pairs(choices) do
                if (mode=='Raid' and value.GateOnly~=true) or A.Core.portalMode(key,value)==mode then filtered[key]=value end
            end
            choiceCache[mode]={config=cfg,getter=cfg and cfg[def.method],revision=A.catalogRevision,value=filtered}
            return filtered
        end
        choiceCache[mode]={config=cfg,getter=cfg and cfg[def.method],revision=A.catalogRevision,value=choices}
        return choices
    end
    -- Older profiles stored only the rush key. Keep the same V1 choice when declared.
    local rushChoices=A.activityChoices('BossRush')
    for key,selected in pairs(A.Core.copy(A.settings.bossRushSelection)) do
        if selected and not rushChoices[key] then
            local migrated=key..':V1'
            if rushChoices[migrated] then
                A.settings.bossRushSelection[key]=nil; A.settings.bossRushSelection[migrated]=true
                A.settingsChanged()
            end
        end
    end
    local rankOrders={Gate={'S','A','B','C','D','E'},MaxTac={'Low','Medium','High','Extreme','Psycho'}}
    local rankWeight={S=6,A=5,B=4,C=3,D=2,E=1,Low=5,Medium=4,High=3,Extreme=2,Psycho=1}
    local function rankRows(mode)
        local present={}; local rows={}
        for _,cfg in pairs(A.activityChoices(mode)) do
            for _,rank in ipairs(type(cfg.GateRanks)=='table' and cfg.GateRanks or {}) do
                if type(rank)=='table' and type(rank.Rank)=='string' then present[rank.Rank]=true end
            end
        end
        for _,rank in ipairs(rankOrders[mode]) do if present[rank] then rows[#rows+1]={key=rank,label=rank} end end
        return rows
    end
    function A.gateRankRows() return rankRows('Gate') end
    function A.maxTacRankRows() return rankRows('MaxTac') end
    local function portalRank(mode,key,p)
        local cfg=A.activityChoices(mode)[key]
        if not cfg then return nil end
        for _,entry in ipairs(type(cfg.GateRanks)=='table' and cfg.GateRanks or {}) do
            local rank=type(entry)=='table' and entry.Rank
            if type(rank)=='string' and rankWeight[rank] and (p.GateRank==rank
                or (type(p.Name)=='string' and p.Name:match('Rank%s+([%a]+)')==rank)
                or (type(p.Title)=='string' and p.Title:match('Rank%s+([%a]+)')==rank)) then return rank end
        end
    end
    local function candidateKeys(mode,choices)
        if mode=='TimeTrial' then return A.Core.activityKeys(choices,mode) end
        local keys=A.Core.keys(choices)
        if mode=='Gate' or mode=='MaxTac' then
            table.sort(keys,function(a,b)
                local left=available[mode][a]; local right=available[mode][b]
                local x=left and rankWeight[left.rank] or 0; local y=right and rankWeight[right.rank] or 0
                if x~=y then return x>y end
                return a<b
            end)
        end
        return keys
    end
    function A.activityRows(mode)
        local choices=A.activityChoices(mode); local rows={}
        for _,key in ipairs(A.Core.activityKeys(choices,mode)) do
            local cfg=choices[key]; local label=cfg.Name or key
            if mode~='TimeTrial' then
                local id=tonumber(cfg.WorldId)
                label=(id and ('World '..id..' | ') or 'Other | ')..label
            end
            rows[#rows+1]={key=key,label=label}
        end
        return rows
    end
    local function context()
        local raw=A.player:GetAttribute('VisibilityContext')
        local mode=type(raw)=='string' and raw:match('^([^:]+):') or nil
        if mode=='Trial' then mode='TimeTrial' end
        if mode=='Raid' then
            local instance=raw:match('^Raid:(.+)$')
            local key=A.runKey(raw) or instance
            local cfg=A.config('RaidConfig'); local entries=cfg and cfg:GetAllRaids() or {}
            if instance and not entries[key] then
                local arenas=workspace:FindFirstChild('RaidArenas')
                local arena=arenas and arenas:FindFirstChild(instance)
                local observed=arena and arena:GetAttribute('RaidKey')
                local base=instance:match('^([^_]+)_')
                if type(observed)=='string' and entries[observed] then key=observed
                elseif base and entries[base] then key=base end
            end
            if entries[key] then A.rememberRun('Raid',instance,key) end
            if entries[key] and entries[key].GateOnly==true then mode=A.Core.portalMode(key,entries[key])
            elseif not entries[key] and pending and (pending.mode=='Gate' or pending.mode=='MaxTac') and raw~=pending.fromContext then
                mode='UnidentifiedRaid' -- Metadata must establish a portal before acquiring its lock.
            end
        end
        return mode~='World' and mode or nil,raw
    end
    A.activityContext=context
    function A.activityExitPending() return stuckExit~=nil end
    local function enabled(mode,key)
        local def=definitions[mode]
        return A.settings[def.toggle] and A.settings[def.selection][key]==true
    end
    local function selectCandidate()
        waitingReason=nil
        for _,mode in ipairs(A.activityOrder()) do
            local choices=A.settings[definitions[mode].toggle] and (stuckBackoff[mode] or 0)<=os.clock() and A.activityChoices(mode) or {}
            for _,key in ipairs(candidateKeys(mode,choices)) do
                if enabled(mode,key) and (backoff[mode..':'..key] or 0)<=os.clock() then
                    local entry=available[mode][key]
                    if mode=='Tower' then
                        local cfg=A.config('TowerConfig'); local util=A.util('TowerStateUtil'); local d=A.data()
                        local tower=choices[key]
                        if cfg and cfg.Enabled~=false and util and d and A.unlocked(tower.WorldId)
                            and util.GetCooldownRemaining(d,tower)<=0 then return mode,key,{} end
                    elseif mode=='Gate' or mode=='MaxTac' then
                        if entry and entry.deadline>os.clock() then
                            if not entry.rank then waitingReason=mode..' rank not provided; waiting for a ranked announcement'
                            elseif A.settings[definitions[mode].ranks][entry.rank]==true then return mode,key,A.Core.copy(entry) end
                        end
                    elseif mode~='Raid' and mode~='Defense' and mode~='BossRush' and entry and entry.deadline>os.clock() then return mode,key,entry
                    elseif mode=='Raid' or mode=='Defense' or mode=='BossRush' then
                        local cfg=choices[key]
                        local data=A.data()
                        local progress=data and type(data.BossRushProgress)=='table' and data.BossRushProgress[cfg.RushKey]
                        if cfg.GateOnly then waitingReason=mode..': portal-only entry; own-run creation unavailable'
                        elseif cfg.WorldId and not A.unlocked(cfg.WorldId) then
                            waitingReason=mode..': unlock World '..tostring(cfg.WorldId)
                        elseif not data then waitingReason='Waiting for player data'
                        elseif cfg.RequiresChallenge and (type(progress)~='table' or progress.ChallengeCompleted~=true) then
                            waitingReason=mode..': complete the native Challenge first'
                        else
                            local cost=cfg.Cost
                            if type(cost)=='table' and A.balance(cost.ItemId)<(tonumber(cost.Amount) or 1) then
                                waitingReason=mode..': need '..tostring(cost.Amount or 1)..' '..tostring(cost.ItemId)
                            else return mode,key,{action='Create',rushKey=cfg.RushKey or key,modeId=cfg.ModeId or 'V1'} end
                        end
                    end
                end
            end
        end
    end
    local function status(text) A.status.Activities=text; A.status['Trial join']=text; A.joinTrace('status',{reason=text}) end
    local function suspendFarm()
        A.watchTarget(nil)
        A.stopFarmMovement()
        if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false end
        -- Followers stop their own movement separately; do not zero another script's input.
    end
    function A.activityBlocksFarm()
        local mode=context()
        return mode~=nil or pending~=nil or leaving~=nil or locked~=nil or returning~=nil or stuckExit~=nil
    end
    function A.requestStuckExit(mode,raw)
        local current,contextRaw=context()
        if not A.alive or not A.running or not A.settings.autoLeaveStuck or not definitions[mode]
            or current~=mode or raw~=contextRaw or pending or leaving or returning or stuckExit
            or (stuckRetry and stuckRetry.mode==mode and stuckRetry.context==raw and stuckRetry.untilTime>os.clock()) then return false end
        stuckExit={mode=mode,context=raw,attempts=0,lastSent=-math.huge}
        pending=nil; locked=nil
        suspendFarm()
        if A.stopTrialMovement then A.stopTrialMovement() end
        if A.stopDungeonMovement then A.stopDungeonMovement() end
        A.joinTrace('stuck timeout',{mode=mode,reason='No run or combat progress within configured timeout'})
        A.coordinateActivities()
        return true
    end
    local function sendRequest(mode,key,entry)
        if mode=='Gate' or mode=='MaxTac' then return A.fire('RaidGateTeleport',key) end
        if mode=='Tower' then return A.fire('TowerJoin',{TowerKey=key}) end
        if mode=='Raid' or (mode=='Defense' and entry.action=='Create') then return A.fire(mode..'Join','Create',key,true) end
        if mode=='BossRush' then return A.fire('BossRushJoin','Create',entry.rushKey or key,entry.modeId or 'V1') end
        return A.fire(mode..'Join',entry.action or 'Join',key)
    end
    local function sendJoin(mode,key,entry)
        local epoch=A.epoch; local raw=select(2,context())
        A.joinTrace('join request',{mode=mode,key=key,action=entry.action or 'Join',rank=entry.rank})
        if not A.alive or not A.running or A.epoch~=epoch or select(2,context())~=raw then return false end
        if not enabled(mode,key) then return false end
        if definitions[mode].ranks then
            local live=available[mode][key]
            if not live or live.deadline<=os.clock() or live.rank~=entry.rank
                or A.settings[definitions[mode].ranks][entry.rank]~=true then return false end
        end
        local sent=sendRequest(mode,key,entry)
        A.joinTrace('join sent',{mode=mode,key=key,sent=sent==true})
        return sent
    end
    local coordinating,coordinateAgain=false,false
    local function coordinateOnce()
        local epoch=A.epoch
        if not A.alive or not A.running then return end
        if A.settings.raidAutoJoin and A.settings.defenseAutoJoin then A.settings.defenseAutoJoin=false end
        local current,raw=context()
        local ctrl=A.client('TeleportController')
        local loading=ctrl and ctrl:IsLoading()
        if not A.alive or not A.running or A.epoch~=epoch then return end
        if select(2,context())~=raw then coordinateAgain=true; return end
        if stuckRetry and raw~=stuckRetry.context then stuckRetry=nil end
        if returning and current and returningContext and raw~=returningContext then returning=nil; returningContext=nil end
        if stuckExit and not A.settings.autoLeaveStuck then stuckExit=nil end
        if stuckExit then
            local exit=stuckExit
            if current and raw~=exit.context then
                -- A new instance or direct native transfer is already confirmed.
                stuckBackoff[exit.mode]=os.clock()+30; stuckExit=nil
            elseif not current and not A.inMode() and not loading then
                stuckBackoff[exit.mode]=os.clock()+30; stuckExit=nil
                locked=nil; returning=nil; leaving=nil
            else
                if raw==exit.context and os.clock()-exit.lastSent>=5 then
                    if exit.attempts>=3 then
                        stuckBackoff[exit.mode]=os.clock()+30; stuckExit=nil
                        stuckRetry={mode=exit.mode,context=exit.context,untilTime=os.clock()+30}
                        if protected[current] and returning~=current then locked=current end
                        A.status['Activity error']='Stuck '..exit.mode..' exit not confirmed; retry in 30s'
                        A.status['Stuck recovery']=A.status['Activity error']
                        status(A.status['Activity error']); return
                    end
                    exit.attempts=exit.attempts+1; exit.lastSent=os.clock()
                    local bridge=(exit.mode=='Gate' or exit.mode=='MaxTac') and 'RaidLeave' or exit.mode..'Leave'
                    local sent=A.fire(bridge)
                    A.joinTrace('stuck leave request',{mode=exit.mode,sent=sent,retry=exit.attempts>1})
                    A.status['Stuck recovery']='Leaving stuck '..exit.mode..' · attempt '..exit.attempts..'/3'
                end
                status('Waiting for stuck '..exit.mode..' exit confirmation'); return
            end
        end
        if protected[current] and returning~=current then locked=current end
        if type(raw)=='string' and raw:match('^World:') and not A.inMode() and not loading then
            locked=nil; returning=nil; leaving=nil
        end
        if pending and not pending.accepted and not loading and not protected[current] then
            local waiting=pending
            local nextMode=selectCandidate()
            if not A.alive or not A.running or A.epoch~=epoch then return end
            if pending~=waiting or select(2,context())~=raw then coordinateAgain=true; return end
            if nextMode and priority(nextMode)>priority(pending.mode) then pending=nil end
        end
        if pending then
            if os.clock()-pending.at>=60 then
                backoff[pending.mode..':'..pending.key]=os.clock()+30
                A.status['Activity error']='Entry timed out: '..pending.mode..'; waiting for native state before retrying'
                pending=nil
                if loading then status(A.status['Activity error']); return end
            end
        end
        if pending then
            if current==pending.mode and (A.runKey(raw)==pending.key or (current~='Gate' and current~='MaxTac' and current~='TimeTrial' and current~='Dungeon')) then
                pending=nil; returning=nil
            elseif protected[current] and returning~=current then pending=nil
            elseif not loading and (not current or definitions[current]) then
                local entry=available[pending.mode][pending.key]
                local scheduled=pending.mode~='Tower' and pending.entry.action~='Create'
                if not enabled(pending.mode,pending.key) or (scheduled and (not entry or entry.deadline<=os.clock()))
                    or (definitions[pending.mode].ranks and (not entry or not entry.rank or not A.settings[definitions[pending.mode].ranks][entry.rank] or entry.rank~=pending.entry.rank)) then
                    pending=nil
                elseif not pending.accepted and os.clock()-pending.lastSent>=8 then
                    if pending.attempts<3 then
                        pending.attempts=pending.attempts+1; pending.lastSent=os.clock()
                        sendJoin(pending.mode,pending.key,pending.entry)
                        status('Retrying '..pending.mode..' entry: '..pending.key); return
                    else
                        backoff[pending.mode..':'..pending.key]=os.clock()+5; pending=nil
                    end

                else status('Waiting for '..pending.mode..' entry confirmation'); return end
            else status('Waiting for '..pending.mode..' entry confirmation'); return end
        end
        if locked then status(locked..' locked until the run ends'); return end
        if loading then status('Blocked by game loading'); return end
        local mode,key,entry=selectCandidate()
        if not A.alive or not A.running or A.epoch~=epoch then return end
        if select(2,context())~=raw or pending then coordinateAgain=true; return end
        if mode and not enabled(mode,key) then coordinateAgain=true; return end
        if mode and definitions[mode].ranks then
            local live=available[mode][key]
            if not live or live.deadline<=os.clock() or live.rank~=entry.rank
                or A.settings[definitions[mode].ranks][entry.rank]~=true then coordinateAgain=true; return end
        end
        if not mode then status(current and ('In '..current) or (waitingReason or 'Waiting for a selected activity')); return end
        local direct=mode=='MaxTac' or mode=='Tower' or mode=='TimeTrial' or mode=='Dungeon'
        if leaving and not direct then
            if os.clock()-leaveAt>=5 then
                if leaveAttempts<3 then
                    leaveAttempts=leaveAttempts+1; leaveAt=os.clock()
                    A.fire((leaving=='Gate' or leaving=='MaxTac') and 'RaidLeave' or leaving..'Leave')
                else
                    A.status['Activity error']='No '..leaving..' exit confirmation; retrying later'
                    backoff[mode..':'..key]=os.clock()+30; leaving=nil; status(A.status['Activity error']); return
                end
            end
            status('Waiting for '..leaving..' exit confirmation'); return
        end
        if current then
            local def=definitions[current]
            if not def then status('Waiting for current mode to finish'); return end
            -- Finished protected runs may transfer next; unfinished ones stay locked above.
            if returning~=current and priority(mode)<=priority(current) then status('Current '..current..' has equal/higher priority than '..mode); return end
            if not direct then
                if returning==current then status('Waiting for '..current..' return teleport'); return end
                leaving=current; leaveAt=os.clock(); leaveAttempts=1; suspendFarm(); status('Leaving '..current..' for '..mode)
                if not A.fire((current=='Gate' or current=='MaxTac') and 'RaidLeave' or current..'Leave') then leaving=nil; status('Leave bridge unavailable: '..current) end
                return
            end
        elseif returning then status('Waiting for '..returning..' return teleport'); return
        elseif A.inMode() then status('Waiting for current mode to finish'); return end
        if direct then leaving=nil end
        pending={mode=mode,key=key,entry=A.Core.copy(entry),at=os.clock(),lastSent=os.clock(),attempts=1,fromContext=raw}
        suspendFarm()
        status(current and ('Transferring '..current..' to '..mode..': '..key)
            or ((mode=='Raid' and 'Starting your own Raid: ' or ('Joining '..mode..': '))..key))
        if not sendJoin(mode,key,entry) then
            backoff[mode..':'..key]=os.clock()+5; pending=nil; status('Join bridge unavailable: '..mode)
        end
    end
    function A.coordinateActivities()
        if coordinating then coordinateAgain=true; return end
        coordinating=true
        local ok,err=pcall(function()
            local passes=0
            repeat
                coordinateAgain=false; passes=passes+1; coordinateOnce()
            until not coordinateAgain or not A.alive or not A.running or passes>=8
        end)
        coordinating=false
        if coordinateAgain and A.tasks.Activities then A.tasks.Activities.next=0 end
        if not ok then error(err) end
    end
    A.tryTrialJoin=A.coordinateActivities
    for _,name in ipairs(order) do
        local mode=name
        if mode~='Gate' and mode~='MaxTac' then
        if mode~='Raid' then A.on(mode..'Announcement',function(p)
            if type(p)~='table' or p.NotifyKind~='GamemodeOpen' or p.GamemodeType~=mode or type(p.Key)~='string' then return end
            -- A raid gate announcement is a world gate teleport, not a joinable raid.
            if p.GateTeleport then return end
            A.joinTrace('opening',{mode=mode,key=p.Key,selected=enabled(mode,p.Key),duration=tonumber(p.ExpiresIn),source='bridge'})
            local duration=tonumber(p.ExpiresIn) or 10
            if duration<=0 or duration~=duration then return end
            available[mode][p.Key]={deadline=os.clock()+math.min(duration,600),modeId=p.ModeId}
            A.coordinateActivities()
        end) end
        A.on(mode..'Ended',function(first,second)
            local packet=A.endPacket(first,second)
            local _,raw=context()
            if not A.runEventMatches(mode,packet,raw,A.runKey(raw)) then return end
            A.joinTrace('run ended',{mode=mode,autoRetry=type(packet)=='table' and packet.AutoRetry==true,timeTrialTransfer=type(packet)=='table' and packet.TimeTrialTransfer==true})
            local current=context()
            -- The native portal transfer can deliver the previous Raid's end
            -- after MaxTac entry; that packet must not end the new locked run.
            if mode=='Raid' and type(packet)=='table' and packet.AutoGateTransfer==true
                and (current=='MaxTac' or locked=='MaxTac') then A.coordinateActivities(); return end
            local ended=mode=='Raid' and ((current=='MaxTac' or locked=='MaxTac') and 'MaxTac'
                or ((current=='Gate' or locked=='Gate') and 'Gate')) or mode
            if (current==ended or locked==ended) and A.settings.webhook then
                A.notify('Mode',ended..' run ended'..(type(packet)=='table' and packet.AutoRetry==true and ' (native auto retry)' or ''))
            end
            if current==ended or locked==ended then locked=nil; returning=ended; returningContext=select(2,context()) end
            if pending and (pending.mode==mode or pending.mode==ended) then pending=nil end
            A.coordinateActivities()
        end)
        if mode=='TimeTrial' or mode=='Dungeon' then
            A.on(mode..'MapReady',function(instance)
                local current,raw=context()
                -- These modes reuse their arena key across runs. A fresh map
                -- after Ended confirms a new run even without a World context.
                if current~=mode or returning~=mode or raw~=returningContext
                    or instance~=raw:match('^[^:]+:(.+)$') then return end
                if stuckExit then stuckBackoff[stuckExit.mode]=os.clock()+30; stuckExit=nil end
                stuckRetry=nil; returning=nil; returningContext=nil; locked=mode
                A.joinTrace('run restarted',{mode=mode,reason='Own map ready after run ended'})
                A.coordinateActivities()
            end)
        end
        if mode~='Tower' then
            A.on(mode..'Join',function(accepted,reason,replyKey)
                A.joinTrace('server reply',{mode=mode,accepted=accepted==true,reason=tostring(reason)})
                if not pending or pending.mode~=mode then return end
                if (mode=='TimeTrial' or mode=='Dungeon') and type(replyKey)=='string' and replyKey~=pending.key then
                    A.joinTrace('ignored reply',{mode=mode,key=replyKey,reason='Reply belongs to a different selected run'}); return
                end
                if accepted==true then pending.accepted=true end
                if accepted==false then
                    local key=pending.key
                    if mode=='Defense' and reason=='defense_already_active' then
                        backoff[mode..':'..key]=os.clock()+30
                    else
                        if reason=='no_active_raid' or reason=='no_active_defense' or reason=='join_closed' or reason=='trial_closed' or reason=='dungeon_closed' then available[mode][key]=nil end
                        backoff[mode..':'..key]=os.clock()+(mode=='Raid' and 30 or 5)
                    end
                    pending=nil
                    A.status['Activity error']=mode..' refused: '..tostring(reason)
                    status(A.status['Activity error'])
                end
            end)
        end
    end
    end
    A.on('RaidAnnouncement',function(p)
        if type(p)~='table' or p.NotifyKind~='GamemodeOpen' or p.GateTeleport~=true or type(p.Key)~='string' then return end
        local duration=tonumber(p.ExpiresIn) or 60
        if duration<=0 or duration~=duration then return end
        local cfg=A.config('RaidConfig'); local entries=cfg and cfg:GetAllRaids() or {}
        local mode=A.Core.portalMode(p.Key,entries[p.Key])
        if mode~='Gate' and mode~='MaxTac' then return end
        local rank=portalRank(mode,p.Key,p)
        A.joinTrace('opening',{mode=mode,key=p.Key,rank=rank,selected=enabled(mode,p.Key) and rank~=nil and A.settings[definitions[mode].ranks][rank]==true,duration=duration,source='bridge'})
        available[mode][p.Key]={deadline=os.clock()+math.min(duration,600),rank=rank}
        A.coordinateActivities()
    end)
    A.on('RaidMapReady',A.coordinateActivities)
    A.on('RaidState',A.coordinateActivities)
    A.on('TowerState',function(p)
        if type(p)=='table' and p.Refused then A.joinTrace('server reply',{mode='Tower',accepted=false,reason=tostring(p.Refused)}) end
        if type(p)=='table' and p.Refused and pending and pending.mode=='Tower' then
            backoff['Tower:'..pending.key]=os.clock()+10; pending=nil
            A.status['Activity error']='Tower refused: '..tostring(p.Refused)
            status(A.status['Activity error'])
        end
    end)
    local lastTrialSchedule,hasTrialSchedule,trialScheduleOpen
    A.on('TimeTrialActiveStatus',function(_,p)
        if type(p)~='table' then return end
        hasTrialSchedule=true; trialScheduleOpen=p.IsOpen==true
        local signature=tostring(p.IsOpen)..':'..table.concat(A.Core.keys(type(p.OpenTrialKeys)=='table' and p.OpenTrialKeys or {[p.OpenTrialKey or '']=true}),',')
        if signature~=lastTrialSchedule then A.joinTrace('Trial schedule',{mode='TimeTrial',key=p.OpenTrialKey,reason=signature}); lastTrialSchedule=signature end
        available.TimeTrial={}
        if p.IsOpen==true then
            local keys=p.OpenTrialKeys or {[p.OpenTrialKey or '']=true}
            for key,value in pairs(keys) do
                if type(key)=='string' and value==true then available.TimeTrial[key]={deadline=math.huge} end
            end
        end
        A.coordinateActivities()
    end)
    -- Native popup attributes provide recovery when injection happens after the
    -- announcement. Read only the small notification containers, never the scene.
    local observedRoots=setmetatable({},{__mode='k'})
    local function readCard(card)
        if not card:IsA('GuiObject') or card.Visible~=true or not card.Parent then return end
        local setting=card:GetAttribute('GamemodePopupSettingKey')
        if type(setting)~='string' then return end
        local mode,key=setting:match('^([^:]+):(.+)$')
        if mode=='Portal' or card:GetAttribute('GamemodePopupIsPortal')==true then
            local cfg=A.config('RaidConfig'); local entries=cfg and cfg:GetAllRaids() or {}
            mode=A.Core.portalMode(key,entries[key])
        end
        local modeId=mode=='BossRush' and key:match('^[^:]+:(.+)$') or nil
        if mode=='BossRush' and not modeId then
            local base,variant=key:match('^(.*)_(%w+)$') -- Native Boss Rush setting-key format.
            if base then key=base..':'..variant; modeId=variant end
        end
        if not definitions[mode] or mode=='Raid' or not key or not enabled(mode,key) then return end
        if mode=='TimeTrial' and hasTrialSchedule and not trialScheduleOpen then return end
        local cfg=A.activityChoices(mode)[key]; if not cfg then return end
        local ranked=definitions[mode].ranks~=nil
        local rank=ranked and portalRank(mode,key,{GateRank=card:GetAttribute('GamemodePopupGateRank')}) or nil
        if ranked and not rank then return end
        local entry=available[mode][key]
        if not entry or entry.deadline<=os.clock() or (ranked and entry.rank~=rank) then
            available[mode][key]={deadline=os.clock()+1,rank=rank,modeId=modeId,source='popup'}
            A.joinTrace('opening',{mode=mode,key=key,rank=rank,selected=true,source='native popup'})
        elseif entry.source=='popup' then entry.deadline=os.clock()+1 end
    end
    function A.refreshOpenCards()
        local pg=A.player:FindFirstChildOfClass('PlayerGui'); if not pg then return end
        local hud=pg:FindFirstChild('HUD'); local main=hud and hud:FindFirstChild('Main')
        local overlay=pg:FindFirstChild('GamemodeNotifyOverlay')
        local roots={}
        for _,parent in ipairs({main or false,overlay or false}) do
            local root=parent and parent:FindFirstChild('GamemodeNotify')
            if root then roots[#roots+1]=root end
        end
        for old,connection in pairs(observedRoots) do
            if not old.Parent then connection:Disconnect(); observedRoots[old]=nil end
        end
        for _,root in ipairs(roots) do
            if not observedRoots[root] and root.ChildAdded then
                observedRoots[root]=A.connect(root.ChildAdded,function(card)
                    readCard(card); A.coordinateActivities()
                end)
            end
            if root.Visible~=false then for _,card in ipairs(root:GetChildren()) do readCard(card) end end
        end
    end
    A.job('Opening recovery',0.5,function()
        for _,mode in ipairs(order) do
            if A.settings[definitions[mode].toggle] then A.refreshOpenCards(); A.coordinateActivities(); return end
        end
    end)
    function A.joinSnapshot()
        local openings={}
        for mode,entries in pairs(available) do
            openings[mode]={}
            for key,entry in pairs(entries) do
                openings[mode][key]={open=entry.deadline>os.clock(),remaining=entry.deadline==math.huge and 'until schedule closes' or math.max(0,entry.deadline-os.clock()),rank=entry.rank}
            end
        end
        return {pending=pending and {mode=pending.mode,key=pending.key,accepted=pending.accepted==true,
            attempts=pending.attempts,rank=pending.entry.rank,age=os.clock()-pending.at},locked=locked,leaving=leaving,returning=returning,available=openings,
            stuckExit=stuckExit and {mode=stuckExit.mode,context=stuckExit.context,attempts=stuckExit.attempts},
            stuckRecovery=A.stuckSnapshot and A.stuckSnapshot() or nil}
    end
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),A.coordinateActivities)
    local lastNotifiedContext
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),function()
        local mode,raw=context()
        if raw==lastNotifiedContext then return end
        lastNotifiedContext=raw
        if mode and definitions[mode] and A.settings.webhook then A.notify('Mode','Entered '..mode..': '..raw) end
    end)
    function A.nativeAutoGates()
        local util=A.util('SettingsStateUtil')
        if util and type(util.Get)=='function' then
            local values=util:Get('AutoGates'); return type(values)=='table' and A.Core.copy(values) or {}
        end
        return {}
    end
    A.job('Native join conflicts',2,function()
        local values=A.nativeAutoGates(); local conflicts={}
        if A.settings.maxTacAutoJoin then
            for rank,on in pairs(values) do
                if on==true and A.defaults.maxTacRanks[rank]~=nil and A.settings.maxTacRanks[rank]~=true then conflicts[#conflicts+1]=rank end
            end
        end
        A.status['Native join conflicts']=#conflicts>0
            and ('Game Auto Gate can independently join unselected MaxTac threats: '..table.concat(conflicts,', ')..'. Disable those ranks in game settings.')
            or 'JoesAAS selections apply to its requests; independent auto-join scripts may still enter other modes.'
    end)
    A.job('Activities',0.2,A.coordinateActivities)
end

end)()(A);

-- ===== stuck_recovery =====
(function()
return function(A)
    local specs={MaxTac={bridge='Raid',folder='RaidArenas',key='RaidKey'},Gate={bridge='Raid',folder='RaidArenas',key='RaidKey'},
        Raid={bridge='Raid',folder='RaidArenas',key='RaidKey'},Defense={bridge='Defense',folder='DefenseArenas',key='DefenseKey'},
        Tower={bridge='Tower',folder='TowerArenas',key='TowerKey'},BossRush={bridge='BossRush',folder='BossRushArenas',key='RushKey'},
        TimeTrial={bridge='TimeTrial',folder='TimeTrialArenas',key='TrialKey'},Dungeon={bridge='Dungeon',folder='DungeonArenas',key='DungeonKey'}}
    local watch
    local observed={'Wave','Room','Floor','EnemyCount','Alive','Phase','ShieldBoss','JoinTimeLeft','LandingTimeLeft'}
    local function valid(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
    function A.stuckTimeout(mode)
        local key=(mode=='TimeTrial' or mode=='Dungeon') and 'trialDungeonStuckSeconds' or 'stuckSeconds'
        local value=tonumber(A.settings[key])
        return valid(value) and math.clamp(value,1,3600) or A.defaults[key]
    end
    local function arenaFor(mode,raw)
        local arenas=workspace:FindFirstChild(specs[mode].folder)
        return arenas and arenas:FindFirstChild(raw:match('^[^:]+:(.+)$'))
    end
    local function current()
        if not A.alive or not A.running or not A.settings.autoLeaveStuck then watch=nil; return end
        local mode,raw=A.activityContext()
        if not specs[mode] or type(raw)~='string' then watch=nil; return end
        if not watch or watch.context~=raw or watch.mode~=mode then
            watch={mode=mode,context=raw,lastProgress=os.clock(),state={},deaths={},phase=nil,graceUntil=0}
        end
        return watch
    end
    local function progress(w,reason)
        w.lastProgress=os.clock(); w.reason=reason
    end
    local function isDead(enemy)
        if enemy:GetAttribute('EnemyDead')==true then return true end
        local real=enemy:GetAttribute('HealthReal')
        if real~=nil then
            local big=A.util('BigNum')
            if big and type(big.Decode)=='function' and type(big.Compare)=='function' then
                local ok,decoded=pcall(big.Decode,real)
                if ok and decoded~=nil then
                    local compared,result=pcall(big.Compare,decoded,0)
                    if compared and type(result)=='number' then return result<=0 end
                end
            end
            local n=tonumber(real)
            if valid(n) then return n<=0 end
        end
        local human=enemy:FindFirstChildOfClass('Humanoid')
        return human~=nil and valid(human.Health) and human.Health<=0
    end
    local function phaseGrace(w)
        local phase=w.state.Phase
        if phase==w.phase then return end
        if w.phase~=nil then progress(w,'Run phase advanced') end
        w.phase=phase; w.graceUntil=0
        if w.mode~='Tower' then return end
        local cfg=A.config('TowerConfig') or {}
        local entries=A.activityChoices('Tower')
        local tower=entries[w.key] or {}
        local seconds
        if phase=='Joining' then seconds=tonumber(w.state.JoinTimeLeft) or tonumber(tower.JoinWindowSeconds) or 25
        elseif phase=='Landing' then seconds=tonumber(w.state.LandingTimeLeft) or tonumber(cfg.LandingDecisionSeconds) or 20
        elseif phase=='Rising' then seconds=tonumber(cfg.FloorTransitionSeconds) or 2 end
        if valid(seconds) then w.graceUntil=os.clock()+math.clamp(seconds,0,60) end
    end
    local function gateGrace(w)
        if w.mode~='Gate' or tonumber(w.state.EnemyCount)~=0 then return end
        local mode=A.activityChoices('Gate')[w.key]
        local wave=tonumber(w.state.Wave)
        local every=mode and tonumber(mode.BossEvery)
        if not wave or wave<=0 or not every or every<=0 or wave%every~=0 or w.ariseWave==wave then return end
        w.ariseWave=wave
        local delay=mode.ShadowArise and tonumber(mode.ShadowArise.WaveDelay)
        if valid(delay) then w.graceUntil=math.max(w.graceUntil,os.clock()+math.clamp(delay,0,60)) end
    end
    local function receive(prefix,packet)
        if type(packet)~='table' or packet.Refused then return end
        local w=current()
        if not w or specs[w.mode].bridge~=prefix or w.ended then return end
        local instance=w.context:match('^[^:]+:(.+)$')
        if packet.InstanceKey and packet.InstanceKey~=instance then return end
        local key=packet[specs[w.mode].key]
        if prefix=='TimeTrial' or prefix=='Dungeon' then
            if key and key~=instance then return end
        elseif key and w.key and key~=w.key then return end
        -- Keyed/full packets establish ownership; ignore unassociated deltas.
        if not w.associated and not packet.Full and not packet.InstanceKey and not key then return end
        w.associated=true; if key then w.key=key end
        local old=w.state
        local nextState=packet.Full and {} or A.Core.copy(old)
        for _,field in ipairs(observed) do if packet[field]~=nil then nextState[field]=A.Core.copy(packet[field]) end end
        for _,field in ipairs(type(packet.Cleared)=='table' and packet.Cleared or {}) do nextState[field]=nil end
        for _,field in ipairs({'Wave','Room','Floor'}) do
            local before,after=tonumber(old[field]),tonumber(nextState[field])
            if after and (not before or after>before) then progress(w,field..' advanced') end
        end
        for _,field in ipairs({'EnemyCount','Alive'}) do
            local before,after=tonumber(old[field]),tonumber(nextState[field])
            if before and after and after<before then progress(w,'Enemies defeated') end
        end
        local beforePhase=type(old.ShieldBoss)=='table' and old.ShieldBoss.Phase
        local afterPhase=type(nextState.ShieldBoss)=='table' and nextState.ShieldBoss.Phase
        if beforePhase and afterPhase and beforePhase~=afterPhase then progress(w,'Boss phase advanced') end
        w.state=nextState; phaseGrace(w); gateGrace(w)
    end
    for _,prefix in ipairs({'Raid','Defense','Tower','TimeTrial','Dungeon','BossRush'}) do
        local name=prefix
        A.on(name..'State',function(packet) receive(name,packet) end)
        A.on(name..'Ended',function(first,second)
            local packet=A.endPacket(first,second)
            local w=current()
            if not w or specs[w.mode].bridge~=name or not A.runEventMatches(name,packet,w.context,w.key) then return end
            if name=='Raid' and w.mode=='MaxTac' and type(packet)=='table' and packet.AutoGateTransfer==true then return end
            if type(packet)=='table' and packet.InstanceKey and packet.InstanceKey~=w.context:match('^[^:]+:(.+)$') then return end
            w.ended=true; w.deaths={}
        end)
        if name~='Tower' then A.on(name..'MapReady',function(instance,detail,generation)
            local w=current()
            if not w or specs[w.mode].bridge~=name or instance~=w.context:match('^[^:]+:(.+)$') then return end
            local room=(name=='TimeTrial' or name=='Dungeon') and tonumber(detail)
            if w.ended then
                watch=nil; w=current()
            end
            w.associated=true
            if room and generation~=nil and generation~=w.generation then
                w.generation=generation; w.graceUntil=math.max(w.graceUntil,os.clock()+30)
            end
            if room and (not tonumber(w.state.Room) or room>tonumber(w.state.Room)) then
                w.state.Room=room; progress(w,'Room loaded')
            end
        end) end
    end
    A.on('DungeonRoomReady',function(key,room,_,__,cycle,generation)
        local w=current()
        if not w or w.mode~='Dungeon' or key~=w.context:match('^[^:]+:(.+)$') then return end
        if cycle==true and generation~=nil and generation~=w.generation then
            w.generation=generation; w.graceUntil=math.max(w.graceUntil,os.clock()+30)
        end
        if tonumber(room) and tonumber(room)>(tonumber(w.state.Room) or 0) then
            w.state.Room=tonumber(room); progress(w,'Dungeon room advanced')
        end
    end)
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),current)
    function A.stuckSnapshot()
        local w=watch
        return w and {mode=w.mode,context=w.context,key=w.key,timeout=A.stuckTimeout(w.mode),
            idle=math.max(0,os.clock()-math.max(w.lastProgress,w.graceUntil)),reason=w.reason,ended=w.ended==true} or {}
    end
    A.job('Stuck recovery',0.5,function()
        local w=current()
        if not A.settings.autoLeaveStuck then A.status['Stuck recovery']='Disabled'; return end
        if not w then A.status['Stuck recovery']='Watching game modes · normal world farming is unaffected'; return end
        if A.activityExitPending() then return end
        local coordinator=A.joinSnapshot()
        if w.ended or coordinator.returning then A.status['Stuck recovery']='Run ended; waiting for normal return'; return end
        if coordinator.pending or coordinator.leaving then
            -- Entry requests have their own bounded 60-second deadline. Never turn a
            -- pending request into repeated proof of combat progress.
            A.coordinateActivities()
            coordinator=A.joinSnapshot()
            if coordinator.pending or coordinator.leaving then
                A.status['Stuck recovery']='Waiting for bounded activity transfer confirmation'; return
            end
        end
        local arena=arenaFor(w.mode,w.context)
        if arena and not w.key then w.key=arena:GetAttribute(specs[w.mode].key) end
        local enemies=arena and arena:FindFirstChild('Enemies')
        local nextDeaths={}
        local observer=A.client('EnemyController')
        for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
            local context=enemy:GetAttribute('VisibilityContext')
            local visible=enemy:GetAttribute('IsClientVisualClone')~=true and (context==nil or context=='' or context==w.context)
            if visible and observer and type(observer.IsGamemodeEnemyVisibleLocally)=='function' then
                local ok,value=pcall(observer.IsGamemodeEnemyVisibleLocally,observer,enemy)
                visible=ok and value==true
            end
            if visible then
                local dead=isDead(enemy)
                if dead and w.deaths[enemy]==false then progress(w,'Enemy defeated') end
                nextDeaths[enemy]=dead
            end
        end
        w.deaths=nextDeaths
        if os.clock()<w.graceUntil then
            A.status['Stuck recovery']=w.mode..' · normal run transition ('..math.ceil(w.graceUntil-os.clock())..'s)'; return
        end
        local idle=os.clock()-math.max(w.lastProgress,w.graceUntil)
        local timeout=A.stuckTimeout(w.mode)
        A.status['Stuck recovery']=w.mode..' · no progress '..string.format('%.1f',idle)..'/'..timeout..'s'
        if idle>=timeout then A.requestStuckExit(w.mode,w.context) end
    end)
end

end)()(A);

-- ===== cyber =====
(function()
return function(A)
    local pending,nextAttempt=nil,0
    function A.ripperdocRows()
        local cfg=A.config('RipperdocConfig'); local rows={}
        for _,slot in ipairs(cfg and cfg.SlotOrder or {}) do rows[#rows+1]={key=slot,label=slot} end
        return rows
    end
    local gigPending,gigNext=nil,0
    local gigBackoff,petBackoff={},{}
    local function gigKey(action,index,gig) return action..':'..index..':'..tostring(gig.Id) end
    local function allowed(action,index,gig) return (gigBackoff[gigKey(action,index,gig)] or 0)<=os.clock() end
    local ranked,rankingDirty,rankingAt=nil,true,0
    A.job('Fixer gigs',0.2,function()
        if not A.alive or not A.running then return end
        if not A.settings.fixerAutoClaim and not A.settings.fixerAutoDeploy and not gigPending then
            A.status['Fixer gigs']='Fixer automation is OFF'; return
        end
        for key,deadline in pairs(gigBackoff) do if deadline<=os.clock() then gigBackoff[key]=nil end end
        for uid,deadline in pairs(petBackoff) do if deadline<=os.clock() then petBackoff[uid]=nil end end
        local cfg=A.config('FixerGigConfig'); local util=A.util('FixerGigUtil'); local d=A.petData()
        if not cfg or cfg.Enabled~=true or not util or not d then A.status['Fixer gigs']='Waiting for gig data'; return end
        -- An unavailable replication snapshot is not evidence of a successful claim.
        if type(d.FixerGigs)~='table' or type(d.FixerGigs.Board)~='table' then
            A.status['Fixer gigs']='Waiting for the gig board'; return
        end
        local board=util.GetBoard(d)
        if gigPending then
            local current=board[gigPending.index]
            local confirmed=gigPending.action=='Claim' and type(current)=='table' and current.Id==gigPending.id
                and type(current.PetUid)~='string' and current.EndsAt==nil
                or (gigPending.action=='Send' and type(current)=='table' and current.Id==gigPending.id
                    and current.PetUid==gigPending.pet and type(current.EndsAt)=='number' and current.EndsAt>0)
            if confirmed then
                A.status['Fixer gigs']=gigPending.action=='Claim' and ('Claimed completed gig '..gigPending.index)
                    or ('Deployed pet rank '..gigPending.rank..' to gig '..gigPending.index)
                if A.settings.webhook then A.notify('Progress',A.status['Fixer gigs']) end
                gigPending=nil; rankingDirty=true
            elseif gigPending.action=='Claim' and (type(current)~='table' or current.Id~=gigPending.id
                or (type(current.PetUid)=='string' and (current.PetUid~=gigPending.pet or current.EndsAt~=gigPending.endsAt))) then
                gigPending=nil; rankingDirty=true; gigNext=os.clock()+1
                A.status['Fixer gigs']='Gig board changed; claim not confirmed'; return
            elseif gigPending.action=='Send' and (type(current)~='table' or current.Id~=gigPending.id
                or (type(current.PetUid)=='string' and current.PetUid~=gigPending.pet)) then
                gigPending=nil; rankingDirty=true; gigNext=os.clock()+1
                A.status['Fixer gigs']='Gig changed before deployment; checking the new board'; return
            elseif A.requestInFlight('FixerGigAction') and os.clock()-gigPending.at>=20 then
                A.status['Fixer gigs']='Gig request still in flight; result unknown, no duplicate will be sent'; return
            elseif os.clock()-gigPending.at<20 then
                A.status['Fixer gigs']='Waiting for gig '..(gigPending.action=='Claim' and 'claim' or 'deployment')..' confirmation'; return
            else
                gigBackoff[gigKey(gigPending.action,gigPending.index,{Id=gigPending.id})]=os.clock()+120
                if gigPending.action=='Send' then petBackoff[gigPending.pet]=os.clock()+120 end
                gigPending=nil
                A.status['Fixer gigs']='Gig action unconfirmed; retrying after 120s'; return
            end
        end
        if not A.settings.fixerAutoClaim and not A.settings.fixerAutoDeploy then
            A.status['Fixer gigs']='Fixer automation is OFF'; return
        end
        if os.clock()<gigNext then return end
        if A.requestInFlight('FixerGigAction') then A.status['Fixer gigs']='Waiting for the previous gig request'; return end
        if not A.unlocked(cfg.WorldId) then A.status['Fixer gigs']='Unlock Night City first'; return end
        local ctrl=A.client('TeleportController')
        if ctrl and ctrl:IsLoading() then A.status['Fixer gigs']='Waiting for game loading'; return end
        local index,gig,action,pet,rank
        if A.settings.fixerAutoClaim then
            for i,value in ipairs(board) do
                if util.IsReady(value,os.time()) and allowed('Claim',i,value) then index=i; gig=value; action='Claim'; break end
            end
        end
        if not action and A.settings.fixerAutoDeploy then
            local slots=tonumber(d.FixerGigs.Slots) or cfg:GetSlots(d)
            if util.CountActive(d)<slots then
                local indices={}
                for i in ipairs(board) do indices[#indices+1]=i end
                if A.settings.fixerPreference=='Big Jobs first' then
                    table.sort(indices,function(a,b)
                        local x=board[a].Duration=='Long' and 1 or 0
                        local y=board[b].Duration=='Long' and 1 or 0
                        if x~=y then return x>y end; return a<b
                    end)
                end
                for _,i in ipairs(indices) do
                    local value=board[i]
                    if type(value)=='table' and type(value.PetUid)~='string' and allowed('Send',i,value) then
                        index=i; gig=value; break
                    end
                end
                if index then
                    if type(d.Pets)~='table' then A.status['Fixer gigs']='Waiting for pet inventory'; return end
                    local power=A.util('PetPowerUtil')
                    if not power or type(power.BuildRanking)~='function' then
                        A.status['Fixer gigs']='Native pet ranking unavailable'; return
                    end
                    -- Keep gig pets in the ranking: busy rank 4 must not make rank 7 eligible.
                    if rankingDirty or not ranked or os.clock()-rankingAt>=30 then
                        ranked={}
                        for _,row in ipairs(power.BuildRanking(d,{IncludeGigPets=true})) do
                            if row.IsDynamic==false then ranked[#ranked+1]=row.UniqueId end
                        end
                        rankingDirty=false; rankingAt=os.clock()
                    end
                    for position=4,6 do
                        local uid=ranked[position]
                        if type(uid)=='string' and type(d.Pets[uid])=='table' and not util.IsPetOnGig(d,uid) and (petBackoff[uid] or 0)<=os.clock() then
                            pet=uid; rank=position; action='Send'; break
                        end
                    end
                    if not action then A.status['Fixer gigs']='Waiting for an available non-scaling pet ranked 4–6'; return end
                end
            end
        end
        if not action then
            local wait=30
            for _,row in ipairs(board) do
                if type(row.EndsAt)=='number' and row.EndsAt>os.time() then wait=math.min(wait,row.EndsAt-os.time()) end
            end
            A.tasks['Fixer gigs'].next=os.clock()+math.max(.2,wait)
            A.status['Fixer gigs']='Waiting for completed gigs or available slots'; return
        end
        local fn=A.Library.Network.Functions:FindFirstChild('FixerGigAction')
        if not fn then A.status['Fixer gigs']='FixerGigAction unavailable'; return end
        gigPending={action=action,index=index,id=gig.Id,pet=pet or gig.PetUid,rank=rank,endsAt=gig.EndsAt,at=os.clock()}
        gigNext=os.clock()+0.3
        A.status['Fixer gigs']=action=='Claim' and ('Claiming gig '..index)
            or ('Deploying pet rank '..rank..' to gig '..index)
        -- Native Claim/Send payloads; one request at a time, below the shared function limit.
        local request=gigPending
        A.invoke('FixerGigAction',table.pack(action,index,pet),function(ok,accepted,reason)
            if gigPending~=request then return end
            if not ok or accepted~=true then
                gigBackoff[gigKey(action,index,gig)]=os.clock()+30
                if action=='Send' then petBackoff[pet]=os.clock()+30 end
                gigPending=nil
                A.status['Fixer gigs']=action..' refused: '..tostring(ok and reason or accepted)
            end
        end)
    end)
    A.on('EquippedUpdated',function()
        rankingDirty=true
        if A.alive then A.tasks['Fixer gigs'].next=0 end
    end)
    A.onPetInventory(function()
        rankingDirty=true
        if A.alive then A.tasks['Fixer gigs'].next=0 end
    end)
    if A.container and type(A.container.OnChange)=='function' then
        for _,field in ipairs({'FixerGigs','Pets','EquippedPets','EquippedPetAccessories','PetAccessories','PetPassives','NamedPets'}) do
            local ok,connection=pcall(A.container.OnChange,A.container,{field},function()
                rankingDirty=true
                if A.alive and (A.settings.fixerAutoClaim or A.settings.fixerAutoDeploy or gigPending) then
                    A.tasks['Fixer gigs'].next=0
                end
            end)
            if ok and connection then A.connections[#A.connections+1]=connection end
        end
    end
    if A.container and type(A.container.OnChange)=='function' then
        local ripperdoc=A.config('RipperdocConfig')
        for _,field in ipairs({'RipperdocLevels',ripperdoc and ripperdoc.CostItemId or 'Eddie'}) do
            local ok,c=pcall(A.container.OnChange,A.container,{field},function()
                if A.alive and A.tasks.Ripperdoc then A.tasks.Ripperdoc.next=0 end
            end)
            if ok and c then A.connections[#A.connections+1]=c end
        end
    end
    A.job('Ripperdoc',0.3,function()
        if not A.settings.ripperdocAuto and not pending then return end
        local cfg=A.config('RipperdocConfig'); local d=A.data()
        if not cfg or cfg.Enabled~=true or not d then return end
        if pending then
            if cfg:GetLevel(d,pending.slot)>pending.level then
                A.status.Ripperdoc='Upgraded '..pending.slot..' to Lv.'..cfg:GetLevel(d,pending.slot)
                if A.settings.webhook then A.notify('Progress',A.status.Ripperdoc) end
                pending=nil
            elseif A.requestInFlight('RipperdocUpgrade') and os.clock()-pending.at>=20 then
                A.status.Ripperdoc='Upgrade still in flight; result unknown, no duplicate will be sent'; return
            elseif os.clock()-pending.at<20 then
                A.status.Ripperdoc='Waiting for '..pending.slot..' upgrade confirmation'; return
            else
                A.status.Ripperdoc='Upgrade unconfirmed; waiting 120s before retrying'
                pending=nil; nextAttempt=os.clock()+120; return
            end
        end
        if not A.settings.ripperdocAuto or os.clock()<nextAttempt then return end
        if A.requestInFlight('RipperdocUpgrade') then A.status.Ripperdoc='Waiting for the previous upgrade request'; return end
        if not A.unlocked(cfg.WorldId) then A.status.Ripperdoc='Unlock Night City first'; return end
        local chosen,level,cost
        for _,slot in ipairs(cfg.SlotOrder) do
            if A.settings.ripperdocSlots[slot] then
                local current=cfg:GetLevel(d,slot)
                local amount=cfg:GetNextCost(slot,current)
                if amount and cfg:IsSlotOpen(d,slot) then chosen=slot; level=current; cost=amount; break end
            end
        end
        if not chosen then A.status.Ripperdoc='Select unfinished slots; later slots require the previous slot at max'; return end
        if A.balance(cfg.CostItemId)<cost then
            A.status.Ripperdoc='Need '..cost..' '..cfg.CostItemId..' for '..chosen; return
        end
        local fn=A.Library.Network.Functions:FindFirstChild('RipperdocUpgrade')
        if not fn then A.status.Ripperdoc='RipperdocUpgrade unavailable'; return end
        -- One normal, serial server request; never spend again before replication confirms.
        pending={slot=chosen,level=level,at=os.clock()}; nextAttempt=os.clock()+0.3
        A.status.Ripperdoc='Upgrading '..chosen
        local request=pending
        A.invoke('RipperdocUpgrade',table.pack(chosen),function(ok,accepted,reason)
            if pending~=request then return end
            if not ok or accepted~=true then
                pending=nil; nextAttempt=os.clock()+30
                A.status.Ripperdoc='Upgrade refused: '..tostring(ok and reason or accepted)
            end
        end)
    end)
end

end)()(A);

-- ===== cyber_plan =====
(function()
return function(A)
    local pending,nextAttempt=nil,0
    function A.cyberPlanRows()
        local cfg=A.config('CyberdeckConfig'); local rows={}
        for _,id in ipairs(cfg and cfg.AttributeOrder or {}) do rows[#rows+1]={key='Attribute:'..id,label='Attribute · '..id} end
        for _,id in ipairs(cfg and cfg.QuickhackOrder or {}) do
            local entry=cfg.Quickhacks[id]
            if entry and entry.Rarity=='Common' then rows[#rows+1]={key='Quickhack:'..id,label='Quickhack · '..entry.Name} end
        end
        return rows
    end
    function A.overclockRows()
        local cfg=A.config('CyberdeckConfig'); local rows={}
        for _,id in ipairs(cfg and cfg.QuickhackOrder or {}) do
            rows[#rows+1]={key=id,label=cfg.Quickhacks[id].Name or id}
        end
        return rows
    end
    local function level(cfg,d,kind,id)
        if kind=='Attribute' then return cfg:GetAttributeLevel(d,id) end
        if kind=='Overclock' then return cfg:GetOverclocks(d,id) end
        return cfg:GetQuickhackLevel(d,id)
    end
    A.job('Cyber plan',0.3,function()
        if not A.settings.cyberPlanAuto and not A.settings.overclockAuto and not pending then return end
        local cfg=A.config('CyberdeckConfig'); local d=A.data()
        if not cfg or cfg.Enabled~=true or not d then A.status['Cyber plan']='Waiting for Cyberdeck data'; return end
        if pending then
            if level(cfg,d,pending.kind,pending.id)>pending.level then
                A.status['Cyber plan']='Confirmed '..pending.kind..' · '..pending.id; pending=nil
            elseif A.requestInFlight('CyberdeckAction') then
                A.status['Cyber plan']='Cyberdeck request in flight; no duplicate'; return
            elseif os.clock()-pending.at<20 then A.status['Cyber plan']='Waiting for Cyberdeck replication'; return
            else pending=nil; nextAttempt=os.clock()+120; A.status['Cyber plan']='Upgrade unconfirmed; retry in 120s'; return end
        end
        if os.clock()<nextAttempt or A.requestInFlight('CyberdeckAction') then return end
        if not A.unlocked(cfg.WorldId) then A.status['Cyber plan']='Unlock Night City first'; return end
        local kind,id,current,cost,action,waiting
        if A.settings.cyberPlanAuto then
            -- Explicit order and numeric targets only. No default spending plan.
            for _,key in ipairs(A.settings.cyberPlanOrder) do
                local k,value=key:match('^([^:]+):(.+)$')
                local info=k=='Attribute' and cfg.Attributes[value] or k=='Quickhack' and cfg.Quickhacks[value]
                if info and (k=='Attribute' or info.Rarity=='Common') then
                    local now=level(cfg,d,k,value)
                    local maximum=k=='Attribute' and cfg.AttributeMaxLevel or info.MaxLevel
                    local target=tonumber(A.settings.cyberPlanTargets[key]) or 0
                    if target>now and target<=maximum then
                        kind=k; id=value; current=now
                        cost=k=='Attribute' and cfg:GetAttributeCost(value,now+1) or cfg:GetQuickhackCost(value,now+1)
                        action=k=='Attribute' and 'Attribute' or (now==0 and 'Unlock' or 'Upgrade')
                        break
                    end
                end
            end
        end
        if kind and cfg:GetPoints(d)<cost then
            waiting='Waiting for '..cost..' skill points · '..id
            kind=nil -- Overclock chips use a separate budget.
        end
        if not kind and A.settings.overclockAuto then
            for _,key in ipairs(cfg.QuickhackOrder) do
                local info=cfg.Quickhacks[key]; local now=cfg:GetOverclocks(d,key)
                local price=cfg:GetOverclockCost(d,key)
                if A.settings.overclockSelection[key]==true and cfg:GetQuickhackLevel(d,key)>=info.MaxLevel
                    and price and A.balance(cfg.Overclock.ItemId)>=price then
                    kind='Overclock'; id=key; current=now; action='Overclock'; break
                end
            end
        end
        if not kind then A.status['Cyber plan']=waiting or 'Waiting for planned upgrades / overclock chips'; return end
        pending={kind=kind,id=id,level=current,at=os.clock()}; nextAttempt=os.clock()+0.3
        local operation=pending
        local sent=A.invoke('CyberdeckAction',table.pack(action,id),function(ok,accepted,reason)
            if pending~=operation then return end
            if not ok or accepted~=true then pending=nil; nextAttempt=os.clock()+30
                A.status['Cyber plan']='Cyberdeck refused: '..tostring(ok and reason or accepted) end
        end)
        if not sent then pending=nil; nextAttempt=os.clock()+10; A.status['Cyber plan']='CyberdeckAction unavailable' end
    end)
end

end)()(A);

-- ===== loadout =====
(function()
return function(A)
    local revision,applied,observedStat=1,0,nil
    local pending,nextAttempt=nil,0
    function A.wakeLoadout() revision=revision+1; if A.tasks.Loadout then A.tasks.Loadout.next=0 end end
    A.onPetInventory(A.wakeLoadout)
    A.on('EquipBestLoadoutResult',function(accepted,reason,stat)
        if not pending or stat~=pending.stat then return end
        if accepted==true then
            applied=pending.revision; A.status.Loadout='Confirmed best '..stat..' loadout'
        else nextAttempt=os.clock()+30; A.status.Loadout='Equip Best refused: '..tostring(reason) end
        pending=nil
    end)
    A.job('Loadout',1,function()
        if not A.settings.loadoutAuto then return end
        if observedStat~=A.settings.loadoutStat then observedStat=A.settings.loadoutStat; revision=revision+1 end
        if pending then
            if os.clock()-pending.at>=15 then pending=nil; nextAttempt=os.clock()+60
                A.status.Loadout='Equip Best unconfirmed; retry in 60s' end
            return
        end
        if applied==revision or os.clock()<nextAttempt then return end
        local d=A.data(); if not d then return end
        for _,queue in pairs(A.passiveQueues or {}) do
            if queue.active and queue.active() then A.status.Loadout='Waiting for passive / curse rolling to settle'; return end
        end
        if A.settings.loadoutStat=='CritChance' or A.settings.loadoutStat=='CritDamage' then
            local cfg=A.config('PromotionRankConfig')
            if not cfg or not cfg:IsCritUnlocked(math.max(0,math.floor(tonumber(d.PromotionRank) or 0))) then
                A.status.Loadout='Unlock Crit in Promotion Ranks first'; return
            end
        end
        if A.requestInFlight('FixerGigAction') then A.status.Loadout='Waiting for pet deployment'; return end
        pending={stat=A.settings.loadoutStat,revision=revision,at=os.clock()}
        if not A.fire('EquipBestLoadout',pending.stat) then pending=nil; nextAttempt=os.clock()+10 end
    end)
    if A.container and type(A.container.OnChange)=='function' then
        for _,field in ipairs({'Accessories','AccessoryCurses','PetAccessories','NamedPets','PetPassives','ActiveSwords','SwordPassives',
            'ActiveTitans','TitanPassives','ShadowCopies','Mounts','PrimordialCopies','ActivePrimordials','RipperdocLevels','FixerGigs',
            'NamedTitans','NamedShadows','NamedPrimordials','MultiplierUpgrades','AchievementPrimordialSlots'}) do
            local ok,c=pcall(A.container.OnChange,A.container,{field},function() if A.alive then A.wakeLoadout() end end)
            if ok and c then A.connections[#A.connections+1]=c end
        end
    end
end

end)()(A);

-- ===== guild_claim =====
(function()
return function(A)
    local pending,nextAttempt=nil,0
    local function missions() local d=A.data(); return d and d.GuildMissions end
    local function rowFor(state,slot)
        return slot=='w' and state.Weekly or (type(state.Daily)=='table' and state.Daily[tonumber(slot:sub(2))])
    end
    A.on('GuildResult',function(action,accepted,reason)
        if action~='missionClaim' or not pending then return end
        -- This reply has no slot ID. Only replication can prove OUR slot was claimed.
        if accepted==false then A.status['Guild quests']='Claim reply: '..tostring(reason)..'; checking mission data' end
    end)
    A.job('Guild quests',1,function()
        if not A.settings.guildAutoClaim and not pending then return end
        local state=missions()
        if type(state)~='table' then A.status['Guild quests']='Waiting for guild mission data'; return end
        if pending then
            local row=rowFor(state,pending.slot)
            if type(row)=='table' and row.K==pending.key and row.C==true then
                A.status['Guild quests']='Claimed '..pending.slot..' · '..pending.key
                pending=nil
            elseif state.Day~=pending.day or state.Week~=pending.week or not row or row.K~=pending.key then
                pending=nil; nextAttempt=os.clock()+1
            elseif os.clock()-pending.at>=15 then
                pending=nil; nextAttempt=os.clock()+30
                A.status['Guild quests']='Claim unconfirmed; retrying in 30s'; return
            else A.status['Guild quests']='Waiting for claim confirmation · '..pending.slot; return end
        end
        if not A.settings.guildAutoClaim or os.clock()<nextAttempt then return end
        local cfg=A.config('GuildMissionConfig'); local util=A.util('GuildMissionUtil')
        local daily=A.config('CloverDailyConfig')
        if not cfg or not util or not daily then A.status['Guild quests']='Mission configuration unavailable'; return end
        local slots={}
        if tonumber(state.Day)==daily:GetDayNumber() then
            for i=1,cfg.DailyCount do slots[#slots+1]='d'..i end
        end
        if tonumber(state.Week)==util.Week() then slots[#slots+1]='w' end
        for _,slot in ipairs(slots) do
            local row=rowFor(state,slot)
            local info=type(row)=='table' and cfg.ByKey[row.K]
            if info and row.C~=true and (tonumber(row.P) or 0)>=util.PersonalGoal(info,row,tonumber(state.Week)) then
                pending={slot=slot,key=row.K,day=state.Day,week=state.Week,at=os.clock()}
                if not A.fire('GuildAction','missionClaim',slot) then
                    pending=nil; nextAttempt=os.clock()+10; A.status['Guild quests']='Guild claim bridge unavailable'
                end
                return
            end
        end
        A.status['Guild quests']='ON · waiting for completed daily / weekly missions'
    end)
    if A.container and type(A.container.OnChange)=='function' then
        local ok,c=pcall(A.container.OnChange,A.container,{'GuildMissions'},function()
            if A.alive and A.tasks['Guild quests'] then A.tasks['Guild quests'].next=0 end
        end)
        if ok and c then A.connections[#A.connections+1]=c end
    end
end

end)()(A);

-- ===== index_sources =====
(function()
return function(A)
    local order={'Accessories','PetAccessories','Titans','Shadows','Swords','Primordials','Mounts'}
    local configs={Accessories='AccessoryConfig',PetAccessories='PetAccessoryConfig',Titans='TitansConfig',
        Shadows='ShadowsConfig',Swords='SwordConfig',Primordials='PrimordialsConfig',Mounts='MountConfig'}
    local rewardCategories={Accessory='Accessories',Accesory='Accessories',PetAccessory='PetAccessories',Mount='Mounts'}
    local accessoryRarities={Common=true,Uncommon=true,Rare=true,Epic=true,Legendary=true,Mythical=true,Secret=true,Divine=true,Limited=true}
    local function finite(n) return type(n)=='number' and n==n and n>=0 and n<math.huge end
    local function percent(n)
        n=tonumber(n)
        if not finite(n) then return 'Chance not published' end
        if n==0 then return '0%' end
        local text=string.format('%.10f',n):gsub('0+$',''):gsub('%.$','')
        if tonumber(text)==0 then text=string.format('%.4g',n) end
        return text..'%'
    end
    local function esc(text)
        return tostring(text or ''):gsub('[%c]',' '):gsub('([\\`*_~|%[%]<>])','\\%1')
    end
    A.indexEscape=esc
    local function buildCatalog(keysByCategory)
        local data=A.data()
        assert(type(data)=='table','Player data is not ready. Try again after the game loads.')
        local collection=A.util('CollectionUtil')
        assert(collection and type(collection.GetKeys)=='function' and type(collection.GetObtained)=='function',
            'The game Index collection API is unavailable. No report was sent.')
        local cache={}
        local warnings={}
        local function config(name,required)
            if cache[name]==nil then
                local ok,value=pcall(A.config,name)
                cache[name]=ok and type(value)=='table' and value or false
                if not cache[name] then warnings[#warnings+1]=name..' unavailable' end
            end
            if required then assert(cache[name],name..' is unavailable. No incomplete Index scan was sent.') end
            return cache[name] or nil
        end
        local function all(name,getter,field)
            local cfg=config(name)
            if not cfg then return {} end
            if type(cfg[getter])=='function' then
                local ok,value=pcall(cfg[getter],cfg)
                if ok and type(value)=='table' then return value end
                warnings[#warnings+1]=name..'.'..getter..' failed'
            end
            return type(cfg[field])=='table' and cfg[field] or {}
        end
        local worlds=all('WorldConfig','GetAllWorlds','Worlds')
        local enemies=all('EnemyConfig','GetAllEnemies','Enemies')
        local spawnConfig=config('SpawnBossConfig')
        local spawnEnemies={}
        for _,boss in pairs(spawnConfig and type(spawnConfig.Bosses)=='table' and spawnConfig.Bosses or {}) do
            if type(boss)=='table' and type(boss.EnemyId)=='string' then spawnEnemies[boss.EnemyId]=boss end
        end
        local raids=all('RaidConfig','GetAllRaids','Raids')
        local defenses=all('DefenseConfig','GetAllDefenses','Defenses')
        local trials=all('TimeTrialConfig','GetAllTrials','Trials')
        local dungeons=all('DungeonConfig','GetAllDungeons','Dungeons')
        local towers=all('TowerConfig','GetAllTowers','Towers')
        local rushes=all('BossRushConfig','GetAllRushes','Rushes')
        local resources=config('ResourcesConfig')
        local function resource(id)
            local item=resources and resources.Items and resources.Items[id]
            return esc(item and item.Name or id or 'currency')
        end
        local function worldId(key,explicit)
            local id=tonumber(explicit)
            if id then return id end
            for wid,w in pairs(worlds) do
                for _,system in pairs(type(w.Systems)=='table' and w.Systems or {}) do
                    if type(system)=='table' and system.Key==key then return tonumber(wid) end
                end
            end
            return tonumber(tostring(key):match('^World(%d+)'))
        end
        local function location(id)
            local w=id and (worlds[id] or worlds[tostring(id)])
            return id and ('World '..tostring(id)..' — '..esc(w and w.Name or 'world name unavailable')) or 'Global'
        end
        local function enemyName(id)
            return esc(type(enemies[id])=='table' and enemies[id].Name or id)
        end
        local function cost(value)
            if type(value)~='table' or value.ItemId==nil then return '' end
            return ' | Cost: '..esc(value.Amount or 1)..' '..resource(value.ItemId)
        end
        local result={at=os.time(),categories={},missing=0,total=0,unknown=0,warnings=warnings}
        local targets={}
        local count=0
        local function yieldScan()
            count=count+1
            if count%40==0 then
                task.wait()
                assert(A.alive,'Index scan cancelled because JoesAAS was unloaded.')
            end
        end
        for _,category in ipairs(order) do
            local cfg=config(configs[category],true)
            local keys=keysByCategory[category]
            local obtained={}
            assert(type(keys)=='table' and type(obtained)=='table','Invalid Index snapshot for '..category)
            local group={key=category,name=category=='PetAccessories' and 'Pet Accessories' or category,total=0,items={}}
            result.categories[#result.categories+1]=group
            targets[category]={}
            local seen={}
            for _,key in ipairs(keys) do
                if type(key)=='string' and not seen[key] then
                    seen[key]=true
                    local system,rarity=key:match('^(.-)::(.+)$')
                    local item
                    if category=='Titans' then item=cfg.Titans and cfg.Titans[system] and cfg.Titans[system].Items[rarity]
                    elseif category=='Swords' then item=cfg.Swords and cfg.Swords[system] and cfg.Swords[system].Items[rarity]
                    elseif category=='Shadows' then item=cfg:GetShadow(key)
                    elseif category=='Primordials' then item=cfg.Demons and cfg.Demons[key]
                    else item=cfg.Items and cfg.Items[key] end
                    assert(type(item)=='table','Index metadata is missing for '..category..' / '..key)
                    local include=(category~='Accessories' or accessoryRarities[item.Rarity]==true)
                        and ((category~='Accessories' and category~='PetAccessories') or item.IndexDisabled~=true)
                    if include then
                        group.total=group.total+1
                        if obtained[key]~=true then
                            local name=item.Name or key
                            if category=='Shadows' and item.Rank then name=name..' · Rank '..item.Rank end
                            local entry={key=key,name=tostring(name),rarity=item.Rarity or rarity or 'Unknown',
                                system=system,variant=rarity,metadata=item,sources={},sourceKeys={}}
                            group.items[#group.items+1]=entry; targets[category][key]=entry
                        end
                    end
                end
                yieldScan()
            end
            result.total=result.total+group.total; result.missing=result.missing+#group.items
        end
        local function add(category,id,wid,text)
            local item=targets[category] and targets[category][id]
            if not item then return end
            local line=location(wid)..'\n'..text
            if not item.sourceKeys[line] then
                item.sourceKeys[line]=true
                item.sources[#item.sources+1]={world=wid or math.huge,text=line}
            end
        end
        local function identify(id,kind)
            if kind~=nil then return rewardCategories[kind] end
            local match
            for _,category in ipairs({'Accessories','PetAccessories','Mounts'}) do
                local cfg=config(configs[category],true)
                if cfg.Items and cfg.Items[id] then
                    if match then return nil end -- A shared ID needs its explicit RewardType.
                    match=category
                end
            end
            return match
        end
        local function drops(values,wid,label,unit,extra)
            for id,drop in pairs(type(values)=='table' and values or {}) do
                if type(drop)=='table' then
                    local itemId=drop.ItemId or drop.Id or id
                    local category=identify(itemId,drop.RewardType or drop.Type)
                    if category then
                        add(category,itemId,wid,label..'\nBase chance: '..percent(drop.Chance)..' '..unit..(extra or ''))
                    end
                end
                yieldScan()
            end
        end
        for id,enemy in pairs(enemies) do
            local spawn=spawnEnemies[id]
            local extra=spawn and ('\nSummon cost: '..tostring(spawn.CostAmount or 1)..' '..resource(spawn.CostItemId)
                ..'\nLoot requires the game\'s participation threshold') or ''
            drops(enemy.Drops,tonumber(spawn and spawn.WorldId or enemy.World),
                (spawn and 'Spawn boss: ' or 'Enemy: ')..enemyName(id),'per kill',extra)
        end
        local function modes(values,kind)
            for key,mode in pairs(values) do
                local wid=worldId(key,mode.WorldId)
                local name=esc(mode.Name or key)
                local label=kind..': '..name
                local extra=cost(mode.Cost)
                drops(mode.Drops,wid,label..' — all enemies','per kill',extra)
                drops(mode.CompletionRewards,wid,label..' — completion reward','per completed run',extra)
                local grouped={}
                for id,enemy in pairs(type(mode.Enemies)=='table' and mode.Enemies or {}) do
                    for itemId,drop in pairs(type(enemy.Drops)=='table' and enemy.Drops or {}) do
                        if type(drop)=='table' then
                            local category=identify(itemId,drop.RewardType or drop.Type)
                            if category then
                                local identity=category..'/'..itemId..'/'..tostring(drop.Chance)
                                local entry=grouped[identity]
                                if not entry then entry={category=category,id=itemId,chance=drop.Chance,enemies={}}; grouped[identity]=entry end
                                entry.enemies[enemyName(id)]=true
                            end
                        end
                        yieldScan()
                    end
                end
                for _,entry in pairs(grouped) do
                    add(entry.category,entry.id,wid,label..'\nEnemies: '..table.concat(A.Core.keys(entry.enemies),', ')
                        ..'\nBase chance: '..percent(entry.chance)..' per kill'..extra)
                end
            end
        end
        modes(raids,'Raid / Gate'); modes(defenses,'Defense'); modes(trials,'Time Trial')
        modes(dungeons,'Dungeon'); modes(towers,'Tower')
        for key,rush in pairs(rushes) do
            for _,mode in pairs(type(rush.Modes)=='table' and rush.Modes or {}) do
                local wid=worldId(key,rush.WorldId)
                local name='Boss Rush: '..esc(mode.Name or rush.Name or key)
                drops(mode.BossDrops,wid,name..' — boss drops','per boss kill',cost(mode.Cost))
                drops(mode.CompletionRewards,wid,name..' — completion reward','per completed run',cost(mode.Cost))
            end
        end
        local function roll(category,cfg,systemKey,system,items)
            local orderForRoll={}
            for _,rarity in ipairs(cfg.Rarity_Order or {}) do
                for _,item in pairs(items) do
                    if item.Rarity==rarity then orderForRoll[#orderForRoll+1]=rarity; break end
                end
                if items[rarity] and not A.Core.contains(orderForRoll,rarity) then orderForRoll[#orderForRoll+1]=rarity end
            end
            local weights=cfg.Rarity_Weights or {}; local sum=0
            for _,rarity in ipairs(orderForRoll) do sum=sum+math.max(0,tonumber(weights[rarity]) or 0) end
            for id,item in pairs(items) do
                local rarity=item.Rarity or id
                local key=category=='Primordials' and id or systemKey..'::'..id
                local probability=sum>0 and math.max(0,tonumber(weights[rarity]) or 0)/sum*100
                    or (#orderForRoll>0 and 100/#orderForRoll or nil)
                add(category,key,worldId(systemKey,system.WorldId),
                    'Roll: '..esc(system.Name or category)..'\nBase chance: '..percent(probability)..' per roll'..cost(system.ItemCost))
                yieldScan()
            end
        end
        local titans=config('TitansConfig',true)
        for key,system in pairs(titans.Titans or {}) do roll('Titans',titans,key,system,system.Items or {}) end
        local swords=config('SwordConfig',true)
        for key,system in pairs(swords.Swords or {}) do roll('Swords',swords,key,system,system.Items or {}) end
        local primordials=config('PrimordialsConfig',true)
        roll('Primordials',primordials,primordials.SystemKey or 'Primordials',primordials,primordials.Demons or {})
        local shadows=config('ShadowsConfig',true)
        for key,mode in pairs(raids) do
            if type(mode.ShadowArise)=='table' then
                for _,rank in ipairs(mode.GateRanks or {{Rank='Default'}}) do
                    local bosses=rank.Bosses or mode.Bosses or {}; local bossTotal=0
                    for _,boss in ipairs(bosses) do bossTotal=bossTotal+math.max(0,tonumber(boss.Weight) or 0) end
                    local weights=rank.AriseVariantWeights or {}; local total=0
                    for _,variant in ipairs(shadows.AriseVariants or {}) do
                        total=total+math.max(0,tonumber(weights[variant.Rarity] or variant.Weight) or 0)
                    end
                    for _,boss in ipairs(bosses) do
                        for _,variant in ipairs(shadows.AriseVariants or {}) do
                            local variantChance=total>0 and math.max(0,tonumber(weights[variant.Rarity] or variant.Weight) or 0)/total*100 or nil
                            add('Shadows',shadows:GetVariantShadowKey(boss.EnemyId,variant.Rarity),worldId(key,mode.WorldId),
                                'Gate: '..esc(mode.Name or key)..' · Gate rank '..esc(rank.Rank)..'\nBoss: '..enemyName(boss.EnemyId)
                                ..' | Spawn share: '..percent(bossTotal>0 and math.max(0,tonumber(boss.Weight) or 0)/bossTotal*100 or nil)
                                ..'\nARISE success: '..percent(mode.ShadowArise.ChancePercent)..' per attempt; '
                                ..esc(mode.ShadowArise.Chances or '?')..' attempts\nVariant chance after successful ARISE: '..percent(variantChance))
                        end
                    end
                end
            end
        end
        local bundles=config('DevProductConfig')
        for key,bundle in pairs(bundles or {}) do
            if type(bundle)=='table' then
                for _,spec in ipairs({{'Accessories','AccessoryId'},{'PetAccessories','PetAccessoryId'},{'Mounts','MountId'}}) do
                    for _,reward in pairs(type(bundle[spec[1]])=='table' and bundle[spec[1]] or {}) do
                        add(spec[1],reward[spec[2]],nil,'Shop: '..esc(bundle.Name or key)
                            ..'\nGuaranteed on purchase (no drop roll) | Price: '..esc(bundle.Price or '?')..' Robux'
                            ..(bundle.TicketPrice and (' / '..esc(bundle.TicketPrice)..' paid tickets') or '')
                            ..(bundle.GlobalMaxPurchases and (' | Limited stock: '..esc(bundle.GlobalMaxPurchases)) or ''))
                    end
                end
            end
        end
        local passes=config('BattlepassConfig')
        for key,pass in pairs(passes and passes.Passes or {}) do
            for _,track in ipairs({'FreeRewards','PremiumRewards'}) do
                for level,reward in ipairs(pass[track] or {}) do
                    local category=rewardCategories[reward.Type]
                    if category then add(category,reward.Id,worldId(key,pass.WorldId),
                        'Battlepass: '..esc(pass.Name or key)..'\n'..(track=='FreeRewards' and 'Free' or 'Premium')
                        ..' track · Level '..level..'\nGuaranteed when eligible reward is claimed (no drop roll)') end
                end
            end
        end
        local merchant=config('MerchantConfig')
        for key,shop in pairs(merchant and merchant.Shops or {}) do
            for _,product in ipairs(shop.Products or {}) do
                local category=identify(product.ItemId,product.RewardType)
                if category then add(category,product.ItemId,worldId(key,shop.WorldId),
                    'Shop: '..esc(shop.Name or key)..' (when available)\nGuaranteed on purchase (no drop roll) | Cost: '
                    ..esc(product.Price or '?')..' '..resource(shop.Currency and shop.Currency.ItemId)) end
            end
        end
        for _,name in ipairs({'CorvoConfig','BallConfig'}) do
            local cfg=config(name)
            if cfg then
                local label='Event: '..esc(cfg.Prompt and cfg.Prompt.ObjectText or name)..' — find it and claim the prompt'
                for _,reward in ipairs(cfg.Rewards or {}) do
                    local category=identify(reward.ItemId,reward.RewardType)
                    if category then
                        local pity=cfg.AccessoryPity
                        add(category,reward.ItemId,tonumber(cfg.WorldId),label..'\nBase chance: '..percent(reward.Chance)..' per claim'
                            ..(pity and pity.Enabled and pity.ItemId==reward.ItemId and (' | Configured pity: '..esc(pity.Threshold)..' claims') or ''))
                    end
                end
            end
        end
        local medal=config('MedalConfig')
        for _,reward in ipairs(medal and medal.Rewards or {}) do
            local category=rewardCategories[reward.Type]
            if category then add(category,reward.PetAccessoryId or reward.ItemId or reward.Id,nil,
                'Medal rewards: link your Medal account, post an Anime Astral clip and play for '
                ..esc((tonumber(medal.PlaytimeRequired) or 0)/60)..' minutes\nGuaranteed when eligible reward is claimed (no drop roll)'
                ..(medal.Enabled==false and ' | Disabled in current config' or '')) end
        end
        for _,group in ipairs(result.categories) do
            local names={}
            for _,item in ipairs(group.items) do names[item.name]=(names[item.name] or 0)+1 end
            for _,item in ipairs(group.items) do
                if names[item.name]>1 and group.key=='Mounts' then
                    local stats=A.Core.keys(item.metadata.Multiplier or {})
                    item.name=item.name..' · '..(#stats>0 and table.concat(stats,' / ') or item.key)
                end
                if #item.sources==0 then
                    item.unknown=true
                    result.unknown=result.unknown+1
                    item.sources[1]={world=math.huge,text='Source and chance not published in the current client configs.\nThis entry is still in the game Index; availability cannot be verified.'}
                end
                table.sort(item.sources,function(a,b) if a.world==b.world then return a.text<b.text end return a.world<b.world end)
                item.world=item.sources[1].world
                item.metadata=nil; item.sourceKeys=nil
            end
            table.sort(group.items,function(a,b)
                if a.world~=b.world then return a.world<b.world end
                if a.name~=b.name then return a.name<b.name end
                if a.rarity~=b.rarity then return a.rarity<b.rarity end
                return a.key<b.key
            end)
        end
        return result
    end
    local catalog,cacheSignature,cachedAt
    function A.indexSnapshot()
        local data=A.data()
        assert(type(data)=='table','Player data is not ready. Try again after the game loads.')
        local collection=A.util('CollectionUtil')
        assert(collection and type(collection.GetKeys)=='function' and type(collection.GetObtained)=='function',
            'The game Index collection API is unavailable. No report was sent.')
        local keys,owned,signature={},{},{tostring(A.catalogRevision)}
        -- Capture all ownership before the first yield; a report represents one instant.
        for _,category in ipairs(order) do
            keys[category]=A.Core.copy(collection.GetKeys(category))
            owned[category]=A.Core.copy(collection.GetObtained(data,category))
            assert(type(keys[category])=='table' and type(owned[category])=='table','Invalid Index snapshot for '..category)
            signature[#signature+1]=category..':'..table.concat(keys[category],',')..':'..tostring(A.config(configs[category]))
        end
        signature=table.concat(signature,'|')
        if not catalog or signature~=cacheSignature or os.clock()-cachedAt>=30 then
            catalog=buildCatalog(keys); cacheSignature=signature; cachedAt=os.clock()
        end
        local result={at=os.time(),categories={},missing=0,total=catalog.total,unknown=0,warnings=A.Core.copy(catalog.warnings)}
        for _,group in ipairs(catalog.categories) do
            local selected={key=group.key,name=group.name,total=group.total,items={}}
            for _,item in ipairs(group.items) do
                if owned[group.key][item.key]~=true then
                    selected.items[#selected.items+1]=A.Core.copy(item)
                    if item.unknown then result.unknown=result.unknown+1 end
                end
            end
            result.categories[#result.categories+1]=selected; result.missing=result.missing+#selected.items
        end
        return result
    end
end

end)()(A);

-- ===== index_report =====
(function()
return function(A)
    -- This destination belongs only to the manual Index report button.
    local destination='https://discord.com/api/webhooks/1556049988575035502/Mh4wKE7W2mnvtsgRt6UfPYaHRiwzFLhI-CkZ2YUYDk4gg1RjjiXEfye8mghrmVKxlrXC'
    local env=(type(getgenv)=='function' and getgenv()) or _G
    local state=env.JoesAASIndexDelivery
    local path=A.folder..'/index-outbox.json'
    if type(state)~='table' or state.version~=1 or (state.scope and state.scope~=A.folder) then
        local saved=A.safeLoad(path..'.tmp') or A.safeLoad(path) or A.safeLoad(path..'.bak')
        state={version=1,pages={},cursor=1,next=0,attempt=0,busy=false,building=false}
        if type(saved)=='table' and saved.version==1 and type(saved.pages)=='table'
            and type(saved.cursor)=='number' and saved.cursor>=1 and saved.cursor<=#saved.pages+1 then
            state.pages=saved.pages; state.cursor=math.floor(saved.cursor); state.blocked=saved.blocked==true
            state.status=#state.pages>0 and 'Recovered queued Index report; delivery will resume' or 'Ready · press the button to send your missing Index'
        end
        env.JoesAASIndexDelivery=state
    end
    state.scope=A.folder; A.indexDeliveryState=state
    local function persistReport()
        if type(writefile)~='function' then return end
        local ok,err=pcall(function()
            local snapshot={version=1,pages=state.pages,cursor=state.cursor,blocked=state.blocked==true}
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            writefile(path..'.tmp',encoded)
            assert(A.Core.equal(A.safeLoad(path..'.tmp'),snapshot),'Index staged read-back failed')
            local previous=A.safeLoad(path)
            if previous then writefile(path..'.bak',A.S.HTTP:JSONEncode(previous)) end
            writefile(path,encoded)
            assert(A.Core.equal(A.safeLoad(path),snapshot),'Index read-back failed')
            local cleared=type(delfile)=='function' and pcall(delfile,path..'.tmp')
            if not cleared or A.safeLoad(path..'.tmp') then pcall(writefile,path..'.tmp','') end
        end)
        if not ok then A.log('Index storage',err) end
    end
    local colors={Accessories=16763955,PetAccessories=12418047,Titans=16742972,Shadows=8282367,
        Swords=5031394,Primordials=15755396,Mounts=6804333}
    local function chunks(text,limit)
        local out={}
        while #text>limit do
            local cut=limit
            -- Byte budgets are conservative for Discord's character limits.
            -- Never cut a UTF-8 code point or discard any source text.
            while cut>0 and (text:byte(cut+1) or 0)>=128 and (text:byte(cut+1) or 0)<192 do cut=cut-1 end
            local newline=text:sub(1,cut):match('.*()\n')
            if newline and newline>cut/2 then cut=newline end
            out[#out+1]=text:sub(1,cut)
            text=text:sub(cut+1)
        end
        if text~='' then out[#out+1]=text end
        return out
    end
    local function label(value,limit)
        return chunks(A.indexEscape(value),limit)[1] or 'Unnamed item'
    end
    function A.indexPages(snapshot)
        assert(type(snapshot)=='table' and type(snapshot.categories)=='table','Invalid Index report snapshot')
        local esc=A.indexEscape
        local summary={}
        for _,group in ipairs(snapshot.categories) do
            summary[#summary+1]='**'..esc(group.name)..'** — '..#group.items..' missing / '..group.total..' total'
        end
        local description='**'..esc(A.player.Name)..'** · '..snapshot.missing..' missing entries\n\n'
            ..table.concat(summary,'\n')..'\n\n'
            ..'Chances are **base, unboosted** percentages. Luck, Drop bonuses and pity can change actual odds. '
            ..'Shadow variant chances apply **after a successful ARISE**, separately from boss spawns.\n'
            ..'Obtained entries follow the game Index inventory and collection history. **Pets are excluded.**'
        if snapshot.unknown>0 then description=description..'\n**'..snapshot.unknown..' entries have unpublished source/chance details**; they are listed explicitly.' end
        if snapshot.missing==0 then description=description..'\n\nAll seven requested collections are complete.' end
        local pages={{title='JoesAAS · Missing Index',description=description,color=5031394}}
        for _,group in ipairs(snapshot.categories) do
            local page,size,categoryPages=nil,0,{}
            local function newPage()
                page={title='JoesAAS · '..group.name,description=#group.items..' missing entries · ordered by world',
                    color=colors[group.key] or 5031394,fields={}}
                size=#page.title+#page.description+180
                pages[#pages+1]=page; categoryPages[#categoryPages+1]=page
            end
            for _,item in ipairs(group.items) do
                local sources={}
                for i,source in ipairs(item.sources) do sources[#sources+1]='**Source '..i..'**\n'..source.text end
                local text='**'..esc(item.rarity)..'**\n'..table.concat(sources,'\n\n')
                local name=esc(item.name)
                if #name>220 then text='**Full name:** '..name..'\n'..text; name=label(item.name,200) end
                for part,value in ipairs(chunks(text,900)) do
                    local fieldName=name..(part>1 and (' · continued '..part) or '')
                    if not page or #page.fields>=8 or size+#fieldName+#value>5400 then newPage() end
                    page.fields[#page.fields+1]={name=fieldName,value=value,inline=false}
                    size=size+#fieldName+#value
                end
            end
            for i,categoryPage in ipairs(categoryPages) do
                categoryPage.description=categoryPage.description..' · category page '..i..'/'..#categoryPages
            end
        end
        if #(snapshot.warnings or {})>0 then
            local warnings='Some source configs could not be read. Missing-entry counts still use the complete game Index.\n\n'
                ..table.concat(snapshot.warnings,'\n')
            for _,part in ipairs(chunks(warnings,3500)) do
                pages[#pages+1]={title='JoesAAS · Source lookup warnings',description=part,color=16763955}
            end
        end
        local reportID=os.date('!%Y%m%d-%H%M%S',snapshot.at)..'-'..tostring(math.floor(os.clock()*1000)%100000)
        for i,page in ipairs(pages) do
            page.footer={text='Report '..reportID..' · Part '..i..'/'..#pages..' · '..os.date('!%Y-%m-%d %H:%M UTC',snapshot.at)}
        end
        return pages
    end
    local function progress()
        return math.max(0,state.cursor-1)..'/'..#state.pages..' pages'
    end
    local function setStatus(message)
        state.status=message; A.status.Index=message
    end
    function A.sendIndexReport()
        if state.building then setStatus('Scanning your Index; please wait'); return false end
        if state.cursor<=#state.pages then
            if state.blocked then
                state.blocked=false; state.attempt=0; state.next=0; persistReport()
                setStatus('Resuming report · '..progress())
                return true
            end
            A.status.Index=state.status or ('Sending report · '..progress()); return false
        end
        if type(A.httpRequest)~='function' then setStatus('Executor HTTP request API unavailable; no report was sent'); return false end
        state.building=true; setStatus('Scanning your Index and looking up sources…')
        task.spawn(function()
            local ok,pages=pcall(function() return A.indexPages(A.indexSnapshot()) end)
            state.building=false
            if not A.alive then return end
            if not ok then
                setStatus('Index scan failed: '..tostring(pages):gsub('https://[^%s]+/api/webhooks/[^%s]+','[webhook redacted]'))
                A.log('Index',A.status.Index); return
            end
            state.pages=pages; state.cursor=1; state.next=0; state.attempt=0; state.blocked=false; persistReport()
            setStatus('Sending report · '..progress())
        end)
        return true
    end
    A.status.Index=state.status or 'Ready · press the button to send your missing Index'
    A.job('Index report delivery',0.2,function()
        if state.building or state.busy then return end
        if state.status then A.status.Index=state.status end
        if state.blocked or state.cursor>#state.pages or os.clock()<state.next then return end
        if not A.httpTurn('Index') then return end
        local page=state.pages[state.cursor]
        state.busy=true
        local ok,response=pcall(function()
            local body=A.S.HTTP:JSONEncode({username='JoesAAS Index',embeds={page}})
            -- Roblox encodes an empty table as {}; Discord requires an array.
            body=body:sub(1,-2)..',"allowed_mentions":{"parse":[]}}'
            local sent,value,unresolved=A.http({Url=destination..'?wait=true',Method='POST',
                Headers={['Content-Type']='application/json'},Body=body},true)
            return {sent=sent,value=value,unresolved=unresolved}
        end)
        state.busy=false
        if ok and response.unresolved then state.status='Waiting for the original HTTP result · '..progress(); A.status.Index=state.status; return end
        local result=ok and response.sent and type(response.value)=='table' and response.value or nil
        local status=result and tonumber(result.StatusCode or result.Status) or 0
        local parsed
        if result then
            local decoded,value=pcall(A.S.HTTP.JSONDecode,A.S.HTTP,result.Body or '')
            if decoded and type(value)=='table' then parsed=value end
        end
        state.attempt=state.attempt+1
        local headers=result and type(result.Headers)=='table' and result.Headers or {}
        local action,delay=A.Core.webhookRetry(status or 0,headers,parsed,state.attempt)
        if action=='done' then
            state.cursor=state.cursor+1; state.attempt=0; state.next=os.clock()+2
            if env.AnimeSuiteHTTP then env.AnimeSuiteHTTP.lastLane='Index' end
            state.status=state.cursor>#state.pages and ('Report sent · '..progress()) or ('Sending report · '..progress())
            if state.cursor>#state.pages then state.pages={}; state.cursor=1 end
        elseif action=='stop' or (state.attempt>=8 and status~=429) then
            state.blocked=true
            state.status='Report paused · '..progress()..' · HTTP '..tostring(status)
                ..' · press the button to retry the unsent pages'
        else
            state.next=os.clock()+delay
            state.status='Sending report · '..progress()..' · retry in '..math.ceil(delay)..'s (HTTP '..tostring(status)..')'
        end
        A.status.Index=state.status; persistReport()
        -- Do not log HTTP responses: an executor or Discord error can echo the secret URL.
    end,true)
end

end)()(A);

-- ===== ui =====
(function()
return function(A)
    local C=A.Core
    assert(type(loadstring)=='function','This executor session has no loadstring API; Fluent cannot load.')
    local pinned='https://github.com/dawid-scripts/Fluent/releases/download/1.1.0/main.lua'
    local cachePath='JoesAAS/Fluent-1.1.0.lua'
    local function initialize(source)
        assert(type(source)=='string','Fluent source unavailable')
        local loader,err=loadstring(source); assert(loader,err)
        local library=loader()
        local valid=type(library)=='table' and type(library.CreateWindow)=='function'
            and type(library.Destroy)=='function' and library.GUI~=nil
            and library.Version=='1.1.0'
        if not valid then
            if type(library)=='table' and type(library.Destroy)=='function' then pcall(library.Destroy,library) end
            error('Fluent 1.1.0 API validation failed')
        end
        return library
    end
    local ready,F=pcall(initialize,A.fluentSource)
    A.fluentSource=nil -- Release the bundled source after compilation.
    if not ready and type(readfile)=='function' then
        local cached,value=pcall(readfile,cachePath)
        if cached then ready,F=pcall(initialize,value) end
    end
    if not ready then
        local downloaded,source=pcall(function() return game:HttpGet(pinned) end)
        if downloaded then ready,F=pcall(initialize,source) end
        if ready and type(writefile)=='function' then
            pcall(function() writefile(cachePath,source) end)
        end
    end
    assert(ready,'Fluent 1.1.0 download and cached fallback unavailable')
    A.fluent=F; A.gui=F.GUI
    local touch=A.S.UIS.TouchEnabled==true
    local camera=workspace.CurrentCamera
    local function dimensions()
        local viewport=camera and camera.ViewportSize or Vector2.new(720,600)
        return math.min(680,math.max(120,viewport.X-24)),math.min(540,math.max(120,viewport.Y-(touch and 76 or 48)))
    end
    local width,height=dimensions()
    local window=F:CreateWindow({Title='JoesAAS',SubTitle=A.version,TabWidth=touch and 92 or 150,
        Size=UDim2.fromOffset(width,height),Acrylic=false,Theme='Dark',MinimizeKey=Enum.KeyCode.RightShift})
    A.gui.DisplayOrder=100001
    local popupLimits={}
    local function fitScreen()
        local w,h=dimensions()
        if window.Root then
            local viewport=camera and camera.ViewportSize or Vector2.new(720,600)
            window.Size=UDim2.fromOffset(w,h)
            window.Position=UDim2.fromOffset((viewport.X-w)/2,(viewport.Y-h)/2)
            window.Root.Size=window.Size; window.Root.Position=window.Position
        end
        if A.clampTouchButton then A.clampTouchButton() end
        if touch then
            for _,limit in ipairs(popupLimits) do limit.MaxSize=Vector2.new(w,h) end
        end
    end
    local function bindCamera()
        if A.viewportConnection then A.viewportConnection:Disconnect() end
        camera=workspace.CurrentCamera
        if camera then A.viewportConnection=A.connect(camera:GetPropertyChangedSignal('ViewportSize'),fitScreen) end
        fitScreen()
    end
    A.connect(workspace:GetPropertyChangedSignal('CurrentCamera'),bindCamera)
    bindCamera()
    if touch then
        function window:Minimize()
            self.Minimized=not self.Minimized; self.Root.Visible=not self.Minimized
        end
        A.touchGui=Instance.new('ScreenGui'); A.touchGui.Name='JoesAASTouchControls'
        A.touchGui.ResetOnSpawn=false; A.touchGui.DisplayOrder=100002
        A.touchGui.Parent=A.player:WaitForChild('PlayerGui')
        A.touchControls={}
        local function touchButton(name,offset,callback)
            local b=Instance.new('TextButton'); b.Name=name; b.Text=name
            b.Size=UDim2.fromOffset(78,44); b.Position=UDim2.new(1,offset,0,6)
            b.TextSize=15; b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=Color3.fromRGB(28,31,38)
            b.Parent=A.touchGui; local corner=Instance.new('UICorner'); corner.CornerRadius=UDim.new(0,8); corner.Parent=b
            A.connect(b.Activated,callback); A.touchControls[name]=b; return b
        end
        local dragging,suppressTap=nil,false
        local suite=touchButton('JoesAAS',-122,function()
            if not suppressTap then window:Minimize() end
        end)
        suite.Size=UDim2.fromOffset(110,46); suite.Text='JoesAAS'; suite.TextSize=15
        suite.Font=Enum.Font.GothamBold; suite.AutoButtonColor=false
        suite.BackgroundColor3=Color3.fromRGB(18,24,34); suite.TextColor3=Color3.fromRGB(230,245,255)
        local shape=suite:FindFirstChildOfClass('UICorner'); if shape then shape.CornerRadius=UDim.new(0,16) end
        local outline=Instance.new('UIStroke'); outline.Color=Color3.fromRGB(77,197,232)
        outline.Thickness=1.3; outline.Transparency=0.2; outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; outline.Parent=suite
        local accent=Instance.new('Frame'); accent.Size=UDim2.fromOffset(5,18)
        accent.Position=UDim2.fromOffset(9,14); accent.BorderSizePixel=0
        accent.BackgroundColor3=Color3.fromRGB(77,197,232); accent.Parent=suite
        local accentRound=Instance.new('UICorner'); accentRound.CornerRadius=UDim.new(1,0); accentRound.Parent=accent
        for x=0,1 do for y=0,2 do
            local dot=Instance.new('Frame'); dot.Size=UDim2.fromOffset(2,2)
            dot.Position=UDim2.fromOffset(96+x*4,17+y*5); dot.BorderSizePixel=0
            dot.BackgroundColor3=Color3.fromRGB(122,147,166); dot.Parent=suite
        end end
        local area=Instance.new('Frame'); area.Name='TouchBounds'; area.Size=UDim2.fromScale(1,1)
        area.BackgroundTransparency=1; area.Parent=A.touchGui; suite.Parent=area
        local function bounds()
            local size=area.AbsoluteSize
            if size and size.X>0 and size.Y>0 then return size.X,size.Y end
            local v=camera and camera.ViewportSize or Vector2.new(720,600)
            return v.X,math.max(46,v.Y-60)
        end
        local function place(x,y)
            local w,h=bounds()
            suite.Position=UDim2.fromOffset(math.clamp(x,4,math.max(4,w-114)),math.clamp(y,4,math.max(4,h-50)))
        end
        function A.clampTouchButton()
            local w,h=bounds(); local pos=suite.Position
            place(pos.X.Scale*w+pos.X.Offset,pos.Y.Scale*h+pos.Y.Offset)
        end
        A.connect(area:GetPropertyChangedSignal('AbsoluteSize'),A.clampTouchButton)
        A.clampTouchButton()
        A.connect(suite.InputBegan,function(input)
            if dragging then return end
            if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
                suppressTap=false
                dragging={input=input,start=input.Position,x=suite.Position.X.Offset,y=suite.Position.Y.Offset}
            end
        end)
        A.connect(A.S.UIS.InputChanged,function(input)
            if not dragging then return end
            if input==dragging.input or (dragging.input.UserInputType==Enum.UserInputType.MouseButton1
                and input.UserInputType==Enum.UserInputType.MouseMovement) then
                local delta=input.Position-dragging.start
                if delta.Magnitude>=6 then suppressTap=true end
                if suppressTap then place(dragging.x+delta.X,dragging.y+delta.Y) end
            end
        end)
        A.connect(A.S.UIS.InputEnded,function(input)
            if dragging and (input==dragging.input or (dragging.input.UserInputType==Enum.UserInputType.MouseButton1
                and input.UserInputType==Enum.UserInputType.MouseButton1)) then dragging=nil end
        end)
        local restore=touchButton('RESTORE',-84,function() if A.render then A.render(false) end end)
        restore.Size=UDim2.fromOffset(130,44); restore.Position=UDim2.new(.5,-65,1,-58)
        restore.Visible=false
    end
    local tabs={}
    for _,name in ipairs({'Farm','Modes','Pets','Passives','Cyber','Guild','Index','Webhook','Settings'}) do
        tabs[name]=window:AddTab({Title=name,Icon=''})
    end
    local sync=true; local bindings={}; local statuses={}
    local function guard(fn,saveDelay)
        return function(...)
            if sync or not A.alive then return end
            local ok,why=pcall(fn,...)
            if ok and A.alive then A.settingsChanged(saveDelay) end
            if not ok then A.log('UI',why); F:Notify({Title='JoesAAS',Content=tostring(why),Duration=6}) end
        end
    end
    local function button(tab,title,fn) return tabs[tab]:AddButton({Title=title,Callback=guard(fn)}) end
    local function note(tab,title,content)
        local paragraph=tabs[tab]:AddParagraph({Title=title,Content=content})
        local last=content; local set=paragraph.SetDesc
        paragraph.SetDesc=function(self,value)
            if value~=last then last=value; set(self,value) end
        end
        return paragraph
    end
    local function status(tab,key)
        local p=note(tab,key,'Ready')
        statuses[#statuses+1]=function() p:SetDesc(tostring(A.status[key] or 'Ready')) end
    end
    local function toggle(tab,title,key,changed)
        local option=tabs[tab]:AddToggle(key,{Title=title,Default=A.settings[key]})
        option:OnChanged(guard(function(value)
            A.settings[key]=value==true
            if changed then changed(A.settings[key]) end
        end))
        bindings[#bindings+1]=function()
            if option.Value~=A.settings[key] then option:SetValue(A.settings[key]) end
        end
        return option
    end
    local function input(tab,title,key,numeric,minimum,maximum)
        local option=tabs[tab]:AddInput(key,{Title=title,Default=tostring(A.settings[key]),Numeric=numeric==true,Finished=false})
        option:OnChanged(guard(function(value)
            if numeric then
                local n=tonumber(value)
                if not n or n~=n or n<0 or n==math.huge then return end
                if minimum then n=math.clamp(n,minimum,maximum) end
                A.settings[key]=n
            else A.settings[key]=tostring(value):match('^%s*(.-)%s*$') end
        end,0.4))
        bindings[#bindings+1]=function()
            local value=tostring(A.settings[key]); if option.Value~=value then option:SetValue(value) end
        end
    end
    local function choices(values)
        return function() local out={}; for _,v in ipairs(values) do out[#out+1]={key=v,label=v} end; return out end
    end
    local function dropdown(tab,title,id,provider,get,set,multi)
        local option=tabs[tab]:AddDropdown(id,{Title=title,Values={},Multi=multi==true,Default=multi and {} or nil,AllowNull=true})
        if multi then
            local nativeSet=option.SetValue
            option.SetValue=function(self,value) return nativeSet(self,C.trueKeys(value)) end
        end
        if touch and type(F.OpenFrames)=='table' then
            local popup=F.OpenFrames[#F.OpenFrames]
            if popup then
                local limit=Instance.new('UISizeConstraint'); local w,h=dimensions()
                limit.MaxSize=Vector2.new(w,h); limit.Parent=popup; popupLimits[#popupLimits+1]=limit
            end
        end
        local rows,byLabel={},{}
        local function refresh()
            rows=provider(); byLabel={}; local labels={}; local selected=multi and {} or nil
            for i,row in ipairs(rows) do
                if touch and #row.label>30 then row.label=C.clipBytes(row.label,26)..'… '..i end
                labels[#labels+1]=row.label; byLabel[row.label]=row.key
                if get(row.key) then
                    if multi then selected[row.label]=true else selected=row.label end
                end
            end
            local changed=#option.Values~=#labels
            if not changed then
                for i,value in ipairs(labels) do if option.Values[i]~=value then changed=true; break end end
            end
            local valueChanged=option.Value~=selected
            if multi then
                valueChanged=false
                for key in pairs(selected) do if not option.Value[key] then valueChanged=true; break end end
                if not valueChanged then
                    for key,value in pairs(option.Value) do
                        if value and not selected[key] then valueChanged=true; break end
                    end
                end
            end
            -- Fluent recreates dropdown rows on both setters. Never call them for unchanged data.
            if changed then option:SetValues(labels) end
            if valueChanged then option:SetValue(selected) end
        end
        bindings[#bindings+1]=refresh
        option:OnChanged(guard(function(value)
            if multi then
                if #rows==0 then return end
                local selected={}
                for _,row in ipairs(rows) do selected[row.key]=type(value)=='table' and value[row.label]==true end
                set(selected)
            elseif value and byLabel[value] then set(byLabel[value]) end
        end))
        return option
    end
    local function choose(tab,title,key,provider)
        return dropdown(tab,title,key,provider,function(id) return tostring(A.settings[key])==id end,
            function(id) A.settings[key]=id; if key=='world' then A.watchTarget(nil) end; A.refreshUI() end)
    end
    local function multi(tab,title,key,provider)
        dropdown(tab,title,key,provider,function(id) return A.settings[key][id]~=false end,function(selected)
            for id,value in pairs(selected) do A.settings[key][id]=value end
        end,true)
        button(tab,'Include all '..title:lower()..' / future entries',function() A.settings[key]={}; A.refreshUI() end)
    end
    choose('Farm','World','world',function()
        local out={}
        for id,w in pairs(A.catalog.worlds) do
            out[#out+1]={key=tostring(id),label=tostring(id)..' - '..w.Name..(A.unlocked(id) and '' or ' [locked]')}
        end
        table.sort(out,function(a,b) return tonumber(a.key)<tonumber(b.key) end); return out
    end)
    dropdown('Farm','Mobs in selected world','worldMobs',function()
        local out={}
        for key,e in pairs(A.catalog.enemies) do
            if tostring(e.World)==A.settings.world then out[#out+1]={key=key,label=tostring(e.ModelName or key)} end
        end
        table.sort(out,function(a,b) return a.label<b.label end); return out
    end,function(id)
        return A.mobAllowed(A.settings.world,id)
    end,function(selected)
        A.setMobSelection(A.settings.world,selected,false)
    end,true)
    button('Farm','Select all mobs / include future mobs in this world',function()
        A.setMobSelection(A.settings.world,{},true); A.refreshUI()
    end)
    button('Farm','Clear mob selection in this world',function() A.setMobSelection(A.settings.world,{},false); A.refreshUI() end)
    choose('Farm','Target order','target',choices({'Nearest','Highest HP','Lowest HP'}))
    choose('Farm','Movement','moveStyle',choices({'Walk','Teleport'}))
    toggle('Farm','Auto farm selected mobs','farm',function(enabled)
        if not enabled then A.stopFarmMovement(); A.watchTarget(nil) end
    end)
    note('Farm','World handling','Joins through the normal world system before combat. Keeps one target until death or removal, then immediately picks across all selected mobs. Selections are saved separately per world.')
    status('Farm','Farm'); status('Farm','Discovery')
    toggle('Farm','Auto teleport to Trial / Dungeon mobs','trialFollow',function()
        if not A.settings.trialFollow then A.stopTrialMovement(); A.stopDungeonMovement() end
    end)
    note('Farm','Trial / Dungeon movement','Teleports to mobs in your current Trial or Dungeon and keeps small anti-stuck steps running between rooms. Stops on exit, death, run end or toggle off.')
    status('Farm','Trial follow'); status('Farm','Dungeon follow')
    dropdown('Farm','Trials to auto join','trialJoinSelection',function()
        return A.activityRows('TimeTrial')
    end,function(key) return A.settings.trialJoinSelection[key]==true end,
    function(selected) A.settings.trialJoinSelection=selected end,true)
    toggle('Farm','Auto join selected trials when open','trialAutoJoin',function() A.tryTrialJoin() end)
    status('Farm','Trial join')
    note('Farm','Trial priority','Insane > Hard > Medium > Easy among selected trials currently open. An active trial finishes first unless your stuck timeout is reached.')
    status('Modes','Activities'); status('Modes','Native join conflicts')
    status('Modes','Activity error'); status('Modes','Join diagnostics')
    button('Modes','Save join diagnostics now',function() A.flushJoinDiagnostics(true) end)
    note('Modes','Raid / Defense','Raid starts YOUR OWN run only; never joins other raids. Defense creates your own run. Normal entry costs apply; errors appear above.')
    local priorityNote=note('Modes','Activity priority',A.priorityText())
    statuses[#statuses+1]=function() priorityNote:SetDesc(A.priorityText()) end
    local editingPriority='MaxTac'
    dropdown('Modes','Activity to move in priority order','priorityEditor',function()
        local rows={}
        for _,key in ipairs(A.Core.priorityOrder(A.settings.priority)) do rows[#rows+1]={key=key,label=A.Core.priorityLabels[key]} end
        return rows
    end,function(key) return editingPriority==key end,function(key) editingPriority=key end)
    button('Modes','Move selected activity higher',function() A.moveActivityPriority(editingPriority,-1) end)
    button('Modes','Move selected activity lower',function() A.moveActivityPriority(editingPriority,1) end)
    button('Modes','Reset activity priority',A.resetActivityPriority)
    note('Modes','Run locks','MaxTac, Tower, Time Trials and Dungeon finish or fail before priority switching. Enabled stuck recovery can leave an unfinished run only after its no-progress timeout. Mob Autofarm always comes last.')
    toggle('Modes','Auto leave stuck runs','autoLeaveStuck',function() A.coordinateActivities() end)
    input('Modes','Stuck timeout · other modes (seconds)','stuckSeconds',true,1,3600)
    input('Modes','Stuck timeout · Trial + Dungeon (seconds)','trialDungeonStuckSeconds',true,1,3600)
    note('Modes','Stuck detection','Defaults: 10 seconds for MaxTac, Tower, Gate, Raid, Defense and Boss Rush; 20 seconds shared by Time Trials and Dungeon. Kills, fewer remaining enemies, new waves/rooms/floors and run/boss phase changes reset the timer. Damage never resets it. Normal Tower join/choice timers, Gate ARISE delays and up to 30 seconds for a new Trial/Dungeon room handshake are allowed first. Walking and countdown updates do not reset it. Normal world mob farming is unaffected. Failed modes wait 30 seconds before this script rejoins.')
    status('Modes','Stuck recovery')
    note('Modes','Transfers','MaxTac, Tower, Trials and Dungeons use direct native entry. Other destinations wait for normal exit. MaxTac, Gate and Tower stay at their join position.')
    note('Modes','Movement','Time Trials and Dungeons follow mobs with continuous anti-stuck steps. Tower opens your own tower. Turn off competing auto-join / movement in your other script to let this coordinator control switching.')
    for _,entry in ipairs({{'MaxTac','maxTacAutoJoin','maxTacSelection'},{'Tower','towerAutoJoin','towerSelection'},{'Dungeon','dungeonAutoJoin','dungeonSelection'},{'Gate','gateAutoJoin','gateSelection'},{'Raid','raidAutoJoin','raidSelection'},
        {'Defense','defenseAutoJoin','defenseSelection'},
        {'BossRush','bossRushAutoJoin','bossRushSelection'}}) do
        local mode,toggleKey,selectionKey=entry[1],entry[2],entry[3]
        dropdown('Modes',mode..' selection',selectionKey,function()
            return A.activityRows(mode)
        end,function(key) return A.settings[selectionKey][key]==true end,
        function(selected)
            A.settings[selectionKey]=(mode=='Raid' or mode=='Defense') and {[selected]=true} or selected
            A.coordinateActivities()
        end,mode~='Raid' and mode~='Defense')
        if mode=='Gate' or mode=='MaxTac' then
            local ranksKey=mode=='Gate' and 'gateRanks' or 'maxTacRanks'
            dropdown('Modes',mode=='Gate' and 'Gate ranks' or 'MaxTac threats',ranksKey,mode=='Gate' and A.gateRankRows or A.maxTacRankRows,
                function(key) return A.settings[ranksKey][key]==true end,
                function(selected) A.settings[ranksKey]=selected; A.coordinateActivities() end,true)
            note('Modes',mode..' rank order',mode=='Gate' and 'S > A > B > C > D > E. Only declared ranks are listed.'
                or 'Low → Medium → High → Extreme → Psycho. MaxTac stays at its join position. Only enabled stuck recovery can leave a stalled unfinished run.')
        end
        toggle('Modes',mode=='Raid' and 'Auto start my own Raid' or (mode=='BossRush' and 'Auto start my own Boss Rush' or ('Auto join '..mode)),toggleKey,function(value)
            if mode=='Raid' or mode=='Defense' then A.setCombatEnabled(mode,value) else A.coordinateActivities() end
        end)
    end
    note('Modes','Boss Rush entry','Choose the exact variant, such as Cursed Rush or King of Curses. Creates your own run after checking the world unlock and key cost. Old base-only choices migrate to the declared V1 variant.')
    input('Pets','Name for unnamed Astral pets','petName')
    toggle('Pets','Auto rename Astral pets ONLY','rename')
    note('Pets','Astral naming','Only verified Astral rarity is eligible. Already named and percentage pets are skipped. Uses the normal Magicule cost. Check the status below for blockers.')
    status('Pets','Rename')
    status('Pets','Rename report')
    button('Pets','Retry unconfirmed renames',A.retryRenaming)
    toggle('Pets','Auto Pet Passive','petPassiveAuto',function(enabled)
        if not enabled then A.stopPetPassives() end
        A.tasks['Pet passives'].next=0
    end)
    note('Pets','Passive queue','Uses the game auto roll until Divine Predator. Scaling pets first, then Common–Astral pets by base power. Finishes the current pet before reprioritizing new pets. Pauses when tokens run out and resumes when replenished. This toggle controls the native Pet Passive queue; avoid running another passive roller at the same time.')
    status('Pets','Pet passives')
    note('Passives','Inventory queues','Uses the game auto roll, strongest base stats first, through Astral rarity. Keeps the current item until its Divine target is retained. New items join automatically; empty currency pauses the queue. Each toggle controls its own native roller; avoid using another script to roll that same type.')
    for _,item in ipairs({
        {kind='AccessoryCurse',title='Auto Accessory Curses',key='accessoryCurseAuto',status='Accessory curses',target='Calamity Curse'},
        {kind='SwordPassive',title='Auto Sword Passives',key='swordPassiveAuto',status='Sword passives',target='Sun Breathing'},
        {kind='TitanPassive',title='Auto Titan Passives',key='titanPassiveAuto',status='Titan passives',target='Rumbling'},
        {kind='ShadowPassive',title='Auto Shadow Passives',key='shadowPassiveAuto',status='Shadow passives',target='Grand Marshal'},
    }) do
        toggle('Passives',item.title,item.key,function(enabled)
            if not enabled then A.passiveQueues[item.kind].stop() end
            A.passiveQueues[item.kind].wake()
        end)
        note('Passives',item.target,'Already completed copies are skipped. Rolls each owned copy separately.')
        status('Passives',item.status)
    end
    dropdown('Cyber','Ripperdoc slots to upgrade','ripperdocSlots',A.ripperdocRows,
        function(key) return A.settings.ripperdocSlots[key]==true end,
        function(selected) A.settings.ripperdocSlots=selected end,true)
    toggle('Cyber','Auto upgrade selected Ripperdoc slots','ripperdocAuto')
    note('Cyber','Ripperdoc costs','Spends Eddies only when enabled, in the normal Head → Torso → Shoulder → Waist → Back order. Each previous slot must be maxed. Waits for the game to confirm every upgrade.')
    status('Cyber','Ripperdoc')
    local function wakeFixer() A.tasks['Fixer gigs'].next=0 end
    toggle('Cyber','Auto claim completed Fixer Gigs','fixerAutoClaim',wakeFixer)
    toggle('Cyber','Auto deploy pets to Fixer Gigs','fixerAutoDeploy',wakeFixer)
    choose('Cyber','Fixer deployment order','fixerPreference',choices({'Board order','Big Jobs first'}))
    status('Cyber','Fixer gigs')
    note('Cyber','Fixer deployment','Uses your 4th, 5th and 6th strongest non-scaling pets, filling available gigs in your chosen order. Pets already on gigs stay in the ranking and are skipped. Enable auto claim too to collect rewards and keep deploying. Sending a pet makes it unavailable for combat until claimed.')
    toggle('Guild','Auto Claim Guild Quests','guildAutoClaim',function() A.tasks['Guild quests'].next=0 end)
    note('Guild','Completed missions','Claims completed personal daily and weekly guild missions only. Does not perform mission objectives, spend guild points, or change guild membership. Waits for the claimed flag before moving on.')
    status('Guild','Guild quests')
    choose('Settings','Automatic loadout objective','loadoutStat',choices({'Power','Damage','Yen','XP','Drop','Luck','Kill','CritChance','CritDamage','ShinyChance'}))
    toggle('Settings','Auto Equip Best Loadout','loadoutAuto',A.wakeLoadout)
    note('Settings','Equipment ownership','Uses native Equip Best after inventory / upgrade changes. This can replace your equipped items. Enable only if JoesAAS should control your loadout; disable competing equipment automation. Active gig pets follow the game restrictions.')
    status('Settings','Loadout')
    dropdown('Cyber','Quickhacks to overclock','overclockSelection',A.overclockRows,
        function(id) return A.settings.overclockSelection[id]==true end,
        function(selected) A.settings.overclockSelection=C.trueKeys(selected) end,true)
    toggle('Cyber','Auto Overclock selected quickhacks','overclockAuto')
    note('Cyber','Overclock budget','Spends Overclock Chips on selected MAX LEVEL quickhacks only, using native costs and replication confirmation. No purchases or drop-only level upgrades.')
    local planKey,planTarget=nil,'0'
    dropdown('Cyber','Point plan entry','pointPlanEditor',A.cyberPlanRows,
        function(key) return planKey==key end,function(key) planKey=key end)
    local planInput=tabs.Cyber:AddInput('pointPlanTarget',{Title='Target level for selected entry',Default='0',Numeric=true,Finished=false})
    planInput:OnChanged(guard(function(value) planTarget=tostring(value) end))
    button('Cyber','Add / update selected point target',function()
        assert(planKey,'Choose an attribute or Common quickhack')
        local cfg=A.config('CyberdeckConfig'); local kind,id=planKey:match('^([^:]+):(.+)$')
        local maximum=kind=='Attribute' and cfg.AttributeMaxLevel or cfg.Quickhacks[id].MaxLevel
        local n=tonumber(planTarget); assert(n and n==n and n>=0 and n<=maximum,'Target must be 0–'..maximum)
        A.settings.cyberPlanTargets[planKey]=math.floor(n)
        if not C.contains(A.settings.cyberPlanOrder,planKey) then table.insert(A.settings.cyberPlanOrder,planKey) end
    end)
    button('Cyber','Move selected point target to first',function()
        for i=#A.settings.cyberPlanOrder,1,-1 do if A.settings.cyberPlanOrder[i]==planKey then table.remove(A.settings.cyberPlanOrder,i) end end
        if planKey and A.settings.cyberPlanTargets[planKey] then table.insert(A.settings.cyberPlanOrder,1,planKey) end
    end)
    button('Cyber','Remove selected point target',function()
        if planKey then A.settings.cyberPlanTargets[planKey]=nil end
        for i=#A.settings.cyberPlanOrder,1,-1 do if A.settings.cyberPlanOrder[i]==planKey then table.remove(A.settings.cyberPlanOrder,i) end end
    end)
    local planNote=note('Cyber','Saved point allocation order','No targets selected')
    statuses[#statuses+1]=function()
        local rows={}
        for i,key in ipairs(A.settings.cyberPlanOrder) do rows[#rows+1]=i..'. '..key..' → '..tostring(A.settings.cyberPlanTargets[key] or 0) end
        planNote:SetDesc(#rows>0 and table.concat(rows,'\n') or 'No targets selected')
    end
    toggle('Cyber','Auto allocate planned Cyberdeck points','cyberPlanAuto')
    note('Cyber','Permanent spending','OFF by default. Points cannot be refunded. Add explicit target levels and order first. Attributes and Common quickhacks share one confirmed spending worker; Rare / Epic quickhack levels remain drop-only.')
    status('Cyber','Cyber plan')
    note('Index','Missing collections','Accessories, pet accessories, titans, shadows, swords, primordials and mounts. Checks the game Index, including its collection history. Pets are excluded.')
    button('Index','Send missing index to Discord',A.sendIndexReport)
    note('Index','Report details','Uses your fixed report webhook. Shows world, source and base chance on numbered category pages. Purchases and claims are marked guaranteed; unpublished details are marked unknown. Works independently of the other webhook settings.')
    status('Index','Index')
    input('Webhook','Webhook URL','webhookURL'); input('Webhook','Discord user ID','pingId')
    toggle('Webhook','Enable webhook','webhook'); toggle('Webhook','Send disconnect notification','sendDisconnect')
    toggle('Webhook','Ping selected user','ping')
    multi('Webhook','Events to send','webhookEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    multi('Webhook','Events to ping','pingEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    toggle('Webhook','Save webhook URL locally with settings','saveSecrets')
    button('Webhook','Send test notification',function() A.notify('Test','Webhook test from JoesAAS',true) end)
    note('Webhook','Disconnect limits','Disconnect notices send while the executor can still run. A force-closed Roblox app cannot send a webhook. Settings restore automatically; enable local URL storage above to restore your webhook URL too.')
    status('Webhook','Webhook'); status('Webhook','Disconnect')
    note('Settings','Automatic settings','Choices and toggles save automatically. Typing saves after a short pause. The next time you execute JoesAAS, it restores your settings and resumes enabled features. No Save, Load or Autoload buttons are needed.')
    toggle('Settings','Black screen / disable 3D rendering','blackScreen',function(value) if A.render then A.render(value) end end)
    note('Settings','Controls',touch and 'Tap JoesAAS to hide/show; drag it to reposition. Use each feature’s own toggle. RESTORE enables rendering. Landscape gives the menus more room.'
        or 'Right Shift: minimize/show Fluent. F8: restore rendering.')
    note('Settings','Executor capabilities',
        'Automatic settings: '..((type(writefile)=='function' and type(readfile)=='function' and type(makefolder)=='function') and 'available' or 'file APIs missing')
        ..' | Webhook HTTP: '..(A.httpRequest and 'available' or 'request API missing')
        ..'. Rendering availability is checked when you use it.')
    status('Settings','Settings')
    status('Settings','Gameplay')
    button('Settings','Refresh catalogs',function() A.discover(); A.refreshUI() end)
    button('Settings','Write diagnostics',function()
        local ok,err=pcall(function()
        assert(type(writefile)=='function','File API unavailable')
        pcall(makefolder,A.folder)
        local jobs,enabled={},{}
        for name,job in pairs(A.tasks) do jobs[name]={busy=job.busy,failures=job.failures,nextIn=math.max(0,job.next-os.clock())} end
        for key,value in pairs(A.settings) do if type(value)=='boolean' then enabled[key]=value end end
        writefile(A.folder..'/diagnostics.json',A.S.HTTP:JSONEncode({version=A.version,rename=A.renameDiagnostics(),status=A.status,logs=A.logs,jobs=jobs,enabled=enabled,
            running=A.running,
            worlds=#C.keys(A.catalog.worlds),enemies=#C.keys(A.catalog.enemies)}))
        assert(A.safeLoad(A.folder..'/diagnostics.json'),'Could not read back diagnostics file')
        end)
        A.status.Settings=ok and ('Saved '..A.folder..'/diagnostics.json') or ('Diagnostics save failed: '..tostring(err))
        A.log('Diagnostics',A.status.Settings)
        F:Notify({Title='Diagnostics',Content=A.status.Settings,Duration=8})
    end)
    button('Settings','Unload',A.stop); status('Settings','Rendering')
    A.overlay=Instance.new('ScreenGui'); A.overlay.Name='JoesAASBlackScreen'
    A.overlay.ResetOnSpawn=false; A.overlay.IgnoreGuiInset=true; A.overlay.DisplayOrder=100000; A.overlay.Enabled=false
    A.overlay.Parent=A.player:WaitForChild('PlayerGui')
    local black=Instance.new('TextButton'); black.Size=UDim2.fromScale(1,1); black.BackgroundColor3=Color3.new(0,0,0)
    black.Text=touch and 'Tap to restore rendering' or 'Rendering disabled - click here or press F8 to restore'
    black.TextColor3=Color3.new(1,1,1); black.TextWrapped=true; black.TextSize=18
    black.AutoButtonColor=false; black.Parent=A.overlay
    function A.render(disabled)
        local ok=true
        if disabled or A.renderOwned then
            ok=pcall(function() A.S.Run:Set3dRenderingEnabled(not disabled) end)
            if ok then A.renderOwned=disabled end
        end
        A.overlay.Enabled=disabled; A.settings.blackScreen=disabled
        if A.touchControls then A.touchControls.RESTORE.Visible=disabled end
        A.status.Rendering=disabled and (ok and '3D rendering disabled' or 'Overlay only: rendering API unavailable') or 'Rendering enabled'
        if A.refreshUI then A.refreshUI() end
        A.settingsChanged()
    end
    function A.restoreRendering()
        if A.renderOwned then A.S.Run:Set3dRenderingEnabled(true); A.renderOwned=false end
    end
    A.connect(black.Activated,function() A.render(false) end)
    A.connect(A.S.UIS.InputBegan,function(key) if key.KeyCode==Enum.KeyCode.F8 then A.render(false) end end)
    function A.refreshUI()
        if sync or not A.alive then return end
        sync=true
        local ok,why=pcall(function() for _,update in ipairs(bindings) do update() end end)
        sync=false
        if not ok then A.log('UI',why) end
    end
    sync=false; A.render(A.settings.blackScreen); A.refreshUI(); window:SelectTab(1)
    A.job('UI status',1,function()
        if F.Unloaded or not A.gui.Parent then A.stop(); return end
        for _,update in ipairs(statuses) do update() end
    end,true)
end


end)()(A);

A.schedule()
A.finishStartup()
end)
if not bootOK then
    if A.stop then pcall(A.stop) end
    warn("JoesAAS startup failed: " .. tostring(bootError))
end
