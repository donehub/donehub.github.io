---
title: Intent Recognition in Production — A Layered Approach
date: 2025-11-09
lang: en
label: 059_intent-recognition-layered-design
tags: [意图识别]
categories: AI
---

When people hear "intent recognition" these days, the first instinct is to throw it at a large language model. The user says something, the model figures out what they want, returns an intent label, done.

That works, and today's models have no trouble understanding intent. But once you hit real traffic, this approach falls apart fast. The real challenge in intent recognition isn't whether you can identify the intent — it's finding the balance between accuracy, latency, and cost. Understanding why you can't rely on LLMs alone, how each layer of a three-tier architecture works in practice, and the kind of problems that tutorials skip over but you'll almost certainly hit after going live — let's walk through all of that.

<!-- more -->

## LLM-Only Falls Apart at Scale

When your system has a few hundred DAU, dumping everything into an LLM is fine — it's easy. But as request volume grows, problems surface in three places.

First is latency. A single LLM call, even with the fastest model, takes at least several hundred milliseconds before the first token appears; sometimes it's a second or two. A user says "open settings" and waits a full second for a response — that's already unacceptable. Intent recognition sits at the very front of the pipeline. If it doesn't return a result, everything behind it stalls. You've just handed the step that should finish fastest to the slowest component in the system.

Then there's cost. A single intent recognition call — counting system prompt, user input, and a few few-shot examples — averages around 500 tokens, and that's being conservative. At current mainstream model pricing, ten thousand requests is real money. When daily requests hit a million, just the "figure out what the user wants" line item will make your monthly bill hurt. Seventy or eighty percent of those requests are obvious intents like "open settings" or "check balance" — paying flagship model prices to recognize those is waste.

Then stability. Models hallucinate. Give it twenty intents to choose from and occasionally it'll invent a nonexistent twenty-first one, or just break the JSON output. With a large request base, even small probabilities add up to meaningful absolute numbers. And a wrong intent isn't a small mistake — it's at the head of the pipeline, so one wrong turn cascades into parameter filling, tool calls, everything downstream.

Latency, cost, and stability all fail together. LLM-only is fine for a demo. It doesn't survive production.

## Rule-Only Is a Dead End Too

Go the other direction — all keywords and regex — and you solve latency, cost, and stability.

But you lose flexibility. Users don't talk the way your rules expect. You wrote "check balance" in your rules, but they say "how much do I have left" or "what's left on my card" or "what was my balance again". You can't enumerate all of these. Chinese expression patterns are practically infinite, and no matter how many rules you write, there's always a phrasing you didn't think of that breaks through.

Then there's the context problem. The user asks "how much is this plan" in one turn, then says "let's go with that one" in the next. Looking at "let's go with that one" in isolation, regex has no idea what they mean — the intent is buried in the conversation history. Rules have no memory. They're inherently incapable of handling this kind of dialogue.

Put the two extremes side by side and it's clear:

| Approach | Fast | Cheap | Stable | Flexible |
|------|----|----|----|------|
| All hardcoded rules | ✅ | ✅ | ✅ | ❌ |
| All LLM | ❌ | ❌ | ❌ | ✅ |

These two rows are basically complementary. So don't pick one — combine them, and route different requests down different paths. That's the layered approach.

## The Three-Layer Funnel

The funnel metaphor fits well — wide at the top, narrow at the bottom. Requests enter from the top. If they can be resolved up there, don't let them leak down. Only the ones the top layers can't handle sink further.

- Rule layer: handles requests with clear meaning and fixed phrasing. Millisecond-level, essentially free. Catches the high-frequency simple stuff first.
- Context layer: handles routine requests that need conversation history to interpret. Uses small models or semantic vector matching — fast and cheap. Most of the daily traffic flows through here.
- Tool layer: catches the complex, ambiguous requests that the first two layers can't resolve. Uses LLMs with tool calling to connect intent recognition directly to execution. Only handles the truly hard cases.

The core logic is: resolve simple requests cheaply, and only bring out the LLM for complex ones.

A request enters and exits, passing through two checkpoints where it can leak downward. The first is a rule miss. The second is the context layer's confidence falling below threshold. These two checkpoints determine how traffic gets distributed, and they're where the interesting design decisions live.

## Keep the Rule Layer Restrained

The rule layer's technology is plain — plain to the point of not looking like AI at all. Keywords, regex, state machines. That's it.

It does one thing: handle imperative, unambiguous intents that basically never change. "Open settings" jumps to the settings page. "Transfer to human" routes to a human agent. "Check balance" calls the balance API. These share a common trait — there are only a handful of ways to say them, and the meaning is locked to the phrasing. Nobody says "transfer to human" in a hundred different creative ways. They just want to talk to a person. Running these through an LLM is overkill.

