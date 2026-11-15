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
eq(HC.Settings.window.backdrop.bgFile,"Interface\\FrameGeneral\\UI-Background-Rock","raid reference rock interior")
eq(HC.Settings.window.hcOpaqueBase~=nil,true,"opaque backplate prevents world bleed-through")
eq(HC.Settings.window.hcRaidBorder.tl.texture,"Interface\\RaidFrame\\RaidPanel-UpperLeft","actual raid-panel border pieces")
eq(HC.Settings.window:GetWidth(),860,"compact native width")
eq(HC.Settings.buttons.General.template,"PanelTopTabButtonTemplate","native horizontal navigation tabs")
eq(HC.Settings.tabBar:IsShown(),false,"no redundant single-page tab")
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
local tile=CreateFrame("Button",nil,UIParent,"BackdropTemplate")
HC.Theme.Border(tile,"accent")
eq(tile.hcNativeFeedbackRole,"accent","label-free binding tiles retain native selection")
eq(rawget(tile,"Text"),nil,"selected icon tiles need no synthetic text label")

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
HC.Quiz.run={{question="Test",choices={"A","B","C","D"},correct=2}}
HC.Quiz.index=0;HC.Quiz.score=0;HC.Quiz:Next();HC.Quiz:Answer(1)
eq(HC.Quiz.frame.answers[2].hcNativeFeedbackRole,"accent","native quiz reveals correct answer")
eq(HC.Quiz.frame.answers[1].hcNativeFeedbackRole,"danger","native quiz identifies wrong pick")
HC.Quiz.index=0;HC.Quiz:Next()
eq(HC.Quiz.frame.answers[2].hcNativeFeedback:IsShown(),false,"native verdict clears for next question")

eq(_G.ConsecratedHammerWhatsNew,nil,"native news never registers the shared renderer")
eq(saved.hammerCore.whatsNewSeen,"1.0.0","queued news is not marked shown")
tick()
eq(HC.WhatsNew.frame:IsShown(),true,"native automatic news shown")
eq(saved.hammerCore.whatsNewSeen,"2.0.0","shown news marked once")
HC.WhatsNew:Hide()
eq(ConsecratedHammerWelcome.busy,0,"native close releases reservation")
eq(ConsecratedHammerWelcome.open,nil,"native close releases owner")

-- Native geometry must survive template callbacks and extra pages.
install()
local G=load("Native",true,nil,function(H)
    H.spec.railButton={label="Back",run=function()end}
    H.Settings:NewPage({name="Complex",description="A wrapped page description",tabs={
        {name="First",build=function(_,y)return y end},
        {name="Second",build=function(_,y)return y end}}})
end)
G.Settings:Show("Complex")
for _,button in pairs(G.Settings.buttons)do button.Text.GetStringWidth=function()return 200 end end
G.Settings:LayoutNativeNavigation()
eq(G.Settings.nativeNavRows>1,true,"extra native pages wrap")
local nav=G.Settings.buttons.General
local width=nav:GetWidth()
nav.scripts.OnShow(nav);nav.scripts.OnEvent(nav,"DISPLAY_SIZE_CHANGED")
eq(nav:GetWidth(),width,"template callbacks retain owned navigation geometry")
for _,spec in ipairs(G.Settings.order)do
    local button=G.Settings.buttons[spec.name]
    eq(button.points[1][2]+button:GetWidth()<=828,true,"wrapped tab remains within window")
end
eq(G.Settings.tabButtons[1].template,"PanelTopTabButtonTemplate","internal tabs use native art")
eq(G.Settings.tabButtons[1].line:IsShown(),false,"internal tabs have no Modern underline")
eq(G.Settings.tabButtons[1].Text.textColour[1],G.Theme.Colour("accent")[1],"active native subtab keeps gold label")
eq(G.Settings.header:GetHeight()>=116,true,"internal tabs reserve header space")
eq(G.Settings.railButton:GetParent(),G.Settings.footer,"optional rail action moves to footer")
local probe=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
probe.Center=probe:CreateTexture()
probe.Center.SetDrawLayer=function(self,layer,level)self.drawLayer,self.drawLevel=layer,level end
G.Theme.Surface(probe,"outer","edge")
eq(probe.Center.drawLevel,-7,"client texture draws above opaque base")
eq(probe.hcRaidBorder.tl:GetParent(),probe,"border remains behind child controls")
local vertical=CreateFrame("Slider",nil,UIParent)
G.Theme.SliderArt(vertical,vertical:CreateTexture(),vertical:CreateTexture(),true)
eq(vertical.hcNativeGroove~=nil,true,"vertical scrollbar retains a native groove")

