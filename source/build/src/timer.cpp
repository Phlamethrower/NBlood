// Build engine timer stuff

#include "timer.h"

#include "build.h"
#include "build_cpuid.h"
#include "compat.h"
#include "enet.h"
#include "renderlayer.h"

#include <time.h>

#ifdef _WIN32
# include "winbits.h"
# include <mmsystem.h>
#endif

#ifdef __riscos__
# include "swis.h"
# define Timer_Start 0x490c0
# define Timer_Value 0x490c2
#endif

#include <atomic>

#if defined RENDERTYPESDL && (SDL_MAJOR_VERSION >= 2)
# define HAVE_TIMER_SDL
#endif

#if !defined _WIN32 && !defined HAVE_TIMER_SDL && !defined ZPL_HAVE_RDTSC && !defined __riscos__
# error No platform timer implementation!
#endif

#define CLOCK_FREQ 1000000ULL

EDUKE32_STATIC_ASSERT(CLOCK_FREQ <= 1000000000ULL);

#ifdef CLOCK_MONOTONIC_RAW
# define CLOCK_TYPE CLOCK_MONOTONIC_RAW
#else
# define CLOCK_TYPE CLOCK_MONOTONIC
#endif  

static int sys_timer;
uint64_t   clockLastSampleTime;
static int clockTicksPerSecond;

static void(*usertimercallback)(void);

#ifdef ZPL_HAVE_RDTSC
static uint64_t tsc_freq;

static FORCE_INLINE ATTRIBUTE((flatten)) void timerFenceRDTSC(void)
{
#if defined __SSE2__
    // On Intel, LFENCE serializes the instruction stream and MFENCE does not.
    // On AMD, MFENCE is dispatch serializing. LFENCE is not, unless:
    // - The processor is AMD family 0Fh/11h, or
    // - The processor is AMD family 10h/12h/14h or later, and MSR (Model Specific Register) C001_1029[1] is set by the kernel
    // https://hadibrais.wordpress.com/2018/05/14/the-significance-of-the-x86-lfence-instruction/
    // https://stackoverflow.com/a/50332912

#if 0
    // MFENCE before LFENCE is preferable when using both.
    // https://www.felixcloutier.com/x86/rdtsc
    _mm_mfence();
#else
    // The above conditions are reasonable assumptions to make for using only LFENCE.
    // In the future, we may want to detect CPUs requiring MFENCE and switch to that if necessary.
#endif

    _mm_lfence();

#elif defined EDUKE32_CPU_X86
    // 32-bit x86 without SSE2 uses CPUID.
    // Use inline assembly to avoid the compiler optimizing out the intrinsic versions.
# if defined _MSC_VER
    __asm
    {
        xor eax, eax
        cpuid
    }
# else
    asm volatile
    (
        "xor %%eax, %%eax\n"
        "cpuid"
        ::: "eax", "ebx", "ecx", "edx"
    );
# endif
#else
    // Everything else gets this.
# if defined __GNUC__
    __sync_synchronize();
# else
    std::atomic_thread_fence(memory_order_seq_cst);
# endif
#endif
}

static FORCE_INLINE ATTRIBUTE((flatten)) uint64_t timerSampleRDTSC(void)
{    
    timerFenceRDTSC();  // We need to serialize the instruction stream before executing RDTSC.
    uint64_t const result = zpl_rdtsc();
    timerFenceRDTSC();  // Some sources suggest serialization is also necessary or desirable after RDTSC.
    // If this code is ever changed to run by itself in a loop in its own thread, only one fence should be needed.

    return result;
}
#endif

int timerGetClockRate(void) { return clockTicksPerSecond; }

static int timerGetCounterType(void);

