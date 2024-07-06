---
layout: post
title: "Storages 1: `Allocator` is a bad abstraction"
date: YYYY-MM-DD HH:MM:SS PST
tags: rust storages
description: Why should we replace `Allocator` in the first place?
---

## Points to cover

- Allocator is a thin wrapper over 'malloc'-like behavior
- Allocator is overly restrictive for most use-cases
  - We make everyone pay for supporting the few
- It requires a more complicated mental model
- What are the properties we care about? 
- What if we split up Allocator into those components (Post 2)