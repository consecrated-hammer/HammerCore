package.path="./tests/?.lua;"..package.path
local wow=require("wow")
local count=0
local function eq(a,b,label) count=count+1;assert(a==b,label..": "..tostring(a).." ~= "..tostring(b)) end
for _,theme in ipairs({"modern","classic"}) do
 wow.Install()
 local ns=wow.LoadHammerCore("src","Test");local HC=ns.HammerCore
 HC.Theme.registry.classic.available=true
 local saved={hammerCore={theme=theme}}
 HC:Init({name="Test",command="test",db=function()return saved end})
 local panel=CreateFrame("Frame",nil,UIParent);panel.hcColumns=2;panel.hcRefresh={}
 local current,calls=5,0
 local row=HC.UI.Slider(panel,"Test value","Editable",0,1,11,2,function()return current end,function(v)current=v;calls=calls+1 end,function(v)return v.." px" end)
 local box,slider=row.hcValueBox,row.hcSlider
 eq(box.kind,"EditBox","numeric field is an edit box")
 eq(box:GetText(),"5 px","unfocused value formatted")
 local function typeValue(text)
  box.scripts.OnEditFocusGained(box);box:SetText(text)
 end
 typeValue("8");box.scripts.OnEnterPressed(box)
 eq(current,9,"snap relative to nonzero minimum")
 eq(calls,1,"single Enter commit")
 box.scripts.OnEditFocusLost(box);eq(calls,1,"focus loss does not double commit")
 typeValue("-100");box.scripts.OnEditFocusLost(box);eq(current,1,"lower clamp")
 typeValue("900");box.scripts.OnEnterPressed(box);eq(current,11,"upper clamp")
 typeValue("bad");box.scripts.OnEnterPressed(box);eq(current,11,"invalid entry ignored")
 eq(box:GetText(),"11 px","invalid entry restores formatting")
 typeValue("3");box.scripts.OnEscapePressed(box);eq(current,11,"Escape cancels")
 eq(box:GetText(),"11 px","Escape restores display")
 typeValue("7");for _,fn in ipairs(panel.hcRefresh)do fn()end
 eq(box:GetText(),"7","refresh preserves unfinished edit")
 box.scripts.OnEditFocusLost(box);eq(current,7,"blur commits")
 slider.scripts.OnMouseWheel(slider,1);eq(current,9,"wheel still steps")
 eq(slider:GetWidth()<80,true,"half-pane slider narrower")
 local full=CreateFrame("Frame",nil,UIParent);full.hcColumns=1
 local fullRow=HC.UI.Slider(full,"Full",nil,0,0,2,0.1,function()return 1 end,function(v)current=v end)
 eq(fullRow.hcSlider:GetWidth()>slider:GetWidth(),true,"full-pane track retains room")
 local input=fullRow.hcValueBox;input.scripts.OnEditFocusGained(input);input:SetText("1.26");input.scripts.OnEnterPressed(input)
 eq(math.abs(current-1.3)<0.00001,true,"decimal values snap")
end
-- Percentage display units and editing/wheel interaction.
wow.Install()
local ns=wow.LoadHammerCore("src","Test");local HC=ns.HammerCore
HC:Init({name="Test",command="test",db=function()return {} end})
local panel=CreateFrame("Frame",nil,UIParent);panel.hcColumns=2
local saved=0.5
local row=HC.UI.Slider(panel,"Opacity",nil,0,0,1,0.05,function()return saved end,function(v)saved=v end,
 function(v)return math.floor(v*100+0.5).."%"end,nil,100)
local box=row.hcValueBox
box.scripts.OnEditFocusGained(box);eq(box:GetText(),"50","percentage editing uses visible units")
box:SetText("65");box.scripts.OnEnterPressed(box);eq(saved,0.65,"percentage typed value converted")
box.scripts.OnEditFocusGained(box);box:SetText("70")
row.hcSlider.scripts.OnMouseWheel(row.hcSlider,1)
eq(saved,0.75,"wheel commits pending edit before stepping")
box.scripts.OnEditFocusLost(box);eq(saved,0.75,"blur cannot overwrite wheel result")
eq(box:GetText(),"75%","formatted percentage restored")
local ok=pcall(HC.UI.Slider,panel,"Bad",nil,0,0,1,0,function()return 0 end,function()end)
eq(ok,false,"zero step rejected")
io.write("Editable sliders: "..count.." checks passed\n")
