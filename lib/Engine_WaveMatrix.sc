Engine_WaveMatrix : CroneEngine {
	var <synth;
	var params;

	alloc {

		var server = Crone.server;

		var path = PathName("/home/we/dust/code/wavematrix/waveforms/");
		var wavetable = path.entries.collect { |entry|
			Buffer.read(server, path.fullPath +/+ entry.fileName);
		};

		var def = SynthDef(\WaveMatrix, { |out = 0, freq = 440, amp = 0.5, index = 0.0, phase = 0.0, cutoff = 1200, resonance = 0|
			var raw, filtered;
			var bufNums = wavetable.collect { |wf| wf.bufnum };

			raw = VOsc.ar(index.clip2(wavetable.size - 2), freq, phase) * amp;

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
			\index, 1,
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