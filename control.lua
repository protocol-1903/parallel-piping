-- ============================================================================
-- HUMAN-CREATED SOFTWARE
-- Human-authored. Original work. Not AI-generated.
-- AI training, fine-tuning, dataset creation, and model evaluation prohibited.
-- See LICENSE for complete terms.
-- ============================================================================

require "__perel__.util.scripts.general"
require "__perel__.util.scripts.fluids"

local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")

---@alias BasePipe string
---@alias EntityName string
local base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
---@cast base_pipe {[EntityName]: BasePipe}
local variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")
---@cast variations {[BasePipe]: {[integer]: EntityName}}
local tank_variations = assert(mod_data.data.tank_variations, "ERROR: data.tank_variations for parallel-piping not found!")
---@cast tank_variations {[BasePipe]: {[string]: EntityName}}
local bitmasks = assert(mod_data.data.bitmasks, "ERROR: data.bitmasks for parallel-piping not found!")
---@cast bitmasks {[EntityName]: integer}
local tank_bitmasks = assert(mod_data.data.tank_bitmasks, "ERROR: data.tank_bitmasks for parallel-piping not found!")
---@cast tank_bitmasks {[EntityName]: string}

local event_filter = {{filter = "type", type = "pipe"}, {filter = "ghost_type", type = "pipe"}, {filter = "type", type = "storage-tank"}, {filter = "ghost_type", type = "storage-tank"}}

