# TinyWorlds Different Steps

- Source: https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud
- Author: TinyWorlds / kddekadenz
- License: CC0 1.0 Universal
- Downloaded archive: `[kdd]DifferentSteps_0.zip`
- Archive SHA-256: `987d072b7deaa65177e005ddd8185f2351be7c9a76cd7575dea560549c39b33b`

Used source files:

- `gravel.ogg`: `34e6057ec1581b5cb8802e4942952b00b1dac235bfcb0ed8cff0ceb15a3ebbbf`
- `stone01.ogg`: `99b04d784eb6b531777a64fb0e319f104eb7cdd6b625c1fac68f511605930a2c`
- `wood01.ogg`: `482d97c5e1e6eb7b239be46f25d093ebebb94cefb56eedb04807b6a5dc68e972`
- `wood02.ogg`: `588bb121bd3db005b4c2a5b55c1cf39b8ec620f820c2123ac1f62748d132dac2`
- `wood03.ogg`: `9b677c284389163f132b94e1323ea713a4c7ac9d5fba849cf7cbf8b53a1627e2`
- `leaves01.ogg`: `93b3bbcd06380eec54335d1869924db6ff2cc6c1cb103502133d78484c5ca836`
- `leaves02.ogg`: `477c35bfd3f740915b24f93cb66364523217692d2749057f9b8be162eb8209f4`
- `mud02.ogg`: `354682c2cb340cd787d892d31beb87c45dda94ca6e8363b16828ab2f1d129b82`

The checked-in `*_source.wav` files are deterministic 44.1 kHz mono PCM16
decodes made with FFmpeg. Their PCM payloads match fresh decodes of the
hash-verified OGG files; the containers retain FFmpeg's `LIST/INFO` encoder
tag. `make_sounds.dart` trims, linearly resamples, fades, and peak-normalizes
them into four runtime variants. Stone also receives a one-pole 1.3 kHz
low-pass. No synthetic layers are added.
Stone playback is resampled to 90% speed to lower its baked pitch.
Wood variants use the three original wood recordings; the fourth variant is a
second subtle resampling of `wood03`.
Leaves alternate the two source recordings with subtle resampling. Dirt and
sponge use four subtly resampled variants of `mud02`.
