local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")
local base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
local variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")
local bitmasks = assert(mod_data.data.bitmasks, "ERROR: data.bitmasks for parallel-piping not found!")
local event_filter = {{filter = "type", type = "pipe"}, {filter = "ghost_type", type = "pipe"}}

local connectables = {}
local conversion = {
  tank_pipe = {
    ending = {
      north = 4,
      east = 8,
      south = 1,
      west = 2
    },
    straight = {
      north = 5,
      east = 10,
      south = 5,
      west = 10
    },
    junction = {
      north = 14,
      east = 13,
      south = 11,
      west = 7
    },
    corner = {
      north = 6,
      east = 12,
      south = 9,
      west = 3
    },
    cross = {
      north = 15,
      east = 15,
      south = 15,
      west = 15
    }
  },
  pipe_tank = {
    [0] = {mask = "0"},
    {mask = "ending", direction = defines.direction.south},
    {mask = "ending", direction = defines.direction.west},
    {mask = "corner", direction = defines.direction.west},
    {mask = "ending", direction = defines.direction.north},
    {mask = "straight", direction = defines.direction.north},
    {mask = "corner", direction = defines.direction.north},
    {mask = "junction", direction = defines.direction.west},
    {mask = "ending", direction = defines.direction.east},
    {mask = "corner", direction = defines.direction.south},
    {mask = "straight", direction = defines.direction.east},
    {mask = "junction", direction = defines.direction.south},
    {mask = "corner", direction = defines.direction.east},
    {mask = "junction", direction = defines.direction.east},
    {mask = "junction", direction = defines.direction.north},
    {mask = "cross"},
  }
}

