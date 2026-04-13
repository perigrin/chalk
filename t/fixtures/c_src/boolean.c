/* ABOUTME: C implementation of Boolean recognition semiring.
   ABOUTME: Provides zero, one, multiply, add with reference-based zero detection.

   STALE (post-Step-B of the unified-context refactor, 2026-04-12):
   This file still implements the pre-Step-B Boolean API where multiply/add
   return bare PL_sv_yes / an AV-ref ZERO sentinel. The Perl-side Boolean
   semiring now returns Chalk::Bootstrap::Context objects so every semiring
   obeys the `(Context, Context) -> Context` invariant. These fixtures will
   be regenerated from lib/Chalk/Bootstrap/BNF/Target/C.pm in Step C and
   should not be hand-edited to match the new API — the codegen path is
   the source of truth. */
#include "chalk.h"
#include "boolean.h"

/* File-scope static: the unique ZERO reference (an empty AV).
   Initialized lazily on first call to boolean_zero().
   NOTE: This is a process-global static. On threaded perls with multiple
   interpreters, this would need MY_CXT for per-interpreter storage.
   Acceptable for this single-interpreter proof of concept. */
static SV *_boolean_ZERO = NULL;

static SV * _get_zero(pTHX) {
    if (!_boolean_ZERO) {
        AV *av = newAV();
        _boolean_ZERO = newRV_noinc((SV*)av);
        /* No SvREADONLY — matches Perl Boolean.pm behavior where $ZERO = [] is mutable */
    }
    return _boolean_ZERO;
}

SV * boolean_zero(pTHX_ SV *self) {
    PERL_UNUSED_ARG(self);
    /* Return with incremented refcount: XS RETVAL path calls sv_2mortal
       which would free the value otherwise. */
    return SvREFCNT_inc(_get_zero(aTHX));
}

SV * boolean_one(pTHX_ SV *self) {
    PERL_UNUSED_ARG(self);
    return &PL_sv_yes;
}

SV * boolean_is_zero(pTHX_ SV *self, SV *value) {
    PERL_UNUSED_ARG(self);
    SV *zero = _get_zero(aTHX);
    /* Reference equality: compare refaddr */
    if (!SvROK(value)) return &PL_sv_no;
    if (!SvROK(zero)) return &PL_sv_no;
    return (SvRV(value) == SvRV(zero)) ? &PL_sv_yes : &PL_sv_no;
}

SV * boolean_multiply(pTHX_ SV *self, SV *left, SV *right) {
    /* Sequence: if either is zero, result is zero */
    if (SvTRUE(boolean_is_zero(aTHX_ self, left))) return SvREFCNT_inc(_get_zero(aTHX));
    if (SvTRUE(boolean_is_zero(aTHX_ self, right))) return SvREFCNT_inc(_get_zero(aTHX));
    return &PL_sv_yes;
}

SV * boolean_add(pTHX_ SV *self, SV *left, SV *right) {
    /* Alternative: if either is non-zero, result is non-zero */
    if (!SvTRUE(boolean_is_zero(aTHX_ self, left))) return &PL_sv_yes;
    if (!SvTRUE(boolean_is_zero(aTHX_ self, right))) return &PL_sv_yes;
    return SvREFCNT_inc(_get_zero(aTHX));
}

SV * boolean_on_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text) {
    PERL_UNUSED_ARG(alt_idx);
    PERL_UNUSED_ARG(pos);
    PERL_UNUSED_ARG(matched_text);
    /* multiply(item->{value}, one()) */
    HV *item_hv = (HV*)SvRV(item);
    SV **val_ptr = hv_fetchs(item_hv, "value", 0);
    SV *item_value = val_ptr ? *val_ptr : &PL_sv_undef;
    return boolean_multiply(aTHX_ self, item_value, boolean_one(aTHX_ self));
}

SV * boolean_on_complete(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *on_epoch_commit) {
    PERL_UNUSED_ARG(self);
    PERL_UNUSED_ARG(alt_idx);
    PERL_UNUSED_ARG(pos);
    PERL_UNUSED_ARG(on_epoch_commit);
    /* Return item->{value} unchanged; SvREFCNT_inc because XS path calls sv_2mortal */
    HV *item_hv = (HV*)SvRV(item);
    SV **val_ptr = hv_fetchs(item_hv, "value", 0);
    return val_ptr ? SvREFCNT_inc(*val_ptr) : &PL_sv_undef;
}

SV * boolean_should_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text, SV *is_predicted) {
    PERL_UNUSED_ARG(self);
    PERL_UNUSED_ARG(item);
    PERL_UNUSED_ARG(alt_idx);
    PERL_UNUSED_ARG(pos);
    PERL_UNUSED_ARG(matched_text);
    PERL_UNUSED_ARG(is_predicted);
    return &PL_sv_yes;
}

SV * boolean_supports_leo(pTHX_ SV *self) {
    PERL_UNUSED_ARG(self);
    return &PL_sv_yes;
}
