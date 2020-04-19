/*
 * softsurface.cpp
 *  An 8-bit rendering surface that can quickly upscale and blit 8-bit paletted buffers to an external 32-bit buffer.
 *
 * Copyright © 2018, Alex Dawson. All rights reserved.
 */

#include "softsurface.h"

#include "pragmas.h"
#include "build.h"

// On ARM it's quicker to calculate the position directly
#ifndef __arm__
#define SCANPOS_LUT
#endif

static int bufferSize;
static uint8_t* buffer;
static vec2_t bufferRes;

static vec2_t destBufferRes;

static uint32_t xScale16;
static uint32_t yScale16;
static uint32_t recXScale16;

static uint32_t pPal[256];

#ifdef SCANPOS_LUT
// lookup table to find the source position within a scanline
static uint16_t* scanPosLookupTable;
#endif

#ifndef SCANPOS_LUT
uint32_t *softsurface_get_pal()
{
    return pPal;
}
#endif

template <uint32_t multiple>
static uint32_t roundUp(uint32_t num)
{
    return (num+multiple-1)/multiple * multiple;
}

static uint32_t countTrailingZeros(uint32_t u)
{
#if (defined __GNUC__  && __GNUC__>=3) || defined __clang__
    return __builtin_ctz(u);
#elif defined _MSC_VER
    DWORD result;
    _BitScanForward(&result, u);
    return result;
#else
    uint32_t last = u;
    for (; u != 0; last = u, u >>= 1);
    return last;
#endif
}

bool softsurface_initialize(vec2_t bufferResolution,
                            vec2_t destBufferResolution)
{
    if (buffer)
        softsurface_destroy();

    bufferRes = bufferResolution;
    destBufferRes = destBufferResolution;

    xScale16 = divscale16(destBufferRes.x, bufferRes.x);
    yScale16 = divscale16(destBufferRes.y, bufferRes.y);
    recXScale16 = divscale16(bufferRes.x, destBufferRes.x);

    // allocate one continuous block of memory large enough to hold the buffer, the palette,
    // and the scanPosLookupTable while maintaining alignment for each
    uint32_t newBufferSize = roundUp<16>(bufferRes.x * bufferRes.y);
    zpl_virtual_memory vm = Xvm_alloc(0, newBufferSize
#ifdef SCANPOS_LUT
     + sizeof(uint16_t) * destBufferRes.x
#endif
     );

    bufferSize = vm.size;
    buffer     = (uint8_t *)vm.data;

#ifdef SCANPOS_LUT
    scanPosLookupTable = (uint16_t *)(buffer + newBufferSize);

    // calculate the scanPosLookupTable for horizontal scaling
    uint32_t incr = 0;
    for (int32_t i = 0; i < destBufferRes.x; ++i)
    {
        scanPosLookupTable[i] = incr >> 16;
        incr += recXScale16;
    }
#endif

    return true;
}

void softsurface_destroy()
{
    if (!buffer)
        return;

    Xvm_free(zpl_vm(buffer, bufferSize));
    buffer = nullptr;

#ifdef SCANPOS_LUT
    scanPosLookupTable = 0;
#endif

    xScale16 = 0;
    yScale16 = 0;
    recXScale16 = 0;

    bufferRes = {};
    destBufferRes = {};
}

void softsurface_setPalette(void* pPalette,
                            uint32_t destRedMask,
                            uint32_t destGreenMask,
                            uint32_t destBlueMask)
{
    if (!buffer)
        return;
    if (!pPalette)
        return;

    uint32_t destRedShift = countTrailingZeros(destRedMask);
    uint32_t destRedLoss = 8 - countTrailingZeros((destRedMask>>destRedShift)+1);
    uint32_t destGreenShift = countTrailingZeros(destGreenMask);
    uint32_t destGreenLoss = 8 - countTrailingZeros((destGreenMask>>destGreenShift)+1);
    uint32_t destBlueShift = countTrailingZeros(destBlueMask);
    uint32_t destBlueLoss = 8 - countTrailingZeros((destBlueMask>>destBlueShift)+1);

    uint8_t* pUI8Palette = (uint8_t*) pPalette;
    for (int i = 0; i < 256; ++i)
    {
        pPal[i] = ((pUI8Palette[sizeof(uint32_t)*i] >> destRedLoss << destRedShift) & destRedMask) |
                  ((pUI8Palette[sizeof(uint32_t)*i+1] >> destGreenLoss << destGreenShift) & destGreenMask) |
                  ((pUI8Palette[sizeof(uint32_t)*i+2] >> destBlueLoss << destBlueShift) & destBlueMask);
    }
}