The code looks roughly like this:

```java
public class RuleLayer {

    // intent -> trigger words / regex
    private static final Map<String, Pattern> RULES = Map.of(
        "OPEN_SETTINGS", Pattern.compile("打开设置|设置页面|去设置"),
        "TRANSFER_HUMAN", Pattern.compile("转人工|人工客服|要真人|找客服"),
        "QUERY_BALANCE", Pattern.compile("查(询)?余额|还有多少钱|卡里.{0,3}剩")
    );

    /**
     * Returns intent on match, null on miss (leaks to next layer)
     */
    public String match(String text) {
        for (var entry : RULES.entrySet()) {
            if (entry.getValue().matcher(text).find()) {
                return entry.getKey();
            }
        }
        return null;
    }
}
```

The code looks simple, but this layer's most common failure mode is greediness. I've seen teams treat the rule layer as a universal solver, stuffing every intent into it, until the rule file is thousands of lines long, regex nesting regex, changing one word breaks everything, and nobody dares touch it. That's completely backwards.

Three rules for what goes in the rule layer. Only put high-frequency intents in — if an intent gets called a few times a day, it's not worth a rule. Rules need maintenance, and maintenance is cost. Only put intents with fixed phrasing in — if an intent has dozens of ways to express it, it's not suited for rules and belongs in a lower layer. Only put intents that basically never change in — don't hardcode intents that the business adjusts frequently, or you'll be stuck in an endless loop of "just add one more word."

There's another subtle pitfall: rules cause collateral damage. The user says "I don't want to transfer to a human, I'll handle it myself" — your regex contains "transfer to human" and it routes them straight to an agent. So your regex needs to account for negation, for context. But once it gets that complex, that's a signal — this intent should be handed off to the next layer.

The test for whether an intent belongs in the rule layer is blunt: if there are only a handful of ways to say it and they basically never change, put it in. If you're hesitating at all, push it down.

## The Context Layer Carries the Real Load

The rule layer intercepts the high-frequency simple stuff first. The context layer is where the real work happens. Most of the daily routine traffic flows through this layer.

The reason it carries the load is that most real conversations require context. "Let's go with that one," "that still doesn't work," "switch to a different one" — pulled out of context, these are meaningless. The intent lives in the conversation history. The rule layer can't reach it, and dumping everything into an LLM is too expensive. The context layer sits right in the sweet spot between.

### Two Approaches

This layer typically uses one of two approaches, each with its own scenario.

One is semantic vector matching. Pre-vectorize preset intent examples and store them in a vector database, with dozens of typical expressions prepared for each intent. When a user request comes in, vectorize it too, then search for which intent it's closest to.

| Step | Process |
|------|------|
| Intent library build (offline) | "check balance" → ["check balance", "how much do I have left", "what's left on my card"...] → vectors; "check bill" → ["how much did I spend this month", "bill details"...] → vectors |
| Online request | "look at my spending this month" → vectorize → search → closest is "check bill" (similarity 0.87) → hit |

The advantage here is that changing intents doesn't require retraining a model — add a new intent by dropping a few more examples into the library and re-vectorizing. Cold start is fast too; you don't need much data to get running. The downside is it mainly looks at semantic similarity, so intents that require multi-step reasoning get tricky.

The other approach is fine-tuning a lightweight small model. Take a model with a few hundred million parameters — BERT-class or a small generative model — and train it on your business data as a dedicated intent classifier. It understands your business better than vector matching, usually gets higher accuracy, and inference is fast. The trade-off is you need enough labeled data, and adding new intents basically means retraining.

How to choose: my experience is that during cold start, when intents are still changing frequently, use vector matching. Once the business stabilizes, you've accumulated enough data, and you want to push accuracy higher, switch to a small model. Mature systems often use both — vector matching for coarse filtering, small model for fine ranking.

### State Management Is the Make-or-Break

The thing that most easily breaks this layer isn't which model you pick — it's state management.

To understand what "let's go with that one" means, you need to know what the user was talking about in the previous turn. That "what they were talking about" is dialogue state. Get the state wrong, and even the best model is useless — garbage context in, garbage intent out.

State typically needs to hold a few things:

```json
{
  "session_id": "u_10086_20260701",
  "current_intent": "SELECT_PACKAGE",
  "history": [
    {"role": "user", "text": "How much is this plan"},
    {"role": "bot",  "text": "Plan A is 59 yuan/month"}
  ],
  "slots": {
    "package_type": null,
    "confirmed": false
  },
  "turn_count": 3
}
```

With this, when "let's go with that one" comes in, you know the current intent is selecting a package, the previous turn discussed Plan A, and the meaning becomes clear — confirming the selection of Plan A.

