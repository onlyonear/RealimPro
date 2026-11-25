# Third-Party Notices

RealimPro is original work that also builds on, or references, the following
third-party components. Their original licenses and copyright notices are
preserved here. The RealimPro source code as a whole is distributed under the
**GNU General Public License v2 (GPL-2.0)**; see `LICENSE`.

---

## 1. Impro-Visor — GNU General Public License v2 or later

RealimPro contains a Swift port of substantial portions of **Impro-Visor**
("Improvisation Advisor").

- Authors: Prof. Robert Keller and Harvey Mudd College
- Copyright (C) 2005–2017 Robert Keller and Harvey Mudd College
- Website: https://www.cs.hmc.edu/~keller/jazz/improvisor/
- License: GPL-2.0-or-later. This derivative work is released under GPL-2.0.

The bundled LSTM model files (`Real imPro/LSTM/combination.rnn`,
`GreatMoments.rnn`) belong to the Impro-Visor model family and are covered by
the same GPL terms.

---

## 2. VexFlow — MIT License

A minified build of **VexFlow** (`Real imPro/vexflow-min.js`) is used to render
music notation in the in-app web view.

- Copyright (c) Mohit Muthanna Cheppudira and VexFlow contributors
- License: MIT (permissive; GPL-compatible)

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

---

## 3. music21 — BSD 3-Clause (reference only)

The MusicXML repeat-expansion behavior was independently implemented following
the approach used by **music21**. No music21 source code is included.

- Copyright (c) Michael Scott Cuthbert and the music21 Project
- License: BSD-3-Clause (permissive; GPL-compatible)

---

## 4. ChoriumRevA SoundFont — custom free license (NOT bundled)

The app's instrument sounds are produced by a SoundFont derived from
**Chorium / ChoriumRevA**.

- Author: openwrld (openwrld@kebi.com)
- Distributed by its author as a free SoundFont, with attribution requested.
- Because the original terms do not clearly state redistribution and
  commercial-use rights, **the SoundFont file is deliberately not included in
  this repository and is ignored by Git (see `.gitignore`)**.
- The maintainer has contacted the original author by email to clarify the
  license; no reply had been received at the time of this release. A record of
  that contact is retained.
- See `README.md -> Getting the SoundFont` for how to obtain and place the file
  for local builds.

If you are the rights holder and have any concern about this notice, please
contact the maintainer at onearonly@gmail.com and the reference can be updated
or removed promptly.
