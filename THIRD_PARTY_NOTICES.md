# Third-party notices

Alloy3D's original code is covered by the root [MIT License](LICENSE).
The third-party portions identified below retain their respective licenses;
the root MIT license does not relicense the CC BY-SA portion.

## BorderlessWindow — CC BY-SA 3.0

- Location: the explicitly marked `BorderlessWindow` declaration and implementation
  in [application/src/app_delegate.mm](application/src/app_delegate.mm).
- Original author: [user1467310](https://stackoverflow.com/users/1467310/user1467310).
- Source: [answer to “keyDown not being called”](https://stackoverflow.com/a/11638926),
  posted July 24, 2012.
- License: [Creative Commons Attribution-ShareAlike 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/)
  ([legal code](https://creativecommons.org/licenses/by-sa/3.0/legalcode.en)).
- Changes for Alloy3D: removed the empty instance-variable block and adjusted
  formatting. The two window eligibility overrides keep the source behavior.

This adapted portion is distributed under CC BY-SA 3.0. Retain its attribution,
source and license links, and identify further adaptations. Adaptations of this
portion must be distributed under a license permitted by its ShareAlike terms.
The identification of this portion does not assert an MIT-only license for it
or imply endorsement by the original author or Stack Overflow.

## ACES filmic tone-mapping approximation — CC0 1.0

- Locations: the ACES curve expression in [shaders/post_process.metal](shaders/post_process.metal)
  and its reference calculation in [tools/forest_probe.mm](tools/forest_probe.mm).
- Author: Krzysztof Narkowicz.
- Source: [“ACES Filmic Tone Mapping Curve”](https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/),
  January 6, 2016.
- The author offers the fitted curve code under CC0 or MIT. Alloy3D uses the
  [CC0 1.0 option](https://creativecommons.org/publicdomain/zero/1.0/).
- Changes: inlined the coefficients into the Metal expression and used the same
  approximation for the sample's reference calculation.

This is the author's fitted approximation, not a full ACES implementation or
an assertion of endorsement by the author or the Academy.

## cgltf — MIT

Location: [third_party/cgltf/cgltf.h](third_party/cgltf/cgltf.h).
Source: [cgltf](https://github.com/jkuhlmann/cgltf).
The original notice is also retained at the end of that header.

Copyright (c) 2018-2021 Johannes Kuhlmann

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

## jsmn, included in cgltf — MIT

Location: the embedded jsmn implementation in
[third_party/cgltf/cgltf.h](third_party/cgltf/cgltf.h).
Source: [jsmn](https://github.com/zserge/jsmn).
The original notice is retained next to the embedded implementation.

Copyright (c) 2010 Serge A. Zaitsev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## Distribution scope

These notices accompany the repository's source distribution. Before distributing
standalone compiled libraries or applications, carry the applicable notices with
those artifacts and check the applicable component licenses. The current build
and install rules do not automate that packaging.
