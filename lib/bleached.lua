-- lib/control/bleached.
-- @eigen

local bleached = {}


-- ------------------------------------------------------------------------
-- deps

-- local inspect = include("lib/inspect")


-- ------------------------------------------------------------------------
-- consts

bleached.M_CC   = 0
bleached.M_CC14 = 1
bleached.M_NRPN = 2


-- ------------------------------------------------------------------------
-- state

local dev_bleached = nil
local midi_bleached = nil
local conf_bleached = nil

bleached.last_pot = 1
bleached.last_val = 0
local tmp_14_vals = {}
local pot_vals = {}


-- ------------------------------------------------------------------------
-- utils - version

local MAX_VERSION = {2, 1, 0}

local function is_supported_version(v, max, index)
  if index == nil then index = 1 end

  if index > #max then
    return true
  end

  if v[index] > max[index] then
    return false
  end

  if v[index] < max[index] then
    return true
  end

  return is_supported_version(v, max, index+1)
end

local function version_string(v)
  return v[1] .. "." .. v[2] .. "." .. v[3]
end

local function is_equal_version(v, v2)
  return (v[1] == v2[1] and v[2] == v2[2] and v[3] == v2[3])
end


-- ------------------------------------------------------------------------
-- utils - sysex

function byte_to_str_midiox(b)
  return string.upper(string.format("%02x", b))
end

function bytes_to_string_midiox(a)
  local out = ""
  for i, b in ipairs(a) do
    if i ~= 1 then
      out = out .. " "
    end
    out = out .. byte_to_str_midiox(b)
  end
  return out
end


-- ------------------------------------------------------------------------
-- sysex - m0dE

-- 0x0E - "m0dE"
bleached.switch_cc_mode = function(mode)
  if dev_bleached == nil then return end
  midi.send(dev_bleached, {0xf0,
                           0x7d, 0x00, 0x00,
                           0x0e,
                           mode,
                           0xf7})
end


-- ------------------------------------------------------------------------
-- sysex - 1nFo / c0nFig

-- 0x1F - "1nFo"
bleached.request_sysex_config_dump = function(midi_dev)
  midi.send(midi_dev, {0xf0,
                       0x7d, 0x00, 0x00,
                       0x1f,
                       0xf7})
end

-- 0x0F - "c0nFig"
bleached.is_sysex_config_dump = function(sysex_payload)
  return (sysex_payload[2] == 0x7d and sysex_payload[3] == 0x00 and sysex_payload[4] == 0x00
          and sysex_payload[5] == 0x0f)
end

bleached.parse_sysex_config_dump_v200 = function(sysex_payload)
  local nb_sensors = sysex_payload[10]
  local ch = sysex_payload[11]

  local ch_list = {}
  local cc_list = {}
  for i=0,nb_sensors-1 do
    table.insert(ch_list, ch)
    table.insert(cc_list, sysex_payload[12+i])
  end

  return {
    version = version,
    ch = ch_list,
    cc = cc_list,
  }
end

bleached.parse_sysex_config_dump_v210 = function(sysex_payload)
  local pinout_list = {}
  local ch_list = {}
  local cc_list = {}
  local cc14_list = {}
  local nrpn_list = {}

  local nb_sensors = sysex_payload[12]

  local cc_mode = sysex_payload[13]

  local offset = 14

  -- pinout
  for i=0,nb_sensors-1 do
    table.insert(pinout_list, sysex_payload[offset])
    offset = offset+1
  end
  -- ch
  for i=0,nb_sensors-1 do
    table.insert(ch_list, sysex_payload[offset])
    offset = offset+1
  end
  -- cc
  for i=0,nb_sensors-1 do
    table.insert(cc_list, sysex_payload[offset])
    offset = offset+1
  end
  -- 14-bit cc
  for i=0,nb_sensors-1 do
    table.insert(cc14_list, {sysex_payload[offset], sysex_payload[offset+1]})
    offset = offset+2
  end
  -- nrpn cc
  for i=0,nb_sensors-1 do
    local msb = sysex_payload[offset] << 7
    local lsb = sysex_payload[offset+1]
    table.insert(nrpn_list, msb + lsb)
    offset = offset+2
  end

  return {
    version = version,
    pinout = pinout_list,
    ch = ch_list,
    cc_mode = cc_mode,
    cc = cc_list,
    cc14 = cc14_list,
    nrpn = nrpn_list,
  }
end

bleached.parse_sysex_config_dump = function(sysex_payload)
  local device_id = sysex_payload[6]
  local version = {sysex_payload[7], sysex_payload[8], sysex_payload[9]}

  if not is_supported_version(version, MAX_VERSION) then
    print("Unsupported bleached version (" .. version_string(version) .. " > " .. version_string(MAX_VERSION)  .. ") !")
    return nil
  end
  print("Bleached version: " .. version_string(version))

  if is_equal_version(version, {2, 1, 0}) then
    return bleached.parse_sysex_config_dump_v210(sysex_payload)
  end
