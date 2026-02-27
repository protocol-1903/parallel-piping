require "util"

for _, surface in pairs(game.surfaces) do
  for _, type in pairs{"ghost_type", "type"} do
    for _, entity in pairs(surface.find_entities_filtered{[type] = "pipe"}) do
      if entity.valid then
        local base = xu.base_pipe[entity.name == "entity-ghost" and entity.ghost_name or entity.name]
        local mask = 0
        local prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
        local force = entity.force
        for bit, offset in pairs(xu.directional_offsets) do
          local position = {
            entity.position.x + offset.x,
            entity.position.y + offset.y
          }
          ---@type LuaEntity
          local neighbour
          for _, e in pairs(surface.find_entities_filtered{
            position = position,
            force = force,
          }) do
            for _, category in pairs(xu.get_categories(e.name == "entity-ghost" and e.ghost_name or e.name)) do
              xu.update_connectables(category)
              if xu.connectables[category][prototype.name] then
                neighbour = e
                break
              end
            end
            if neighbour then break end
          end
          if neighbour then
            if xu.base_pipe[neighbour.name == "entity-ghost" and neighbour.ghost_name or neighbour.name] then
              mask = mask + 2 ^ (bit - 1)
            else
              for _, n2 in pairs(xu.get_pipe_neighoburs(neighbour)) do
                if entity.unit_number == n2.unit_number then
                  mask = mask + 2 ^ (bit - 1)
                  break
                end
              end
            end
          end
        end
        local health = entity.health
        local marked = entity.to_be_deconstructed()
        local fluid = entity.fluidbox[1]
        if fluid then
          local amount = entity.fluidbox.get_fluid_segment_contents(1)
          fluid.amount = amount[fluid.name]
        end
        local params = {
          name = entity.name == "entity-ghost" and "entity-ghost" or xu.variations[base][mask],
          ghost_name = entity.name == "entity-ghost" and xu.variations[base][mask] or nil,
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