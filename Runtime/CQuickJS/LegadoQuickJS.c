#include "include/LegadoQuickJS.h"
#include "vendor/quickjs.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct Evaluation Evaluation;
struct LQJSRuntime {
    JSRuntime *runtime;
    JSContext *context;
    LQJSHostCall host;
    LQJSShouldCancel should_cancel;
    void *opaque;
    Evaluation *active;
};

struct LQJSCancellation {
    atomic_bool cancelled;
};

struct Evaluation {
    uint64_t deadline;
    const LQJSCancellation *cancellation;
    LQJSStatus interruption;
    LQJSRuntime *owner;
    size_t output_limit;
};

static uint64_t monotonic_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

static int interrupt(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    Evaluation *evaluation = opaque;
    if ((evaluation->cancellation && atomic_load(&evaluation->cancellation->cancelled)) ||
        (evaluation->owner->should_cancel && evaluation->owner->should_cancel(evaluation->owner->opaque))) {
        evaluation->interruption = LQJS_CANCELLED;
    } else if (monotonic_ns() >= evaluation->deadline) {
        evaluation->interruption = LQJS_TIMEOUT;
    }
    return evaluation->interruption != LQJS_OK;
}

static JSValue host_call(JSContext *context, JSValueConst this_value, int argc, JSValueConst *argv) {
    (void)this_value;
    LQJSRuntime *runtime = JS_GetContextOpaque(context);
    if (!runtime->host || argc < 1 || !JS_IsString(argv[0])) return JS_ThrowTypeError(context, "Invalid host call");
    if (!runtime->active || interrupt(runtime->runtime, runtime->active)) return JS_ThrowInternalError(context, "Interrupted host call");
    JSValue arguments = JS_NewArray(context);
    for (int i = 1; i < argc; i++) JS_SetPropertyUint32(context, arguments, i - 1, JS_DupValue(context, argv[i]));
    JSValue json = JS_JSONStringify(context, arguments, JS_UNDEFINED, JS_UNDEFINED);
    JS_FreeValue(context, arguments);
    if (JS_IsException(json)) return json;
    size_t length = 0;
    const char *encoded = JS_ToCStringLen(context, &length, json);
    JS_FreeValue(context, json);
    if (!encoded) return JS_EXCEPTION;
    if (length > runtime->active->output_limit) {
        JS_FreeCString(context, encoded);
        return JS_ThrowRangeError(context, "Host arguments exceed size limit");
    }
    const char *action = JS_ToCString(context, argv[0]);
    if (!action) { JS_FreeCString(context, encoded); return JS_EXCEPTION; }
    char *response = runtime->host(runtime->opaque, action, encoded);
    JS_FreeCString(context, action);
    JS_FreeCString(context, encoded);
    if (!response) return JS_ThrowOutOfMemory(context);
    JSValue envelope = JS_ParseJSON(context, response, strlen(response), "<host>");
    free(response);
    if (JS_IsException(envelope)) return envelope;
    JSValue error = JS_GetPropertyStr(context, envelope, "error");
    JSValue result;
    if (JS_IsString(error)) {
        const char *message = JS_ToCString(context, error);
        result = JS_ThrowInternalError(context, "%s", message ? message : "Host call failed");
        JS_FreeCString(context, message);
    } else {
        result = JS_GetPropertyStr(context, envelope, "value");
    }
    JS_FreeValue(context, error);
    JS_FreeValue(context, envelope);
    return result;
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
    JS_SetContextOpaque(runtime->context, runtime);
    JSValue global = JS_GetGlobalObject(runtime->context);
    JS_SetPropertyStr(runtime->context, global, "__legadoHost", JS_NewCFunction(runtime->context, host_call, "__legadoHost", 1));
    JS_FreeValue(runtime->context, global);
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

int lqjs_cancellation_is_cancelled(const LQJSCancellation *cancellation) {
    return cancellation && atomic_load(&cancellation->cancelled);
}

void lqjs_set_host(LQJSRuntime *runtime, LQJSHostCall callback, LQJSShouldCancel should_cancel, void *opaque) {
    runtime->host = callback;
    runtime->should_cancel = should_cancel;
    runtime->opaque = opaque;
}

LQJSResult lqjs_set_global(LQJSRuntime *runtime, const char *name, const char *json, size_t length) {
    JS_UpdateStackTop(runtime->runtime);
    JSValue value = JS_ParseJSON(runtime->context, json, length, "<binding>");
    int failed = JS_IsException(value);
    if (!failed) {
        JSValue global = JS_GetGlobalObject(runtime->context);
        failed = JS_DefinePropertyValueStr(runtime->context, global, name, value, JS_PROP_C_W_E | JS_PROP_THROW) < 0;
        JS_FreeValue(runtime->context, global);
    }
    LQJSResult result = { .status = failed ? LQJS_SCRIPT_ERROR : LQJS_OK };
    if (failed) {
        /* Do not invoke a user-defined exception.toString outside an evaluation budget. */
        JSValue exception = JS_GetException(runtime->context);
        JS_FreeValue(runtime->context, exception);
        result.error = strdup("Unable to install script binding");
    }
    return result;
}

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
        .interruption = LQJS_OK,
        .owner = runtime,
        .output_limit = output_limit
    };
    if (interrupt(runtime->runtime, &evaluation)) {
        result.status = evaluation.interruption;
        return result;
    }
    /* Swift callers may move a serialized runtime between worker threads. */
    JS_UpdateStackTop(runtime->runtime);
    Evaluation *previous = runtime->active;
    runtime->active = &evaluation;
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
    if (interrupt(runtime->runtime, &evaluation)) {
        free(result.json);
        result.json = NULL;
        result.status = evaluation.interruption;
    }
    runtime->active = previous;
    JS_SetInterruptHandler(runtime->runtime, previous ? interrupt : NULL, previous);
    return result;
}

void lqjs_result_destroy(LQJSResult result) {
    free(result.json);
    free(result.error);
}
