# QuickJS interruption investigation

This probe is separate from the iOS app. It does not change the app's JavaScript engine or add a package dependency.

Tested source: the official [QuickJS 2026-06-04 archive](https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz).

SHA-256: `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`.

After downloading and extracting the source, build its static library and compile this probe (replace the example absolute paths with your local directories):

```sh
make -C /tmp/quickjs-2026-06-04 -j2 libquickjs.a CC=clang
clang -I /tmp/quickjs-2026-06-04 tools/runtime_probe/quickjs_interrupt.c /tmp/quickjs-2026-06-04/libquickjs.a -lm -lpthread -o /tmp/legado-quickjs-interrupt
/tmp/legado-quickjs-interrupt
```

Observed on macOS, 2026-10-26:

```text
50/50 loops interrupted; recovery evaluations passed; all contexts and runtimes freed.
Elapsed 0.266 s, interrupt callback polls 4752.
```

The probe installs QuickJS's public interrupt callback, gives each script a 5 ms monotonic-clock budget, applies a 16 MiB heap limit and 256 KiB stack limit, and runs three kinds of infinite loops over 50 fresh runtimes. Each interrupted evaluation is followed by `1 + 1`, then explicit context and runtime destruction. Timing and callback counts vary by machine. This is not a leak-detector result or a guarantee that every native operation can be interrupted at its deadline.

Also compiled the five core files (`quickjs.c`, `dtoa.c`, `libregexp.c`, `libunicode.c`, `cutils.c`) with the installed iPhoneOS SDK, targeting arm64 and iOS 15.0. The operating-system / shell module `quickjs-libc.c` was excluded. This confirms compilation, not iOS runtime behavior or a working Swift bridge.

The next integration must preserve Legado's existing Java / book / source bindings, bound host HTTP calls separately, verify interruption and cleanup on iOS, and cover expensive native operations as well as loops. See [the runtime implementation notes](../../docs/SourceRuntime.md).
