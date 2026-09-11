# Ashborn

Plymouth script theme with a grey unlock screen, RGB-split reveal, and separate
shutdown fade. The runtime requires the script plugin, JetBrainsMono Nerd Font,
the sixteen PNGs in `assets/`, and the helpers in `../../integration/`.

The asset manifest records geometry and SHA-256 hashes. Images are scaled at
startup and sprites are reused; refresh callbacks do not load or resize images.
Output changes after startup do not reflow the shared canvas.

The boot helper allows 3 seconds for the 2.3-second reveal; shutdown allows
1 second for a 0.6-second fade. Unit timeouts are 4 and 2 seconds. Neither helper
starts or quits Plymouth; the script's quit callback cannot delay teardown.

Original theme code and user-supplied artwork are licensed under the
[MIT License](LICENSE). Third-party fonts retain their own licenses;
trademark rights are not granted by this license.
