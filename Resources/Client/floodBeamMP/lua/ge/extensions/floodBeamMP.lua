local M = {}

local allWater = {}
local ocean = nil
local calledOnInit = false -- For calling "E_OnInitialize" only once when BeamMP's experimental "Disable lua reloading when bla bla bla" is enabled

local function findObject(objectName, className)
    local obj = scenetree.findObject(objectName)
    if obj then return obj end
    if not className then return nil end

    local objects = scenetree.findClassObjects(className)
    for _, name in pairs(objects) do
        local object = scenetree.findObject(name)
        if string.find(name, objectName) then return object end
    end

    return
end

local function tableToMatrix(tbl)
    local mat = MatrixF(true)
    mat:setColumn(0, tbl.c0)
    mat:setColumn(1, tbl.c1)
    mat:setColumn(2, tbl.c2)
    mat:setColumn(3, tbl.c3)
    return mat
end


--[[         this function comes from spawn.lua in beamng's lua folder. I need this to pick a valid spawn point but not spawn the default vehicle.
pickSpawnPoint s responsible for finding a valid spawn point for a player and camera
@param spawnName string represent player or camera spawn point
]]
local function pickSpawnPoint(spawnName)
	local playerSP,spawnPointName
	local defaultSpawnPoint = setSpawnpoint.loadDefaultSpawnpoint()
	local spawnDefaultGroups = {"CameraSpawnPoints", "PlayerSpawnPoints", "PlayerDropPoints"}
	if defaultSpawnPoint then
		local spawnPoint = scenetree.findObject(defaultSpawnPoint)
		if spawnPoint then
		    return spawnPoint
		else
		    log('W', logTag, 'No SpawnPointName in mission file vehicle spawn in the default position')
		end
	end

    --Override for FloodEscapeCrater (for now):
    local floodSpawn = scenetree.findObject("Spawn_CraterBottom")
    if floodSpawn then
        return scenetree.findObjectById(floodSpawn.obj:getId())
    end

	--Walk through the groups until we find a valid object
	for i,v in pairs(spawnDefaultGroups) do
		if scenetree.findObject(spawnDefaultGroups[i]) then
		    local spawngroupPoint = scenetree.findObject(spawnDefaultGroups[i]):getRandom()
		    if not spawngroupPoint then
			    break
		    end
		    local sgPpointID = scenetree.findObjectById(spawngroupPoint:getId())
		    if not sgPpointID then
			    break
		    end
		    return sgPpointID
		end
	end

	--[[ ensuring backward compability with mods
	]]
	local dps = scenetree.findObject("DefaultPlayerSpawnSphere")
	if dps then
		return scenetree.findObjectById(dps.obj:getId())
	end

	--[[Didn't find a spawn point by looking for the groups so let's return the
	 "default" SpawnSphere First create it if it doesn't already exist
	]]
	playerSP = createObject('SpawnSphere')
	if not playerSP then
		log('E', logTag, 'could not create playerSP')
		return
	end
	playerSP.dataBlock = scenetree.findObject('SpawnSphereMarker')
	if spawnName == "player" then
		playerSP.spawnClass = "BeamNGVehicle"
		playerSP.spawnDatablock = "default_vehicle"
		spawnPointName = "DefaultPlayerSpawnSphere"
		playerSP:registerObject(spawnPointName)
	elseif spawnName == 'camera' then
		playerSP.spawnClass = "Camera"
		playerSP.spawnDatablock = "Observer"
		spawnPointName = "DefaultCameraSpawnSphere"
		playerSP:registerObject(spawnPointName)
	end
	local missionCleanup = scenetree.MissionCleanup
	if not missionCleanup then
		log('E', logTag, 'MissionCleanup does not exist')
		return
	end
	--[[ Add it to the MissionCleanup group so that it doesn't get saved
		to the Mission (and gets cleaned up of course)
	]]
	missionCleanup:addObject(playerSP.obj)
	return playerSP
end