local function get_or_update_connectables(name)
  if not connectables[name] then
    connectables[name] = {}
    local categories = {}
    for _, fluidbox in pairs(prototypes.entity[variations[name]["1"]].fluidbox_prototypes) do
      for _, pipe_connection in pairs(fluidbox.pipe_connections) do
        if pipe_connection.connection_type == "normal" then
          for _, category in pairs(pipe_connection.connection_category) do
            categories[category] = true
          end
        end
      end
    end
    for pipe in pairs(variations) do
      local connectable = false
      local prototype = prototypes.entity[variations[pipe]["1"]]
      for _, fluidbox in pairs(prototype.fluidbox_prototypes) do
        for _, pipe_connection in pairs(fluidbox.pipe_connections) do
          if pipe_connection.connection_type == "normal" then
            for _, category in pairs(pipe_connection.connection_category) do
              if categories[category] then
                connectable = true
                connectables[name][#connectables[name]+1] = pipe
                break
              end
            end
          end
          if connectable then break end
        end
        if connectable then break end
      end
    end
    for _, base in pairs(connectables[name]) do
      for _, variation in pairs(variations[base] or {}) do
        connectables[base][#connectables[base]+1] = variation
      end
    end
  end
end

local function add_connection(entity, bitmask, player)
  if not entity.valid then return end
  local prev_name = prev.name == "entity-ghost" and prev.ghost_name or prev.name
  local prev_variation = get_connection_bit(prev.position, entity.position)
  local new_mask = bit32.bor(bitmasks[prev_name], prev_variation)
  if new_mask ~= bitmasks[prev_name] then
    -- LOSSY UNDO STACK CHECK
    local index
    for i = 1, stack.get_undo_item_count() do
      for _, action in pairs(stack.get_undo_item(i)) do
        if action.type == "built-entity" and
          action.surface_index == surface.index and
          action.target.name == prev.name and
          action.target.position.x == prev.position.x and
          action.target.position.y == prev.position.y then
          index = i
          break
        end
      end
      if index then break end
    end
    -- game.print(index)
    local health = prev.health
    local new_prev = surface.create_entity({
      name = prev.name == "entity-ghost" and "entity-ghost" or variations[base_pipe[prev_name]]["" .. new_mask],
      ghost_name = prev.name == "entity-ghost" and variations[base_pipe[prev_name]]["" .. new_mask] or nil,
      position = prev.position,
      quality = prev.quality,
      force = prev.force,
      player = index and player.index or nil,
      undo_index = index,
      create_build_effect_smoke = false,
    }) --[[@as LuaEntity]]
    prev.destroy{player = index and player or nil, undo_index = index}
    if health then new_prev.health = health end
  end
end

local function remove_connection(entity, bitmask, player)
  if not entity.valid then return end

end

script.on_init(function()
  ---@type table<uint, MapPosition> player index
  storage.build_position = {}
  ---@type table<uint, {entity: LuaEntity, position: MapPosition}> player index
  storage.previous = {}
  ---@type table<uint, uint> player index -> bitmask
  storage.existing_connections = {}
  ---@type table<uint, uint> player index -> health
  storage.old_health = {}
end)

script.on_configuration_changed(function()
  storage.build_position = storage.build_position or {}
  storage.previous = storage.previous or {}
  storage.existing_connections = storage.existing_connections or {}
  storage.old_health = storage.old_health or {}
end)

local offset_to_bit = {
  [string.pack(">i3i3", 0, -1)] = 2 ^ 0,
  [string.pack(">i3i3", 1, 0)]  = 2 ^ 1,
  [string.pack(">i3i3", 0, 1)]  = 2 ^ 2,
  [string.pack(">i3i3", -1, 0)] = 2 ^ 3,
}

---@param a MapPosition
---@param b MapPosition
---@return uint8 bit
local function get_connection_bit(a, b)
  return offset_to_bit[string.pack(">i3i3", b.x - a.x, b.y - a.y)] or 0
end

---@param event EventData.on_pre_build
script.on_event(defines.events.on_pre_build, function(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  local cursor = player.cursor_stack
  if not cursor or not cursor.valid_for_read then return end
  local place_result = cursor.prototype.place_result
  if not place_result or place_result.type ~= "pipe" then return end

  get_or_update_connectables(place_result.name)

  local position = event.position
  local entity = player.surface.find_entities_filtered{type = "pipe", position = position, limit = 1, name = connectables[place_result.name]}[1]
  local ghost = player.surface.find_entities_filtered{ghost_type = "pipe", position = position, limit = 1, ghost_name = connectables[place_result.name]}[1]
  if entity or ghost then
    storage.existing_connections[event.player_index] = bitmasks[entity and entity.name or ghost.ghost_name]
    if entity and event.build_mode == defines.build_mode.normal then
      storage.old_health[event.player_index] = entity and entity.health or nil
      entity.health = entity.max_health
    end
  end
end)

---@param event EventData.on_built_entity|EventData.script_raised_built
local function on_built(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  local entity = event.entity
  local previous = storage.previous[player.index]
  storage.previous[player.index] = {entity = entity, position = entity.position}
  local name = entity.name == "entity-ghost" and entity.ghost_name or entity.name
  local base = base_pipe[name]

  -- only handle normal placement, for now. ignore undo/redo
  if name ~= base then return end

  local surface = entity.surface
  local stack = player.undo_redo_stack
  local blueprint = #stack.get_undo_item(1) ~= 1
  if blueprint then -- multiple items (blueprint or otherwise) do complicated checks
    for i, action in pairs(stack.get_undo_item(1)) do
      if action.type == "built-entity" and
        action.target.name == entity.name and
        action.target.position.x == entity.position.x and
        action.target.position.y == entity.position.y then
        stack.remove_undo_action(1, i)
        break
      end
    end
  end

  local variation = storage.existing_connections[player.index] or 0
  storage.existing_connections[player.index] = nil

  if previous then
    variation = bit32.bor(variation, get_connection_bit(entity.position, previous.position))
    local prev = previous.entity
    if prev.valid then
      local prev_name = prev.name == "entity-ghost" and prev.ghost_name or prev.name
      local prev_variation = get_connection_bit(prev.position, entity.position)
      local new_mask = bit32.bor(bitmasks[prev_name], prev_variation)
      if new_mask ~= bitmasks[prev_name] then
        -- LOSSY UNDO STACK CHECK
        local index
        for i = 1, stack.get_undo_item_count() do
          for _, action in pairs(stack.get_undo_item(i)) do
            if action.type == "built-entity" and
              action.surface_index == surface.index and
              action.target.name == prev.name and
              action.target.position.x == prev.position.x and
              action.target.position.y == prev.position.y then
              index = i
              break
            end
          end
          if index then break end
        end
        local health = prev.health
        local new_prev = surface.create_entity({
          name = prev.name == "entity-ghost" and "entity-ghost" or variations[base_pipe[prev_name]]["" .. new_mask],
          ghost_name = prev.name == "entity-ghost" and variations[base_pipe[prev_name]]["" .. new_mask] or nil,
          position = prev.position,
          quality = prev.quality,
          force = prev.force,
          player = index and player.index or nil,
          undo_index = index,
          create_build_effect_smoke = false,
        }) --[[@as LuaEntity]]
        prev.destroy{player = index and player or nil, undo_index = index}
        if health then new_prev.health = health end
      end
    end
  end

  local new_name = variations[base]["" .. variation]
  if surface.can_place_entity{name = new_name, position = entity.position, force = entity.force} then
    local health = storage.old_health[player.index] or entity.health
    storage.old_health[player.index] = nil
    local new_entity = surface.create_entity({
      name = entity.name == "entity-ghost" and "entity-ghost" or new_name,
      ghost_name = entity.name == "entity-ghost" and new_name or nil,
      position = entity.position,
      quality = entity.quality,
      force = entity.force,
      player = player.index,
      undo_index = 1,
      create_build_effect_smoke = false,
    }) --[[@as LuaEntity]]
    entity.destroy()
    if health then new_entity.health = health end
    storage.previous[player.index].entity = new_entity
  else
    if player.cursor_stack and player.cursor_stack.valid_for_read then
      player.cursor_stack.count = player.cursor_stack.count + 1
    elseif event.consumed_items and player.cursor_stack and player.is_cursor_empty() then
      -- just placed last item, put it back
      player.cursor_stack.transfer_stack(event.consumed_items[1])
    end
    entity.destroy()
  end

  -- simple remove only item in list (this thing that was just built)
  if not blueprint then
    stack.remove_undo_action(1, 1)
  end
end

script.on_event(defines.events.on_built_entity, on_built, event_filter)
-- script.on_event(defines.events.script_raised_built, on_built, event_filter)

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
local function on_destroyed(event)
  -- something got removed, disconnect neighbours
  local entity = event.entity
  local player = event.player_index and game.get_player(event.player_index)
  local base = base_pipe[entity.name == "entity-ghost" and entity.ghost_name or entity.name]
  if storage.existing_connections[player.index] == bitmasks[entity.name == "entity-ghost" and entity.ghost_name or entity.name] or not base then return end
  for bit, offset in pairs{
    [4] = {0, -1},
    [8] = {1, 0},
    [1] = {0, 1},
    [2] = {-1, 0}
  } do
    -- populate if nonexistant
    get_or_update_connectables(base)
    local neighbour = entity.surface.find_entities_filtered{
      position = {
        entity.position.x + offset[1],
        entity.position.y + offset[2]
      },
      type = "pipe",
      name = connectables[base],
      limit = 1,
    }[1] or entity.surface.find_entities_filtered{
      position = {
        entity.position.x + offset[1],
        entity.position.y + offset[2]
      },
      ghost_type = "pipe",
      ghost_name = connectables[base],
      limit = 1,
    }[1]
    if neighbour then
      local name = neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name
      local old_mask = bitmasks[name]
      local new_mask = old_mask - bit32.band(old_mask, bit)
      if old_mask ~= new_mask then
        -- LOSSY UNDO STACK CHECK
        local stack = player and player.undo_redo_stack
        local index
        if stack then
          for i = 1, stack.get_undo_item_count() do
            for _, action in pairs(stack.get_undo_item(i)) do
              if action.type == "built-entity" and
                action.surface_index == entity.surface.index and
                action.target.name == name and
                action.target.position.x == neighbour.position.x and
                action.target.position.y == neighbour.position.y then
                index = i
                break
              end
            end
            if index then break end
          end
        end
        local health = neighbour.health
        local new_prev = entity.surface.create_entity({
          name = neighbour.name == "entity-ghost" and "entity-ghost" or variations[base_pipe[name]]["" .. new_mask],
          ghost_name = neighbour.name == "entity-ghost" and variations[base_pipe[name]]["" .. new_mask] or nil,
          position = neighbour.position,
          quality = neighbour.quality,
          force = neighbour.force,
          player = index and player.index or nil,
          undo_index = index,
          create_build_effect_smoke = false,
        }) --[[@as LuaEntity]]
        neighbour.destroy{player = index and player or nil, undo_index = index}
        if health then new_prev.health = health end
      end
    end
  end
end

script.on_event(defines.events.on_player_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.on_robot_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.on_space_platform_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.script_raised_destroy, on_destroyed, event_filter)
script.on_event(defines.events.on_entity_died, on_destroyed, event_filter)

-- script.on_event(defines.events.on_undo_applied, function (event)
--   for _, action in pairs(event.actions) do
--     if action.type == "built-entity" then
--       -- undoing build, the entity is being tagged for deconstruction
--     elseif action.type == "removed-entity" then
--       -- redoing build, the entity is being ghost placed
--     end
--   end
-- end)

-- script.on_event(defines.events.on_player_setup_blueprint, function (event)
-- 	local player = game.get_player(event.player_index)
-- 	local blueprint = player.blueprint_to_setup
--   -- if normally invalid
-- 	if not blueprint or not blueprint.valid_for_read then blueprint = player.cursor_stack end
--   -- if non existant, cancel
--   local entities = blueprint and blueprint.get_blueprint_entities()
--   if not entities then return end
--   local changed = false
--   -- update entities
--   for _, entity in pairs(entities) do
--     if base_pipe[entity.name] then
--       changed = true
--       local variation = conversion.pipe_tank[bitmasks[entity.name]]
--       entity.name = variations[base_pipe[entity.name]][variation.mask]
--       entity.direction = variation.direction
--     end
--   end
--   if not changed then return end -- make no changes unless required
--   blueprint.set_blueprint_entities(entities)
-- end)

-- DONE: cursor ghost
-- DONE: ghosts in general
-- DONE: undo/redo
-- DONE: items being inserted/removed *why*
-- TODO: blueprints
-- TODO: mod compat checks
-- TODO: on removal update adjacent connections
-- DONE: health issues
-- DONE: placing an item with health removes it's health
-- TODO: placing an item with health on an existing thing removes the item with health (probably can ignore)
-- TODO: fluid shit
-- TODO: if aup installed, search with a specific collision mask