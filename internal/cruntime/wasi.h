// WASI (WebAssembly System Interface) implementation for wasm5
// This file contains all WASI-related constants, types, and function declarations

#ifndef WASI_H
#define WASI_H

#include <stdint.h>

// ============================================================================
// WASI Handler IDs (must match runtime.mbt)
// ============================================================================

#define HOST_IMPORT_WASI_ARGS_GET           8
#define HOST_IMPORT_WASI_ARGS_SIZES_GET     9
#define HOST_IMPORT_WASI_ENVIRON_GET        10
#define HOST_IMPORT_WASI_ENVIRON_SIZES_GET  11
#define HOST_IMPORT_WASI_FD_WRITE           12
#define HOST_IMPORT_WASI_FD_READ            13
#define HOST_IMPORT_WASI_FD_CLOSE           14
#define HOST_IMPORT_WASI_FD_PRESTAT_GET     15
#define HOST_IMPORT_WASI_FD_PRESTAT_DIR_NAME 16
#define HOST_IMPORT_WASI_FD_FDSTAT_GET      17
#define HOST_IMPORT_WASI_PROC_EXIT          18
#define HOST_IMPORT_WASI_CLOCK_TIME_GET     19
#define HOST_IMPORT_WASI_RANDOM_GET         20
#define HOST_IMPORT_WASI_PATH_OPEN          21
#define HOST_IMPORT_WASI_FD_SEEK            22
#define HOST_IMPORT_WASI_FD_TELL            23
#define HOST_IMPORT_WASI_FD_FILESTAT_GET    24
#define HOST_IMPORT_WASI_PATH_FILESTAT_GET  25
#define HOST_IMPORT_WASI_FD_SYNC            26
#define HOST_IMPORT_WASI_FD_DATASYNC        27
#define HOST_IMPORT_WASI_SCHED_YIELD        28
#define HOST_IMPORT_WASI_PATH_CREATE_DIRECTORY 29
#define HOST_IMPORT_WASI_PATH_REMOVE_DIRECTORY 30
#define HOST_IMPORT_WASI_PATH_UNLINK_FILE   31
#define HOST_IMPORT_WASI_PATH_RENAME        32
#define HOST_IMPORT_WASI_FD_FDSTAT_SET_FLAGS 33
#define HOST_IMPORT_WASI_FD_PREAD           34
#define HOST_IMPORT_WASI_FD_PWRITE          35
#define HOST_IMPORT_WASI_FD_READDIR         36
#define HOST_IMPORT_WASI_FD_FILESTAT_SET_SIZE 37
#define HOST_IMPORT_WASI_FD_FILESTAT_SET_TIMES 38
#define HOST_IMPORT_WASI_FD_ADVISE          39
#define HOST_IMPORT_WASI_FD_ALLOCATE        40
#define HOST_IMPORT_WASI_CLOCK_RES_GET      42
#define HOST_IMPORT_WASI_PROC_RAISE         47

// ============================================================================
// WASI Error Codes
// ============================================================================

#define WASI_ERRNO_SUCCESS    0
#define WASI_ERRNO_ACCES      2    // Permission denied
#define WASI_ERRNO_BADF       8
#define WASI_ERRNO_EXIST      20   // File exists
#define WASI_ERRNO_INVAL      28
#define WASI_ERRNO_IO         29   // I/O error
#define WASI_ERRNO_ISDIR      31
#define WASI_ERRNO_NAMETOOLONG 37  // Filename too long
#define WASI_ERRNO_NFILE      41   // Too many open files in system
#define WASI_ERRNO_NOENT      44   // No such file or directory
#define WASI_ERRNO_NOSPC      51   // No space left on device
#define WASI_ERRNO_NOSYS      52
#define WASI_ERRNO_NOTDIR     54
#define WASI_ERRNO_NOTEMPTY   55   // Directory not empty
#define WASI_ERRNO_PERM       63   // Operation not permitted
#define WASI_ERRNO_ROFS       69   // Read-only file system
#define WASI_ERRNO_SPIPE      70   // Invalid seek (pipe)

// ============================================================================
// WASI File Descriptor Types
// ============================================================================

