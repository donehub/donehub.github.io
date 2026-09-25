---
title: A Practical Guide to Specification-Driven Development
date: 2025-12-24
tags: SDD
categories: AI
lang: en
label: 061_sdd-spec-driven-development-guide
---

## Why SDD Took Off

In the second half of 2025, two hot projects appeared on GitHub almost simultaneously, both built around the same concept: SDD (Specification-Driven Development).

| Project | Stars | Creator | Created |
|---------|-------|---------|---------|
| spec-kit | 87,549 | GitHub (official) | 2025-08 |
| OpenSpec | 39,543 | Fission AI | 2025-08 |

SDD isn't new—the concept dates back to around 2010, but it never caught on. What changed in 2025 is that AI coding assistants finally became usable enough. Specifications used to be written for humans; now they're written so AI can understand requirements and generate code. That shift turned SDD from a nice-to-have methodology into a practical necessity.

<!-- more -->
---

## How Development Methodologies Evolved

The evolution of software development methodologies has followed a consistent direction: pushing quality assurance earlier in the process. Traditional development flows through requirements, coding, testing, and deployment, with problems often surfacing only at the testing or deployment stage. TDD, proposed in 2003, moved the starting point to writing tests before code, ensuring testability. BDD, introduced in 2006, pushed further to behavioral descriptions defined in natural language. SDD moves the starting point to the specification level: define exactly what to build in a structured document first, then let AI generate code against that specification.

| Methodology | Starting Point | Core Idea |
|-------------|---------------|-----------|
| Traditional | Coding | Write and debug, problems surface during testing |
| TDD | Tests | Write test cases first, ensure verifiability |
| BDD | Behavior | Describe system behavior in natural language, derive tests and code |
| SDD | Specification | Write a complete specification, let AI generate code from it |

## Why SDD Didn't Catch On Before

SDD's core premise—writing specifications before code—sounds logical. Three practical obstacles kept it from gaining adoption.

First, experienced developers write code faster than they write specs. Senior engineers have code templates ready in their heads; jumping straight into implementation beats documenting first. Second, specs drift out of sync with code. When code changes but the spec doesn't get updated, the spec becomes decoration. Third, there was no tooling support. A Markdown file can't execute, and there's no way to verify whether code matches the specification.

AI coding tools gradually solved all three problems between 2024 and 2025. AI can generate code from specifications, adjust implementations when specifications change, and verify consistency between code and specs automatically.

## Three Conditions for the SDD Explosion

| Condition | What Changed |
|-----------|-------------|
| Mature AI coding tools | Claude Code, Cursor, Copilot produce production-grade code |
| Developer role shift | From code writer to spec designer plus code reviewer |
| Complete toolchains | spec-kit and OpenSpec provide full execution frameworks for specs |

Industry forecasts project that by 2026, 80% of developers will use AI coding tools as standard practice, spending more time on specification design and architecture than on writing code itself.

## What SDD Actually Is

SDD works by first describing what to build in a structured specification, then having AI generate code against that specification, and finally verifying the code matches the spec. Its core capabilities include:

| Capability | Description |
|------------|-------------|
| Collaborative clarification | Developers often don't fully understand their own requirements. AI helps define problems and explore solutions. This is SDD's most underrated capability |
| Spec as contract | The specification is not a reference document; it's a contract between human and machine. AI must implement strictly against it |
| Iteration-friendly | Specifications can be updated at any time, and AI adjusts code accordingly. Specs don't become throwaway artifacts |
| Verification loop | Tools can verify whether code matches the spec and flag deviations automatically |
| Traceability | Every line of code traces back to a specific specification clause |

## Collaborative Clarification: The Most Underrated Capability

Many people assume the SDD workflow is: developer writes a clear specification, then AI follows it. In practice, developers often don't know exactly what they want. The traditional model assumes developers think everything through, write the spec, then hand it to AI for implementation. SDD's clarification mode fits reality better: a developer has a vague idea, AI asks questions to sharpen it, both sides collaboratively define the problem and explore solutions, and the result becomes a specification for AI to implement.

Think of it this way. The traditional mode is like handing a restaurant chef a complete menu and asking them to cook it exactly. The clarification mode is like saying you want something light, then discussing with the chef whether soup or steamed dishes work, what you're allergic to, and arriving at a menu together. Commands like `/speckit.clarify` and `/opsx:explore` exist for this reason: AI becomes an active requirements clarification partner, not a passive executor.

The clarification process itself is defining the problem. A surprising number of bugs trace back not to incorrect code, but to requirements that were never properly thought through.

## Specification File Structure

A complete SDD specification typically has four parts. Using OpenSpec as an example, a change lives in a directory like this:

```
openspec/changes/add-dark-mode/
├── proposal.md          # Why this change, what's the impact
├── specs/
│   ├── requirements.md  # Functional requirements detail
│   └── scenarios.md     # Usage scenarios
├── design.md            # Technical approach: how to implement
└── tasks.md             # Task list: broken into steps
```

The proposal answers why and what impact. The specs answer what features and what scenarios. The design answers the technical implementation approach. Tasks break execution into traceable steps.

