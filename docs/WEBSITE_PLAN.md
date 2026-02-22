<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Website & Marketing Plan

**Purpose:** Launch website and marketing campaign for Janus v0.2.6
**Timeline:** 2-4 weeks
**Goal:** Establish Janus as the first AI-native programming language

---

## 🎯 Core Message

**Primary Tagline:**
> "Janus: The First AI-Native Programming Language"

**Secondary Tagline:**
> "Where Humans Write Intent, AI Verifies Correctness, and Code Just Works"

**Value Propositions:**
1. **For Humans:** Python-simple syntax, Rust-level performance
2. **For AI:** Queryable semantics, verifiable correctness
3. **For Teams:** Faster development, safer refactoring, better collaboration

---

## 🌐 Website Structure

### Homepage

**Hero Section:**
```
┌─────────────────────────────────────────────────────┐
│                                                     │
│         JANUS                                       │
│  The First AI-Native Programming Language          │
│                                                     │
│  [Try Online]  [Download]  [Documentation]         │
│                                                     │
│  v0.2.6 • Production Ready • 99.7% Test Coverage   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Code Example (Side-by-side):**
```
┌──────────────────────┬──────────────────────┐
│  Human Writes:       │  AI Understands:     │
├──────────────────────┼──────────────────────┤
│ func fibonacci(n) do │ • Pure function      │
│   if n <= 1 do       │ • No allocations     │
│     return n         │ • Error handling via │
│   end                │   result type        │
│   return fib(n-1) +  │ • Recursive (tail    │
│          fib(n-2)    │   call optimizable)  │
│ end                  │                      │
└──────────────────────┴──────────────────────┘
```

**Key Features (Cards):**
```
┌──────────────┬──────────────┬──────────────┐
│ 🤖 AI-Native │ 🚀 Fast      │ 📚 Simple    │
├──────────────┼──────────────┼──────────────┤
│ Queryable    │ Native code  │ Python-like  │
│ semantics    │ generation   │ syntax       │
│              │              │              │
│ Stable IDs   │ Zero         │ Progressive  │
│              │ overhead     │ disclosure   │
└──────────────┴──────────────┴──────────────┘
```

**Stats Banner:**
```
642 Tests Passing  •  100% Core Features  •  Native Performance
```

### Why Janus?

**Content:** Adapted from `docs/WHY_JANUS.md`

**Sections:**
1. The Breakthrough (dual interface)
2. Why AI Agents Love Janus
3. Why Humans Love Janus
4. What This Enables
5. Comparison Table

**Visual:** Interactive comparison table with filters

### Getting Started

**Quick Start:**
```bash
# Install Janus
curl -sSf https://janus-lang.org/install.sh | sh

# Create your first program
echo 'func main() do print("Hello, Janus!") end' > hello.jan

# Run it
janus run hello.jan
```

**Tutorial Path:**
1. Hello World
2. Variables & Types
3. Functions & Control Flow
4. Error Handling
5. Zig Integration
6. Building Real Projects

### Documentation

**Structure:**
```
Documentation
├── Language Guide
│   ├── Basics
│   ├── :core Profile
│   ├── :service Profile (coming)
│   └── Advanced Topics
├── API Reference
│   ├── Standard Library
│   ├── Core Types
│   └── Zig Integration
├── Tutorials
│   ├── Building a CLI Tool
│   ├── File Processing
│   └── Web Service (coming)
└── Specifications
    ├── SPEC-018: :core Profile
    └── SPEC-002: Profiles System
