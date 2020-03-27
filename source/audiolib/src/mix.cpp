/*
 Copyright (C) 2009 Jonathon Fowler <jf@jonof.id.au>

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 See the GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

 */

#include "_multivc.h"

template uint32_t MV_MixMono<uint8_t, int16_t>(struct VoiceNode * const voice, uint32_t length);
template uint32_t MV_MixStereo<uint8_t, int16_t>(struct VoiceNode * const voice, uint32_t length);
template uint32_t MV_MixMono<int16_t, int16_t>(struct VoiceNode * const voice, uint32_t length);
template uint32_t MV_MixStereo<int16_t, int16_t>(struct VoiceNode * const voice, uint32_t length);
template void MV_Reverb<int16_t>(char const *src, char * const dest, const fix16_t volume, int count);

/*
 length = count of samples to mix
 position = offset of starting sample in source
 rate = resampling increment
 volume = direct volume adjustment, 1.0 = no change
 */

// mono source, mono output
template <typename S, typename D>
uint32_t MV_MixMono(struct VoiceNode * const voice, uint32_t length)
{
    auto const * __restrict source = (S const *)voice->sound;
    auto       * __restrict dest   = (D *)MV_MixDestination;

    uint32_t       position = voice->position;
    uint32_t const rate     = voice->RateScale;
    fix16_t const  volume   = fix16_fast_trunc_mul(voice->volume, MV_GlobalVolume);

    do
    {
        auto const isample0 = CONVERT_LE_SAMPLE_TO_SIGNED<S, D>(source[position >> 16]);

        position += rate;

        *dest = MIX_SAMPLES<D>(SCALE_SAMPLE(isample0, fix16_fast_trunc_mul(volume, voice->LeftVolume)), *dest);
        dest++;

        voice->LeftVolume = SMOOTH_VOLUME(voice->LeftVolume, voice->LeftVolumeDest);
    }
    while (--length);

    MV_MixDestination = (char *)dest;

    return position;
}

// mono source, stereo output
template <typename S, typename D>
uint32_t MV_MixStereo(struct VoiceNode * const voice, uint32_t length)
{
    auto const * __restrict source = (S const *)voice->sound;
    auto       * __restrict dest   = (D *)MV_MixDestination;

    uint32_t       position = voice->position;
    uint32_t const rate     = voice->RateScale;
    fix16_t  const volume   = fix16_fast_trunc_mul(voice->volume, MV_GlobalVolume);

#ifdef __arm__
    /* ARM optimised mixing for 16bit stereo destination, suitable for any 32bit
       ARM. Note: Currently doesn't implement smooth volume changes. */
    if ((sizeof(D) == 2) && (MV_RightChannelOffset == 2))
    {
        int32_t leftvol = fix16_min(fix16_fast_trunc_mul(volume, voice->LeftVolume), fix16_one);
        int32_t rightvol = fix16_min(fix16_fast_trunc_mul(volume, voice->RightVolume), fix16_one);
        int32_t * __restrict dest32 = (int32_t *) dest;

        do
        {
            int const isample0 = CONVERT_LE_SAMPLE_TO_SIGNED<S, D>(source[position >> 16]);

            position += rate;

            int32_t mix = *dest32;
            int32_t left,right;
            uint32_t magic = 0x80000000;

            int32_t const sample0L = isample0*leftvol;
            int32_t const sample0R = isample0*rightvol;

            /* 32bit saturating add: left = sample0L + (mix<<16) */
            asm("adds %0,%1,%2,lsl #16\n\tsbcvs %0,%3,#0" : "=r" (left) : "r" (sample0L), "r" (mix), "r" (magic) : "cc");

            /* right = sample0R + mix */
            asm("adds %0,%1,%2\n\tsbcvs %0,%3,#0" : "=r" (right) : "r" (sample0R), "r" (mix), "r" (magic) : "cc");

            *dest32++ = (((uint32_t)left)>>16) | (right & 0xffff0000);
        }
        while (--length);

        voice->LeftVolume = voice->LeftVolumeDest;
        voice->RightVolume = voice->RightVolumeDest;

        MV_MixDestination = (char *) dest32;

        return position;
    }
#endif

    do
    {
        auto const isample0 = CONVERT_LE_SAMPLE_TO_SIGNED<S, D>(source[position >> 16]);

        position += rate;

        *dest = MIX_SAMPLES<D>(SCALE_SAMPLE(isample0, fix16_fast_trunc_mul(volume, voice->LeftVolume)), *dest);
        *(dest + (MV_RightChannelOffset / sizeof(*dest)))
            = MIX_SAMPLES<D>(SCALE_SAMPLE(isample0, fix16_fast_trunc_mul(volume, voice->RightVolume)), *(dest + (MV_RightChannelOffset / sizeof(*dest))));
        dest += 2;

        voice->LeftVolume = SMOOTH_VOLUME(voice->LeftVolume, voice->LeftVolumeDest);
        voice->RightVolume = SMOOTH_VOLUME(voice->RightVolume, voice->RightVolumeDest);
    }
    while (--length);

    MV_MixDestination = (char *)dest;

    return position;
}

template <typename T>
void MV_Reverb(char const *src, char * const dest, const fix16_t volume, int count)
{
    auto input  = (T const *)src;
    auto output = (T *)dest;

    do
    {
        auto const isample0 = CONVERT_SAMPLE_TO_SIGNED<T>(*input++);
        *output++ = CONVERT_SAMPLE_FROM_SIGNED<T>(SCALE_SAMPLE(isample0, volume));
    }
    while (--count > 0);
}
