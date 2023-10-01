-- wavematrix
-- @eigen.


-- -------------------------------------------------------------------------
-- deps

local script_dir
if norns then
  script_dir = norns.state.path
elseif seamstress then
  script_dir = seamstress.state.path .. "/"
end

local wavutils = include("lib/wavutils")
local colorutil = include("lib/colorutil")

local bleached = include("lib/bleached")

include("lib/core")


-- -------------------------------------------------------------------------
-- consts

DBG = true

FPS = 60

WAVE_H = 40

WAVE_PADDING_X = 2

SHIFT_FACTOR = 5

MAX_WAVES_DISPLAYED = 70

MAX_FOLDING_ROWS = 6


-- -------------------------------------------------------------------------
-- colors

COL_BG = {24, 34, 34}

COL_WAVE_FG = {111, 211, 111} -- green
COL_WAVE_FG_2 = {128, 0, 128} -- purple
COL_WAVE_BG = {244, 108, 108}
COL_WAVE_SELECTED = {50, 205, 50}
COL_WAVE_SELECTED_OFF = {255, 0, 0}


-- -------------------------------------------------------------------------
-- state

screen_dirty = true
screen_wavetable_dirty = true

fullscreen = false

mouse_x = 0
mouse_y = 0

has_bleached = false

wavetable = {}


-- -------------------------------------------------------------------------
-- wav parsing

