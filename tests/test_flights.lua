package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function near(actual, expected, label)
    if type(actual) ~= "number" or math.abs(actual - expected) > 0.01 then
        error(label .. ": expected about " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- A flight map: Booty Bay (slot 1, node 19) to Orgrimmar (slot 3, node 23)
-- through Grom'gol (slot 2, node 20).
local world
local function install(options)
    options = options or {}
    wow.Install({ TestAddon = { Version = "1.0.0" } })
    world = { clock = 100, taxi = false, hooks = {}, events = {}, frequentFlier = options.frequentFlier }
    GetTime = function() return world.clock end
    GetServerTime = function() return 5000 + world.clock end
    UnitOnTaxi = function() return world.taxi end
    hooksecurefunc = function(name, fn) world.hooks[name] = fn end
    TakeTaxiNode = function() end
    TaxiRequestEarlyLanding = function() end
    C_Timer = nil
    GetTaxiMapID = function() return 1414 end
    C_TaxiMap = { GetAllTaxiNodes = function()
        return { { slotIndex = 1, nodeID = 19 }, { slotIndex = 2, nodeID = 20 }, { slotIndex = 3, nodeID = 23 } }
    end }
    local names = { "Booty Bay", "Grom'gol", "Orgrimmar" }
    NumTaxiNodes = function() return 3 end
    TaxiNodeName = function(slot) return names[slot] end
    TaxiNodeGetType = function(slot) return slot == 1 and "CURRENT" or "REACHABLE" end
    GetNumRoutes = function(slot) return slot == 3 and 2 or 1 end
    TaxiGetNodeSlot = function(slot, hop, source)
        if slot == 3 then
            if hop == 1 then return source and 1 or 2 end
            return source and 2 or 3
        end
        return source and 1 or slot
    end
    C_Traits = { GetConfigIDByTreeID = function(tree) return tree == 1188 and 7 or nil end,
        GetNodeInfo = function(_, node) return node == 110300 and { activeRank = world.frequentFlier and 1 or 0 } or nil end }
    if options.library ~= false then
        LibTaxiData_API = {
            GetClientInfo = function() return { dataSet = "forever" } end,
            GetOutgoingPaths = function(node)
                if node == 19 then return { [1] = { toNodeID = 20, distanceYards = 304, delaySeconds = 0 } } end
                if node == 20 then return { [2] = { toNodeID = 23, distanceYards = 608, delaySeconds = 0 } } end
                return {}
            end,
        }
    else
        LibTaxiData_API = nil
    end
    local saved = options.saved or {}
    local ns = wow.LoadHammerCore("src", "TestAddon")
    local HC = ns.HammerCore
    local flights = options.flights
    if flights == nil then flights = true end
    HC:Init({ name = "TestAddon", command = "testaddon", db = function() return saved end, flights = flights })
    return HC, saved
end

local function fire(HC, event) HC.Flights.frame.scripts.OnEvent(HC.Flights.frame, event) end

-- Takes the flight to a slot and boards it.
local function takeOff(HC, slot)
    world.hooks.TakeTaxiNode(slot)
    world.taxi = true
    fire(HC, "PLAYER_CONTROL_LOST")
end

local function landAfter(HC, seconds)
    world.clock = world.clock + seconds
    world.taxi = false
    fire(HC, "PLAYER_CONTROL_GAINED")
end

-- Opt-in: an addon without `flights` hooks nothing.
do
    local HC = install({ flights = false })
    HC:Start()
    equal(HC.Flights.enabled, nil, "flights stay off without the spec flag")
    equal(world.hooks.TakeTaxiNode, nil, "no taxi hook without the spec flag")
end

-- Estimates from LibTaxiData: 912 yards over two legs at 30.4 yd/s.
do
    local HC = install()
    HC:Start()
    equal(HC.Flights.enabled, true, "HC:Start enables flights")
    local seconds, source, route = HC.Flights:Estimate(3)
    near(seconds, 30, "two legs at 30.4 yd/s")
    equal(source, "libtaxidata", "the estimate names its source")
    equal(route.from, "Booty Bay", "route start")
    equal(route.to, "Orgrimmar", "route destination")
    equal(route.key, "19>23", "routes are keyed by node IDs")
end

-- Frequent Flier flies 20% faster.
do
    local HC = install({ frequentFlier = true })
    HC:Start()
    near(HC.Flights:Estimate(3), 25, "Frequent Flier divides the time by 1.2")
end

-- Without LibTaxiData the time is unknown, but the flight still works.
do
    local HC = install({ library = false })
    HC:Start()
    local seconds, source = HC.Flights:Estimate(3)
    equal(seconds, nil, "no estimate without LibTaxiData")
    equal(source, "unknown", "unknown source")
    local took, landed
    HC.Flights:OnTakeoff(function(info) took = info end)
    HC.Flights:OnLanding(function(info) landed = info end)
    takeOff(HC, 3)
    equal(took.to, "Orgrimmar", "takeoff names the destination")
    equal(took.remaining, nil, "no countdown for an unknown route")
    landAfter(HC, 42)
    near(landed.elapsed, 42, "landing reports the flight time")
    equal(landed.learned, true, "the time is learned")
    near(HC.Flights:Estimate(3), 42, "the learned time is used next time")
    equal(select(2, HC.Flights:Estimate(3)), "learned", "learned source")
end

-- A full flight: takeoff, countdown, landing, learning.
do
    local HC, saved = install()
    HC:Start()
    local events = {}
    HC.Flights:OnTakeoff(function(info) events[#events + 1] = "takeoff:" .. info.source end)
    HC.Flights:OnLanding(function(info) events[#events + 1] = "landing" end)
    takeOff(HC, 3)
    equal(HC.Flights:Flying(), true, "on the flight")
    world.clock = world.clock + 10
    near(HC.Flights:Current().remaining, 20, "remaining counts down")
    landAfter(HC, 26)
    equal(table.concat(events, ","), "takeoff:libtaxidata,landing", "callbacks in order")
    equal(HC.Flights:Flying(), false, "landed")
    near(HC.Flights:Learned("19>23").seconds, 36, "real time learned")
    equal(saved.hammerCore.flights, ConsecratedHammerFlights, "the addon saves the shared table")
end

-- Learned times are stored at normal speed, so they serve both speeds.
do
    local HC = install({ frequentFlier = true })
    HC:Start()
    takeOff(HC, 3)
    landAfter(HC, 30)
    near(HC.Flights:Learned("19>23").seconds, 36, "stored at normal speed")
    near(HC.Flights:Estimate(3), 30, "read back at Frequent Flier speed")
    world.frequentFlier = false
    near(HC.Flights:Estimate(3), 36, "read back at normal speed")
end

-- Early landings and short hops aren't learned.
do
    local HC = install()
    HC:Start()
    takeOff(HC, 3)
    world.hooks.TaxiRequestEarlyLanding()
    local landed
    HC.Flights:OnLanding(function(info) landed = info end)
    landAfter(HC, 15)
    equal(landed.early, true, "early landing reported")
    equal(landed.learned, false, "early landing not learned")
    equal(HC.Flights:Learned("19>23"), nil, "nothing stored")
    takeOff(HC, 2)
    landAfter(HC, 5)
    equal(HC.Flights:Learned("19>20"), nil, "a 5 s hop isn't learned")
end

-- Takeoff without boarding expires.
do
    local HC = install()
    HC:Start()
    world.hooks.TakeTaxiNode(3)
    world.clock = world.clock + 11
    HC.Flights:Tick()
    world.taxi = true
    HC.Flights:Tick()
    equal(HC.Flights:Flying(), false, "a stale takeoff doesn't board")
end

-- A reload mid-flight: the flight is resumed with no route.
do
    local HC = install()
    HC:Start()
    local took
    HC.Flights:OnTakeoff(function(info) took = info end)
    world.taxi = true
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(took.resumed, true, "resumed flight")
    equal(took.seconds, nil, "no time for a resumed flight")
    local landed
    HC.Flights:OnLanding(function(info) landed = info end)
    landAfter(HC, 50)
    equal(landed.learned, false, "a resumed flight isn't learned")
end

-- Two addons share learned times, and each saves the merged set.
do
    local HC, saved = install({ saved = { hammerCore = { flights = { schema = 1, routes = {
        ["19>23"] = { seconds = 40, samples = 2, at = 10 }, ["1>2"] = { seconds = 60, samples = 1, at = 5 } } } } } })
    HC:Start()
    -- A second addon loads into the same session with its own saved copy.
    local otherSaved = { hammerCore = { flights = { schema = 1, routes = {
        ["19>23"] = { seconds = 35, samples = 1, at = 20 }, ["3>4"] = { seconds = 70, samples = 1, at = 5 } } } } }
    local other = wow.LoadHammerCore("src", "OtherAddon").HammerCore
    other:Init({ name = "OtherAddon", command = "otheraddon", db = function() return otherSaved end, flights = true })
    other:Start()
    equal(saved.hammerCore.flights, otherSaved.hammerCore.flights, "both addons save one table")
    near(HC.Flights:Learned("19>23").seconds, 35, "the more recent time wins")
    near(HC.Flights:Learned("1>2").seconds, 60, "first addon's route kept")
    near(HC.Flights:Learned("3>4").seconds, 70, "second addon's route kept")
end

-- Bad saved data is ignored, not trusted.
do
    local HC = install({ saved = { hammerCore = { flights = { routes = { ["19>23"] = { seconds = "fast" }, [4] = {} } } } } })
    HC:Start()
    equal(HC.Flights:Learned("19>23"), nil, "a bad entry is dropped")
    near(HC.Flights:Estimate(3), 30, "falls back to LibTaxiData")
end

-- Diagnostics.
do
    local HC = install()
    HC:Start()
    local report = HC.DiagnosticReport()
    assert(report:find("LibTaxiData: loaded (forever)", 1, true), "diagnostics name LibTaxiData")
    assert(report:find("Learned routes: 0", 1, true), "diagnostics count learned routes")
    takeOff(HC, 3)
    assert(HC.Flights:Report():find("Flying: Booty Bay to Orgrimmar, 30 s left (libtaxidata)", 1, true),
        "diagnostics show the flight")
end

-- Troubleshooting: LibTaxiData's status and a link to it.
do
    local HC = install({ library = false })
    HC:Start()
    HC.Settings:Show("Troubleshooting")
    local note = wow.FindText("LibTaxiData isn't installed: flight times are learned as you fly. Routes learned: 0.")
    assert(note, "Troubleshooting says LibTaxiData is missing")
    local get = wow.FindButton("Get LibTaxiData")
    assert(get, "a Get LibTaxiData button")
    get.scripts.OnClick(get)
    assert(HC.Dialog:IsShown(), "the link dialog opens")
    assert(wow.FindText("Press Ctrl+C to copy, then paste it into your browser."), "it's the copy-link dialog")
end
do
    local HC = install({ flights = false })
    HC:Start()
    HC.Settings:Show("Troubleshooting")
    assert(not wow.FindButton("Get LibTaxiData"), "no flight section without flights")
end

-- Takeoff and landing only: no estimates, nothing learned or saved, but
-- the callbacks and Current() still work.
do
    local HC, saved = install({ flights = { estimates = false } })
    HC:Start()
    equal(HC.Flights.enabled, true, "a flights table enables flights")
    equal(HC.Flights.Estimates(), false, "estimates are off")
    equal(saved.hammerCore and saved.hammerCore.flights, nil, "nothing saved at start")
    local paths = LibTaxiData_API.GetOutgoingPaths
    local looked = 0
    LibTaxiData_API.GetOutgoingPaths = function(...) looked = looked + 1; return paths(...) end
    local seconds, source = HC.Flights:Estimate(3)
    equal(seconds, nil, "no estimate")
    equal(source, "unknown", "unknown source")
    local took, landed
    HC.Flights:OnTakeoff(function(info) took = info end)
    HC.Flights:OnLanding(function(info) landed = info end)
    takeOff(HC, 3)
    equal(took ~= nil, true, "takeoff still fires")
    equal(took.to, "Orgrimmar", "takeoff still names the destination")
    equal(took.remaining, nil, "no countdown")
    equal(HC.Flights:Current().to, "Orgrimmar", "Current still works")
    equal(looked, 0, "LibTaxiData is never asked")
    assert(HC.Flights:Report():find("Flights: on (no estimates)", 1, true), "diagnostics say no estimates")
    landAfter(HC, 42)
    near(landed.elapsed, 42, "landing still fires with the time flown")
    equal(landed.learned, false, "nothing is learned")
    equal(saved.hammerCore.flights, nil, "nothing is saved")
    HC.Settings:Show("Troubleshooting")
    assert(not wow.FindButton("Get LibTaxiData"), "no LibTaxiData section without estimates")
end
do
    local HC = install({ flights = {} })
    HC:Start()
    equal(HC.Flights.Estimates(), true, "a table without estimates = false keeps estimates")
    near(HC.Flights:Estimate(3), 30, "and uses LibTaxiData")
end

-- Dialogue taxis have no TakeTaxiNode call and their taxi flag can arrive late.
for _, estimates in ipairs({ true, false }) do
    local HC = install({ flights = estimates and true or { estimates = false } })
    local poll, took, landed, count = {}, nil, nil, 0
    C_Timer = { NewTicker = function(_, fn)
        poll.tick = fn
        return { Cancel = function() poll.cancelled = true end }
    end }
    HC:Start()
    HC.Flights:OnTakeoff(function(info) took = info; count = count + 1 end)
    HC.Flights:OnLanding(function(info) landed = info end)
    fire(HC, "PLAYER_CONTROL_LOST")
    equal(took, nil, "control loss alone cannot start a flight")
    equal(type(poll.tick), "function", "dialogue takeoff starts bounded polling")
    world.taxi = true
    world.clock = world.clock + 0.5
    poll.tick()
    equal(took ~= nil, true, "delayed taxi state confirms a dialogue flight")
    equal(took.resumed, nil, "a dialogue takeoff is new, not a reload")
    equal(took.seconds, nil, "no invented estimate")
    equal(took.key, nil, "no invented route")
    poll.tick()
    equal(count, 1, "takeoff emits once")
    landAfter(HC, 42)
    equal(landed.learned, false, "unmapped flights cannot pollute learned routes")
    equal(poll.cancelled, true, "landing stops polling")
end

-- Stuns or rejected flights must not produce offers or an endless ticker.
do
    local HC = install()
    local poll, count = {}, 0
    C_Timer = { NewTicker = function(_, fn)
        poll.tick = fn
        return { Cancel = function() poll.cancelled = true end }
    end }
    HC:Start()
    HC.Flights:OnTakeoff(function() count = count + 1 end)
    fire(HC, "PLAYER_CONTROL_LOST")
    fire(HC, "PLAYER_CONTROL_GAINED")
    world.clock = world.clock + HC.Flights.BOARD_WAIT + 1
    poll.tick()
    equal(count, 0, "control loss without taxi state is not a flight")
    equal(poll.cancelled, true, "the confirmation window expires")
    world.taxi = true
    HC.Flights:Tick()
    equal(count, 0, "expired observations cannot start a flight")
end

-- An expired map request must not name a later dialogue flight.
do
    local HC = install()
    HC:Start()
    world.hooks.TakeTaxiNode(3)
    world.clock = world.clock + HC.Flights.BOARD_WAIT + 1
    world.taxi = true
    fire(HC, "PLAYER_CONTROL_LOST")
    equal(HC.Flights:Current().key, nil, "expired route metadata is discarded")
    equal(HC.Flights:Current().resumed, nil, "the new confirmed takeoff still starts")
end

-- The fallback catches a takeoff with no hook and no control-loss event, but
-- only once the world has loaded, and never re-offers a resumed flight.
do
    local HC = install()
    local took, count = nil, 0
    HC:Start()
    HC.Flights:OnTakeoff(function(info) took = info; count = count + 1 end)
    local frame = HC.Flights.frame
    equal(frame.scripts.OnUpdate, nil, "no fallback before the world loads")
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(type(frame.scripts.OnUpdate), "function", "fallback starts after world entry")
    world.taxi = true
    frame.scripts.OnUpdate(frame, 1)
    equal(count, 0, "the fallback is throttled")
    frame.scripts.OnUpdate(frame, 1.1)
    equal(count, 1, "a silent takeoff is caught")
    equal(took.resumed, nil, "and treated as new")
    equal(took.key, nil, "with no invented route")
    frame.scripts.OnUpdate(frame, 2.1)
    equal(count, 1, "once")
    landAfter(HC, 30)
end
do
    local HC = install()
    local took, count = nil, 0
    HC:Start()
    HC.Flights:OnTakeoff(function(info) took = info; count = count + 1 end)
    world.taxi = true
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(count, 1, "a reload mid-flight resumes")
    equal(took.resumed, true, "marked resumed")
    HC.Flights.frame.scripts.OnUpdate(HC.Flights.frame, 5)
    equal(count, 1, "the fallback doesn't offer it again")
end

io.write("test_flights: ok\n")
