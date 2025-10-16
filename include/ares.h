#ifndef ZIG_COUNTER_H
#define ZIG_COUNTER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

void zig_increment_counter(void);
void zig_decrement_counter(void);
int32_t zig_get_counter(void);
void zig_init_counter(void);
void zig_deinit_counter(void);

void zig_process_file_path(const char* path);

#ifdef __cplusplus
}
#endif

#endif // ZIG_COUNTER_H
