--[[
  DimMA Preheater  –  grandMA3 Plugin  (Lampen vorglühen seit 2026)
  --------------------------------------------------------------
  Erstellt einen eigenen Dimmer-Fixture-Type (8 bit oder 16 bit) mit
  einstellbarem Preheat und Limit, komplett ohne Vorlage.

    Preheat = DMX-Ausgabe bei 0 %
    Limit   = DMX-Ausgabe bei 100 %

  Funktionsweise:
    1. Das Plugin schreibt eine grandMA3-Fixture-Type-Datei (.xml) in die
       User-Fixture-Library.
    2. Diese Datei wird in ShowData.Patch.FixtureTypes mit
       Import <Nr> /File "..." /Path "..." auf die nächste freie Nummer
       importiert (Fallback: Lua-Import über Acquire():Import()).

  Der DMX-Kanal enthält einen LogicalChannel "Dimmer":
      "Dimmer"     Preheat .. Limit  (hier läuft der Dimmer 0..100 %)
      "Over Limit" Limit+1 .. Max    (NoFeature, nur wenn Limit < 100)

  Aufruf:
    Plugin "DimMA Preheater"             -> Dialog
    Plugin "DimMA Preheater" "16,5,90"   -> ohne Dialog (Bit, Preheat %, Limit %)

  Name wird automatisch vergeben, z. B. "Dimmer 16bit PH5 L90".
]]

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

local TITLE = "DimMA Preheater"

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function log(fmt, ...) Printf("[" .. TITLE .. "] " .. fmt, ...) end
local function err(fmt, ...) ErrPrintf("[" .. TITLE .. "] " .. fmt, ...) end

local function round(x) return math.floor(x + 0.5) end

