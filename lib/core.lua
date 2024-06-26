
-- base1 modulo
function mod1(v, m)
  return ((v - 1) % m) + 1
end

-- continuous version of `mod1`
function mod1_smooth(v, m)
  local v_mod = mod1(v, math.floor(m))
  local m_ceil = math.ceil(m)
  local v_ceil = mod1(v, m_ceil)
  if v_ceil == m_ceil then
    return util.linlin(0, v_ceil, 0, m, v_ceil)
  end
  return v_mod
end

function offness(v, prev_v, next_v)
  local prev_delta = math.abs(v - prev_v)
  local next_delta = math.abs(next_v - v)

  if v == prev_v or v == next_v then
    return 0.0
  end

  if prev_delta < next_delta then
    return prev_delta / ((next_v - prev_v)/2)
  else
    return next_delta / ((next_v - prev_v)/2)
  end
end


-- -------------------------------------------------------------------------
-- string

function string_ends(s, ending)
  return s:sub(-#ending) == ending
end

-- -------------------------------------------------------------------------
-- 2d folding

  function index_to_coords(i, nb_rows)
  local y = mod1_smooth(i, nb_rows)
  local x = (i - y) / nb_rows + 1
  return x, y
end

function coords_to_index(x, y, nb_rows)
    if nb_rows == 1 then
        return x
    end
    return (x - 1) * nb_rows + y
end

-- -------------------------------------------------------------------------
-- tables

-- remove all element of table without changing its memory pointer
function tempty(t)
  for k, v in pairs(t) do
    t[k] = nil
  end
end