A few practical points on state management. Don't stuff conversation history in indefinitely — context is limited and it costs money. A common approach: keep the last few turns as raw text, summarize earlier turns to compress them, and pull out key constraints the user has already confirmed into structured fields. State needs to expire. A conversation from ten minutes ago might not still be relevant context. Set a TTL, or reset when the user clearly changes topics. Otherwise you'll get situations where you ask a new question and the system is still interpreting it through the lens of what you said half an hour ago. Intent switches and interruptions need handling too. The user is in the middle of setting up a plan and suddenly throws in "wait, check my balance first" — that's a classic interruption. You need to recognize it as a new intent, stash the old task, handle the new one, then come back. Get this wrong and the conversation feels rigid.

State management is really just managing the conversation's memory. Not glamorous, but it's the foundation that determines whether the context layer can actually handle real traffic.

## The Tool Layer Is a Safety Net, Not the Main Force

If a request has leaked all the way to the tool layer, it means the first two layers couldn't handle it. What's left is the complex, ambiguous stuff that requires genuine understanding and reasoning. This is where the LLM finally comes in.

The tool layer combines an LLM with tool calling. It doesn't just recognize intent — it connects intent all the way to execution. It understands the user's complex request, picks the right tools (via Function Calling or MCP), fills in the parameters, and routes directly to execution. For example, a user says "Find the months last year where my phone bill exceeded 100, and see if there's a cheaper plan I could switch to." This involves querying, filtering, comparing, and recommending — rules and vector matching can't handle any of it. The LLM understands it, breaks it into a sequence of tool calls: query billing history, filter, match against plan catalog, generate a recommendation — intent to execution in one continuous chain.

I've written a separate post on [how Function Calling works under the hood and how the models are trained for it](/2026/03/21/llm-function-calling-deep-analysis/), so I won't expand on that here. One point specific to intent recognition: the tool layer's advantage is that it collapses recognition and execution into a single step. The first two layers are essentially classifiers — they tell you what the intent is, and then something else still has to go execute it. In the tool layer, the model recognizes the intent, selects the tool, and fills the parameters all at once. The pipeline is end-to-end.

But the tool layer has a bottom line: it's a safety net, not the main force. We already did the math — LLMs are slow and expensive. If it's handling the bulk of traffic, all the work you put into the rule layer and context layer was for nothing, and costs spike instantly. A healthy tool layer only sees a small fraction of requests.

This actually gives you a useful monitoring signal. Watch the tool layer's traffic share. If it suddenly climbs, something's wrong upstream — either rules are failing, the context layer's threshold has drifted, or a batch of new intents has arrived that the upper layers don't cover. That percentage is basically a thermometer for the whole funnel's health.

## Problems You Only Hit After Going Live

The three layers above are the skeleton. Once you're running in production, you'll find that a pile of details determine whether it lives or dies. This part is actually the most useful.

### Valves Between Layers

Whether the funnel leaks correctly depends entirely on the valves. The rule layer's valve is simple — match or miss, binary. The tricky one is the context layer. The model returns "this is check-balance, confidence 0.72" — is 0.72 good enough? You need a threshold.

Set the threshold too high, say 0.95, and a bunch of requests the context layer could have handled get knocked down to the tool layer just because they missed by a little. Costs go up. Set it too low, say 0.5, and the model's coin-flip results get returned as confirmed intents. Accuracy drops.

There's no standard answer for this threshold — you need to tune it against real data gradually. And it's often not a single global value; it's one threshold per intent. Some intents are forgiving — if you get them wrong, the damage is small, so the threshold can be lower. Others are sensitive, like those involving charges or account cancellation — those need very high confidence before you let them through.

### Let It Say "I Don't Know"

This is the thing beginners most often miss. Your intent library has twenty intents. The user might say something completely outside those twenty at any time. The system needs an exit.

Some systems insist on picking the closest match from the twenty, and that's a disaster. The user asks something totally unrelated, the system force-fits it into "check balance," and then solemnly reports a balance figure. The user is baffled.

The correct approach is to allow rejection. The model can return "I'm not sure, this doesn't match any known intent." After rejection, either go to clarification or leak down to the tool layer for the LLM to handle. "I don't know" is a legitimate output, and sometimes an important one. Don't force the classifier to give an answer no matter what.

### Ask When Unsure

When confidence sits in the middle band — not high enough to execute directly, not low enough to reject — the best move is often not to guess, but to ask.

The user says "I want to change it." The system figures it could be changing the plan or changing the address, both around 0.6 confidence. Instead of gambling, just ask "Do you want to change your plan, or your delivery address?" One question turns an ambiguous intent into a clear one, and the user thinks the system is reliable.

The value of clarification is that it trades the system's uncertainty for a very cheap interaction, instead of guessing wrong and dealing with the consequences. When designing the funnel, the default action for the middle confidence band should be clarification.

