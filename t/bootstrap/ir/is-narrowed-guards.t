# ABOUTME: Pins that the loader's "already decided" guards test COMMITMENT, not defined-ness.
# ABOUTME: `Unknown` in the field means undecided, so a guard must not treat it as an answer.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::Serialize::JSON;
use Chalk::IR::Analysis;

# THE DISTINCTION. Nine sites in the loader ask "has this node already been
# assigned a representation?" and skip their work when the answer is yes. They
# spell that question `defined $node->representation`.
#
# That spelling is only correct while `Unknown` CANNOT REACH THE FIELD. Today
# it cannot: the wire-stamp seed at Serialize/JSON.pm:548 gates on
# %LOWERABLE_STAMP, which lists six committed types and drops everything else
# -- including `Unknown`, which is precisely how the producer says "I could not
# type this".
#
# Slice 3b of docs/plans/2026-08-24-loader-analysis-pipeline.md removes that
# gate, so `Unknown` starts landing in the field. Every `defined` guard then
# reads it as "already decided" and skips -- turning the producer's admission
# of ignorance into a committed answer. Measured consequence: the OOB->Slot fix
# at :1459 stops firing and corpus R9 miscompiles (an out-of-bounds read must
# print `Undef:`, not payload 0).
#
# So the guards must ask about COMMITMENT, not defined-ness. That is
# _is_narrowed. The producer already made this exact split (perl5-son
# FromOptree.pm:3100, `defined $stamp && $stamp->type ne 'Unknown'`); chalk's
# field holds a plain string rather than a Stamp object, so the predicate is
# spelled against the string here.
#
# This file pins the predicate itself. It is deliberately NOT a test of any one
# of the nine call sites: the sites are all the same question, and pinning the
# question once is what makes converting them mechanical.

subtest '_is_narrowed separates committed from undecided' => sub {
    my $narrowed = \&Chalk::IR::Analysis::_is_narrowed;

    ok !$narrowed->(undef), 'undef is not narrowed -- nothing was decided';
    ok !$narrowed->('Unknown'),
        'Unknown is not narrowed -- the producer decided it could not decide';

    ok $narrowed->($_), "$_ is narrowed" for qw(Int Num Str Boolean Undef Object);

    # Slot is not a lattice type -- it is the lowering encoding for a value
    # that may be absent. It is still a COMMITMENT (the OOB path chose it
    # deliberately at :1459), so a guard must treat it as decided and not
    # re-derive over it.
    ok $narrowed->('Slot'), 'Slot is narrowed -- a deliberate commitment';

    # The two names 3b widens the seed to admit. They are commitments too:
    # once ArrayRef lands in the field, a later pass must not overwrite it.
    ok $narrowed->($_), "$_ is narrowed" for qw(ArrayRef HashRef);
};

subtest 'the predicate is what the nine guards actually call' => sub {
    # A guard that still spells the question `defined ...->representation` is
    # one that will misread `Unknown` the moment 3b lands. Sweep for the old
    # spelling so a reintroduced one fails HERE, with this explanation,
    # rather than as a silent miscompile after the gate is removed.
    # BOTH files. The guards moved to Analysis.pm when the inference passes
    # left the loader, but the loader still decodes stamps off the wire and
    # could regrow one. Either file gaining a bare `defined ->representation`
    # is the regression this sweeps for.
    for my $path (qw(
        lib/Chalk/IR/Analysis.pm
        lib/Chalk/IR/Serialize/JSON.pm
    )) {
        open my $fh, '<', $path or die "cannot read $path: $!";
        my @stale;
        while (my $line = <$fh>) {
            next if $line =~ /^\s*#/;                # comments explain, not guard
            next unless $line =~ /->representation\b/;
            next unless $line =~ /\bdefined\b/;
            # _is_narrowed itself is the one place the old spelling is correct.
            next if $line =~ /sub _is_narrowed/;
            push @stale, "$.: " . ($line =~ s/^\s+|\s+$//gr);
        }
        close $fh;

        is \@stale, [],
            "no guard tests defined-ness of a representation in $path"
            or diag(
                "These sites ask `defined ->representation`, which reads Unknown\n"
              . "as a committed answer. Use _is_narrowed(\$node->representation)."
            );
    }
};

done_testing;
