local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")
local base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
local variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")
local bitmasks = assert(mod_data.data.bitmasks, "ERROR: data.bitmasks for parallel-piping not found!")
local event_filter = assert(mod_data.data.event_filter, "ERROR: data.event_filter for parallel-piping not found!")

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

-- ---@param name string
-- ---@return string variation
-- local function get_variation(name)
--   return tonumber(name:sub(-2)) or 0
-- end

script.on_event(defines.events.on_pre_build, function(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  local cursor = player.cursor_stack
  if not (cursor and cursor.valid_for_read) then return end
  local place_result = cursor.prototype.place_result
  if not (place_result and place_result.type == "pipe") then return end

  local position = event.position
  local entity = player.surface.find_entities_filtered{type = "pipe", position = position, limit = 1}[1]
  local ghost = player.surface.find_entities_filtered{ghost_type = "pipe", position = position, limit = 1}[1]
  if entity or ghost then
    storage.existing_connections[event.player_index] = bitmasks[entity and entity.name or ghost.ghost_name]
    if entity and event.build_mode == defines.build_mode.normal then
      storage.old_health[event.player_index] = entity and entity.health or nil
      entity.health = entity.max_health
    end
  end
end)

script.on_event(defines.events.on_built_entity, function(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  local entity = event.entity
  local previous = storage.previous[player.index]
  storage.previous[player.index] = {entity = entity, position = entity.position}
  local surface = entity.surface
  local name = entity.name == "entity-ghost" and entity.ghost_name or entity.name
  local base = base_pipe[name]
  local stack = player.undo_redo_stack


  if not base then return end

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

  -- local remove = 0

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
        -- game.print(index)
        local health = prev.health
        local new_prev = surface.create_entity({
          name = prev.name == "entity-ghost" and "entity-ghost" or variations[base_pipe[prev_name]]["" .. new_mask],
          ghost_name = prev.name == "entity-ghost" and variations[base_pipe[prev_name]]["" .. new_mask] or nil,
          position = prev.position,
          quality = prev.quality,
          force = prev.force,
          -- fast_replace = true,
          -- spill = false,
          player = index and player.index or nil,
          undo_index = index,
          create_build_effect_smoke = false,
        }) --[[@as LuaEntity]]
        -- undo_index = 1
        prev.destroy{player = index and player or nil, undo_index = index}
        if health then new_prev.health = health end
        -- if new_prev.name ~= "entity-ghost" then remove = 1 end
      end
    end
  end

  -- local new_name = string.format("%s-pp-%02d", name, variation)
  local new_name = variations[base]["" .. variation]
  if surface.can_place_entity{name = new_name, position = entity.position, force = entity.force} then
    local health = storage.old_health[player.index]
    storage.old_health[player.index] = nil
    local new_entity = surface.create_entity({
      name = entity.name == "entity-ghost" and "entity-ghost" or new_name,
      ghost_name = entity.name == "entity-ghost" and new_name or nil,
      position = entity.position,
      quality = entity.quality,
      force = entity.force,
      -- fast_replace = true,
      -- spill = false,
      player = player.index,
      undo_index = 1,
      create_build_effect_smoke = false,
    }) --[[@as LuaEntity]]
    entity.destroy()
    if health then new_entity.health = health end
    storage.previous[player.index].entity = new_entity
    -- if new_entity.name ~= "entity-ghost" then remove = remove + 1 end


    -- local cursor = player.cursor_stack
    -- if entity.name ~= "entity-ghost" and cursor and cursor.valid_for_read then--and (cursor.health < 1) == (health < entity.max_health) then
    --   cursor.count = cursor.count - 1
    -- else
    --   player.remove_item{name = name, count = 1}
    -- end
  else
    -- reinsert to cursor if not a ghost
    if entity.name ~= "entity-ghost" and player.cursor_stack and player.cursor_stack.valid_for_read then
      player.cursor_stack.count = player.cursor_stack.count + 1
    end
    entity.destroy()
    -- player.mine_entity(entity, true)
    -- player.remove_item{name = name, count = 1}
  end
  -- game.print(serpent.block(stack.get_undo_item(2)))
  
  if not blueprint then
    -- simple remove only item in list (this thing that was just built)
    stack.remove_undo_action(1, 1)
  end


end, {{filter = "type", type = "pipe"}, {filter = "ghost_type", type = "pipe"}})

-- DONE: cursor ghost
-- DONE: ghosts in general
-- DONE: undo/redo
-- DONE: items being inserted/removed *why*
-- TODO: blueprints
-- TODO: mod compat checks
-- TODO: on removal update adjacent connections
-- DONE: health issues