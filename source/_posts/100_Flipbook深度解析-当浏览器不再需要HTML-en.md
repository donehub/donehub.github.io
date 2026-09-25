---
title: "Flipbook Deep Dive: When Browsers No Longer Need HTML"
date: 2026-05-23
tags: [Interesting Things]
categories: [AI]
lang: en
label: 100_Flipbook深度解析-当浏览器不再需要HTML
---

Over the past 50 years, human-computer interaction has evolved from CLI to GUI to Web. Shopify CEO Tobi Lütke recently reposted something that drew my attention to an experimental product called [flipbook.page](https://flipbook.page/). It's described as "a fully on-demand, real-time-generated infinite visual browser." The core idea: every page you see is an image generated in real time by AI — no HTML, no CSS, no JavaScript. Everything is pixels.

<!-- more -->
## What Is Flipbook

Traditional browser rendering follows a familiar chain: user clicks a link, server returns HTML, browser parses the DOM, executes CSS and JS, and displays the page. Flipbook's chain is fundamentally different: the user clicks somewhere in an image, the AI interprets the intent, and generates a new image in real time as the next page.

Here's how it works concretely. You open flipbook.page and enter a topic to explore. The AI generates a polished infographic containing text, icons, charts, and illustrations. All text is rendered as image pixels — there's no HTML text overlay. You click on an element in the image (say, a data point in a chart), and the AI interprets what you clicked, then generates a deeper, more detailed image in real time. This repeats endlessly. It feels less like browsing discrete web pages and more like exploring an infinitely unfolding knowledge map.

---

## Core Technology Architecture

### Image Generation and Video Transition Coordination

Two AI systems work in concert behind Flipbook. An image generation model draws each page in real time based on user intent. A custom video model generates smooth transition animations between pages. When the user enables video stream mode, the two systems merge into a continuous 1080p video stream — page transitions become smooth camera movements instead of hard jumps.

| System | Responsibility | Analogy |
|------|------|------|
| Image generation model | Draws each page in real time based on user intent | The painter |
| Custom video model | Generates smooth transition animations between pages | The director |

### Content Sources

Flipbook isn't a pure hallucination engine. Content comes from two channels. First, agentic web search fetches real data from the internet in real time. Second, the image model's own knowledge base — the world knowledge learned during training. The team openly acknowledges that factual accuracy is roughly on par with ChatGPT/Gemini/Claude, meaning the hallucination problem persists.

### Text Rendering

One detail worth attention: the team specifically addressed text rendering. All on-screen text is rendered as pixels by the image model — no text overlay is applied to the images. Every word, every heading, every data annotation in the image is drawn by the model itself. Occasionally, text may appear slightly unclear or mispositioned, though this should improve with model iterations.

This design choice introduces a fundamental shift: text in this system is no longer a copyable text node — it's part of the visual element. What this means for accessibility and SEO, the team hasn't answered yet.

---

## Team Background

Flipbook's founding team consists of three people. Zain Shah, a former OpenAI researcher, leads the technical core. Eddie Jiao previously worked at Humane and Slack. Drew Carr came from Apple. The latter two handle product design. Compute is sponsored by Modal, and the investor is South Park Commons (which also backed Notion and Figma).

A former OpenAI researcher plus two top-tier product designers — this combination explains why the project has both technical depth and strong interaction intuition. The team composition also hints at something: Flipbook's core challenge isn't the model itself, but how to package model capabilities into a product form users actually want to keep using.

---

## Why It Deserves Attention

### From Building Interfaces to Generating Them

For the past 30 years, we've taken a premise for granted: human-computer interfaces are built by engineers writing code. Whether early HTML pages, Flash animations, or modern React components, the pattern is the same — engineers define structure, browsers render it, users interact within that framework. Flipbook breaks this assumption: interfaces are no longer built — they're generated.

The significance of this shift is that it transfers interface production from engineers to AI. In traditional web development, interfaces are static and predefined — users can only interact within the framework engineers set up. Flipbook's interfaces are dynamic and generated on demand — every click creates an entirely new interface. It's equivalent to swapping the rendering engine from GPU to large model.

### Expanding the Dimensions of Information Expression

The team puts it directly: a picture is worth a thousand words, yet our screens mostly show text and colored rectangles. On the traditional web, the options for explaining a complex concept are limited: write text and let readers figure it out, put up an image a designer pre-made, or create an animation or video — but those are expensive and inflexible.

Flipbook's approach is to let AI automatically choose the most appropriate form of information expression for the current context. If the most effective expression is a single word, you see a word. If it's an illustration, you see an illustration. If it's a data visualization, you see a data visualization. This isn't just displaying information — it's selecting the optimal way to convey it. For knowledge-intensive content consumption scenarios, this adaptive expression capability has real value.

### HyperCard's Return

Flipbook has been described as a full AI implementation of HyperCard. HyperCard was software Apple launched in 1987 that let users organize knowledge and navigate in a card-based format. Its core philosophy was that knowledge should be explored spatially, not searched linearly. That idea was too ahead of its time and was ultimately supplanted by the World Wide Web. Thirty-seven years later, AI has made spatial knowledge exploration viable again — and this time users don't need to manually create the cards.

HyperCard's failure, though, wasn't purely about technology immaturity — it was more about ecosystem and business model not catching up. Whether Flipbook can avoid the same fate depends on whether it can build a sustainable content ecosystem.

---

## Evolution Directions and Feasibility Analysis

Flipbook is currently an experiment, but its planned evolution directions are worth analyzing one by one.

### Transaction Loop

The team's example: today you use Flipbook to research a travel plan, but booking happens elsewhere. In the future, the entire process could happen within Flipbook. Closing the loop from information exploration to action execution sounds appealing, but the implementation difficulty is enormous. Transactions involve payment, refunds, dispute resolution, merchant integration — a complex chain of processes that can't be solved by generating an image with a button. The more likely near-term path is Flipbook generating infographics and then deep-linking to specialized transaction platforms to complete the purchase, rather than building its own full transaction infrastructure.

### Real-Time Data Streams

Current pages are snapshot-style images, but the team plans to render stock prices, exchange rates, weather, and other data in real time within the images — turning Flipbook from an information exploration tool into a real-time dynamic dashboard. This direction is technically feasible, but it essentially means overlaying real-time data streams on images — every frame needs regeneration, multiplying compute costs severalfold. A more practical approach might be hybrid rendering: static content generated by the image model, dynamic data overlaid via traditional overlay techniques.

### Interaction Capabilities

The team mentioned future support for form input, state storage, and complex operations — letting users type, select, and drag directly on generated images. Flipbook would have its own memory (shopping carts, bookmarks, project drafts). This means interaction capabilities would be embedded into the pixel generation process, no longer the exclusive domain of HTML elements. But this needs to solve a fundamental problem: pure image interfaces have far lower interaction precision and efficiency than DOM elements. Clicking a button in an image and clicking a real HTML button are very different experiences — the former requires visual recognition to determine click coordinates, the latter has a clear, direct event target.

### Unified Entry Point Across Apps

This is the most ambitious direction. The team envisions a world where all the tools you use are as rich and visual as the physical world. Translated plainly, Flipbook could become a meta-interface for all apps: hailing a ride, sending an email, ordering food — all dispatched through natural language plus visual interfaces, without opening any standalone app.

| Scenario | Now | Flipbook Vision |
|------|------|--------------|
| Ride-hailing | Open Uber → enter address → confirm | Say "call a ride to the airport" → selection image generated → tap confirm |
| Email | Open Gmail → compose → send | Say "send Alice the project update" → preview image generated → tap send |
| Food delivery | Open food app → pick restaurant → order | Say "order Thai food" → recommendation image generated → tap order |

The problem with this vision is that each vertical app has massive business logic, data, and service integrations behind it — a visual layer can't replace any of that. Flipbook is more likely to become a dispatch layer on top of these apps rather than a replacement. Think of it as an operating system role, but the underlying services still depend on specialized apps.

### Personalized Generation

Currently, generation produces general infographics. In the future, combined with personal data, it could generate fully customized content for each user: your health data plus fitness goals generating a personalized workout plan visualization; your spending habits plus budget generating a tailored financial advice graphic. This direction has clear commercial value, but it hinges on users trusting Flipbook with their personal data — a privacy trust issue.

---

## Technical Challenges

Flipbook has a long road ahead. Several core bottlenecks exist today.

Compute cost is the most immediate problem. Every page is generated in real time by AI, meaning every user click incurs a full image generation inference cost. Model compression, hot-page caching, and edge computing are possible mitigation directions, but until model inference costs drop by an order of magnitude, large-scale commercialization faces significant economic pressure.

Text rendering precision — the team admits it's occasionally imperfect. Image models' text generation capabilities are improving rapidly, but matching the precision of traditional typesetting engines still has a gap, especially in multilingual and complex layout scenarios.

Factual accuracy on par with ChatGPT/Gemini/Claude means the hallucination problem isn't fundamentally solved. In information exploration scenarios, hallucination tolerance is relatively high (users cross-verify), but if Flipbook enters transaction or decision-making scenarios, accuracy requirements jump significantly.

Interaction latency is another hard constraint. Current generation requires wait time — while streaming generation and intent prediction can alleviate this, the latency gap compared to the traditional web experience of clicking a link and instantly loading a page remains noticeable.

| Challenge | Current State | Breakthrough Direction |
|------|----------|----------|
| Compute cost | Every page AI-generated in real time, extremely expensive | Model compression, hot-page caching, edge computing |
| Text rendering precision | Team admits occasional imperfection | Next-gen image models' text capabilities |
| Factual accuracy | ChatGPT-level, hallucinations possible | RAG + real-time search + citation tracing |
| Interaction latency | Generation requires wait time | Streaming generation, intent prediction for pre-generation |
| Business model | Currently sponsored compute | Subscription, per-page consumption billing, B2B |

---

## Personal Assessment

When I first saw the Flipbook demo, my reaction was skepticism about its practicality. But after thinking it through, it touches on a fundamental question: why do we need browsers? A browser's core function is to retrieve information and enable interaction. The traditional web implements this with HTML/CSS/JS, but that's just one implementation — not the only one.

Flipbook redefines the interface form with AI: no longer pages pre-written by engineers, but visual expressions generated on demand based on user intent. From pre-recorded TV to live interactive broadcasts — content is no longer fixed, it changes with demand.

This direction has value, but I'm reserved about it replacing the traditional web in the near term. Pure image interfaces are inferior to DOM interfaces in information density, interaction precision, accessibility, and search indexing. Flipbook is more likely to become a complementary information exploration tool rather than a web replacement. Its best-fit scenario is open-ended knowledge exploration and learning, not task-oriented scenarios requiring precise operations and high efficiency.

The shift from interfaces being built to interfaces being generated is real. But generative interfaces and structured interfaces will coexist for a long time, each with its appropriate scenarios. Flipbook's value lies in being the first to demonstrate the feasibility of generative interfaces, providing a concrete product reference for this direction.
