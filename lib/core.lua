
-- base1 modulo
function mod1(v, m)
  return ((v - 1) % m) + 1
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
