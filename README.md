# zero-jetpack

Toby Jaffey https://mastodon.me.uk/@tobyjaffey

Play at: https://ringtailsoftware.github.io/zero-jetpack

A game built on https://github.com/ringtailsoftware/zig-wasm-audio-framebuffer

Fly Zero the Ziguana through space, collect the eggs and deposit them carefully in the basket.

# Build and test (assumes you have zig installed)

    zig build
    cd zig-out && python3 -m http.server 8000

# Build and test via docker

    make

Browse to http://localhost:8000

# Notes

This project is a mess, I've been working on for fun and education. I'm sharing the code because it might help others who are trying to figure out similar things.

## Definitely bad stuff

 - Error/allocation handling is almost non-existent. It's a game, if something fails then the whole thing fails
 - Physics. All of the physics is hand-rolled. Some of it isn't very realistic. Other bits aren't even framerate independent
 - Graphics. Everything is drawn all of the time. Primitives are clipped to the framebuffer to stop them writing to bad memory locations, but that's it. It's a testament to zig and wasm that it's so fast at all
 - The collision detection is known to be bad. It works when the frame time delta is kept small, it would fail if larger movements were allowed

## Not so bad stuff

 - It's probably quite portable. Apart from `getTimeUs()`, it doesn't call out to anything in the host. The host polls the code for sound and pixel buffers
 - The levels are pairs of levelX.png and levelX.txt files in `assets/`. Each png is a bitmap with a colour for each thing in the game. White is empty, black is rock, red is an egg (redness dictates egg size). Blue is the player start position and green is the basket location
 - The sprite tilesheets and animations are all defined in `assets/sprites.json`

