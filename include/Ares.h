#ifndef ARES_H
#define ARES_H

#include <stdint.h>
#include <stddef.h>

typedef void (*AresCallback)(uint8_t event, const uint8_t *ptr, size_t dataLen);

typedef struct {
    uint64_t scheme;
    uintptr_t light_theme_ptr;
    size_t light_theme_len;
    uintptr_t dark_theme_ptr;
    size_t dark_theme_len;
} ExternSettings;

typedef struct {
    uint64_t name;
    uint64_t len;
    uint8_t fg[4];
    uint8_t bg[4];
    uint8_t primaryBg[4];
    uint8_t primaryFg[4];
    uint8_t mutedBg[4];
    uint8_t mutedFg[4];
    uint8_t scrollThumb[4];
    uint8_t scrollTrack[4];
    uint8_t border[4];
} ExternTheme;

void initState(AresCallback callback);
void deinitState(void);
void drainEvents(void);

void *createSettings(void);
void destroySettings(void *settings);
void loadSettings(void *settings, const uint8_t *path, uint64_t len, void *monitor);
void readSettings(void *settings, ExternSettings *ext);
void readTheme(void *settings, ExternTheme *ext);

void *createIo(void);
void destroyIo(void *io);

void *createMonitor(void);
void destroyMonitor(void *monitor);

#endif
