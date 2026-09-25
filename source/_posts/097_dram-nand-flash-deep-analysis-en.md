---
title: "The Storage Chip Duo: A Complete Analysis of DRAM and NAND Flash"
date: 2026-05-14
categories: Storage Chips
tags: [Concept Explained]
lang: en
label: 097_dram-nand-flash-deep-analysis
---

## Background

Several major events in the storage chip industry in 2026 are worth paying attention to: Samsung's market cap hit a new high, with HBM orders booked through next year; SK Hynix's stock price surged as it became NVIDIA's largest HBM supplier; Micron announced mass production of HBM3e; and CXMT (ChangXin Memory Technologies) closed a successful funding round, marking another breakthrough for China's DRAM industry. Behind these headlines — memory sticks, SSDs, HBM — all trace back to two fundamental technology families: DRAM and NAND Flash.

Understanding the difference and relationship between these two makes all of those news stories click into place.

<!-- more -->
---

## DRAM: The Compute System's Workbench

### Basic Concept

DRAM (Dynamic Random Access Memory) is the working memory of a compute system. When you open a document on your computer, the file is loaded from the drive into DRAM, and the CPU reads data from DRAM for processing. DRAM serves as the temporary workbench between the CPU and persistent storage — once power is cut, data vanishes instantly. That's why an unsaved file disappears when the power goes out: the data in DRAM is gone in a flash.

It's called "dynamic" because the data must be continuously refreshed to be retained. A DRAM storage cell consists of one capacitor and one transistor — charged capacitor represents "1," discharged represents "0." The problem is that capacitors leak charge naturally. After a few milliseconds, the charge dissipates and the data is lost. The solution is to refresh every few milliseconds, topping up the charge. That's what "dynamic" means: data isn't stored statically — it requires continuous refreshing.

By comparison, SRAM (Static Random Access Memory) uses six transistors per storage cell and doesn't need refreshing, but its structure is complex, density is low, and cost is high. DRAM offers the better price-performance ratio for high-capacity memory, while SRAM performs better but costs more, so it's relegated to small caches inside the CPU (L1/L2/L3).

| Feature | DRAM | SRAM |
|------|------|------|
| Storage cell | 1 capacitor + 1 transistor | 6 transistors |
| Refresh required | Periodic refresh mandatory | Not required |
| Density | High (simple structure) | Low (complex structure) |
| Capacity | Large (up to 16GB per chip) | Small (typically KB to MB) |
| Cost | Cheaper | More expensive |
| Applications | Memory sticks, phone RAM | CPU cache (L1/L2/L3) |

### Product Family

The DRAM family has multiple branches, each optimized for different scenarios:

| Product | Characteristics | Use Case | Bandwidth | Key Manufacturers |
|------|------|------|------|----------|
| DDR4/DDR5 | Standard memory modules | PC, servers | ~25GB/s | Samsung/SK Hynix/Micron/CXMT |
| LPDDR4/LPDDR5 | Low-power variant | Phones, tablets | ~60GB/s | Samsung/SK Hynix/Micron/CXMT |
| HBM/HBM3e | Stacked, high bandwidth | AI training GPUs | ~1TB/s+ | Samsung/SK Hynix/Micron |
| GDDR6/GDDR7 | Graphics memory | Gaming GPUs | ~160GB/s | Samsung/SK Hynix/Micron |
| Server DRAM | Server-grade | Data centers | ~50GB/s | Samsung/SK Hynix/Micron/CXMT |
| Mobile DRAM | Mobile-optimized | Smartwatches, IoT | ~10GB/s | All major vendors |

### HBM and Its Relationship with AI

HBM became critical to AI because of the bandwidth bottleneck. A standard DDR5 memory module delivers about 25GB/s per channel, but AI training requires hundreds of GB/s or even TB/s-level bandwidth. GPUs like NVIDIA's H100 have enormous compute power, but they can't be fed data fast enough — traditional memory becomes the bottleneck.

HBM's solution is vertical stacking. Traditional memory modules have chips laid flat on a PCB with long signal paths. HBM stacks 8–12 layers of DRAM chips vertically, connected through TSVs (Through-Silicon Vias), creating extremely short paths at extremely high speeds. Then CoWoS packaging places the HBM and GPU on the same silicon interposer, enabling adjacent communication.

