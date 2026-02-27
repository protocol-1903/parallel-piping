local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")
local base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
local variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")
local bitmasks = assert(mod_data.data.bitmasks, "ERROR: data.bitmasks for parallel-piping not found!")
local event_filter = {{filter = "type", type = "pipe"}, {filter = "ghost_type", type = "pipe"}, {filter = "type", type = "storage-tank"}, {filter = "ghost_type", type = "storage-tank"}}

-- transform "0" to 0 etc
for index, set in pairs(variations) do
  local new_set = {}
  for mask, entity in pairs(set) do
    if tonumber(mask) then
      new_set[tonumber(mask)] = entity
    else
      new_set[mask] = entity
    end
  end
  variations[index] = new_set
end

local conversion = {
  tank_pipe = {
    nothingburger = {
      [0] = 0,
      [4] = 0,
      [8] = 0,
      [12] = 0
    },
    ending = {
      [0] = 4,
      [4] = 8,
      [8] = 1,
      [12] = 2
    },
    straight = {
      [0] = 5,
      [4] = 10,
      [8] = 5,
      [12] = 10
    },
    junction = {
      [0] = 14,
      [4] = 13,
      [8] = 11,
      [12] = 7
    },
    corner = {
      [0] = 6,
      [4] = 12,
      [8] = 9,
      [12] = 3
    },
    cross = {
      [0] = 15,
      [4] = 15,
      [8] = 15,
      [12] = 15
    }
  },
  pipe_tank = {
    [0] = {mask = "nothingburger"},
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

local categories = {}
local function get_categories(entity)
  if categories[entity] then return categories[entity] end
  categories[entity] = prototypes.entity[base_pipe[entity] and variations[base_pipe[entity]][1] or entity].fluidbox_prototypes[1].pipe_connections[1].connection_category
  return categories[entity]
end

local connectables = {}
local function update_connectables(category)
  if connectables[category] then return end
  connectables[category] = {}
  for pipe in pairs(variations) do
    connectables[category][pipe] = false
    for _, c2 in pairs(get_categories(pipe)) do
      if c2 == category then
        connectables[category][pipe] = true
        break
      end
    end
  end
end

local directional_offsets = {
  {x = 0, y = -1},
  {x = 1, y = 0},
  {x = 0, y = 1},
  {x = -1, y = 0}
}

---@param entity LuaEntity
---@return LuaEntity[] neighbours
local function get_pipe_neighoburs(entity)
  local neighbours = {}
  local prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
  local surface = entity.surface
  local force = entity.force
  -- fluidbox_prototypes is {} for unsupported entities
  for _, fluidbox in pairs(prototype.fluidbox_prototypes) do
    for _, pipe_connection in pairs(fluidbox.pipe_connections) do
      if pipe_connection.connection_type ~= "normal" then goto continue end
      local o1 = pipe_connection.positions[entity.direction / 4 + 1]
      local o2 = directional_offsets[(entity.direction + pipe_connection.direction) % 16 / 4 + 1]
      local position = {
        entity.position.x + o1.x + o2.x,
        entity.position.y + o1.y + o2.y
      }
      -- populate if nonexistant
      for _, category in pairs(get_categories(prototype.name)) do
        update_connectables(category)
      end
      ---@type LuaEntity
      local neighbour
      for _, e in pairs(surface.find_entities_filtered{type = "pipe", position = position, radius = 0.25, force = force}) do
        for _, category in pairs(get_categories(prototype.name)) do
          if connectables[category][base_pipe[e.name]] then
            neighbour = e
            break
          end
        end
      end
      if not neighbour then
        for _, e in pairs(surface.find_entities_filtered{ghost_type = "pipe", position = position, radius = 0.25, force = force}) do
          for _, category in pairs(get_categories(prototype.name)) do
            if connectables[category][base_pipe[e.ghost_name]] then
              neighbour = e
              break
            end
          end
        end
      end
      neighbours[#neighbours+1] = neighbour
      ::continue::
    end
  end
  return neighbours
end

---Returns the undo action associated with this entity
---@param actions UndoRedoAction[]
---@param entity LuaEntity
---@return uint32? action_index
local function find_build_action(actions, entity)
  for a, action in pairs(actions) do
    if action.type == "built-entity" and
      action.surface_index == entity.surface_index and
      action.target.name == entity.name and
      action.target.position.x == entity.position.x and
      action.target.position.y == entity.position.y then
      return a
    end
  end
end

---Returns the undo item and action associated with this entity
---@param stack LuaUndoRedoStack
---@param entity LuaEntity
---@return uint32? item_index, uint32? action_index
local function find_build_item(stack, entity)
  if not stack then return end
  for i = 1, stack.get_undo_item_count() do
    local action_index = find_build_action(stack.get_undo_item(i), entity)
    if action_index then return i, action_index end
  end
end

---@param prototype LuaEntityPrototype
---@return double size
local function get_size(prototype)
  local box = prototype.collision_box
  local dx, dy = box.right_bottom.x - box.left_top.x, box.right_bottom.y - box.left_top.y
  return dx > dy and dx or dy
end

script.on_init(function()
  ---@type table<uint, uint> player index -> tick
  storage.build_ticks = {}
  ---@type table<uint, LuaEntity> player index -> entity
  storage.previous = {}
  ---@type table<uint, uint> player index -> bitmask
  storage.existing_connections = {}
  ---@type table<uint, uint> player index -> health
  storage.old_health = {}
  ---@type table<uint, uint> player index -> health
  storage.old_fluid = {}
end)

script.on_configuration_changed(function()
  storage.build_ticks = storage.build_ticks or {}
  storage.previous = storage.previous or {}
  storage.existing_connections = storage.existing_connections or {}
  storage.old_health = storage.old_health or {}
  storage.old_fluid = storage.old_fluid or {}
end)

---@param a MapPosition
---@param b MapPosition
---@return defines.direction
local function get_direction(a, b)
  return math.abs(a.x - b.x) > math.abs(a.y - b.y) and (a.x < b.x and 4 or 12) or (a.y < b.y and 8 or 0)
end

--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive|EventData.on_cancelled_deconstruction
local function on_built(event)
  local player = event.player_index and game.get_player(event.player_index)
  local entity = event.entity
  local previous = player and storage.previous[player.index]
  if player then
    storage.previous[player.index] = entity
  end
  local prototype = entity.name == "entity-ghost" and entity.ghost_prototype or entity.prototype
  local name = prototype.name
  local base = base_pipe[name]

  local surface = entity.surface
  local stack = player and player.undo_redo_stack
  local blueprint = stack and #stack.get_undo_item(1) ~= 1
  if base then
    if blueprint then -- multiple items (blueprint or otherwise) do complicated checks
      local i = find_build_action(stack.get_undo_item(1), entity)
      if i then stack.remove_undo_action(1, i) end
    end

    -- just placed a blueprint, convert to normal
    if entity.type == "entity-ghost" and entity.ghost_type == "storage-tank" or entity.type == "storage-tank" then
      local mask = conversion.tank_pipe[bitmasks[name]][entity.direction]
      local new_name = variations[base_pipe[name]][mask]
      local new_entity = surface.create_entity{
        name = entity.name == "entity-ghost" and "entity-ghost" or new_name,
        ghost_name = entity.name == "entity-ghost" and new_name or nil,
        position = entity.position,
        quality = entity.quality,
        force = entity.force,
        player = event.player_index,
        undo_index = player and 1 or nil,
        create_build_effect_smoke = false,
      }
      entity.destroy()
      if player then
        storage.previous[player.index] = new_entity
      end
      if stack and not blueprint then
        stack.remove_undo_action(1, 1)
      end
      return
    end
  end

  local existing = player and storage.existing_connections[player.index]
  local variation = existing and bitmasks[existing] or 0
  if player then
    storage.existing_connections[player.index] = nil
  end

  local can_place = base and surface.can_place_entity{name = variations[base][0], position = entity.position, force = entity.force}

  if previous and previous.valid then
    local prev_prototype = previous.name == "entity-ghost" and previous.ghost_prototype or previous.prototype
    if base_pipe[prev_prototype.name] then
      local prev_variation = 2 ^ (get_direction(previous.position, entity.position) / 4)
      local new_mask = bit32.bor(bitmasks[prev_prototype.name], prev_variation)
      local connect = base_pipe[existing or name] == base_pipe[prev_prototype.name] or existing == ""
      local dx, dy = math.abs(entity.position.x - previous.position.x), math.abs(entity.position.y - previous.position.y)
      if not connect then
        for _, category in pairs(get_categories(base and base_pipe[existing or name] or name)) do
          update_connectables(category)
          if connectables[category][base_pipe[prev_prototype.name]] then
            connect = true
            break
          end
        end
      end
      local dist = (math.ceil(get_size(prototype)) + math.ceil(get_size(prev_prototype))) / 2
      if (not can_place or dx ~= dy and math.max(dx, dy) == dist) and connect and new_mask ~= bitmasks[prev_prototype.name] then
        variation = bit32.bor(variation, 2 ^ (get_direction(entity.position, previous.position) / 4))
        -- LOSSY UNDO STACK CHECK
        local build_index, build_action = find_build_item(stack, previous)
        local health = previous.health
        local fluid = previous.fluidbox[1]
        if fluid then
          local amount = previous.fluidbox.get_fluid_segment_contents(1)
          fluid.amount = amount[fluid.name]
        end
        local new_prev = surface.create_entity{
          name = previous.name == "entity-ghost" and "entity-ghost" or variations[base_pipe[prev_prototype.name]][new_mask],
          ghost_name = previous.name == "entity-ghost" and variations[base_pipe[prev_prototype.name]][new_mask] or nil,
          position = previous.position,
          quality = previous.quality,
          force = previous.force,
          player = build_index and player.index or nil,
          undo_index = build_index,
          create_build_effect_smoke = false,
        }
        previous.destroy()
        if build_index then stack.remove_undo_action(build_index, build_action) end
        if health then new_prev.health = health end
        if fluid then new_prev.fluidbox[1] = fluid end
      end
    else -- not a pipe, connect generically if allowed
      for _, neighbour in pairs(get_pipe_neighoburs(previous)) do
        if neighbour.unit_number == entity.unit_number then
          variation = bit32.bor(variation, 2 ^ (get_direction(entity.position, previous.position) / 4))
          break
        end
      end
    end
  end

  if can_place then
    local health = player and storage.old_health[player.index] or entity.health
    local fluid = player and storage.old_fluid[player.index]
    local new_name = variations[base][variation]
    if player then
      storage.old_health[player.index] = nil
    end
    local new_entity = surface.create_entity{
      name = entity.name == "entity-ghost" and "entity-ghost" or new_name,
      ghost_name = entity.name == "entity-ghost" and new_name or nil,
      position = entity.position,
      quality = entity.quality,
      force = entity.force,
      player = event.player_index,
      undo_index = player and 1 or nil,
      create_build_effect_smoke = false,
    }
    entity.destroy()
    if health then new_entity.health = health end
    if fluid then new_entity.fluidbox[1] = fluid end
    if player then
      storage.previous[player.index] = new_entity
    end
  elseif base then
    if player and player.cursor_stack and player.cursor_stack.valid_for_read then
      player.cursor_stack.count = player.cursor_stack.count + 1
    elseif player and event.consumed_items and player.cursor_stack and player.is_cursor_empty() then
      -- just placed last item, put it back
      player.cursor_stack.transfer_stack(event.consumed_items[1])
    end
    local params = {
      position = entity.position,
      force = entity.force,
      collision_mask = prototypes.entity[variations[base][variation]].collision_mask.layers,
      limit = 1
    }
    entity.destroy()
    if player then
      storage.previous[player.index] = surface.find_entities_filtered(params)[1]
    end
  end

  -- simple remove only item in list (this thing that was just built)
  if stack and not blueprint then
    stack.remove_undo_action(1, 1)
  end
end

script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.on_robot_built_entity, on_built, event_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_built, event_filter)
script.on_event(defines.events.script_raised_built, on_built, event_filter)
script.on_event(defines.events.script_raised_revive, on_built, event_filter)

---@param event EventData.on_pre_build
script.on_event(defines.events.on_pre_build, function(event)
  storage.build_ticks[event.player_index] = event.tick
  storage.old_health[event.player_index] = nil
  storage.old_fluid[event.player_index] = nil
  local player = game.get_player(event.player_index)
  local place_result = player.cursor_ghost and player.cursor_ghost.name.place_result or
    player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.prototype.place_result or nil
  if not place_result or place_result.type ~= "pipe" then return end
  -- populate if nonexistant
  for _, category in pairs(get_categories(place_result.name)) do
    update_connectables(category)
  end
  local position = event.position
  local entity = player.surface.find_entities_filtered{
    type = "pipe",
    position = position,
    radius = 0.25,
    force = player.force,
    collision_mask = prototypes.entity[variations[place_result.name][0]].collision_mask.layers.object and "object" or "tomwub-underground"
  }[1]
  local ghost = player.surface.find_entities_filtered{
    ghost_type = "pipe",
    position = position,
    radius = 0.25,
    force = player.force,
    collision_mask = prototypes.entity[variations[place_result.name][0]].collision_mask.layers.object and "object" or "tomwub-underground"
  }[1]
  if entity or ghost then
    storage.existing_connections[event.player_index] = entity and entity.name or ghost.ghost_name
    if entity and event.build_mode == defines.build_mode.normal then
      storage.old_health[event.player_index] = entity and entity.health or nil
      if entity and entity.fluidbox[1] then
        local fluid = entity.fluidbox[1]
        local amount = entity.fluidbox.get_fluid_segment_contents(1)
        fluid.amount = amount[fluid.name]
        storage.old_fluid[event.player_index] = fluid
      end
      entity.health = entity.max_health
    end
  end
  if entity and (event.build_mode ~= defines.build_mode.normal or player.controller_type == defines.controllers.remote) then
    -- mimic normal build event
    storage.old_health[event.player_index] = entity and entity.health or nil
    local fluid = entity.fluidbox[1]
    if fluid then
      local amount = entity.fluidbox.get_fluid_segment_contents(1)
      fluid.amount = amount[fluid.name]
      storage.old_fluid[event.player_index] = fluid
    end
    entity.health = entity.max_health
    local event_data = event
    event.entity = entity.surface.create_entity{
      name = base_pipe[entity.name],
      position = entity.position,
      quality = entity.quality,
      force = entity.force,
      create_build_effect_smoke = false
    }
    entity.destroy();
    on_built(event_data)
  end
end)

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
local function on_destroyed(event)
  if storage.build_ticks[event.player_index] == event.tick then
    storage.build_ticks[event.player_index] = nil
    return -- early return for fast-replace events
  end
  -- something got removed, disconnect neighbours
  local entity = event.entity
  local player = event.player_index and game.get_player(event.player_index)
  local prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
  local surface = entity.surface
  local force = entity.force
  local stack = player and player.undo_redo_stack
  local blueprint = stack and #stack.get_undo_item(1) ~= 1
  if blueprint then -- multiple items (blueprint or otherwise) do complicated checks
    local i = find_build_action(stack.get_undo_item(1), entity)
    if i then stack.remove_undo_action(1, i) end
  end
  -- fluidbox_prototypes is {} for unsupported entities
  for _, neighbour in pairs(get_pipe_neighoburs(entity)) do
    local mask = bitmasks[neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name]
    local b2 = base_pipe[neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name]
    local bit = 2 ^ (get_direction(neighbour.position, entity.position) / 4 % 4)
    if not bit32.btest(mask, bit) then goto continue end
    mask = mask - bit
    -- LOSSY UNDO STACK CHECK
    local build_index, build_action = find_build_item(stack, neighbour)
    local health = neighbour.health
    local marked = neighbour.to_be_deconstructed()
    local fluid = neighbour.fluidbox[1]
    if fluid then
      local amount = neighbour.fluidbox.get_fluid_segment_contents(1)
      fluid.amount = amount[fluid.name]
    end
    local new_neighbour = surface.create_entity({
      name = neighbour.name == "entity-ghost" and "entity-ghost" or variations[b2][mask],
      ghost_name = neighbour.name == "entity-ghost" and variations[b2][mask] or nil,
      position = neighbour.position,
      quality = neighbour.quality,
      force = neighbour.force,
      player = build_index and player.index or nil,
      undo_index = build_index,
      create_build_effect_smoke = false,
    }) --[[@as LuaEntity]]
    neighbour.destroy()
    if build_index then stack.remove_undo_action(build_index, build_action) end
    if health then new_neighbour.health = health end
    if marked then new_neighbour.order_deconstruction(new_neighbour.force) end
    if fluid then new_neighbour.fluidbox[1] = fluid end
    ::continue::
  end
  for _, fluidbox in pairs(prototype.fluidbox_prototypes) do
    for _, pipe_connection in pairs(fluidbox.pipe_connections) do
      if pipe_connection.connection_type ~= "normal" then goto continue end
      local o1 = pipe_connection.positions[entity.direction / 4 + 1]
      local o2 = directional_offsets[(entity.direction + pipe_connection.direction) % 16 / 4 + 1]
      local position = {
        entity.position.x + o1.x + o2.x,
        entity.position.y + o1.y + o2.y
      }
      -- populate if nonexistant
      for _, category in pairs(get_categories(prototype.name)) do
        update_connectables(category)
      end
      ---@type LuaEntity
      local neighbour
      for _, e in pairs(surface.find_entities_filtered{type = "pipe", position = position, radius = 0.25, force = force}) do
        for _, category in pairs(get_categories(prototype.name)) do
          if connectables[category][base_pipe[e.name]] then
            neighbour = e
            break
          end
        end
      end
      if not neighbour then
        for _, e in pairs(surface.find_entities_filtered{ghost_type = "pipe", position = position, radius = 0.25, force = force}) do
          for _, category in pairs(get_categories(prototype.name)) do
            if connectables[category][base_pipe[e.ghost_name]] then
              neighbour = e
              break
            end
          end
        end
      end
      if not neighbour then goto continue end
      -- skip if not connected to destroyed entity
      ::continue::
    end
  end
end

script.on_event(defines.events.on_player_mined_entity, on_destroyed)
script.on_event(defines.events.on_robot_mined_entity, on_destroyed)
script.on_event(defines.events.on_space_platform_mined_entity, on_destroyed)
script.on_event(defines.events.script_raised_destroy, on_destroyed)
script.on_event(defines.events.on_entity_died, on_destroyed)

script.on_event(defines.events.on_player_setup_blueprint, function (event)
	local player = game.get_player(event.player_index)
	local blueprint = player.blueprint_to_setup
  -- if normally invalid
	if not blueprint or not blueprint.valid_for_read then blueprint = player.cursor_stack end
  -- if non existant, cancel
  local entities = blueprint and blueprint.get_blueprint_entities()
  if not entities then return end
  local changed = false
  -- update entities
  for _, entity in pairs(entities) do
    if base_pipe[entity.name] then
      changed = true
      local variation = conversion.pipe_tank[bitmasks[entity.name]]
      entity.name = variations[base_pipe[entity.name]][variation.mask]
      entity.direction = variation.direction
    end
  end
  if not changed then return end -- make no changes unless required
  blueprint.set_blueprint_entities(entities)
end)