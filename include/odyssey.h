#ifndef ODYSSEY_H
#define ODYSSEY_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/////////////////
//~ General Types

int odyssey_init(int argc, char **argv);
void odyssey_deinit(void);

int odyssey_db_start(void);
void odyssey_db_stop(void);

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
} odyssey_maybe_entity_s;

void odyssey_drop_entity(odyssey_entity_s entity);

///////////////////
//~ Observers Types

typedef struct {
    void* ptr;
    uint64_t key;
    uint32_t id;
} odyssey_observer_s;

typedef struct {
    odyssey_observer_s observer;
    bool valid;
} odyssey_maybe_observer_s;

void odyssey_remove_observer(odyssey_observer_s observer);

///////////////////
//~ Workspace Types

typedef odyssey_maybe_entity_s odyssey_workspace_creation_t;
odyssey_workspace_creation_t odyssey_workspace_new(odyssey_app_t app);

/////////////////
//~ Session Types

typedef odyssey_maybe_entity_s odyssey_session_creation_t;
odyssey_session_creation_t odyssey_session_new(odyssey_app_t app);


#ifdef __cplusplus
}
#endif

#endif
