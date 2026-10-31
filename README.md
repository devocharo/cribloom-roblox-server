# 🌸 Critbloom — Multiplayer Arena

> **A fast-paced, bloom-themed multiplayer combat arena where critical hits blossom into devastating chain reactions.**

## 🎮 Game Concept

**Critbloom** is a 4v4 arena brawler where every critical hit triggers a "Bloom" — a cascading visual and mechanical effect that spreads to nearby enemies. Master the timing of your attacks, position for maximum Bloom chains, and dominate the arena.

### Core Mechanics

| Mechanic | Description |
|----------|-------------|
| **Critical Bloom** | Crits spawn a Bloom zone (3s) — enemies inside take 25% more damage |
| **Chain Reaction** | Blooms overlap → **Super Bloom** (50% dmg, slows, visual spectacle) |
| **Petal Dash** | Double-tap movement → invulnerable dash through Blooms, refreshes cooldowns |
| **Essence System** | Deal/heal in Blooms → gain Essence → ultimate ability at 100% |

### Game Modes
- **Bloom Ball** — Capture the neutral Bloom core, hold it in your zone
- **Petal Hunt** — Collect essence petals spawned by Super Blooms
- **Last Bloom Standing** — Elimination, final circle shrinks with Bloom zones

## 📁 Project Structure

```
critbloomrobloxserver/
├── ServerScriptService/          # Server-authoritative logic
│   ├── GameManager.server.lua    # Match lifecycle, mode management
│   ├── PlayerData.server.lua     # DataStore persistence, stats
│   ├── CombatSystem.server.lua   # Damage, crits, Bloom logic
│   ├── Matchmaking.server.lua    # Queue, team balancing
│   └── EssenceSystem.server.lua  # Ultimate charging, abilities
├── ReplicatedStorage/
│   ├── Modules/
│   │   ├── BloomMath.lua         # Shared bloom calculations
│   │   ├── GameConstants.lua     # Tunables, config
│   │   ├── Network.lua           # RemoteEvent/Function wrappers
│   │   └── Utility.lua           # Helpers
│   ├── Remotes/                  # Client↔Server communication
│   └── Assets/                   # Shared asset IDs
├── StarterPlayer/
│   ├── StarterCharacterScripts/  # Character-level client logic
│   │   ├── Movement.client.lua   # Petal Dash, bloom interaction
│   │   └── Combat.client.lua     # Input, visual feedback
│   └── StarterPlayerScripts/     # Player-level client logic
│       ├── UIController.client.lua
│       └── Camera.client.lua
├── StarterGui/
│   ├── HUD.gui.lua               # Health, essence, bloom indicators
│   ├── MatchUI.gui.lua           # Score, timer, minimap
│   └── MenuUI.gui.lua            # Main menu, queue, settings
├── Workspace/
│   ├── Maps/                     # Arena map models
│   ├── Spawns/                   # Team spawn points
│   └── BloomZones/               # Visual bloom zone parts
└── Assets/
    ├── Animations/               # Animation IDs
    ├── Sounds/                   # Sound IDs
    └── Particles/                # ParticleEmitter configs
```

## 🚀 Quick Start

1. **Open in Roblox Studio** → `File > Open from File` → select this folder
2. **Enable API Services** → Game Settings > Security > Enable Studio Access to API Services
3. **Configure DataStores** → Run `SetupDataStores` once in command bar
4. **Playtest** → Press Play (F5) → Two players minimum for matchmaking

## ⚙️ Configuration

Edit `ReplicatedStorage/Modules/GameConstants.lua` to tune:
- Crit chance / Bloom radius / duration
- Essence gain rates
- Match timers, team sizes
- Map rotation

## 📊 Data Persistence

Uses **OrderedDataStore** for leaderboards + **DataStore2** pattern for player profiles:
- Wins / Losses / Elo
- Total Blooms triggered / Super Blooms
- Favorite character / cosmetic unlocks

## 🎨 Visual Style

- **Palette**: Deep violet → magenta → gold gradients
- **Bloom Effect**: Custom particle system + PostProcessing Bloom
- **UI**: Rounded, petal-shaped elements with subtle animation

## 📜 License

MIT — Build something beautiful with it.

---

*Made with 💜 for the Roblox community*