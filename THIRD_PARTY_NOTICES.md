# Third-party notices

## iSH ARM64

OmniBot embeds source from [`XuYouo/ish-arm64`](https://github.com/XuYouo/ish-arm64)
at commit `303811a09958409ac4713cde3aee2bc7995a42f0` as its local Linux runtime.
iSH is distributed under GPLv3, with qualifying later contributions also
licensed under GPLv2. The upstream Apple-distribution covenant does not remove
the GPL source and notice obligations.

The complete corresponding source used by this project is pinned in
`Vendor/ish-arm64`. The application resources under `Resources/Legal` include
the upstream notice, the GNU GPL version 2 and version 3 license texts, this
notice, and the Apple-distribution covenant.

## Alpine Linux root filesystem

The bundled Alpine 3.21.0 AArch64 minirootfs contains packages under multiple
licenses. The exact artifact and SHA-256 are documented in
`OmniBot/Resources/Alpine/README.md`; the exact installed package versions and
declared licenses are listed in
`OmniBot/Resources/Legal/Alpine-3.21.0-Packages.md`. Before public binary
distribution, publish corresponding source or a valid source offer for the
exact rootfs and any packages added to the release image.

## Chromium hterm

The interactive iOS terminal uses the hterm JavaScript terminal emulator from
the ChromiumOS `libapps` project, as pinned by the vendored iSH source tree.
hterm is distributed under the BSD 3-Clause License. The complete license is
bundled at `OmniBot/Resources/Legal/hterm-BSD-License.txt`.

## Lobe Icons

The provider and model logo assets include SVGs derived from
[`lobehub/lobe-icons`](https://github.com/lobehub/lobe-icons), distributed under
the MIT License. The complete upstream license is bundled at
`OmniBot/Resources/Legal/Lobe-Icons-License.md`. Provider names and logos may
also be trademarks of their respective owners; their inclusion does not imply
affiliation or endorsement.

## Lucide Icons

The chat composer includes SVG paths from the
[`lucide-icons/lucide`](https://github.com/lucide-icons/lucide) project. Lucide
is distributed under the ISC License, with specified icons derived from Feather
and distributed under the MIT License. The complete upstream license notice is
bundled at `OmniBot/Resources/Legal/Lucide-License.md`.

## UI/UX Pro Max repository tooling

The repository-local Codex skill under `.codex/skills/ui-ux-pro-max` is derived
from [`nextlevelbuilder/ui-ux-pro-max-skill`](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)
and is distributed under the MIT License. Its complete license is retained at
`.codex/skills/ui-ux-pro-max/LICENSE`.

## Distribution note

Static in-process iSH integration can make the combined application subject to
GPL distribution requirements. OmniBot is distributed under `GPL-3.0-only` to
align the project license with those obligations. Binary distributors remain
responsible for providing exact corresponding source and required notices.
App Store review of an Agent that downloads and executes packages is separate
from the absence of JIT.