local function fmtNum(x)
  -- 5 -> "5", 2.5 -> "2.5"
  return (string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", ""))
end

-- Prozent -> DMX-Wert in der gewählten Auflösung
local function percentToDmx(pct, bits)
  local max = (bits == 16) and 65535 or 255
  return round(pct / 100 * max)
end

-- DMX-Wert (8/16 bit) -> grandMA3-Format (24 bit Hex, z. B. 8 bit 0x38 = "383838")
local function dmxToHex(value, bits)
  local v24
  if bits == 16 then
    v24 = round(value * 16777215 / 65535)
  else
    v24 = value * 65793 -- 0x010101
  end
  if v24 > 16777215 then v24 = 16777215 end
  return string.format("%06X", v24)
end

local function randomGuid()
  math.randomseed(os.time() + math.floor((os.clock() * 100000) % 100000))
  local parts = {}
  for i = 1, 16 do parts[i] = string.format("%02X", math.random(0, 255)) end
  return table.concat(parts, " ")
end

local function trimSlash(p)
  return (tostring(p):gsub("[/\\]+$", ""))
end

---------------------------------------------------------------------------
-- Fixture-Type-XML erzeugen
---------------------------------------------------------------------------

local function buildXml(name, bits, preheatPct, limitPct)
  local maxDmx     = (bits == 16) and 65535 or 255
  local preheatDmx = percentToDmx(preheatPct, bits)
  local limitDmx   = percentToDmx(limitPct, bits)

  local preheatHex = dmxToHex(preheatDmx, bits)
  local limitHex   = dmxToHex(limitDmx, bits)

  -- Ein LogicalChannel. "Dimmer" ist die ERSTE ChannelFunction und startet
  -- direkt beim Preheat-Wert (kein extra Bereich darunter), damit die
  -- Encoder-Bar nur den Wert zeigt (z. B. "50") statt "2:50".
  -- Über dem Limit folgt nur bei Bedarf ein Reserve-Bereich (NoFeature).
  local ind = "                        "
  local cfInd = ind .. "    "

  local cfXml = ind .. '<LogicalChannel Attribute="Dimmer" Master="Grand">\n'
  cfXml = cfXml .. cfInd .. string.format(
    '<ChannelFunction Name="Dimmer" Attribute="Dimmer"%s Default="%s"/>\n',
    (preheatDmx > 0) and (' DMXFrom="' .. preheatHex .. '"') or "",
    preheatHex)
  if limitDmx < maxDmx then
    local highHex = dmxToHex(limitDmx + 1, bits)
    cfXml = cfXml .. cfInd .. string.format(
      '<ChannelFunction Name="Over Limit" Attribute="NoFeature" DMXFrom="%s" Default="%s"/>\n',
      highHex, highHex)
  end
  cfXml = cfXml .. ind .. '</LogicalChannel>\n'

  local channelOffsets = (bits == 16) and 'Coarse="1" Fine="2"' or 'Coarse="1"'

  local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<GMA3 DataVersion="2.3.2.0">
    <FixtureType Name="%NAME%" Guid="%GUID%" ShortName="%SHORT%" LongName="%NAME%" Description="Created by DimMA Preheater: %BITS% bit, Preheat %PH% %%, Limit %LIM% %%" Manufacturer="Generic" Universal="No">
        <AttributeDefinitions>
            <DeactivationGroups/>
            <ActivationGroups/>
            <FeatureGroups>
                <FeatureGroup Name="Dimmer">
                    <Feature Name="Dimmer"/>
                </FeatureGroup>
                <FeatureGroup Name="Control">
                    <Feature Name="Control"/>
                </FeatureGroup>
            </FeatureGroups>
            <Attributes>
                <Attribute Name="Dimmer" Pretty="Dim" Feature="Dimmer.Dimmer" Special="Dimmer" SpecialIndex="0" PhysicalUnit="LuminousIntensity" Color="0.0000000000,0.0000000000,0.0000000000,1.0000000000" NaturalReadout="Percent" EncoderResolution="Coarse"/>
                <Attribute Name="NoFeature" Pretty="NoFeature" Feature="Control.Control" Color="0.0000000000,0.0000000000,0.0000000000,1.0000000000" NaturalReadout="Percent" EncoderResolution="Coarse"/>
            </Attributes>
        </AttributeDefinitions>
        <Wheels/>
        <PhysicalDescriptions>
            <Emitters/>
            <CRIs/>
            <FTFilters/>
            <Connectors/>
            <PhysicalProperties>
                <PhysicalPropertiesData/>
            </PhysicalProperties>
            <ColorSpaceCollect/>
            <GamutCollect/>
        </PhysicalDescriptions>
        <Models/>
        <Geometries>
            <Geometry Name="Base" GridAuto="Auto">
                <Beam Name="Beam" GridAuto="Auto" GridX="0" GridY="0" GridZ="0" BeamRadius="0.050" BeamType="Wash"/>
            </Geometry>
        </Geometries>
        <DMXModes>
            <DMXMode Name="%BITS% bit" Geometry="Base" XYZ="No" DiveInto="Yes">
                <DMXChannels>
                    <DMXChannel %OFFSETS% DefaultChannelFunction="Dimmer.Dimmer" Highlight="%LIMHEX%" Lowlight="%PHHEX%" Geometry="Base">
%FUNCTIONS%                    </DMXChannel>
                </DMXChannels>
                <Relations/>
                <FTMacros/>
                <SoftwareVersions/>
                <FTPresets/>
            </DMXMode>
        </DMXModes>
        <Revisions>
            <Revision Text="Created by DimMA Preheater" Date="%DATE%" UserID="0"/>
        </Revisions>
        <Protocols>
            <RDMFixtureType>
                <Parameters/>
                <Notifications>
                    <RDMAbsentNotification/>
                </Notifications>
                <FTRDMPersonalityCollect/>
            </RDMFixtureType>
        </Protocols>
    </FixtureType>
</GMA3>
]]

  local repl = {
    NAME      = name,
    SHORT     = string.format("Dim%d", bits),
    GUID      = randomGuid(),
    BITS      = tostring(bits),
    PH        = fmtNum(preheatPct),
    LIM       = fmtNum(limitPct),
    OFFSETS   = channelOffsets,
    LIMHEX    = limitHex,
    PHHEX     = preheatHex,
    FUNCTIONS = cfXml,
    DATE      = os.date("%d.%m.%Y %H:%M:%S"),
  }
  xml = xml:gsub("%%(%u+)%%", function(key) return repl[key] or ("%" .. key .. "%") end)
  xml = xml:gsub("%%%%", "%%")

  log("%d bit: Preheat %s %% = DMX %d (%s), Limit %s %% = DMX %d (%s)",
      bits, fmtNum(preheatPct), preheatDmx, preheatHex,
      fmtNum(limitPct), limitDmx, limitHex)
  return xml
