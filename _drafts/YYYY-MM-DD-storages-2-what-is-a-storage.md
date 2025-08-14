---
layout: post
title: "Storages 2: What is a Storage?"
date: YYYY-MM-DD HH:MM:SS PST
tags: rust storages
description: What is a `Storage`?
---

Welcome to part 2 of my series on the `Storage` API. If you missed the first post, it can be found [here](TODO).

In the last post, we went over why `Allocator` isn't serving its purpose. In this post, we'll cover the basics of the proposed replacement.

## The Base

All storages, no matter what else they can do, need to be able to... well, store something. Here's one way we could define `Storage`:

```rs
type Memory = [MaybeUninit<u8>];

unsafe trait Storage {
	type Handle;

	fn allocate(&mut self, layout: Layout) -> Result<Self::Handle, AllocError>;
	unsafe fn deallocate(&mut self, handle: Self::Handle, layout: Layout);

	fn resolve(&self, handle: Self::Handle, layout: Layout) -> &Memory;
	fn resolve_mut(&mut self, handle: Self::Handle, layout: Layout) -> &mut Memory;
}
```

We already see some differences to `Allocator`. Instead of always returning pointers, we use a `Handle` associated type. This can then be turned into references with the `resolve` or `resolve_mut` methods. These methods return references to slices of `MaybeUninit` bytes - because they're references, they compiler *won't let them outlive the borrow of the allocator*. This is an important property, because `Storage` doesn't require that memory is pinned by default. That means the 'allocation' it returns could actually be from inside the storage value itself - moving the storage moves the memory then, but that's fine because we didn't return a pointer on allocation, but an opaque `Handle`. It's also only possible to mutate the backing memory if you are holding a unique reference to the storage. It turns out many allocating types (including `Box`, `Vec`, and even `BTreeMap`) work just fine with these restrictions, since they exactly match Rust's existing rules around aliasing-xor-mutation and ownership.

Most places that discuss benefits of `Storage` start by pointing out that this allows things like `Box<dyn Trait>` in alloc-free contexts, since now you can have some `InlineStorage<BYTES, ALIGN>` that has a fixed max size, and any type that fits in that space can be used without actual indirection. This is a very nice property for embedded or certain highly-optimized use-cases, but I didn't start with it because it's only *one advantage* of storage, and one that most people honestly may never use. If you don't care about this use case, it's easy to ask why we should be making a more complex API for this one thing. But really, the point isn't one use-case, it's about providing a better abstraction that fits in with Rust's style and memory-safety guarantees.

## But I really like leaking things

So, now we have our base. It allows the important things - allocating and deallocating memory. But now you *do* want to be able to pin your memory, or share handles between different instance of the same `Storage`. Something like `Rc` needs to be able to do this, since every `Rc` will be holding its own instance of a `Storage`, and we expect to be able to clone it and still resolve the handle to the same memory.

We allow `Storage` implementations to provide these extended guarantees in the same way as `Iterator` does, with subtraits. The `PinningStorage` trait means that, until `dealloc` is called, the memory the storage points to won't move. There's also a `SharedMutabilityStorage` that allows resolving `&self -> &mut Memory` unsafely, implying memory mutation is legal behind shared references, and that different handles can be resolved mutably at the same time.

```rs
unsafe trait PinningStorage: Storage {}
```

```rs
unsafe trait SharedMutabilityStorage: Storage {
	unsafe fn resolve_shared(&self, handle: Self::Handle, layout: Layout) -> &mut Memory;
}
```

This architecture, of having subtraits to represent guarantees, also means you can easily write `Storage` adapters in the same way you have `Iterator` adapters. Some `FallbackStorage<S1, S2>` type that tries one storage, then another when the first returns an `AllocError` can implement `PinningStorage` if both its sub-storages implement it, but not otherwise. Overall, the design is flexible for both the implementors of storages *and* the users, since a user can request as many or as few guarantees as they want.

## What else?

Since `Storage` is just a proposal, it's not 100% certain what set of subtraits would exist, and what exact guarantees each would provide. There's a tug-of-war between being incredibly granular but making it harder for users, and being broad and making it harder to implement useful things. If we go really broad, we end up back at `Allocator`, a single trait that encompasses too many guarantees. This is actually one frequently included proposal - keep a trait alias `Allocator`, like the following:

```rs
trait Allocator = Storage + PinningStorage + SharedMutabilityStorage + ...;
```

Then, users who still want 'just give me `malloc`' can simply bound on `Allocator`, and don't even need to think about the details of the implementation. This may slightly encourage requiring more guarantees than you need, but it also provides both a nice simple entry point, while making it much easier to look at the documentation and immediately see that you're just requesting 'a storage, but with a bunch of requirements'. I personally think it's a fine inclusion, since one reasonable complaint about storages is that they have a pretty broad API surface for when you just want to get started with custom allocators.

Hopefully you now have at least a basic understanding of the `Storage` API. In the next post, we'll be looking at some concrete implementations of interesting storages, and data-types that use them.
