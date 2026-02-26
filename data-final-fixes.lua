-- local new_pipes = {}
-- for name, pipe in pairs(data.raw.pipe) do
--   local pipe_connections = pipe.fluid_box.pipe_connections
--   pipe.fluid_box.pipe_connections = {}

--   for i = 0, 15 do
--     local new = table.deepcopy(pipe)
--     new.type = "pipe"
--     new.name = string.format("%s-pp-%02d", name, i)
--     new.placeable_by = new.placeable_by or {item = name, count = 1}

--     local connections = new.fluid_box.pipe_connections
--     for j = 0, 3 do
--       if bit32.btest(i, 2^j) then
--         connections[#connections+1] = pipe_connections[j+1]
--       end
--     end

--     new_pipes[#new_pipes+1] = new
--   end

--   pipe.collision_mask = {layers = {}}
-- end

-- data:extend(new_pipes)

local base_pipe, variations, bitmasks = {}, {}, {}

local blacklist = {}

--[[
NORTH VERSIONS:
  o - pipe connection
  x - blocked
NOTHINGBURGER:
  x
 x x
  x
ENDING:
  x
 x x
  o
STRAIGHT:
  o
 x x
  o
CORNER:
  x
 x o
  o
JUNCTION:
  x
 o o
  o
CROSS:
  o
 o o
  o
]]

-- TODO link pipes and tanks

-- collect all connection categories before we add new things to index
-- local categories = {default = true}
-- for _, prototypes in pairs {
--   "pump",
--   "storage-tank",
--   "assembling-machine",
--   "furnace",
--   "boiler",
--   "fluid-turret",
--   "mining-drill",
--   "offshore-pump",
--   "generator",
--   "fusion-generator",
--   "fusion-reactor",
--   "thruster",
--   "inserter",
--   "agricultural-tower",
--   "lab",
--   "radar",
--   "reactor",
--   "loader",
--   "valve",
--   "pipe",
--   "pipe-to-ground"
-- } do for _, prototype in pairs(data.raw[prototypes] or {}) do
--   local fluid_boxes = {}
--   -- multiple fluid_boxes
--   for _, fluid_box in pairs(prototype.fluid_boxes or {}) do
--     fluid_boxes[#fluid_boxes + 1] = fluid_box
--   end
--   fluid_boxes[#fluid_boxes + 1] = prototype.fluid_box
--   fluid_boxes[#fluid_boxes + 1] = prototype.input_fluid_box
--   fluid_boxes[#fluid_boxes + 1] = prototype.output_fluid_box
--   fluid_boxes[#fluid_boxes + 1] = prototype.fuel_fluid_box
--   fluid_boxes[#fluid_boxes + 1] = prototype.oxidizer_fluid_box
--   fluid_boxes[#fluid_boxes + 1] = prototype.energy_source and prototype.energy_source.fluid_box or nil
--   for _, fluid_box in pairs(fluid_boxes) do
--     for _, pipe_connection in pairs(fluid_box.pipe_connections) do
--       for _, connection_category in pairs(type(pipe_connection.connection_category) == "table" and pipe_connection.connection_category or {pipe_connection.connection_category}) do
--         categories[connection_category] = true
--       end
--     end
--   end
-- end end

-- local connection_categories = {}
-- for category in pairs(categories) do
--   connection_categories[#connection_categories+1] = category
-- end

for p, prototype in pairs(data.raw.pipe) do
  if prototype.ignore_by_parallel_piping or blacklist[p] or #prototype.fluid_box.pipe_connections ~= 4 then
    prototype.ignore_by_parallel_piping = nil
    blacklist[p] = true
  else
    base_pipe[p] = p
    variations[p] = {}
    -- sort pipe connections to north, south, east, west
    local pipe_connections = prototype.fluid_box.pipe_connections
    for _, connection in pairs(pipe_connections) do
      connection.flow_direction = "input-output"
      prototype.fluid_box.pipe_connections[connection.direction/4+1] = connection
    end
  end
end

for _, prototype in pairs(data.raw["pipe-to-ground"]) do
  prototype.fast_replaceable_group = nil
end

for _, prototype in pairs(data.raw["infinity-pipe"]) do
  prototype.fast_replaceable_group = nil
end

local new_entities = {}

for p, prototype in pairs(data.raw.pipe) do
  if variations[p] then
    prototype.placeable_by = prototype.placeable_by or {item = p, count = 1}
    prototype.fast_replaceable_group = p
    -- prototype.collision_mask = prototype.collision_mask or {layers = {}}
    local pipe_connections = prototype.fluid_box.pipe_connections
    prototype.fluid_box.pipe_connections = {}
    -- create variations for in-world manipulation
    for i = 0, 15 do
      local pipe = util.table.deepcopy(prototype)
			pipe.name = string.format("%s-pp-%02d", p, i)
			pipe.localised_name = prototype.localised_name or {"entity-name." .. p}
			pipe.localised_description = prototype.localised_description or {"entity-description." .. p}
      -- pipe.collision_mask.layers["parallel-piping-connectable"] = true
			pipe.build_sound = nil
      pipe.created_smoke = nil
      pipe.placeable_by = prototype.placeable_by or {item = p, count = 1}
      pipe.hidden = true
      pipe.hidden_in_factoriopedia = true
      local connections = pipe.fluid_box.pipe_connections
      for j = 0, 3 do
        connections[#connections+1] = bit32.btest(i, 2^(j)) and pipe_connections[j+1] or nil
      end
      new_entities[#new_entities+1] = pipe
      base_pipe[pipe.name] = p
      variations[p][i] = pipe.name
      bitmasks[pipe.name] = i
    end
    -- create variations for blueprints
    for suffix, metadata in pairs{
      nothingburger = {
        pictures = {
          north = "straight_vertical_single",
          east = "straight_vertical_single",
          south = "straight_vertical_single",
          west = "straight_vertical_single"
        },
        pipe_connections = {}
      },
      ending = {
        pictures = {
          north = "ending_down",
          east = "ending_left",
          south = "ending_up",
          west = "ending_right"
        },
        pipe_connections = {3}
      },
      straight = {
        pictures = {
          north = "straight_vertical",
          east = "straight_horizontal",
          south = "straight_vertical",
          west = "straight_horizontal"
        },
        pipe_connections = {1, 3}
      },
      corner = {
        pictures = {
          north = "corner_down_right",
          east = "corner_down_left",
          south = "corner_up_left",
          west = "corner_up_right"
        },
        pipe_connections = {2, 3}
      },
      junction = {
        pictures = {
          north = "t_down",
          east = "t_left",
          south = "t_up",
          west = "t_right"
        },
        pipe_connections = {2, 3, 4}
      },
      cross = {
        pictures = {
          north = "cross",
          east = "cross",
          south = "cross",
          west = "cross"
        },
        pipe_connections = {1, 2, 3, 4}
      }
    } do
      ---@type data.StorageTankPrototype
      local tank = table.deepcopy(prototype)
      tank.type = "storage-tank"
			tank.name = p .. "-pp-" .. suffix
			tank.localised_name = prototype.localised_name or {"entity-name." .. p}
			tank.localised_description = prototype.localised_description or {"entity-description." .. p}
      -- tank.collision_mask = {layers = {}}
			tank.build_sound = nil
      tank.created_smoke = nil
      tank.window_bounding_box = {{0,0},{0,0}}
      tank.show_fluid_icon = false
      tank.pictures = {}
      tank.fluid_box.pipe_connections = {}
      tank.flow_length_in_ticks = 1
      tank.hidden = true
      tank.hidden_in_factoriopedia = true
      for _, index in pairs(metadata.pipe_connections) do
        tank.fluid_box.pipe_connections[#tank.fluid_box.pipe_connections+1] = pipe_connections[index]
      end
      for variation, alt in pairs{
        picture = "",
        frozen_patch = feature_flags.freezing and "_frozen" or nil,
      } do for direction, index in pairs(metadata.pictures) do
        tank.pictures[variation] = tank.pictures[variation] or {}
        tank.pictures[variation][direction] = prototype.pictures[index .. alt]
      end end
      new_entities[#new_entities+1] = tank
      base_pipe[tank.name] = p
      variations[p][suffix] = tank.name
      bitmasks[tank.name] = suffix
    end
    -- ensure at least one connection even if its not useable
    prototype.fluid_box.pipe_connections = {{
      connection_type = "linked",
      linked_connection_id = 1
    }}
    prototype.collision_mask = {layers = {out_of_map = true}}
    -- prototype.fluid_box.pipe_connections = pipe_connections
    -- data.raw.item[p].place_result = p .. "-pp-tester"
    -- base_pipe[p .. "-pp-tester"] = p
    -- util entity to test for connections (need apply graphics still)
    -- new_entities[#new_entities + 1] = {
    --   name = p .. "-pp-tester",
    --   type = "assembling-machine",
    --   energy_usage = "1W",
    --   crafting_speed = 1,
    --   crafting_categories = {"crafting"},
    --   energy_source = {type = "void"},
    --   flags = {"not-in-made-in"},
    --   collision_mask = {layers = {}},
    --   collision_box = {{-0.5, -0.5}, {0.5, 0.5}},
    --   fluid_boxes_off_when_no_fluid_recipe = false,
    --   fluid_boxes = {
    --     {
    --       volume = 1,
    --       production_type = "input",
    --       pipe_connections = {prototype.fluid_box.pipe_connections[1]}
    --     },
    --     {
    --       volume = 1,
    --       production_type = "input",
    --       pipe_connections = {prototype.fluid_box.pipe_connections[2]}
    --     },
    --     {
    --       volume = 1,
    --       production_type = "input",
    --       pipe_connections = {prototype.fluid_box.pipe_connections[3]}
    --     },
    --     {
    --       volume = 1,
    --       production_type = "input",
    --       pipe_connections = {prototype.fluid_box.pipe_connections[4]}
    --     }
    --   },
    --   hidden = true,
    --   hidden_in_factoriopedia = true
    -- }
  end
end

data:extend(new_entities)

data:extend{
  {
    name = "parallel-piping",
    type = "mod-data",
    data = {
      base_pipe = base_pipe,
      variations = variations,
      bitmasks = bitmasks
    }
  },
  -- { -- collision mask for pipe type entities
  --   name = "parallel-piping-connectable",
  --   type = "collision-layer"
  -- },
  -- {
  --   type = "smoke-with-trigger",
  --   name = "piping-build-record",
  --   flags = {"placeable-off-grid"},
  --   duration = 3600, -- one minute
  --   movement_slow_down_factor = 0
  -- },
  {
    type = "custom-input",
    name = "piping-configure",
    linked_game_control = "build",
    key_sequence = ""
  },
  -- {
  --   type = "custom-input",
  --   name = "piping-build",
  --   linked_game_control = "build",
  --   key_sequence = ""
  -- },
  {
    name = "piping-rotate",
    type = "custom-input",
    linked_game_control = "rotate",
    key_sequence = ""
  },
  {
    name = "piping-reverse-rotate",
    type = "custom-input",
    linked_game_control = "reverse-rotate",
    key_sequence = ""
  }
}
