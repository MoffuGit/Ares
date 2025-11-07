#ifndef ARES_H
#define ARES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef void* ares_app_t;
typedef void* ares_surface_t;

typedef struct {
  void* nsview;
} ares_platform_macos_s;

typedef struct {
  ares_platform_macos_s macos;
} ares_platform_u;

typedef struct {
  ares_platform_u platform;
  double scale_factor;
} ares_surface_config_s;

ares_app_t ares_app_new();
ares_surface_t ares_surface_new(ares_app_t, ares_surface_config_s);
void ares_app_free(ares_app_t);

void ares_surface_free(ares_surface_t);

void ares_surface_set_size(ares_surface_t, uint32_t, uint32_t);
void ares_surface_set_content_scale(ares_surface_t, double, double);

void ares_surface_set_file(ares_surface_t, const char*);

int ares_init(uintptr_t, char**);

#ifdef __cplusplus
}
#endif

#endif // ARES_H