uint8_t* softsurface_getBuffer()
{
    return buffer;
}

vec2_t softsurface_getBufferResolution()
{
    return bufferRes;
}

vec2_t softsurface_getDestinationBufferResolution()
{
    return destBufferRes;
}

#ifdef SCANPOS_LUT
#define BLIT(x) pDst[x] = *((UINTTYPE*)(pPal+pSrc[pScanPos[x]]))
#else
#define BLIT(x) pDst[x] = pal[pSrc[scanPos>>16]]; scanPos += recXScale16
#endif
#define BLIT2(x) BLIT(x); BLIT(x+1)
#if !defined(SCANPOS_LUT) && defined(__riscos__)
// GCC does an awful job at optimising this code, refusing to interleave pixel processing. Interleave it manually.
#define BLIT4(x) do { \
uint32_t t0,t1,t2,t3; \
t0 = pSrc[scanPos>>16]; scanPos += recXScale16; \
t1 = pSrc[scanPos>>16]; scanPos += recXScale16; \
t2 = pSrc[scanPos>>16]; scanPos += recXScale16; \
t3 = pSrc[scanPos>>16]; scanPos += recXScale16; \
t0 = pal[t0]; t1 = pal[t1]; t2 = pal[t2]; t3 = pal[t3]; \
pDst[x] = t0; pDst[x+1] = t1; pDst[x+2] = t2; pDst[x+3] = t3; \
} while(0)
#else
#define BLIT4(x) BLIT2(x); BLIT2(x+2)
#endif
#define BLIT8(x) BLIT4(x); BLIT4(x+4)
#define BLIT16(x) BLIT8(x); BLIT8(x+8)
#define BLIT32(x) BLIT16(x); BLIT16(x+16)
#define BLIT64(x) BLIT32(x); BLIT32(x+32)
template <typename UINTTYPE>
void softsurface_blitBufferInternal(UINTTYPE* destBuffer)
{
    const uint8_t* __restrict pSrc = buffer;
    UINTTYPE* __restrict pDst = destBuffer;
    const UINTTYPE* const pEnd = destBuffer+destBufferRes.x*mulscale16(yScale16, bufferRes.y);
    uint32_t remainder = 0;
#ifndef SCANPOS_LUT
    // Use a function to get the palette address - so that GCC uses the address directly, instead of generating slower code which (for every pixel!) calculates the address relative to another pointer it already has (sigh)
    const uint32_t* __restrict pal = softsurface_get_pal();
#endif
    while (pDst < pEnd)
    {
#ifdef SCANPOS_LUT
        uint16_t* __restrict pScanPos = scanPosLookupTable;
#else
        uint32_t scanPos = 0;
#endif
        UINTTYPE* const pScanEnd = pDst+destBufferRes.x;
        while (pDst <= pScanEnd-64)
        {
            BLIT64(0);
            pDst += 64;
#ifdef SCANPOS_LUT
            pScanPos += 64;
#endif
        }
        while (pDst < pScanEnd)
        {
            BLIT(0);
            ++pDst;
#ifdef SCANPOS_LUT
            ++pScanPos;
#endif
        }
        pSrc += bufferRes.x;

        static const uint32_t MASK16 = (1<<16)-1;
        uint32_t linesCopied = 1;
        uint32_t linesToCopy = yScale16+remainder;
        remainder = linesToCopy & MASK16;
        linesToCopy = (linesToCopy >> 16)-1;
        const UINTTYPE* const __restrict pScanLineSrc = pDst-destBufferRes.x;
        while (linesToCopy)
        {
            uint32_t lines = min(linesCopied, linesToCopy);
            memcpy(pDst, pScanLineSrc, sizeof(UINTTYPE)*lines*destBufferRes.x);
            pDst += lines*destBufferRes.x;
            linesToCopy -= lines;
        }
    }
}

