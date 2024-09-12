---
layout: post
title: "Shorts: NaN Boxing and Rust"
date: 2024-09-11 21:24:00 PT
tags: rust shorts
description: All about NaN boxes and the `boxing` library
---

# Type-safe NaN boxing in Rust

Many interpreters for languages that include lots of floating point numbers use a technique known as `NaN`-boxing for improved space efficiency. What is it, and how can we make it both easy and safe with Rust?

## What is it?

First, let's understand what NaN-boxing actually is. For that, we need to understand how `f64` is stored in memory. This will only be the minimal detail necessary for our purposes - for a more in-depth exploration of the floating point format, see [this article](https://blog.reverberate.org/2014/09/what-every-computer-programmer-should.html).

![Float Layout (Wikimedia)](https://upload.wikimedia.org/wikipedia/commons/thumb/a/a9/IEEE_754_Double_Floating_Point_Format.svg/927px-IEEE_754_Double_Floating_Point_Format.svg.png)

This diagram shows the layout of an `f64`. We don't care about what the different parts mean, just this: if the exponent field is all 1's, and *any* bit in the fraction field is 1, the float is a `NaN`. This means there are a lot of valid `NaN` representations in an `f64` - around 4.5e15 of them. We have to give up half to avoid signalling `NaN`s, for various reasons. But if we're careful about it, we should be able to use the rest of that space for whatever data we want.

With that, we get to the central idea of `NaN`-boxing - use the unspecified bits of floating-point `NaN` payloads to store other data. This is basically a fancy kind of [niche optimization](https://rust-lang.github.io/unsafe-code-guidelines/layout/enums.html#discriminant-elision-on-option-like-enums), like Rust already does with enums containing `NonZero` values. Unfortunately, the compiler isn't quite smart enough to do this for us, so we'll have to implement it ourselves. We want to still be able to store `NaN` floats, so we'll pick a single 'canonical' `NaN` value for that. After removing this value, we have 51 bits to work with, and since types come in size multiples of one byte, that gives us 48 bits (6 bytes) to store our values in, and 3 bits to store some kind of tag that we'll use to keep track of the type we've stored. The sign bit of a `NaN` doesn't matter, so we can use that to get one more tag bit, bringing us up to four. Some implementations may use the space slightly differently, but you can never get more than 51 bits of space anyways.

Of course, there are pros and cons to doing this. Programs like JavaScript engines tend to use this technique because they have lots of floating point values, and it allows basically halving (due to alignment restrictions) your memory usage for every value. If you have a lot of floats, this is a good trade-off. If floats are rare though, you may drastically decrease the efficiency of the common case, since reading non-float values involves extra work. Also, while it's common to store pointers using this technique for data larger than 48 bits, that only works if you can assume you're running in a restricted address space[^1]. This is _mostly_ always true currently, but it's not truly 100% portable.

## Making it easy in Rust

So, now we know how `NaN`-boxing works, and a bit about its pros and cons. So how do we implement it in Rust? In the end, we want something that behaves kind of like the following `enum`, but is only 64 bits in size:

```rs
enum FloatBox {
    Float(f64),
    Int(i32),
    Boxed(Box<T>)
}
```

We'll start by building an abstraction at the lowest level. A type that can only be 'a float' or 'something else', and is in charge of ensuring we can't *accidentally* change between the two. It also provides a nice encapsulation of the bit-fiddling logic everything else will rely on.

### The `RawBox` type

This lowest level is defined roughly like this:

```rs
#[repr(C)]
union RawBox {
  float: f64,
  value: ManuallyDrop<Value>,
}
```

Though the full definition has a couple other fields included for various implementation reasons. To check whether the stored value is a float or some other `Value`, we can't *only* do `is_nan()`, since we'd like to be able to represent `NaN` floats too. So, we choose our 'canonical' `NaN`, and determine whether we're storing a float or some other value using `float.is_nan() && float.as_bits() & SIGN_MASK != NAN_BITS`. The sign mask lets us keep track of `NaN` sign - this is useful for Intel chips, which use a specific negative `NaN` value as a value they call 'Real Indefinite'. Luckily, this value happens to be equal to `boxing`'s single canonical `NaN` value, so we support this value behaving correctly 'for free'.

`Value` itself is a pretty simple `repr(C)` type that tracks both the bits we can't touch that make the value a `NaN`, and the bits we use as a tag. With 3 bits in the payload and 1 sign bit, we get 4 bits, or 16 possible tag values. However, there's a hidden pitfall here - if the tag was all zero, and the payload was all zero, we'd just have the canonical `NaN` value! `boxing` avoids this situation by simply not allowing an all-zero tag - this loses us one positive and one negative tag, giving us 14 tags to work with. This is a lot better than avoiding this problem by giving up another whole bit to always be one, since that would leave you with 8 tags instead.

This 'raw' box is a useful abstraction to start with - it lets us implement all the bit fiddling we'll need to do in one place, and supports methods like `tag`, `store`, and `load` for getting at the data inside it. However, it's still not very nice to work with at a high level. While the interface is *safe*, meaning you can't accidentally cause UB or break library invariants, it doesn't handle checking the tag on its own, or allow storing any data with invariants beyond 'is initialized' to preserve that safety[^2].

There are an infinite number of possible implementations you may want to build on top of this base. After all, different projects may want to store different types of data. `boxing` tries to provide implementations for a couple common cases, but if you need something tailored to your needs, you can build it yourself on top of `RawBox`, and let `boxing` handle the bit-level work.

### The `heap::NanBox<'a, T>` type

The primary high-level implementation built in. This type actually assigns the different tag values meanings, and lets you store both borrowed and owned data on the heap if it doesn't fit inline. Since `RawBox` handles all the bit-level work, this type is actually pretty simple. It's basically just a mapping of tags to types, and some implementation work to handle converting the supported types into raw bytes and getting them back out. The lifetime lets you even use it to store references instead of owned data, so it should work easily with an arena or other source of long-lived references.

### In the future

Its been suggested that `boxing` support actually turning its boxes into enums, since there's a major ergonomic limitation of the `NaN` boxes themselves - you can't match on them. I've started implementing this, and once it's done will be releasing an updated version. If you're interested in using it yourself, please try out the library, and suggest any improvements [on the issue tracker](https://github.com/CraftSpider/boxing/issues). The hope is that the conversion between the two forms can be made transparent enough to the compiler that it will optimize the match to be the same as calling the relevant methods yourself.

## Wrapping up

This was a fun project to work on, and I hope it can be useful to someone implementing their own interpreter or other performance-sensitive code someday. If you're interested, check out `boxing` on [crates.io](https://crates.io/crates/boxing) or [GitHub](https://github.com/craftspider/boxing).

[^1]: Many 64-bit systems don't actually ever return pointers with values greater than 2^48. This actually hints at another interesting kind of niched data structure.
[^2]: If you're familiar with pointer UB in Rust, you may say 'wait, but what about provenance?' One of the skipped fields in the `union` is a `*mut ()` field, used in place such as cloning to make sure provenance is preserved. The test suite, including pointer round-trips, is run under Miri to ensure the `RawBox` interface is sound even under strict provenance.