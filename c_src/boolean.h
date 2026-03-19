/* ABOUTME: Function prototypes for Boolean semiring C implementation.
   ABOUTME: Included by other .c files that call boolean functions directly. */
#ifndef CHALK_BOOLEAN_H
#define CHALK_BOOLEAN_H
#include "chalk.h"

SV * boolean_zero(pTHX_ SV *self);
SV * boolean_one(pTHX_ SV *self);
SV * boolean_is_zero(pTHX_ SV *self, SV *value);
SV * boolean_multiply(pTHX_ SV *self, SV *left, SV *right);
SV * boolean_add(pTHX_ SV *self, SV *left, SV *right);
SV * boolean_on_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text);
SV * boolean_on_complete(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *on_epoch_commit);
SV * boolean_should_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text, SV *is_predicted);
SV * boolean_supports_leo(pTHX_ SV *self);

#endif /* CHALK_BOOLEAN_H */
