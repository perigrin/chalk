# ABOUTME: Tests that RunUnderPerl->capture returns a fully-populated BehaviorRecord
# ABOUTME: for tier-1 idioms A1 (bare VarDecl) and A5 (VarDecl field) from the corpus.
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib';

use Chalk::CodeGen::Harness::RunUnderPerl;
use Chalk::CodeGen::Harness::BehaviorRecord;

# Short alias for readability in tests
use constant Oracle => 'Chalk::CodeGen::Harness::RunUnderPerl';

# A1: bare VarDecl — simplest possible class method
my $A1_SNIPPET = 'class C { method m() { my $x = 1; return $x; } }';

# Exercise spec: create an instance with no params, call m() in scalar context
my $A1_SPEC = {
    class        => 'C',
    constructor  => { params => {} },
    method       => 'm',
    method_args  => [],
    context      => 'scalar',
};

my $record_a1 = Oracle->capture($A1_SNIPPET, $A1_SPEC);

isa_ok( $record_a1, ['Chalk::CodeGen::Harness::BehaviorRecord'],
    'capture returns a BehaviorRecord' );

# Every named axis must be defined (not undef-by-omission).
# return_values is an arrayref (may be empty list, but must be arrayref)
ok( defined $record_a1->return_values, 'return_values axis is defined' );
ref_ok( $record_a1->return_values, 'ARRAY', 'return_values is an arrayref' );
is( $record_a1->return_values->[0], 1, 'A1 returns 1' );

ok( defined $record_a1->wantarray_context, 'wantarray_context axis is defined' );
is( $record_a1->wantarray_context, 'scalar', 'wantarray_context is scalar' );

ok( defined $record_a1->stdout, 'stdout axis is defined' );
is( $record_a1->stdout, '', 'A1 produces no stdout' );

ok( defined $record_a1->stderr, 'stderr axis is defined' );
is( $record_a1->stderr, '', 'A1 produces no stderr' );

# exception must be undef for a non-dying snippet
is( $record_a1->exception, undef, 'exception is undef for non-dying A1' );

# object_state must be a hashref (possibly empty for class with no fields)
ok( defined $record_a1->object_state, 'object_state axis is defined' );
ref_ok( $record_a1->object_state, 'HASH', 'object_state is a hashref' );

# policy axes must be defined
ok( defined $record_a1->hash_order_policy, 'hash_order_policy axis is defined' );
ok( defined $record_a1->fp_tolerance, 'fp_tolerance axis is defined' );
ok( defined $record_a1->dualvar_policy, 'dualvar_policy axis is defined' );
ok( defined $record_a1->aliasing_topology, 'aliasing_topology axis is defined' );

# A5: VarDecl field — tests :param constructor
my $A5_SNIPPET = 'class C { field $x :param; method m() { return $x; } }';

my $A5_SPEC = {
    class        => 'C',
    constructor  => { params => { x => 42 } },
    method       => 'm',
    method_args  => [],
    context      => 'scalar',
};

my $record_a5 = Oracle->capture($A5_SNIPPET, $A5_SPEC);

isa_ok( $record_a5, ['Chalk::CodeGen::Harness::BehaviorRecord'],
    'A5 capture returns a BehaviorRecord' );
is( $record_a5->return_values->[0], 42, 'A5 returns param value 42' );
is( $record_a5->exception, undef, 'A5 no exception' );

# object_state should reflect the :param field value post-call
ok( defined $record_a5->object_state, 'A5 object_state defined' );

done_testing;
