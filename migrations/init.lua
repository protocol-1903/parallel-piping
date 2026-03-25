require "__perel__.util.scripts.general"
require "__perel__.util.scripts.fluids"

local mod_data = assert(prototypes.mod_data["parallel-piping"], "ERROR: mod-data for parallel-piping not found!")
local base_pipe = assert(mod_data.data.base_pipe, "ERROR: data.base_pipe for parallel-piping not found!")
local variations = assert(mod_data.data.variations, "ERROR: data.variations for parallel-piping not found!")

for _, surface in pairs(game.surfaces) do
  for _, type in pairs{"ghost_type", "type"} do
    for _, entity in pairs(surface.find_entities_filtered{[type] = "pipe"}) do
      if entity.valid then
        local base = base_pipe[entity.name == "entity-ghost" and entity.ghost_name or entity.name]
        local mask = perel.get_pipe_connection_bitmask(entity)
        local health = entity.health
        local marked = entity.to_be_deconstructed()
        local fluid = entity.fluidbox[1]
        if fluid then
          local amount = entity.fluidbox.get_fluid_segment_contents(1)
          fluid.amount = amount and amount[fluid.name] or fluid.amount
        end
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
    end
  end
end