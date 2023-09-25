
local colorutil = {}


-- ------------------------------------------------------------------------

function colorutil.scale(min_col, max_col, cursor)
  local r = min_col[1] + (max_col[1] - min_col[1]) * cursor
  local g = min_col[2] + (max_col[2] - min_col[2]) * cursor
  local b = min_col[3] + (max_col[3] - min_col[3]) * cursor
  return {r, g, b}
end


-- ------------------------------------------------------------------------

return colorutil
