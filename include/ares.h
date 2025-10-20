#ifndef ARES_H
#define ARES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef void* ares_app_t;

ares_app_t ares_app_new();
void ares_app_free(ares_app_t);
int ares_init(uintptr_t, char**);

#ifdef __cplusplus
}
#endif

#endif // ARES_H
