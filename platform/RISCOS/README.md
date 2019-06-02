# NBlood for RISC OS

## Building
1. Build libsdl1.2debian & libsdl-mixer1.2 using the GCCSDK autobuilder
2. `source` the `env/ro-path` file from your GCCSDK install
3. `./platform/riscosbuild.sh`

## Installing
See the main NBlood readme file for details on which data files are needed. You'll also need nblood.pk3 from this repository.

Note that as with other RISC OS SDL apps, you'll need to make sure to redirect stdout & stderr to file or `null:` to avoid the output interfering with things.

It's recommended to have the DRenderer & Freepats packages installed from PackMan in order to get sound + music.

## Issues

* I haven't tried building with the OpenGL renderer enabled
* FLAC is disabled (autobuilder recipe appears to be broken)
* It's a bit of a memory hog - even if you use the `-cachesize` option to reduce the cache from the default of 96MB, you'll probably still need a machine with at least 128MB of RAM to be able to run it
* It's a CPU hog - ARM versions of the assembler plotting routines are needed, but also the audio mixing appears to be using a disproportionately high amount of CPU time, mainly due to using floating point math for volume scaling/mixing
  * NBlood prefers to run in a colour depth which matches the current screen colour depth. So you can get a little bit more performance by switching to an 8bpp mode before running. (Note the `ScreenBPP = 8` in the config file merely means that the software renderer is in use, as opposed to the (unsupported) OpenGL renderer)
* Although some paths can be configured on the command line, NBlood is hardcoded to read/write save games and some other files to the current directory