```

### Playground

**Features:**
- Online code editor (Monaco/CodeMirror)
- Instant compilation (WASM-based compiler)
- LLVM IR viewer
- AST visualizer
- Example programs gallery

**Examples:**
- Hello World
- Fibonacci
- Quicksort
- File I/O
- JSON parsing
- Error handling showcase

### Community

**Sections:**
1. **Discord** - Real-time chat, support
2. **Forum** - Long-form discussions
3. **GitHub** - Issues, PRs, contributions
4. **Twitter/Mastodon** - Updates, announcements
5. **Blog** - Technical deep-dives

**Contribution Guide:**
- Code of conduct
- How to contribute
- Good first issues
- Development setup

### Blog

**Launch Posts:**
1. "Introducing Janus: The First AI-Native Language"
2. "How Janus Enables AI-Human Collaboration"
3. "From Idea to Working Language in 6 Months"
4. "The ASTDB: Code as a Database"
5. "Zero-Cost Zig Integration: The Best of Both Worlds"

**Technical Series:**
- "Building a Compiler in 2026"
- "Profile Systems: Progressive Disclosure Done Right"
- "The Atom: Stable Identity in a Mutable World"
- "QTJIR: Our SSA Intermediate Representation"

### Download

**Packages:**
- Linux (x64, ARM64)
- macOS (Intel, Apple Silicon)
- Windows (x64)
- Docker images
- Source tarball

**Installation Methods:**
- curl script (recommended)
- Package managers (apt, brew, chocolatey)
- From source (with build guide)

---

## 🎨 Design System

### Brand Colors

```
Primary:   #2C3E50 (Dark Blue-Grey)
Secondary: #E74C3C (Vibrant Red)
Accent:    #3498DB (Bright Blue)
Success:   #27AE60 (Green)
Warning:   #F39C12 (Orange)
```

### Typography

**Headings:** Inter or Poppins (modern, clean)
**Body:** Source Sans Pro or system-ui
**Code:** JetBrains Mono or Fira Code

### Visual Identity

**Logo:** Janus face (two directions, dual interface concept)
**Mascot:** TBD (optional - could be a two-faced owl/raven)
**Iconography:** Duotone style, consistent geometric shapes

### UI Components

**Code Blocks:**
- Syntax highlighting (custom theme)
- Copy button
- Line numbers
- Language indicator

**Interactive Elements:**
- Playground widgets
- AST visualizer
- LLVM IR viewer
- Type inspector

---

## 📱 Social Media Strategy

### Platforms

**Primary:**
- Twitter/X (@janus_lang)
- Mastodon (fosstodon.org/@janus)
- GitHub (organization + discussions)
- Reddit (r/programming, r/ProgrammingLanguages)

**Secondary:**
- LinkedIn (for enterprise/education)
- YouTube (tutorials, talks)
- Twitch (live coding sessions)

### Content Calendar

**Launch Week:**
- Day 1: Announcement post
- Day 2: "Why Janus?" explainer
- Day 3: Code examples showcase
- Day 4: AI collaboration demo
- Day 5: Performance benchmarks
- Day 6: Community spotlight
- Day 7: Roadmap reveal

**Ongoing:**
- Monday: Tutorial/Tip
- Wednesday: Technical deep-dive
- Friday: Community highlight
- Sunday: Weekly roundup

### Hashtags

**Primary:** #JanusLang #AINativeProgramming
**Secondary:** #ProgrammingLanguages #CompilerDesign #SystemsProgramming

---

## 🎤 Launch Strategy

### Phase 1: Pre-Launch (Week 1-2)

**Goals:**
- Build anticipation
- Gather early adopters
- Prepare infrastructure

**Tactics:**
- Teaser posts on social media
- Email to interested developers
- Reach out to tech influencers
- Prepare demo videos
- Set up Discord/forum

**Deliverables:**
- Website 80% complete
- Social media accounts created
- Community platforms ready
- Press kit prepared

### Phase 2: Launch (Week 3)

**Goals:**
- Maximum visibility
- Drive downloads
- Engage early users

**Tactics:**
- Publish on Hacker News
- Post on Reddit (r/programming)
- Email tech journalists
- Tweet storm with examples
- Live demo on Twitch/YouTube
- AMAs on Reddit/Discord

**Deliverables:**
- Website 100% live
- v0.2.6 release published
- Launch blog post
- Demo videos
- Press release

### Phase 3: Post-Launch (Week 4+)

**Goals:**
- Sustain momentum
- Build community
- Gather feedback

**Tactics:**
- Regular blog posts
- Tutorial series
- Office hours (Discord)
- Showcase user projects
- Conference submissions

**Deliverables:**
- Weekly blog posts
- Tutorial content
- Example projects
- Community highlights
- Roadmap updates

---

## 📊 Success Metrics

### Website
- Unique visitors: 10,000+ (month 1)
- Playground usage: 1,000+ sessions
- Documentation pageviews: 5,000+
- Download conversions: 2% of visitors

### Community
- GitHub stars: 500+ (month 1)
- Discord members: 200+
- Forum posts: 50+
- Contributors: 10+

### Media
- Hacker News front page (1 day)
- Reddit r/programming top 10
- Tech blog mentions: 5+
- Twitter impressions: 50,000+

### Technical
- Issue reports: 20+ (shows engagement)
- Pull requests: 5+
- Example projects: 10+
- Tutorial completions: 100+

---

## 🛠️ Technical Stack (Website)

### Recommended

**Static Site Generator:**
- Hugo (fast, Go-based)
- Eleventy (flexible, JS-based)
- Astro (modern, island architecture)

**Playground:**
- Monaco Editor (VS Code engine)
- WASM-compiled Janus
- CodeMirror 6 (lightweight alternative)

**Hosting:**
- Netlify (easy deploys, CDN)
- Vercel (excellent performance)
- GitHub Pages (free, simple)
- Cloudflare Pages (fast, global)

**Analytics:**
- Plausible (privacy-friendly)
- Fathom (simple, privacy-focused)
- Umami (self-hosted, open source)

**Search:**
- Algolia (instant search)
- Meilisearch (self-hosted)
- Pagefind (static, no backend)

---

## 📝 Content Priorities

### Must-Have (Launch)
- [x] Homepage with hero
- [x] Why Janus? page
- [x] Getting Started guide
- [x] :core Profile documentation
- [x] API reference (basic)
- [ ] Playground (basic)
- [ ] Download page
- [ ] 3-5 example programs

### Should-Have (Week 2)
- [ ] Full tutorial series
- [ ] Blog infrastructure
- [ ] 2-3 launch blog posts
- [ ] Community pages
- [ ] FAQ
- [ ] Roadmap page
- [ ] Press kit

### Nice-to-Have (Month 1)
- [ ] Video tutorials
- [ ] Interactive AST visualizer
- [ ] LLVM IR explorer
- [ ] Benchmark comparisons
- [ ] Case studies
- [ ] Newsletter signup
- [ ] Events calendar

---

## 🤝 Outreach Targets

### Tech Media
- **Hacker News** (Show HN post)
- **Reddit** (r/programming, r/ProgrammingLanguages)
- **Lobsters** (programming.dev)
- **The Changelog** (podcast pitch)
- **InfoQ** (article pitch)
- **DevClass** (news coverage)

### Influencers/Educators
- **ThePrimeagen** (Twitch streamer, Vim/performance)
- **TJ DeVries** (Neovim, tooling)
- **Andreas Kling** (SerenityOS, compilers)
- **Casey Muratori** (Handmade Hero, performance)
- **Tsoding** (live coding, language design)

### Academic
- **Universities** (CS departments)
- **Coding bootcamps**
- **Online learning platforms** (Coursera, Udemy)

### Corporate
- **Tech companies** (looking for systems languages)
- **DevOps teams** (automation, tooling)
- **Game studios** (future :game profile)

---

## 💰 Budget Considerations

### Free Tier (Bootstrap)
- ✅ GitHub Pages hosting
- ✅ GitHub Discussions (community)
- ✅ Discord (free tier)
- ✅ Twitter/Mastodon (organic)
- ✅ DIY videos/demos

**Cost:** $0/month

### Starter Tier (Recommended)
- 💵 Domain name (janus-lang.org): $15/year
- 💵 Netlify Pro: $19/month
- 💵 Plausible Analytics: $9/month
- 💵 Email service (Mailchimp): $13/month
- 💵 Canva Pro (graphics): $13/month

**Cost:** ~$55/month + domain

### Professional Tier (Growth)
- 💵 Everything in Starter
- 💵 Video editing (DaVinci Resolve: free)
- 💵 Sponsored posts (later)
- 💵 Conference travel (later)
- 💵 Swag (stickers, shirts)

**Cost:** $100-500/month (as needed)

---

## ✅ Action Items (Prioritized)

### Week 1: Foundation
- [ ] Register domain (janus-lang.org)
- [ ] Set up GitHub organization
- [ ] Create website skeleton (Hugo/Astro)
- [ ] Draft homepage copy
- [ ] Design logo/brand identity
- [ ] Create social media accounts

### Week 2: Content
- [ ] Migrate docs to website
- [ ] Write Getting Started guide
- [ ] Prepare 5 example programs
- [ ] Create demo videos (screen recordings)
- [ ] Write launch blog post
- [ ] Prepare press kit

### Week 3: Infrastructure
- [ ] Deploy website (staging)
- [ ] Set up playground (basic)
- [ ] Configure analytics
- [ ] Test download links
- [ ] Launch Discord server
- [ ] Finalize social media bios

### Week 4: Launch
- [ ] Go live (production)
- [ ] Post to Hacker News
- [ ] Post to Reddit
- [ ] Tweet announcement
- [ ] Email outreach (journalists, influencers)
- [ ] Monitor and engage

---

## 📚 Resource Templates

### Press Release Template

```markdown
FOR IMMEDIATE RELEASE

