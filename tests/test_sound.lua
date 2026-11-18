-- The hitmarker sound: the WAV carried in src/hitsound.lua and the volume applied to the samples.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end
local sound = dofile("src/sound.lua")
local wav = dofile("src/hitsound.lua")

test("the_sound_is_a_plain_mono_16_bit_wav", function()
	eq(wav:sub(1, 4), "RIFF", "riff")
	eq(wav:sub(9, 16), "WAVEfmt ", "wave")
	eq(wav:sub(37, 40), "data", "the samples start at byte 45")
	local channels, rate, bits = wav:byte(23) + wav:byte(24) * 256, wav:byte(25) + wav:byte(26) * 256 + wav:byte(27) * 65536, wav:byte(35)
	eq(channels, 1, "mono") eq(rate, 44100, "rate") eq(bits, 16, "bits")
	eq(#wav < 20000, true, "short")
end)

test("the_volume_scales_every_sample_and_keeps_the_header", function()
	local head = wav:sub(1, 44)
	local function sample(s, i)
		local lo, hi = s:byte(44 + i * 2 + 1, 44 + i * 2 + 2)
		local v = lo + hi * 256
		return v >= 32768 and v - 65536 or v
	end
	local half = sound.scaled(wav, 0.5)
	eq(#half, #wav, "same length")
	eq(half:sub(1, 44), head, "header kept")
	local loudest, at = 0, 0
	for i = 0, (#wav - 44) / 2 - 1 do
		if math.abs(sample(wav, i)) > loudest then loudest, at = math.abs(sample(wav, i)), i end
	end
	near(sample(half, at), math.floor(sample(wav, at) * 0.5 + 0.5), "half", 0)
	eq(sound.scaled(wav, 1), wav, "full volume: as it is")
	eq(sample(sound.scaled(wav, 0), at), 0, "silent")
end)

test("the_setting_follows_a_curve_below_the_full_sound", function()
	eq(sound.gain(0), 0, "off")
	near(sound.gain(1), sound.GAIN, "the most")
	near(sound.gain(0.7), 0.196, "0.7 plays as 0.2 did in 0.7.0", 1e-3)
	near(sound.gain(0.5), sound.GAIN / 4, "half way is a quarter")
end)

return T
