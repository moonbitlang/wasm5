// WASI (WebAssembly System Interface) implementation for wasm5
// This file contains all WASI-related implementations

// Feature test macros for POSIX APIs
#if defined(__linux__)
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#elif defined(__APPLE__)
// macOS: clock_gettime is available in macOS 10.12+
#include <AvailabilityMacros.h>
#endif

#include "wasi.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <errno.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#include <direct.h>
#define write _write
#define read _read
#else
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>
#endif

#if !defined(_WIN32)
#include <sched.h>
#endif

// ============================================================================
// WASI Types and State
// ============================================================================

// WASI context state
typedef struct WasiContext {
    int argc;
    char** argv;
    int environ_count;
    char** environ;
    int exit_code;
    int has_exited;
} WasiContext;

static WasiContext g_wasi_ctx = {0, NULL, 0, NULL, 0, 0};

// Preopen table (fd 0-2 are stdin/stdout/stderr, 3+ are directories)
#define WASI_MAX_PREOPENS 8
typedef struct WasiPreopen {
    int host_fd;
    const char* path;
} WasiPreopen;

static WasiPreopen g_wasi_preopens[WASI_MAX_PREOPENS] = {
    {0, "<stdin>"},
    {1, "<stdout>"},
    {2, "<stderr>"},
    {-1, NULL},
    {-1, NULL},
    {-1, NULL},
    {-1, NULL},
    {-1, NULL},
};
static int g_wasi_num_preopens = 3;

// Dynamic FD table for files opened via path_open
#define MAX_WASI_FDS 256

typedef struct {
    int host_fd;              // -1 if slot is free
    uint8_t filetype;         // WASI_FILETYPE_*
    uint16_t flags;           // WASI_FDFLAGS_*
    uint64_t rights_base;
    uint64_t rights_inheriting;
} WasiFdEntry;

static WasiFdEntry g_fd_table[MAX_WASI_FDS];
static int g_fd_table_initialized = 0;

// ============================================================================
// Helper Functions
// ============================================================================

// Initialize the dynamic FD table
static void init_fd_table(void) {
    if (g_fd_table_initialized) return;
    for (int i = 0; i < MAX_WASI_FDS; i++) {
        g_fd_table[i].host_fd = -1;
        g_fd_table[i].filetype = WASI_FILETYPE_UNKNOWN;
        g_fd_table[i].flags = 0;
        g_fd_table[i].rights_base = 0;
        g_fd_table[i].rights_inheriting = 0;
    }
    // Reserve 0-2 for stdio (not in fd_table, handled separately)
    g_fd_table_initialized = 1;
}

// Allocate a new WASI fd from the dynamic table
// Returns WASI fd (>= WASI_MAX_PREOPENS) or -1 if no free slots
static int allocate_fd(int host_fd, uint8_t filetype, uint16_t flags,
                       uint64_t rights_base, uint64_t rights_inheriting) {
    init_fd_table();
    // Start from WASI_MAX_PREOPENS to avoid collision with preopened fds
    for (int i = WASI_MAX_PREOPENS; i < MAX_WASI_FDS; i++) {
        if (g_fd_table[i].host_fd < 0) {
            g_fd_table[i].host_fd = host_fd;
            g_fd_table[i].filetype = filetype;
            g_fd_table[i].flags = flags;
            g_fd_table[i].rights_base = rights_base;
            g_fd_table[i].rights_inheriting = rights_inheriting;
            return i;
        }
    }
    return -1;  // No free slots
}

// Free a WASI fd from the dynamic table
static void free_fd(int wasi_fd) {
    if (wasi_fd >= WASI_MAX_PREOPENS && wasi_fd < MAX_WASI_FDS) {
        g_fd_table[wasi_fd].host_fd = -1;
        g_fd_table[wasi_fd].filetype = WASI_FILETYPE_UNKNOWN;
        g_fd_table[wasi_fd].flags = 0;
        g_fd_table[wasi_fd].rights_base = 0;
        g_fd_table[wasi_fd].rights_inheriting = 0;
    }
}

// Get host fd from WASI fd, checking all fd sources
// Returns host fd or -1 if invalid
static int get_host_fd(int wasi_fd) {
    init_fd_table();
    if (wasi_fd < 0) return -1;

    // stdio fds
    if (wasi_fd < 3) return wasi_fd;

    // Preopened directories (3 to g_wasi_num_preopens - 1)
    if (wasi_fd < g_wasi_num_preopens) {
        return g_wasi_preopens[wasi_fd].host_fd;
    }

    // Dynamic fd table (>= WASI_MAX_PREOPENS)
    if (wasi_fd >= WASI_MAX_PREOPENS && wasi_fd < MAX_WASI_FDS) {
        return g_fd_table[wasi_fd].host_fd;
    }

    return -1;
}

// Get WasiFdEntry for a WASI fd (only for dynamic fds)
static WasiFdEntry* get_fd_entry(int wasi_fd) {
    init_fd_table();
    if (wasi_fd >= WASI_MAX_PREOPENS && wasi_fd < MAX_WASI_FDS) {
        if (g_fd_table[wasi_fd].host_fd >= 0) {
            return &g_fd_table[wasi_fd];
        }
    }
    return NULL;
}

// Convert errno to WASI error code
static uint32_t errno_to_wasi(int err) {
    switch (err) {
        case 0:       return WASI_ERRNO_SUCCESS;
#ifdef EACCES
        case EACCES:  return WASI_ERRNO_ACCES;
#endif
#ifdef EBADF
        case EBADF:   return WASI_ERRNO_BADF;
#endif
#ifdef EEXIST
        case EEXIST:  return WASI_ERRNO_EXIST;
#endif
#ifdef EINVAL
        case EINVAL:  return WASI_ERRNO_INVAL;
#endif
#ifdef EIO
        case EIO:     return WASI_ERRNO_IO;
#endif
#ifdef EISDIR
        case EISDIR:  return WASI_ERRNO_ISDIR;
#endif
#ifdef ENOENT
        case ENOENT:  return WASI_ERRNO_NOENT;
#endif
#ifdef ENOSPC
        case ENOSPC:  return WASI_ERRNO_NOSPC;
#endif
#ifdef ENOTDIR
        case ENOTDIR: return WASI_ERRNO_NOTDIR;
#endif
#ifdef ENOTEMPTY
        case ENOTEMPTY: return WASI_ERRNO_NOTEMPTY;
#endif
#ifdef EPERM
        case EPERM:   return WASI_ERRNO_PERM;
#endif
#ifdef EROFS
        case EROFS:   return WASI_ERRNO_ROFS;
#endif
#ifdef ESPIPE
        case ESPIPE:  return WASI_ERRNO_SPIPE;
#endif
#ifdef ENAMETOOLONG
        case ENAMETOOLONG: return WASI_ERRNO_NAMETOOLONG;
#endif
        default:      return WASI_ERRNO_IO;
    }
}

// ============================================================================
// Public WASI API
// ============================================================================

// Initialize WASI context with command-line arguments
void wasi_init(int argc, char** argv) {
    g_wasi_ctx.argc = argc;
    g_wasi_ctx.argv = argv;
    g_wasi_ctx.exit_code = 0;
    g_wasi_ctx.has_exited = 0;

    // Initialize environment (simplified - no env vars for now)
    g_wasi_ctx.environ_count = 0;
    g_wasi_ctx.environ = NULL;
}

// Get WASI exit code
int wasi_get_exit_code(void) {
    return g_wasi_ctx.exit_code;
}

// Check if WASI has exited
int wasi_has_exited(void) {
    return g_wasi_ctx.has_exited;
}