### Intent and Slots Are Different Things

Many people conflate intent recognition with parameter extraction, but they're two steps. First recognize the intent — what does the user want to do. Then fill the slots — what parameters does doing that require.

"Book a flight from Beijing to Shanghai tomorrow" — the intent is booking a flight, the slots are date=tomorrow, origin=Beijing, destination=Shanghai. If the intent is right but the slots aren't filled — say the date is missing — the system still has to ask "which date would you like?" Which loops right back to clarification.

In the three-layer funnel, slot filling typically happens after the intent is determined. The rule layer or context layer locks down the intent, then a dedicated extraction logic fills the slots — regex, NER models, or even an LLM. If slots aren't complete, ask follow-up questions. Only execute when everything's filled.

### Cold Start with Zero Data

A new business launches. You have zero real user data. You can't train a small model, and the vector library examples are ones you made up yourself. Time for a different approach.

Here's the sequence I follow. Start with the rule layer and tool layer carrying the load. Hand-write rules for high-frequency clear intents, and route everything else to the LLM. The tool layer handles more traffic at this stage, which is expensive, but at least it runs.

Have the tool layer accumulate data as a side effect. While the LLM processes requests, log the user input alongside the recognized intent. That's your earliest batch of labeled data — though you'll want to sample and manually verify it.

Once you have enough data, bolt on the context layer. Use the accumulated data to train a small model or populate the vector library, shifting traffic from the tool layer up to the higher layers. Costs come down naturally.

This is a data flywheel: the tool layer catches everything and produces data, which feeds the upper layers, which take over more traffic, and the tool layer retreats to its safety-net position. It's expensive at first — that's the price of buying data. Once it's running smoothly, costs drop.

### You Need a Way to Recover from Mistakes

Production will have misclassifications. The question isn't whether it'll happen — it's whether mistakes get recorded and used for improvement.

Any reasonably healthy intent recognition system has a bad-case recovery pipeline somewhere. Conversations where the user was clearly dissatisfied — repeated rephrasing, saying the same thing over and over, directly saying "you didn't understand me" — get automatically tagged into a review queue. After human confirmation, you either add rules, add vector examples, or add entries to the training set. Without this recovery loop, your system stays frozen at the level it was on launch day and never improves.

## Walking a Request Through the Full Pipeline

Let's trace a request end to end to tie everything together.

The user says "Actually, forget it. Show me how much I spent this month."

| Step | Process |
|------|------|
| Rule layer | Regex scan — "how much I spent" doesn't precisely hit any hard rule. Leaks down. |
| Context layer | Combined with state: the previous turn had the user debating whether to sign up for a plan. "Actually, forget it" classified as abandoning the current plan task. "Show me how much I spent this month" vector-matches to QUERY_BILL with confidence 0.89, above that intent's threshold of 0.85. Hit — returns QUERY_BILL. |
| Slot filling | QUERY_BILL needs a `time` slot. Extracted time=current month from "this month." Slots complete. |
| Execution | Calls the billing query API, returns the result. The LLM was never involved. |

Now a complex one that leaks all the way to the bottom. The user says "I feel like this plan isn't worth it. Can you analyze whether there's a better fit for me?"

| Step | Process |
|------|------|
| Rule layer | No match. Leaks. |
| Context layer | Semantics too diffuse — vector matching tops out at 0.6, below threshold. Rejected. Leaks. |
| Tool layer | LLM takes over. Understands the complex request to "analyze whether the current plan is worth it and recommend alternatives." Calls query user plan, query historical usage, match plan catalog in sequence. Generates recommendation. Intent to execution in one shot. |

Same system — simple requests get resolved in milliseconds at the top layer, complex ones sink down to the LLM. That's the point of layering. Not every request needs the strongest weapon. Each request gets matched to the right cost.

## What Layering Actually Solves

This three-layer structure for intent recognition is really managing four things simultaneously: accuracy, latency, cost, and flexibility. No single approach can handle all four. Rules sacrifice flexibility. LLMs sacrifice latency and cost. What's clever about layering isn't that it uses any new technology — rules, regex, vector matching are all ancient — it's that it matches each request to the most appropriate processing method. High-frequency clear requests go through rules, which are fast and cheap. Routine requests that need context go through the context layer, balancing speed and flexibility. The small number of complex, ambiguous requests go to the tool layer, trading cost for capability.

Add rejection, clarification, thresholds, the cold-start flywheel, and bad-case recovery on top, and the whole thing can actually survive in production — and keep getting better.

LLMs are genuinely powerful — powerful enough to create the illusion that you can just dump everything on them. But the systems that actually ship, handle traffic, and keep costs in check never got there by using the strongest model. They got there by knowing where not to use it. That's what layering is about — making sure every cent of cost lands where it should.
