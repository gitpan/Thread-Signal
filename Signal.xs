#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = Thread::Signal       PACKAGE = Thread::Signal

#----------------------------------------------------------------------
# OUT: 1 pid of current thread

int
_threadpid()

    PROTOTYPE: ;$
    CODE:
        RETVAL = getpid();
    OUTPUT:
        RETVAL
