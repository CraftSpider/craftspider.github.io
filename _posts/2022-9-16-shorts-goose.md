---
layout: post
title: "Shorts: The Goose Language"
date: 2022-9-16 12:00:00 EST
tags: rust shorts
description: A language that is intentionally obtuse
---

I have a passing interest in esoteric languages, and one day I was talking with my partner we had an interesting idea: What if there was a programming language without return statements? You still had functions, but instead of them returning at the end or when you invoked `return`, you defined them alongside a condition expression. When this expression evaluates to true, the function exits.

He and I spent a while going back and forth about some possible semantics for this language. In general, we tried to follow a pattern of making the language usable, while simultaneously making it intentionally somewhat obtuse to write. We settled on removing `if` and `while` loops, as those could be easily emulated by functions.

The current implementation of the language is interpreted but typed to an unspecified degree - which personally, I feel is fitting for a language meant to be intentionally annoying to use.

If you're interested in checking out Goose, take a look at [https://github.com/CraftSpider/goose]. Feel free to open issues on the repository if you have any comments or suggestions.