```
Traditional memory module:
┌───┐
│Chip│ ← Laid flat on PCB, signals travel far
└───┘

HBM:
┌─────┐
│Chip 8│ ↑
├─────┤ │ 8-12 layers stacked vertically
│Chip 7│ │ Connected via TSV (Through-Silicon Vias)
│ ... │ │ Extremely short paths, extremely fast
└──┬──┘ ↓
   └── GPU die (adjacent packaging)
```

| Technology | Role |
|------|------|
| TSV (Through-Silicon Via) | Drill micro-holes in chips for vertical conduction |
| 3D Stacking | 8 or 12 layers of DRAM chips stacked together |
| CoWoS Packaging | HBM and GPU packaged on the same silicon interposer |

The bandwidth comparison is striking: DDR5 modules deliver about 25GB/s, HBM3 reaches about 1TB/s, and HBM3e pushes past 1.5TB/s. HBM provides 40–60x the bandwidth of standard memory. This is also a major reason why NVIDIA H100s start at $30,000 — HBM costs account for a significant portion. In AI training scenarios, GPU compute is no longer the bottleneck; memory bandwidth is. Whoever secures more HBM can train larger models.

### Competitive Landscape

The global DRAM market is highly concentrated — the big three control over 93% of the market:

| Rank | Manufacturer | Country | Market Share | Trend | Technology Level |
|:----:|------|------|:----:|:----:|----------|
| 1 | Samsung Electronics | South Korea | ~40-41% | Slightly declining | Most advanced |
| 2 | SK Hynix | South Korea | ~28-29% | Rising | HBM leader |
| 3 | Micron Technology | USA | ~23-24% | Stable | Top-tier |
| 4 | CXMT | China | ~5-6% | Rising | Catching up |
| 5 | Nanya Technology | Taiwan | ~2% | Stable | Mid-tier |
| 6 | Winbond | Taiwan | ~1% | Stable | Mid-to-low tier |
| 7 | PSMC | Taiwan | <1% | Stable | Foundry |

A few notable shifts in 2025. SK Hynix's share rose, driven primarily by HBM business — it has become NVIDIA's largest HBM supplier. CXMT grew from 3–5% to 5–6%, with domestic substitution accelerating. Samsung's share dipped slightly, a strategic choice to shift toward higher-margin HBM and reduce low-end capacity.

| Manufacturer | DDR5 | LPDDR5X | HBM3e | GDDR7 | Process Node |
|------|:----:|:-------:|:-----:|:-----:|:----:|
| Samsung | ✅ | ✅ | ✅ | ✅ | 12nm |
| SK Hynix | ✅ | ✅ | ✅ Leader | ✅ | 12nm |
| Micron | ✅ | ✅ | ✅ | ✅ | 12nm |
| CXMT | ✅ | ✅ | ❌ | ❌ | 17nm |
| Nanya | ✅ | ❌ | ❌ | ❌ | 20nm |
| Winbond | ❌ | ❌ | ❌ | ❌ | 25nm |

The technology capability matrix shows the big three covering DDR5, LPDDR5X, HBM3e, and GDDR7 across the board, with process nodes at 12nm. CXMT can produce DDR5 and LPDDR5X, but HBM and GDDR7 remain gaps, and its process node at 17nm is roughly two generations behind. That said, 5–6% market share for a company founded in 2016 represents a respectable pace of progress.

Mainland China has only one DRAM manufacturer — CXMT — currently focused on DDR4/DDR5 and LPDDR4/LPDDR5, with HBM still in R&D. In Japan, former DRAM giant Elpida went bankrupt in 2012 and was acquired by SK Hynix, effectively ending Japan's DRAM industry.

---

## NAND Flash: The Compute System's Permanent Warehouse

### Basic Concept

NAND Flash is a type of non-volatile memory — data persists after power is cut. The 128GB of storage in your phone and the 512GB SSD in your laptop are both NAND Flash. If DRAM is the temporary workbench, NAND Flash is the permanent warehouse where all files, apps, and system data live, surviving even when the machine is off.

The name "NAND" comes from the logic gate (Not AND) — this transistor array structure stores data. "Flash" refers to erase speed: traditional EEPROM takes seconds to erase, while NAND Flash takes only milliseconds — fast as a flash, hence the name Flash Memory.

### How It Works

NAND's storage cell is the floating-gate transistor. Electrons injected into the floating gate stay trapped even without power — that's the root of non-volatility. Writing involves using high voltage to inject electrons into the floating gate; erasing uses even higher voltage to pull them out; reading detects whether electrons are present in the floating gate.

