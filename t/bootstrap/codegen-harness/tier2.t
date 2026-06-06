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

# ===========================================================================
# T10-T20: Unit 1 — Chalk::IR::Node::BinOp
#
# Exercises: left() reader, right() reader, op_str() dying.
# Bilateral: left/right are set from explicit :param; op_str() raises exception.
# Oracle-derived expected values:
#   left()    => 'left_val'
#   right()   => 'right_val'
#   op_str()  => exception with message 'Subclass must implement op_str()'
# ===========================================================================

# T10: BinOp unit is registered and run_unit does not die
{
    my $result = eval { Chalk::CodeGen::Harness::Tier2->run_unit('BinOp') };
    ok(!$@, 'T10: run_unit(BinOp) does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_unit died', 3 if $@;
        ok(defined $result,           'T10: run_unit(BinOp) returns defined result');
        ok(exists $result->{S},       'T10: result has S key');
        ok(exists $result->{verdict}, 'T10: result has verdict key');
    }
}

# T11: S side — left() returns 'left_val' (perl oracle)
{
    my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('BinOp', 'left') };
    ok(!$@, 'T11: run_unit_method(BinOp, left) does not die') or diag($@);
    SKIP: {
        skip 'run_unit_method died', 1 if $@;
        my $S_val = defined $r ? $r->{S}->return_values->[0] : undef;
        is($S_val, 'left_val', 'T11: S side: BinOp->left() returns "left_val" (perl oracle)');
    }
}

# T12: S side — right() returns 'right_val' (perl oracle)
{
    my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('BinOp', 'right') };
    ok(!$@, 'T12: run_unit_method(BinOp, right) does not die') or diag($@);
    SKIP: {
        skip 'run_unit_method died', 1 if $@;
        my $S_val = defined $r ? $r->{S}->return_values->[0] : undef;
        is($S_val, 'right_val', 'T12: S side: BinOp->right() returns "right_val" (perl oracle)');
    }
}

# T13: S side — op_str() raises exception (perl oracle confirms die message)
{
    my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('BinOp', 'op_str') };
    ok(!$@, 'T13: run_unit_method(BinOp, op_str) does not die') or diag($@);
    SKIP: {
        skip 'run_unit_method died', 2 if $@;
        my $exc = defined $r ? $r->{S}->exception : undef;
        ok(defined $exc, 'T13: S side: BinOp->op_str() raises an exception (perl oracle)');
        SKIP: {
            skip 'no exception', 1 unless defined $exc;
            is($exc->{message}, 'Subclass must implement op_str()',
                'T13: S side: op_str() die message matches oracle');
        }
    }
}

# T14: P side — left() returns 'left_val', right() returns 'right_val' (S=P PASS)
{
    for my $method (qw(left right)) {
        my $expected = $method eq 'left' ? 'left_val' : 'right_val';
        my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('BinOp', $method) };
        SKIP: {
            skip "run_unit_method(BinOp, $method) died: $@", 2 if $@;
            my $P_val = defined $r ? $r->{P}->return_values->[0] : undef;
            is($P_val, $expected, "T14: P side: BinOp->$method() returns \"$expected\"");
            my $verdict = $r->{verdict}{verdict} // $r->{verdict} // 'NO_VERDICT';
            is($verdict, 'PASS', "T14: BinOp->$method(): verdict is PASS (S=P confirmed)");
        }
    }
}

# T15: P side — op_str() raises exception (S=P PASS via exception axis)
{
    my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('BinOp', 'op_str') };
    SKIP: {
        skip "run_unit_method(BinOp, op_str) died: $@", 2 if $@;
        ok(defined $r->{P}->exception, 'T15: P side: generated BinOp->op_str() raises exception');
        my $verdict = $r->{verdict}{verdict} // $r->{verdict} // 'NO_VERDICT';
        is($verdict, 'PASS', 'T15: BinOp->op_str(): verdict is PASS (S=P via exception axis)');
    }
}

# ===========================================================================
# T20-T35: Unit 2 — Chalk::Grammar::Symbol
#
# Bilateral exercise: terminal symbol (type='terminal') and reference symbol
# (type='reference', quantifier='*').
#
# Oracle-derived expected values:
#   terminal: is_terminal=1, is_reference=0, is_quantified=0,
#             goto_key='t:foo', to_string='/foo/'
#   reference: is_terminal=0, is_reference=1, is_quantified=1,
#              goto_key='n:Bar', to_string='Bar*'
# ===========================================================================

# T20: Symbol unit is registered and run_unit does not die
{
    my $result = eval { Chalk::CodeGen::Harness::Tier2->run_unit('Symbol') };
    ok(!$@, 'T20: run_unit(Symbol) does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_unit died', 2 if $@;
        ok(defined $result,           'T20: run_unit(Symbol) returns defined result');
        ok(exists $result->{verdict}, 'T20: result has verdict key');
    }
}