end

---------------------------------------------------------------------------
-- Pfad zur Fixture-Type-Library finden
---------------------------------------------------------------------------

local function tryGetPath(v)
  local ok, p = pcall(GetPath, v)
  if ok and type(p) == "string" and p ~= "" then return trimSlash(p) end
  return nil
end

local function findFixtureTypeLibraryPath()
  if Enums and Enums.PathType then
    -- 1) Die User-Fixture-Library (gma3_library/fixturetypes)
    if Enums.PathType.UserFixtures then
      local p = tryGetPath(Enums.PathType.UserFixtures)
      if p then return p end
    end
    -- 2) Irgendein Eintrag mit "user" + "fixture" im Namen
    for k, v in pairs(Enums.PathType) do
      local key = tostring(k):lower()
      if key:find("user", 1, true) and key:find("fixture", 1, true)
         and not key:find("resource", 1, true) then
        local p = tryGetPath(v)
        if p then return p end
      end
    end
    -- 3) Temp-Ordner
    for k, v in pairs(Enums.PathType) do
      if tostring(k):lower() == "temp" then
        local p = tryGetPath(v)
        if p then return p end
      end
    end
  end
  return tryGetPath("temp")
end

-- Command-Line-Ziel auf ShowData.Patch.FixtureTypes setzen
-- (immer nur eine Ebene pro ChangeDestination, sonst landet man woanders)
local function gotoPatchFixtureTypes()
  Cmd('ChangeDestination Root')
  Cmd('ChangeDestination "ShowData"')
  Cmd('ChangeDestination "Patch"')
  Cmd('ChangeDestination "FixtureTypes"')
end

local function gotoRoot()
  Cmd('ChangeDestination Root')
end

local function nextFixtureTypeNumber()
  local maxNo = 0
  for _, ft in ipairs(Patch().FixtureTypes:Children()) do
    local ok, no = pcall(function() return ft.no end)
    no = ok and tonumber(no) or nil
    if no and no > maxNo then maxNo = no end
  end
  if maxNo == 0 then maxNo = Patch().FixtureTypes:Count() end
  return maxNo + 1
end

local function writeFile(path, content)
  local f, e = io.open(path, "w")
  if not f then return false, e end
  f:write(content)
  f:close()
  return true
end

---------------------------------------------------------------------------
-- Fixture-Type anlegen
---------------------------------------------------------------------------

local function findFixtureTypeByName(name)
  for _, ft in ipairs(Patch().FixtureTypes:Children()) do
    if ft.name == name then return ft end
  end
  return nil
end

