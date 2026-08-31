# Official desktop packages differ across the Arch family

**Finding.** ChatGPT Desktop and Claude Desktop are official vendor Linux applications and fit
nixagent's `desktop` group: both drive remote frontier models, install graphical launchers, and
load no local model weights. Upstream Arch packages neither application. The AUR and CachyOS do,
but ChatGPT has a different package name on each.

| Application | Plain Arch source/name | CachyOS source/name | Command |
|---|---|---|---|
| ChatGPT Desktop | AUR `chatgpt-desktop` | `cachyos/chatgpt-desktop-bin` | `chatgpt` |
| Claude Desktop | AUR `claude-desktop` | `cachyos/claude-desktop` | `claude-desktop` |

The AUR package sources point directly at vendor Linux packages:

- ChatGPT: `persistent.oaistatic.com/codex-app-prod/linux/.../chatgpt_<version>_<arch>.deb`
- Claude: `downloads.claude.ai/claude-desktop/apt/stable/.../claude-desktop_<version>_<arch>.deb`

The CachyOS file database confirms the commands and desktop entries rather than inferring them
from package names:

| Package | Executable | Desktop entry |
|---|---|---|
| `chatgpt-desktop-bin` | `/usr/bin/chatgpt` | `/usr/share/applications/chatgpt.desktop` |
| `claude-desktop` | `/usr/bin/claude-desktop` | `/usr/share/applications/com.anthropic.Claude.desktop` |

**Decided:** both are `desktop` catalogue selections with `aur = true` as the plain-Arch floor and
`archRepoOn = [ "cachyos" ]` for the repository lift. ChatGPT additionally carries
`archPackageOn.cachyos = "chatgpt-desktop-bin"`; `arch` remains `chatgpt-desktop`, so a plain Arch
host never receives a CachyOS-only package name.

Neither vendor exposes a per-user desktop installer script. Their entries therefore carry
`upstream = null`; nixagent's home plane does not invent a `.deb` extraction mechanism.
