#ifndef ODYSSEY_H
#define ODYSSEY_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int odyssey_init(int argc, char **argv);
void odyssey_deinit(void);

/////////////
//~ App Types

typedef void* odyssey_app_t;
typedef void (*odyssey_wakeup_cb)(void*);

typedef struct {
    void* userdata;
    odyssey_wakeup_cb wakeup_cb;
} odyssey_options_s;

odyssey_app_t odyssey_app_new(const odyssey_options_s* options);
void odyssey_app_free(odyssey_app_t);
void odyssey_app_flush(odyssey_app_t);

//////////////////
//~ Entities Types

typedef struct {
    void* store;
    void* type_id;
    uint64_t id;
} odyssey_entity_s;

typedef struct {
    odyssey_entity_s entity;
    bool valid;
} odyssey_entity_creation_s;

typedef struct {
    void* ptr;
    uint64_t key;
    uint32_t id;
} odyssey_observer_s;

typedef odyssey_entity_creation_s odyssey_workspace_creation_t;
void odyssey_drop_entity(odyssey_entity_s entity);

///////////////////
//~ Observers Types

typedef struct {
    odyssey_observer_s observer;
    bool valid;
} odyssey_observer_creation_s;

///////////////////
//~ Workspace Types

typedef struct {
    size_t count;
} odyssey_workspace_s;

typedef odyssey_observer_creation_s odyssey_workspace_observer_creation_t;

typedef bool (*odyssey_workspace_observe_cb)(void*, odyssey_workspace_s);

odyssey_workspace_creation_t odyssey_workspace_new(odyssey_app_t app);

void odyssey_workspace_set(odyssey_app_t app, odyssey_entity_s entity, odyssey_workspace_s* workspace);

odyssey_workspace_observer_creation_t odyssey_workspace_observe(
    odyssey_app_t app,
    odyssey_entity_s workspace,
    odyssey_workspace_observe_cb callback,
    void* userdata
);
void odyssey_workspace_unobserve(odyssey_observer_s observer);

#ifdef __cplusplus
}
#endif

#endif
