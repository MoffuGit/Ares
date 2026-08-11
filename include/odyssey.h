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

typedef struct {
    __uint128_t value;
    bool valid;
} odyssey_maybe_u128_s;

/////////////////
//~ General Types

int odyssey_init(int argc, char **argv);
void odyssey_deinit(void);

int odyssey_db_start(void);
void odyssey_db_stop(void);

/////////////
//~ App Types

typedef void* odyssey_app_t;

odyssey_app_t odyssey_app_new();
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
//~ Workspace Types

typedef struct {
    odyssey_string_s* ptr;
    size_t len;
} odyssey_workspace_paths_s;

//@@ SerializedWorkspaces

typedef struct {
    double x;
    double y;
    double width;
    double height;
} odyssey_workspace_window_bounds_s;

typedef struct {
    odyssey_workspace_window_bounds_s value;
    bool valid;
} odyssey_maybe_workspace_window_bounds_s;

typedef struct {
    double width;
    bool valid;
} odyssey_maybe_workspace_dock_width_s;

typedef struct {
    odyssey_workspace_paths_s paths;
    odyssey_maybe_u128_s session;
    odyssey_maybe_workspace_window_bounds_s window;
    odyssey_maybe_workspace_dock_width_s left_dock;
    odyssey_maybe_workspace_dock_width_s right_dock;
    int64_t timestamp;
    int64_t id;
} odyssey_serialized_workspace_s;

typedef struct {
    odyssey_serialized_workspace_s* ptr;
    size_t len;
} odyssey_workspace_list_s;

odyssey_workspace_list_s odyssey_workspace_get_all_metadata_and_validate(void);
odyssey_workspace_list_s odyssey_workspace_get_by_session(odyssey_entity_s session);
void odyssey_workspace_list_free(odyssey_workspace_list_s list);
int odyssey_workspace_delete_by_id(int64_t id);

typedef odyssey_maybe_entity_s odyssey_workspace_creation_t;
odyssey_workspace_creation_t odyssey_workspace_new(odyssey_app_t app, odyssey_entity_s session, odyssey_workspace_paths_s paths);
void odyssey_workspace_mark_for_restoration(odyssey_entity_s workspace);
void odyssey_workspace_set_bounds(
    odyssey_entity_s workspace,
    odyssey_maybe_workspace_window_bounds_s bounds,
    odyssey_maybe_workspace_dock_width_s left_dock,
    odyssey_maybe_workspace_dock_width_s right_dock
);
int64_t odyssey_workspace_get_id(odyssey_entity_s workspace);

/////////////////
//~ Session Types

typedef odyssey_maybe_entity_s odyssey_session_creation_t;
odyssey_session_creation_t odyssey_session_new(odyssey_app_t app);


#ifdef __cplusplus
}
#endif

#endif
