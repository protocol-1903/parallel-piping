--------------------------------------------------------------------------------------------------- get type
-- get the type of pipe
local function getType(entity)
  -- get name from ghost or normal
  local name = entity.type == "entity-ghost" and entity.ghost_name or entity.name
  -- if npt
  if name:find("-npt") then return name:sub(1, -8)
  -- else
  else return name end
end

--------------------------------------------------------------------------------------------------- get id
-- check the amount of blocked for a pipe entity, based on number
local function getID(entity)
  -- return if nil
  if not entity then return; end
  -- get name
  local name = entity.type == "entity-ghost" and entity.ghost_name or entity.type == "pipe" and entity.name
	if not name then return; end
  -- if npt
  if name:find("-npt") then return name:sub(-3, -2)
  -- else name
  else return name end
end

--------------------------------------------------------------------------------------------------- you cant do that
-- they did something illegal. or tried to.
local function youCantDoThat(player, position)
  if not player then return end
  -- tell the player no
  player.create_local_flying_text{text = "Cannot place pipe", create_at_cursor = true}
  player.play_sound{path = "utility/cannot_build", position = position}
end

--------------------------------------------------------------------------------------------------- put it back
-- a bit like time travel
local function putItBack(event)
  if event.player_index then
    game.get_player(event.player_index).insert({name = getType(event.entity)})
  elseif event.robot then
    event.robot.get_inventory(defines.inventory.robot_cargo).clear()
    event.robot.get_inventory(defines.inventory.robot_cargo).insert({name = getType(event.entity)})
  end
end

--------------------------------------------------------------------------------------------------- find blocked
-- find number of blocked entities based on the position and type of pipe
local function findBlocked(entity, type_entity, skip, fluid_check)
	local blocked = 0
  local fluidboxes = {}
  for i, offset in pairs({{0,-1}, {1,0}, {0,1}, {-1,0}}) do
    if not skip or (entity.position.x + offset[1] ~= skip.x or entity.position.y + offset[2] ~= skip.y) then
      -- find pipe (?)
      local pipe = entity.surface.find_entities_filtered({type = 'pipe', position = {entity.position.x + offset[1], entity.position.y + offset[2]}})[1]
      -- check pipe material
      local type = pipe and getType(pipe) or nil
      if type and type ~= getType(type_entity) then blocked = blocked + 2^(i - 1)
      elseif fluid_check then
        -- dont allow fluid networks to mix
        if pipe and pipe.fluidbox.get_fluid_segment_contents(1) then
          for fluid, _ in pairs(pipe.fluidbox.get_fluid_segment_contents(1)) do
            for _, fluidbox in pairs(fluidboxes) do if fluid ~= fluidbox.fluid and pipe.fluidbox.get_fluid_segment_id(1) ~= fluidbox.network then return -1 end end
            table.insert(fluidboxes, {fluid = fluid, network = pipe.fluidbox.get_fluid_segment_id(1)})
          end
        end
      end
    end
  end
  return blocked
end

--------------------------------------------------------------------------------------------------- create new pipe
local function createNewPipe(entity, blocked)
  local surface = entity.surface
  local position = entity.position
  local force = entity.force
  local player = entity.last_user
  local fluidbox = #entity.fluidbox >= 1 and entity.fluidbox[1] or nil
  local name = blocked ~= 0 and string.format("%s-npt-%02d", getType(entity), 15 - blocked) or getType(entity)
  local upgrade = entity.to_be_upgraded() and entity.get_upgrade_target()
  -- destroy the old entity
  if not entity.destroy() then return; end -- return if something breaks
  local entity = surface.create_entity({
    name = name,
    position = position,
    force = force,
    player = player,
    create_build_effect_smoke = false,
  })
  entity.fluidbox[1] = fluidbox
  if upgrade then entity.order_upgrade({force = force, player = player, target = upgrade}) end
end

local recent_event
local recent_tick