#define WASI_FILETYPE_UNKNOWN          0
#define WASI_FILETYPE_BLOCK_DEVICE     1
#define WASI_FILETYPE_CHARACTER_DEVICE 2
#define WASI_FILETYPE_DIRECTORY        3
#define WASI_FILETYPE_REGULAR_FILE     4
#define WASI_FILETYPE_SOCKET_DGRAM     5
#define WASI_FILETYPE_SOCKET_STREAM    6
#define WASI_FILETYPE_SYMBOLIC_LINK    7

// ============================================================================
// WASI Rights (simplified - just the commonly used ones)
// ============================================================================

#define WASI_RIGHTS_FD_READ             (1ULL << 1)
#define WASI_RIGHTS_FD_WRITE            (1ULL << 6)
#define WASI_RIGHTS_FD_SEEK             (1ULL << 2)
#define WASI_RIGHTS_FD_FDSTAT_SET_FLAGS (1ULL << 3)
#define WASI_RIGHTS_PATH_OPEN           (1ULL << 13)

// ============================================================================
// WASI Clock IDs
// ============================================================================

#define WASI_CLOCKID_REALTIME  0
#define WASI_CLOCKID_MONOTONIC 1

// ============================================================================
// WASI Preopen Type
// ============================================================================

#define WASI_PREOPENTYPE_DIR 0

// ============================================================================
// WASI Open Flags (oflags)
// ============================================================================

#define WASI_OFLAGS_CREAT     1
#define WASI_OFLAGS_DIRECTORY 2
#define WASI_OFLAGS_EXCL      4
#define WASI_OFLAGS_TRUNC     8

// ============================================================================
// WASI FD Flags (fdflags)
// ============================================================================

#define WASI_FDFLAGS_APPEND   1
#define WASI_FDFLAGS_DSYNC    2
#define WASI_FDFLAGS_NONBLOCK 4
#define WASI_FDFLAGS_RSYNC    8
#define WASI_FDFLAGS_SYNC     16

// ============================================================================
// Public WASI API (called from MoonBit FFI)
// ============================================================================

// Initialize WASI context with command-line arguments
void wasi_init(int argc, char** argv);

// Get WASI exit code (after proc_exit)
int wasi_get_exit_code(void);

// Check if WASI has exited (via proc_exit)
int wasi_has_exited(void);

// Initialize WASI with empty arguments
void wasi_init_empty(void);

// Add a preopened file to the WASI environment
// Returns the WASI fd number (3+) or -1 on error
int wasi_add_preopen_file(int host_fd, const char* path);

// FFI wrapper for wasi_add_preopen_file without path (for testing)
int wasi_add_preopen_file_ffi(int host_fd);

// Reset preopens to just stdin/stdout/stderr
void wasi_reset_preopens(void);

// ============================================================================
// WASI Syscall Implementations (called from op_call_import)
// ============================================================================

uint32_t wasi_args_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_args_sizes_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_environ_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_environ_sizes_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_write(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_read(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_close(uint64_t* args);
uint32_t wasi_fd_prestat_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_prestat_dir_name(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_fdstat_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_proc_exit(uint64_t* args);
uint32_t wasi_clock_time_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_random_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_path_open(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_seek(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_tell(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_filestat_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_path_filestat_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_sync(uint64_t* args);
uint32_t wasi_fd_datasync(uint64_t* args);
uint32_t wasi_sched_yield(void);
uint32_t wasi_path_create_directory(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_path_remove_directory(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_path_unlink_file(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_path_rename(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_fdstat_set_flags(uint64_t* args);
uint32_t wasi_fd_pread(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_pwrite(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_readdir(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_fd_filestat_set_size(uint64_t* args);
uint32_t wasi_fd_filestat_set_times(uint64_t* args);
uint32_t wasi_fd_advise(uint64_t* args);
uint32_t wasi_fd_allocate(uint64_t* args);
uint32_t wasi_clock_res_get(uint64_t* args, uint8_t* mem, int mem_size);
uint32_t wasi_proc_raise(uint64_t* args);

#endif // WASI_H
