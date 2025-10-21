#ifndef ARES_H
#define ARES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef void* ares_app_t;
typedef void* ares_surface_t;

ares_app_t ares_app_new();
ares_surface_t ares_surface_new(ares_app_t);
void ares_app_free(ares_app_t);

void ares_surface_free(ares_surface_t);

int ares_init(uintptr_t, char**);

#ifdef __cplusplus
}
#endif

#endif // ARES_H
