# Third-party notices

This repository ships one file it did not write: `tools/site/vendor/mermaid.min.js`, the browser script that draws the book's diagrams. `make site` copies it, unmodified, into the published website, together with this file. It is a **bundle**: mermaid and the packages below are compiled into the one file. This page names each of them, with its licence, and gives the licence texts once.

Not covered here: the Kits that `make setup` downloads (each keeps its own licence), and the Dart, Flutter and Rust packages that `pub` and `cargo` download on your machine when you build the apps (this repository does not redistribute them). This repository's own licences are in [README.md](README.md#licence).

## The file

| | |
|---|---|
| File | `tools/site/vendor/mermaid.min.js` |
| sha256 | `a8a6a6f805b074a8261a2825c86f99c8054acb3b35f50bb7e24a4f9f2c3c3b9f` |
| Built from | mermaid 12.2.0 (MIT), the `dist/mermaid.min.js` of the npm package `https://registry.npmjs.org/mermaid/-/mermaid-12.2.0.tgz` |
| Tarball sha1 | `8500d2500a57bd10f0c8ab03ec4deff87df36c39` (equal to the `shasum` the npm registry publishes for this version; the file in the tarball is byte-for-byte the vendored file) |
| Which packages are inside | read from the unminified build in the same tarball (`dist/mermaid.js`, sha256 `ffd1a76f0553952a344c68a9b1502dd5cfb6faab72541307b74679c5abc9cec8`), which keeps one `node_modules/.pnpm/<package>@<version>` comment per bundled file; versions are exactly those. 77 packages (67 from those comments, 10 inlined through `@mermaid-js/parser`, see below) |
| Lockfile | The npm tarball ships none. The mermaid repository's `pnpm-lock.yaml` at the tag `mermaid@12.2.0` (sha256 `d75b263b5a0ace23797e375423a7d24e6e208c440c7eb75d4cc4a422de5973ca`) was read for the packages inlined through the parser |
| Fetched | 2026-10-24, over HTTPS, by `tools/gen-third-party-notices.py` (run it again after upgrading the file; see [the vendor README](tools/site/vendor/README.md)) |

Copies of `mermaid.min.js` carry the licence banners the build keeps (DOMPurify, lodash, cytoscape); the rest of the notices are below.

## What needs attention

Everything below is permissive (MIT, ISC, BSD-3-Clause, Apache-2.0) except one licence that is not on that list and one
that offers a choice. Read these before the repository or the site is announced.

| Package | Licence | Why it is listed here | What it asks of us |
|---|---|---|---|
| `elkjs` 0.9.3 | **EPL-2.0** (Eclipse Public License 2.0, a weak, file-level copyleft licence) | It is inside `mermaid.min.js`: `elkjs/lib/elk.bundled.js`, the ELK graph layout engine compiled to JavaScript. 342 occurrences of `org.eclipse.elk` are in the minified file. | When the code is distributed in object form (this file is), the distributor must say that the source is available and how to get it, and give the licence text (below). The source of the exact version is the npm tarball in the table "What was fetched" (its sha1 is there) and the upstream project <https://github.com/kieler/elkjs>, which builds <https://github.com/eclipse/elk>. Changes to EPL-licensed code must stay under the EPL; this repository does not change it (the bundle is mermaid's own build, vendored unmodified). The EPL does not reach this repository's own code or the Kit Book's text, which are separate works under Apache-2.0 and CC BY 4.0; whether a minified bundle of many licences counts as one combined work is a legal question this file does not settle. |
| `dompurify` 3.4.12 | **(MPL-2.0 OR Apache-2.0)**, a choice | Same bundle. The package metadata and the banner kept in the minified file both say "Apache license 2.0 and Mozilla Public License 2.0". | **This project takes DOMPurify under the Apache License 2.0** (the choice the licence gives the recipient). Apache-2.0 is on the permitted list, so nothing more is needed than the notice and licence text below. The copy of `LICENSE` in the npm tarball is the Apache-2.0 text only. |
| `khroma` 2.1.0 | MIT (by its licence file) | The package metadata has no `license` field. | Nothing; the licence file in the tarball is the MIT licence, listed below. |
| `fastdom` 1.0.12 | MIT (by `package.json` and the README) | The tarball has no licence file. | Nothing; the MIT licence is stated in the README of the package, with the copyright line below. |

The permitted list used for the check: 0BSD, Apache-2.0, BSD-2-Clause, BSD-3-Clause, CC0-1.0, ISC, MIT.

## Components

