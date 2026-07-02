#ifndef ODYSSEY_H
#define ODYSSEY_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* odyssey_app_t;
typedef struct {
    void* store;
    void* type_id;
    uint64_t id;
} odyssey_entity_s;

typedef struct {
    odyssey_entity_s entity;
    bool valid;
} odyssey_entity_creation_s;

typedef odyssey_entity_s odyssey_workspace_t;
typedef odyssey_entity_creation_s odyssey_workspace_creation_t;

typedef void (*odyssey_wakeup_cb)(void*);

typedef struct {
    void* userdata;
    odyssey_wakeup_cb wakeup_cb;
} odyssey_options_s;

int odyssey_init(int argc, char **argv);
void odyssey_deinit(void);

odyssey_app_t odyssey_app_new(const odyssey_options_s* options);
void odyssey_app_free(odyssey_app_t);
void odyssey_app_flush(odyssey_app_t);

void odyssey_drop_entity(odyssey_entity_s entity);

odyssey_workspace_creation_t odyssey_workspace_new(odyssey_app_t app);

#ifdef __cplusplus
}
#endif

#endif