// returns ticks since epoch in the format and frequency specified
template<typename T> T timerGetTicks(T freq)
{
#ifdef __riscos__
    if (timerGetCounterType() == TIMER_MOD)
    {
        // Not relative to epoch time, but timerGetTicks / timerGetHiTicks is only used for interval timing anyway?
        return (T) (timerGetPerformanceCounter() / ((T)1000000/freq));
    }
#endif
    timespec ts;
    enet_gettime(CLOCK_TYPE, &ts);
    return ts.tv_sec * freq + (T)((uint64_t)ts.tv_nsec * freq / (T)1000000000);
}

uint32_t timerGetTicks(void) { return timerGetTicks<uint32_t>(1000); }
double   timerGetHiTicks(void) { return timerGetTicks<double>(1000.0); }

ATTRIBUTE((flatten)) void timerUpdateClock(void)
{
    if (!clockTicksPerSecond) return;

    auto time    = timerGetTicks<uint64_t>(CLOCK_FREQ);
    auto elapsed = (time - clockLastSampleTime) * clockTicksPerSecond;
    auto cnt     = elapsed / CLOCK_FREQ;

    totalclock.setFraction(((elapsed - cnt * CLOCK_FREQ) * 65536) / CLOCK_FREQ);

    if (cnt <= 0) return;

    totalclock += cnt;
    clockLastSampleTime += cnt * tabledivide64_noinline(CLOCK_FREQ, clockTicksPerSecond);

    if (usertimercallback)
        for (; cnt > 0; cnt--) usertimercallback();
}

static inline int timerGetCounterType(void)
{
    switch (sys_timer)
    {
        default:
        case TIMER_AUTO:
#ifdef __riscos__
        case TIMER_MOD:
            return TIMER_MOD;
        case TIMER_CLIB:
            return TIMER_CLIB;
#endif
#ifdef HAVE_TIMER_SDL
        case TIMER_SDL:
            return TIMER_SDL;
#endif // HAVE_TIMER_SDL
#ifdef _WIN32
        case TIMER_QPC:
            return TIMER_QPC;
#endif // _WIN32
#ifdef ZPL_HAVE_RDTSC
        case TIMER_RDTSC:
            return TIMER_RDTSC;
#endif
    }
}

uint64_t timerGetPerformanceCounter(void)
{
    switch (timerGetCounterType())
    {
        default:
#ifdef HAVE_TIMER_SDL
        case TIMER_SDL: return SDL_GetPerformanceCounter();
#endif
#ifdef _WIN32
        case TIMER_QPC:
        {
            LARGE_INTEGER li;
            QueryPerformanceCounter(&li);
            return li.QuadPart;
        }
#endif // _WIN32
#ifdef ZPL_HAVE_RDTSC
        case TIMER_RDTSC: return timerSampleRDTSC();
#endif
#ifdef __riscos__
        case TIMER_CLIB: return clock();
        case TIMER_MOD:
        {
            uint32_t sec,msec;
            _swix(Timer_Value,_OUTR(0,1),&sec,&msec);
            return (((uint64_t)sec)*1000000) + msec;
        }
#endif
    }
}

uint64_t timerGetPerformanceFrequency(void)
{
    switch (timerGetCounterType())
    {
        default:
#ifdef HAVE_TIMER_SDL
        case TIMER_SDL: return SDL_GetPerformanceFrequency();
#endif
#ifdef _WIN32
        case TIMER_QPC:
        {
            LARGE_INTEGER li;
            QueryPerformanceFrequency(&li);
            return li.QuadPart;
        }
#endif // _WIN32
#ifdef ZPL_HAVE_RDTSC
        case TIMER_RDTSC: return tsc_freq;
#endif
#ifdef __riscos__
        case TIMER_CLIB: return CLOCKS_PER_SEC;
        case TIMER_MOD: return 1000000;
#endif
    }
}