--[[
   Got this from funstuff.lua, as it wasn't exposed to other modules 
--]]
local function randomizeColors()
  local veh = getPlayerVehicle(0)
  if not veh then return end
  local modelInfo = core_vehicles.getModel(veh.JBeam)
  if not modelInfo then return end
  local paints = tableKeys(tableValuesAsLookupDict(modelInfo.model.paints or {}))
  local paint1, paint2, paint3 = paints[math.random(1, #paints)], paints[math.random(1, #paints)], paints[math.random(1, #paints)]
  local paintData = {
    createVehiclePaint({x=paint1.baseColor[1], y=paint1.baseColor[2], z=paint1.baseColor[3], w=paint1.baseColor[4]}, {paint1.metallic, paint1.roughness, paint1.clearcoat, paint1.clearcoatRoughness}),
    createVehiclePaint({x=paint2.baseColor[1], y=paint2.baseColor[2], z=paint2.baseColor[3], w=paint2.baseColor[4]}, {paint2.metallic, paint2.roughness, paint2.clearcoat, paint2.clearcoatRoughness}),
    createVehiclePaint({x=paint3.baseColor[1], y=paint3.baseColor[2], z=paint3.baseColor[3], w=paint3.baseColor[4]}, {paint3.metallic, paint3.roughness, paint3.clearcoat, paint3.clearcoatRoughness})}
  veh.color = ColorF(paintData[1].baseColor[1], paintData[1].baseColor[2], paintData[1].baseColor[3], paintData[1].baseColor[4]):asLinear4F()
  veh.colorPalette0 = ColorF(paintData[2].baseColor[1], paintData[2].baseColor[2], paintData[2].baseColor[3], paintData[2].baseColor[4]):asLinear4F()
  veh.colorPalette1 = ColorF(paintData[3].baseColor[1], paintData[3].baseColor[2], paintData[3].baseColor[3], paintData[3].baseColor[4]):asLinear4F()
  veh:setMetallicPaintData(paintData)
  return {"reload"}
end

local hiddenWater = {}

local function getWaterLevel()
    if not ocean then return nil end
    return ocean.position:getColumn(3).z
end

local function getAllWater()
    local water = {}
    local toSearch = {
        "River",
        "WaterBlock"
    }

    for _, name in pairs(toSearch) do
        local objects = scenetree.findClassObjects(name)
        for _, id in pairs(objects) do
            if not tonumber(id) then
                local source = scenetree.findObject(id)
                if source then
                    table.insert(water, source)
                end
            else
                local source = scenetree.findObjectById(tonumber(id))
                if source then
                    table.insert(water, source)
                end
            end
        end
    end

    return water
end

local function handleWaterSources()
    local height = getWaterLevel()

    for id, water in pairs(allWater) do
        local waterHeight = water.position:getColumn(3).z
        if M.hideCoveredWater and not hiddenWater[id] and waterHeight < height then
            water.isRenderEnabled = false
            hiddenWater[id] = true
        elseif waterHeight > height and hiddenWater[id] then
            water.isRenderEnabled = true
            hiddenWater[id] = false
        elseif not M.hideCoveredWater and hiddenWater[id] then
            water.isRenderEnabled = true
            hiddenWater[id] = false
        end
    end
end

AddEventHandler("E_TeleportToDefaultSpawn", function()
    local spawnPoint = pickSpawnPoint('player')
	if not spawnPoint then return end
	for vehID, vehData in pairs(MPVehicleGE.getOwnMap()) do
		local veh = be:getObjectByID(vehID)
		if not veh then return end
		local spawnPos = spawnPoint:getPosition()
		local spawnQuat = quat(spawnPoint:getRotation()) * quat(0,0,1,0)
		spawnPos.x = spawnPos.x + math.random(-10,10)
		spawnPos.y = spawnPos.y + math.random(-10,10)
		spawnPos.z = spawnPos.z + math.random(1,10)
		spawn.safeTeleport(veh, spawnPos, spawnQuat)
		-- veh:setPositionRotation(spawnPos.x + rand(-10,10), spawnPos.y + rand(-10,10), spawnPos.z + rand(1,10), spawnQuat.x, spawnQuat.y, spawnQuat.z, spawnQuat.w) -- random offset to make it less likely to spawn inside of each other
		veh:queueLuaCommand("recovery.recoverInPlace()")
	end
end)

--[[
   Got this from funstuff.lua randomVehicle(), as it wasn't exposed to other modules 
--]]
local vehicleOptions = nil
AddEventHandler("E_SpawnRandomVehicle", function()
  local vehs =  core_vehicles.getVehicleList().vehicles
  if not vehicleOptions then
    vehicleOptions = {}
    for _, v in ipairs(vehs) do
      local passType = true
      passType = passType and (v.model.Type == 'Car' or v.model.Type == 'Truck') and v.model['Body Style'] ~= 'Bus' and v.model['isAuxiliary'] ~= true -- always only use cars or trucks
      if passType then
        local model = {
          model = v.model.key,
          configs = {},
          paints = tableKeys(tableValuesAsLookupDict(v.model.paints or {}))
        }
        for _, c in pairs(v.configs) do
          local passConfig = true
          passConfig = passConfig and c["Top Speed"] and c["Top Speed"] > 19 and c['isAuxiliary'] ~= true -- always have some minimum speed
          if passConfig then
            table.insert(model.configs, {
              config = c.key,
              name = c.Name,
            })
          end
        end
        if #model.configs > 0 then
          table.insert(vehicleOptions, model)
        end
      end
    end
  end
  local model = vehicleOptions[math.random(1, #vehicleOptions)]
  local config = model.configs[math.random(1, #model.configs)]
  local options = {config = config}
  local spawningOptions = sanitizeVehicleSpawnOptions(model.model, options)
  if be:getPlayerVehicle(0) then
    core_vehicles.replaceVehicle(spawningOptions.model, spawningOptions.config)
  else
    core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions.config)
  end
  randomizeColors()
end)

AddEventHandler("E_OnPlayerLoaded", function()
    allWater = getAllWater()
    ocean = findObject("Ocean", "WaterPlane")

    if calledOnInit then return end
    TriggerServerEvent("E_OnInitiliaze", tostring(getWaterLevel()))
    calledOnInit = true
end)

AddEventHandler("E_SetWaterLevel", function(level)
    level = tonumber(level) or nil
    if not level then log("W", "setWaterLevel", "level is nil") return end
    if not ocean then log("W", "setWaterLevel", "ocean is nil") return end
    local c3 = ocean.position:getColumn(3)
    ocean.position = tableToMatrix({
        c0 = ocean.position:getColumn(0),
        c1 = ocean.position:getColumn(1),
        c2 = ocean.position:getColumn(2),
        c3 = vec3(c3.x, c3.y, level)
    })

    handleWaterSources() -- Hides/Shows water sources depending on the ocean level
    -- print("Water level set to " .. tostring(level) .. " meters, player vehicle z: " .. tostring(getPlayerVehicle(0) and getPlayerVehicle(0):getPosition() and getPlayerVehicle(0):getPosition().z or "N/A"))
    if getPlayerVehicle(0) and getPlayerVehicle(0):getPosition() and level > getPlayerVehicle(0):getPosition().z then
        TriggerServerEvent("E_OnPlayerUnderWater", "")
    end
end)

AddEventHandler("E_SetRainVolume", function(volume)
    local volume = tonumber(volume) or 0
    if not volume then
        log("W", "E_SetRainVolume", "Invalid data: " .. tostring(data))
        return
    end

    local rainObj = findObject("rain_coverage", "Precipitation")
    if not rainObj then
        log("W", "E_SetRainVolume", "rain_coverage not found")
        return
    end

    local soundObj = findObject("rain_sound")
    if soundObj then
        soundObj:delete()
    end

    if volume == -1 then -- Automatic
        volume = rainObj.numDrops / 100
    end

    soundObj = createObject("SFXEmitter")
    soundObj.scale = Point3F(100, 100, 100)
    soundObj.fileName = String('/art/sound/environment/amb_rain_medium.ogg')
    soundObj.playOnAdd = true
    soundObj.isLooping = true
    soundObj.volume = volume
    soundObj.isStreaming = true
    soundObj.is3D = false
    soundObj:registerObject('rain_sound')
end)

AddEventHandler("E_SetRainAmount", function(amount)
    amount = tonumber(amount) or 0
    local rainObj = findObject("rain_coverage", "Precipitation")
    if not rainObj then -- Create the rain object
        rainObj = createObject("Precipitation")
        rainObj.dataBlock = scenetree.findObject("rain_medium")
        rainObj.splashSize = 0
        rainObj.splashMS = 0
        rainObj.animateSplashes = 0
        rainObj.boxWidth = 16.0
        rainObj.boxHeight = 10.0
        rainObj.dropSize = 1.0
        rainObj.doCollision = true
        rainObj.hitVehicles = true
        rainObj.rotateWithCamVel = true
        rainObj.followCam = true
        rainObj.useWind = true
        rainObj.minSpeed = 0.4
        rainObj.maxSpeed = 0.5
        rainObj.minMass = 4
        rainObj.masMass = 5
        rainObj:registerObject('rain_coverage')
    end

    rainObj.numDrops = amount
end)

M.hideCoveredWater = hideCoveredWater

return M
