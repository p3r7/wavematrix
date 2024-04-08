Engine_WaveMatrix : CroneEngine {
	var <synth;
	var params;

	alloc {

		var server = Crone.server;

		var path = PathName("/home/we/dust/code/wavematrix/waveforms/");
		var wavetable = path.entries.collect { |entry|
			Buffer.read(server, path.fullPath +/+ entry.fileName);
		};

		var def = SynthDef(\WaveMatrix, { |out = 0, freq = 440, amp = 0.5,
			prev_bottom_i = 0.0, next_bottom_i = 0.0,
			prev_top_i = 0.0, next_top_i = 0.0,
			mix_x = 0.0, mix_y = 0.0,
			phase = 0.0, cutoff = 1200, resonance = 0|

			// TODO: was at doing XFade2 of 4 wavetables
			var prev_bottom, next_bottom, prev_top, next_top, raw_top, raw_bottom, raw, filtered;
			var bufNums = wavetable.collect { |wf| wf.bufnum };

			prev_bottom = VOsc.ar(prev_bottom_i.clip2(wavetable.size - 2), freq, phase) * amp;
			next_bottom = VOsc.ar(next_bottom_i.clip2(wavetable.size - 2), freq, phase) * amp;
			prev_top = VOsc.ar(prev_top_i.clip2(wavetable.size - 2), freq, phase) * amp;
			next_top = VOsc.ar(next_top_i.clip2(wavetable.size - 2), freq, phase) * amp;

			// NB: mix_* converted for XFade2 range (-1 to 1)
			raw_bottom = XFade2.ar(prev_bottom, next_bottom, mix_x * 2 - 1) * amp;
			raw_top = XFade2.ar(prev_top, next_top, mix_x * 2 - 1) * amp;

			raw = XFade2.ar(raw_bottom, raw_top, mix_y * 2 - 1) * amp;

			filtered = MoogFF.ar(in: raw, freq: cutoff, gain: resonance);

			// Output the signal in stereo
			Out.ar(0, filtered ! 2);
		}).add;

		def.send(server);
		server.sync;

		synth = Synth.new(\WaveMatrix, [\out, context.out_b], target: context.xg);

		// We don't need to sync with the server in this example,
		//   because were not actually doing anything that depends on the SynthDef being available,
		//   so let's leave this commented:
		// Server.default.sync;

		params = Dictionary.newFrom([
			\freq, 80,
			\prev_bottom_i, 0.0,
			\next_bottom_i, 0.0,
			\prev_top_i, 0.0,
			\next_top_i, 0.0,
			\mix_x, 0.0,
			\mix_y, 0.0,
			\cutoff, 8000,
			\resonance, 0.0,
			\amp, 0.1;
		]);

		params.keysDo({ arg key;
			this.addCommand(key, "f", { arg msg;
				params[key] = msg[1];
				synth.set(key, msg[1]);
			});
		});

	}

	free {
		synth.free;
	}
}