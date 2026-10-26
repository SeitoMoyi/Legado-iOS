#ifndef LEGADO_QUICKJS_H
#define LEGADO_QUICKJS_H

#include <stddef.h>
#include <stdint.h>

typedef struct LQJSRuntime LQJSRuntime;
typedef struct LQJSCancellation LQJSCancellation;
/* Host returns an owned malloc-compatible JSON envelope: {"value":...} or {"error":...}.
 * It is called on the evaluating thread; the adapter releases the returned buffer. */
typedef char *(*LQJSHostCall)(void *opaque, const char *action, const char *arguments);
typedef int (*LQJSShouldCancel)(void *opaque);

typedef enum {
    LQJS_OK = 0,
    LQJS_SCRIPT_ERROR = 1,
    LQJS_TIMEOUT = 2,
    LQJS_CANCELLED = 3,
    LQJS_OUTPUT_LIMIT = 4,
    LQJS_ALLOCATION_ERROR = 5
} LQJSStatus;

typedef struct {
    LQJSStatus status;
    char *json;
    char *error;
} LQJSResult;

LQJSRuntime *lqjs_create(size_t memory_limit, size_t stack_limit);
void lqjs_destroy(LQJSRuntime *runtime);
LQJSCancellation *lqjs_cancellation_create(void);
void lqjs_cancellation_cancel(LQJSCancellation *cancellation);
void lqjs_cancellation_destroy(LQJSCancellation *cancellation);
int lqjs_cancellation_is_cancelled(const LQJSCancellation *cancellation);
void lqjs_set_host(LQJSRuntime *runtime, LQJSHostCall callback, LQJSShouldCancel should_cancel, void *opaque);
LQJSResult lqjs_set_global(LQJSRuntime *runtime, const char *name, const char *json, size_t length);

/* Serial calls only. The cancellation signal may be set from any thread. No OS / shell
 * module, filesystem, network, module loader, or asynchronous job pump is installed. */
LQJSResult lqjs_evaluate(LQJSRuntime *runtime, const char *script, size_t length,
                       uint64_t timeout_ns, size_t output_limit,
                       const LQJSCancellation *cancellation);
void lqjs_result_destroy(LQJSResult result);

#endif