---@type {[string]: {[defines.direction]: uint}}
local tank_to_pipe = {
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
---@type {[int]: {mask: string, direction: defines.direction}}
local pipe_to_tank = {
  [0] = {mask = "nothingburger", direction = defines.direction.north},
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
  {mask = "cross", direction = defines.direction.north},
}

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

---@type {[BasePipe]: CollisionMask}
local collision_masks = {}
for base, vars in pairs(variations) do
  collision_masks[base] = prototypes.entity[vars[0]].collision_mask
end

-- update PEREL conneciton categories for 00 entities and pipes
for base, set in pairs(variations) do
  perel.set_entity_connection_categories(set[0], perel.get_entity_connection_categories(prototypes.entity[set[1]]))
  perel.set_entity_connection_categories(base, perel.get_entity_connection_categories(prototypes.entity[set[1]]))
end

---@class ParallelPipingStorage
---@field pre_built_data {[PlayerIdentification]: {fluid: Fluid?, health: float?, entity_name: string?, tick: MapTick?}?}
---@field previous {[PlayerIdentification]: LuaEntity?}
storage = {} --[[@as ParallelPipingStorage]]

script.on_init(function()
  storage.pre_built_data = {}
  storage.previous = {}
end)

script.on_configuration_changed(function()
  storage.pre_built_data = storage.pre_built_data or {}
  storage.previous = storage.previous or {}
end)

--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive|EventData.on_cancelled_deconstruction
local function on_built(event)
  local player = event.player_index and game.get_player(event.player_index)
  local this = event.entity
  local pre_built_data = player and storage.pre_built_data[player.index] or {}
  local prev = player and storage.previous[player.index]
  if player then
    storage.previous[player.index] = this
  end
  local prev_name = prev and prev.valid and (prev.name == "entity-ghost" and prev.ghost_name or prev.name)
  local this_prototype = this.name == "entity-ghost" and this.ghost_prototype or this.prototype ---@cast this_prototype LuaEntityPrototype
  local this_name = this_prototype.name
  local this_base = base_pipe[this_name]
  local this_mask = bitmasks[this_name]

  local surface = this.surface
  if this_mask then -- already a custom pipe variation

    -- just placed a blueprint, convert to normal
    if this.type == "entity-ghost" and this.ghost_type == "storage-tank" or this.type == "storage-tank" then
      -- placeholder variation, convert
      ---@diagnostic disable-next-line: undefined-field
      local mask = tank_to_pipe[this_mask][this.direction]
      local new_name = variations[this_base][mask]
      local new_entity = surface.create_entity{
        name = this.name == "entity-ghost" and "entity-ghost" or new_name,
        ghost_name = this.name == "entity-ghost" and new_name or nil,
        position = this.position,
        quality = this.quality,
        force = this.force,
        create_build_effect_smoke = false,
        raise_built = true
      }
      this.destroy()
      if player then
        storage.previous[player.index] = new_entity
      end
      return
    end

    -- already a variation, do no more work
    return
  end

  if not player then
    -- no player agency means make as many connections as possible (some mod or something created this)
    -- TODO fill in
  end

  local existing_name = pre_built_data.entity_name
  local new_var = existing_name and bitmasks[existing_name] or 0

  -- check if this entity can exist here, otherwise the player might be making a connection
  local can_place = existing_name and true or this_base and surface.can_place_entity{
    name = variations[this_base][0],
    position = this.position,
    force = this.force,
  }
  -- if this is a ghost, make sure it doesn't collide with other ghosts when built
  if can_place and this.type == "entity-ghost" then
    for _, ghost in pairs(surface.find_entities_filtered{
      type = "entity-ghost",
      position = this.position,
      force = this.force
    }) do
      if ghost ~= this then
        for layer in pairs(prototypes.entity[variations[this_base][0]].collision_mask.layers) do
          if ghost.ghost_prototype.collision_mask.layers[layer] then
            can_place = false
            break
          end
        end
        if not can_place then break end
      end
    end
  end

  local new_prev_var
  local prev_base
  local prev_fluid ---@cast prev_fluid Fluid?
  
  -- logic checks

  if prev and prev_name then
    -- previous pipe exists

    prev_base = base_pipe[prev_name]

    if prev_base then
      -- prev is a pipe

      local connect = false
      local prev_var = bitmasks[prev_name]
      local prev_variations = prev_base and variations[prev_base]
      local prev_prototype = prototypes.entity[prev_name]

      local dx, dy = math.abs(this.position.x - prev.position.x), math.abs(this.position.y - prev.position.y)
      local dist = (math.ceil(perel.get_side_length(this_prototype)) + math.ceil(perel.get_side_length(prev_prototype))) / 2

      -- distance based checks 
      if math.max(dx, dy) > dist then goto continue end
      -- possible to connect, check if possible

      if can_place then
        -- looking to see if the pipes can connect

        -- check fluid compatibility
        local existing_fluid = pre_built_data.fluid
        prev_fluid = perel.get_fluid(prev)
        connect = not existing_fluid or not prev_fluid or existing_fluid.name == prev_fluid.name
        if not connect then goto continue end
        -- no need to check categories if the fluids are incompatible

        -- ensure categories are compatible
        if base_pipe[existing_name or this_name] == prev_base then
          -- of the same time, so they're garunteed to be compatible
          connect = true
        else

          local this_categories = perel.get_entity_connection_categories(prototypes.entity[variations[base_pipe[existing_name or this_name]][1]])
          for prev_category in pairs(perel.get_entity_connection_categories(prototypes.entity[prev_variations[1]])) do
            if this_categories[prev_category] then
              connect = true
              goto continue
            end
          end

        end

      else
        -- looking to see if prev can connect to this non-pipe entity

        for _, existing_entity in pairs(surface.find_entities_filtered{position = this.position, force = this.force}) do
          if existing_entity == this then goto skip end

          for i, fluidbox in pairs(perel.get_possible_fluidbox_neighbours_by_fluidbox_and_connection(existing_entity)) do
            for j, connection in pairs(fluidbox) do
              for _, neighbour in pairs(connection) do
                if neighbour == prev then goto skip2 end
                
                -- check fluid compatibility
                local existing_fluid = perel.get_fluid(existing_entity, i)
                prev_fluid = perel.get_fluid(prev)
                connect = not existing_fluid or not prev_fluid or existing_fluid.name == prev_fluid.name

                goto continue

                ::skip2::
              end
            end
          end

          ::skip::
        end
      end

      ::continue::

      if connect then
        new_prev_var = bit32.bor(prev_var, 2 ^ (perel.get_direction(prev.position, this.position) / 4))
        new_var = bit32.bor(new_var, 2 ^ (perel.get_direction(this.position, prev.position) / 4))
        goto update
      end

    else
      -- prev is not a pipe

      for i, fluidbox in pairs(perel.get_possible_fluidbox_neighbours_by_fluidbox_and_connection(prev)) do
        for j, connection in pairs(fluidbox) do
          for _, neighbour in pairs(connection) do
            if neighbour ~= this then goto skip2 end
            -- the connections line up, now make sure they are compatible

            -- check fluid compatibility
            local existing_fluid = perel.get_fluid(prev, i)
            prev_fluid = perel.get_fluid(prev)
            if not existing_fluid or not prev_fluid or existing_fluid.name == prev_fluid.name then
              new_var = bit32.bor(new_var, 2 ^ (perel.get_direction(this.position, prev.position) / 4))
            end

            goto update

            ::skip2::
          end
        end
      end

    end
  end

  ::update:: -- actually update the relevant entities

  -- if not can_place and new_var > 0 then
  --   local new_name = variations[this_base][new_var]
  --   can_place = surface.can_fast_replace{
  --     name = this.name == "entity-ghost" and "entity-ghost" or new_name,
  --     ghost_name = this.name == "entity-ghost" and new_name or nil,
  --     position = this.position,
  --     force = this.force
  --   }
  -- end

  if can_place then
    -- able to place, update variation

    local health = pre_built_data.health or this.health
    -- local fluid = pre_built_data.fluid
    -- if fluid then
    --   fluid.amount = fluid.amount + (prev_fluid and prev_fluid.amount or 0)
    -- end

    local new_name = variations[this_base][new_var]
    local new_entity = surface.create_entity{
      name = this.name == "entity-ghost" and "entity-ghost" or new_name,
      ghost_name = this.name == "entity-ghost" and new_name or nil,
      position = this.position,
      quality = this.quality,
      force = this.force,
      create_build_effect_smoke = false,
      raise_built = true
    }

    if this then this.destroy() end

    if health then new_entity.health = health end
    -- if fluid then new_entity.set_fluid(1, fluid) end
    if player then storage.previous[player.index] = new_entity end

  elseif this_base then
    -- unable to place

    if this.name ~= "entity-ghost" then
      -- return to cursor/inventory

      if player and player.cursor_stack and player.cursor_stack.valid_for_read then
        player.cursor_stack.count = player.cursor_stack.count + 1
      elseif player and event.consumed_items and player.cursor_stack and (player.is_cursor_empty() or player.cursor_ghost and player.cursor_ghost.name.name == event.consumed_items[1].name) then
        -- just placed last item, put it back
        player.cursor_stack.transfer_stack(event.consumed_items[1])
      end
    end
    
    if player then
      -- update what the previous entity is

      for _, filters in pairs{
        {
          position = this.position,
          force = this.force,
          collision_mask = prototypes.entity[variations[this_base][0]].collision_mask.layers
        },
        { -- even more basic check, ignore collision mask requirement (compound entities, etc)
          position = this.position,
          force = this.force,
        }
      } do for _, entity in pairs(surface.find_entities_filtered(filters)) do

        local prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
        if #prototype.fluidbox_prototypes ~= 0 then
          storage.previous[player.index] = entity
          goto update_prev
        end

      end end

    end

    this.destroy()
  end

  ::update_prev::

  if prev_base and new_prev_var then

    local health = prev.health
    -- local fluid = pre_built_data.fluid
    -- if fluid then
    --   fluid.amount = fluid.amount + (prev_fluid and prev_fluid.amount or 0)
    -- end

    
    local new_name = variations[prev_base][new_prev_var]
    local new_entity = surface.create_entity{
      name = prev.name == "entity-ghost" and "entity-ghost" or new_name,
      ghost_name = prev.name == "entity-ghost" and new_name or nil,
      position = prev.position,
      quality = prev.quality,
      force = prev.force,
      create_build_effect_smoke = false,
      raise_built = true
    }

    if prev then prev.destroy() end

    if health then new_entity.health = health end
    -- if fluid then new_entity.set_fluid(1, fluid) end

  end
end

script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.on_robot_built_entity, on_built, event_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_built, event_filter)
script.on_event(defines.events.script_raised_built, on_built, event_filter)
script.on_event(defines.events.script_raised_revive, on_built, event_filter)

