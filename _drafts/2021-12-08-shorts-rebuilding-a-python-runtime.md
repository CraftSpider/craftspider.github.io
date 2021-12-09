---
layout: post
title: "Shorts: Rebuilding a Python runtime"
date: 2021-12-08 19:07:00 EST
tags: python shorts
description: How to `del` your whole python runtime, then get it back
---

A while ago, I wrote up what I think is a neat little Python script. I've since lost the original file, but we're going to re-write it, right here.

What did this file do in the first place? Well, it started by deleting the whole runtime. In other words, it called `del` on every single global variable, module, type, etc. Recursively, in a couple cases. Once that's done, it becomes impossible to even import modules. After all, imports are actually managed by a special global `__import__` function, which we now can't access.

Lets start with re-writing that. I'll be using Python 3.9, but this general formula should work for any version.

First, we get a reference to both the globals dictionary, then we want to get rid of all global variables that aren't `__builtins__`, or the globals themselves. After all, this contains things like the file loader. Then we can get rid of the iteration variable, finally followed by our globals variable.

```py
_globals = globals()
for i in list(_globals.keys()):
    if i not in ("__builtins__", "_globals"):
        del _globals[i]
del i
del _globals
```

Next step, we want to clean up our builtins. This will remove our ability to access `__import__`, Exceptions, and any of the builtin types or functions by name. We also need to preserve one or two things here, as we'll be using them right up until the end.

```py
for i in dir(__builtins__):
    # If you want to see things, you can exclude print here, and use it for debugging.
    # This doesn't change anything as long as you otherwise pretend it doesn't exist
    if i != "delattr":
        delattr(__builtins__, i)
del i
del __builtins__.delattr
del __builtins__
```

Now we should be in an 'empty' runtime environment. If you're following along, now is a good time to play around a bit. Figure out what you can and can't do.

The answer is, not much. You can write out literals and control flow, but just about everything else is impossible. Imports don't work, you can't call `quit`, and you can't name any types. Now, how are you going to get back to where we started from here? Well, it starts with the most important thing we can still do: create literals. Python literals don't look up their type in `__builtins__`, their types are hardcoded. This means we can get their types back, through all instances `__class__` variable! We'll start by doing that. These won't be builtins yet, but we'll get to that later.

```py
int = (1).__class__
float = (1.5).__class__
bool = (True).__class__
tuple = ((1, 2)).__class__
list = [].__class__
dict = {}.__class__
```

This is all well and good, but where can we go from here? Well, our end-goal is to rebuild everything. How do we even intend to do that? Well, assuming the things we deleted still exist somewhere, we should be able to get them back using the `gc` module, getting all active objects. To get that, we either need to be able to import things again, or, we can get it out of the un-deleted `sys.modules` if we're lucky and it was loaded before during the startup process. But that's all still a pipe dream. First, lets see what other builtin types we can still get back:

```py
type = int.__class__
object = type.__base__
```

And here's our first 'holy grail': `object`. It is the base of all types, and that means something very special for us: It has a method, `__subclasses__()`, which will give us every subclass of `object` created thus far. This include `BaseError`, and through it all the exception types, as well as the importer types. Now, we won't be invoking these directly, because they can give us something much more useful.

```py
```