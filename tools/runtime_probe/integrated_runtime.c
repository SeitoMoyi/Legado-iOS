#include "LegadoQuickJS.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

static char *nested(void *opaque, const char *action, const char *arguments) {
    (void)action; (void)arguments;
    LQJSResult value = lqjs_evaluate(opaque, "1+1", 3, 100000000, 1024, NULL);
    int good = value.status == LQJS_OK && value.json && !strcmp(value.json, "2");
    lqjs_result_destroy(value);
    return strdup(good ? "{\"value\":2}" : "{\"error\":\"Nested call failed\"}");
}

static void *cancel_later(void *opaque) {
    usleep(25000);
    lqjs_cancellation_cancel(opaque);
    return NULL;
}

int main(void) {
    for (int i = 0; i < 50; i++) {
        LQJSRuntime *runtime = lqjs_create(16 * 1024 * 1024, 256 * 1024);
        if (!runtime) return 1;
        lqjs_set_host(runtime, nested, NULL, runtime);
        const char *script = "__legadoHost('nested');while(true){}";
        LQJSResult result = lqjs_evaluate(runtime, script, strlen(script), 5000000, 1024, NULL);
        if (result.status != LQJS_TIMEOUT) return 2;
        lqjs_result_destroy(result);
        result = lqjs_evaluate(runtime, "1+1", 3, 100000000, 1024, NULL);
        if (result.status != LQJS_OK || !result.json || strcmp(result.json, "2")) return 3;
        lqjs_result_destroy(result);
        lqjs_destroy(runtime);
    }
    LQJSRuntime *runtime = lqjs_create(16 * 1024 * 1024, 256 * 1024);
    LQJSCancellation *cancellation = lqjs_cancellation_create();
    if (!runtime || !cancellation) return 4;
    pthread_t thread;
    if (pthread_create(&thread, NULL, cancel_later, cancellation)) return 5;
    const char *script = "while(true){}";
    LQJSResult result = lqjs_evaluate(runtime, script, strlen(script), 2000000000, 1024, cancellation);
    pthread_join(thread, NULL);
    if (result.status != LQJS_CANCELLED) return 6;
    lqjs_result_destroy(result);
    lqjs_cancellation_destroy(cancellation);
    lqjs_destroy(runtime);
    puts("PASS: 50 nested-host timeout/recovery cycles; cross-thread cancellation; all runtimes freed.");
    return 0;
}
