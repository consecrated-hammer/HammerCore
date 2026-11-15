package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")
local checks = 0
local function eq(a,b,label)
    checks=checks+1
    if a~=b then error(label..": expected "..tostring(b)..", got "..tostring(a),2) end
end
local NOTES={{version="2.0.0",date="2026-11-15",items={{text="Native UI",page="General"}}}}
local timers,combat
local function install()
    wow.Install({Native={Version="2.0.0"},Other={Version="2.0.0"},Third={Version="2.0.0"}})
    timers={};combat=false
    InCombatLockdown=function()return combat end
    IsLoggedIn=function()return true end
    C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
end
local function tick()
    local pending=timers;timers={}
    for _,fn in ipairs(pending)do fn()end
end
local function load(name,native,saved,beforeStart)
    saved=saved or {hammerCore={startupMessage=false,whatsNewSeen="1.0.0",theme="modern"}}
    local HC=wow.LoadHammerCore(native and "src" or (os.getenv("HAMMERCORE_PREVIOUS_SOURCE") or "src"),name).HammerCore
    HC:Init({name=name,command=name:lower(),icon="icon",presentation=native and "blizzard" or nil,
        db=function()return saved end,whatsNew=NOTES})
    HC.Settings:NewPage({name="General"},function(panel,y)
        local row;row,y=HC.UI.Check(panel,"Enabled",nil,y,function()return saved.on end,function(v)saved.on=v end)
        HC.testCheck=row.hcCheckbox
        HC.testSlider,y=HC.UI.Slider(panel,"Size",nil,y,1,10,1,function()return saved.size or 5 end,function(v)saved.size=v end)
        return y
    end)
    if beforeStart then beforeStart(HC) end
    HC:Start()
    return HC,saved
end

-- Entire lazy UI uses the scoped presentation; saved legacy preference is preserved.
install()
local HC,saved=load("Native",true)
eq(HC.Theme.IsBlizzard(),true,"native opt-in")
eq(saved.hammerCore.theme,"modern","saved Modern preference preserved")
HC.Settings:Show("General")
eq(next(HC.Settings.errors),nil,"all reference pages construct")
eq(HC.Settings.window.hcPresentation,"blizzard","native shell")
eq(HC.Settings.window.backdrop.edgeFile,HC.Theme.NATIVE.border,"Blizzard outer border")
eq(HC.testCheck.normalTexture,"Interface\\Buttons\\UI-CheckBox-Up","native checkbox")
wow.Click(HC.testCheck);eq(saved.on,true,"one click toggles once")
wow.Click(HC.testCheck);eq(saved.on,false,"second click toggles once")
saved.hammerCore.theme="classic"
eq(select(2,HC.Theme.Active()),"blizzard","late saved-theme changes cannot reskin lazy UI")
eq(HC.Theme.Set("modern"),false,"fixed preview cannot claim a live theme switch")
local toggle=HC.UI.Switch(HC.Settings.window)
eq(toggle.nativeCheck.normalTexture,"Interface\\Buttons\\UI-CheckBox-Up","direct switches use native checks")
toggle:SetChecked(true);eq(toggle:GetChecked(),true,"native switch retains checked contract")
local box=HC.testSlider.hcValueBox
box.scripts.OnEditFocusGained(box);box:SetText("9");box.scripts.OnEnterPressed(box)
eq(saved.size,9,"native numeric input commits")
box.scripts.OnEditFocusGained(box);box:SetText("3");box.scripts.OnEscapePressed(box)
eq(saved.size,9,"native numeric Escape cancels")
HC.Bindings.Capture:Start({title="Test",inputs={keys=true},onKey=function()return true end})
eq(HC.Bindings.Capture.frame.prompt.hcPresentation,"blizzard","binding capture prompt is native")
HC.Bindings.Capture:Stop()
HC.Menu:Open({{text="Checked",checked=true},{text="Disabled",disabled=true}})
eq(HC.Menu.frame.hcPresentation,"blizzard","native menu")
eq(HC.Menu.items[1].check.texture,HC.Theme.NATIVE.check,"native menu tick")
HC.Dialog:Confirm({title="Clear",text="Clear?"})
eq(HC.Dialog.frame.hcPresentation,"blizzard","native confirmation")
HC.Dialog.frame:Hide()
HC.Copy:Show("Report","Long report")
eq(HC.Copy.frame.hcPresentation,"blizzard","native report")
HC.Quiz:Create()
eq(HC.Quiz.frame.hcPresentation,"blizzard","native quiz")
eq(HC.Quiz.frame.timer.texture,HC.Theme.NATIVE.progress,"native quiz progress")
eq(_G.ConsecratedHammerWhatsNew,nil,"native news never registers the shared renderer")
eq(saved.hammerCore.whatsNewSeen,"1.0.0","queued news is not marked shown")
tick()
eq(HC.WhatsNew.frame:IsShown(),true,"native automatic news shown")
eq(saved.hammerCore.whatsNewSeen,"2.0.0","shown news marked once")
HC.WhatsNew:Hide()
eq(ConsecratedHammerWelcome.busy,0,"native close releases reservation")
eq(ConsecratedHammerWelcome.open,nil,"native close releases owner")

