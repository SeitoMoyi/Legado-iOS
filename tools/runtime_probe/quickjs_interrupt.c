/* Standalone investigation only: not linked into LegadoCore or the iOS application. */
#include "quickjs.h"
#include <stdio.h>
#include <string.h>
#include <time.h>

struct Budget { double deadline; unsigned polls; };

static double now(void) {
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return value.tv_sec + value.tv_nsec / 1e9;
}

static int interrupt(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    struct Budget *budget = opaque;
    budget->polls++;
    return now() >= budget->deadline;
}

int main(void) {
    const char *loops[] = { "while (true) {}", "for (;;) {}", "(function(){ for (;;) {} })()" };
    double start = now();
    unsigned total_polls = 0;
    for (int attempt = 0; attempt < 50; attempt++) {
        JSRuntime *runtime = JS_NewRuntime();
        if (!runtime) return 1;
        JS_SetMemoryLimit(runtime, 16 * 1024 * 1024);
        JS_SetMaxStackSize(runtime, 256 * 1024);
        JSContext *context = JS_NewContext(runtime);
        if (!context) { JS_FreeRuntime(runtime); return 1; }
        struct Budget budget = { now() + .005, 0 };
        JS_SetInterruptHandler(runtime, interrupt, &budget);
        const char *script = loops[attempt % 3];
        JSValue value = JS_Eval(context, script, strlen(script), "loop.js", JS_EVAL_TYPE_GLOBAL);
        int interrupted = JS_IsException(value) && budget.polls > 0;
        JS_FreeValue(context, value);
        JSValue exception = JS_GetException(context);
        JS_FreeValue(context, exception);
        JS_SetInterruptHandler(runtime, NULL, NULL);
        value = JS_Eval(context, "1 + 1", 5, "recovery.js", JS_EVAL_TYPE_GLOBAL);
        int answer = 0;
        int recovered = !JS_IsException(value) && JS_ToInt32(context, &answer, value) == 0 && answer == 2;
        JS_FreeValue(context, value);
        total_polls += budget.polls;
        JS_FreeContext(context);
        JS_FreeRuntime(runtime);
        if (!interrupted || !recovered) {
            fprintf(stderr, "Attempt %d failed: interrupted=%d recovered=%d\n", attempt, interrupted, recovered);
            return 1;
        }
    }
    printf("50/50 loops interrupted; recovery evaluations passed; all contexts and runtimes freed.\n");
    printf("Elapsed %.3f s, interrupt callback polls %u.\n", now() - start, total_polls);
    return 0;
}