// Initialize WASI with empty arguments (called from MoonBit)
void wasi_init_empty(void) {
    static char* empty_argv[] = {"wasm5", NULL};
    wasi_init(1, empty_argv);
}

// Add a preopened file to the WASI environment
// Returns the WASI fd number (3+) or -1 on error
int wasi_add_preopen_file(int host_fd, const char* path) {
    if (g_wasi_num_preopens >= WASI_MAX_PREOPENS) {
        return -1;
    }
    int wasi_fd = g_wasi_num_preopens;
    g_wasi_preopens[wasi_fd].host_fd = host_fd;
    g_wasi_preopens[wasi_fd].path = path;
    g_wasi_num_preopens++;
    return wasi_fd;
}

// FFI wrapper for wasi_add_preopen_file without path (for testing)
int wasi_add_preopen_file_ffi(int host_fd) {
    return wasi_add_preopen_file(host_fd, "<test>");
}

// Reset preopens to just stdin/stdout/stderr
void wasi_reset_preopens(void) {
    // Close any open preopened files (fd 3+)
    for (int i = 3; i < g_wasi_num_preopens; i++) {
        if (g_wasi_preopens[i].host_fd >= 0) {
            // Don't close - the caller is responsible for closing host fds
            g_wasi_preopens[i].host_fd = -1;
            g_wasi_preopens[i].path = NULL;
        }
    }
    g_wasi_num_preopens = 3;
}

// ============================================================================
// WASI Syscall Implementations
// ============================================================================

