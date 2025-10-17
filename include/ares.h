#ifndef ARES_H
#define ARES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

int ares_init(uintptr_t, char**);

void zig_increment_counter(void);
void zig_decrement_counter(void);
int32_t zig_get_counter(void);
void zig_init_counter(void);
void zig_deinit_counter(void);

void zig_process_file_path(const char* path);

#ifdef __cplusplus
}
#endif

#endif // ARES_H
