---
layout: post
title: "Storages 3: Interesting Storages"
date: 2026-03-16 12:00:00 PST
tags: rust storages
description: Examples of useful storage implementations.
---

Welcome to Part 3 of my series on the `Storage` API. If you missed the first post, it can be found [here](TODO).

In previous posts, we examined the `Storage` API and its advantages over `Allocator`. Now, we'll examine some interesting
implementations. Most of these would be impossible to implement with `Allocator` as-is.

## Inline Storage

This is often pointed to as the 'canonical' advantage of storages - it's a `Storage` that, instead of allocating memory on the heap, actually hands out handles to its own stack location. This allows the creation of a `Box<dyn Trait, InlineStorage<...>>` even on bare-metal targets with no allocator. It's a good example of a storage that makes use of most of the relaxed guarantees over `Allocator`. Handles it gives out aren't pinned (since the actual location of the item will change on every move), and it doesn't necessarily support shared mutability.

The definition of this type is fairly simple, since it's basically just a bag of bytes, with the requested size and alignment. See the following example implementation[^1]:

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

The struct itself is just the requested number of bytes, plus an align. The implementation of this type
is left as an exercise to the reader, as it isn't important for our purposes. We also assume it's a ZST here.

The impl is similarly trivial - we don't need a handle at all, since we only support one location, and so all we need to do
is confirm the requested allocation will fit in our size and align. Then when we resolve, we can just directly return the backing
array as a `Memory` slice.

Our `InlineStorage` can implement none of the extended `Storage` traits. It can't be pinned, it doesn't support multiple allocations, and at least our variant doesn't handle shared mutability (though that one could be changed). It's a good example of what's unlocked by relaxing our guarantees, and does have uses outside embedded contexts. `std`'s `Vec` can make use of it, for example, to have `ArrayVec` behavior, fully on-stack but with dynamic length tracking, with no extra work. With 338 million downloads, this is definitely a use case with a lot of interest.

But as mentioned last article, there are more interesting abilities of this API than just inline items. Though the next one does make use of it as a primitive...

## Small Storage

While _only_ inline values may not seem so useful in most situations, there's a common optimization that makes use of them in combination with more normal allocation - 'small' vector optimizations. This has a little over twice the downloads at time-of-writing, at 680 million. This is fairly simple with storages, though the whole implementation doesn't _quite_ fit in an example[^2]:

```rs
pub enum MaybeHandle<S: Storage> {
	Inline,
	Outline(S::Handle)
}

pub struct SmallStorage<const SIZE: usize, ALIGN: Align, S: Storage> {
    inline: InlineStorage<SIZE, ALIGN>,
    outline: S,
}

unsafe impl<DataStore, S: Storage> Storage for SmallStorage<DataStore, S> {
    type Handle = MaybeHandle<S>;

    fn allocate(&mut self, layout: Layout) -> Result<Self::Handle, AllocError> {
        if self.inline.fits(layout) {
            self.inline.allocate(layout)?;
            Ok(MaybeHandle::Inline)
        } else {
            let addr = self.outline.allocate(layout)?;
            Ok(MaybeHandle::Outline(addr))
        }
    }

    unsafe fn deallocate(&mut self, handle: Self::Handle, layout: Layout) {
        match handle {
        	MaybeHandle::Inline => self.inline.deallocate((), layout),
        	MaybeHandle::Outline(addr) => self.outline.deallocate(addr, layout),
        }
    }

    unsafe fn resolve(&self, handle: Self::Handle, layout: Layout) -> &Memory {
        match handle {
        	MaybeHandle::Inline => self.inline.resolve(()), layout),
        	MaybeHandle::Outline(addr) => self.outline.resolve(addr, layout),
        }
    }

    unsafe fn resolve_mut(&mut self, handle: Self::Handle, layout: Layout) -> &mut Memory {
        match handle {
        	MaybeHandle::Inline => self.inline.resolve_mut(()), layout),
        	MaybeHandle::Outline(addr) => self.outline.resolve_mut(addr, layout),
        }
    }

    unsafe fn grow(
        &mut self,
        handle: Self::Handle,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<Self::Handle, AllocError> {
        // .. snip ..
    }

    unsafe fn shrink(
        &mut self,
        handle: Self::Handle,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<Self::Handle, AllocError> {
        // .. snip ..
    }
}
```

This gives us the optimization we desire, again, with minimal changes needed to the `std` types. Users can choose how big their 'inline' storage is, and in a failure case fallback to any storage they want. Normally this would be a system allocator, but it could be any other storage location.

## Putting Memory Anywhere

We just implied there were other storage locations than a system allocator or an inline storage. Many of these locations are somewhat niche, but they have uses, particularly in performance-critical software. We can make storages that live in static memory, on the heap as local variables, or even in a file on disk[^3].

We can also make storage transformers, like iterator transformers. A debug or tracing transformer could be used to track memory usage over time in a granular fashion (which doesn't entirely replace global tracing). One can also imagine some kind of arena transformer that can apply to any storage and bunches multiple small allocations into single larger ones. Some of this may already be possible with allocators as-is, but I think they're still useful to bring up. And even if Rust doesn't go with the storages proposal, it's still worth considering what the chosen API does and doesn't allow.

# Conclusions

In this series, we've covered the problems with `Allocator`, the `Storage` proposal, and some hopefully motivating examples. I hope that even if you don't agree with storages for the standard library, this series has helped provide better motivation, and encouraged you to consider the tradeoffs of whichever way Rust goes.

[^1]: Example code borrowed from https://github.com/CAD97/storages-api/, with some changes to simplify things for example
[^2]: As an optimization, the full implementation actually puts the allocator handle in the inline storage. This allows it to use a ZST handle, at the cost of a more complicated implementation.
[^3]: Definitely not good for high-performance applications, but could be very interesting for games. Have the allocator itself act as an LRU cache, saving rarely accessed allocations to disk.