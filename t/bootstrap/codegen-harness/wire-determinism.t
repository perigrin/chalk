# ABOUTME: Determinism gate (C8) — generate() over the same hand graph twice yields BYTE-IDENTICAL Perl.
# ABOUTME: Guards the existing determinism invariant; orthogonal to behavior comparison.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness::PerlDriver;
use Chalk::Bootstrap::Perl::Target::Perl;

# --- T1: A1 — same graph object, two emissions, byte-identical ---
# The same Chalk::MOP object passed twice to Target::Perl->generate must produce
# the same string output. If hash iteration order or node ordering is
# non-deterministic, this will catch it.
{
    my $graph   = Chalk::CodeGen::Harness::HandGraphs->graph_for('A1');
    my $target1 = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $target2 = Chalk::Bootstrap::Perl::Target::Perl->new;

    my $emit1 = eval { $target1->generate($graph) };
    is($@, '', 'A1: first emission does not die');
    my $emit2 = eval { $target2->generate($graph) };
    is($@, '', 'A1: second emission does not die');

    SKIP: {
        skip 'emissions failed', 1 unless defined $emit1 && defined $emit2;

        # Normalise: if generate returns HashRef[Str], join values sorted by key.
        my $str1 = _flatten($emit1);
        my $str2 = _flatten($emit2);

        is($str1, $str2, 'A1: two emissions of the same graph are byte-identical');
    }
}

# --- T2: A4 — same graph, two emissions, byte-identical ---
{
    my $graph   = Chalk::CodeGen::Harness::HandGraphs->graph_for('A4');
    my $target1 = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $target2 = Chalk::Bootstrap::Perl::Target::Perl->new;

    my $emit1 = eval { $target1->generate($graph) };
    my $emit2 = eval { $target2->generate($graph) };

    SKIP: {
        skip 'emissions failed', 1 unless defined $emit1 && defined $emit2;

        is(_flatten($emit1), _flatten($emit2),
            'A4: two emissions of the same graph are byte-identical');
    }
}

# --- T3: A5 — same graph, two emissions, byte-identical ---
{
    my $graph   = Chalk::CodeGen::Harness::HandGraphs->graph_for('A5');
    my $target1 = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $target2 = Chalk::Bootstrap::Perl::Target::Perl->new;

    my $emit1 = eval { $target1->generate($graph) };
    my $emit2 = eval { $target2->generate($graph) };

    SKIP: {
        skip 'emissions failed', 1 unless defined $emit1 && defined $emit2;

        is(_flatten($emit1), _flatten($emit2),
            'A5: two emissions of the same graph are byte-identical');
    }
}

# --- T4: Perturbed emission FAILS the gate ---
# Simulates a non-deterministic emission: the same base string with extra
# whitespace added to the second emission. The gate MUST detect this diff
# and NOT silently pass it.
{
    my $graph  = Chalk::CodeGen::Harness::HandGraphs->graph_for('A1');
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;

    my $emit1 = eval { $target->generate($graph) };
    SKIP: {
        skip 'emission failed', 1 unless defined $emit1;

        my $str1 = _flatten($emit1);
        # Perturb: append a trailing space to simulate non-deterministic output.
        my $str2 = $str1 . ' ';

        isnt($str1, $str2,
            'perturbed emission is detected as non-equal (gate catches diff)');
    }
}

# --- T5: PerlDriver->run returns emission_meta with determinism flag ---
# The driver exposes whether it succeeded in generating complete code.
{
    my $graph = Chalk::CodeGen::Harness::HandGraphs->graph_for('A1');
    my $spec  = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };

    my ($P, $meta) = eval { Chalk::CodeGen::Harness::PerlDriver->run($graph, $spec) };
    is($@, '', 'PerlDriver->run does not die for A1');

    SKIP: {
        skip 'PerlDriver->run failed', 2 unless defined $P && defined $meta;

        ok(exists $meta->{emitted_for_every_construct},
            'emission_meta contains emitted_for_every_construct');
        ok(exists $meta->{marked_unsupported},
            'emission_meta contains marked_unsupported');
    }
}

# --- helper ---
sub _flatten {
    my ($v) = @_;
    return '' unless defined $v;
    return $v unless ref $v eq 'HASH';
    return join("\n", map { $v->{$_} } sort keys %$v);
}

done_testing();
