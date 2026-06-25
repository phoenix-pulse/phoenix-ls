package.path = "packages/nvim-plugin/lua/?.lua;packages/nvim-plugin/lua/?/init.lua;" .. package.path

package.preload["phoenix-pulse.lsp"] = function()
  return {}
end

vim = {
  split = function(value, sep, opts)
    local plain = opts and opts.plain
    local parts = {}
    local start = 1

    while true do
      local first, last = string.find(value, sep, start, plain)
      if not first then
        table.insert(parts, string.sub(value, start))
        return parts
      end

      table.insert(parts, string.sub(value, start, first - 1))
      start = last + 1
    end
  end,
  list_slice = function(values, first, last)
    local sliced = {}
    for index = first, last do
      table.insert(sliced, values[index])
    end
    return sliced
  end,
}

local erd = require("phoenix-pulse.erd")

local diagram = erd._generate_mermaid_code({
  {
    name = "App.Catalog.Product",
    tableName = "products",
    fields = {},
    associations = {
      {
        fieldName = "tags",
        targetModule = "App.Catalog.Tag",
        type = "many_to_many",
        cardinality = "many_to_many",
        joinThrough = "products_tags",
      },
    },
  },
  {
    name = "App.Catalog.Tag",
    tableName = "tags",
    fields = {},
    associations = {},
  },
})

if not string.find(diagram, 'products }o%-%-o{ tags : "many to many via products_tags"') then
  error("expected many-to-many join metadata in Mermaid relationship label", 2)
end
