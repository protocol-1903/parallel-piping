require "__perel__.util.scripts.general"
require "__perel__.util.scripts.fluids"

local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")
local base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
local variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")

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

local entities = {}

-- replace with pipes with all connections
for _, surface in pairs(game.surfaces) do
  for _, type in pairs{"ghost_type", "type"} do
    for _, entity in pairs(surface.find_entities_filtered{[type] = "pipe"}) do
      if entity.valid then
        local base = base_pipe[entity.name == "entity-ghost" and entity.ghost_name or entity.name]
        local fluid = entity.fluidbox[1]
        if fluid then
          local amount = entity.fluidbox.get_fluid_segment_contents(1)
          fluid.amount = amount and amount[fluid.name] or fluid.amount
        end
        local params = {
          name = entity.name == "entity-ghost" and "entity-ghost" or variations[base][15],
          ghost_name = entity.name == "entity-ghost" and variations[base][15] or nil,
          position = entity.position,
          quality = entity.quality,
          force = entity.force
        }
        entities[#entities+1] = {
          health = entity.health,
          marked = entity.to_be_deconstructed()
        }
        entity.fluidbox[1] = nil
        entity.destroy()
        local new_entity = surface.create_entity(params)
        if fluid then
          local amount = new_entity.fluidbox.get_fluid_segment_contents(1)
          fluid.amount = fluid.amount + (amount and amount[fluid.name] or 0)
        end
        new_entity.fluidbox[1] = fluid
        entities[#entities].entity = new_entity
      end
    end
  end
end

for _, tuple in pairs(entities) do
  local entity = tuple.entity
  local health = tuple.health
  local fluid = entity.fluidbox[1]
  if fluid then
    local amount = entity.fluidbox.get_fluid_segment_contents(1)
    fluid.amount = amount and amount[fluid.name] or fluid.amount
  end
  entity.fluidbox[1] = nil
  local marked = tuple.marked
  local surface = entity.surface
  local base = base_pipe[entity.name == "entity-ghost" and entity.ghost_name or entity.name]
  local mask = perel.get_pipe_connection_bitmask(entity)
  local params = {
    name = entity.name == "entity-ghost" and "entity-ghost" or variations[base][mask],
    ghost_name = entity.name == "entity-ghost" and variations[base][mask] or nil,
    position = entity.position,
    quality = entity.quality,
    force = entity.force,
    create_build_effect_smoke = false,
  }
  entity.destroy()
  local new_entity = surface.create_entity(params)
  if health then new_entity.health = health end
  if marked then new_entity.order_deconstruction(new_entity.force) end
  if fluid then new_entity.fluidbox[1] = fluid end
end