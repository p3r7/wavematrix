Engine_WaveMatrix : CroneEngine {
	var <synth;
	var params;
	var wavetable;

	alloc {

		var server = Crone.server;
		var def;

		var path = PathName("/home/we/dust/code/wavematrix/wavetables/init/");

		wavetable = path.entries.collect { |entry|
			Buffer.read(server, path.fullPath +/+ entry.fileName);
		};

		def = SynthDef(\WaveMatrix, {
			arg out = 0,
			table_max,
			gate = 0, vel = 0.5,
			freq = 440, amp = 0.5,
			// index
			prev_bottom_i = 0.0, next_bottom_i = 0.0,
			prev_top_i = 0.0, next_top_i = 0.0,
			// phase
			prev_bottom_p = 0.0, next_bottom_p = 0.0,
			prev_top_p = 0.0, next_top_p = 0.0,
			// x-fade
			mix_x = 0.0, mix_y = 0.0,
			// amp env
			amp_offset = 0.0,
			attack = 0.1, decay = 0.1, sustain = 0.7, release = 0.5,
			// filter
			cutoff = 1200, resonance = 0.0;

			// TODO: was at doing XFade2 of 4 wavetables
			var prev_bottom, next_bottom, prev_top, next_top, raw_top, raw_bottom, raw, filtered;
			// var bufNums = wavetable.collect { |wf| wf.bufnum };
			var indexLag = 0.1;
			var env, scaledEnv;

			prev_bottom_i = Lag.kr(prev_bottom_i, indexLag);
			next_bottom_i = Lag.kr(next_bottom_i, indexLag);
			prev_top_i = Lag.kr(prev_top_i, indexLag);
			next_top_i = Lag.kr(next_top_i, indexLag);

			mix_x = Lag.kr(mix_x, indexLag);

			prev_bottom = VOsc.ar(prev_bottom_i.clip2(table_max - 2), freq, prev_bottom_p) * amp;
			next_bottom = VOsc.ar(next_bottom_i.clip2(table_max - 2), freq, next_bottom_p) * amp;
			prev_top = VOsc.ar(prev_top_i.clip2(table_max - 2), freq, prev_top_p) * amp;
			next_top = VOsc.ar(next_top_i.clip2(table_max - 2), freq, next_top_p) * amp;

			// NB: mix_* converted for XFade2 range (-1 to 1)
			raw_bottom = XFade2.ar(prev_bottom, next_bottom, mix_x * 2 - 1) * amp;
			raw_top = XFade2.ar(prev_top, next_top, mix_x * 2 - 1) * amp;

			raw = XFade2.ar(raw_bottom, raw_top, mix_y * 2 - 1) * amp;

			//raw = LeakDC.ar(raw, 0.995);

			env = EnvGen.kr(Env.adsr(attack, decay, sustain, release), gate, doneAction: 0);
			scaledEnv = (1 - amp_offset) * env + amp_offset;

			filtered = MoogFF.ar(in: raw, freq: cutoff, gain: resonance) * scaledEnv * vel;

			// Output the signal in stereo
			Out.ar(0, filtered ! 2);
		}).add;

		def.send(server);
		server.sync;

		synth = Synth.new(\WaveMatrix, [\out, context.out_b, \table_max, wavetable.size - 2] , target: context.xg);

		// We don't need to sync with the server in this example,
		//   because were not actually doing anything that depends on the SynthDef being available,
		//   so let's leave this commented:
		// Server.default.sync;

		params = Dictionary.newFrom([
			\freq, 80,
			\amp, 0.1, // REVIEW: remove?
			// index
			\prev_bottom_i, 0.0,
			\next_bottom_i, 0.0,
			\prev_top_i, 0.0,
			\next_top_i, 0.0,
			// phase
			\prev_bottom_p, 0.0,
			\next_bottom_p, 0.0,
			\prev_top_p, 0.0,
			\next_top_p, 0.0,
			// xfade
			\mix_x, 0.0,
			\mix_y, 0.0,
			// amp env
			\amp_offset, 0.0,
			\attack, 0.1,
			\decay, 0.1,
			\sustain, 0.7,
			\release, 0.5,
			// filter
			\cutoff, 8000,
			\resonance, 0.0,
		]);

		params.keysDo({ arg key;
			this.addCommand(key, "f", { arg msg;
				params[key] = msg[1];
				synth.set(key, msg[1]);
			});
		});

		this.addCommand("loadWavetable", "s", { arg msg;
			var path = PathName(msg[1].asString);
			wavetable = path.entries.collect { |entry|
				Buffer.read(server, path.fullPath +/+ entry.fileName);
			};
			synth.set(\table_max, wavetable.size - 2);
			"Loading new wavetable".postln;
		});

		this.addCommand("noteOn", "if", { arg msg;
			var freq = msg[1];
			var vel = msg[2];
			synth.set(\freq, freq, \vel, vel, \gate, 1);
		});
		this.addCommand("noteOff", "", { arg msg;
			synth.set(\gate, 0);
		});

	}

	free {
		synth.free;
		wavetable.do(_.free);
	}
}