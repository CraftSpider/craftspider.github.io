---
layout: post
title: "Storages 1: `Allocator` is a bad abstraction"
date: YYYY-MM-DD HH:MM:SS PST
tags: rust storages
description: Why should we replace `Allocator` in the first place?
---

Welcome to my new series on the `Storage` proposal, a replacement for the currently-unstable `Allocator` trait. We'll be going over why `Allocator` isn't a good abstraction, how we can do better, and look into a shiny future. So, lets dive in with part 1, where I'll hopefully convince you that the current `Allocator` trait isn't a very good abstraction.

## Why does this matter?

I guess I'll first address a higher level question - Why does any of this matter? Who cares if `Allocator` sucks, if its gotten us this far? If you already consider the answer to these obvious, feel free to skip this section. These are fair enough questions to have, given that a lot of practical programming is about 'good enough'. However, I think that Rust has done a good job so far of setting a higher standard. The `std` library isn't just a collection of random pieces, but a currated library of the most important abstractions. Things like randomness and time management haven't yet made it into the standard library because there are many potential implementations, and the maintainers of Rust made a decision to let libraries determine what the most popular and cleanest implementation looks like before considering lifting it into the standard library. `Allocator` should be no different - nothing prevents you from writing your own `Box` and `Vec` with whatever allocator you want to use. But for it to be in the standard library, it should preferably be the _best_ such implementation. Or at least one that's good enough for 99% of use cases.

Another important detail is that the standard library has pretty strong compatibility guarantees to follow. If we stabilize `Allocator` now and regret the design later, changing it is basically impossible. Maybe with enough editions we could gradually shove it into the shape we want, but that would also involve committing to maintaining both the new interface and the old one, forever. There are several examples of such regrets in the standard library, and maintainers often lament their existence. For one example, making `mem::uninitialized()` a compile error in newer editions is regularly discussed, and the implementation has changed several times to make it less dangerous. It doesn't even return anything like uninitialized memory nowadays, instead returning a value filled with repetitions of `0x01`.

Hopefully I've convinced you that getting things right *matters*, and thus it's worth at least considering all the options before committing to what we're stuck with forever. With that established, I'll move into the actual point of the article.

## `Allocator` is leaky

The `Allocator` trait, currently, has some pretty restrictive safety guarantees. These come from what it really is - a thin wrapper over `malloc`. The allocator trait isn't really designed to be an abstraction over *any* method of allocation. It's designed to be a good abstraction over different implementations of things that you could sub in for `malloc` and `free` in a C program. This makes it a very leaky abstraction - the implementor is constrained in what they can do, because the user is allowed to assume all sorts of things about the returned pointers.

This, in turnm makes `Allocator` overly restrictive for most use cases. You never `Pin` your value? It has to be pinnable anyways. You never leak any values? You must be able to anyways. And one you may not normally consider - you never need to mutate the data without `&mut` access to the allocator? It has to support shared mutation anyways. We make all use-cases pay for support for things a lot of data types or situations may not ever need. It would be nice to separate these concerns - have a way to only require the guarantees you actually need, so you automatically allow users who don't care to... not care.

## `Allocator` is complex

If all that seemed pretty technical, that's because it is. `Allocator` needs a complex mental model to understand what it's doing. It's not just handing out 'pointers to stuff', it's handing out 'pinned/unique/leakable pointers'. Forgetting any of these properties in your implementation will make your `Allocator` unsound. Even the Rust devs have had problems with this - the `Allocator` trait has required several tweaks to both implementation and safety rules to fix actual unsoundness in the existing implementation. Some of this is unavoidable, allocation is a pretty low-level thing and will require some level of understanding of the underlying rules no matter what. But some of it could have been avoided if the rules were broken up into clearer chunks, allowing one to evaluate the soundness of an implementation under one rule at a time.

## Imagining a better world

So, `Allocator` is leaky and complicated. It abstracts 'being malloc', not some deeper concept. What would we prefer it to be an abstraction of? And what rules do we want this hypothetical trait to follow? Lets start with what the name implies - allocation. Allocation, at a deeper level, is about getting 'a chunk of memory' that can be used to store data in. This seems like a good place to start. Lets try to build an abstraction that is based on 'providing memory to use' as its conceptual goal. On top of that, we'll want to keep track of a couple properties some implementations will require. *Some* users will want to be able to know that memory they get is 'Pinned'. Such memory has a single consistent address until deallocated. Some users will want memory to be 'Leakable'. This means the memory can outlive the type that provided it, and maybe later deallocated by a different instance of the same type. Some users will want to store multiple elements at once - users like `Box` or `Rc` only ever care about one chunk of memory, but `Vec` will want to grow and shrink that memory over time, and a user like `HashMap` may want many different chunks, not caring if they're contiguous. And finally, some users (`Rc`, `Arc`) will want to be able to mutate the memory using only a shared reference to the allocator, while others will only ever mutate it while maintaining unique ownership (`Box`, `Vec`).

With all this, we've established why `Allocator` is a bad abstraction, and what the abstraction we actually want should look like. In the next post, we'll finally discuss `Storage`, the proposal for how to write that abstraction.
