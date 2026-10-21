#include "include/espeak-ng/speak_lib.h"

/*
 * Dummy function that references key espeak-ng symbols.
 * Called from Swift to prevent the linker from stripping
 * these symbols when building a static framework.
 */
void espeak_ng_force_link(void) {
    volatile void *p;
    p = (void *)espeak_Initialize;
    p = (void *)espeak_SetVoiceByName;
    p = (void *)espeak_TextToPhonemes;
    p = (void *)espeak_Terminate;
    p = (void *)espeak_Info;
    (void)p;
}
