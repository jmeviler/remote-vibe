Source: https://github.com/ExistentialAudio/BlackHole
Commit: 561d934c77a1fa64987e01ccabe890fed30e181f
Original file: BlackHole/BlackHole.c
Build customization: own bundle/device names, mono 48 kHz, no volume control, no default system output. Modified CanBeDefaultDevice to permit input only, preventing selection as default speaker output.
Local fixes: validate UID-translation qualifier sizes with != (valid sizes must not be rejected); select name formatting at compile time; remove the redundant box-UID comparison. Audio processing is unchanged.
Derived component distributed under GPL v3; complete corresponding source and license are included in this directory.
