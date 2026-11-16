package.path="./tests/?.lua;"..package.path
local wow=require("wow")
local checks=0
local function eq(a,b,why)checks=checks+1;if a~=b then error(why..": expected "..tostring(b)..", got "..tostring(a),2)end end
local world
local function create(name,version,saved)
    world.meta[name]={Version=version}
    local H=wow.LoadHammerCore("src",name).HammerCore
    saved=saved or {hammerCore={startupMessage=false}}
    H:Init({name=name,command=name:lower(),db=function()return saved end})
    H:Start()
    return H,saved
end
local function setup(version,saved,legacy,noTimer)
    world={meta={},clock=100,epoch=1800000000,timers={},sends={},registered=0,guild=true,home=false,instance=false,raid=false}
    wow.Install(world.meta)
    GetTime=function()return world.clock end
    GetServerTime=function()return world.epoch+math.floor(world.clock-100)end
    IsLoggedIn=function()return true end
    UnitFullName=function()return "Me","Realm"end
    GetNormalizedRealmName=function()return "Realm"end
    IsInGuild=function()return world.guild end
    LE_PARTY_CATEGORY_HOME,LE_PARTY_CATEGORY_INSTANCE=1,2
    IsInGroup=function(category)
        if category==2 then return world.instance end
        if category==1 then return world.home end
        return world.home or world.instance
    end
    IsInRaid=function()return world.home and world.raid end
    GetNumGroupMembers=function(category)return category==2 and (world.instance and (world.instanceCount or 5) or 0)
        or (world.home and (world.homeCount or 2) or 0)end
    local function register()world.registered=world.registered+1;return true end
    local function send(prefix,payload,channel)world.sends[#world.sends+1]={prefix=prefix,payload=payload,channel=channel,at=world.clock};return true end
    if legacy then C_ChatInfo=nil;RegisterAddonMessagePrefix=register;SendAddonMessage=send
    else C_ChatInfo={RegisterAddonMessagePrefix=register,SendAddonMessage=send};RegisterAddonMessagePrefix,SendAddonMessage=nil,nil end
    C_Timer=not noTimer and {After=function(delay,fn)world.timers[#world.timers+1]={at=world.clock+delay,fn=fn}end}or nil
    return create("TestAddon",version,saved)
end
local function advance(seconds)
    local stop=world.clock+seconds
    while true do
        local nextIndex
        for i,timer in ipairs(world.timers)do if timer.at<=stop and(not nextIndex or timer.at<world.timers[nextIndex].at)then nextIndex=i end end
        if not nextIndex then break end
        local timer=table.remove(world.timers,nextIndex);world.clock=timer.at;timer.fn()
    end
    world.clock=stop
end
local function receive(H,version,channel,name,sender)
    H.UpdateReminders:Receive(H.UpdateReminders.PREFIX,(name or "TestAddon").."\t"..version,channel or "GUILD",sender or "Peer-Realm")
end
-- Numeric release ordering is independent of development-version normalization elsewhere.
do
    local H=setup("1.2.3");local U=H.UpdateReminders
    eq(U.Compare("1.10.0","1.9.99"),1,"numeric minor ordering")
    eq(U.Compare("0.15.10","0.15.2"),1,"numeric patch ordering")
    eq(U.Compare("1.2.3","1.2.3"),0,"equal version")
    for _,version in ipairs({"1.2.3-dev1","1.2.3-alpha","1.2.3-beta.1","v1.2.3","1.2.3+dev","1.2","1.02.3","1.2.3 ","99999.2.3","|cffff00001.2.3","@project-version@"})do
        eq(U.Parse(version),nil,"invalid/non-stable packet: "..version)
    end
end
-- No participation, no cached reminder and no prefix/timer registration on test builds.
for _,version in ipairs({"1.2.3-dev1","1.2.3-alpha","1.2.3-beta.1","1.2.3+test","unknown"})do
    local saved={hammerCore={startupMessage=false,updateRelease={version="9.0.0",heardAt=1800000000}}}
    local H=setup(version,saved);receive(H,"9.9.9");advance(60)
    eq(#wow.printed,0,"non-stable local build stays silent: "..version)
    eq(#world.sends,0,"non-stable local build never announces: "..version)
    eq(world.registered,0,"non-stable local build never registers: "..version)
    eq(H.UpdateReminders.events,nil,"non-stable local build has no listener")
end
-- Incoming prereleases must not create/update cache or produce replies or notices.
do
    local H,saved=setup("1.2.3")
    for _,version in ipairs({"9.0.0-dev1","9.0.0-alpha","9.0.0-beta","9.0.0+test","9.0.0\tnoise"})do receive(H,version)end
    eq(#wow.printed,0,"incoming test versions produce no notice")
    eq(saved.hammerCore.updateRelease,nil,"incoming test versions never enter cache")
    eq(next(H.UpdateReminders.pending),nil,"incoming test versions produce no reply")
    receive(H,"1.3.0")
    eq(#wow.printed,0,"live update waits until login grace is over")
    advance(15)
    eq(wow.LastPrint(),"TestAddon: Version 1.3.0 is available (you have 1.2.3). Update on CurseForge.","one concise named update notice")
    receive(H,"1.4.0")
    eq(#wow.printed,1,"at most one notice per login")
    eq(saved.hammerCore.updateRelease.version,"1.4.0","newest stable version remembered")
    eq(saved.hammerCore.updateRelease.sender,nil,"no sender is stored")
    receive(H,"1.3.9")
    eq(saved.hammerCore.updateRelease.version,"1.4.0","older announcement cannot lower known release")
end
-- Cache survives login, expires, and is removed after updating or if invalid.
do
    local H,saved=setup("1.2.3");receive(H,"1.3.0")
    local persisted=saved
    H=setup("1.2.3",persisted);advance(15)
    eq(#wow.printed,1,"recent cached newer release reminds on next login")
    H=setup("1.3.0",persisted);advance(15)
    eq(#wow.printed,0,"updated addon has no reminder")
    eq(persisted.hammerCore.updateRelease,nil,"updated version clears old cache")
    for _,record in ipairs({{version="9.0.0-dev1",heardAt=1800000000},{version="9.0.0",heardAt=1799000000},{version="9.0.0",heardAt=1900000000},{version="9.0.0",heardAt="bad"}})do
        H,saved=setup("1.2.3",{hammerCore={startupMessage=false,updateRelease=record}});advance(15)
        eq(#wow.printed,0,"invalid/stale cache stays silent")
        eq(saved.hammerCore.updateRelease,nil,"invalid/stale cache removed")
    end
end
-- Real party/guild/instance routing; deferred sends respect departures and throttling.
do
    local H=setup("1.2.3");world.home,world.instance=true,true
    advance(15)
    eq(#world.sends,3,"announces to guild, home party and instance group")
    for _,packet in ipairs(world.sends)do eq(packet.payload,"TestAddon\t1.2.3","announces installed version only")end
    H.UpdateReminders:Broadcast();H.UpdateReminders:Broadcast();advance(10)
    eq(#world.sends,3,"repeated roster events are throttled")
    world.home,world.instance=false,false;advance(30)
    eq(#world.sends,4,"deferred send skips departed groups")
    world.home,world.raid=true,true;H.UpdateReminders:Broadcast();advance(3)
    eq(world.sends[#world.sends].channel,"RAID","home raid uses raid channel")
end
-- An older peer gets a stable reply; an equal/newer answer suppresses duplicates.
do
    local H=setup("1.3.0");advance(45);world.sends={};receive(H,"1.2.0")
    eq(H.UpdateReminders.pending.GUILD.reason,"reply","older peer schedules reply")
    receive(H,"1.3.0");advance(4)
    eq(#world.sends,0,"equal-version peer suppresses redundant reply")
    receive(H,"1.2.0");advance(4)
    eq(#world.sends,1,"older peer gets one reply")
    eq(world.sends[1].payload,"TestAddon\t1.3.0","reply sends actual installed stable release")
end
-- Filtering prevents unrelated, unsupported, self or malformed packets from notifying.
do
    local H,saved=setup("1.2.3")
    receive(H,"9.0.0","WHISPER");receive(H,"9.0.0","GUILD","OtherAddon")
    receive(H,"9.0.0","GUILD",nil,"Me-Realm")
    H.UpdateReminders:Receive("OtherPrefix","TestAddon\t9.0.0","GUILD","Peer-Realm")
    H.UpdateReminders:Receive(H.UpdateReminders.PREFIX,string.rep("x",90),"GUILD","Peer-Realm")
    world.guild=false;receive(H,"9.0.0");advance(20)
    eq(#wow.printed,0,"invalid packets cannot notify")
    eq(saved.hammerCore.updateRelease,nil,"invalid packets cannot be remembered")
    eq(#world.sends,0,"login send skips a departed guild")
end
-- The toggle cancels pending traffic/reminders, preserves cache, and is independent of startup chat.
do
    local H,saved=setup("1.2.3",{hammerCore={startupMessage=false,updateReminders=false,updateRelease={version="1.3.0",heardAt=1800000000}}})
    advance(20);receive(H,"1.3.0")
    eq(#wow.printed,0,"disabled reminder stays silent")
    eq(world.registered,0,"disabled setting never registers transport")
    H.UpdateReminders:SetEnabled(true);H.UpdateReminders:SetEnabled(false);advance(20)
    eq(#world.sends,0,"disable cancels deferred login traffic")
    eq(#wow.printed,0,"disable cancels cached login reminder")
    H.UpdateReminders:SetEnabled(true);advance(15)
    eq(#wow.printed,1,"enabling can show a cached update")
    H.UpdateReminders:SetEnabled(false);H.UpdateReminders:SetEnabled(true);advance(35)
    eq(#wow.printed,1,"toggle cycling cannot repeat notice in same login")
    H.Settings:Show("Visibility")
    eq(#H.Settings:Search("Update reminders")>0,true,"reminder setting is searchable")
end
-- Legacy transport and absent timers work, while missing network APIs fail quietly.
do
    local H=setup("1.2.3",nil,true,true);receive(H,"1.3.0")
    eq(#world.sends,1,"legacy/no-timer path announces once")
    eq(#wow.printed,1,"legacy path receives stable newer version")
    H=setup("1.2.3");C_ChatInfo=nil;RegisterAddonMessagePrefix,SendAddonMessage=nil,nil
    H.UpdateReminders:Apply();advance(20)
    eq(#world.sends,0,"missing APIs cancel pending sends")
    eq(H.UpdateReminders.enabled,false,"missing APIs disable participation")
end
-- Multiple private copies on one prefix filter their own addon names.
do
    local H=setup("1.2.3");local other,otherSaved=create("OtherAddon","2.0.0")
    receive(H,"1.3.0")
    other.UpdateReminders:Receive(other.UpdateReminders.PREFIX,"TestAddon\t1.3.0","GUILD","Peer-Realm")
    eq(otherSaved.hammerCore.updateRelease,nil,"other addon ignores unrelated version")
    other.UpdateReminders:Receive(other.UpdateReminders.PREFIX,"OtherAddon\t2.1.0","GUILD","Peer-Realm")
    eq(otherSaved.hammerCore.updateRelease.version,"2.1.0","other private copy handles its own version")
    advance(15)
    eq(#wow.printed,2,"private instances notify once each")
end
-- Roster churn cannot bypass login grace or keep rebroadcasting unrelated channels.
do
    local H=setup("1.2.3");world.home=true
    H.UpdateReminders.events.scripts.OnEvent(H.UpdateReminders.events,"GROUP_ROSTER_UPDATE")
    receive(H,"1.3.0");advance(6)
    eq(#world.sends,0,"early roster event cannot bypass login wait")
    eq(#wow.printed,0,"early announcement cannot bypass chat wait")
    advance(10)
    eq(#world.sends,2,"login announces once on each current channel")
    for i=1,20 do
        H.UpdateReminders.events.scripts.OnEvent(H.UpdateReminders.events,"GROUP_ROSTER_UPDATE")
        H.UpdateReminders.events.scripts.OnEvent(H.UpdateReminders.events,"PLAYER_GUILD_UPDATE")
    end
    advance(35)
    eq(#world.sends,2,"unchanged roster/rank events produce no extra announcements")
    world.homeCount=3
    H.UpdateReminders.events.scripts.OnEvent(H.UpdateReminders.events,"GROUP_ROSTER_UPDATE")
    eq(H.UpdateReminders.pending.GUILD,nil,"party change cannot rebroadcast to guild")
    advance(3)
    eq(#world.sends,3,"new party membership announces on its channel")
    eq(world.sends[3].channel,"PARTY","only changed party channel used")
end
-- Modern enum success/failure results and bounded recovery.
do
    local H=setup("1.2.3");local attempts=0
    H.UpdateReminders.send=function()attempts=attempts+1;return attempts==1 and 3 or 0 end
    advance(25)
    eq(attempts,2,"modern throttling result gets one bounded retry")
    eq(H.UpdateReminders.lastSent.GUILD~=nil,true,"only modern enum success records a send")
    H=setup("1.2.3");attempts=0
    H.UpdateReminders.send=function()attempts=attempts+1;return 9 end
    advance(120)
    eq(attempts,2,"persistent send error cannot loop forever")
    eq(H.UpdateReminders.lastSent.GUILD,nil,"failed enums cannot consume successful-send throttle")
    H=setup("1.2.3")
    C_ChatInfo.RegisterAddonMessagePrefix=function()return 2 end
    H.UpdateReminders:Apply();advance(20)
    eq(H.UpdateReminders.enabled,false,"invalid prefix result disables transport")
    eq(#world.sends,0,"rejected prefix cannot send")
    C_ChatInfo.RegisterAddonMessagePrefix=function()return 1 end
    H.UpdateReminders:Apply();advance(20)
    eq(H.UpdateReminders.enabled,true,"duplicate-prefix enum supports private copies")
    eq(#world.sends,1,"duplicate registration still announces")
end
-- Broadcast intent survives reply suppression; folder names and self realms are robust.
do
    local H=setup("1.3.0");advance(45);world.sends={}
    receive(H,"1.2.0");H.UpdateReminders:Broadcast();receive(H,"1.3.0");advance(4)
    eq(#world.sends,1,"equal peer cannot cancel a promoted broadcast")
    H=setup("1.2.3");UnitFullName=function()return "Me",""end
    receive(H,"9.0.0","GUILD",nil,"Me-Realm")
    eq(H.State().updateRelease,nil,"empty own realm uses normalized fallback")
    local other=create("My-Addon.Core","1.0.0")
    other.UpdateReminders:Receive(other.UpdateReminders.PREFIX,"My-Addon.Core\t1.1.0","GUILD","Peer-Realm")
    advance(15)
    eq(other.State().updateRelease.version,"1.1.0","exact addon identity supports punctuation")
end
-- Remembering a newer release never advertises it on behalf of another copy.
do
    local H=setup("1.2.3",{hammerCore={startupMessage=false,updateRelease={version="9.0.0",heardAt=1800000000}}})
    advance(15)
    eq(world.sends[1].payload,"TestAddon\t1.2.3","cached versions are never relayed")
    local database=H.spec.db;H.spec.db=function()return nil end
    receive(H,"10.0.0");advance(35)
    H.spec.db=database
    eq(H.State().updateRelease.version,"9.0.0","missing live state cannot replace remembered release")
end
io.write("Stable update reminders: "..checks.." checks passed\n")
