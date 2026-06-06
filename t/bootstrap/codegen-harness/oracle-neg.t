# ABOUTME: Adversarial/negative tests for the oracle — guards against false-green scenarios.
# ABOUTME: Tests malformed extraction, non-determinism, empty specs, unobserved axes, exception paths.
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib';

use Chalk::CodeGen::Harness::RunUnderPerl;
use Chalk::CodeGen::Harness::BehaviorRecord;

use constant Oracle => 'Chalk::CodeGen::Harness::RunUnderPerl';

# --- Negative test 1: Malformed extraction (empty body) must REFUSE, not pass vacuously ---
# If extract_snippet returns empty/degenerate content, wrap_program must die or produce an
# error, and capture must propagate that error rather than returning an empty-passing record.
{
    my $empty_snippet = '';  # extraction silently dropped body
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    ok(
        dies { Oracle->capture($empty_snippet, $spec) },
        'capture dies on empty/degenerate snippet (malformed extraction guard)'
    );
}

# --- Negative test 2: Under-specified exercise spec (missing method) must ERROR ---
# An exercise spec with no method field provides nothing to invoke/observe.
{
    my $snippet = 'class C { method m() { my $x = 1; return $x; } }';
    my $bad_spec = {
        class       => 'C',
        constructor => { params => {} },
        # method is absent — nothing to invoke
        method_args => [],
        context     => 'scalar',
    };

    ok(
        dies { Oracle->capture($snippet, $bad_spec) },
        'capture dies when exercise spec has no method (under-specified)'
    );
}

# --- Negative test 3: Under-specified exercise spec (missing class) must ERROR ---
{
    my $snippet = 'class C { method m() { my $x = 1; return $x; } }';
    my $bad_spec = {
        # class is absent
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    ok(
        dies { Oracle->capture($snippet, $bad_spec) },
        'capture dies when exercise spec has no class (under-specified)'
    );
}

# --- Negative test 4: Exception path — die-ing snippet records exception, not crash ---
# B4: bare die — class C { method m() { die "boom"; } }
{
    my $snippet = 'class C { method m() { die "boom"; } }';
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $record = Oracle->capture($snippet, $spec);
    isa_ok( $record, ['Chalk::CodeGen::Harness::BehaviorRecord'],
        'die-ing snippet produces a BehaviorRecord (not a crash)' );
    ok( defined $record->exception, 'exception axis is populated for die-ing snippet' );
    ref_ok( $record->exception, 'HASH', 'exception is a hashref' );
    ok( exists $record->exception->{kind}, 'exception has kind field' );
    ok( exists $record->exception->{message}, 'exception has message field' );
    like( $record->exception->{message}, qr/boom/, 'exception message contains "boom"' );
    is( $record->exception->{kind}, 'string', 'plain die string has kind=string' );
}

# --- Negative test 5: Object exception (die with object) records kind=object + class ---
{
    my $snippet = <<'END_SNIPPET';
class MyError { field $msg :param; method message() { return $msg; } }
class C { method m() { die MyError->new(msg => "bad thing"); } }
END_SNIPPET

    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $record = Oracle->capture($snippet, $spec);
    isa_ok( $record, ['Chalk::CodeGen::Harness::BehaviorRecord'],
        'object-die snippet produces a BehaviorRecord' );
    ok( defined $record->exception, 'exception axis populated for object die' );
    is( $record->exception->{kind}, 'object', 'object die has kind=object' );
    like( $record->exception->{class}, qr/MyError/, 'exception class captured' );
}

# --- Negative test 6: Unobserved-axis STDERR — warn produces non-empty stderr axis ---
# B8: bare warn — class C { method m() { warn "hi"; return 1; } }
{
    my $snippet = 'class C { method m() { warn "hi"; return 1; } }';
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $record = Oracle->capture($snippet, $spec);
    isa_ok( $record, ['Chalk::CodeGen::Harness::BehaviorRecord'],
        'warn snippet produces a BehaviorRecord' );
    ok( defined $record->stderr, 'stderr axis defined for warn snippet' );
    like( $record->stderr, qr/hi/, 'stderr axis contains "hi" from warn' );
    is( $record->return_values->[0], 1, 'return value still captured alongside warn' );
}

# --- Negative test 7: Unobserved-axis STDOUT — print populates stdout axis ---
# B2: bare print
{
    my $snippet = 'class C { method m() { print "hi"; return 1; } }';
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $record = Oracle->capture($snippet, $spec);
    isa_ok( $record, ['Chalk::CodeGen::Harness::BehaviorRecord'],
        'print snippet produces a BehaviorRecord' );
    ok( defined $record->stdout, 'stdout axis defined for print snippet' );
    like( $record->stdout, qr/hi/, 'stdout axis contains "hi" from print' );
}

# --- Negative test 8: Non-deterministic hash output is normalized ---
# A snippet that returns a hashref has its keys sorted by normalize_return_values
# (via normalize_hash_order) so that insertion-order variation doesn't create
# false-stable vs false-unstable comparisons.
# Two captures of a hashref-returning snippet, after normalization, must be identical.
{
    # The snippet returns a hashref — normalize_return_values will sort its keys.
    my $snippet = 'class C { method m() { my %h = (b => 2, a => 1); my $r = \%h; return $r; } }';
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $record1 = Oracle->capture($snippet, $spec);
    my $record2 = Oracle->capture($snippet, $spec);

    isa_ok( $record1, ['Chalk::CodeGen::Harness::BehaviorRecord'],
        'hash snippet produces a BehaviorRecord on run 1' );
    isa_ok( $record2, ['Chalk::CodeGen::Harness::BehaviorRecord'],
        'hash snippet produces a BehaviorRecord on run 2' );

    # normalize_return_values sorts hash keys at every level.
    # Both runs must produce the same normalized structure regardless of hash seed.
    my $norm1 = $record1->normalize_return_values( $record1->return_values );
    my $norm2 = $record2->normalize_return_values( $record2->return_values );
    is( $norm1, $norm2, 'hash_order normalization produces stable return_values across runs' );

    # The normalized hashref must have sorted keys (a before b).
    my $href = $norm1->[0];
    ref_ok( $href, 'HASH', 'normalized return value is a hashref' );
    is( [ sort keys %$href ], [sort keys %$href], 'normalized hash keys are sorted' );
}

# --- Negative test 9: wantarray context is captured correctly ---
# A method called in list context vs scalar context should record different wantarray_context
{
    my $snippet = 'class C { method m() { return (1, 2, 3); } }';

    my $spec_list = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'list',
    };

    my $spec_scalar = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $record_list   = Oracle->capture($snippet, $spec_list);
    my $record_scalar = Oracle->capture($snippet, $spec_scalar);

    is( $record_list->wantarray_context,   'list',   'list context recorded as list' );
    is( $record_scalar->wantarray_context, 'scalar', 'scalar context recorded as scalar' );

    # List context should have multiple return values
    ok( scalar @{ $record_list->return_values } > 1,
        'list context yields multiple return values' );
}

done_testing;
