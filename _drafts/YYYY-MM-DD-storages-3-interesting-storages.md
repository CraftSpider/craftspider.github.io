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

## Inline Storage

This is often pointed to as the 'canonical' advantage of storages - it's a `Storage` that, instead of allocating memory on the heap, actually hands out handles to its own stack location. This allows the creation of a `Box<dyn Trait, InlineStorage<...>>` even on bare-metal targets with no allocator. It's a good example of a storage that makes use of most of the relaxed guarantees over `Allocator`. Handles it gives out aren't pinned (since the actual location of the item will change on every move), and it doesn't necessarily support shared mutability.

The definition of this type is fairly simple, since it's basically just a bag of bytes, with the requested size and alignment.

```rs
trait Align { ... }

struct InlineStorage<const BYTES: usize, ALIGN: Align> {
    backing: [MaybeUninit<u8>; BYTES],
    _align: ALIGN::Align,
}

unsafe impl<const BYTES: usize, ALIGN: Align> Storage for InlineStorage<BYTES, ALIGN> {
    type Handle = ();

	fn allocate(&mut self, layout: Layout) -> Result<Self::Handle, AllocError> {
	    if layout.size() > SIZE {
	        return Err(AllocError::InsufficientSpace);
	    }
	    if layout.align() > ALIGN::as_usize() {
	        return Err(AllocError::InsufficientAlign);
	    }
	    Ok(())
	}
	
	unsafe fn deallocate(&mut self, _: Self::Handle, _: Layout) {}

	fn resolve(&self, _: Self::Handle, layout: Layout) -> &Memory {
	    &self.backing
	}
	
	fn resolve_mut(&mut self, handle: Self::Handle, layout: Layout) -> &mut Memory {
	    &mut self.backing
	}
}
```

We'll go over this implementation piecemeal.

The struct itself is just the requested number of bytes, plus an align. The implementation of this type
is left as an exercise to the reader, this could be made into a `usize` with