---@param event EventData.on_pre_build
script.on_event(defines.events.on_pre_build, function(event)
  ---@type LuaEntity?
  local prev = storage.previous[event.player_index]
  local build_data = {tick = game.tick}

  storage.pre_built_data[event.player_index] = build_data

  local player = game.get_player(event.player_index)
  local place_result = player.cursor_ghost and player.cursor_ghost.name.place_result or
    player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.prototype.place_result or nil

  if not place_result or place_result.type ~= "pipe" then return end

  local position = event.position
  local mask = prototypes.entity[variations[place_result.name][0]].collision_mask.layers.object and "object" or "tomwub-underground"

  local entity = player.surface.find_entities_filtered{
    type = "pipe",
    position = position,
    force = player.force,
    collision_mask = mask
  }[1]

  local ghost

  for _, e in pairs(player.surface.find_entities_filtered{
    type = "entity-ghost",
    ghost_type = "pipe",
    position = position,
    force = player.force
  }) do
    if e.ghost_prototype.collision_mask.layers[mask] then
      ghost = e
      break
    end
  end

  if entity or ghost then

    build_data.entity_name = entity and entity.name or ghost.ghost_name

    local this_fluid = entity and perel.get_fluid(entity)

    if this_fluid and prev and prev.valid and prev.name ~= "entity-ghost" then

      local prev_fluid = perel.get_fluid(prev)

      -- only check validity if we're attempting to mix fluids
      if this_fluid and prev_fluid and this_fluid.name ~= prev_fluid.name then

        local dx, dy = math.abs(entity.position.x - prev.position.x), math.abs(entity.position.y - prev.position.y)
        local dist = (
          ---@diagnostic disable-next-line: param-type-mismatch
          math.ceil(perel.get_side_length(entity.name == "entity-ghost" and entity.ghost_prototype or entity.prototype)) +
          ---@diagnostic disable-next-line: param-type-mismatch
          math.ceil(perel.get_side_length(prev.name == "entity-ghost" and prev.ghost_prototype or prev.prototype))
        ) / 2

        if dx ~= dy and math.max(dx, dy) == dist then
          -- entities will be connected, so prevent this

          player.create_local_flying_text{
            text = {"action-leads-to-fluid-mixing"},
            create_at_cursor = true
          } -- notify

          entity.surface.create_entity{
            name = "parallel-piping-blockage",
            position = entity.position
          } -- block placement

          return

        end
      end
    end

    if entity and event.build_mode == defines.build_mode.normal then
      -- no mixing will happen, update fluid count

      build_data.fluid = this_fluid
      build_data.health = entity.health

      entity.destroy()

    end
  end
  if entity and (event.build_mode ~= defines.build_mode.normal or player.controller_type == defines.controllers.remote) then

    -- mimic normal build event
    build_data.fluid = perel.get_fluid(entity)
    build_data.health = entity.health

    ---@diagnostic disable-next-line: inject-field
    event.entity = entity.surface.create_entity{
      name = base_pipe[entity.name],
      position = entity.position,
      quality = entity.quality,
      force = entity.force,
      create_build_effect_smoke = false
    }

    entity.destroy();

    ---@diagnostic disable-next-line: param-type-mismatch
    on_built(event)

  end
end)

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
local function on_destroyed(event)
  if event.player_index and storage.pre_built_data[event.player_index].tick == event.tick then
    storage.pre_built_data[event.player_index].tick = nil
    return -- early return for fast-replace events
  end
  -- something got removed, disconnect neighbours
  local entity = event.entity
  local player = event.player_index and game.get_player(event.player_index)
  local surface = entity.surface
  local stack = player and player.undo_redo_stack
  local blueprint = stack and stack.get_undo_item_count() > 0 and #stack.get_undo_item(1) ~= 1
  if blueprint then -- multiple items (blueprint or otherwise) do complicated checks
    local i = perel.find_build_action(stack.get_undo_item(1), entity)
    -- if i then stack.remove_undo_action(1, i) end
  end
  ---@type Fluid[]
  local fluid_target_thresholds = {}
  -- for i = 1, entity.fluids_count do
  --   local fluid = entity.get_fluid(i)
  --   if fluid then
  --     local segment = entity.get_fluid_segment_fluid(1)
  --     local amount = segment and segment.amount or fluid.amount
  --     local total_capacity = entity.get_fluid_segment_capacity(i)
  --     local this_capacity = entity.get_fluid_capacity(i)
  --     if total_capacity ~= this_capacity then
  --       fluid.amount = amount / (total_capacity - this_capacity)
  --       fluid_target_thresholds[i] = fluid
  --     end
  --   end
  -- end
  -- ---@type PipeConnection[][]
  -- local fluid_targets = {}
  -- for i, fluidbox in pairs(perel.get_fluidbox_targets_by_fluidbox_and_connection(entity, true, true)) do
  --   fluid_targets[i] = {}
  --   for _, tuple in pairs(fluidbox) do
  --     local neighbour = tuple.target --[[@as LuaEntity]]
  --     local mask = bitmasks[neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name]
  --     local b2 = base_pipe[neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name]
  --     local bit = 2 ^ (perel.get_direction(neighbour.position, entity.position) / 4)
  --     fluid_targets[i][#fluid_targets[i]+1] = tuple
  --     if mask and b2 and bit32.btest(mask, bit) and not neighbour.to_be_deconstructed() then
  --       ---@diagnostic disable-next-line: assign-type-mismatch
  --       mask = mask - bit
  --       local build_index, build_action = perel.find_build_item(stack, neighbour)
  --       local health = neighbour.health
  --       local marked = neighbour.to_be_deconstructed()
  --       ---@diagnostic disable-next-line: param-type-mismatch
  --       local new_neighbour = surface.create_entity{
  --         name = neighbour.name == "entity-ghost" and "entity-ghost" or variations[b2][mask],
  --         ghost_name = neighbour.name == "entity-ghost" and variations[b2][mask] or nil,
  --         position = neighbour.position,
  --         quality = neighbour.quality,
  --         force = neighbour.force,
  --         player = build_index and player.index or nil,
  --         undo_index = build_index,
  --         create_build_effect_smoke = false,
  --         raise_built = true
  --       }
  --       neighbour.destroy()
  --       ---@diagnostic disable-next-line: param-type-mismatch
  --       if build_index then stack.remove_undo_action(build_index, build_action) end
  --       if health then new_neighbour.health = health end
  --       if marked then new_neighbour.order_deconstruction(new_neighbour.force) end
  --       ---@diagnostic disable-next-line: missing-fields
  --       fluid_targets[i][#fluid_targets[i]] = {target = new_neighbour, target_fluidbox_index = 1} -- update fluid distribution target
  --     end
  --   end
  -- end

  -- -- evenly distribute fluid
  -- for i, fluid in pairs(fluid_target_thresholds) do
  --   local fill_percent = fluid.amount
  --   for _, tuple in pairs(fluid_targets[i] or {}) do
  --     ---@cast tuple {target: LuaEntity, target_fluidbox_index: int, target_pipe_connection_index: int}
  --     fluid.amount = fill_percent * tuple.target.get_fluid_capacity(tuple.target_fluidbox_index)
  --     if fluid.amount > 0 then
  --       -- tuple.target.set_fluid(tuple.target_fluidbox_index, fluid)
  --     end
  --   end
  -- end
end

script.on_event(defines.events.on_player_mined_entity, on_destroyed)
script.on_event(defines.events.on_robot_mined_entity, on_destroyed)
script.on_event(defines.events.on_space_platform_mined_entity, on_destroyed)
script.on_event(defines.events.script_raised_destroy, on_destroyed)
script.on_event(defines.events.on_entity_died, on_destroyed)

---@param event EventData.on_cancelled_deconstruction
script.on_event(defines.events.on_cancelled_deconstruction, function (event)
  local entity = event.entity
  local prototype = entity.name == "entity-ghost" and entity.ghost_prototype or entity.prototype
  local base = base_pipe[prototype.name]
  if not base then return end
  local mask = bitmasks[prototype.name]
  local new_mask = 0
  local player = event.player_index and game.get_player(event.player_index)
  local stack = player and player.undo_redo_stack
  local surface = entity.surface
  for _, neighbour in pairs(perel.get_fluidbox_neighoburs(entity)) do
    ---@diagnostic disable-next-line: assign-type-mismatch
    new_mask = new_mask + 2 ^ (perel.get_direction(entity.position, neighbour.position) / 4)
  end
  if mask == new_mask then return end
  -- something was removed, replace this entity
  local build_index, build_action = perel.find_build_item(stack, entity)
  local health = entity.health
  local fluid = entity.get_fluid(1)
  if fluid then
    local segment = entity.get_fluid_segment_fluid(1)
    fluid.amount = segment and segment.amount or fluid.amount
  end
  local params = {
    name = entity.name == "entity-ghost" and "entity-ghost" or variations[base][mask],
    ghost_name = entity.name == "entity-ghost" and variations[base][mask] or nil,
    position = entity.position,
    quality = entity.quality,
    force = entity.force,
    player = build_index and player.index or nil,
    undo_index = build_index,
    create_build_effect_smoke = false,
    raise_built = true
  }
  entity.destroy()
  ---@diagnostic disable-next-line: param-type-mismatch
  local new_entity = surface.create_entity(params)
  ---@diagnostic disable-next-line: param-type-mismatch
  if build_index then stack.remove_undo_action(build_index, build_action) end
  if health then new_entity.health = health end
  -- if fluid then new_entity.set_fluid(1, fluid) end
end)

script.on_event(defines.events.on_player_setup_blueprint, function (event)
	local player = game.get_player(event.player_index)
	local blueprint = player.blueprint_to_setup
  -- if normally invalid
  ---@diagnostic disable-next-line: assign-type-mismatch
	if not blueprint or not blueprint.valid_for_read then blueprint = player.cursor_stack end
  -- if non existant, cancel
  local entities = blueprint and blueprint.get_blueprint_entities()
  if not entities then return end
  local changed = false
  -- update entities
  for _, entity in pairs(entities) do
    if base_pipe[entity.name] then
      changed = true
      ---@diagnostic disable-next-line: undefined-field
      local variation = pipe_to_tank[bitmasks[entity.name]]
      ---@diagnostic disable-next-line: undefined-field
      entity.name = tank_variations[base_pipe[entity.name]][variation.mask]
      entity.direction = variation.direction
    end
  end
  if not changed then return end -- make no changes unless required
  blueprint.set_blueprint_entities(entities)
end)