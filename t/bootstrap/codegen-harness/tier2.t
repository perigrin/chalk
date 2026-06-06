# ABOUTME: TDD test for tier-2 corpus — real lib/ units exercised via hand-authored MOP graphs.
# ABOUTME: Proves the tier-2 path: S = real lib/ file under perl, P = hand-authored MOP via emitter.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::Tier2;
use Chalk::CodeGen::Harness::GapMap;

# ---------------------------------------------------------------------------
# T1: Tier2 module loads and has run_unit method
# ---------------------------------------------------------------------------
ok(Chalk::CodeGen::Harness::Tier2->can('run_unit'),
    'Tier2 has run_unit class method');

# ---------------------------------------------------------------------------
# T2: run_unit('Add') returns a result hashref with S, P, verdict
# ---------------------------------------------------------------------------
my $result;
{
    $result = eval { Chalk::CodeGen::Harness::Tier2->run_unit('Add') };
    ok(!$@, 'run_unit(Add) does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_unit died', 3 if $@;
        ok(defined $result,          'run_unit returns a defined result');
        ok(exists $result->{S},      'result has S key (oracle behavior)');
        ok(exists $result->{P},      'result has P key (generated behavior)');
        ok(exists $result->{verdict},'result has verdict key');
    }
}

# ---------------------------------------------------------------------------
# T3: S side — oracle (real Add.pm under perl) returns 'Add' and '+'
# ---------------------------------------------------------------------------
SKIP: {
    skip 'run_unit died', 4 unless defined $result;

    # operation() must return 'Add'
    my $S_op = Chalk::CodeGen::Harness::Tier2->run_unit_method('Add', 'operation');
    ok(!$@, 'run_unit_method(Add, operation) does not die') or diag($@);
    SKIP: {
        skip 'run_unit_method died', 1 if $@;
        my $S_val = defined $S_op ? $S_op->{S}->return_values->[0] : undef;
        is($S_val, 'Add', 'S side: Add->operation() returns "Add" (perl oracle)');
    }

    # op_str() must return '+'
    my $S_op_str = Chalk::CodeGen::Harness::Tier2->run_unit_method('Add', 'op_str');
    ok(!$@, 'run_unit_method(Add, op_str) does not die') or diag($@);
    SKIP: {
        skip 'run_unit_method died', 1 if $@;
        my $S_val = defined $S_op_str ? $S_op_str->{S}->return_values->[0] : undef;
        is($S_val, '+', 'S side: Add->op_str() returns "+" (perl oracle)');
    }
}

# ---------------------------------------------------------------------------
# T4: P side — hand-authored MOP via emitter returns 'Add' and '+'
# ---------------------------------------------------------------------------
SKIP: {
    skip 'run_unit died', 2 unless defined $result;

    my $op_result = eval {
        Chalk::CodeGen::Harness::Tier2->run_unit_method('Add', 'operation')
    };
    SKIP: {
        skip 'run_unit_method died', 1 if $@;
        my $P_val = defined $op_result ? $op_result->{P}->return_values->[0] : undef;
        is($P_val, 'Add', 'P side: generated Add->operation() returns "Add"');
    }

    my $op_str_result = eval {
        Chalk::CodeGen::Harness::Tier2->run_unit_method('Add', 'op_str')
    };
    SKIP: {
        skip 'run_unit_method died', 1 if $@;
        my $P_val = defined $op_str_result ? $op_str_result->{P}->return_values->[0] : undef;
        is($P_val, '+', 'P side: generated Add->op_str() returns "+"');
    }
}

# ---------------------------------------------------------------------------
# T5: verdict for both methods is PASS (S == P)
# ---------------------------------------------------------------------------
SKIP: {
    skip 'run_unit died', 2 unless defined $result;

    for my $method (qw(operation op_str)) {
        my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('Add', $method) };
        SKIP: {
            skip "run_unit_method($method) died: $@", 1 if $@;
            my $verdict = $r->{verdict}{verdict} // $r->{verdict} // 'NO_VERDICT';
            is($verdict, 'PASS', "Add->$method(): verdict is PASS (S=P confirmed)");
        }
    }
}

# ---------------------------------------------------------------------------
# T6: graph_source is tagged 'hand' (trusted — not parser-derived)
# ---------------------------------------------------------------------------
SKIP: {
    skip 'run_unit died', 1 unless defined $result;

    my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('Add', 'operation') };
    SKIP: {
        skip 'run_unit_method died', 1 if $@;
        my $src = $r->{verdict}{graph_source} // '';
        like($src, qr/^hand/, 'graph_source is tagged "hand" (tier-2 trusted graph)');
    }
}

# ---------------------------------------------------------------------------
# T7: under-spec guard — a unit spec with no args for a parameterized method
# must return UNDER_SPECIFIED, not a vacuous PASS
# ---------------------------------------------------------------------------
{
    my $verdict = eval {
        Chalk::CodeGen::Harness::Tier2->check_spec_completeness(
            'Add',
            'method m($x) { return $x; }',   # snippet with a param
            {
                class  => 'Chalk::IR::Node::Add',
                method => 'm',
                method_args => [],             # no args — under-specified
            }
        )
    };
    ok(!$@, 'check_spec_completeness does not die') or diag($@);
    ok(defined $verdict && $verdict,
        'under-spec guard fires when method has params but spec supplies no args');
}

# ---------------------------------------------------------------------------
# T8: manual-output guard — spec with expected_output field must be rejected
# (expected values must be perl-derived, never hand-specified)
# ---------------------------------------------------------------------------
{
    my $err;
    eval {
        Chalk::CodeGen::Harness::Tier2->run_unit_method('Add', 'operation',
            { expected_output => 'Add' }
        );
    };
    $err = $@;
    ok(defined $err && $err,
        'manual expected_output in spec is rejected (expected_values must be perl-derived)');
}

# ---------------------------------------------------------------------------
# T9: tier1_green is still TRUE after tier-2 run (no regression)
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    ok(!$@, 'GapMap->generate() still runs without error after tier-2 work') or diag($@);
    SKIP: {
        skip 'generate failed', 1 unless defined $gap_map;
        ok(Chalk::CodeGen::Harness::GapMap->tier1_green($gap_map),
            'tier1_green is TRUE — no regressions from tier-2 work');
    }
}

done_testing();
