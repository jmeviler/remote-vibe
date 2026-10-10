Protocol implementation adapted from vRemoter (2d906f32b8fc06f98d998b1343d995e7ffed1840).
Source headers credit FanXeon@Poemcoder.
https://github.com/VincentKingHsu/vRemoter

MIT License

Copyright (c) 2026 Sima Qingfeng

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


Interaction reference: https://github.com/Tilkmilk/vibe-mote (fb30e479694524962512b5bba6afc76cd0a04778).
No Windows driver or injection code used.

Xiaomi RC003 protocol and F5 usage reference: SayAll / remote-mic-app
https://github.com/HD838A/remote-mic-app
Reference revision: 24d84d7301aa6cf1820a9d9ee99dba33ff60cb60
Copyright (C) 2026 SayAll contributors. GPL-3.0-only (see ../LICENSE in source,
or LICENSE in the application resources).
RC003 capability parsing, frame accumulation and standard IMA decoding are
adapted for Remote Vibe's shared voice pipeline. No SayAll artwork, drivers,
update services, audio postprocessing or application UI are included.
Upstream credits remote-bridge-hub, GPL-3.0-only, revision
8a93f321ac71a602300c6cd77f7256fa4b63068e:
https://github.com/xxb26553663-star/remote-bridge-hub