| Package | Version | Licence | Copyright notice(s) in its licence file | How it was found |
|---|---|---|---|---|
| `@braintree/sanitize-url` | 7.1.2 | MIT | Copyright (c) 2017 Braintree | path comment in the build |
| `@chevrotain/cst-dts-gen` | 13.2.0 | Apache-2.0 | copyright notice that is included in or attached to the work; copyright license to reproduce, prepare Derivative Works of,; Copyright [yyyy] [name of copyright owner] | path comment in the build |
| `@chevrotain/gast` | 13.2.0 | Apache-2.0 | copyright notice that is included in or attached to the work; copyright license to reproduce, prepare Derivative Works of,; Copyright [yyyy] [name of copyright owner] | path comment in the build |
| `@chevrotain/regexp-to-ast` | 13.2.0 | Apache-2.0 | copyright notice that is included in or attached to the work; copyright license to reproduce, prepare Derivative Works of,; Copyright [yyyy] [name of copyright owner] | path comment in the build |
| `@chevrotain/types` | 13.2.0 | Apache-2.0 | copyright notice that is included in or attached to the work; copyright license to reproduce, prepare Derivative Works of,; Copyright [yyyy] [name of copyright owner] | inlined through `@mermaid-js/parser` |
| `@chevrotain/utils` | 13.2.0 | Apache-2.0 | copyright notice that is included in or attached to the work; copyright license to reproduce, prepare Derivative Works of,; Copyright [yyyy] [name of copyright owner] | path comment in the build |
| `@iconify/utils` | 3.0.2 | MIT | Copyright (c) 2021-PRESENT Vjacheslav Trushkin | path comment in the build |
| `@mermaid-js/parser` | 2.0.1 | MIT | Copyright (c) 2023 Yokozuna59 | inlined through `@mermaid-js/parser` |
| `@upsetjs/venn.js` | 2.0.0 | MIT | Copyright (c) 2013 Ben Frederickson; Copyright (c) 2021 Samuel Gratzl | path comment in the build |
| `chevrotain` | 13.2.0 | Apache-2.0 | copyright notice that is included in or attached to the work; copyright license to reproduce, prepare Derivative Works of,; Copyright [yyyy] [name of copyright owner] | path comment in the build |
| `chevrotain-allstar` | 0.5.0 | MIT | Copyright 2022 TypeFox GmbH | inlined through `@mermaid-js/parser` |
| `cose-base` | 1.0.3 | MIT | Copyright (c) 2019 - present, iVis@Bilkent. | path comment in the build |
| `cose-base` | 2.2.0 | MIT | Copyright (c) 2019 - present, iVis@Bilkent. | path comment in the build |
| `cytoscape` | 3.34.0 | MIT | Copyright (c) 2016-2026, The Cytoscape Consortium. | path comment in the build |
| `cytoscape-cose-bilkent` | 4.1.0 | MIT | Copyright (c) 2016-2018, The Cytoscape Consortium. | path comment in the build |
| `cytoscape-fcose` | 2.2.0 | MIT | Copyright (c) 2018 - present, iVis-at-Bilkent. | path comment in the build |
| `d3` | 7.9.0 | ISC | Copyright 2010-2023 Mike Bostock | path comment in the build |
| `d3-array` | 2.12.1 | BSD-3-Clause | Copyright 2010-2020 Mike Bostock | path comment in the build |
| `d3-array` | 3.2.4 | ISC | Copyright 2010-2023 Mike Bostock | path comment in the build |
| `d3-axis` | 3.0.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-brush` | 3.0.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-chord` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-color` | 3.1.0 | ISC | Copyright 2010-2022 Mike Bostock | path comment in the build |
| `d3-contour` | 4.0.2 | ISC | Copyright 2012-2023 Mike Bostock | path comment in the build |
| `d3-delaunay` | 6.0.4 | ISC | Copyright 2018-2021 Observable, Inc.; Copyright 2021 Mapbox | path comment in the build |
| `d3-dispatch` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-drag` | 3.0.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-dsv` | 3.0.1 | ISC | Copyright 2013-2021 Mike Bostock | path comment in the build |
| `d3-ease` | 3.0.1 | BSD-3-Clause | Copyright 2010-2021 Mike Bostock; Copyright 2001 Robert Penner | path comment in the build |
| `d3-fetch` | 3.0.1 | ISC | Copyright 2016-2021 Mike Bostock | path comment in the build |
| `d3-force` | 3.0.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-format` | 3.1.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-geo` | 3.1.1 | ISC | Copyright 2010-2024 Mike Bostock; Copyright 2008-2012 Charles Karney; COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER | path comment in the build |
| `d3-hierarchy` | 3.1.2 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-interpolate` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-path` | 1.0.9 | BSD-3-Clause | Copyright 2015-2016 Mike Bostock | path comment in the build |
| `d3-path` | 3.1.0 | ISC | Copyright 2015-2022 Mike Bostock | path comment in the build |
| `d3-polygon` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-quadtree` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-random` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-sankey` | 0.12.3 | BSD-3-Clause | Copyright 2015, Mike Bostock | path comment in the build |
| `d3-scale` | 4.0.2 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-scale-chromatic` | 3.1.0 | ISC | Copyright 2010-2024 Mike Bostock; Copyright 2002 Cynthia Brewer, Mark Harrower, and The Pennsylvania State University | path comment in the build |
| `d3-selection` | 3.0.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-shape` | 1.3.7 | BSD-3-Clause | Copyright 2010-2015 Mike Bostock | path comment in the build |
| `d3-shape` | 3.2.0 | ISC | Copyright 2010-2022 Mike Bostock | path comment in the build |
| `d3-time` | 3.1.0 | ISC | Copyright 2010-2022 Mike Bostock | path comment in the build |
| `d3-time-format` | 4.1.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-timer` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-transition` | 3.0.1 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `d3-zoom` | 3.0.0 | ISC | Copyright 2010-2021 Mike Bostock | path comment in the build |
| `dagre-d3-es` | 7.0.14 | MIT | Copyright (c) 2022-2024 Thibaut Lassalle, David Newell, Alois Klink, Sidharth Vinod and dagre-es contributors | path comment in the build |
| `dayjs` | 1.11.21 | MIT | Copyright (c) 2018-present, iamkun | path comment in the build |
| `dompurify` | 3.4.12 | (MPL-2.0 OR Apache-2.0) **(attention)** | copyright notice that is included in or attached to the work; copyright license to reproduce, prepare Derivative Works of,; Copyright [yyyy] [name of copyright owner] | path comment in the build |
| `elkjs` | 0.9.3 | EPL-2.0 **(attention)** | copyright rights in its Contribution, if any, to grant the copyright | path comment in the build |
| `es-toolkit` | 1.45.1 | MIT | Copyright (c) 2024 Viva Republica, Inc; Copyright OpenJS Foundation and other contributors | path comment in the build |
| `fastdom` | 1.0.12 | MIT | Copyright (c) 2016 Wilson Page <wilsonpage@me.com> | path comment in the build |
| `internmap` | 2.0.3 | ISC | Copyright 2021 Mike Bostock | path comment in the build |
| `js-yaml` | 4.3.0 | MIT | Copyright (C) 2011-2015 by Vitaly Puzrin | path comment in the build |
| `katex` | 0.18.11 | MIT | Copyright (c) 2013-2020 Khan Academy and other contributors | path comment in the build |
| `khroma` | 2.1.0 | MIT (from its licence file; none declared in the metadata) | Copyright (c) 2019-present Fabio Spampinato, Andrew Maney | path comment in the build |
| `langium` | 4.4.0 | MIT | Copyright 2021 TypeFox GmbH | inlined through `@mermaid-js/parser` |
| `layout-base` | 1.0.2 | MIT | Copyright (c) 2019 iVis@Bilkent | path comment in the build |
| `layout-base` | 2.0.1 | MIT | Copyright (c) 2019 iVis@Bilkent | path comment in the build |
| `lodash-es` | 4.18.1 | MIT | Copyright OpenJS Foundation and other contributors <https://openjsf.org/>; Copyright and related rights for sample code are waived via CC0. Sample | path comment in the build |
| `marked` | 16.3.0 | MIT | Copyright (c) 2018+, MarkedJS (https://github.com/markedjs/); Copyright (c) 2011-2018, Christopher Jeffrey (https://github.com/chjj/); Copyright © 2004, John Gruber | path comment in the build |
| `mermaid` | 12.2.0 | MIT | Copyright (c) 2014 - 2022 Knut Sveidqvist | the project itself |
| `roughjs` | 4.6.6 | MIT | Copyright (c) 2019 Preet Shihn | path comment in the build |
| `stylis` | 4.3.6 | MIT | Copyright (c) 2016-present Sultan Tarimo | path comment in the build |
| `ts-dedent` | 2.2.0 | MIT | Copyright (c) 2018 Tamino Martinius | path comment in the build |
| `uuid` | 14.0.0 | MIT | Copyright (c) 2010-2020 Robert Kieffer and other contributors | path comment in the build |
| `vscode-jsonrpc` | 9.0.3 | MIT | Copyright (c) Microsoft Corporation | inlined through `@mermaid-js/parser` |
| `vscode-languageserver` | 10.1.1 | MIT | Copyright (c) Microsoft Corporation | inlined through `@mermaid-js/parser` |
| `vscode-languageserver-protocol` | 3.18.4 | MIT | Copyright (c) Microsoft Corporation | inlined through `@mermaid-js/parser` |
| `vscode-languageserver-textdocument` | 1.0.15 | MIT | Copyright (c) Microsoft Corporation | inlined through `@mermaid-js/parser` |
| `vscode-languageserver-types` | 3.18.4 | MIT | Copyright (c) Microsoft Corporation | inlined through `@mermaid-js/parser` |
| `vscode-uri` | 3.1.0 | MIT | Copyright (c) Microsoft | inlined through `@mermaid-js/parser` |

Two packages appear twice or more at different versions (`d3-array`, `d3-path`, `d3-shape`, `cose-base`, `layout-base`) because different parts of the bundle depend on different majors. Where the lockfile holds two patch versions of an inlined package, the highest is listed; the licence does not differ.

## What was fetched

For each package: the registry metadata document, the tarball (its sha1 is the one the registry publishes, and was checked), and the licence file taken from the tarball. The sha256 values are of those exact bytes, as fetched on 2026-10-24.

| Package | Metadata sha256 | Tarball sha1 | Licence file | Licence file sha256 |
|---|---|---|---|---|
| `@braintree/sanitize-url@7.1.2` | `47d32549c03ed7470eedef8620b879374f799fcb500066583d45af00f0669b4e` | `ca2035b0fefe956a8676ff0c69af73e605fcd81f` | `LICENSE` | `0984740e0c3d725c8044dec7edcefe1dbce180ef5a7bc710c251e19607000158` |
| `@chevrotain/cst-dts-gen@13.2.0` | `ebb2f44897802bd0281e6795611971c8d37ef69b4ea3573bb47049c4ac0c9ea2` | `64d904738c224327b14ed616d174cb2c097c8eea` | `LICENSE.txt` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `@chevrotain/gast@13.2.0` | `b3fbdde62d8aec0461d8f24a5f7501dcc407c35aaceb465d407fad7c918349f7` | `3fd21451c3a6d1550e8ef61aca656359fd468644` | `LICENSE.txt` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `@chevrotain/regexp-to-ast@13.2.0` | `9bd8c17ced5352226fcf851ce2c09251eadbdb15b99fd11c1a3dc0a6916f8bdc` | `fc254a6af6461f7cce6a0f5b8ecbd3dd2dadf3ea` | `LICENSE.txt` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `@chevrotain/types@13.2.0` | `4fe0571b6fa6e9b9e260e9c94ddcea6e4fe518df0a3740705d087a4e0e92cd13` | `546500791f9713e8c7bcd1a090fdc232374cf832` | `LICENSE.txt` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `@chevrotain/utils@13.2.0` | `f6ced8e57b88f2ca2739858160854f1a40ce716ab97f00aafa07f69fe9b45fd9` | `87111f7fa043331083adb0e65ec4d8e66ff98688` | `LICENSE.txt` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `@iconify/utils@3.0.2` | `8e28d004658d257c0f043db940d50cefa0a164d9cbb52b8b16e452b6307337a3` | `9599607f20690cd3e7a5d2d459af0eb81a89dc2b` | `license.txt` | `a86793ac023162ce98b91899601c15f6712f44943163c4f92a0a4bf89152b3bf` |
| `@mermaid-js/parser@2.0.1` | `242fc09475a5b685cf6888b60eb96afd4d5eab971e22363e1e61043a93bd35d1` | `ac69b59ead67a3b16a8e6d7ec5159e3cd66ee7c5` | `LICENSE` | `d374061c40bfb6f99c5033290caefda97a9b3e7e477e5ee02f487143ef2177e8` |
| `@upsetjs/venn.js@2.0.0` | `f2cbe7871fd3e8e5afc078875c98b84c86024f407e2cde7e87b038abd5ca1e5b` | `3be192038cdda927aa4f8b22ab51af82abf47f34` | `LICENSE` | `6a3508febf2cfccfee96597394543a6154a4bb0b1f91f28404be42c09e9fcb54` |
| `chevrotain@13.2.0` | `0f08a8f424f4e3eab1d1d873b617988a4e8ef6cd3f88da3e7c609ecf202440df` | `eb4426dcd8befff3d4c2880f8a54367498803ba4` | `LICENSE.txt` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `chevrotain-allstar@0.5.0` | `743ac26c8ada567e2ad1a8121c8e7d5e1a6558791ef770cbabaf27d8f5f95a99` | `439dde76f970f2ce549a8b6eb4298dba7ef00466` | `LICENSE` | `1db2cfbc7ce5fa3b82699b4ac4badce8984084d25b5308ece00f5c9b1381a0a5` |
| `cose-base@1.0.3` | `06d9e8f83eecf28273e601add7c89820f25e9050ffc82c2912a8e706056c8ea6` | `650334b41b869578a543358b80cda7e0abe0a60a` | `LICENSE` | `5fb3cf4a14c3c5af6e473a192df8bca10c77754e3a0c6492c79fb92a76a5478a` |
| `cose-base@2.2.0` | `c5cb4cc492faf3e29c9af23f7f30345084d3c707ea544e7561b225356f7324a5` | `1c395c35b6e10bb83f9769ca8b817d614add5c01` | `LICENSE` | `5fb3cf4a14c3c5af6e473a192df8bca10c77754e3a0c6492c79fb92a76a5478a` |
| `cytoscape@3.34.0` | `50d9e2c13a7bdd4da8415fdee0f27e053654c8ab6a0b214ba79254ba53e10466` | `5fbe2eb1cf76b070a8ecd5647c35f65aa097c9c6` | `LICENSE` | `eb319c6e6f233607f71e8e2f450391751883cfc0eeb3ca7ef574c13d1d9c2203` |
| `cytoscape-cose-bilkent@4.1.0` | `0b2de04e1aa6bca47d4f4783eed5ce7e65fede00f25b39e518ecbb96d60594af` | `762fa121df9930ffeb51a495d87917c570ac209b` | `LICENSE` | `440fc58a56a12814e417d2b341da89b050da052dc75bdb235607d37ec5fe74ef` |
| `cytoscape-fcose@2.2.0` | `693a02d4da94b4e5164b2cbdd26533cacdc0ba6fcd84efa51c1729f98b67cc51` | `e4d6f6490df4fab58ae9cea9e5c3ab8d7472f471` | `LICENSE` | `2837634f403949215760fcdd2fa1ed0c64875d02099ecc8318c704b852f1421d` |
| `d3@7.9.0` | `a8852f42809b57096b811eb24a994fc05612b11068cf6086973466c9edbf02a8` | `579e7acb3d749caf8860bd1741ae8d371070cd5d` | `LICENSE` | `3e6849627f74ff73c257a3ae1efb574015d94fc1035c05ec3c15805165efcbc4` |
| `d3-array@2.12.1` | `aeba34f3b861b7c1ead6a250d109f2d6b767ab5edffa5cc374da925f6da45072` | `e20b41aafcdffdf5d50928004ececf815a465e81` | `LICENSE` | `0747bebeb06b10954913149be9b9a8bdf6fad3e6fdcbd9f9524e7a94c13d2cea` |
| `d3-array@3.2.4` | `efc336f352239ffe4ad51a7e77a0e918bf1019915ee066b801136d802e35a9c1` | `15fec33b237f97ac5d7c986dc77da273a8ed0bb5` | `LICENSE` | `3e6849627f74ff73c257a3ae1efb574015d94fc1035c05ec3c15805165efcbc4` |
| `d3-axis@3.0.0` | `65ac9e37ca77819738a02fdfb2f2701343a2fd51bbb2a1537b56b94c0aa4f01a` | `c42a4a13e8131d637b745fc2973824cfeaf93322` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-brush@3.0.0` | `a1f59424450218081f01dafd09e11caccb858da37222b321f07ea3e207424e24` | `6f767c4ed8dcb79de7ede3e1c0f89e63ef64d31c` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-chord@3.0.1` | `0110fe7cddadb3ba64a6ce7bc929e16e9a4befb7e439890dc2f9000d3128b80e` | `d156d61f485fce8327e6abf339cb41d8cbba6966` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-color@3.1.0` | `85bb4cf747b3f64fee8ad46ff6dbc416d889d2090296cf27016cb39de44eae73` | `395b2833dfac71507f12ac2f7af23bf819de24e2` | `LICENSE` | `faa682e3e430941f958d26180458f5934a62f58dac4d70ccdd15608c15d0f884` |
| `d3-contour@4.0.2` | `704c181306d1f63b51d96616a860d3fc10a7d2282a83df7314e2a881091702ed` | `bb92063bc8c5663acb2422f99c73cbb6c6ae3bcc` | `LICENSE` | `e51cba0e4fa1d8c078e15319868f2b90188f413f9ce9dac1043b62db32901e93` |
| `d3-delaunay@6.0.4` | `74a2ca02083955edbd4657dfc39f1a24993e39580730b38a7eee5e26c7e733fb` | `98169038733a0a5babbeda55054f795bb9e4a58b` | `LICENSE` | `582c3022bd01942336095f92b58a90b1be624dc547d987555c6c956512dd24c1` |
| `d3-dispatch@3.0.1` | `b2eb396e040ae2af159f8c7e45499ed2f35b4af7491838024c12b7fdac827fae` | `5fc75284e9c2375c36c839411a0cf550cbfc4d5e` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-drag@3.0.0` | `8a56ffd0df82a9c5408cdc2860d9926392c0263553ba4c816276ec9c0b4828cb` | `994aae9cd23c719f53b5e10e3a0a6108c69607ba` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-dsv@3.0.1` | `0b74c55612e6e14da3645eeef7b5f59c1c8f8dc4e99d3185117bd259e069cb03` | `c63af978f4d6a0d084a52a673922be2160789b73` | `LICENSE` | `7842a82012622e5a37bfe4f6c1b67cd3bae6350716b5bf87f36cea0bdc1319dc` |
| `d3-ease@3.0.1` | `420fca6d2ef552b861007907df81d2b2281ba7b26558360f1614a6c595a29564` | `9658ac38a2140d59d346160f1f6c30fda0bd12f4` | `LICENSE` | `b989d9085148d21ff64a75e14462aefa06b2589a55553b07b1460c70081c7d08` |
| `d3-fetch@3.0.1` | `2f29e4101089048afe5bb4cea5462848dafa87d3251b1b34f04ca2fead3b4270` | `83141bff9856a0edb5e38de89cdcfe63d0a60a22` | `LICENSE` | `ffdc17dc9040006bddeb891c95bfbb492e86d6bc64a4a4233666febab1be35e0` |
| `d3-force@3.0.0` | `9f09f32eba453073850596cda7a1d1844f0f82c724913ce59f908525eab720f6` | `3e2ba1a61e70888fe3d9194e30d6d14eece155c4` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-format@3.1.0` | `107ec875df2f2858e95d6c3c4803caf284554059fe13cb52d04a44e110b07791` | `9260e23a28ea5cb109e93b21a06e24e2ebd55641` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-geo@3.1.1` | `755cb2734b363cb00edf8003a8aee70cfb52a5de37145af8fb4159da910eebea` | `6027cf51246f9b2ebd64f99e01dc7c3364033a4d` | `LICENSE` | `3e3edc1224eec9c39cd26491a21304a62883c1e5b6a65c5283ccc7a6cc94baee` |
| `d3-hierarchy@3.1.2` | `2f3af515824350e6acd86b9ec0c357e6f922ef7288bb0c8887524dd775760424` | `b01cd42c1eed3d46db77a5966cf726f8c09160c6` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-interpolate@3.0.1` | `7d5b2c6d687b626131c96fc00948bbef399ae46c5ffdfeb88a12030f2d0bbe90` | `3c47aa5b32c5b3dfb56ef3fd4342078a632b400d` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-path@1.0.9` | `eba4bd05cd250f03d1ca6893ffec629b97eae4923688ee716636cb8ff7d0ff36` | `48c050bb1fe8c262493a8caf5524e3e9591701cf` | `LICENSE` | `b8265327ab678f554800e71188b1cc6b1ff57522e292d2b1c0be66f27cf328b6` |
| `d3-path@3.1.0` | `b41bac95560fe34589b26faa7d763e9506d8b36e0bd63cbe0a92a5117c1f59ba` | `22df939032fb5a71ae8b1800d61ddb7851c42526` | `LICENSE` | `a09b0d6d76e768fca2085fad05743ee81ddd11946bcda160a3cf5e1081a479aa` |
| `d3-polygon@3.0.1` | `98598215bcb8a149e3966689cee50527a8a0d5ba2ff779bd2db4f45d58fdcb05` | `0b45d3dd1c48a29c8e057e6135693ec80bf16398` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-quadtree@3.0.1` | `c01550da058b264c4936b1e80d99c3fa791bddc31124105c1648033b83766b2f` | `6dca3e8be2b393c9a9d514dabbd80a92deef1a4f` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-random@3.0.1` | `9c504da01b2d4de030a89758de846416bc0ba8ab3d091b36dee202c57ce3b5d5` | `d4926378d333d9c0bfd1e6fa0194d30aebaa20f4` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-sankey@0.12.3` | `2564cd8954660a9b8a33112944d09a619b840e048da683d20a38d9e2cf1a27c9` | `b3c268627bd72e5d80336e8de6acbfec9d15d01d` | `LICENSE` | `2bf785e778d67a4f5266cffcd4f2cc5bb98cde73791666e7efeb8002ba32dfa5` |
| `d3-scale@4.0.2` | `d54b5c17c1c85071ed35b71c46160d4d2a9a4f4cbebdfc7cb32cc3a75d637951` | `82b38e8e8ff7080764f8dcec77bd4be393689396` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-scale-chromatic@3.1.0` | `b38590190a0e2faf7c34c33a541ef49a53b53eb9708374ef07bdae873108fd65` | `34c39da298b23c20e02f1a4b239bd0f22e7f1314` | `LICENSE` | `0986d93944902cca9af86824b6a641b4b7c2d10602fc510c433a8bcd443919fe` |
| `d3-selection@3.0.0` | `ad3a82c93377f90bb52dc5c88d4137d17358b79aa0996736c937975247d3e4ca` | `c25338207efa72cc5b9bd1458a1a41901f1e1b31` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-shape@1.3.7` | `238e90fa1c6304ef26cb415e1a583e8a3c131e752866c43806d7d500ef6603a0` | `df63801be07bc986bc54f63789b4fe502992b5d7` | `LICENSE` | `7eea8533ea92bd8c32a901e89ecb0305890905bb12711449565ddff96891146d` |
| `d3-shape@3.2.0` | `5109e9194deac647e0ed48fdef983386fc786238739c148ac6ac09fe956ad6eb` | `a1a839cbd9ba45f28674c69d7f855bcf91dfc6a5` | `LICENSE` | `faa682e3e430941f958d26180458f5934a62f58dac4d70ccdd15608c15d0f884` |
| `d3-time@3.1.0` | `6bc04ee13779fe228160e61f0820d55ad08a9368ad6e90387df613da61182db6` | `9310db56e992e3c0175e1ef385e545e48a9bb5c7` | `LICENSE` | `faa682e3e430941f958d26180458f5934a62f58dac4d70ccdd15608c15d0f884` |
| `d3-time-format@4.1.0` | `d35c1f7e9fb5d8058c9659bae40e4b11f8ab1aa27f98421373ea781f569e12dc` | `7ab5257a5041d11ecb4fe70a5c7d16a195bb408a` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-timer@3.0.1` | `dcce69a0bb17b1c0116b5a8d32c71b3bd8802a19c1277a9c2da76d2b2bb39213` | `6284d2a2708285b1abb7e201eda4380af35e63b0` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-transition@3.0.1` | `83ffcb5a7430b7647acef661b8f36de027c722b6954ce464d6245762ca9bde5f` | `6869fdde1448868077fdd5989200cb61b2a1645f` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `d3-zoom@3.0.0` | `9d2d220a366a69969b9ab12ae4c08d05763561df7071e7e4d0c7ac4d96e0436d` | `d13f4165c73217ffeaa54295cd6969b3e7aee8f3` | `LICENSE` | `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee` |
| `dagre-d3-es@7.0.14` | `7ca7a5dffe34cfdcd49ad74250c097c7fea6de5d226caefd4896b8a9af63d1de` | `1272276e26457cf3b97dac569f8f0531ec33c377` | `LICENSE.md` | `d01eb84ccce437dbf5fd40853bceea0f287930920acea066597a4a25ead63858` |
| `dayjs@1.11.21` | `a04614247bbc82f7452a3aedf89da7302b76f5c83856524af2c29b13ac1113b6` | `57f87562e62de76f3c704bd2b8d522fc33068eb2` | `LICENSE` | `5faab7526d055651be3aab769d58897be6bd91f3d39d137f25f12dba1b31d5dc` |
| `dompurify@3.4.12` | `39c258b5a49f9a907a7121914109b40d05a338a2e857117c9e675f9dc5cf7248` | `6fa2265e9bbdce882c4ace4107626051b448ffa8` | `LICENSE` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `elkjs@0.9.3` | `abb0ec3308c8ccd3ea6aaee8c7c094108bf5bb5db904ff9d8c0a670204612769` | `16711f8ceb09f1b12b99e971b138a8384a529161` | `LICENSE.md` | `89591d4578fb1ebd91501312a3d25f021bd865a2e436641c1cf7b1bc7e3c1617` |
| `es-toolkit@1.45.1` | `044746e01957d5c2e2733de17ab158e3632e698f2a3b8013f2988fe350a439bd` | `21b28b2bd43178fd4c9c937c445d5bcaccce907b` | `LICENSE` | `ed68888a2a28f32a05e88f24d4d4ee75075a1bda2b6372a1f2e00fa0576a5524` |
| `fastdom@1.0.12` | `5a2cee4f117bc194bb923afd460dec3e86967c38cc65f939efc8c9c966d215a1` | `ae43d55af017252ae499b2e186511ab97412de39` | `README.md (licence section)` | `50c0de64f5cd5e39859b43f7eca7f5843fb3c3d5ac7e34a453e27419ad51e08c` |
| `internmap@2.0.3` | `efff9214ae9163a79f6c925b1fd68cb5a4d92a053f376ab4df25e1ae9ae01a0a` | `6685f23755e43c524e251d29cbc97248e3061009` | `LICENSE` | `9ea8903938dab5f12c4572d60725069bec2d1b0dc3bcc210b09bae946a5ebb1f` |
| `js-yaml@4.3.0` | `4b02807ee34fe30d821a23060ada59b9d06da1b3d248a7663751f46d827348f2` | `d1900572a7f7cf0b5f540c83673e60bad3436592` | `LICENSE` | `a07bc24468b9654ce76a547d47a2db282d07733b715db4c73a98bd63961f9550` |
| `katex@0.18.11` | `03afff21fb4dc3ee59546b9e1dad162c6d35820f27457ba2822537e6a2acbcf1` | `ca4e9e6db78aeff485c3a1dbe46a08bf196defe9` | `LICENSE` | `766ccc1f306c885aa45542a9846bbd0a505b27a0374f146778171c2254ce18e3` |
| `khroma@2.1.0` | `523d6298a1a0dffc7196c57571bfb27e77809ab19391af7092c46f59c559e044` | `45f2ce94ce231a437cf5b63c2e886e6eb42bbbb1` | `license` | `66b333b0f66759a0b710459e03f7029abe17f4358114a128d2c972e642961b49` |
| `langium@4.4.0` | `4b663e16957a03d6704e15cd9e569d438fca8f55281da8cfabdcace5621c37b5` | `89137445dcfd4143753ac77797e579666760066f` | `LICENSE` | `599bf70b4e55f06250571d103dbd8441e0c47cb7f858c0147ca312ce38e9ef2a` |
| `layout-base@1.0.2` | `2dadc00c8afbc27c6be3108590473b27daca8b38f8bd477e5b5356ebc0f28174` | `1291e296883c322a9dd4c5dd82063721b53e26e2` | `LICENSE` | `eabb762d8a95109a39c9be3247325529a5239a7aca327d909c3ccdc41f3a06bf` |
| `layout-base@2.0.1` | `75def23dd3bbd9028ba4504978d3972b355f88fabc85270d807979809b860940` | `d0337913586c90f9c2c075292069f5c2da5dd285` | `LICENSE` | `eabb762d8a95109a39c9be3247325529a5239a7aca327d909c3ccdc41f3a06bf` |
| `lodash-es@4.18.1` | `175e33b8efa9221ac159d49fdea2d70ec967d02bbd4e2f4613da9993bf920dea` | `b962eeb80d9d983a900bf342961fb7418ca10b1d` | `LICENSE` | `f71e8ed126b46346494aad5486874cd8f0aafe95092ed67d2e3cb6110f939abc` |
| `marked@16.3.0` | `5c7117f46954b48b9068005f7c7a717797d29c1c6a6e5e63ea326c1ce7560692` | `2f513891f867d6edc4772b4a026db9cc331eb94f` | `LICENSE.md` | `8e3a3f82f59a60958f56ca08f445647c32a4733dc7ca6c2c46f6eb898471ab9c` |
| `mermaid@12.2.0` | `ad544b494ceb01f572fcb0856a7244648f82f821316fc4c051bafb0185abb0bc` | `8500d2500a57bd10f0c8ab03ec4deff87df36c39` | `LICENSE` | `ec9fb67dcb25eccc416ed56e1aab819222c805a2a4bfe4cb19e7556bf2ffde80` |
| `roughjs@4.6.6` | `5bbfdba7a1dc7a8e2b7fe4fad275018bb726346d52a561352562f814a16b721c` | `1059f49a5e0c80dee541a005b20cc322b222158b` | `LICENSE` | `dca9a392272606ac748ac0976a2a1133f14eef841c27beaa51a844d53c56a09d` |
| `stylis@4.3.6` | `80d3411c537d63df13c9830454c4a613d1e7fa53a4b2abc725ca0fe13f3fe38d` | `7c7b97191cb4f195f03ecab7d52f7902ed378320` | `LICENSE` | `88c579c6ee44b41137a21321190d177982e5b17d4fa1b83a4a2e3ea325a8fc9a` |
| `ts-dedent@2.2.0` | `eb745d6a3d13d5dc0cb13fe2a8aa16c233a5d00d72dcd91b8bb43f0fd1974965` | `39e4bd297cd036292ae2394eb3412be63f563bb5` | `LICENSE` | `eff13095d9d762c3bd9dda74370c81e2130c28f2691bc455603abf973bac25b9` |
| `uuid@14.0.0` | `afed241ba8e324aebc43bce60ec011146f5c142a84e0795795b3c91ee18f2ff8` | `0af883220163d264ffe0c084f6b8a89b9666966d` | `LICENSE.md` | `beaa6b04fb82e41dd2ad679e19e27953afb5999b1abbb455b6564e78ebfeb332` |
| `vscode-jsonrpc@9.0.3` | `6f385639c57c7b1ffbeb5a256e220b5f87a7119b83c1dcc7cba2609c726b29bb` | `98c7c2873de7824402ee5785851e33149bb4fd3a` | `License.txt` | `ec9ee83580841e8eb687aca9867f221503809ba6426c7f876ede17d91b9fcfd0` |
| `vscode-languageserver@10.1.1` | `e0876706804636a28a0f4c946307aee16eb265119ac04a353ddce6678eb217af` | `300898e9a88198fb074e8290a2e6a471e94fd484` | `License.txt` | `ec9ee83580841e8eb687aca9867f221503809ba6426c7f876ede17d91b9fcfd0` |
| `vscode-languageserver-protocol@3.18.4` | `48a86f4bfb877cd88f4680404147fc35afc2db35f4eb3a9e25120f2edd1ad003` | `897e7a9c8f46b36e39e03a85ef8a2050f98f94a2` | `License.txt` | `ec9ee83580841e8eb687aca9867f221503809ba6426c7f876ede17d91b9fcfd0` |
| `vscode-languageserver-textdocument@1.0.15` | `8746875c33830226197f51df0db053eb80dad3c685f6d5515fe9a4ab3a84b8c1` | `5e74ef9b83ec91c812625e0f56bab36e71f9fd07` | `License.txt` | `ec9ee83580841e8eb687aca9867f221503809ba6426c7f876ede17d91b9fcfd0` |
| `vscode-languageserver-types@3.18.4` | `3af5028ecf9b346175d1f464983ec5c0b505bb506fcee75e1bb7dbda46e1458e` | `9fc9ba2bc5006a4335b159c7a41027bd8c7c3a07` | `License.txt` | `ec9ee83580841e8eb687aca9867f221503809ba6426c7f876ede17d91b9fcfd0` |
| `vscode-uri@3.1.0` | `4a113f58bd08b0b10ba0371cc1b5c4c6ab6959e143b460901accccf1fc662595` | `dd09ec5a66a38b5c3fffc774015713496d14e09c` | `LICENSE.md` | `c669138cb1eb01fbb745e8e460b291e4f2869c14a40061390b6095d845ed4c82` |

The addresses are `https://registry.npmjs.org/<name>/<version>` for the metadata and the `dist.tarball` address inside it for the tarball. `fastdom` ships no licence file; its text is the licence section of its README, and `khroma`'s metadata has no `license` field (its licence file is MIT).

## Licence texts

Each distinct text appears once, exactly as the first package listed under it ships it; the other packages listed share the same wording apart from the copyright line, which is in the Components table. Apache-2.0 and the EPL are the standard texts.

### 1. (MPL-2.0 OR Apache-2.0) / Apache-2.0

Applies to: `dompurify 3.4.12`, `@chevrotain/cst-dts-gen 13.2.0`, `@chevrotain/gast 13.2.0`, `@chevrotain/regexp-to-ast 13.2.0`, `@chevrotain/types 13.2.0`, `@chevrotain/utils 13.2.0`, `chevrotain 13.2.0`.

`dompurify` is taken under the Apache License 2.0 (its package offers MPL-2.0 or Apache-2.0); see the attention table.

Text as shipped by `dompurify 3.4.12` (`LICENSE`):

```text

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

### 2. BSD-3-Clause

Applies to: `d3-array 2.12.1`, `d3-ease 3.0.1`, `d3-path 1.0.9`, `d3-sankey 0.12.3`, `d3-shape 1.3.7`.

Text as shipped by `d3-array 2.12.1` (`LICENSE`):

```text
Copyright 2010-2020 Mike Bostock
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the author nor the names of contributors may be used to
  endorse or promote products derived from this software without specific prior
  written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### 3. EPL-2.0

Applies to: `elkjs 0.9.3`.

Text as shipped by `elkjs 0.9.3` (`LICENSE.md`):

```text
# Eclipse Public License - v 2.0

THE ACCOMPANYING PROGRAM IS PROVIDED UNDER THE TERMS OF THIS ECLIPSE
PUBLIC LICENSE (“AGREEMENT”). ANY USE, REPRODUCTION OR DISTRIBUTION OF
THE PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE OF THIS AGREEMENT.

## 1. DEFINITIONS

“Contribution” means:

-   a\) in the case of the initial Contributor, the initial content
    Distributed under this Agreement, and
-   b\) in the case of each subsequent Contributor:
    -   i\) changes to the Program, and
    -   ii\) additions to the Program;

    where such changes and/or additions to the Program originate from
    and are Distributed by that particular Contributor. A Contribution
    “originates” from a Contributor if it was added to the Program by
    such Contributor itself or anyone acting on such Contributor's
    behalf. Contributions do not include changes or additions to the
    Program that are not Modified Works.

“Contributor” means any person or entity that Distributes the Program.

“Licensed Patents” mean patent claims licensable by a Contributor which
are necessarily infringed by the use or sale of its Contribution alone
or when combined with the Program.

“Program” means the Contributions Distributed in accordance with this
Agreement.

“Recipient” means anyone who receives the Program under this Agreement
or any Secondary License (as applicable), including Contributors.

“Derivative Works” shall mean any work, whether in Source Code or other
form, that is based on (or derived from) the Program and for which the
editorial revisions, annotations, elaborations, or other modifications
represent, as a whole, an original work of authorship.

“Modified Works” shall mean any work in Source Code or other form that
results from an addition to, deletion from, or modification of the
contents of the Program, including, for purposes of clarity any new file
in Source Code form that contains any contents of the Program. Modified
Works shall not include works that contain only declarations,
interfaces, types, classes, structures, or files of the Program solely
in each case in order to link to, bind by name, or subclass the Program
or Modified Works thereof.

“Distribute” means the acts of a) distributing or b) making available in
any manner that enables the transfer of a copy.

“Source Code” means the form of a Program preferred for making
modifications, including but not limited to software source code,
documentation source, and configuration files.

“Secondary License” means either the GNU General Public License, Version
2.0, or any later versions of that license, including any exceptions or
additional permissions as identified by the initial Contributor.

## 2. GRANT OF RIGHTS

-   a\) Subject to the terms of this Agreement, each Contributor hereby
    grants Recipient a non-exclusive, worldwide, royalty-free copyright
    license to reproduce, prepare Derivative Works of, publicly display,
    publicly perform, Distribute and sublicense the Contribution of such
    Contributor, if any, and such Derivative Works.
-   b\) Subject to the terms of this Agreement, each Contributor hereby
    grants Recipient a non-exclusive, worldwide, royalty-free patent license
    under Licensed Patents to make, use, sell, offer to sell, import and
    otherwise transfer the Contribution of such Contributor, if any, in
    Source Code or other form. This patent license shall apply to the
    combination of the Contribution and the Program if, at the time the
    Contribution is added by the Contributor, such addition of the
    Contribution causes such combination to be covered by the
    Licensed Patents. The patent license shall not apply to any other
    combinations which include the Contribution. No hardware per se is
    licensed hereunder.
-   c\) Recipient understands that although each Contributor grants the
    licenses to its Contributions set forth herein, no assurances are
    provided by any Contributor that the Program does not infringe the
    patent or other intellectual property rights of any other entity. Each
    Contributor disclaims any liability to Recipient for claims brought by
    any other entity based on infringement of intellectual property rights
    or otherwise. As a condition to exercising the rights and licenses
    granted hereunder, each Recipient hereby assumes sole responsibility to
    secure any other intellectual property rights needed, if any. For
    example, if a third party patent license is required to allow Recipient
    to Distribute the Program, it is Recipient's responsibility to acquire
    that license before distributing the Program.
-   d\) Each Contributor represents that to its knowledge it has sufficient
    copyright rights in its Contribution, if any, to grant the copyright
    license set forth in this Agreement.
-   e\) Notwithstanding the terms of any Secondary License, no Contributor
    makes additional grants to any Recipient (other than those set forth in
    this Agreement) as a result of such Recipient's receipt of the Program
    under the terms of a Secondary License (if permitted under the terms of
    Section 3).

## 3. REQUIREMENTS

3.1 If a Contributor Distributes the Program in any form, then:

-   a\) the Program must also be made available as Source Code, in accordance
    with section 3.2, and the Contributor must accompany the Program with a
    statement that the Source Code for the Program is available under this
    Agreement, and informs Recipients how to obtain it in a reasonable
    manner on or through a medium customarily used for software exchange;
    and
-   b\) the Contributor may Distribute the Program under a license different
    than this Agreement, provided that such license:
    -   i\) effectively disclaims on behalf of all other Contributors all
        warranties and conditions, express and implied, including warranties or
        conditions of title and non-infringement, and implied warranties or
        conditions of merchantability and fitness for a particular purpose;
    -   ii\) effectively excludes on behalf of all other Contributors all
        liability for damages, including direct, indirect, special, incidental
        and consequential damages, such as lost profits;
    -   iii\) does not attempt to limit or alter the recipients' rights in the
        Source Code under section 3.2; and
    -   iv\) requires any subsequent distribution of the Program by any party to
        be under a license that satisfies the requirements of this section 3.

3.2 When the Program is Distributed as Source Code:

-   a\) it must be made available under this Agreement, or if the Program (i)
    is combined with other material in a separate file or files made
    available under a Secondary License, and (ii) the initial Contributor
    attached to the Source Code the notice described in Exhibit A of this
    Agreement, then the Program may be made available under the terms of
    such Secondary Licenses, and
-   b\) a copy of this Agreement must be included with each copy of
    the Program.

3.3 Contributors may not remove or alter any copyright, patent,
trademark, attribution notices, disclaimers of warranty, or limitations
of liability (‘notices’) contained within the Program from any copy of
the Program which they Distribute, provided that Contributors may add
their own appropriate notices.

## 4. COMMERCIAL DISTRIBUTION

Commercial distributors of software may accept certain responsibilities
with respect to end users, business partners and the like. While this
license is intended to facilitate the commercial use of the Program, the
Contributor who includes the Program in a commercial product offering
should do so in a manner which does not create potential liability for
other Contributors. Therefore, if a Contributor includes the Program in
a commercial product offering, such Contributor (“Commercial
Contributor”) hereby agrees to defend and indemnify every other
Contributor (“Indemnified Contributor”) against any losses, damages and
costs (collectively “Losses”) arising from claims, lawsuits and other
legal actions brought by a third party against the Indemnified
Contributor to the extent caused by the acts or omissions of such
Commercial Contributor in connection with its distribution of the
Program in a commercial product offering. The obligations in this
section do not apply to any claims or Losses relating to any actual or
alleged intellectual property infringement. In order to qualify, an
Indemnified Contributor must: a) promptly notify the Commercial
Contributor in writing of such claim, and b) allow the Commercial
Contributor to control, and cooperate with the Commercial Contributor
in, the defense and any related settlement negotiations. The Indemnified
Contributor may participate in any such claim at its own expense.

For example, a Contributor might include the Program in a commercial
product offering, Product X. That Contributor is then a Commercial
Contributor. If that Commercial Contributor then makes performance
claims, or offers warranties related to Product X, those performance
claims and warranties are such Commercial Contributor's responsibility
alone. Under this section, the Commercial Contributor would have to
defend claims against the other Contributors related to those
performance claims and warranties, and if a court requires any other
Contributor to pay any damages as a result, the Commercial Contributor
must pay those damages.

## 5. NO WARRANTY {#warranty}

EXCEPT AS EXPRESSLY SET FORTH IN THIS AGREEMENT, AND TO THE EXTENT
PERMITTED BY APPLICABLE LAW, THE PROGRAM IS PROVIDED ON AN “AS IS”
BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS OF
TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A PARTICULAR
PURPOSE. Each Recipient is solely responsible for determining the
appropriateness of using and distributing the Program and assumes all
risks associated with its exercise of rights under this Agreement,
including but not limited to the risks and costs of program errors,
compliance with applicable laws, damage to or loss of data, programs or
equipment, and unavailability or interruption of operations.

## 6. DISCLAIMER OF LIABILITY {#disclaimer}

EXCEPT AS EXPRESSLY SET FORTH IN THIS AGREEMENT, AND TO THE EXTENT
PERMITTED BY APPLICABLE LAW, NEITHER RECIPIENT NOR ANY CONTRIBUTORS
SHALL HAVE ANY LIABILITY FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING WITHOUT LIMITATION LOST
PROFITS), HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OR DISTRIBUTION OF THE PROGRAM OR THE
EXERCISE OF ANY RIGHTS GRANTED HEREUNDER, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.

## 7. GENERAL

If any provision of this Agreement is invalid or unenforceable under
applicable law, it shall not affect the validity or enforceability of
the remainder of the terms of this Agreement, and without further action
by the parties hereto, such provision shall be reformed to the minimum
extent necessary to make such provision valid and enforceable.

If Recipient institutes patent litigation against any entity (including
a cross-claim or counterclaim in a lawsuit) alleging that the Program
itself (excluding combinations of the Program with other software or
hardware) infringes such Recipient's patent(s), then such Recipient's
rights granted under Section 2(b) shall terminate as of the date such
litigation is filed.

All Recipient's rights under this Agreement shall terminate if it fails
to comply with any of the material terms or conditions of this Agreement
and does not cure such failure in a reasonable period of time after
becoming aware of such noncompliance. If all Recipient's rights under
this Agreement terminate, Recipient agrees to cease use and distribution
of the Program as soon as reasonably practicable. However, Recipient's
obligations under this Agreement and any licenses granted by Recipient
relating to the Program shall continue and survive.

Everyone is permitted to copy and distribute copies of this Agreement,
but in order to avoid inconsistency the Agreement is copyrighted and may
only be modified in the following manner. The Agreement Steward reserves
the right to publish new versions (including revisions) of this
Agreement from time to time. No one other than the Agreement Steward has
the right to modify this Agreement. The Eclipse Foundation is the
initial Agreement Steward. The Eclipse Foundation may assign the
responsibility to serve as the Agreement Steward to a suitable separate
entity. Each new version of the Agreement will be given a distinguishing
version number. The Program (including Contributions) may always be
Distributed subject to the version of the Agreement under which it was
received. In addition, after a new version of the Agreement is
published, Contributor may elect to Distribute the Program (including
its Contributions) under the new version.

Except as expressly stated in Sections 2(a) and 2(b) above, Recipient
receives no rights or licenses to the intellectual property of any
Contributor under this Agreement, whether expressly, by implication,
estoppel or otherwise. All rights in the Program not expressly granted
under this Agreement are reserved. Nothing in this Agreement is intended
to be enforceable by any entity that is not a Contributor or Recipient.
No third-party beneficiary rights are created under this Agreement.

## Exhibit A – Form of Secondary Licenses Notice {#exhibit-a}

“This Source Code may also be made available under the following
Secondary Licenses when the conditions for such availability set forth
in the Eclipse Public License, v. 2.0 are satisfied: {name license(s),
version(s), and exceptions or additional permissions here}.”

> Simply including a copy of this Agreement, including this Exhibit A is
> not sufficient to license the Source Code under Secondary Licenses.
>
> If it is not possible or desirable to put the notice in a particular
> file, then You may include the notice in a location (such as a LICENSE
> file in a relevant directory) where a recipient would be likely to
> look for such a notice.
>
> You may add additional accurate notices of copyright ownership.
```

### 4. ISC

Applies to: `d3-scale-chromatic 3.1.0`.

Text as shipped by `d3-scale-chromatic 3.1.0` (`LICENSE`):

```text
Copyright 2010-2024 Mike Bostock

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.

Apache-Style Software License for ColorBrewer software and ColorBrewer Color Schemes

Copyright 2002 Cynthia Brewer, Mark Harrower, and The Pennsylvania State University

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
```

### 5. ISC

Applies to: `d3-geo 3.1.1`.

Text as shipped by `d3-geo 3.1.1` (`LICENSE`):

```text
Copyright 2010-2024 Mike Bostock

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.

This license applies to GeographicLib, versions 1.12 and later.

Copyright 2008-2012 Charles Karney

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 6. ISC

Applies to: `d3 7.9.0`, `d3-array 3.2.4`, `d3-axis 3.0.0`, `d3-brush 3.0.0`, `d3-chord 3.0.1`, `d3-color 3.1.0`, `d3-contour 4.0.2`, `d3-delaunay 6.0.4`, `d3-dispatch 3.0.1`, `d3-drag 3.0.0`, `d3-dsv 3.0.1`, `d3-fetch 3.0.1`, `d3-force 3.0.0`, `d3-format 3.1.0`, `d3-hierarchy 3.1.2`, `d3-interpolate 3.0.1`, `d3-path 3.1.0`, `d3-polygon 3.0.1`, `d3-quadtree 3.0.1`, `d3-random 3.0.1`, `d3-scale 4.0.2`, `d3-selection 3.0.0`, `d3-shape 3.2.0`, `d3-time 3.1.0`, `d3-time-format 4.1.0`, `d3-timer 3.0.1`, `d3-transition 3.0.1`, `d3-zoom 3.0.0`, `internmap 2.0.3`.

Text as shipped by `d3 7.9.0` (`LICENSE`):

```text
Copyright 2010-2023 Mike Bostock

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.
```

### 7. MIT

Applies to: `lodash-es 4.18.1`.

Text as shipped by `lodash-es 4.18.1` (`LICENSE`):

```text
Copyright OpenJS Foundation and other contributors <https://openjsf.org/>

Based on Underscore.js, copyright Jeremy Ashkenas,
DocumentCloud and Investigative Reporters & Editors <http://underscorejs.org/>

This software consists of voluntary contributions made by many
individuals. For exact contribution history, see the revision history
available at https://github.com/lodash/lodash

The following license applies to all parts of this software except as
documented below:

====

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

====

Copyright and related rights for sample code are waived via CC0. Sample
code is defined as all source code displayed within the prose of the
documentation.

CC0: http://creativecommons.org/publicdomain/zero/1.0/

====

Files located in the node_modules and vendor directories are externally
maintained libraries used by this software which have their own
licenses; we recommend you read them, as their terms may differ from the
terms above.
```

### 8. MIT

Applies to: `@mermaid-js/parser 2.0.1`, `katex 0.18.11`, `mermaid 12.2.0`.

Text as shipped by `@mermaid-js/parser 2.0.1` (`LICENSE`):

```text
The MIT License (MIT)

Copyright (c) 2023 Yokozuna59

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
```

### 9. MIT

Applies to: `chevrotain-allstar 0.5.0`, `langium 4.4.0`.

Text as shipped by `chevrotain-allstar 0.5.0` (`LICENSE`):

```text
Copyright 2022 TypeFox GmbH

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 10. MIT

Applies to: `khroma 2.1.0`.

Text as shipped by `khroma 2.1.0` (`license`):

```text
The MIT License (MIT)

Copyright (c) 2019-present Fabio Spampinato, Andrew Maney

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

### 11. MIT

Applies to: `fastdom 1.0.12`.

Text as shipped by `fastdom 1.0.12` (`README.md (licence section)`):

```text
(The MIT License)

Copyright (c) 2016 Wilson Page <wilsonpage@me.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the 'Software'), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 12. MIT