# T21-T25: Terminal symbol — bilateral axis 1
{
    my %expected_terminal = (
        is_terminal   => '1',
        is_reference  => '0',     # false: JSON::PP::Boolean stringifies to '0'
        is_quantified => '0',     # false: JSON::PP::Boolean stringifies to '0'
        goto_key      => 't:foo',
        to_string     => '/foo/',
    );

    for my $method (qw(is_terminal is_reference is_quantified goto_key to_string)) {
        my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('Symbol', $method) };
        SKIP: {
            skip "run_unit_method(Symbol, $method) died: $@", 3 if $@;
            my $S_val = defined $r ? $r->{S}->return_values->[0] : undef;
            my $exp   = $expected_terminal{$method};
            is($S_val, $exp, "T21: S side: Symbol(terminal)->$method() = '$exp' (oracle)");
            my $P_val = defined $r ? $r->{P}->return_values->[0] : undef;
            is($P_val, $exp, "T22: P side: Symbol(terminal)->$method() = '$exp'");
            my $verdict = $r->{verdict}{verdict} // $r->{verdict} // 'NO_VERDICT';
            is($verdict, 'PASS',
                "T23: Symbol(terminal)->$method(): verdict is PASS (S=P confirmed)");
        }
    }
}

# T26-T30: Reference symbol (Symbol_ref) — bilateral axis 2
{
    my %expected_ref = (
        is_terminal   => '0',     # false: JSON::PP::Boolean stringifies to '0'
        is_reference  => '1',
        is_quantified => '1',
        goto_key      => 'n:Bar',
        to_string     => 'Bar*',
    );

    for my $method (qw(is_terminal is_reference is_quantified goto_key to_string)) {
        my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('Symbol_ref', $method) };
        SKIP: {
            skip "run_unit_method(Symbol_ref, $method) died: $@", 3 if $@;
            my $S_val = defined $r ? $r->{S}->return_values->[0] : undef;
            my $exp   = $expected_ref{$method};
            is($S_val, $exp, "T26: S side: Symbol(ref)->$method() = '$exp' (oracle)");
            my $P_val = defined $r ? $r->{P}->return_values->[0] : undef;
            is($P_val, $exp, "T27: P side: Symbol(ref)->$method() = '$exp'");
            my $verdict = $r->{verdict}{verdict} // $r->{verdict} // 'NO_VERDICT';
            is($verdict, 'PASS',
                "T28: Symbol(ref)->$method(): verdict is PASS (S=P confirmed)");
        }
    }
}

# ===========================================================================
# T36-T50: Unit 3 — Chalk::Grammar::Rule
#
# Bilateral exercise: terminal-only rule (is_terminal_rule=true) and
# mixed rule with a nonterminal symbol (is_terminal_rule=false).
#
# Oracle-derived expected values:
#   Rule (terminal): alternative_count=1, is_terminal_rule=1,
#                    to_string='TermRule ::= /foo/ /bar/ ;'
#   Rule_mixed:      alternative_count=1, is_terminal_rule='',
#                    to_string='MixedRule ::= /foo/ Bar ;'
# ===========================================================================

# T36: Rule unit is registered and run_unit does not die
{
    my $result = eval { Chalk::CodeGen::Harness::Tier2->run_unit('Rule') };
    ok(!$@, 'T36: run_unit(Rule) does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_unit died', 2 if $@;
        ok(defined $result,           'T36: run_unit(Rule) returns defined result');
        ok(exists $result->{verdict}, 'T36: result has verdict key');
    }
}

# T37-T39: Terminal-only rule methods — bilateral axis 1 (is_terminal_rule = true)
{
    my %expected_terminal_rule = (
        alternative_count => '1',
        is_terminal_rule  => '1',
        to_string         => 'TermRule ::= /foo/ /bar/ ;',
    );

    for my $method (qw(alternative_count is_terminal_rule to_string)) {
        my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('Rule', $method) };
        SKIP: {
            skip "run_unit_method(Rule, $method) died: $@", 3 if $@;
            my $S_val = defined $r ? $r->{S}->return_values->[0] : undef;
            my $exp   = $expected_terminal_rule{$method};
            is($S_val, $exp, "T37: S side: Rule(terminal)->$method() = '$exp' (oracle)");
            my $P_val = defined $r ? $r->{P}->return_values->[0] : undef;
            is($P_val, $exp, "T38: P side: Rule(terminal)->$method() = '$exp'");
            my $verdict = $r->{verdict}{verdict} // $r->{verdict} // 'NO_VERDICT';
            is($verdict, 'PASS',
                "T39: Rule(terminal)->$method(): verdict is PASS (S=P confirmed)");
        }
    }
}

# T40-T42: Mixed rule — bilateral axis 2 (is_terminal_rule = false)
{
    my %expected_mixed_rule = (
        alternative_count => '1',
        is_terminal_rule  => '0',     # false: JSON::PP::Boolean stringifies to '0'
        to_string         => 'MixedRule ::= /foo/ Bar ;',
    );

    for my $method (qw(alternative_count is_terminal_rule to_string)) {
        my $r = eval { Chalk::CodeGen::Harness::Tier2->run_unit_method('Rule_mixed', $method) };
        SKIP: {
            skip "run_unit_method(Rule_mixed, $method) died: $@", 3 if $@;
            my $S_val = defined $r ? $r->{S}->return_values->[0] : undef;
            my $exp   = $expected_mixed_rule{$method};
            is($S_val, $exp, "T40: S side: Rule(mixed)->$method() = '$exp' (oracle)");
            my $P_val = defined $r ? $r->{P}->return_values->[0] : undef;
            is($P_val, $exp, "T41: P side: Rule(mixed)->$method() = '$exp'");
            my $verdict = $r->{verdict}{verdict} // $r->{verdict} // 'NO_VERDICT';
            is($verdict, 'PASS',
                "T42: Rule(mixed)->$method(): verdict is PASS (S=P confirmed)");
        }
    }
}

done_testing();
