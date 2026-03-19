/* ABOUTME: Thin XS wrapper for Boolean semiring C implementation.
   ABOUTME: XSUBs delegate to boolean_*() functions in chalk.so. */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "boolean.h"

/* Perl_class_setup_stash is in proto.h but guarded by PERL_IN_CLASS_C etc.
   Forward-declare it directly so BOOT can call it from external XS code. */
extern void Perl_class_setup_stash(pTHX_ HV *stash);

MODULE = Chalk::Bootstrap::Semiring::Boolean  PACKAGE = Chalk::Bootstrap::Semiring::Boolean

PROTOTYPES: DISABLE

SV *
zero(self)
    SV *self
  CODE:
    RETVAL = boolean_zero(aTHX_ self);
  OUTPUT:
    RETVAL

SV *
one(self)
    SV *self
  CODE:
    RETVAL = boolean_one(aTHX_ self);
  OUTPUT:
    RETVAL

SV *
is_zero(self, value)
    SV *self
    SV *value
  CODE:
    RETVAL = boolean_is_zero(aTHX_ self, value);
  OUTPUT:
    RETVAL

SV *
multiply(self, left, right)
    SV *self
    SV *left
    SV *right
  CODE:
    RETVAL = boolean_multiply(aTHX_ self, left, right);
  OUTPUT:
    RETVAL

SV *
add(self, left, right)
    SV *self
    SV *left
    SV *right
  CODE:
    RETVAL = boolean_add(aTHX_ self, left, right);
  OUTPUT:
    RETVAL

SV *
on_scan(self, item, alt_idx, pos, matched_text)
    SV *self
    SV *item
    SV *alt_idx
    SV *pos
    SV *matched_text
  CODE:
    RETVAL = boolean_on_scan(aTHX_ self, item, alt_idx, pos, matched_text);
  OUTPUT:
    RETVAL

SV *
on_complete(self, item, alt_idx, pos, ...)
    SV *self
    SV *item
    SV *alt_idx
    SV *pos
  CODE:
    SV *on_epoch_commit = items > 4 ? ST(4) : &PL_sv_undef;
    RETVAL = boolean_on_complete(aTHX_ self, item, alt_idx, pos, on_epoch_commit);
  OUTPUT:
    RETVAL

SV *
should_scan(self, item, alt_idx, pos, matched_text, is_predicted)
    SV *self
    SV *item
    SV *alt_idx
    SV *pos
    SV *matched_text
    SV *is_predicted
  CODE:
    RETVAL = boolean_should_scan(aTHX_ self, item, alt_idx, pos, matched_text, is_predicted);
  OUTPUT:
    RETVAL

SV *
supports_leo(self)
    SV *self
  CODE:
    RETVAL = boolean_supports_leo(aTHX_ self);
  OUTPUT:
    RETVAL

BOOT:
{
    HV *stash = gv_stashpv("Chalk::Bootstrap::Semiring::Boolean", GV_ADD);
    HV *old_stash = PL_curstash;
    PL_curstash = stash;
    ENTER;
    Perl_class_setup_stash(aTHX_ stash);

    /* Boolean has no fields, no ADJUST — just seal the class */

    LEAVE;  /* triggers seal_stash via SAVEDESTRUCTOR_X */
    PL_curstash = old_stash;
}