```
NAND storage cell = floating-gate transistor

┌─────────────────┐
│ Floating gate   │ ← Electrons are trapped here
│  Electrons = "0"│    They won't escape
│  No electrons = "1"│
└─────────────────┘

Write: inject electrons into floating gate (high voltage)
Erase: pull electrons out of floating gate (even higher voltage)
Read: detect whether floating gate has electrons
```

This mechanism introduces a side effect: limited write/erase endurance. Each storage cell can only be written and erased a finite number of times (thousands to tens of thousands), and excessive cycling degrades the floating gate oxide layer, reducing data retention. Modern SSDs use wear leveling algorithms to distribute writes evenly, so in practice, endurance is rarely a concern.

### Classification by Bits per Cell

NAND is classified into four types based on how many bits each storage cell holds:

| Type | Bits per Cell | Characteristics | Endurance | Applications |
|------|:----------:|------|------|------|
| SLC | 1 bit | Fastest, most durable, most expensive | 100K cycles | Enterprise/military |
| MLC | 2 bit | Balanced performance and cost | 1K–10K cycles | High-end consumer |
| TLC | 3 bit | Mainstream choice, best value | 500–3K cycles | Consumer SSDs |
| QLC | 4 bit | Cheap but slow | 100–1K cycles | High-capacity storage |

More bits per cell means higher space utilization and lower cost, but speed and endurance both decline. Consumer SSDs today are predominantly TLC, with QLC gradually gaining ground in high-capacity storage scenarios. SLC, due to its high cost, is essentially confined to enterprise and military use.

### 3D NAND and the Layer Count Race

Traditional NAND is planar, which limits capacity. Modern technology stacks storage cells vertically, multiplying capacity within the same footprint. Leading manufacturers now exceed 230 layers:

| Manufacturer | Max Layer Count |
|------|:--------:|
| Samsung | 236 |
| SK Hynix | 238 |
| Micron | 232 |
| YMTC | 232 (Xtacking technology) |

```
Traditional 2D NAND:
┌──┐ ┌──┐ ┌──┐ ┌──┐ ← Single layer, planar

3D NAND:
┌──┐
│232│ ↑ Vertical stacking
├──┤ │ Same footprint, double the capacity
│...│ │
└──┘ ↓
```

The marginal returns of the layer count race are diminishing. Going from 128 to 232 layers nearly doubles capacity, but pushing from 232 to 300+ layers brings sharply increasing process difficulty and declining yields. Future capacity growth will likely require new materials (like CTF replacing floating gates) and architectural innovations.

### YMTC's Xtacking Architecture

Traditional 3D NAND manufactures storage cells and peripheral circuits on the same wafer, then stacks them together. As layer counts increase, the storage cells and peripheral circuits interfere with each other. YMTC's Xtacking architecture makes a critical change: storage cells and peripheral circuits are manufactured on separate wafers, then bonded together.

```
Traditional 3D NAND:
┌─────────────────┐
│ Storage cells +  │ ← Manufactured on the same wafer
│ peripheral       │    More layers = more interference
│ circuits stacked │
└─────────────────┘

Xtacking architecture:
┌──────────┐   ┌──────────┐
│ Storage    │ ←→│ Peripheral│ ← Manufactured on separate wafers,
│ cells      │   │ circuits  │   then bonded together
│ (vertical  │   │ (high-speed│
│  stacking) │   │  logic)   │
└──────────┘   └──────────┘
```

