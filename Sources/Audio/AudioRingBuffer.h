#ifndef REMOTE_VIBE_AUDIO_RING_BUFFER_H
#define REMOTE_VIBE_AUDIO_RING_BUFFER_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    kRVLogicalRingCapacity = 48000 * 4,
    kRVPhysicalRingGuard = 8192,
    kRVPhysicalRingCapacity = kRVLogicalRingCapacity + kRVPhysicalRingGuard
};

typedef struct {
    uint64_t readPos;
    uint64_t writePos;
    uint64_t renderedFrames;
    uint64_t fedFrames;
    uint64_t droppedFrames;
    uint64_t peakBuffered;
    uint32_t flags;
    float samples[kRVPhysicalRingCapacity];
} RVAudioRing;

static inline RVAudioRing * _Nullable RVAudioRingCreate(void) {
    return (RVAudioRing *)calloc(1, sizeof(RVAudioRing));
}

static inline void RVAudioRingDestroy(RVAudioRing * _Nullable ring) {
    free(ring);
}

static inline void RVAudioRingPrepare(RVAudioRing * _Nonnull ring) {
    __atomic_store_n(&ring->flags, 0u, __ATOMIC_RELEASE);
    __atomic_store_n(&ring->readPos, 0ull, __ATOMIC_RELEASE);
    __atomic_store_n(&ring->writePos, 0ull, __ATOMIC_RELEASE);
    __atomic_store_n(&ring->renderedFrames, 0ull, __ATOMIC_RELEASE);
    __atomic_store_n(&ring->fedFrames, 0ull, __ATOMIC_RELEASE);
    __atomic_store_n(&ring->droppedFrames, 0ull, __ATOMIC_RELEASE);
    __atomic_store_n(&ring->peakBuffered, 0ull, __ATOMIC_RELEASE);
    __atomic_store_n(&ring->flags, 1u, __ATOMIC_RELEASE);
}

static inline void RVAudioRingStartDraining(RVAudioRing * _Nonnull ring) {
    __atomic_fetch_or(&ring->flags, 2u, __ATOMIC_RELEASE);
}

static inline void RVAudioRingStop(RVAudioRing * _Nonnull ring) {
    __atomic_store_n(&ring->flags, 0u, __ATOMIC_RELEASE);
    uint64_t w = __atomic_load_n(&ring->writePos, __ATOMIC_ACQUIRE);
    __atomic_store_n(&ring->readPos, w, __ATOMIC_RELEASE);
}

static inline uint64_t RVAudioRingPendingFrames(RVAudioRing * _Nonnull ring) {
    if ((__atomic_load_n(&ring->flags, __ATOMIC_ACQUIRE) & 1u) == 0u) {
        return 0ull;
    }
    uint64_t w = __atomic_load_n(&ring->writePos, __ATOMIC_ACQUIRE);
    uint64_t r = __atomic_load_n(&ring->readPos, __ATOMIC_ACQUIRE);
    if (w <= r) {
        return 0ull;
    }
    uint64_t diff = w - r;
    return diff > (uint64_t)kRVLogicalRingCapacity ? (uint64_t)kRVLogicalRingCapacity : diff;
}

static inline uint64_t RVAudioRingRenderedFrames(RVAudioRing * _Nonnull ring) {
    return __atomic_load_n(&ring->renderedFrames, __ATOMIC_ACQUIRE);
}

static inline uint64_t RVAudioRingFedFrames(RVAudioRing * _Nonnull ring) {
    return __atomic_load_n(&ring->fedFrames, __ATOMIC_ACQUIRE);
}

static inline uint64_t RVAudioRingDroppedFrames(RVAudioRing * _Nonnull ring) {
    return __atomic_load_n(&ring->droppedFrames, __ATOMIC_ACQUIRE);
}

static inline uint64_t RVAudioRingPeakBuffered(RVAudioRing * _Nonnull ring) {
    return __atomic_load_n(&ring->peakBuffered, __ATOMIC_ACQUIRE);
}

static inline void RVAudioRingWrite(RVAudioRing * _Nonnull ring, const float * _Nonnull frames, uint32_t count) {
    if (count == 0u || (__atomic_load_n(&ring->flags, __ATOMIC_ACQUIRE) & 1u) == 0u) {
        return;
    }
    uint64_t w = __atomic_load_n(&ring->writePos, __ATOMIC_RELAXED);
    for (uint32_t i = 0u; i < count; i++) {
        uint32_t slot = (uint32_t)((w + (uint64_t)i) % (uint64_t)kRVPhysicalRingCapacity);
        ring->samples[slot] = frames[i];
    }
    uint64_t wNew = w + (uint64_t)count;
    __atomic_store_n(&ring->writePos, wNew, __ATOMIC_RELEASE);
    __atomic_fetch_add(&ring->fedFrames, (uint64_t)count, __ATOMIC_RELAXED);

    uint64_t cap = (uint64_t)kRVLogicalRingCapacity;
    uint64_t r = __atomic_load_n(&ring->readPos, __ATOMIC_ACQUIRE);
    if (wNew > r && (wNew - r) > cap) {
        uint64_t minRead = wNew - cap;
        while (r < minRead) {
            uint64_t prev = r;
            if (__atomic_compare_exchange_n(&ring->readPos, &r, minRead, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
                __atomic_fetch_add(&ring->droppedFrames, minRead - prev, __ATOMIC_RELAXED);
                r = minRead;
                break;
            }
        }
    }
    uint64_t buffered = wNew > r ? (wNew - r) : 0ull;
    if (buffered > cap) {
        buffered = cap;
    }
    uint64_t peak = __atomic_load_n(&ring->peakBuffered, __ATOMIC_RELAXED);
    while (buffered > peak) {
        if (__atomic_compare_exchange_n(&ring->peakBuffered, &peak, buffered, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            break;
        }
    }
}

static inline uint32_t RVAudioRingRender(RVAudioRing * _Nonnull ring, float * _Nonnull outData, uint32_t frames) {
    if (frames == 0u) {
        return 0u;
    }
    memset(outData, 0, (size_t)frames * sizeof(float));
    if ((__atomic_load_n(&ring->flags, __ATOMIC_ACQUIRE) & 3u) != 3u) {
        return 0u;
    }
    for (int attempt = 0; attempt < 3; attempt++) {
        uint64_t r = __atomic_load_n(&ring->readPos, __ATOMIC_ACQUIRE);
        uint64_t w = __atomic_load_n(&ring->writePos, __ATOMIC_ACQUIRE);
        if (w <= r) {
            return 0u;
        }
        uint64_t available = w - r;
        if (available > (uint64_t)kRVLogicalRingCapacity) {
            available = (uint64_t)kRVLogicalRingCapacity;
        }
        uint32_t take = frames < (uint32_t)available ? frames : (uint32_t)available;
        for (uint32_t i = 0u; i < take; i++) {
            uint32_t slot = (uint32_t)((r + (uint64_t)i) % (uint64_t)kRVPhysicalRingCapacity);
            outData[i] = ring->samples[slot];
        }
        if (__atomic_compare_exchange_n(&ring->readPos, &r, r + (uint64_t)take, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
            __atomic_fetch_add(&ring->renderedFrames, (uint64_t)take, __ATOMIC_RELAXED);
            return take;
        }
        memset(outData, 0, (size_t)take * sizeof(float));
    }
    return 0u;
}

#endif
