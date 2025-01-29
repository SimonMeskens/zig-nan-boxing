# ⚡ Zig NaN Boxing

This library provides a 64-bit dynamic box type that you can use for dynamically typed interpreters, that provides a number of types:

- Doubles (including NaN)
- Integers (signed and unsigned)
- Booleans
- Pointers (truncated at 48 bits), including Null
- C Strings
- Null

The project is complete and tested, but hasn't seen strong use yet. Your help could make it production ready.

## Basic Usage

Example:
```zig
const maybe: ?bool = true;         // Is this real life?

var box = Box.from(42);            // Box an integer
box = Box.from(maybe);             // Now it's a boolean

if (box.isNull()) unreachable;     // Check if it's null
const truth: bool = box.isTrue();  // Take it back out
```
The project also contains fairly exhaustive tests that you can check for more examples.

**Note:** Strings won't automatically get coerced into boxed strings using `from`, you should instead use `fromString`, since it avoids having to guess at intent.

## Run the tests

A comprehensive suite of tests is provided.

```shell
zig build test --summary all
```

## Contributing

I would love to get usage and bug reports if people use this, so I can gauge the production readiness.

PR's are welcome, but I'd like to keep the scope fairly narrow, so new features might get rejected for expanding the scope too much. Feel free to discuss first!

**Q: Will you add 32bit dynamic boxes?**

If I do, they probably wouldn't be NaN boxes, but instead tagged pointers, and that might not fit the scope of this project. I would likely instead make a separate library with 32bit and 64bit tagged pointers.