--------------------------------------------------------------------------------------------------- block construction
local function blockConstruction(event)
  if event.robot then putItBack(event)
  elseif not event.target then -- player
    youCantDoThat(game.get_player(event.player_index), event.entity.position)
    -- if pipe, place in inventory
    if event.entity.type == "pipe" then putItBack(event) end
  else youCantDoThat(game.get_player(event.player_index), event.entity.position) end -- upgrade
  -- store position for later use
  local fluidbox = #event.entity.fluidbox >= 1 and event.entity.fluidbox[1] or nil
  -- remove placed pipe
  event.entity.destroy()
  -- replace old pipe if required
  if event.tick == recent_tick then
    recent_event.surface.create_entity({
      name = recent_event.name,
      position = recent_event.position,
      force = recent_event.force,
      player = recent_event.last_user,
      create_build_effect_smoke = false
    }).fluidbox[1] = fluidbox
    recent_tick = nil
  end
end

--------------------------------------------------------------------------------------------------- update adjacent pipes
local function updateAdjacent(position, surface, skip)
  for o, offset in pairs({{0,-1}, {1,0}, {0,1}, {-1,0}}) do
    local adjacent_pipe = surface.find_entities_filtered({type = "pipe", position = {position.x + offset[1], position.y + offset[2]}})[1]
    if adjacent_pipe then
      -- find blocked
      local blocked = findBlocked(adjacent_pipe, adjacent_pipe, skip and position or nil, false)
      -- update the pipe if something is different
      if blocked ~= getID(adjacent_pipe) and not adjacent_pipe.to_be_deconstructed() then
        -- create a new pipe
        createNewPipe(adjacent_pipe, blocked)
      end
    end
  end
end

--------------------------------------------------------------------------------------------------- log event
local function log_event(event)
  recent_tick = event.tick
  recent_event = {
    type = getType(event.entity),
    name = event.entity.name,
    force = event.entity.force,
    last_user = event.entity.last_user,
    surface = event.entity.surface,
    position = event.entity.position,
    fluidbox = #event.entity.fluidbox >= 1 and event.entity.fluidbox[1] or nil
  }
end