local function createDimmerFixture(bits, preheatPct, limitPct)
  local name = string.format("Dimmer %dbit PH%s L%s", bits, fmtNum(preheatPct), fmtNum(limitPct))

  if findFixtureTypeByName(name) then
    log("Fixture-Type '%s' gibt es schon – du kannst ihn direkt patchen.", name)
    return true
  end

  local libPath = findFixtureTypeLibraryPath()
  if not libPath then
    err("Pfad zur Fixture-Type-Library nicht gefunden.")
    return false
  end

  local baseName = string.format("DimMA@Dimmer %dbit PH%s L%s@v1",
                                 bits, fmtNum(preheatPct), fmtNum(limitPct))
  local fullPath = libPath .. "/" .. baseName .. ".xml"

  local ok, e = writeFile(fullPath, buildXml(name, bits, preheatPct, limitPct))
  if not ok then
    err("Datei konnte nicht geschrieben werden (%s): %s", fullPath, tostring(e))
    return false
  end
  log("Fixture-Type-Datei geschrieben: %s", fullPath)

  if libPath:find('"', 1, true) then
    err("Pfad enthält ein Anführungszeichen, Import nicht möglich: %s", libPath)
    return false
  end

  local fileName = baseName .. ".xml"
  local target   = nextFixtureTypeNumber()

  -- Versuch 1: Import-Befehl direkt in ShowData.Patch.FixtureTypes
  gotoPatchFixtureTypes()
  local okCmd, cmdErr = pcall(Cmd, string.format('Import %d /File "%s" /Path "%s"',
                                                 target, fileName, libPath))
  gotoRoot()
  if not okCmd then err("Import-Befehl fehlgeschlagen: %s", tostring(cmdErr)) end

  if findFixtureTypeByName(name) then
    log("Fertig! Fixture-Type '%s' angelegt (Nr. %d). Jetzt einfach patchen.", name, target)
    return true
  end

  -- Versuch 2: Lua-Import in einen neuen Fixture-Type-Platz
  log("Import-Befehl hat nicht geklappt, versuche Lua-Import ...")
  local fts = Patch().FixtureTypes
  local okAcq, newFt = pcall(function()
    if fts.Acquire then return fts:Acquire() end
    return fts:Aquire()
  end)
  if okAcq and newFt then
    local okImp, imported = pcall(newFt.Import, newFt, libPath .. "/", fileName)
    if okImp and imported and findFixtureTypeByName(name) then
      log("Fertig! Fixture-Type '%s' angelegt. Jetzt einfach patchen.", name)
      return true
    end
    -- leeren Platz wieder aufräumen (nur wenn er eindeutig unser leerer ist)
    pcall(function()
      local n = newFt.name
      if n ~= nil and n ~= "" and n ~= name then return end
      for i, c in ipairs(fts:Children()) do
        if c == newFt then fts:Delete(i) return end
      end
    end)
  end

  err("Automatischer Import hat nicht geklappt. Die Datei liegt hier:")
  err("%s", fullPath)
  err("Patch > Fixture Types > Import > User-Library > '%s' auswählen.", baseName)
  return false
end

---------------------------------------------------------------------------
-- Eingabe
---------------------------------------------------------------------------

local function validate(bits, preheat, limit)
  if bits ~= 8 and bits ~= 16 then return "Auflösung muss 8 oder 16 bit sein." end
  if not preheat or preheat < 0 or preheat > 100 then return "Preheat muss zwischen 0 und 100 % liegen." end
  if not limit or limit < 0 or limit > 100 then return "Limit muss zwischen 0 und 100 % liegen." end
  if percentToDmx(preheat, bits) >= percentToDmx(limit, bits) then
    return "Preheat muss kleiner als das Limit sein."
  end
  return nil
end

local function parseArgument(argument)
  local parts = {}
  for p in tostring(argument):gmatch("[^,]+") do
    parts[#parts + 1] = p:match("^%s*(.-)%s*$")
  end
  return tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
end

local function askUser()
  local res = MessageBox({
    title = TITLE,
    message = "Neuen Dimmer-Fixture-Type erstellen.\n" ..
              "Preheat = Ausgabe bei 0 %, Limit = Ausgabe bei 100 %.",
    commands = {
      { value = 1, name = "Erstellen" },
      { value = 0, name = "Abbrechen" },
    },
    inputs = {
      { name = "Preheat %", value = "5", whiteFilter = "0123456789.",
        maxTextLength = 6, vkPlugin = "NumericInput" },
      { name = "Limit %", value = "100", whiteFilter = "0123456789.",
        maxTextLength = 6, vkPlugin = "NumericInput" },
    },
    selectors = {
      { name = "Auflösung", selectedValue = 8, type = 1,
        values = { ["8 bit"] = 8, ["16 bit"] = 16 } },
    },
  })

  if not res or not res.success or res.result ~= 1 then return nil end

  return tonumber(res.selectors["Auflösung"]),
         tonumber(res.inputs["Preheat %"]),
         tonumber(res.inputs["Limit %"])
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

local function Main(displayHandle, argument)
  local bits, preheat, limit

  if argument and argument ~= "" then
    bits, preheat, limit = parseArgument(argument)
  else
    bits, preheat, limit = askUser()
    if bits == nil then log("Abgebrochen.") return end
  end

  local problem = validate(bits, preheat, limit)
  if problem then
    err(problem)
    MessageBox({ title = TITLE, message = problem,
                 commands = { { value = 1, name = "OK" } } })
    return
  end

  local ok, result = pcall(createDimmerFixture, bits, preheat, limit)
  if not ok then
    err("Fehler: %s", tostring(result))
  end
end

return Main
