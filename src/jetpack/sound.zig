const std = @import("std");
const Game = @import("game.zig").Game;
const ziggysynth = @import("ziggysynth.zig");
const SoundFont = ziggysynth.SoundFont;
const Synthesizer = ziggysynth.Synthesizer;
const SynthesizerSettings = ziggysynth.SynthesizerSettings;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const SoundFx = enum {
    ThrustOn,
    ThrustOff,
    Smashed,
    InBasket,
};

const RENDER_QUANTUM_FRAMES = 128; // WebAudio's render quantum size

const ThrustInstrument = 125;    // MIDI Helicopter
const ThrustPitch = 50;
const SmashInstrument = 112;    // MIDI bell
const SmashPitch = 45;
const InBasketInstrument = 112;    // MIDI bell
const InBasketPitch = 70;
const TalkInstrument = 54;    // MIDI synth voice

const talkPitches:[10]i32 = .{40, 29, 62, 50, 34, 49, 24, 56, 32, 19};

pub const Sound = struct {
    const Self = @This();

    synthBuf_left: [RENDER_QUANTUM_FRAMES]f32,
    synthBuf_right: [RENDER_QUANTUM_FRAMES]f32,
    synthesizer: Synthesizer,
    thrusting: bool,
    thrustOnTime: u32,
    talking: bool,
    talkStartTime: u32,
    talkCurPitch: i32,

    pub fn init(sampleRate:f32, sf2name:[]const u8) Self {
        // create the synthesizer
// related to https://github.com/ziglang/zig/issues/14917 ?
//        const synth_font = Game.Assets.ASSET_MAP.get(sf2name).?;
_ = sf2name;
const synth_font = @embedFile("assets/gzdoom.sf2");
        var fbs = std.io.fixedBufferStream(synth_font);
        var reader = fbs.reader();
        var sound_font = SoundFont.init(allocator, reader) catch unreachable;
        var settings = SynthesizerSettings.init(@floatToInt(i32, sampleRate));
        settings.block_size = RENDER_QUANTUM_FRAMES;
        var synthesizer = Synthesizer.init(allocator, sound_font, settings) catch unreachable;

        return Self {
            .synthesizer = synthesizer,
            .synthBuf_left = undefined,
            .synthBuf_right = undefined,
            .thrusting = false,
            .thrustOnTime = 0,
            .talking = false,
            .talkStartTime = 0,
            .talkCurPitch = 0,
        };
    }

    pub fn mixSoundQuantum(self:*Self, mix_left:*[RENDER_QUANTUM_FRAMES]f32, mix_right:*[RENDER_QUANTUM_FRAMES]f32, volume:f32) void {
        self.synthesizer.render(&self.synthBuf_left, &self.synthBuf_right);

        if (self.thrusting) {   // avoid thrust sound staying on if main loop is stuck doing something (e.g. modal Dialog)
            if (Game.millis() > self.thrustOnTime + 1000) {
                self.singleShot(.ThrustOff);
            }
        }

        if (self.talking) {
            const pitchIndex:usize = ((Game.millis() - self.talkStartTime) / 250) % talkPitches.len;
            if (talkPitches[pitchIndex] != self.talkCurPitch) {
                self.talkCurPitch = talkPitches[pitchIndex];
                self.synthesizer.noteOffAllChannel(1, false);
                self.synthesizer.processMidiMessage(1, 0xC0, TalkInstrument, 0);
                self.synthesizer.noteOn(1, talkPitches[pitchIndex], 60);
            }
        }

        var i:usize = 0;
        while (i < RENDER_QUANTUM_FRAMES) : (i += 1) {
            mix_left[i] += self.synthBuf_left[i] * volume;
            mix_right[i] += self.synthBuf_right[i] * volume;
        }
    }

    pub fn talk(self:*Self, en:bool) void {
        self.talking = en;
        self.talkStartTime = Game.millis();

        if (!en) {
            self.synthesizer.noteOffAllChannel(1, false);
        }
    }

    pub fn singleShot(self:*Self, fx: SoundFx) void {
        switch(fx) {
            .ThrustOn => {
                if (!self.thrusting) {
                    self.thrusting = true;
                    self.thrustOnTime = Game.millis();
                    self.synthesizer.processMidiMessage(0, 0xC0, ThrustInstrument, 0);
                    self.synthesizer.noteOn(0, ThrustPitch, 127);
                }
            },
            .ThrustOff => {
                if (self.thrusting) {
                    self.thrusting = false;
                    self.synthesizer.noteOff(0, ThrustPitch);
                }
            },
            .Smashed => {
                self.synthesizer.processMidiMessage(0, 0xC0, SmashInstrument, 0);
                self.synthesizer.noteOn(0, SmashPitch, 127);
            },
            .InBasket => {
                self.synthesizer.processMidiMessage(0, 0xC0, InBasketInstrument, 0);
                self.synthesizer.noteOn(0, InBasketPitch, 127);
            }

        }
    }
};