## How SDD Relates to TDD and BDD

SDD doesn't replace TDD and BDD; it adds a specification layer on top. SDD defines what to build at the top level, BDD defines what behaviors the system should exhibit at the middle level, TDD defines how to verify correctness at the bottom level, and the final code implementation is constrained by all three layers. AI doesn't generate code freely; it operates within the triple constraint of specification, behavior, and tests.

| Layer | Focus | Question Answered |
|-------|-------|-------------------|
| SDD | Specification | What to build |
| BDD | Behavior | What behaviors the system should have |
| TDD | Tests | How to verify correctness |
| Implementation | Code | AI generates under the above three constraints |

## Workflow With and Without SDD

Without SDD, requirements and AI get refined through back-and-forth conversation, with constant revisions and low efficiency.

```
You: Add dark mode
AI: Sure, creating ThemeContext...
You: Wait, I want localStorage persistence
AI: Let me change that...
You: Also support auto-switching to system theme
AI: Updating...
You: Toggle button goes on the right side of the navbar
AI: ...
```

With SDD, you align on what to build first, then implement in one pass, eliminating the revision overhead.

```
You: /opsx:propose "Add dark mode"
AI: Generates full spec → proposal + specs + design + tasks
You: Reviews spec, notices localStorage persistence is missing, adds it
AI: Updates spec
You: Confirms everything looks good, executes /opsx:apply
AI: Implements everything per spec in one shot
```

## Supported Code Agents

| Code Agent | spec-kit Support | OpenSpec Support |
|------------|-----------------|-----------------|
| Claude Code | `--ai claude` | `/opsx:*` commands |
| Cursor | slash commands | slash commands |
| GitHub Copilot CLI | Native support | skills mode |
| Codex CLI | skills mode | skills mode |
| Windsurf | Supported | Supported |

## The Clarification Mode

The workflows described above assume the developer knows what to build. Real work often involves vague requirements: wanting to add a comment feature to a blog but not knowing how to design it, or users complaining that search is slow without specifics about what's slow. The clarification mode handles exactly these situations.

| Before Clarification | After Clarification |
|---------------------|---------------------|
| I want a comment feature (vague) | Comments require login, support nested replies up to 3 levels, editable and deletable, admin moderation required (clear) |
| Search is too slow (generic) | Homepage search API responds in 3s+, root cause is full-text search bypassing indexes, needs SQL optimization and caching (specific) |
| Improve user experience (abstract) | Add skeleton screens, confirmation dialogs for critical actions, real-time form validation hints (actionable) |

Rework and delays on many projects trace back to these same root causes: misunderstanding requirements leads to building the wrong thing, unclear boundaries cause scope creep, and insufficient exploration of technical options leads to wrong architectural choices. SDD's clarification mode pushes these problems upstream, solving them before any code gets written.

### spec-kit's Clarification Flow

Using the `/speckit.clarify` command, AI walks through progressive questions to nail down requirement boundaries:

```
You: /speckit.clarify "I want to add a comment feature to my blog"

AI: Let me help you clarify this requirement...
    Q1: Do comments require login to post?
    You: Yes, login required

    Q2: Can comments reply to other comments? (nested threads)
    You: Yes, up to 3 levels of nesting

    Q3: Can comments be edited or deleted after posting?
    You: Editable within 5 minutes of posting, users can delete their own

    Q4: Do comments need moderation? Or display immediately?
    You: Need moderation, admin approves before display

    AI: Good, let me compile the clarified requirements...

    [generates clarification.md]
    ✓ Problem boundaries defined
    ✓ Key decisions recorded
    ✓ Ready for specification phase

You: /speckit.spec blog-comment-system
```

### OpenSpec's Exploration Flow

Using the `/opsx:explore` command, AI helps scope the problem, diagnose causes, and explore solutions:

```
You: /opsx:explore "Users complain search is too slow, want to optimize"

AI: Let me analyze the problem first...

    1. Scope the problem:
       - Is it the homepage search? Or admin backend search?
       - All searches slow? Or specific keywords?
       - What's the threshold for "slow"? 2s? 5s?

    You: The site-wide search on the homepage, takes about 3-4 seconds

    2. Diagnose possible causes:
       - Current implementation: LIKE '%keyword%' full-text search
       - Data volume: posts table has 100k+ rows, not using indexes
       - Caching strategy: no cache, hits database every time

    3. Explore solutions:
       Option A: Add full-text index (MySQL FULLTEXT)
       Option B: Introduce Elasticsearch
       Option C: Add Redis cache for hot keywords

       Comparison:
       | Option | Cost | Effect | Maintenance |
       |--------|------|--------|-------------|
       | A | Low | Medium (still slow with large data) | Low |
       | B | High | High | High (new component) |
       | C | Low | Medium (depends on hit rate) | Low |

       Recommendation: Combine A + C, add index as baseline, cache for hot queries

    You: Let's go with A + C

    AI: Got it, generating exploration record...

    [generates openspec/explorations/search-optimization/]
    ✓ exploration.md — Problem analysis + solution comparison
    ✓ decision.md — Final choice + reasoning
    ✓ Ready for /opsx:propose phase
```