Janus Programming Language Launches v0.2.6
First AI-Native Language Reaches Production Readiness

[CITY, DATE] — The Self Sovereign Society Foundation today
announced the release of Janus v0.2.6, the world's first
programming language designed from the ground up for AI-human
collaboration.

Janus combines Python-like simplicity with native performance
and AI-queryable semantics, enabling developers to write code
that both humans and AI assistants can understand deeply.

Key features:
• 99.7% test coverage with 642 passing tests
• Native compilation to machine code
• Zero-cost integration with Zig standard library
• ASTDB: Code as a queryable database
• Profile system for progressive disclosure

"We built Janus for the AI age," said [NAME], lead developer.
"It's not just AI-friendly—it's AI-native, while remaining
beautifully simple for human developers."

Learn more: https://janus-lang.org
```

### Tweet Templates

**Launch:**
```
🎉 Introducing Janus v0.2.6: The first AI-native programming language

✅ Python-simple syntax
✅ Native performance
✅ AI-queryable semantics
✅ 99.7% test coverage

Try it now: https://janus-lang.org

#JanusLang #Programming
```

**Technical:**
```
What makes Janus AI-native?

🗄️ Code as a database (ASTDB)
🆔 Stable UUIDs (not text locations)
📊 Queryable semantics
✅ Verifiable correctness

AI can UNDERSTAND your code, not just parse it.

Thread 🧵👇
```

**Community:**
```
Looking for early adopters! 👋

If you're interested in:
• Systems programming
• AI-assisted development
• Language design
• Compiler internals

Join us: https://discord.gg/janus

Let's build the future together! 🚀
```

---

## 🎯 Next Steps

**Immediate (This Week):**
1. Review and approve this plan
2. Assign roles/responsibilities
3. Set up project management (Notion/Linear)
4. Begin domain registration
5. Start website development

**Short-term (Next 2 Weeks):**
1. Complete website MVP
2. Create demo content
3. Set up community platforms
4. Prepare launch materials
5. Reach out to early supporters

**Medium-term (Month 1):**
1. Execute launch
2. Monitor metrics
3. Engage community
4. Iterate based on feedback
5. Plan next features

---

*"The Monastery is complete. Now we open the gates."*

**Ready to launch? Let's build the future of programming! 🚀**