-- Whole-addon style selection is persisted separately and applied only on reload.
install()
local reloads=0
ReloadUI=function()reloads=reloads+1 end
local function switcher(H)H.spec.presentationSwitcher=true end
local P,choice=load("Native",true,nil,switcher)
P.Settings:Show("General")
eq(P.Settings.styleButton:GetText(),"Style: Classic","default preserves the native preview")
wow.Click(P.Settings.styleButton);wow.Click(P.Dialog.frame.cancel)
eq(choice.hammerCore.presentation,nil,"cancel does not save a style")
eq(reloads,0,"cancel does not reload")
wow.Click(P.Settings.styleButton);combat=true;wow.Click(P.Dialog.frame.accept)
eq(choice.hammerCore.presentation,nil,"combat does not save a style")
eq(reloads,0,"combat does not reload")
combat=false;wow.Click(P.Settings.styleButton);wow.Click(P.Dialog.frame.accept)
eq(choice.hammerCore.presentation,"modern","accept saves Modern choice")
eq(reloads,1,"accept requests one reload")
eq(HC.Settings.styleButton,nil,"fixed preview still has no switch")
eq(P.DiagnosticReport():find("Style: Classic; saved: Modern; reload to apply",1,true)~=nil,true,"diagnostics show pending whole-addon choice")
eq(P.Theme.IsBlizzard(),true,"existing session stays Classic until reload")
P.Copy:Show("Report","test")
eq(P.Copy.frame.hcPresentation,"blizzard","lazy window stays with current session")
eq(choice.hammerCore.theme,"modern","legacy preference preserved")
-- Simulate reload into the same character's saved database.
install();ReloadUI=function()reloads=reloads+1 end
P=load("Native",true,choice,switcher)
P.Settings:Show("General")
eq(P.Theme.IsBlizzard(),false,"saved Modern applies on next session")
eq(P.Settings.styleButton:GetText(),"Style: Modern","switch also exists in Modern")
eq(P.Settings.window:GetWidth(),1000,"Modern uses the original settings shell")
eq(P.Settings:Search("Classic")[1]~=nil,true,"style switch is searchable")
choice.hammerCore.theme="classic"
eq(select(2,P.Theme.Active()),"modern","Modern whole-addon style remains frozen")
wow.Click(P.Settings.styleButton);wow.Click(P.Dialog.frame.accept)
eq(choice.hammerCore.presentation,"blizzard","Modern can save Classic choice")
eq(reloads,2,"reverse switch requests one reload")
eq(P.Theme.IsBlizzard(),false,"reverse switch cannot partly reskin session")
P.Copy:Show("Report","test")
eq(P.Copy.frame.hcPresentation,nil,"Modern lazy dialog stays Modern until reload")
install();P=load("Native",true,choice,switcher)
eq(P.Theme.IsBlizzard(),true,"Classic restored on next session")
eq(P.Theme.SetPresentation("unknown"),false,"invalid selection rejected")
eq(P.Theme.Set("modern"),true,"hidden command saves the whole-addon choice")
eq(P.Theme.IsBlizzard(),true,"hidden command is also reload-only")
install();P=load("Native",true,{hammerCore={presentation="invalid"}},switcher)
eq(P.Theme.IsBlizzard(),true,"invalid saved selection falls back to build default")
install();P=load("Other",false,{hammerCore={presentation="blizzard"}})
eq(P.Theme.IsBlizzard and P.Theme.IsBlizzard() or false,false,"non-opted-in peer ignores style preference")
P.Settings:Show("General")
eq(P.Settings.styleButton,nil,"non-opted-in consumer has no switch")

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

-- Reopening a visible native window is idempotent, including combat.
install();N,saved=load("Native",true);tick();combat=true
local seen=saved.hammerCore.whatsNewSeen
N.WhatsNew:Show()
eq(N.WhatsNew.nativeRequest,nil,"manual repeat raises the existing visible notice")
eq(saved.hammerCore.whatsNewSeen,seen,"repeated visible visit leaves seen record alone")
-- A genuinely new lower-level request retains its accepted delivery on close.
N.WhatsNew:RequestNative(N.WhatsNew:Section(N.WhatsNew:Releases()),false)
N.WhatsNew:Hide()
eq(N.WhatsNew.nativeRequest~=nil,true,"closing an old notice preserves a separately deferred request")
combat=false;N.WhatsNew:TryShow()
eq(N.WhatsNew.frame:IsShown(),true,"deferred request survives old-window close")
N.WhatsNew:Hide()
-- An ordinary manual display without a pending automatic notice is not consumption.
N,saved=load("Third",true,{hammerCore={whatsNew=false,whatsNewSeen="1.0.0"}})
saved.hammerCore.whatsNewSeen="1.0.0"
N.WhatsNew:Show()
eq(saved.hammerCore.whatsNewSeen,"1.0.0","standalone manual display preserves Modern seen semantics")
N.WhatsNew:Hide()

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
-- Dismissal survives a fresh login using only serialized SavedVariables.
local function copySaved(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value)do result[key]=copySaved(item)end;return result
end
for _,native in ipairs({true,false})do
    install()
    local name=native and "Native" or "Other"
    local H,state=load(name,native)
    tick()
    eq(H.WhatsNew.frame:IsShown(),true,"unseen update opens before dismissal")
    H.WhatsNew:Hide()
    local persisted=copySaved(state)
    install();H=load(name,native,persisted);tick()
    eq(H.WhatsNew.frame==nil or not H.WhatsNew.frame:IsShown(),true,"dismissed update stays closed on fresh login")
    eq(H.WhatsNew.nativeRequest,nil,"fresh login cannot requeue dismissed native update")
    -- Still notify for an actual new release, then remain quiet after that dismissal.
    install();H=load(name,native,persisted,function(core)
        core.spec.whatsNew={{version="3.0.0",items={{text="A new update"}}},unpack(NOTES)}
    end);tick()
    eq(H.WhatsNew.frame:IsShown(),true,"newer release can notify again")
    H.WhatsNew:Hide();persisted=copySaved(persisted)
    install();H=load(name,native,persisted,function(core)
        core.spec.whatsNew={{version="3.0.0",items={{text="A new update"}}},unpack(NOTES)}
    end);tick()
    eq(H.WhatsNew.frame==nil or not H.WhatsNew.frame:IsShown(),true,"new release also stays dismissed on next login")
end
io.write("Native presentation: "..checks.." checks passed\n")
