// Darwin process accounting: bytes and nanoseconds, never RSS-as-footprint.
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
int main(int argc, char **argv) {
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return 3;
    printf("[");
    for (int i = 1; i < argc; i++) {
        char *end; long pid = strtol(argv[i], &end, 10);
        if (*end || pid <= 0 || pid > 2147483647) return 2;
        struct rusage_info_v4 usage = {0};
        int result = proc_pid_rusage((int)pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage);
        if (i > 1) printf(",");
        if (result) printf("{\"pid\":%ld,\"error\":%d}", pid, errno);
        else printf("{\"pid\":%ld,\"start\":%llu,\"footprint\":%llu,\"cpu_ns\":%llu}",
            pid, usage.ri_proc_start_abstime, usage.ri_phys_footprint,
            (unsigned long long)(((__uint128_t)usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom));
    }
    puts("]");
}
