#import "SNSingleCopy.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

/* Opened and never closed: the lock is the open file's, let go of with it
   when the process ends. */
BOOL SNLockFileForLife(NSString *path) {
    int file = open(path.fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (file < 0) return YES;
    if (flock(file, LOCK_EX | LOCK_NB) == 0) return YES;
    int why = errno;
    close(file);
    return why != EWOULDBLOCK;
}
