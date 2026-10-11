// Run the audio plug-in as ordinary code; no HAL installation or system writes.
#include <assert.h>
#include <math.h>
#define kDriver_Name "RemoteVibeMic"
#define kPlugIn_BundleID "local.ben.RemoteVibeMic"
#define kDevice_Name "Chromecast Mic"
#define kHas_Driver_Name_Format false
#define kNumber_Of_Channels 1
#define kSampleRates 48000
#define kEnableVolumeControl false
#define kCanBeDefaultSystemDevice false
#include "../Driver/RemoteVibeMic.c"

static UInt32 property(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = {selector, scope, kAudioObjectPropertyElementMain};
    UInt32 result = 999, size = sizeof(result);
    assert(BlackHole_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
                                    &address, 0, NULL, sizeof(result), &size, &result) == noErr);
    return result;
}

static void roundtrip(UInt64 position, UInt32 frames) {
    float *written = calloc(frames, sizeof(float)), *read = calloc(frames, sizeof(float));
    for (UInt32 i = 0; i < frames; i++) written[i] = sinf((float)i * 0.137f) * 0.4f;
    AudioServerPlugInIOCycleInfo cycle = {0};
    cycle.mOutputTime.mSampleTime = position;
    cycle.mInputTime.mSampleTime = position;
    assert(BlackHole_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Output,
        1, kAudioServerPlugInIOOperationWriteMix, frames, &cycle, written, NULL) == noErr);
    assert(BlackHole_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input,
        2, kAudioServerPlugInIOOperationReadInput, frames, &cycle, read, NULL) == noErr);
    assert(memcmp(written, read, frames * sizeof(float)) == 0);
    // Once the writer stops, a later reader must receive silence, not old audio.
    cycle.mInputTime.mSampleTime = position + frames * 2;
    assert(BlackHole_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Input,
        2, kAudioServerPlugInIOOperationReadInput, frames, &cycle, read, NULL) == noErr);
    for (UInt32 i = 0; i < frames; i++) assert(read[i] == 0);
    free(written); free(read);
}

int main(void) {
    assert(property(kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeInput) == 1);
    assert(property(kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput) == 0);
    assert(property(kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, kAudioObjectPropertyScopeOutput) == 0);
    assert(BlackHole_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
    assert(BlackHole_StartIO(gAudioServerPlugInDriverRef, kObjectID_Device, 2) == noErr);
    roundtrip(1000, 480);
    roundtrip(kRing_Buffer_Frame_Size - 100, 512); // wrap across the ring boundary
    roundtrip(kRing_Buffer_Frame_Size * 3 + 120, 2048);
    assert(BlackHole_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device, 1) == noErr);
    assert(gRingBuffer != NULL);
    assert(BlackHole_StopIO(gAudioServerPlugInDriverRef, kObjectID_Device, 2) == noErr);
    assert(gRingBuffer == NULL);
    puts("PASS: audio loopback, ring wrap, silence after writer stops, two-client cleanup, microphone-only default.");
    return 0;
}
