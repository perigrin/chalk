# ABOUTME: Tests the Chalk PadAccess cross-graph identity contract (Phase 4b-2).
# ABOUTME: A pad slot's identity is its variable name, not the CV-local pad index (targ).
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node::PadAccess;

# Phase 4b-2: `targ` is the Perl pad-slot index, which is CV-local and unstable
# across compilation units. It must NOT be identity-bearing, so that B::SoN IR
# loaded into Chalk hash-conses two semantically identical reads together. No
# Chalk consumer (LLVM backend, scheduler, elaborator) reads targ behaviorally;
# they resolve PadAccess -> VarDecl via inputs[0]. See PadAccess::content_hash.

my $a = Chalk::IR::Node::PadAccess->new(id => 'pad_a', targ => 1, varname => '$x');
my $b = Chalk::IR::Node::PadAccess->new(id => 'pad_b', targ => 2, varname => '$x');

isnt($a->targ, $b->targ, 'the two reads have different pad indices (the instability)');
is($a->content_hash, $b->content_hash,
    'identical varname + inputs produce identical content_hash despite different targ');

# targ is preserved as a (non-identity) field for diagnostics / round-trip.
is($a->targ, 1, 'targ still readable');
is($a->varname, '$x', 'varname still readable');

# Regression guard: distinct variable names stay distinct.
my $y = Chalk::IR::Node::PadAccess->new(id => 'pad_y', targ => 1, varname => '$y');
isnt($a->content_hash, $y->content_hash,
    'different variable names produce different identity');

done_testing();
