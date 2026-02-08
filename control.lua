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
  if not entity and not ghost then return end
  storage.existing_connections[event.player_index] = bitmasks[entity and entity.name or ghost.ghost_name]
end)

script.on_event(defines.events.on_built_entity, function(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  local entity = event.entity
  local previous = storage.previous[player.index]
  storage.previous[player.index] = {entity = entity, position = entity.position}
  local surface = entity.surface
  local name = entity.name == "entity-ghost" and entity.ghost_name or entity.name
  local base = base_pipe[name]

  if not base then return end

  local variation = storage.existing_connections[player.index] or 0
  storage.existing_connections[player.index] = nil

  local remove = 0

  if previous then
    variation = bit32.bor(variation, get_connection_bit(entity.position, previous.position))

    local prev = previous.entity
    if prev.valid then
      local prev_name = prev.name == "entity-ghost" and prev.ghost_name or prev.name
      local prev_variation = get_connection_bit(prev.position, entity.position)
      local new_mask = bit32.bor(bitmasks[prev_name], prev_variation)
      if new_mask ~= bitmasks[prev_name] then
        local health = prev.health
        prev = surface.create_entity({
          name = prev.name == "entity-ghost" and "entity-ghost" or variations[base_pipe[prev_name]]["" .. new_mask],
          ghost_name = prev.name == "entity-ghost" and variations[base_pipe[prev_name]]["" .. new_mask] or nil,
          position = prev.position,
          quality = prev.quality,
          force = prev.force,
          fast_replace = true,
          spill = false,
          -- player = player.index,
          -- undo_index = 1,
          create_build_effect_smoke = false,
        }) --[[@as LuaEntity]]
        if health then prev.health = health end
        if prev.name ~= "entity-ghost" then remove = 1 end
      end
    end
  end

  -- local new_name = string.format("%s-pp-%02d", name, variation)
  local new_name = variations[base]["" .. variation]
  if surface.can_place_entity{name = new_name, position = entity.position, force = entity.force} then
    local health = entity.health
    entity = surface.create_entity({
      name = entity.name == "entity-ghost" and "entity-ghost" or new_name,
      ghost_name = entity.name == "entity-ghost" and new_name or nil,
      position = entity.position,
      quality = entity.quality,
      force = entity.force,
      fast_replace = true,
      spill = false,
      -- player = player.index,
      -- undo_index = 1,
      create_build_effect_smoke = false,
    }) --[[@as LuaEntity]]
    if health then entity.health = health end
    storage.previous[player.index].entity = entity
    if entity.name ~= "entity-ghost" then remove = remove + 1 end


    local cursor = player.cursor_stack
    -- if entity.name ~= "entity-ghost" and cursor and cursor.valid_for_read then--and (cursor.health < 1) == (health < entity.max_health) then
    --   cursor.count = cursor.count - 1
    -- else
    --   player.remove_item{name = name, count = 1}
    -- end
  else
    -- reinsert to cursor if not a ghost
    if entity.name ~= "entity-ghost" then
      player.cursor_stack.count = player.cursor_stack.count + 1
    end
    entity.destroy()
    -- player.mine_entity(entity, true)
    -- player.remove_item{name = name, count = 1}
  end


end, {{filter = "type", type = "pipe"}, {filter = "ghost_type", type = "pipe"}})

script.on_event(defines.events.on_undo_applied, function(event)
  local actions = event.actions
  for i = #actions, 1, -1 do
    -- local action = actions[i]
    -- if action.type == "built-entity" then
    --   if action.target.name ~= "pipe" then
    --     local surface = game.get_surface(action.surface_index) --[[@as LuaSurface]]
    --     surface.find_entity(action.target.name, action.target.position).destroy()
    --   end
    -- elseif action.type == "removed-entity" then
    --   if action.target.name ~= "pipe" then
    --     local surface = game.get_surface(action.surface_index) --[[@as LuaSurface]]
    --     surface.find_entities_filtered{name = "entity-ghost", ghost_name = action.target.name, position = action.position}[1].revive()
    --   end
    -- end
    -- game.print(serpent.block(action))
  end
end)

-- DONE: cursor ghost
-- DONE: ghosts in general
-- TODO: undo/redo
-- TODO: blueprints
-- TODO: mod compat checks
-- TODO: on removal update adjacent connections