## Installation

### Installing spec-kit

```bash
# Option 1: Install stable release (v0.6.1)
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.6.1

# Option 2: Install latest
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

# Verify installation
specify check
```

Initialize a project:

```bash
# Create new project
specify init my-project --ai claude

# Or initialize in existing project
specify init . --ai claude
```

### Installing OpenSpec

```bash
# Requires Node.js 20.19.0+
npm install -g @fission-ai/openspec@latest

# Verify installation
openspec --version

# Initialize project
cd your-project
openspec init
```

## Hands-On: Adding Dark Mode to a Blog

### spec-kit Full Workflow

Step one: define project principles. Run `/speckit.constitution` in Claude Code to set code style, test coverage, and documentation requirements. AI generates `.speckit/constitution.md`.

Step two: create feature specification. Run `/speckit.spec add-dark-mode` with requirement points: support light, dark, and system-follow modes; preference stored in localStorage; toggle button on the right side of the navbar; smooth transition animation on switch. AI generates `.speckit/features/add-dark-mode/spec.md`.

Step three: generate implementation plan. Run `/speckit.plan add-dark-mode`. AI produces a plan file covering technology choices, file change list, and implementation steps.

Step four: break down tasks. Run `/speckit.tasks add-dark-mode`. AI generates a task list:

```markdown
## Tasks

### 1. Infrastructure
- [ ] 1.1 Create ThemeContext
- [ ] 1.2 Define CSS variable system
- [ ] 1.3 Create useTheme hook

### 2. UI Components
- [ ] 2.1 Create ThemeToggle component
- [ ] 2.2 Add transition animation styles
- [ ] 2.3 Integrate into navbar

### 3. Persistence
- [ ] 3.1 localStorage read/write logic
- [ ] 3.2 System theme listener

### 4. Testing
- [ ] 4.1 ThemeContext unit tests
- [ ] 4.2 ThemeToggle component tests
```

Step five: execute implementation. Run `/speckit.implement add-dark-mode`. AI implements code item by item per the task list.

Step six: verify and review. Run `/speckit.verify add-dark-mode`. AI checks each task for completion, verifies code matches the spec, and confirms tests pass.

### OpenSpec Full Workflow

Step one: generate a complete specification in one shot. Run `/opsx:propose` with a description of requirements. AI generates the full spec directory:

```
openspec/changes/add-dark-mode/
├── proposal.md          # Why, which pages are affected
├── specs/
│   ├── requirements.md  # Functional requirements detail
│   └── scenarios.md     # User scenarios
├── design.md            # Technical approach: React Context + CSS variables
└── tasks.md             # Implementation task list
```

Step two: review and adjust. Open specs/requirements.md, add a requirement: toggle button should display the current mode icon (sun, moon, computer). AI updates the spec files.

Step three: execute. Run `/opsx:apply`. AI implements tasks one by one:

```text
AI: Implementing tasks...
     ✓ 1.1 Create ThemeContext provider
     ✓ 1.2 Define CSS variable system
     ✓ 1.3 Create useTheme hook
     ✓ 2.1 Create ThemeToggle component
     ✓ 2.2 Add transition animation
     ✓ 2.3 Integrate to navbar
     ✓ 3.1 localStorage logic
     ✓ 3.2 System theme listener
     ✓ 4.1 Unit tests
     ✓ 4.2 Component tests
     All tasks complete!
```

Step four: archive. Run `/opsx:archive`. AI archives the completed change to the history directory, with spec files updated accordingly.

## Choosing Between spec-kit and OpenSpec

| Dimension | spec-kit | OpenSpec |
|-----------|----------|----------|
| Creator | GitHub (official) | Fission AI (startup) |
| Style | Engineering-focused, rigorous | Flexible, fast |
| Installation | Python + uv | Node.js + npm |
| Workflow | Step-by-step (6 commands) | One-shot generate + apply |
| Extensibility | 40+ official extensions | Configuration-based customization |
| Best For | Large projects, team collaboration | Personal projects, rapid iteration |
| Learning Curve | Steeper (more concepts) | Flatter (quick to pick up) |

My recommendation: go with spec-kit for large teams or Python projects, and OpenSpec for individual developers or TypeScript projects. If you want to quickly experience the SDD workflow, try OpenSpec first, then learn spec-kit systematically.

---

SDD's core value is moving the quality gate upstream to the specification stage. When AI can generate code from specifications, spec quality directly determines code quality. Rather than reworking repeatedly during implementation, invest time in clarifying requirements before writing any code.

## References

- [GitHub spec-kit](https://github.com/github/spec-kit) — 87k+ Stars
- [Fission-AI OpenSpec](https://github.com/Fission-AI/OpenSpec) — 39k+ Stars
- [The Rise of SDD in the AI Era](https://dev.to/the-rise-of-specification-driven-development-in-the-ai-era)
- [SDD Complete Guide](https://devops.com/specification-driven-development-a-complete-guide/)
