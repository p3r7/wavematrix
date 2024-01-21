
local wavutils = {}


-- -------------------------------------------------------------------------
-- deps

-- include("lib/kaitai/kaitaistruct")
include("lib/kaitai/wav")


-- -------------------------------------------------------------------------
-- sample

function wavutils.unsigned_to_signed(v, bit_depth)
  if v >= 2 ^ (bit_depth-1) then
    return v - 2 ^ bit_depth
  end
  return v
end

-- NB: unused
function wavutils.bytes_to_sample(bytes)
  local v = 0
  for i=1,#bytes do
    v = v + (bytes[i] << (8*(#bytes-i)))
  end
  return v
end

function wavutils.str_to_sample(str, id)
  str = string.reverse(str) -- big endian

  local v = 0
  local max = 0
  for i = 1, #str do
    local c = str:sub(i,i)
    local b = string.byte(c)
    v = v + (b << (8*(#str-i)))
    max = max + (0xff << (8*(#str-i)))
  end

  local unsigned_v = v

  v= wavutils.unsigned_to_signed(v, 8*#str)

  -- if DBG then
  --   print(id .. "\t" .. unsigned_v .. "\t" .. v)
  -- end

  return v
end


-- -------------------------------------------------------------------------
-- wav - normalization

function wavutils.wave_normalized(wave, bytes_per_sample)
  local normalized = {}

  local max = 0
  for i = 1,bytes_per_sample do
    max = max + (0xff << (8*(bytes_per_sample-i)))
  end

  for i, v in ipairs(wave) do
    normalized[i] = v / (max/2)
  end

  return normalized
end


-- -------------------------------------------------------------------------
-- wav - file

function wavutils.parse_wav(filepath)
  local w = Wav:from_file(filepath)

  -- is chunk #1 metadata
  assert(w.subchunks[1].chunk_id.label == "fmt")
  -- is chunk #2 data
  assert(w.subchunks[2].chunk_id.label == "data")
  fmt = w.subchunks[1].chunk_data
  data = w.subchunks[2].chunk_data.data

    -- is mono, PCM, not float
  assert(fmt.n_channels == 1)
  assert(fmt.is_basic_pcm == true)
  assert(fmt.is_basic_float == false)

  -- https://stackoverflow.com/a/26022154
  local bytes_per_sample_frame = fmt.n_block_align
  local nb_sample_frames = #data / bytes_per_sample_frame
  local nb_samples = nb_sample_frames * fmt.n_channels
  -- NB: following oly works when 1 channel
  local bits_per_sample = fmt.w_bits_per_sample
  local bytes_per_sample = bits_per_sample / 8

  local hz = fmt.n_samples_per_sec

  local wave = {}
  for i=1,nb_samples do

    local s = (i-1)*bytes_per_sample+1
    local e = s+bytes_per_sample-1
    local sample_str = string.sub(data, s, e)
    wave[i] = wavutils.str_to_sample(sample_str, i)
  end

  if DBG then
    -- tab.print(wave)
  end

  wave = wavutils.wave_normalized(wave, bytes_per_sample)

  return wave
end


-- -------------------------------------------------------------------------

return wavutils