--------------------------------------------------------------------------------------------------- script mine
script.on_event(defines.events.script_raised_destroy, function (event)
  local entity = event.entity
  -- check if pipe, otherwise return
  if entity.type ~= "pipe" then return; end
	local pipeType = getType(entity)
  -- check if valid, otherwise return
	if not pipeType then return; end
  -- update adjacent pipes
  updateAdjacent(entity.position, entity.surface, true)
end, {{filter = "type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- player mine
script.on_event(defines.events.on_player_mined_entity, function (event)
  -- log the event in case it is an upgrade
  log_event(event)
  local entity = event.entity
  -- check if pipe, otherwise return
  if entity.type ~= "pipe" then return; end
	local pipeType = getType(entity)
  -- check if valid, otherwise return
	if not pipeType then return; end
  -- update adjacent pipes
  updateAdjacent(entity.position, entity.surface, true)
end, {{filter = "type", type = "pipe"}})

local recentMistake = nil

--------------------------------------------------------------------------------------------------- robot mine
script.on_event(defines.events.on_robot_mined_entity, function (event)
  -- log the event in case it is an upgrade
  log_event(event)
  recentMistake = event.buffer.get_contents()
  if not event.robot.get_inventory(defines.inventory.robot_cargo).is_empty() then
    event.buffer.clear()
  end
  local entity = event.entity
  -- check if pipe, otherwise return
  if entity.type ~= "pipe" then return; end
	local pipeType = getType(entity)
  -- check if valid, otherwise return
	if not pipeType then return; end
  -- update adjacent pipes
  updateAdjacent(entity.position, entity.surface, true)
end, {{filter = "type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- script build
script.on_event(defines.events.script_raised_built, function (event)
  -- find adjacent pipes
  local blocked = findBlocked(event.entity, event.entity, nil, true)
  -- if different fluidboxes have different fluids, cancel construction
  if blocked == -1 then
    blockConstruction(event)
    -- return so nothing else happens
    return
  end
  -- update adjacent pipes
  updateAdjacent(event.entity.position, event.entity.surface, false)
  -- create a new pipe
  createNewPipe(event.entity, blocked)
  recent_tick = nil
end, {{filter = "type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- player build
script.on_event(defines.events.on_built_entity, function (event)
  -- find adjacent pipes
  local blocked = findBlocked(event.entity, event.entity, nil, true)
  -- if different fluidboxes have different fluids, cancel construction
  if blocked == -1 then
    blockConstruction(event)
    -- return so nothing else happens
    return
  end
  -- do not continue if ghost
  if event.entity.type == "entity-ghost" then return end
  -- update adjacent pipes
  updateAdjacent(event.entity.position, event.entity.surface, false)
  -- create a new pipe
  createNewPipe(event.entity, blocked)
  recent_tick = nil
end, {{filter = "type", type = "pipe"}, {filter = "ghost_type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- robot build
script.on_event(defines.events.on_robot_built_entity, function (event)
  -- find adjacent pipes
  local blocked = findBlocked(event.entity, event.entity, nil, true)
  -- if different fluidboxes have different fluids, cancel construction
  if blocked == -1 then
    blockConstruction(event)
    -- return so nothing else happens
    return
  end
  -- put the old item back if its a replacement and valid
  if recent_tick == event.tick then
    for item, _ in pairs(recentMistake) do
      event.robot.get_inventory(defines.inventory.robot_cargo).insert({name = item})
    end
  end
  -- update adjacent pipes
  updateAdjacent(event.entity.position, event.entity.surface, false)
  -- create a new pipe
  createNewPipe(event.entity, blocked)
  recent_tick = nil
  recentMistake = nil
end, {{filter = "type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- cancel deconstruction
script.on_event(defines.events.on_cancelled_deconstruction, function (event)
  -- update adjacent pipes
  updateAdjacent(event.entity.position, event.entity.surface, false)
  -- find adjacent pipes
  local blocked = findBlocked(event.entity, event.entity, nil, false)
  -- if nothing is blocked, return
  if blocked == 0 then return; end
  -- create a new pipe
  createNewPipe(event.entity, blocked)
end, {{filter = "type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- entity mark upgrade
script.on_event(defines.events.on_marked_for_upgrade, function (event)
  -- if the same type, cancel
  if getType(event.entity) == getType(event.target) then
    event.entity.cancel_upgrade(event.entity.force)
  -- if would connect networks
  elseif findBlocked(event.entity, event.target, nil, true) == -1 then
    event.entity.cancel_upgrade(event.entity.force)
    youCantDoThat(game.get_player(event.player_index), event.entity.position)
  end
end, {{filter = "type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- ghost mark upgrade
script.on_event(defines.events.on_pre_ghost_upgraded, function (event)
  -- if the same type, cancel
  if findBlocked(event.ghost, event.target, nil, true) == -1 then
    event.ghost.cancel_upgrade(event.ghost.force)
    youCantDoThat(game.get_player(event.player_index), event.ghost.position)
  end
end, {{filter = "ghost_type", type = "pipe"}})

--------------------------------------------------------------------------------------------------- blueprint
script.on_event({defines.events.on_player_setup_blueprint}, function (event)
	local player = game.players[event.player_index]
	local blueprint = player and player.blueprint_to_setup
  -- if normally invalid
	if not blueprint or not blueprint.valid_for_read then blueprint = player.cursor_stack end
  -- if non existant, cancel
  if not blueprint then return end
  local entities = blueprint and blueprint.get_blueprint_entities()
  if not entities then return; end
  -- update entities
  for i, entity in pairs(entities) do entity.name = getType(entity) end
  blueprint.set_blueprint_entities(entities)
end)