function parse_wav_dir(dirpath)
  local filenames = util.scandir(dirpath)
  for _, filename in pairs(filenames) do
    if filename:sub(-#'.wav') == '.wav' then
      local filepath = dirpath .. filename
      local wave = wavutils.parse_wav(filepath)
      table.insert(wavetable, wave)
    end
  end
end


-- -------------------------------------------------------------------------
-- bleached

local function bleached_cc_cb(midi_msg)
  has_bleached = true

  local row = bleached.cc_to_row(midi_msg.cc)
  local pot = bleached.cc_to_row_pot(midi_msg.cc)
  local v = midi_msg.val

  if row == 1 and pot == 1 then
    params:set("wavetable_cursor_x", util.linlin(0, 127, 0, 1, v))
  elseif row == 1 and pot == 2 then
    params:set("wavetable_cursor_y", util.linlin(0, 127, 0, 1, v))
  elseif row == 2 and pot == 1 then
    params:set("wavetable_pos_shift", util.linlin(0, 127, 0, 1, v))
  elseif row == 2 and pot == 2 then
    params:set("wavetable_length", util.linlin(0, 127, 0, 1, v))
  elseif row == 2 and pot == 3 then
    params:set("wavetable_fold", util.linlin(0, 127, 0, 1, v))
  elseif row == 2 and pot == 4 then
    params:set("wave_phase_shift_amount", util.linlin(0, 127, 0, 1, v))
  end
end


-- -------------------------------------------------------------------------
-- params

local function format_percent(param)
  local value = param:get()
  return string.format("%.2f", value * 100) .. "%"
end


-- -------------------------------------------------------------------------
-- init

local clock_redraw

function init()
  -- screen.set_size(512, 128)

  bleached.init(bleached_cc_cb)

  local pct_control_off = controlspec.new(0, 1, "lin", 0, 0.0, "")
  local pct_control_on = controlspec.new(0, 1, "lin", 0, 1.0, "")

  params:add{type = "control", id = "wavetable_length", name = "wavetable length", controlspec = pct_control_on, formatter = format_percent}
  params:set_action("wavetable_length", function (_v)
                      screen_wavetable_dirty = true
                      screen_dirty = true
  end)
  params:add{type = "control", id = "wavetable_pos_shift", name = "wavetable shift", controlspec = pct_control_off, formatter = format_percent}
  params:set_action("wavetable_pos_shift", function (_v)
                      screen_wavetable_dirty = true
                      screen_dirty = true
  end)
  params:add{type = "control", id = "wavetable_cursor_x", name = "wavetable cursor x", controlspec = pct_control_off, formatter = format_percent}
  params:set_action("wavetable_cursor_x", function (_v)
                      screen_dirty = true
  end)
  params:add{type = "control", id = "wavetable_cursor_y", name = "wavetable cursor y", controlspec = pct_control_off, formatter = format_percent}
  params:set_action("wavetable_cursor_y", function (_v)
                      screen_dirty = true
  end)
  params:add{type = "control", id = "wavetable_fold", name = "wavetable folding", controlspec = pct_control_off, formatter = format_percent}
  params:set_action("wavetable_fold", function (_v)
                      screen_wavetable_dirty = true
                      screen_dirty = true
  end)
  params:add{type = "control", id = "wave_phase_shift_amount", name = "wave phase shift", controlspec = pct_control_off, formatter = format_percent}
  params:set_action("wave_phase_shift_amount", function (_v)
                      screen_wavetable_dirty = true
                      screen_dirty = true
  end)

  parse_wav_dir(script_dir.."/waveforms/")

  clock_redraw = clock.run(function()
      while true do
        clock.sleep(1/FPS)
        if screen_dirty then
          redraw()
        end
      end
  end)
end


screen.mouse = function(x, y)
  mouse_x, mouse_y = x, y

  local _, screen_h = screen.get_size()
  local wavetable_w = screen_h * 3/4
  local wave_margin_y = (screen_h - wavetable_w)/2 + (WAVE_H/2)
  if mouse_y >= wave_margin_y
    and mouse_y <= screen_h - wave_margin_y then
    screen_wavetable_dirty = true
    screen_dirty = true
  end

  -- if not has_bleached then
  --   local _, screen_h = screen.get_size()
  --   params:set("wavetable_cursor_x", util.linlin(0, screen_h, 0, 1, screen_h-mouse_y))
  -- end
end

-- ------------------------------------------------------------------------
-- ux - keyboard

screen.key = function(char, modifiers, is_repeat, state)
  if char.name ~= nil then
    if char.name == "F11" and state >= 1 then
      fullscreen = not fullscreen
      screen.set_fullscreen(fullscreen)
    end
  end
end


-- -------------------------------------------------------------------------
-- screen

local wavetable_texture = nil

-- function index_to_coords(i, nb_rows)
--   if nb_rows == 1 then
--     return i, 1
--   end
--   local x = math.max(1, util.round(i/nb_rows))
--   local y = mod1_smooth(i, nb_rows)
--   return x, y
-- end

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

function draw_wave_from_table(wi, x, y, w, a, phase_shift)
  for t=1,w do
    local wt = util.round(util.linlin(1, w, 1, #wavetable[wi], t))
    wt = mod1(wt + util.round(phase_shift), #wavetable[wi])

    local x_point = t + x
    local y_point = y - wavetable[wi][wt]*(a/2)

    if t > 1 then
      screen.line(x_point, y_point)
    end
    screen.move(x_point, y_point)
  end
end

function draw_wavetable(nb_waves, nb_rows, pos_shift, wavetable_w, wave_padding_x, wave_padding_y, wave_margin_y, row_padding_y)
  local screen_w, screen_h = screen.get_size()
  local nb_waves_per_row = math.floor(nb_waves/nb_rows)

  -- NB: we draw from front to back
  for i=nb_waves,1,-1 do
    local wi = mod1(i + pos_shift, #wavetable)

    local x, y = index_to_coords(i, nb_rows)

    local wave_x = 1 + (x-1) * wave_padding_x
    local wave_y = screen_h - wave_margin_y
      - (y-1) * row_padding_y
      - (x-1) * wave_padding_y

    -- bugged but cool parallax-y effect
    -- local phase_shift = params:get("wave_phase_shift_amount") * SHIFT_FACTOR * (i/nb_waves) * #wavetable[wi]
    -- correct but maybe less "fun"
    local phase_shift = params:get("wave_phase_shift_amount") * SHIFT_FACTOR * (wi/nb_waves) * #wavetable[wi]

    local c
    if false and math.abs(mouse_y - wave_y) < (wave_padding_y/2) then
      c = {200, 200, 200}
    else
      -- y color
      local c2 = colorutil.scale(COL_WAVE_FG, COL_WAVE_FG_2, util.linlin(1, MAX_FOLDING_ROWS, 0, 1, y))
      c = colorutil.scale(COL_WAVE_FG, c2, util.linlin(1, MAX_FOLDING_ROWS, 0, 1, y))
      c = colorutil.scale(c, COL_WAVE_FG, util.linlin(nb_waves, 1, 0, 1, i))
      -- x color (fade out)
      local fade_out_amount = 0
      if nb_waves < MAX_WAVES_DISPLAYED/20 then
        fade_out_amount = util.clamp(util.linlin(1, MAX_WAVES_DISPLAYED, 0, 1, i), 0, 0.95)
      else
        fade_out_amount = util.clamp(util.linlin(1, nb_waves, 0, 1, i), 0, 0.95)
      end
      c = colorutil.scale(c, COL_BG, fade_out_amount)
    end

    screen.color(table.unpack(c))

    local a = util.linlin(1, MAX_FOLDING_ROWS, WAVE_H, WAVE_H/(MAX_FOLDING_ROWS/2), nb_rows)
    draw_wave_from_table(wi, wave_x, wave_y, wavetable_w, a, phase_shift)
  end
end

function draw_interpolating_cursor(nb_waves, nb_rows, pos_shift, wavetable_w, wave_padding_x, wave_padding_y, wave_margin_y, row_padding_y)
  local screen_w, screen_h = screen.get_size()

  local nb_waves_per_row = nb_waves/nb_rows

  local x = params:get("wavetable_cursor_x") * (nb_waves_per_row - 1) + 1
  local y = params:get("wavetable_cursor_y") * (nb_rows - 1) + 1
  local i = coords_to_index(x, y, nb_rows)

  local prev_i = math.floor(i)
  local next_i = math.ceil(i)
  local off = offness(i, prev_i, next_i)
  local prev_wi = mod1(prev_i + pos_shift, #wavetable)
  local next_wi = mod1(next_i + pos_shift, #wavetable)

  local y_offset = screen_h - wave_margin_y - (i-1) * wave_padding_y

  local c = colorutil.scale(COL_WAVE_SELECTED, COL_WAVE_SELECTED_OFF, off)
  screen.color(table.unpack(c))

  local a = WAVE_H/nb_rows

  for t=1,wavetable_w do
    -- NB: assuming all waves have same length!
    local nb_samples = math.min(#wavetable[prev_wi], #wavetable[next_wi])

    local wt = util.round(util.linlin(1, wavetable_w, 1, nb_samples, t))
    local wt_prev = mod1(wt + util.round(params:get("wave_phase_shift_amount") * SHIFT_FACTOR * (prev_i/nb_waves) * nb_samples), nb_samples)
    local wt_next = mod1(wt + util.round(params:get("wave_phase_shift_amount") * SHIFT_FACTOR * (next_i/nb_waves) * nb_samples), nb_samples)

    local v = util.linlin(prev_i, next_i, wavetable[prev_wi][wt_prev], wavetable[next_wi][wt_next], i)

    -- local x = 1 + t + (i-1) * wave_padding_x
    -- local y = y_offset - v*(a/2)

    local wave_x = 1 + (x-1) * wave_padding_x + t
    local wave_y = screen_h - wave_margin_y
      - (y-1) * row_padding_y
      - (x-1) * wave_padding_y
      - v*(a/2)

    if t > 1 then
      screen.line(wave_x, wave_y)
    end
    screen.move(wave_x, wave_y)
  end
end

function redraw()
  local screen_w, screen_h = screen.get_size()

  screen.clear()

  screen.move(1, 1)
  screen.color(table.unpack(COL_BG))
  screen.rect_fill(screen_w, screen_h)

  local wavetable_w = screen_h * 3/4

  -- local frame_padding = (screen_h - wavetable_w)/2
  -- screen.move(frame_padding, frame_padding)
  -- screen.color(103, 103, 103)
  -- screen.rect(wavetable_w, wavetable_w)

  local nb_rows = params:get("wavetable_fold") * (MAX_FOLDING_ROWS-1) + 1
  local nb_waves = math.max(util.round(params:get("wavetable_length") * math.min(#wavetable, MAX_WAVES_DISPLAYED)), 2)
  local nb_waves_per_row = nb_waves/nb_rows
  local pos_shift = util.round(params:get("wavetable_pos_shift") * (#wavetable-1))

  -- spacing between waves
  -- local wave_padding_x = math.min(WAVE_PADDING_X, screen_w/nb_waves_per_row)
  local wave_padding_x = math.min(WAVE_PADDING_X, screen_w)
  local wave_padding_y = (wavetable_w - WAVE_H) / (nb_waves-1)
  local row_padding_y = (wavetable_w - WAVE_H) / nb_rows
  -- spacing between wavetable & top/bottom
  local wave_margin_y = (screen_h - wavetable_w)/2 + (WAVE_H/2)

  draw_wavetable(nb_waves, nb_rows, pos_shift, wavetable_w, wave_padding_x, wave_padding_y, wave_margin_y, row_padding_y)
  draw_interpolating_cursor(nb_waves, nb_rows, pos_shift, wavetable_w, wave_padding_x, wave_padding_y, wave_margin_y, row_padding_y)

  -- optim that doesn't work
  -- if screen_wavetable_dirty or wavetable_texture == nil then
  --   draw_wavetable(nb_waves, nb_rows, pos_shift, wavetable_w, wave_padding_x, wave_padding_y, wave_margin_y, row_padding_y)
  --   screen.move(1, 1)
  --   screen.refresh()
  --   wavetable_texture = screen.new_texture(screen_w, screen_h)
  --   screen_wavetable_dirty = false
  --   return
  -- else
  --   wavetable_texture:render(1, 1)
  --   draw_interpolating_cursor(nb_waves, nb_rows, pos_shift, wavetable_w, wave_padding_x, wave_padding_y, wave_margin_y)
  -- end

  screen.refresh()
  screen_dirty = false
end
