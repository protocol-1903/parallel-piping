-- update the force
for _, surface in pairs(game.surfaces) do
  for _, type in pairs{"ghost_type", "type"} do
    for _, entity in pairs(surface.find_entities_filtered{[type] = "pipe"}) do
      if entity.valid and entity.force.name == "enemy" then
        entity.force = "player"
      end
    end
  end
end