// WASI fd_write - write to file descriptor
uint32_t wasi_fd_write(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t iovs_offset = (uint32_t)args[1];
    uint32_t iovs_len = (uint32_t)args[2];
    uint32_t nwritten_offset = (uint32_t)args[3];

    // Bounds check for iovec array and nwritten pointer
    if (iovs_offset + iovs_len * 8 > (uint32_t)mem_size ||
        nwritten_offset + 4 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Get host fd (supports stdio, preopens, and dynamic fds)
    int host_fd = get_host_fd(fd);
    if (host_fd < 0) {
        return WASI_ERRNO_BADF;
    }

    size_t total_written = 0;

    for (uint32_t i = 0; i < iovs_len; i++) {
        // Read iovec from WASM memory (little-endian)
        uint32_t buf_offset = *(uint32_t*)(mem + iovs_offset + i * 8);
        uint32_t buf_len = *(uint32_t*)(mem + iovs_offset + i * 8 + 4);

        if (buf_offset + buf_len > (uint32_t)mem_size) {
            return WASI_ERRNO_INVAL;
        }

        // Use write() syscall for all fds (works for both stdio and files)
        ssize_t written = write(host_fd, mem + buf_offset, buf_len);
        if (written < 0) {
            *(uint32_t*)(mem + nwritten_offset) = (uint32_t)total_written;
            return errno_to_wasi(errno);
        }
        total_written += (size_t)written;
        if ((size_t)written < buf_len) {
            break;  // Short write
        }
    }

    // Write nwritten back to WASM memory
    *(uint32_t*)(mem + nwritten_offset) = (uint32_t)total_written;
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_read - read from file descriptor
uint32_t wasi_fd_read(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t iovs_offset = (uint32_t)args[1];
    uint32_t iovs_len = (uint32_t)args[2];
    uint32_t nread_offset = (uint32_t)args[3];

    // Bounds check
    if (iovs_offset + iovs_len * 8 > (uint32_t)mem_size ||
        nread_offset + 4 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Get host fd (supports stdio, preopens, and dynamic fds)
    int host_fd = get_host_fd(fd);
    if (host_fd < 0) {
        return WASI_ERRNO_BADF;
    }

    size_t total_read = 0;

    for (uint32_t i = 0; i < iovs_len; i++) {
        uint32_t buf_offset = *(uint32_t*)(mem + iovs_offset + i * 8);
        uint32_t buf_len = *(uint32_t*)(mem + iovs_offset + i * 8 + 4);

        if (buf_offset + buf_len > (uint32_t)mem_size) {
            return WASI_ERRNO_INVAL;
        }

        // Use read() syscall for all fds (works for both stdio and files)
        ssize_t bytes_read = read(host_fd, mem + buf_offset, buf_len);
        if (bytes_read < 0) {
            *(uint32_t*)(mem + nread_offset) = (uint32_t)total_read;
            return errno_to_wasi(errno);
        }
        total_read += (size_t)bytes_read;
        if ((size_t)bytes_read < buf_len) {
            break;  // EOF or short read
        }
    }

    *(uint32_t*)(mem + nread_offset) = (uint32_t)total_read;
    return WASI_ERRNO_SUCCESS;
}

// WASI args_sizes_get - get sizes of command line arguments
uint32_t wasi_args_sizes_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t argc_offset = (uint32_t)args[0];
    uint32_t argv_buf_size_offset = (uint32_t)args[1];

    if (argc_offset + 4 > (uint32_t)mem_size ||
        argv_buf_size_offset + 4 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Calculate total buffer size needed
    size_t buf_size = 0;
    for (int i = 0; i < g_wasi_ctx.argc; i++) {
        buf_size += strlen(g_wasi_ctx.argv[i]) + 1;  // +1 for null terminator
    }

    *(uint32_t*)(mem + argc_offset) = (uint32_t)g_wasi_ctx.argc;
    *(uint32_t*)(mem + argv_buf_size_offset) = (uint32_t)buf_size;
    return WASI_ERRNO_SUCCESS;
}

// WASI args_get - get command line arguments
uint32_t wasi_args_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t argv_offset = (uint32_t)args[0];      // Array of i32 pointers
    uint32_t argv_buf_offset = (uint32_t)args[1];  // String data buffer

    uint32_t buf_ptr = argv_buf_offset;
    for (int i = 0; i < g_wasi_ctx.argc; i++) {
        // Write pointer to argv array
        if (argv_offset + (uint32_t)i * 4 + 4 > (uint32_t)mem_size) {
            return WASI_ERRNO_INVAL;
        }
        *(uint32_t*)(mem + argv_offset + i * 4) = buf_ptr;

        // Copy string to buffer
        size_t len = strlen(g_wasi_ctx.argv[i]) + 1;
        if (buf_ptr + len > (uint32_t)mem_size) {
            return WASI_ERRNO_INVAL;
        }
        memcpy(mem + buf_ptr, g_wasi_ctx.argv[i], len);
        buf_ptr += (uint32_t)len;
    }
    return WASI_ERRNO_SUCCESS;
}

// WASI environ_sizes_get - get sizes of environment variables
uint32_t wasi_environ_sizes_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t count_offset = (uint32_t)args[0];
    uint32_t buf_size_offset = (uint32_t)args[1];

    if (count_offset + 4 > (uint32_t)mem_size ||
        buf_size_offset + 4 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // No environment variables for now
    *(uint32_t*)(mem + count_offset) = 0;
    *(uint32_t*)(mem + buf_size_offset) = 0;
    return WASI_ERRNO_SUCCESS;
}

// WASI environ_get - get environment variables
uint32_t wasi_environ_get(uint64_t* args, uint8_t* mem, int mem_size) {
    (void)args;
    (void)mem;
    (void)mem_size;
    // No environment variables for now - nothing to copy
    return WASI_ERRNO_SUCCESS;
}

// WASI proc_exit - exit the process
uint32_t wasi_proc_exit(uint64_t* args) {
    g_wasi_ctx.exit_code = (int)(uint32_t)args[0];
    g_wasi_ctx.has_exited = 1;
    return 0;  // Never actually returns normally
}

// WASI fd_close - close file descriptor
uint32_t wasi_fd_close(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    // Don't allow closing stdin/stdout/stderr
    if (fd <= 2) {
        return WASI_ERRNO_BADF;
    }

    // Check if it's a dynamically opened fd
    if (fd >= WASI_MAX_PREOPENS && fd < MAX_WASI_FDS) {
        int host_fd = g_fd_table[fd].host_fd;
        if (host_fd >= 0) {
            close(host_fd);
            free_fd(fd);
            return WASI_ERRNO_SUCCESS;
        }
    }

    // Preopened fds (3 to g_wasi_num_preopens-1) - don't close these
    if (fd < (uint32_t)g_wasi_num_preopens) {
        // Preopened directories shouldn't be closed by WASI programs
        return WASI_ERRNO_BADF;
    }

    return WASI_ERRNO_BADF;
}

// WASI fd_prestat_get - get preopen info for fd
uint32_t wasi_fd_prestat_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t buf_offset = (uint32_t)args[1];

    if (buf_offset + 8 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Check if fd is a valid preopen
    if (fd >= (uint32_t)g_wasi_num_preopens || fd < 3) {
        // fd 0-2 are stdio, not preopens; fd >= num_preopens is invalid
        return WASI_ERRNO_BADF;
    }

    if (g_wasi_preopens[fd].host_fd < 0) {
        return WASI_ERRNO_BADF;
    }

    // Write prestat structure (type=dir, name_len)
    const char* path = g_wasi_preopens[fd].path;
    size_t path_len = path ? strlen(path) : 0;

    *(uint32_t*)(mem + buf_offset) = WASI_PREOPENTYPE_DIR;  // type
    *(uint32_t*)(mem + buf_offset + 4) = (uint32_t)path_len;  // name_len

    return WASI_ERRNO_SUCCESS;
}

// WASI fd_prestat_dir_name - get preopen directory name
uint32_t wasi_fd_prestat_dir_name(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t path_offset = (uint32_t)args[1];
    uint32_t path_len = (uint32_t)args[2];

    if (path_offset + path_len > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    if (fd >= (uint32_t)g_wasi_num_preopens || fd < 3) {
        return WASI_ERRNO_BADF;
    }

    if (g_wasi_preopens[fd].host_fd < 0) {
        return WASI_ERRNO_BADF;
    }

    const char* path = g_wasi_preopens[fd].path;
    size_t actual_len = path ? strlen(path) : 0;

    if (path_len < actual_len) {
        return WASI_ERRNO_INVAL;  // Buffer too small
    }

    if (path && actual_len > 0) {
        memcpy(mem + path_offset, path, actual_len);
    }

    return WASI_ERRNO_SUCCESS;
}

// WASI fd_fdstat_get - get file descriptor status
uint32_t wasi_fd_fdstat_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t buf_offset = (uint32_t)args[1];

    // fdstat structure is 24 bytes
    if (buf_offset + 24 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    uint8_t filetype;
    uint16_t fdflags = 0;
    uint64_t rights_base;
    uint64_t rights_inheriting;

    if (fd == 0) {
        // stdin
        filetype = WASI_FILETYPE_CHARACTER_DEVICE;
        rights_base = WASI_RIGHTS_FD_READ;
        rights_inheriting = 0;
    } else if (fd == 1 || fd == 2) {
        // stdout/stderr
        filetype = WASI_FILETYPE_CHARACTER_DEVICE;
        rights_base = WASI_RIGHTS_FD_WRITE;
        rights_inheriting = 0;
    } else if (fd < (uint32_t)g_wasi_num_preopens && g_wasi_preopens[fd].host_fd >= 0) {
        // Preopened directory
        filetype = WASI_FILETYPE_DIRECTORY;
        rights_base = WASI_RIGHTS_PATH_OPEN | WASI_RIGHTS_FD_READ;
        rights_inheriting = WASI_RIGHTS_FD_READ | WASI_RIGHTS_FD_WRITE | WASI_RIGHTS_FD_SEEK;
    } else {
        // Check dynamic fd table
        WasiFdEntry* entry = get_fd_entry(fd);
        if (entry) {
            filetype = entry->filetype;
            fdflags = entry->flags;
            rights_base = entry->rights_base;
            rights_inheriting = entry->rights_inheriting;
        } else {
            return WASI_ERRNO_BADF;
        }
    }

    // Write fdstat structure
    *(uint8_t*)(mem + buf_offset) = filetype;         // fs_filetype
    *(uint8_t*)(mem + buf_offset + 1) = 0;            // padding
    *(uint16_t*)(mem + buf_offset + 2) = fdflags;     // fs_flags
    *(uint32_t*)(mem + buf_offset + 4) = 0;           // padding
    *(uint64_t*)(mem + buf_offset + 8) = rights_base; // fs_rights_base
    *(uint64_t*)(mem + buf_offset + 16) = rights_inheriting; // fs_rights_inheriting

    return WASI_ERRNO_SUCCESS;
}

// WASI clock_time_get - get current time
uint32_t wasi_clock_time_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t clock_id = (uint32_t)args[0];
    // uint64_t precision = args[1];  // Ignored
    uint32_t time_offset = (uint32_t)args[2];

    if (time_offset + 8 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    uint64_t time_ns;

    if (clock_id == WASI_CLOCKID_REALTIME || clock_id == WASI_CLOCKID_MONOTONIC) {
#ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
        // Convert from 100-ns intervals since 1601 to ns since Unix epoch
        time_ns = (t - 116444736000000000ULL) * 100;
#else
        struct timespec ts;
        clock_gettime(clock_id == WASI_CLOCKID_REALTIME ? CLOCK_REALTIME : CLOCK_MONOTONIC, &ts);
        time_ns = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
#endif
    } else {
        return WASI_ERRNO_INVAL;
    }

    *(uint64_t*)(mem + time_offset) = time_ns;
    return WASI_ERRNO_SUCCESS;
}

// WASI random_get - get random bytes
uint32_t wasi_random_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t buf_offset = (uint32_t)args[0];
    uint32_t buf_len = (uint32_t)args[1];

    if (buf_offset + buf_len > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Simple PRNG for now (not cryptographically secure)
    static uint64_t seed = 0;
    if (seed == 0) {
        seed = (uint64_t)time(NULL);
    }

    for (uint32_t i = 0; i < buf_len; i++) {
        // LCG random
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        mem[buf_offset + i] = (uint8_t)(seed >> 33);
    }

    return WASI_ERRNO_SUCCESS;
}

// WASI fd_seek - seek to position in file
uint32_t wasi_fd_seek(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    int64_t offset = (int64_t)args[1];
    uint8_t whence = (uint8_t)args[2];  // 0=SET, 1=CUR, 2=END
    uint32_t newoffset_ptr = (uint32_t)args[3];

    if (newoffset_ptr + 8 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Get host fd (supports preopens and dynamic fds)
    int host_fd = get_host_fd(fd);
    if (host_fd < 0 || fd < 3) {  // Don't allow seeking on stdio
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    int host_whence;
    switch (whence) {
        case 0:
            host_whence = SEEK_SET;
            break;
        case 1:
            host_whence = SEEK_CUR;
            break;
        case 2:
            host_whence = SEEK_END;
            break;
        default:
            return WASI_ERRNO_INVAL;
    }
    int64_t result = _lseeki64(host_fd, offset, host_whence);
#else
    int host_whence;
    switch (whence) {
        case 0:
            host_whence = SEEK_SET;
            break;
        case 1:
            host_whence = SEEK_CUR;
            break;
        case 2:
            host_whence = SEEK_END;
            break;
        default:
            return WASI_ERRNO_INVAL;
    }
    off_t result = lseek(host_fd, offset, host_whence);
#endif
    if (result < 0) {
        return WASI_ERRNO_INVAL;
    }

    *(uint64_t*)(mem + newoffset_ptr) = (uint64_t)result;
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_tell - get current file position
uint32_t wasi_fd_tell(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t offset_ptr = (uint32_t)args[1];

    if (offset_ptr + 8 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Get host fd (supports preopens and dynamic fds)
    int host_fd = get_host_fd(fd);
    if (host_fd < 0 || fd < 3) {  // Don't allow tell on stdio
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    int64_t result = _lseeki64(host_fd, 0, SEEK_CUR);
#else
    off_t result = lseek(host_fd, 0, SEEK_CUR);
#endif
    if (result < 0) {
        return WASI_ERRNO_INVAL;
    }

    *(uint64_t*)(mem + offset_ptr) = (uint64_t)result;
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_filestat_get - get file stats via fd
// WASI filestat structure (64 bytes):
// dev: u64, ino: u64, filetype: u8, nlink: u64, size: u64, atim: u64, mtim: u64, ctim: u64
uint32_t wasi_fd_filestat_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t buf_ptr = (uint32_t)args[1];

    if (buf_ptr + 64 > (uint32_t)mem_size) {
        return WASI_ERRNO_INVAL;
    }

    // Get host fd (supports stdio, preopens, and dynamic fds)
    int host_fd = get_host_fd(fd);
    if (host_fd < 0) {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    // On Windows, use _fstat64
    struct __stat64 st;
    if (_fstat64(host_fd, &st) < 0) {
        return WASI_ERRNO_BADF;
    }
    uint8_t filetype = ((st.st_mode & _S_IFDIR) ? WASI_FILETYPE_DIRECTORY :
                        (st.st_mode & _S_IFREG) ? WASI_FILETYPE_REGULAR_FILE :
                        (st.st_mode & _S_IFCHR) ? WASI_FILETYPE_CHARACTER_DEVICE :
                        WASI_FILETYPE_UNKNOWN);
    uint64_t dev = st.st_dev;
    uint64_t ino = st.st_ino;
    uint64_t nlink = st.st_nlink;
    uint64_t size = st.st_size;
    uint64_t atim = (uint64_t)st.st_atime * 1000000000ULL;
    uint64_t mtim = (uint64_t)st.st_mtime * 1000000000ULL;
    uint64_t ctim = (uint64_t)st.st_ctime * 1000000000ULL;
#else
    struct stat st;
    if (fstat(host_fd, &st) < 0) {
        return WASI_ERRNO_BADF;
    }
    uint8_t filetype = (S_ISDIR(st.st_mode) ? WASI_FILETYPE_DIRECTORY :
                        S_ISREG(st.st_mode) ? WASI_FILETYPE_REGULAR_FILE :
                        S_ISCHR(st.st_mode) ? WASI_FILETYPE_CHARACTER_DEVICE :
                        WASI_FILETYPE_UNKNOWN);
    uint64_t dev = st.st_dev;
    uint64_t ino = st.st_ino;
    uint64_t nlink = st.st_nlink;
    uint64_t size = (uint64_t)st.st_size;
    uint64_t atim = (uint64_t)st.st_atime * 1000000000ULL;
    uint64_t mtim = (uint64_t)st.st_mtime * 1000000000ULL;
    uint64_t ctim = (uint64_t)st.st_ctime * 1000000000ULL;
#endif

    uint8_t* buf = mem + buf_ptr;
    memset(buf, 0, 64);  // Zero out padding bytes
    *(uint64_t*)(buf + 0) = dev;
    *(uint64_t*)(buf + 8) = ino;
    buf[16] = filetype;
    // Padding at 17-23
    *(uint64_t*)(buf + 24) = nlink;
    *(uint64_t*)(buf + 32) = size;
    *(uint64_t*)(buf + 40) = atim;
    *(uint64_t*)(buf + 48) = mtim;
    *(uint64_t*)(buf + 56) = ctim;

    return WASI_ERRNO_SUCCESS;
}

// WASI fd_sync - sync data and metadata to storage
uint32_t wasi_fd_sync(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];

    // Get host fd (supports preopens and dynamic fds)
    int host_fd = get_host_fd(fd);
    if (host_fd < 0 || fd < 3) {  // Don't sync stdio
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    if (_commit(host_fd) < 0) {
        return WASI_ERRNO_IO;
    }
#else
    if (fsync(host_fd) < 0) {
        return WASI_ERRNO_IO;
    }
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_datasync - sync data (not metadata) to storage
uint32_t wasi_fd_datasync(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];

    // Get host fd (supports preopens and dynamic fds)
    int host_fd = get_host_fd(fd);
    if (host_fd < 0 || fd < 3) {  // Don't sync stdio
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    if (_commit(host_fd) < 0) {
        return WASI_ERRNO_IO;
    }
#elif defined(__APPLE__)
    // macOS doesn't have fdatasync, use fcntl F_FULLFSYNC for full sync
    if (fcntl(host_fd, F_FULLFSYNC) < 0) {
        // Fall back to fsync if F_FULLFSYNC fails
        if (fsync(host_fd) < 0) {
            return WASI_ERRNO_IO;
        }
    }
#else
    if (fdatasync(host_fd) < 0) {
        return WASI_ERRNO_IO;
    }
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI sched_yield - yield the current thread
uint32_t wasi_sched_yield(void) {
#ifdef _WIN32
    SwitchToThread();
#else
    sched_yield();
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI path_open - open a file relative to a directory
// Args: dirfd, dirflags, path_ptr, path_len, oflags, rights_base, rights_inheriting, fdflags, fd_ptr
uint32_t wasi_path_open(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t dirfd = (uint32_t)args[0];
    uint32_t dirflags = (uint32_t)args[1];  // lookupflags (e.g., symlink_follow)
    uint32_t path_ptr = (uint32_t)args[2];
    uint32_t path_len = (uint32_t)args[3];
    uint16_t oflags = (uint16_t)args[4];
    uint64_t rights_base = args[5];
    uint64_t rights_inheriting = args[6];
    uint16_t fdflags = (uint16_t)args[7];
    uint32_t fd_ptr = (uint32_t)args[8];

    (void)dirflags;  // Not fully used yet

    // Bounds check
    if (path_ptr + path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (fd_ptr + 4 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (path_len >= 512) return WASI_ERRNO_NAMETOOLONG;
    if (path_len == 0) return WASI_ERRNO_INVAL;

    // Copy path to null-terminated buffer
    char host_path[512];
    memcpy(host_path, mem + path_ptr, path_len);
    host_path[path_len] = '\0';

    // Get base directory fd - must be a preopened directory
    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

    // Translate WASI flags to host flags
    int flags = 0;
    if (oflags & WASI_OFLAGS_CREAT) flags |= O_CREAT;
    if (oflags & WASI_OFLAGS_EXCL) flags |= O_EXCL;
    if (oflags & WASI_OFLAGS_TRUNC) flags |= O_TRUNC;
    if (fdflags & WASI_FDFLAGS_APPEND) flags |= O_APPEND;
#ifndef _WIN32
    if (fdflags & WASI_FDFLAGS_NONBLOCK) flags |= O_NONBLOCK;
    if (fdflags & WASI_FDFLAGS_SYNC) flags |= O_SYNC;
#ifdef O_DSYNC
    if (fdflags & WASI_FDFLAGS_DSYNC) flags |= O_DSYNC;
#endif
#endif

    // Determine read/write mode from rights
    int has_read = (rights_base & WASI_RIGHTS_FD_READ) != 0;
    int has_write = (rights_base & WASI_RIGHTS_FD_WRITE) != 0;
    if (has_read && has_write) flags |= O_RDWR;
    else if (has_write) flags |= O_WRONLY;
    else flags |= O_RDONLY;

#ifdef _WIN32
    flags |= _O_BINARY;
    // Windows: construct full path (base_path + "/" + host_path)
    char full_path[1024];
    if (base_path && base_path[0] != '<') {
        snprintf(full_path, sizeof(full_path), "%s/%s", base_path, host_path);
    } else {
        snprintf(full_path, sizeof(full_path), "%s", host_path);
    }
    int host_fd = _open(full_path, flags, 0644);
#else
    int host_fd = openat(base_fd, host_path, flags, 0644);
#endif

    if (host_fd < 0) {
        return errno_to_wasi(errno);
    }

    // Determine file type
    uint8_t filetype = WASI_FILETYPE_REGULAR_FILE;
    if (oflags & WASI_OFLAGS_DIRECTORY) {
        filetype = WASI_FILETYPE_DIRECTORY;
    } else {
#ifdef _WIN32
        struct __stat64 st;
        if (_fstat64(host_fd, &st) == 0) {
            if (st.st_mode & _S_IFDIR) filetype = WASI_FILETYPE_DIRECTORY;
            else if (st.st_mode & _S_IFREG) filetype = WASI_FILETYPE_REGULAR_FILE;
            else if (st.st_mode & _S_IFCHR) filetype = WASI_FILETYPE_CHARACTER_DEVICE;
        }
#else
        struct stat st;
        if (fstat(host_fd, &st) == 0) {
            if (S_ISDIR(st.st_mode)) filetype = WASI_FILETYPE_DIRECTORY;
            else if (S_ISREG(st.st_mode)) filetype = WASI_FILETYPE_REGULAR_FILE;
            else if (S_ISCHR(st.st_mode)) filetype = WASI_FILETYPE_CHARACTER_DEVICE;
            else if (S_ISLNK(st.st_mode)) filetype = WASI_FILETYPE_SYMBOLIC_LINK;
        }
#endif
    }

    // Allocate WASI fd
    int wasi_fd = allocate_fd(host_fd, filetype, fdflags, rights_base, rights_inheriting);
    if (wasi_fd < 0) {
        close(host_fd);
        return WASI_ERRNO_NFILE;
    }

    *(uint32_t*)(mem + fd_ptr) = (uint32_t)wasi_fd;
    return WASI_ERRNO_SUCCESS;
}

// WASI path_filestat_get - get file stats via path
uint32_t wasi_path_filestat_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t dirfd = (uint32_t)args[0];
    uint32_t flags = (uint32_t)args[1];  // lookupflags
    uint32_t path_ptr = (uint32_t)args[2];
    uint32_t path_len = (uint32_t)args[3];
    uint32_t buf_ptr = (uint32_t)args[4];

    if (path_ptr + path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (buf_ptr + 64 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char host_path[512];
    memcpy(host_path, mem + path_ptr, path_len);
    host_path[path_len] = '\0';

    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    char full_path[1024];
    if (base_path && base_path[0] != '<') {
        snprintf(full_path, sizeof(full_path), "%s/%s", base_path, host_path);
    } else {
        snprintf(full_path, sizeof(full_path), "%s", host_path);
    }
    struct __stat64 st;
    if (_stat64(full_path, &st) < 0) return errno_to_wasi(errno);
    uint8_t filetype = ((st.st_mode & _S_IFDIR) ? WASI_FILETYPE_DIRECTORY :
                        (st.st_mode & _S_IFREG) ? WASI_FILETYPE_REGULAR_FILE :
                        (st.st_mode & _S_IFCHR) ? WASI_FILETYPE_CHARACTER_DEVICE :
                        WASI_FILETYPE_UNKNOWN);
    uint64_t dev = st.st_dev;
    uint64_t ino = st.st_ino;
    uint64_t nlink = st.st_nlink;
    uint64_t size = st.st_size;
    uint64_t atim = (uint64_t)st.st_atime * 1000000000ULL;
    uint64_t mtim = (uint64_t)st.st_mtime * 1000000000ULL;
    uint64_t ctim = (uint64_t)st.st_ctime * 1000000000ULL;
#else
    int stat_flags = (flags & 1) ? 0 : AT_SYMLINK_NOFOLLOW;  // flags & 1 = LOOKUPFLAGS_SYMLINK_FOLLOW
    struct stat st;
    if (fstatat(base_fd, host_path, &st, stat_flags) < 0) return errno_to_wasi(errno);
    uint8_t filetype = (S_ISDIR(st.st_mode) ? WASI_FILETYPE_DIRECTORY :
                        S_ISREG(st.st_mode) ? WASI_FILETYPE_REGULAR_FILE :
                        S_ISCHR(st.st_mode) ? WASI_FILETYPE_CHARACTER_DEVICE :
                        S_ISLNK(st.st_mode) ? WASI_FILETYPE_SYMBOLIC_LINK :
                        WASI_FILETYPE_UNKNOWN);
    uint64_t dev = st.st_dev;
    uint64_t ino = st.st_ino;
    uint64_t nlink = st.st_nlink;
    uint64_t size = (uint64_t)st.st_size;
    uint64_t atim = (uint64_t)st.st_atime * 1000000000ULL;
    uint64_t mtim = (uint64_t)st.st_mtime * 1000000000ULL;
    uint64_t ctim = (uint64_t)st.st_ctime * 1000000000ULL;
#endif

    uint8_t* buf = mem + buf_ptr;
    memset(buf, 0, 64);
    *(uint64_t*)(buf + 0) = dev;
    *(uint64_t*)(buf + 8) = ino;
    buf[16] = filetype;
    *(uint64_t*)(buf + 24) = nlink;
    *(uint64_t*)(buf + 32) = size;
    *(uint64_t*)(buf + 40) = atim;
    *(uint64_t*)(buf + 48) = mtim;
    *(uint64_t*)(buf + 56) = ctim;

    return WASI_ERRNO_SUCCESS;
}

// WASI path_filestat_set_times - set file timestamps via path
uint32_t wasi_path_filestat_set_times(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t dirfd = (uint32_t)args[0];
    uint32_t flags = (uint32_t)args[1];  // lookupflags
    uint32_t path_ptr = (uint32_t)args[2];
    uint32_t path_len = (uint32_t)args[3];
    uint64_t atim = args[4];
    uint64_t mtim = args[5];
    uint16_t fst_flags = (uint16_t)args[6];

    if (path_ptr + path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char host_path[512];
    memcpy(host_path, mem + path_ptr, path_len);
    host_path[path_len] = '\0';

    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    (void)flags;
    (void)base_path;
    (void)atim;
    (void)mtim;
    (void)fst_flags;
    return WASI_ERRNO_NOSYS;
#else
    struct timespec times[2];
    // Access time
    if (fst_flags & 1) {  // FSTFLAGS_ATIM_NOW
        times[0].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 2) {  // FSTFLAGS_ATIM
        times[0].tv_sec = (time_t)(atim / 1000000000ULL);
        times[0].tv_nsec = (long)(atim % 1000000000ULL);
    } else {
        times[0].tv_nsec = UTIME_OMIT;
    }
    // Modification time
    if (fst_flags & 4) {  // FSTFLAGS_MTIM_NOW
        times[1].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 8) {  // FSTFLAGS_MTIM
        times[1].tv_sec = (time_t)(mtim / 1000000000ULL);
        times[1].tv_nsec = (long)(mtim % 1000000000ULL);
    } else {
        times[1].tv_nsec = UTIME_OMIT;
    }
    int stat_flags = (flags & 1) ? 0 : AT_SYMLINK_NOFOLLOW;
    if (utimensat(base_fd, host_path, times, stat_flags) < 0) return errno_to_wasi(errno);
    return WASI_ERRNO_SUCCESS;
#endif
}

// WASI path_create_directory - create a directory
uint32_t wasi_path_create_directory(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t dirfd = (uint32_t)args[0];
    uint32_t path_ptr = (uint32_t)args[1];
    uint32_t path_len = (uint32_t)args[2];

    if (path_ptr + path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char host_path[512];
    memcpy(host_path, mem + path_ptr, path_len);
    host_path[path_len] = '\0';

    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    char full_path[1024];
    if (base_path && base_path[0] != '<') {
        snprintf(full_path, sizeof(full_path), "%s/%s", base_path, host_path);
    } else {
        snprintf(full_path, sizeof(full_path), "%s", host_path);
    }
    if (_mkdir(full_path) < 0) return errno_to_wasi(errno);
#else
    if (mkdirat(base_fd, host_path, 0755) < 0) return errno_to_wasi(errno);
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI path_remove_directory - remove a directory
uint32_t wasi_path_remove_directory(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t dirfd = (uint32_t)args[0];
    uint32_t path_ptr = (uint32_t)args[1];
    uint32_t path_len = (uint32_t)args[2];

    if (path_ptr + path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char host_path[512];
    memcpy(host_path, mem + path_ptr, path_len);
    host_path[path_len] = '\0';

    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    char full_path[1024];
    if (base_path && base_path[0] != '<') {
        snprintf(full_path, sizeof(full_path), "%s/%s", base_path, host_path);
    } else {
        snprintf(full_path, sizeof(full_path), "%s", host_path);
    }
    if (_rmdir(full_path) < 0) return errno_to_wasi(errno);
#else
    if (unlinkat(base_fd, host_path, AT_REMOVEDIR) < 0) return errno_to_wasi(errno);
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI path_unlink_file - unlink (delete) a file
uint32_t wasi_path_unlink_file(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t dirfd = (uint32_t)args[0];
    uint32_t path_ptr = (uint32_t)args[1];
    uint32_t path_len = (uint32_t)args[2];

    if (path_ptr + path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char host_path[512];
    memcpy(host_path, mem + path_ptr, path_len);
    host_path[path_len] = '\0';

    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    char full_path[1024];
    if (base_path && base_path[0] != '<') {
        snprintf(full_path, sizeof(full_path), "%s/%s", base_path, host_path);
    } else {
        snprintf(full_path, sizeof(full_path), "%s", host_path);
    }
    if (_unlink(full_path) < 0) return errno_to_wasi(errno);
#else
    if (unlinkat(base_fd, host_path, 0) < 0) return errno_to_wasi(errno);
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI path_rename - rename a file or directory
uint32_t wasi_path_rename(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t old_dirfd = (uint32_t)args[0];
    uint32_t old_path_ptr = (uint32_t)args[1];
    uint32_t old_path_len = (uint32_t)args[2];
    uint32_t new_dirfd = (uint32_t)args[3];
    uint32_t new_path_ptr = (uint32_t)args[4];
    uint32_t new_path_len = (uint32_t)args[5];

    if (old_path_ptr + old_path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (new_path_ptr + new_path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (old_path_len >= 512 || new_path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char old_path[512], new_path[512];
    memcpy(old_path, mem + old_path_ptr, old_path_len);
    old_path[old_path_len] = '\0';
    memcpy(new_path, mem + new_path_ptr, new_path_len);
    new_path[new_path_len] = '\0';

    int old_base_fd = -1, new_base_fd = -1;
    const char* old_base_path = NULL;
    const char* new_base_path = NULL;

    if (old_dirfd >= 3 && old_dirfd < (uint32_t)g_wasi_num_preopens) {
        old_base_fd = g_wasi_preopens[old_dirfd].host_fd;
        old_base_path = g_wasi_preopens[old_dirfd].path;
        if (old_base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

    if (new_dirfd >= 3 && new_dirfd < (uint32_t)g_wasi_num_preopens) {
        new_base_fd = g_wasi_preopens[new_dirfd].host_fd;
        new_base_path = g_wasi_preopens[new_dirfd].path;
        if (new_base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    char old_full_path[1024], new_full_path[1024];
    if (old_base_path && old_base_path[0] != '<') {
        snprintf(old_full_path, sizeof(old_full_path), "%s/%s", old_base_path, old_path);
    } else {
        snprintf(old_full_path, sizeof(old_full_path), "%s", old_path);
    }
    if (new_base_path && new_base_path[0] != '<') {
        snprintf(new_full_path, sizeof(new_full_path), "%s/%s", new_base_path, new_path);
    } else {
        snprintf(new_full_path, sizeof(new_full_path), "%s", new_path);
    }
    if (rename(old_full_path, new_full_path) < 0) return errno_to_wasi(errno);
#else
    if (renameat(old_base_fd, old_path, new_base_fd, new_path) < 0) return errno_to_wasi(errno);
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI path_link - create a hard link
uint32_t wasi_path_link(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t old_dirfd = (uint32_t)args[0];
    uint32_t old_flags = (uint32_t)args[1];  // lookupflags
    uint32_t old_path_ptr = (uint32_t)args[2];
    uint32_t old_path_len = (uint32_t)args[3];
    uint32_t new_dirfd = (uint32_t)args[4];
    uint32_t new_path_ptr = (uint32_t)args[5];
    uint32_t new_path_len = (uint32_t)args[6];

    if (old_path_ptr + old_path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (new_path_ptr + new_path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (old_path_len >= 512 || new_path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char old_path[512];
    char new_path[512];
    memcpy(old_path, mem + old_path_ptr, old_path_len);
    memcpy(new_path, mem + new_path_ptr, new_path_len);
    old_path[old_path_len] = '\0';
    new_path[new_path_len] = '\0';

    int old_base_fd = -1;
    const char* old_base_path = NULL;
    if (old_dirfd >= 3 && old_dirfd < (uint32_t)g_wasi_num_preopens) {
        old_base_fd = g_wasi_preopens[old_dirfd].host_fd;
        old_base_path = g_wasi_preopens[old_dirfd].path;
        if (old_base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

    int new_base_fd = -1;
    const char* new_base_path = NULL;
    if (new_dirfd >= 3 && new_dirfd < (uint32_t)g_wasi_num_preopens) {
        new_base_fd = g_wasi_preopens[new_dirfd].host_fd;
        new_base_path = g_wasi_preopens[new_dirfd].path;
        if (new_base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    (void)old_flags;
    (void)old_base_path;
    (void)new_base_path;
    return WASI_ERRNO_NOSYS;
#else
    int link_flags = (old_flags & 1) ? AT_SYMLINK_FOLLOW : 0;
    if (linkat(old_base_fd, old_path, new_base_fd, new_path, link_flags) < 0) {
        return errno_to_wasi(errno);
    }
    return WASI_ERRNO_SUCCESS;
#endif
}

// WASI path_readlink - read the target of a symlink
uint32_t wasi_path_readlink(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t dirfd = (uint32_t)args[0];
    uint32_t path_ptr = (uint32_t)args[1];
    uint32_t path_len = (uint32_t)args[2];
    uint32_t buf_ptr = (uint32_t)args[3];
    uint32_t buf_len = (uint32_t)args[4];
    uint32_t bufused_ptr = (uint32_t)args[5];

    if (path_ptr + path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (buf_ptr + buf_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (bufused_ptr + 4 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char host_path[512];
    memcpy(host_path, mem + path_ptr, path_len);
    host_path[path_len] = '\0';

    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    (void)base_path;
    *(uint32_t*)(mem + bufused_ptr) = 0;
    return WASI_ERRNO_NOSYS;
#else
    ssize_t len = readlinkat(base_fd, host_path, (char*)(mem + buf_ptr), buf_len);
    if (len < 0) return errno_to_wasi(errno);
    *(uint32_t*)(mem + bufused_ptr) = (uint32_t)len;
    return WASI_ERRNO_SUCCESS;
#endif
}

// WASI path_symlink - create a symlink
uint32_t wasi_path_symlink(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t old_path_ptr = (uint32_t)args[0];
    uint32_t old_path_len = (uint32_t)args[1];
    uint32_t dirfd = (uint32_t)args[2];
    uint32_t new_path_ptr = (uint32_t)args[3];
    uint32_t new_path_len = (uint32_t)args[4];

    if (old_path_ptr + old_path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (new_path_ptr + new_path_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (old_path_len >= 512 || new_path_len >= 512) return WASI_ERRNO_NAMETOOLONG;

    char old_path[512];
    char new_path[512];
    memcpy(old_path, mem + old_path_ptr, old_path_len);
    memcpy(new_path, mem + new_path_ptr, new_path_len);
    old_path[old_path_len] = '\0';
    new_path[new_path_len] = '\0';

    int base_fd = -1;
    const char* base_path = NULL;
    if (dirfd >= 3 && dirfd < (uint32_t)g_wasi_num_preopens) {
        base_fd = g_wasi_preopens[dirfd].host_fd;
        base_path = g_wasi_preopens[dirfd].path;
        if (base_fd < 0) return WASI_ERRNO_BADF;
    } else {
        return WASI_ERRNO_BADF;
    }

#ifdef _WIN32
    (void)base_path;
    return WASI_ERRNO_NOSYS;
#else
    if (symlinkat(old_path, base_fd, new_path) < 0) return errno_to_wasi(errno);
    return WASI_ERRNO_SUCCESS;
#endif
}

// WASI fd_pread - read from file at offset without changing position
uint32_t wasi_fd_pread(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t iovs_ptr = (uint32_t)args[1];
    uint32_t iovs_len = (uint32_t)args[2];
    uint64_t offset = args[3];
    uint32_t nread_ptr = (uint32_t)args[4];

    if (iovs_ptr + iovs_len * 8 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (nread_ptr + 4 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

    size_t total_read = 0;
    for (uint32_t i = 0; i < iovs_len; i++) {
        uint32_t buf_ptr = *(uint32_t*)(mem + iovs_ptr + i * 8);
        uint32_t buf_len = *(uint32_t*)(mem + iovs_ptr + i * 8 + 4);

        if (buf_ptr + buf_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;

#ifdef _WIN32
        // Windows doesn't have pread, simulate with lseek + read + lseek
        int64_t saved_pos = _lseeki64(host_fd, 0, SEEK_CUR);
        if (saved_pos < 0) return WASI_ERRNO_IO;
        if (_lseeki64(host_fd, (int64_t)offset + (int64_t)total_read, SEEK_SET) < 0) {
            _lseeki64(host_fd, saved_pos, SEEK_SET);
            return WASI_ERRNO_IO;
        }
        ssize_t bytes_read = read(host_fd, mem + buf_ptr, buf_len);
        _lseeki64(host_fd, saved_pos, SEEK_SET);
#else
        ssize_t bytes_read = pread(host_fd, mem + buf_ptr, buf_len, (off_t)(offset + total_read));
#endif
        if (bytes_read < 0) {
            *(uint32_t*)(mem + nread_ptr) = (uint32_t)total_read;
            return errno_to_wasi(errno);
        }
        total_read += (size_t)bytes_read;
        if ((size_t)bytes_read < buf_len) break;
    }

    *(uint32_t*)(mem + nread_ptr) = (uint32_t)total_read;
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_pwrite - write to file at offset without changing position
uint32_t wasi_fd_pwrite(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t iovs_ptr = (uint32_t)args[1];
    uint32_t iovs_len = (uint32_t)args[2];
    uint64_t offset = args[3];
    uint32_t nwritten_ptr = (uint32_t)args[4];

    if (iovs_ptr + iovs_len * 8 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (nwritten_ptr + 4 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

    size_t total_written = 0;
    for (uint32_t i = 0; i < iovs_len; i++) {
        uint32_t buf_ptr = *(uint32_t*)(mem + iovs_ptr + i * 8);
        uint32_t buf_len = *(uint32_t*)(mem + iovs_ptr + i * 8 + 4);

        if (buf_ptr + buf_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;

#ifdef _WIN32
        // Windows doesn't have pwrite, simulate
        int64_t saved_pos = _lseeki64(host_fd, 0, SEEK_CUR);
        if (saved_pos < 0) return WASI_ERRNO_IO;
        if (_lseeki64(host_fd, (int64_t)offset + (int64_t)total_written, SEEK_SET) < 0) {
            _lseeki64(host_fd, saved_pos, SEEK_SET);
            return WASI_ERRNO_IO;
        }
        ssize_t bytes_written = write(host_fd, mem + buf_ptr, buf_len);
        _lseeki64(host_fd, saved_pos, SEEK_SET);
#else
        ssize_t bytes_written = pwrite(host_fd, mem + buf_ptr, buf_len, (off_t)(offset + total_written));
#endif
        if (bytes_written < 0) {
            *(uint32_t*)(mem + nwritten_ptr) = (uint32_t)total_written;
            return errno_to_wasi(errno);
        }
        total_written += (size_t)bytes_written;
        if ((size_t)bytes_written < buf_len) break;
    }

    *(uint32_t*)(mem + nwritten_ptr) = (uint32_t)total_written;
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_fdstat_set_flags - set fd flags
uint32_t wasi_fd_fdstat_set_flags(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    uint16_t flags = (uint16_t)args[1];

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

#ifndef _WIN32
    int fl = 0;
    if (flags & WASI_FDFLAGS_APPEND) fl |= O_APPEND;
    if (flags & WASI_FDFLAGS_NONBLOCK) fl |= O_NONBLOCK;
#ifdef O_SYNC
    if (flags & WASI_FDFLAGS_SYNC) fl |= O_SYNC;
#endif
#ifdef O_DSYNC
    if (flags & WASI_FDFLAGS_DSYNC) fl |= O_DSYNC;
#endif
    if (fcntl(host_fd, F_SETFL, fl) < 0) return errno_to_wasi(errno);
#endif

    // Update fd_table entry if it exists
    WasiFdEntry* entry = get_fd_entry(fd);
    if (entry) {
        entry->flags = flags;
    }

    return WASI_ERRNO_SUCCESS;
}

// WASI fd_fdstat_set_rights - set fd rights
uint32_t wasi_fd_fdstat_set_rights(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    uint64_t rights_base = args[1];
    uint64_t rights_inheriting = args[2];

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

    WasiFdEntry* entry = get_fd_entry(fd);
    if (entry) {
        entry->rights_base = rights_base;
        entry->rights_inheriting = rights_inheriting;
    }

    return WASI_ERRNO_SUCCESS;
}

// WASI fd_renumber - move fd to another number
uint32_t wasi_fd_renumber(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t to = (uint32_t)args[1];

    if (fd <= 2 || to <= 2) return WASI_ERRNO_BADF;
    if (fd < WASI_MAX_PREOPENS || to < WASI_MAX_PREOPENS) return WASI_ERRNO_BADF;
    if (fd >= MAX_WASI_FDS || to >= MAX_WASI_FDS) return WASI_ERRNO_BADF;
    if (fd == to) return WASI_ERRNO_SUCCESS;

    init_fd_table();
    if (g_fd_table[fd].host_fd < 0) return WASI_ERRNO_BADF;

    if (g_fd_table[to].host_fd >= 0) {
        close(g_fd_table[to].host_fd);
    }

    g_fd_table[to] = g_fd_table[fd];
    g_fd_table[fd].host_fd = -1;
    g_fd_table[fd].filetype = WASI_FILETYPE_UNKNOWN;
    g_fd_table[fd].flags = 0;
    g_fd_table[fd].rights_base = 0;
    g_fd_table[fd].rights_inheriting = 0;

    return WASI_ERRNO_SUCCESS;
}

// WASI fd_filestat_set_size - truncate file
uint32_t wasi_fd_filestat_set_size(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    uint64_t size = args[1];

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

#ifdef _WIN32
    if (_chsize_s(host_fd, (long long)size) != 0) return errno_to_wasi(errno);
#else
    if (ftruncate(host_fd, (off_t)size) < 0) return errno_to_wasi(errno);
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_filestat_set_times - set file timestamps
uint32_t wasi_fd_filestat_set_times(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    uint64_t atim = args[1];
    uint64_t mtim = args[2];
    uint16_t fst_flags = (uint16_t)args[3];

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

#ifndef _WIN32
    struct timespec times[2];
    // Access time
    if (fst_flags & 1) {  // FSTFLAGS_ATIM_NOW
        times[0].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 2) {  // FSTFLAGS_ATIM
        times[0].tv_sec = (time_t)(atim / 1000000000ULL);
        times[0].tv_nsec = (long)(atim % 1000000000ULL);
    } else {
        times[0].tv_nsec = UTIME_OMIT;
    }
    // Modification time
    if (fst_flags & 4) {  // FSTFLAGS_MTIM_NOW
        times[1].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 8) {  // FSTFLAGS_MTIM
        times[1].tv_sec = (time_t)(mtim / 1000000000ULL);
        times[1].tv_nsec = (long)(mtim % 1000000000ULL);
    } else {
        times[1].tv_nsec = UTIME_OMIT;
    }
    if (futimens(host_fd, times) < 0) return errno_to_wasi(errno);
#else
    (void)atim;
    (void)mtim;
    (void)fst_flags;
    // Windows: simplified - not fully implemented
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_advise - provide file access advice (hint)
uint32_t wasi_fd_advise(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    // uint64_t offset = args[1];
    // uint64_t len = args[2];
    // uint8_t advice = (uint8_t)args[3];

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

    // Advisory only - implementations may ignore
    // posix_fadvise could be used on Linux, but we'll just succeed
    return WASI_ERRNO_SUCCESS;
}

// WASI fd_allocate - allocate space for a file
uint32_t wasi_fd_allocate(uint64_t* args) {
    uint32_t fd = (uint32_t)args[0];
    uint64_t offset = args[1];
    uint64_t len = args[2];

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

#if defined(__linux__)
    if (posix_fallocate(host_fd, (off_t)offset, (off_t)len) != 0) {
        return errno_to_wasi(errno);
    }
#elif defined(__APPLE__)
    // macOS: use ftruncate to extend if needed
    struct stat st;
    if (fstat(host_fd, &st) < 0) return errno_to_wasi(errno);
    uint64_t new_size = offset + len;
    if ((uint64_t)st.st_size < new_size) {
        if (ftruncate(host_fd, (off_t)new_size) < 0) return errno_to_wasi(errno);
    }
#else
    (void)offset;
    (void)len;
    return WASI_ERRNO_NOSYS;
#endif
    return WASI_ERRNO_SUCCESS;
}

// WASI clock_res_get - get clock resolution
uint32_t wasi_clock_res_get(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t clock_id = (uint32_t)args[0];
    uint32_t res_ptr = (uint32_t)args[1];

    if (res_ptr + 8 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;

    if (clock_id != WASI_CLOCKID_REALTIME && clock_id != WASI_CLOCKID_MONOTONIC) {
        return WASI_ERRNO_INVAL;
    }

    uint64_t resolution;
#ifdef _WIN32
    resolution = 1000000;  // 1ms default for Windows
#else
    struct timespec ts;
    clockid_t clk = (clock_id == WASI_CLOCKID_REALTIME) ? CLOCK_REALTIME : CLOCK_MONOTONIC;
    if (clock_getres(clk, &ts) < 0) {
        resolution = 1000000;  // 1ms fallback
    } else {
        resolution = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
    }
#endif

    *(uint64_t*)(mem + res_ptr) = resolution;
    return WASI_ERRNO_SUCCESS;
}

// WASI proc_raise - raise a signal
uint32_t wasi_proc_raise(uint64_t* args) {
    (void)args;  // Signal number ignored for now
    // Most implementations just return NOSYS for security reasons
    return WASI_ERRNO_NOSYS;
}

// WASI fd_readdir - read directory entries
// This is complex due to the cookie-based iteration and marshaling
uint32_t wasi_fd_readdir(uint64_t* args, uint8_t* mem, int mem_size) {
    uint32_t fd = (uint32_t)args[0];
    uint32_t buf_ptr = (uint32_t)args[1];
    uint32_t buf_len = (uint32_t)args[2];
    uint64_t cookie = args[3];
    uint32_t bufused_ptr = (uint32_t)args[4];

    if (buf_ptr + buf_len > (uint32_t)mem_size) return WASI_ERRNO_INVAL;
    if (bufused_ptr + 4 > (uint32_t)mem_size) return WASI_ERRNO_INVAL;

    int host_fd = get_host_fd(fd);
    if (host_fd < 0) return WASI_ERRNO_BADF;

#ifdef _WIN32
    // Windows: not implemented
    *(uint32_t*)(mem + bufused_ptr) = 0;
    return WASI_ERRNO_NOSYS;
#else
    // Open directory from fd
    DIR* dir = fdopendir(dup(host_fd));
    if (!dir) return errno_to_wasi(errno);

    // Seek to cookie position
    if (cookie > 0) {
        seekdir(dir, (long)cookie);
    }

    uint32_t bufused = 0;
    struct dirent* entry;
    while ((entry = readdir(dir)) != NULL && bufused < buf_len) {
        // WASI dirent structure:
        // d_next: u64 (cookie for next entry)
        // d_ino: u64
        // d_namlen: u32
        // d_type: u8
        // name follows (not null-terminated in buffer)
        size_t name_len = strlen(entry->d_name);
        size_t entry_size = 24 + name_len;  // 8 + 8 + 4 + 1 + padding + name

        if (bufused + entry_size > buf_len) break;

        uint8_t* out = mem + buf_ptr + bufused;
        uint64_t next_cookie = (uint64_t)telldir(dir);
        *(uint64_t*)(out + 0) = next_cookie;  // d_next
        *(uint64_t*)(out + 8) = entry->d_ino;  // d_ino
        *(uint32_t*)(out + 16) = (uint32_t)name_len;  // d_namlen

        // Map d_type to WASI filetype
        uint8_t filetype = WASI_FILETYPE_UNKNOWN;
        switch (entry->d_type) {
            case DT_REG: filetype = WASI_FILETYPE_REGULAR_FILE; break;
            case DT_DIR: filetype = WASI_FILETYPE_DIRECTORY; break;
            case DT_LNK: filetype = WASI_FILETYPE_SYMBOLIC_LINK; break;
            case DT_CHR: filetype = WASI_FILETYPE_CHARACTER_DEVICE; break;
            case DT_BLK: filetype = WASI_FILETYPE_BLOCK_DEVICE; break;
            case DT_SOCK: filetype = WASI_FILETYPE_SOCKET_STREAM; break;
            default: filetype = WASI_FILETYPE_UNKNOWN; break;
        }
        out[20] = filetype;  // d_type

        // Copy name (at offset 24, after padding)
        memcpy(out + 24, entry->d_name, name_len);

        bufused += (uint32_t)entry_size;
    }

    closedir(dir);
    *(uint32_t*)(mem + bufused_ptr) = bufused;
    return WASI_ERRNO_SUCCESS;
#endif
}
