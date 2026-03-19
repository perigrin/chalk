/* ABOUTME: Shared header for all Chalk C implementation files.
   ABOUTME: Includes Perl API, defines CHALK_FIELD macro for ObjectFIELDS access. */
#ifndef CHALK_H
#define CHALK_H

#include "EXTERN.h"
#include "perl.h"
/* XSUB.h is required even in .c files: on threaded perls it redefines
   aTHX to PERL_GET_THX, which is needed for the pTHX_/aTHX_ macros
   used in every function signature. */
#include "XSUB.h"

/* Field access macro — wraps ObjectFIELDS for readability.
   Usage: CHALK_FIELD(self, 0) to access field at index 0. */
#define CHALK_FIELD(self, idx) ObjectFIELDS(SvRV(self))[idx]

/* Perl 5.42 class C API is declared in proto.h (included via perl.h).
   No additional forward declarations needed here. */

#endif /* CHALK_H */
