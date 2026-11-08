#import "SNSingleCopy.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

/* Opened and never closed: the lock is the handle's, let go of with it
   when the process ends. */
BOOL SNLockFileForLife(NSString *path) {
    NSUInteger length = path.length;
    unichar *wide = calloc(length + 1, sizeof(unichar));
    [path getCharacters:wide range:NSMakeRange(0, length)];
    HANDLE file = CreateFileW((LPCWSTR)wide, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    free(wide);
    if (file == INVALID_HANDLE_VALUE) return YES;
    OVERLAPPED from = {0};
    if (LockFileEx(file, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0, &from)) return YES;
    DWORD why = GetLastError();
    CloseHandle(file);
    return why != ERROR_LOCK_VIOLATION;
}