Applies to: `marked 16.3.0`.

Text as shipped by `marked 16.3.0` (`LICENSE.md`):

```text
# License information

## Contribution License Agreement

If you contribute code to this project, you are implicitly allowing your code
to be distributed under the MIT license. You are also implicitly verifying that
all code is your original work. `</legalese>`

## Marked

Copyright (c) 2018+, MarkedJS (https://github.com/markedjs/)
Copyright (c) 2011-2018, Christopher Jeffrey (https://github.com/chjj/)

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

## Markdown

Copyright © 2004, John Gruber
http://daringfireball.net/
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
* Neither the name “Markdown” nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

This software is provided by the copyright holders and contributors “as is” and any express or implied warranties, including, but not limited to, the implied warranties of merchantability and fitness for a particular purpose are disclaimed. In no event shall the copyright owner or contributors be liable for any direct, indirect, incidental, special, exemplary, or consequential damages (including, but not limited to, procurement of substitute goods or services; loss of use, data, or profits; or business interruption) however caused and on any theory of liability, whether in contract, strict liability, or tort (including negligence or otherwise) arising in any way out of the use of this software, even if advised of the possibility of such damage.
```

### 13. MIT

Applies to: `vscode-jsonrpc 9.0.3`, `vscode-languageserver 10.1.1`, `vscode-languageserver-protocol 3.18.4`, `vscode-languageserver-textdocument 1.0.15`, `vscode-languageserver-types 3.18.4`.

