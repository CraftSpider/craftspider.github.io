---
layout: post
title: "Storages 3: Interesting Storages"
date: YYYY-MM-DD HH:MM:SS PST
tags: rust storages
description: Examples of useful storage implementations.
---

Welcome to Part 3 of my series on the `Storage` API. If you missed the first post, it can be found [here](TODO).

In previous posts, we examined the `Storage` API and its advantages over `Allocator`. Now, we'll examine some interesting
implementations. Most of these would be impossible to implement with `Allocator` as-is.

## 