static int osdcmd_sys_timer(osdcmdptr_t parm)
{
    static char constexpr const *s[] = { "auto", "QPC", "SDL", "RDTSC", "CLIB", "MOD" };
    int const r = osdcmd_cvar_set(parm);

    if (r != OSDCMD_OK)
        goto print_and_return;

#ifndef _WIN32
    if (sys_timer == TIMER_QPC)
        sys_timer = TIMER_AUTO;
#endif
#ifndef HAVE_TIMER_SDL
    if (sys_timer == TIMER_SDL)
        sys_timer = TIMER_AUTO;
#endif
#ifndef ZPL_HAVE_RDTSC
    if (sys_timer == TIMER_RDTSC)
        sys_timer = TIMER_AUTO;
#endif
#ifndef __riscos__
    if ((sys_timer == TIMER_CLIB) || (sys_timer == TIMER_MOD))
        sys_timer = TIMER_AUTO;
#endif
    if ((unsigned)sys_timer >= NUMTIMERS)
        sys_timer = TIMER_AUTO;

#ifdef __riscos__
    /* Check TimerMod is available */
    if ((timerGetCounterType() == TIMER_MOD) && _swix(Timer_Start,0))
        sys_timer = TIMER_CLIB;
#endif

    if (sys_timer != TIMER_AUTO || !OSD_ParsingScript())
print_and_return:
        OSD_Printf("Using \"%s\" timer with %g MHz frequency\n", s[sys_timer], timerGetPerformanceFrequency() / 1.0e6);

#if defined EDUKE32_CPU_X86 && defined ZPL_HAVE_RDTSC
    if (sys_timer == TIMER_RDTSC && !cpu.features.invariant_tsc)
        OSD_Printf("WARNING: invariant TSC support not detected! You may experience timing issues.\n");
#endif

    clockLastSampleTime = timerGetTicks<uint64_t>(CLOCK_FREQ);

    return r;
}

int timerInit(int const tickspersecond)
{
    static int initDone;

    if (initDone == 0)
    {
        initDone = 1;

        static osdcvardata_t sys_timer_cvar = { "sys_timer",
                                                "engine timing backend:\n"
                                                "   0: auto\n"
#ifdef _WIN32
                                                "   1: WinAPI QueryPerformanceCounter\n"
#endif
#ifdef HAVE_TIMER_SDL
                                                "   2: SDL_GetPerformanceCounter\n"
#endif
#ifdef ZPL_HAVE_RDTSC
                                                "   3: CPU RDTSC instruction\n"
#endif
#ifdef __riscos__
                                                "   4: C library\n"
                                                "   5: TimerMod\n"
#endif
                                                , (void *)&sys_timer, CVAR_INT | CVAR_FUNCPTR, 0, NUMTIMERS };

        OSD_RegisterCvar(&sys_timer_cvar, osdcmd_sys_timer);

#ifdef __riscos__
        /* Check TimerMod is available */
        if ((timerGetCounterType() == TIMER_MOD) && _swix(Timer_Start,0))
            sys_timer = TIMER_CLIB;
#endif

#ifdef HAVE_TIMER_SDL
        SDL_InitSubSystem(SDL_INIT_TIMER);
#endif
#ifdef ZPL_HAVE_RDTSC
        if (tsc_freq == 0)
        {
            auto const calibrationEndTime = timerGetHiTicks() + 100.0;
            auto const samplePeriodBegin  = timerSampleRDTSC();
            do { } while (timerGetHiTicks() < calibrationEndTime);
            auto const samplePeriodEnd = timerSampleRDTSC();
            auto const timePerSample   = timerSampleRDTSC() - samplePeriodEnd;

            tsc_freq = (samplePeriodEnd - samplePeriodBegin - timePerSample) * 10;
        }
#endif
        initDone = 1;
    }

    clockTicksPerSecond = tickspersecond;
    clockLastSampleTime = timerGetTicks<uint64_t>(CLOCK_FREQ);

    usertimercallback = nullptr;

    return 0;
}

void(*timerSetCallback(void(*callback)(void)))(void)
{
    void(*oldtimercallback)(void);

    oldtimercallback = usertimercallback;
    usertimercallback = callback;

    return oldtimercallback;
}