#ifdef SCANPOS_LUT
#define NPBLIT(x) pDst[x] = pSrc[pScanPos[x]]
#else
#define NPBLIT(x) pDst[x] = pSrc[scanPos>>16]; scanPos += recXScale16
#endif
#define NPBLIT2(x) NPBLIT(x); NPBLIT(x+1)
#if !defined(SCANPOS_LUT) && defined(__riscos__)
// GCC does an awful job at optimising this code, refusing to interleave pixel processing. Interleave it manually.
#define NPBLIT4(x) do { \
uint32_t t0,t1,t2,t3; \
t0 = pSrc[scanPos>>16]; scanPos += recXScale16; \
t1 = pSrc[scanPos>>16]; scanPos += recXScale16; \
t2 = pSrc[scanPos>>16]; scanPos += recXScale16; \
t3 = pSrc[scanPos>>16]; scanPos += recXScale16; \
pDst[x] = t0; pDst[x+1] = t1; pDst[x+2] = t2; pDst[x+3] = t3; \
} while(0)
#else
#define NPBLIT4(x) NPBLIT2(x); NPBLIT2(x+2)
#endif
#define NPBLIT8(x) NPBLIT4(x); NPBLIT4(x+4)
#define NPBLIT16(x) NPBLIT8(x); NPBLIT8(x+8)
#define NPBLIT32(x) NPBLIT16(x); NPBLIT16(x+16)
#define NPBLIT64(x) NPBLIT32(x); NPBLIT32(x+32)
template <typename UINTTYPE>
void softsurface_blitBufferInternalNoPal(UINTTYPE* destBuffer)
{
    const uint8_t* __restrict pSrc = buffer;
    UINTTYPE* __restrict pDst = destBuffer;
    const UINTTYPE* const pEnd = destBuffer+destBufferRes.x*mulscale16(yScale16, bufferRes.y);
    uint32_t remainder = 0;
    while (pDst < pEnd)
    {
        if (xScale16 == 65536)
        {
            memcpy(pDst, pSrc, sizeof(UINTTYPE)*destBufferRes.x);
            pDst += bufferRes.x;
        }
        else
        {
#ifdef SCANPOS_LUT
            uint16_t* __restrict pScanPos = scanPosLookupTable;
#else
            uint32_t scanPos = 0;
#endif
            UINTTYPE* const pScanEnd = pDst+destBufferRes.x;
            while (pDst <= pScanEnd-64)
            {
                NPBLIT64(0);
                pDst += 64;
#ifdef SCANPOS_LUT
                pScanPos += 64;
#endif
            }
            while (pDst < pScanEnd)
            {
                NPBLIT(0);
                ++pDst;
#ifdef SCANPOS_LUT
                ++pScanPos;
#endif
            }
        }
        pSrc += bufferRes.x;

        static const uint32_t MASK16 = (1<<16)-1;
        uint32_t linesCopied = 1;
        uint32_t linesToCopy = yScale16+remainder;
        remainder = linesToCopy & MASK16;
        linesToCopy = (linesToCopy >> 16)-1;
        const UINTTYPE* const __restrict pScanLineSrc = pDst-destBufferRes.x;
        while (linesToCopy)
        {
            uint32_t lines = min(linesCopied, linesToCopy);
            memcpy(pDst, pScanLineSrc, sizeof(UINTTYPE)*lines*destBufferRes.x);
            pDst += lines*destBufferRes.x;
            linesToCopy -= lines;
        }
    }
}

void softsurface_blitBuffer(uint32_t* destBuffer,
                            uint32_t destBytesPerPixel)
{
    if (!buffer)
        return;
    if (!destBuffer)
        return;

    switch (destBytesPerPixel)
    {
    case 1:
        softsurface_blitBufferInternalNoPal<uint8_t>((uint8_t*) destBuffer);
        break;
    case 2:
        softsurface_blitBufferInternal<uint16_t>((uint16_t*) destBuffer);
        break;
    case 4:
        softsurface_blitBufferInternal<uint32_t>(destBuffer);
        break;
    default:
        return;
    }
}