end


-- ------------------------------------------------------------------------
-- init

local function process_incoming_sysex(sysex_payload)
  print("got sysex from bleached")
  if bleached.is_sysex_config_dump(sysex_payload) then
    print("is c0nFig")
    conf_bleached = bleached.parse_sysex_config_dump(sysex_payload)
    print("done retrieving bleached config")
    -- print(inspect(conf_bleached))
  else
    print("unknown sysex, payload:")
    tab.print(sysex_payload)
  end
end

function bleached.init(cc_cb_fn)
  for _,dev in pairs(midi.devices) do
    if dev.name~=nil and dev.name == "h2o2d" then
      print("detected h2o2d (bleached) midi dev")
      dev_bleached = dev
      midi_bleached = midi.connect(dev.port)
    end
  end

  if midi_bleached == nil then
    return
  end

  local is_sysex_dump_on = false
  local sysex_payload = {}

  midi_bleached.event = function(data)

    -- print(bytes_to_string_midiox(data))

    local d = midi.to_msg(data)

    if is_sysex_dump_on then
      for _, b in pairs(data) do
        table.insert(sysex_payload, b)
        if b == 0xf7 then
          is_sysex_dump_on = false
          process_incoming_sysex(sysex_payload)
        end
      end
    elseif d.type == 'sysex' then
      is_sysex_dump_on = true
      sysex_payload = {}
      for _, b in pairs(d.raw) do
        table.insert(sysex_payload, b)
        if b == 0xf7 then
          is_sysex_dump_on = false
          process_incoming_sysex(sysex_payload)
        end
      end
    elseif d.type == 'cc' and conf_bleached ~= nil then
      if cc_cb_fn ~= nil then
        cc_cb_fn(d)
      end
    end
  end

  -- ask config dump via sysex
  bleached.request_sysex_config_dump(dev_bleached)

end


-- ------------------------------------------------------------------------
-- conf accessors (stateful)

local function mustHaveConf()
  if conf_bleached == nil then
    error("Attempted to access the bleached configuration but it didn't get retrieved.")
  end
end

function bleached.conf()
  return conf_bleached
end

function bleached.nb_pots()
  return #conf_bleached.cc
end

function bleached.cc_to_row(cc)
  local pot = bleached.cc_to_pot(cc)

  if pot > 4 then
    return 1
  end
  return 2
end

function bleached.cc_to_row_pot(cc)
  local pot = bleached.cc_to_pot(cc)

  if pot > 4 then
    return pot - 4
  end
  return pot
end

function bleached.cc_to_pot(cc)
  mustHaveConf()

  local cc_mode = conf_bleached.cc_mode

  if cc_mode == bleached.M_CC then
    local t = tab.invert(conf_bleached.cc)
    return t[cc]
  else
    for i, cc14 in ipairs(conf_bleached.cc14) do
      if cc == cc14[1] or  cc == cc14[2] then
        return i
      end
    end
  end

end

function bleached.register_val(cc, val)
  mustHaveConf()

  local cc_mode = conf_bleached.cc_mode

  if cc_mode == bleached.M_CC then
    local pot = bleached.cc_to_pot(cc)
    pot_vals[pot] = val

    bleached.last_pot = pot
    bleached.last_val = val
  elseif cc_mode == bleached.M_CC14 then
    local pot = bleached.cc_to_pot(cc)
    local cc14 = conf_bleached.cc14[pot]

    -- TODO: LSB is optional

    if cc == cc14[1] then -- MSB
      tmp_14_vals[pot] = val << 7
    else -- LSB
      tmp_14_vals[pot] = tmp_14_vals[pot] + val
      bleached.last_pot = pot
      bleached.last_val = tmp_14_vals[pot]
    end

  elseif cc_mode ==  bleached.M_NRPN then
    -- TODO
  end

end

function bleached.is_final_val_update(cc)
  local cc_mode = conf_bleached.cc_mode

  if cc_mode == bleached.M_CC then
    return true
  elseif cc_mode == bleached.M_NRPN then
    return (cc == 6)
  elseif cc_mode == bleached.M_CC14 then
    for _, cc14 in ipairs(conf_bleached.cc14) do
      if cc == cc14[2] then
        return true
      end
    end
    return false
  end
  return false
end

function bleached.is_14_bits()
  local cc_mode = conf_bleached.cc_mode

  if cc_mode == bleached.M_CC then
    return false
  end
  return true
end

-- ------------------------------------------------------------------------

return bleached
