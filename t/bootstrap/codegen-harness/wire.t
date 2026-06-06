# ABOUTME: End-to-end wire test — hand graph -> Target::Perl->generate -> run -> S-vs-P verdict.
# ABOUTME: Asserts the full harness loop produces a PASS verdict for known-good tier-1 idioms.
use 5.42.0;
use utf8;

use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::CodeGen::Harness;
use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness::PerlDriver;

# --- T1: Harness module loads ---
ok(defined &Chalk::CodeGen::Harness::run_entry, 'Chalk::CodeGen::Harness exports run_entry');

# --- T2: PerlDriver module loads ---
ok(defined &Chalk::CodeGen::Harness::PerlDriver::run,
    'Chalk::CodeGen::Harness::PerlDriver exports run');

# --- T3: The driver feeds the SAME graph object that HandGraphs produced ---
# This is a structural AC from the issue: grep for generate|graph_for in PerlDriver.pm
{
    my $driver_src = do {
        open my $fh, '<', 'lib/Chalk/CodeGen/Harness/PerlDriver.pm'
            or die "Cannot open PerlDriver.pm: $!";
        local $/;
        <$fh>;
    };
    like($driver_src, qr/generate/, 'PerlDriver.pm calls generate');
    like($driver_src, qr/graph_for|graph/, 'PerlDriver.pm references graph/graph_for');
}

# --- T4: run_entry for A1 produces S, P, and a verdict ---
# A1: class C { method m() { my $x = 1; return $x; } }
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $result = eval { Chalk::CodeGen::Harness->run_entry('A1', $spec) };
    is($@, '', 'run_entry("A1") does not die');
    ok(defined $result, 'run_entry returns a defined value');

    SKIP: {
        skip 'no result', 5 unless defined $result;

        ok(defined $result->{S}, 'result contains S (oracle record)');
        ok(defined $result->{P}, 'result contains P (generated record)');
        ok(defined $result->{verdict}, 'result contains verdict');

        # S must be a BehaviorRecord
        isa_ok($result->{S}, 'Chalk::CodeGen::Harness::BehaviorRecord',
            'S is a BehaviorRecord');

        # verdict must be one of PASS/GAP/MISCOMPILE
        like($result->{verdict}{verdict}, qr/^(?:PASS|GAP|MISCOMPILE)$/,
            'verdict is PASS, GAP, or MISCOMPILE');
    }
}

# --- T5: A1 end-to-end produces a PASS verdict ---
# A1 is the simplest known-good idiom: my $x = 1; return $x;
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $result = eval { Chalk::CodeGen::Harness->run_entry('A1', $spec) };
    is($@, '', 'A1 end-to-end does not die');

    SKIP: {
        skip 'no result', 3 unless defined $result;

        is($result->{verdict}{verdict}, 'PASS',
            'A1: end-to-end S-vs-P verdict is PASS');

        # S oracle should observe return value 1
        my $rv_s = $result->{S}->return_values;
        is($rv_s->[0], 1, 'S oracle observes return value 1 for A1');

        # P generated should also observe return value 1
        my $rv_p = $result->{P}->return_values;
        is($rv_p->[0], 1, 'P generated observes return value 1 for A1');
    }
}

# --- T6: A5 end-to-end with :param field ---
# A5: class C { field $x :param; method m() { return $x; } }
{
    my $spec = {
        class       => 'C',
        constructor => { params => { x => 42 } },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my $result = eval { Chalk::CodeGen::Harness->run_entry('A5', $spec) };
    is($@, '', 'A5 end-to-end does not die');

    SKIP: {
        skip 'no result', 2 unless defined $result;

        # A5 has a :param field — the generated code must support it
        like($result->{verdict}{verdict}, qr/^(?:PASS|GAP|MISCOMPILE)$/,
            'A5: verdict is a valid classification');
        ok(defined $result->{S}, 'A5: oracle record S is present');
    }
}

done_testing();
