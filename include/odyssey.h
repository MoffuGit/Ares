#ifndef ODYSSEY_H
#define ODYSSEY_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/////////////////
//~ Common Types

typedef struct {
    const uint8_t* ptr;
    size_t len;
} odyssey_string_s;

/////////////////
//~ General Types

int odyssey_init(int argc, char **argv);
void odyssey_deinit(void);

/////////////
//~ App Types

typedef void (*odyssey_runtime_cb)(void*);

typedef  struct {
    void* userdata;
    odyssey_runtime_cb event_callback;
} odyssey_runtime_s;

typedef void* odyssey_app_t;

odyssey_app_t odyssey_app_new(const odyssey_runtime_s*);
void odyssey_app_run(odyssey_app_t);
void odyssey_app_free(odyssey_app_t);

#ifdef __cplusplus
}
#endif

#endif