-- Both registration orders preserve the old Modern aggregate and serialize notices.
for _,nativeFirst in ipairs({true,false})do
    install()
    local N,O,oldRender
    if nativeFirst then N=load("Native",true);O=load("Other",false) else O=load("Other",false);oldRender=ConsecratedHammerWhatsNew.render;N=load("Native",true)end
    eq(#ConsecratedHammerWhatsNew.sections,1,"only Modern section in shared queue")
    if oldRender then eq(ConsecratedHammerWhatsNew.render,oldRender,"native does not replace old renderer")end
    tick()
    eq(N.WhatsNew.frame:IsShown(),true,"native notice owns first slot")
    eq(O.WhatsNew.frame==nil,true,"Modern notice waits")
    N.WhatsNew:Hide()
    eq(O.WhatsNew.frame:IsShown(),true,"Modern aggregate follows native close")
    eq(O.Theme.IsBlizzard and O.Theme.IsBlizzard() or false,false,"other addon remains Modern")
    eq(O.WhatsNew.frame.hcPresentation,nil,"other popup is untouched")
end

-- Already-visible Modern news is observed without hiding it or consuming its state.
install()
local O=load("Other",false);tick()
local N=load("Native",true);tick()
eq(N.WhatsNew.frame==nil,true,"native waits for an existing old popup")
eq(O.WhatsNew.frame:IsShown(),true,"old popup remains visible")
O.WhatsNew:Hide();tick()
eq(N.WhatsNew.frame:IsShown(),true,"native follows an existing old popup")
N.WhatsNew:Hide()

-- Actual old/new Welcome scheduling takes precedence in both startup orders.
for _,nativeFirst in ipairs({true,false})do
    install()
    local function welcome(H)
        H.Welcome:Register({rows={{key="choice",label="Pick",choices={{value="yes",label="Yes"}},get=function()return "yes"end,set=function()end}}})
    end
    local oldSaved={hammerCore={startupMessage=false,whatsNewSeen="1.0.0",welcomePending=true}}
    if nativeFirst then N=load("Native",true);O=load("Other",false,oldSaved,welcome)
    else O=load("Other",false,oldSaved,welcome);N=load("Native",true)end
    tick()
    eq(O.Welcome.frame:IsShown(),true,"old welcome opens before native news")
    eq(N.WhatsNew.frame==nil,true,"welcome delays native news")
    eq(#ConsecratedHammerWelcome.queue,1,"native waits once in compatible queue")
    O.Welcome:Hide()
    eq(N.WhatsNew.frame:IsShown(),true,"native follows welcome dismissal")
    N.WhatsNew:Hide()
    eq(ConsecratedHammerWelcome.busy,0,"all welcome/native claims released")
end

-- Combat holds the reservation; manual opening replaces its own automatic request.
install();combat=true
N,saved=load("Native",true);tick()
eq(N.WhatsNew.frame==nil,true,"no automatic opening during combat")
eq(N.WhatsNew:Show(),true,"deferred manual notice is accepted")
eq(ConsecratedHammerWelcome.busy,1,"manual and automatic share one reservation")
combat=false;N.WhatsNew:TryShow()
eq(N.WhatsNew.frame:IsShown(),true,"deferred manual notice opens")
N.WhatsNew:Hide();tick()
eq(N.WhatsNew.frame:IsShown(),false,"no duplicate automatic popup after manual display")
eq(ConsecratedHammerWelcome.busy,0,"deferred notice releases once")

-- Opt-out while waiting drops the reservation without pretending a window was shown.
install();N,saved=load("Native",true);saved.hammerCore.whatsNew=false;tick()
eq(N.WhatsNew.frame==nil,true,"pending opt-out stays quiet")
eq(ConsecratedHammerWelcome.busy,0,"opt-out releases coordination")
eq(saved.hammerCore.whatsNewSeen,"1.0.0","unshown cancelled notice not marked shown")

-- Failed renders release older copies and retry only once; manual can recover later.
install();N,saved=load("Native",true)
local show=N.WhatsNew.ShowSections
N.WhatsNew.ShowSections=function()error("render failure")end
tick();tick()
eq(ConsecratedHammerWelcome.busy,0,"render failure cannot wedge other addons")
eq(ConsecratedHammerWelcome.open,nil,"failed render releases owner")
eq(saved.hammerCore.whatsNewSeen,"1.0.0","failed render not marked shown")
eq(N.WhatsNew.nativeRequest,nil,"failed automatic retry is bounded")
N.WhatsNew.ShowSections=show;N.WhatsNew:Show()
eq(N.WhatsNew.frame:IsShown(),true,"manual request recovers after failed automatic render")
N.WhatsNew:Hide()

-- Missing saved state suppresses fresh-install notifications as before.
install();N=load("Native",true,{})
eq(N.WhatsNew.nativeRequest,nil,"fresh install remains quiet")
eq(_G.ConsecratedHammerWhatsNew,nil,"fresh install cannot take over aggregate")
-- The capability remains safe if another consumer opts in later.
install();N=load("Native",true);local T=load("Third",true);tick()
eq(N.WhatsNew.frame:IsShown(),true,"first native owner opens")
eq(T.WhatsNew.frame==nil,true,"second native owner waits")
N.WhatsNew:Hide();eq(T.WhatsNew.frame:IsShown(),true,"second native owner follows")
T.WhatsNew:Hide();eq(ConsecratedHammerWelcome.busy,0,"all native claims released")
io.write("Native presentation: "..checks.." checks passed\n")
