_G.xu = xu or {}

local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")
xu.base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
xu.variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")
xu.bitmasks = assert(mod_data.data.bitmasks, "ERROR: data.bitmasks for parallel-piping not found!")


xu.categories = {}
xu.get_categories = function(entity)
  local base = xu.base_pipe[entity] and xu.variations[xu.base_pipe[entity]][1] or entity
  if xu.categories[base] then return xu.categories[base] end
  local prototype = prototypes.entity[base]
  if not prototype.fluidbox_prototypes[1] then return {} end
  xu.categories[base] = prototype.fluidbox_prototypes[1].pipe_connections[1].connection_category or {}
  return xu.categories[base]
end

xu.connectables = {}
xu.update_connectables = function(category)
  if xu.connectables[category] then return end
  xu.connectables[category] = {}
  for pipe in pairs(xu.variations) do
    xu.connectables[category][pipe] = false
    for _, c2 in pairs(xu.get_categories(pipe)) do
      if c2 == category then
        xu.connectables[category][pipe] = true
        break
      end
    end
  end
end

xu.directional_offsets = {
  {x = 0, y = -1},
  {x = 1, y = 0},
  {x = 0, y = 1},
  {x = -1, y = 0}
}

---@param entity LuaEntity
---@return LuaEntity[] neighbours
xu.get_pipe_neighoburs = function(entity)
  local neighbours = {}
  local prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
  local surface = entity.surface
  local force = entity.force
  -- fluidbox_prototypes is {} for unsupported entities
  for _, fluidbox in pairs(prototype.fluidbox_prototypes) do
    for _, pipe_connection in pairs(fluidbox.pipe_connections) do
      if pipe_connection.connection_type ~= "normal" then goto continue end
      local o1 = pipe_connection.positions[entity.direction / 4 + 1]
      local o2 = xu.directional_offsets[(entity.direction + pipe_connection.direction) % 16 / 4 + 1]
      local position = {
        entity.position.x + o1.x + o2.x,
        entity.position.y + o1.y + o2.y
      }
      -- populate if nonexistant
      for _, category in pairs(xu.get_categories(prototype.name)) do
        xu.update_connectables(category)
      end
      ---@type LuaEntity
      local neighbour
      for _, e in pairs(surface.find_entities_filtered{type = "pipe", position = position, force = force}) do
        for _, category in pairs(xu.get_categories(prototype.name)) do
          if xu.connectables[category][xu.base_pipe[e.name]] then
            neighbour = e
            break
          end
        end
      end
      if not neighbour then
        for _, e in pairs(surface.find_entities_filtered{ghost_type = "pipe", position = position, force = force}) do
          for _, category in pairs(xu.get_categories(prototype.name)) do
            if xu.connectables[category][xu.base_pipe[e.ghost_name]] then
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
xu.find_build_action = function(actions, entity)
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
xu.find_build_item = function(stack, entity)
  if not stack then return end
  for i = 1, stack.get_undo_item_count() do
    local action_index = xu.find_build_action(stack.get_undo_item(i), entity)
    if action_index then return i, action_index end
  end
end

---@param prototype LuaEntityPrototype
---@return double size
xu.get_size = function(prototype)
  local box = prototype.collision_box
  local dx, dy = box.right_bottom.x - box.left_top.x, box.right_bottom.y - box.left_top.y
  return dx > dy and dx or dy
end

---@param a MapPosition
---@param b MapPosition
---@return defines.direction
xu.get_direction = function(a, b)
  return math.abs(a.x - b.x) > math.abs(a.y - b.y) and (a.x < b.x and 4 or 12) or (a.y < b.y and 8 or 0)
end

xu.tank_to_pipe = {
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
}
xu.pipe_to_tank = {
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

return xu