#include "include/LegadoQuickJS.h"
#include "vendor/quickjs.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct LQJSRuntime {
    JSRuntime *runtime;
    JSContext *context;
};

struct LQJSCancellation {
    atomic_bool cancelled;
};

typedef struct {
    uint64_t deadline;
    const LQJSCancellation *cancellation;
    LQJSStatus interruption;
} Evaluation;

static uint64_t monotonic_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

static int interrupt(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    Evaluation *evaluation = opaque;
    if (evaluation->cancellation && atomic_load(&evaluation->cancellation->cancelled)) {
        evaluation->interruption = LQJS_CANCELLED;
    } else if (monotonic_ns() >= evaluation->deadline) {
        evaluation->interruption = LQJS_TIMEOUT;
    }
    return evaluation->interruption != LQJS_OK;
}

LQJSRuntime *lqjs_create(size_t memory_limit, size_t stack_limit) {
    LQJSRuntime *runtime = calloc(1, sizeof(*runtime));
    if (!runtime) return NULL;
    runtime->runtime = JS_NewRuntime();
    if (!runtime->runtime) { free(runtime); return NULL; }
    JS_SetMemoryLimit(runtime->runtime, memory_limit);
    JS_SetMaxStackSize(runtime->runtime, stack_limit);
    JS_SetCanBlock(runtime->runtime, 0);
    runtime->context = JS_NewContext(runtime->runtime);
    if (!runtime->context) { JS_FreeRuntime(runtime->runtime); free(runtime); return NULL; }
    return runtime;
}

void lqjs_destroy(LQJSRuntime *runtime) {
    if (!runtime) return;
    JS_FreeContext(runtime->context);
    JS_FreeRuntime(runtime->runtime);
    free(runtime);
}

LQJSCancellation *lqjs_cancellation_create(void) {
    LQJSCancellation *cancellation = malloc(sizeof(*cancellation));
    if (cancellation) atomic_init(&cancellation->cancelled, 0);
    return cancellation;
}

void lqjs_cancellation_cancel(LQJSCancellation *cancellation) {
    if (cancellation) atomic_store(&cancellation->cancelled, 1);
}

void lqjs_cancellation_destroy(LQJSCancellation *cancellation) { free(cancellation); }

static LQJSResult exception_result(JSContext *context, Evaluation *evaluation, size_t output_limit) {
    JSValue exception = JS_GetException(context);
    const char *message = JS_ToCString(context, exception);
    LQJSResult result = { .status = LQJS_SCRIPT_ERROR };
    if (message) {
        size_t length = strlen(message);
        if (length <= output_limit) result.error = strdup(message);
        JS_FreeCString(context, message);
    } else {
        /* A throwing error.toString() leaves a second exception in the context. */
        JSValue secondary = JS_GetException(context);
        JS_FreeValue(context, secondary);
    }
    JS_FreeValue(context, exception);
    if (evaluation->interruption != LQJS_OK) result.status = evaluation->interruption;
    return result;
}

LQJSResult lqjs_evaluate(LQJSRuntime *runtime, const char *script, size_t length,
                       uint64_t timeout_ns, size_t output_limit,
                       const LQJSCancellation *cancellation) {
    LQJSResult result = { .status = LQJS_OK };
    if (!runtime || !script) { result.status = LQJS_ALLOCATION_ERROR; return result; }
    uint64_t now = monotonic_ns();
    Evaluation evaluation = {
        .deadline = UINT64_MAX - now < timeout_ns ? UINT64_MAX : now + timeout_ns,
        .cancellation = cancellation,
        .interruption = LQJS_OK
    };
    if (interrupt(runtime->runtime, &evaluation)) {
        result.status = evaluation.interruption;
        return result;
    }
    /* Swift callers may move a serialized runtime between worker threads. */
    JS_UpdateStackTop(runtime->runtime);
    JS_SetInterruptHandler(runtime->runtime, interrupt, &evaluation);
    JSValue value = JS_Eval(runtime->context, script, length, "<legado>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) {
        result = exception_result(runtime->context, &evaluation, output_limit);
    } else if (!JS_IsUndefined(value)) {
        JSValue json = JS_JSONStringify(runtime->context, value, JS_UNDEFINED, JS_UNDEFINED);
        if (JS_IsException(json)) {
            result = exception_result(runtime->context, &evaluation, output_limit);
        } else if (!JS_IsUndefined(json)) {
            size_t json_length;
            const char *text = JS_ToCStringLen(runtime->context, &json_length, json);
            if (!text) {
                result = exception_result(runtime->context, &evaluation, output_limit);
            } else {
                if (json_length > output_limit) result.status = LQJS_OUTPUT_LIMIT;
                else {
                    result.json = malloc(json_length + 1);
                    if (result.json) memcpy(result.json, text, json_length + 1);
                    else result.status = LQJS_ALLOCATION_ERROR;
                }
                JS_FreeCString(runtime->context, text);
            }
        }
        JS_FreeValue(runtime->context, json);
    }
    JS_FreeValue(runtime->context, value);
    /* Also catch cancellation during a short evaluation / custom JSON serialization. */
    if (result.status == LQJS_OK && interrupt(runtime->runtime, &evaluation)) {
        free(result.json);
        result.json = NULL;
        result.status = evaluation.interruption;
    }
    JS_SetInterruptHandler(runtime->runtime, NULL, NULL);
    return result;
}

void lqjs_result_destroy(LQJSResult result) {
    free(result.json);
    free(result.error);
}