Text as shipped by `vscode-jsonrpc 9.0.3` (`License.txt`):

```text
Copyright (c) Microsoft Corporation

All rights reserved.

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 14. MIT

Applies to: `dagre-d3-es 7.0.14`.

Text as shipped by `dagre-d3-es 7.0.14` (`LICENSE.md`):

```text
Original dagre-d3 copyright: Copyright (c) 2013 Chris Pettitt
Original dagre copyright: Copyright (c) 2012-2014 Chris Pettitt
Original graphlib copyright: Copyright (c) 2012-2014 Chris Pettitt

Copyright (c) 2022-2024 Thibaut Lassalle, David Newell, Alois Klink, Sidharth Vinod and dagre-es contributors

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
```

### 15. MIT

Applies to: `cytoscape 3.34.0`, `cytoscape-cose-bilkent 4.1.0`, `cytoscape-fcose 2.2.0`.

Text as shipped by `cytoscape 3.34.0` (`LICENSE`):

```text
Copyright (c) 2016-2026, The Cytoscape Consortium.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### 16. MIT

Applies to: `uuid 14.0.0`, `vscode-uri 3.1.0`.

Text as shipped by `uuid 14.0.0` (`LICENSE.md`):

```text
The MIT License (MIT)

Copyright (c) 2010-2020 Robert Kieffer and other contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 17. MIT

Applies to: `es-toolkit 1.45.1`.

Text as shipped by `es-toolkit 1.45.1` (`LICENSE`):

```text
MIT License

Copyright (c) 2024 Viva Republica, Inc

Copyright OpenJS Foundation and other contributors

Parts of the test suite and compatibility layer in `es-toolkit/compat` are derived from Lodash (https://github.com/lodash/lodash) by the OpenJS Foundation (https://openjsf.org/) and Underscore.js by Jeremy Ashkenas, DocumentCloud and Investigative Reporters & Editors (http://underscorejs.org/)

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
```

### 18. MIT

Applies to: `js-yaml 4.3.0`.

Text as shipped by `js-yaml 4.3.0` (`LICENSE`):

```text
(The MIT License)

Copyright (C) 2011-2015 by Vitaly Puzrin

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
```

### 19. MIT

Applies to: `@braintree/sanitize-url 7.1.2`, `@iconify/utils 3.0.2`, `@upsetjs/venn.js 2.0.0`, `cose-base 1.0.3`, `cose-base 2.2.0`, `dayjs 1.11.21`, `layout-base 1.0.2`, `layout-base 2.0.1`, `roughjs 4.6.6`, `stylis 4.3.6`, `ts-dedent 2.2.0`.

Text as shipped by `@braintree/sanitize-url 7.1.2` (`LICENSE`):

```text
MIT License

Copyright (c) 2017 Braintree

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
```