This architecture delivers three benefits: higher storage density (peripheral circuits don't consume storage cell area), faster I/O speeds (peripheral circuits use a more advanced logic process), and better manufacturing efficiency (two wafers can be independently optimized for yield). Xtacking enabled YMTC to reach parity with Samsung and SK Hynix at the 232-layer node — a rare architecture-level innovation in China's domestic storage chip industry.

### NAND Flash Product Family

| Product | Characteristics | Use Case | Speed |
|------|------|------|------|
| SSD | High-capacity, high-speed storage | Computer drives | 3-7GB/s |
| UFS | High-speed embedded storage | Mid-to-high-end phones | ~4GB/s |
| eMMC | Integrated controller, low cost | Low-end phones/IoT | ~400MB/s |
| SD/TF cards | Removable, portable | Cameras/drones | ~100MB/s |
| USB flash drives | Portable, universal | Data transfer | ~100MB/s |

### Competitive Landscape

The NAND Flash market is somewhat more distributed than DRAM but remains highly concentrated:

| Rank | Manufacturer | Country | Market Share | Trend | Technology Level |
|:----:|------|------|:----:|:----:|----------|
| 1 | Samsung Electronics | South Korea | ~35-38% | Stable | Most advanced |
| 2 | Kioxia | Japan | ~15-18% | Stable | Top-tier (IPO in 2024) |
| 3 | Western Digital | USA | ~12-15% | Stable | Top-tier (JV with Kioxia) |
| 4 | SK Hynix | South Korea | ~12-15% | Rising | Top-tier (incl. Solidigm) |
| 5 | Micron Technology | USA | ~10-12% | Stable | Top-tier |
| 6 | YMTC | China | ~5-8% | Constrained | Near top-tier |

Key changes in 2025. Kioxia completed its IPO in late 2024, securing capital for capacity expansion. Western Digital plans to spin off its SanDisk business. YMTC's global share growth has been hindered by U.S. sanctions, but its domestic market position continues to develop steadily.

YMTC is China's largest NAND Flash manufacturer, and its 232-layer Xtacking technology is close to the first tier. Compared to CXMT in DRAM, YMTC is in a considerably stronger competitive position internationally.

---

## DRAM vs NAND Flash

| Dimension | DRAM | NAND Flash |
|------|------|------------|
| After power loss | Data lost | Data retained |
| Refresh required | Periodic refresh mandatory | Not required |
| Speed | Very fast (tens of GB/s) | Slower (a few GB/s) |
| Capacity | Smaller (8-16GB/chip) | Larger (256GB-4TB/chip) |
| Write/erase endurance | Unlimited (theoretically) | Limited (thousands to tens of thousands) |
| Cost/GB | More expensive | Cheaper |
| Typical products | Memory sticks, HBM | SSDs, phone storage |

The two play distinct roles in a compute system. When launching a large game, the game files live on the SSD (NAND); at startup they're loaded into the memory stick (DRAM); the GPU reads rendering data from HBM. NAND handles persistent storage, DRAM handles runtime data staging, and HBM feeds the GPU with high-bandwidth data. All three are indispensable, each doing its job.

---

## China's Storage Industry

China's mainland storage chip industry is carried by two companies on two separate tracks — CXMT and YMTC. Their international gaps differ significantly:

| Company | Technology Domain | Positioning | International Gap |
|------|----------|------|----------|
| CXMT | DRAM | China's only memory manufacturer | Significant gap (~2 generations behind) |
| YMTC | NAND Flash | China's largest flash memory manufacturer | Small gap (close to first tier) |

The reason for the different gaps is worth analyzing. In DRAM, Samsung, SK Hynix, and Micron have 40 years of accumulated expertise, extraordinarily complex processes, and high patent barriers. Equipment constraints (lithography, etching machines) from export controls make catching up even harder. In NAND, the technology path is more flexible. YMTC achieved a leapfrog move with Xtacking architecture — layer stacking relies more on process innovation than pure lithography shrink, giving latecomers more room to compete.

CXMT's challenge is that DRAM process shrinkage has reached 12nm, and every step forward requires parallel advances in EUV lithography and other leading-edge processes — precisely the core chokepoint of sanctions. YMTC is in a somewhat better position; 232 layers is already near first-tier, and sanctions affect it more in equipment access and overseas market expansion than in the technology itself.

---

## Assessment and Outlook

The storage chip industry's landscape won't shift fundamentally in the near term. Samsung, SK Hynix, and Micron's dominance in DRAM is solid, and while NAND faces challenges from YMTC and Kioxia, that structure is equally stable.

Two variables are worth watching closely. The first is HBM supply and demand. AI training demand for HBM continues to grow rapidly, while HBM capacity expansion is constrained by TSV and CoWoS packaging yields — the supply shortage won't ease in the near term. This is good news for SK Hynix but adds cost pressure for AI chip companies that need HBM.

The second is the pace of breakthrough in China's storage industry. CXMT's catch-up in DRAM takes time — the jump from 17nm to 12nm isn't just process improvement, it also involves equipment restrictions. YMTC is better positioned in NAND; 232-layer Xtacking has already demonstrated architecture innovation capability, and whether it can maintain a stable equipment supply chain under sanctions is the key variable.

From an investment and technology tracking perspective, several signals in the storage chip industry merit ongoing attention: HBM capacity expansion progress, YMTC's next-generation layer count breakthrough, CXMT's HBM R&D developments, and the three majors' process shrinkage competition dynamics.
