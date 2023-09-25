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


-- -------------------------------------------------------------------------
-- colors

COL_BG = {24, 34, 34}

COL_WAVE_FG = {111, 211, 111}
COL_WAVE_BG = {244, 108, 108}
COL_WAVE_SELECTED = {50, 205, 50}
COL_WAVE_SELECTED_OFF = {255, 0, 0}


-- -------------------------------------------------------------------------
-- state

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
    params:set("wave_phase_shift_amount", util.linlin(0, 127, 0, 1, v))
  elseif row == 1 and pot == 2 then
    params:set("wavetable_cursor_travel", util.linlin(0, 127, 0, 1, v))
  elseif row == 2 and pot == 3 then
    params:set("wavetable_pos_shift", util.linlin(0, 127, 0, 1, v))
  elseif row == 2 and pot == 4 then
    params:set("wavetable_length", util.linlin(0, 127, 0, 1, v))
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
  params:add{type = "control", id = "wave_phase_shift_amount", name = "wave phase shift", controlspec = pct_control_off, formatter = format_percent}
  params:add{type = "control", id = "wavetable_cursor_travel", name = "wavetable cursor", controlspec = pct_control_off, formatter = format_percent}
  params:add{type = "control", id = "wavetable_length", name = "wavetable length", controlspec = pct_control_on, formatter = format_percent}
  params:add{type = "control", id = "wavetable_pos_shift", name = "wavetable shift", controlspec = pct_control_off, formatter = format_percent}

  -- parse_wav_dir(script_dir.."/data/")
  parse_wav_dir(script_dir.."/waveforms/")

  clock_redraw = clock.run(function()
      while true do
        clock.sleep(1/FPS)
        redraw()
      end
  end)
end


screen.mouse = function(x, y)
  mouse_x, mouse_y = x, y
  -- if not has_bleached then
  --   local _, screen_h = screen.get_size()
  --   params:set("wavetable_cursor_travel", util.linlin(0, screen_h, 0, 1, screen_h-mouse_y))
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

function redraw()
  screen.clear()

  local screen_w, screen_h = screen.get_size()

  -- local wavetable_w = screen_h
  local wavetable_w = screen_h * 3/4

  screen.move(1, 1)
  screen.color(table.unpack(COL_BG))
  screen.rect_fill(screen_w, screen_h)

  -- local frame_padding = (screen_h - wavetable_w)/2
  -- screen.move(frame_padding, frame_padding)
  -- screen.color(103, 103, 103)
  -- screen.rect(wavetable_w, wavetable_w)

  local nb_waves = math.max(util.round(params:get("wavetable_length") * math.min(#wavetable, MAX_WAVES_DISPLAYED)), 2)
  local pos_shift = util.round(params:get("wavetable_pos_shift") * math.min(#wavetable, MAX_WAVES_DISPLAYED))

  local wave_padding_x = math.min(WAVE_PADDING_X, screen_w/nb_waves)
  local wave_padding_y = (wavetable_w - WAVE_H) / (nb_waves-1)

  -- NB: we draw from front to back
  for i=nb_waves,1,-1 do
    local wi = mod1(i + pos_shift, #wavetable)
    local w = wavetable[wi]

    local y_offset = screen_h - (screen_h - wavetable_w)/2 - (WAVE_H/2) - (i-1) * wave_padding_y

    local c
    if math.abs(mouse_y - y_offset) < (wave_padding_y/2) then
      c = {200, 200, 200}
    else
      c = colorutil.scale(COL_WAVE_FG, COL_WAVE_BG, util.linlin(1, nb_waves, 0, 1, i))
      local fade_out_amount = util.clamp(util.linlin(1, nb_waves, 0, 1, i),0 ,0.95)
      c = colorutil.scale(c, COL_BG, fade_out_amount)
    end

    screen.color(table.unpack(c))

    for t=1,wavetable_w do
      local wt = util.round(util.linlin(1, wavetable_w, 1, #wavetable[wi], t))
      wt = mod1(wt + util.round(params:get("wave_phase_shift_amount") * SHIFT_FACTOR * (i/nb_waves) * #wavetable[wi]), #wavetable[wi])

      local x = t + i * wave_padding_x
      local y = y_offset - wavetable[wi][wt]*(WAVE_H/2)

      if t > 1 then
        screen.line(x, y)
      end
      screen.move(x, y)
    end
  end

  -- interpolating cursor
  local i = params:get("wavetable_cursor_travel") * nb_waves
  if i < 1 then i = 1 end
  local prev_i = math.floor(i)
  local next_i = math.ceil(i)
  local off = offness(i, prev_i, next_i)
  local prev_wi = mod1(prev_i + pos_shift, #wavetable)
  local next_wi = mod1(next_i + pos_shift, #wavetable)

  local y_offset = screen_h - (screen_h - wavetable_w)/2 - (WAVE_H/2) - (i-1) * wave_padding_y

  local c = colorutil.scale(COL_WAVE_SELECTED, COL_WAVE_SELECTED_OFF, off)
  screen.color(table.unpack(c))

  for t=1,wavetable_w do
    -- NB: assuming all waves have same length!
    local nb_samples = math.min(#wavetable[prev_wi], #wavetable[next_wi])

    local wt = util.round(util.linlin(1, wavetable_w, 1, nb_samples, t))
    local wt_prev = mod1(wt + util.round(params:get("wave_phase_shift_amount") * SHIFT_FACTOR * (prev_i/nb_waves) * nb_samples), nb_samples)
    local wt_next = mod1(wt + util.round(params:get("wave_phase_shift_amount") * SHIFT_FACTOR * (next_i/nb_waves) * nb_samples), nb_samples)

    local v = util.linlin(prev_i, next_i, wavetable[prev_wi][wt_prev], wavetable[next_wi][wt_next], i)

    local x = t + i * wave_padding_x
    local y = y_offset - v*(WAVE_H/2)

    if t > 1 then
      screen.line(x, y)
    end
    screen.move(x, y)
  end


  screen.refresh()
end
