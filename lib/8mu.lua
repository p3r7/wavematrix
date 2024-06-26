
local _8mu = {}

local this_device = "Music Thing m0 Plus"

_8mu.last_pot = 1
_8mu.last_val = 0
local pot_vals = {}


-- ------------------------------------------------------------------------
-- SYSEX

-- 0x1F - "1nFo"
_8mu.request_sysex_config_dump = function(midi_dev)
	print("request_sysex_config_dump")
  midi.send(midi_dev, {0xf0, 0x7d, 0x00, 0x00, 0x1f, 0xf7})
end

-- 0x0F - "c0nFig"
_8mu.is_sysex_config_dump = function(sysex_payload)
  return (sysex_payload[2] == 0x7d and sysex_payload[3] == 0x00 and sysex_payload[4] == 0x00
          and sysex_payload[5] == 0x0f)
end

_8mu.parse_sysex_config_dump = function(sysex_payload)
  local lengthNum = 0
  for k, v in pairs(sysex_payload) do -- for every key in the table with a corresponding non-nil value
    lengthNum = lengthNum + 1
  end

  -- print(lengthNum)
  --tab.print(sysex_payload)

  local i = 6 + 4 -- offset
  local led_power_on = false
  local led_data_blink = false
  local rot = false
  local min_v = 0
  local max_v = 127
  local raw_min_v = 0
  local raw_max_v = 0
  local usb_ch_list={}
  local trs_ch_list={}
  local usb_cc_list={}
  local trs_cc_list={}

  -- if sysex_payload[i+0] == 1 then
  --   led_power_on = true
  -- end
  -- if sysex_payload[i+1] == 1 then
  --   led_data_blink = true
  -- end
  -- if sysex_payload[i+2] == 1 then
  --   rot = true
  -- end
  -- if sysex_payload[i+2] == 1 then
  --   rot = true
  -- end

  -- NB: these seem to be wrongly reported...
  -- raw_min_v = (sysex_payload[i+5] << 8) + sysex_payload[i+4]
  -- raw_max_v = (sysex_payload[i+7] << 8) + sysex_payload[i+6]
  local w=58 -- usb-cc
  local x=74 -- trs-cc
  local y=26 -- usb-channel
  local z=42 -- trs-channel
  for fader_idx = 1,16 do
    -- print(w,x,y,z)
    local usb_cc = sysex_payload[w]
    w = w+1
    table.insert(usb_cc_list, usb_cc)
    local trs_cc = sysex_payload[x]
    x = x+1
    table.insert(trs_cc_list, trs_cc)
    local usb_ch = sysex_payload[y]
    y = y+1
    table.insert(usb_ch_list, usb_ch + 1)

    local trs_ch = sysex_payload[z]
    if trs_ch == nil then
      trs_ch = 0
    end
    z = z+1
    table.insert(trs_ch_list, trs_ch +1 )

--    print(usb_cc .. ":" .. usb_ch .. " - " .. trs_cc .. ":" .. trs_ch)
  end

  return {
    led_power_on = led_power_on,
    led_data_blink = led_data_blink,
    rot = rot,
    min_v = min_v,
    max_v = max_v,
    raw_min_v = raw_min_v,
    raw_max_v = raw_max_v,
    usb_ch = usb_ch_list,
    trs_ch = trs_ch_list,
    usb_cc = usb_cc_list,
    trs_cc = trs_cc_list,
  }
end


-- ------------------------------------------------------------------------
-- PLUG'N'PLAY MIDI BINDING

local dev_8mu=nil
local midi_8mu=nil
local conf_8mu=nil


_8mu.init = function(cc_cb_fn)
  for _,dev in pairs(midi.devices) do
    if dev.name~=nil and dev.name == this_device then
      print("detected " .. this_device .. ", will lookup its config via sysex")

      dev_8mu = dev
      midi_8mu = midi.connect(dev.port)

      local is_sysex_dump_on = false
      local sysex_payload = {}

      midi_8mu.event=function(data)
        -- tab.print(data)
        local d=midi.to_msg(data)

        if is_sysex_dump_on then
          for _, b in pairs(data) do
            -- print(b)
            table.insert(sysex_payload, b)
            if b == 0xf7 then
              is_sysex_dump_on = false
              if _8mu.is_sysex_config_dump(sysex_payload) then
                conf_8mu = _8mu.parse_sysex_config_dump(sysex_payload)
                print("done retrieving 8mu config")
              end
            end
          end
        elseif d.type == 'sysex' then
          is_sysex_dump_on = true
          sysex_payload = {}
          for _, b in pairs(d.raw) do
            table.insert(sysex_payload, b)
          end
        elseif d.type == 'cc' and conf_8mu ~= nil and d.cc < 127 then

			  if cc_cb_fn ~= nil then
				cc_cb_fn(d)
			  end

		elseif d.cc == 127 then
--				print("request sysex")
				_8mu.request_sysex_config_dump(dev_8mu)
				return
        end
      end

      -- ask config dump via sysex
      _8mu.request_sysex_config_dump(dev_8mu)

      break
    end
  end
end


-- ------------------------------------------------------------------------
-- CONF ACCESSORS (STATEFUL)

local function mustHaveConf()
  if conf_8mu == nil then
    error("Attempted to access the 8mu configuration but it didn't get retrieved.")
  end
end

_8mu.cc_2_slider_id = function(cc)
  mustHaveConf()

  local slider_id = nil
  for i, slider_cc in pairs(conf_8mu.usb_cc) do
    if slider_cc == cc then
      slider_id = i
    end
  end

  return slider_id
end

_8mu.min_v = function()
  mustHaveConf()
  return conf_8mu.min_v
end

_8mu.max_v = function()
  mustHaveConf()
  return conf_8mu.max_v
end


-- ------------------------------------------------------------------------

return _8mu
