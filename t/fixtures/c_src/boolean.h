/* ABOUTME: Function prototypes for Chalk::Bootstrap::Semiring::Boolean (generated). */
/* ABOUTME: Included by other .c files for cross-class calls. */
#ifndef CHALK_BOOLEAN_H
#define CHALK_BOOLEAN_H
#include "chalk.h"

SV * boolean_add(pTHX_ SV *self, SV *left, SV *right);
void boolean_init_statics(pTHX);
SV * boolean_is_zero(pTHX_ SV *self, SV *value);
SV * boolean_multiply(pTHX_ SV *self, SV *left, SV *right);
SV * boolean_one(pTHX_ SV *self);
SV * boolean_slot_name(pTHX_ SV *self);
SV * boolean_zero(pTHX_ SV *self);

#endif /* CHALK_BOOLEAN_H */
