local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")
local base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
local variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")
local event_filter = assert(mod_data.data.event_filter, "ERROR: data.event_filter for parallel-piping not found!")

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

--------------------------------------------------------------------------------------------------- blueprint
-- script.on_event({defines.events.on_player_setup_blueprint}, function (event)
-- 	local player = game.players[event.player_index]
-- 	local blueprint = player and player.blueprint_to_setup
--   -- if normally invalid
-- 	if not blueprint or not blueprint.valid_for_read then blueprint = player.cursor_stack end
--   -- if non existant, cancel
--   if not blueprint then return end
--   local entities = blueprint and blueprint.get_blueprint_entities()
--   if not entities then return; end
--   -- update entities
--   for i, entity in pairs(entities) do entity.name = getType(entity) end
--   blueprint.set_blueprint_entities(entities)
-- end)

script.on_init(function()
  storage.build_ticks = storage.build_ticks or {}
end)

script.on_configuration_changed(function()
  storage.build_ticks = storage.build_ticks or {}
end)

script.on_event(defines.events.on_player_created, function (event)
  storage.build_ticks[event.player_index] = {}
end)

-- clear excess ticks (3600)
script.on_nth_tick(121, function (event)
  for _, build_ticks in pairs(storage.build_ticks) do
    for tick in pairs(build_ticks) do
      if tick + 3600 < event.tick then
        build_ticks[tick] = nil
      end
    end
  end
end)

--[[
okay, so
here is earth. ROUND
if this network has a filter already:
  ignore networks with invalid filters
  prioritize networks with the same filter
if this network has no filter:
  prioritize 2+ adjacent networks share the same filter
connect to as many networks as possible
]]

--[[
RULE PRIORITY:
  if not existing:
    if fluids exist: pick the fluid with the most connections existing
    if tie: (2-2 or 1-1 or 1-1-1 or 1-1-1-1)
      if 2 fluid A and 2 fluid B:
        if none recent:
          if all 4 independent networks: pick north align
          if fluid A independent and fluid B consistent networks: connect fluid A
          if fluid A consistent and fluid B consistent networks: pick north align
        if 1 recent: pick recent
        if 2 recent:
          if both same fluid: connect both recent
          if both different fluid:
            
        if only 2 most recent and same fluid: connect 2 most recent
        if 2+ most recent:
        if only one fluid has two different networks: pick those networks to connect them
        if both individual connections per fluid the same network: pick empty
        if all 4 different networks: pick fluid
      if 2 fluid A and 2 fluid B:
        if only one fluid has two different networks: pick those networks to connect them
        if both individual connections per fluid the same network: pick smaller network (bounding box)
        if all 4 different networks: pick fluid with smallest network 
        else: pick north align and merge
      if 1-1:
        if 1 fluid and 1 empty: merge both
        if 2 fluids: pick north align
      if 1 of multiple different fluids and 1 empty:
        if 2+ recently built and one of 2 most recent is empty: connect 2 most recent
        if 1 most recent: connect most recent
        else: connect empty
      if 1 of multiple different fluids: pick north align
    else no fluids: merge all


]]

--- @param event EventData.on_built_entity
script.on_event(defines.events.on_built_entity, function (event)
  local player = game.get_player(event.player_index)
  local entity = event.entity
  local base = base_pipe[entity.name]
  if not base then return end -- skip things we dont care about
  local last_entity = storage.last_click[event.player_index]
  local neighbours = entity.neighbours
  local same_base, most_recent = 0, 3600
  local fluids, networks = {}, {}
  for i, set in pairs(neighbours) do
    local neighbour = set[1]
    set = neighbour and { -- properties in order of priority
      entity = neighbour,
      ticks = base_pipe[neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name] and
        3600 - ((entity.surface.find_entity("piping-build-record", neighbour.position) or {}).time_to_live or 0) or nil,
      base = base_pipe[neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name] or nil,
      id = entity.fluidbox.get_fluid_segment_id(i) or 0,
      -- box = entity.fluidbox.get_fluid_segment_extent_bounding_box(i)
    } or {}
    if neighbour then -- get fluid, if it exists, its not part of this entity's fluidbox yet
      game.print(entity.surface.find_entities_filtered{name = "piping-build-record", position = neighbour.position}[1])
      for j = 1, #neighbour.fluidbox do
        if neighbour.fluidbox.get_fluid_segment_id(j) == set.id then
          set.fluid = (neighbour.fluidbox[j] or {}).name
          break
        end
      end
    end
    if neighbour then
      most_recent = (set.ticks or 3600) < most_recent and set.ticks or most_recent
      same_base = same_base + (base == set.base and 1 or 0)
      fluids[set.fluid or 0] = set.fluid and ((fluids[set.fluid] or 0) + 1) or nil
      networks[set.id] = (networks[set.id] or 0) + 1
    end
    neighbours[i] = set
  end
  -- game.print(serpent.block(neighbours))
  -- make a tracker for how long the entity has been alive
  entity.surface.create_entity{
    name = "piping-build-record",
    position = entity.position,
    force = entity.force,
    create_build_effect_smoke = false,
    preserve_ghosts_and_corpses = true
  }
  -- analyze
  local filter
  if most_recent < 3600 then
    for _, set in pairs(neighbours) do
      if set.ticks == most_recent then
        filter = set.fluid
        break
      end
    end
  elseif table_size(fluids) == 1 then
    game.print("1 fluid")
    for _, set in pairs(neighbours) do
      filter = filter or set.fluid
    end
  elseif table_size(fluids) > 1 then
    game.print("2 fluids")
    local prevalent, size = nil, 0
    for fluid, count in pairs(fluids) do
      if count > size then
        prevalent = fluid
        size = count
      elseif count == size then
        prevalent = nil
      end
    end
    -- nil if even
    filter = prevalent or "no fluid"
    -- else some edge case 2-2 or 1-1/1-1-1/1-1-1-1
  end
  -- build bitmask using constraints
  local bitmask = 0
  for index, set in pairs(neighbours) do
    if set.fluid == filter or not filter or not set.entity then
      bitmask = bitmask + 2^(index - 1)
    end
  end

  -- game.print(bitmask)

  -- create new entity
  entity.surface.create_entity{
    name = variations[base]["" .. bitmask] or base,
    position = entity.position,
    force = entity.force,
    quality = entity.quality,
    create_build_effect_smoke = false,
    preserve_ghosts_and_corpses = true
  }
  entity.destroy()

  -- error: edge case discovered
  -- log(serpent.block(neighbours))
  -- error("ERROR: edge case fluid connection logic discovered, please report on github")

end, event_filter)

-- script.on_event("piping-build", function (event)
--   if event.in_gui then return end
--   local player = game.get_player(event.player_index)
--   game.print(player.selected)
--   local item = player.cursor_ghost and player.cursor_ghost.name or
--     player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.prototype or nil
--   if not item or not item.place_result then return end
--   storage.build_ticks[event.player_index][event.tick] = player.selected.position
-- end)