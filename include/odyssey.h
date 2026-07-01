#ifndef ODYSSEY_H
#define ODYSSEY_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void* odyssey_app_t;
typedef void* odyssey_workspace_t;

typedef void (*odyssey_wakeup_cb)(void*);

typedef struct {
    void* userdata;
    odyssey_wakeup_cb wakeup_cb;
} odyssey_config_s;

int odyssey_init(int argc, char **argv);
void odyssey_deinit(void);

odyssey_app_t odyssey_app_new(void);
void odyssey_app_free(odyssey_app_t);

#ifdef __cplusplus
}
#endif

#endif
