# ABOUTME: The repr fixpoint terminates because _is_narrowed latches each node
# ABOUTME: to one write -- not because the join converges. Pins that dependency.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::IR::Analysis;
require Chalk::IR::NodeFactory;
require Chalk::IR::Graph;

# WHY THIS FILE EXISTS.
#
# `_propagate_computed_reprs` is a `while ($changed)` loop, so a reader assumes
# it terminates the usual way: the lattice has finite height, reprs only move
# upward, and eventually nothing moves. That is NOT how this loop terminates.
#
# EVERY `$changed = 1` in it is unconditional -- not one tests whether the repr
# actually moved. So `$changed` is set on every write, whether or not the write
# changed anything. What makes the loop finite is the `_is_narrowed` guard at
# the top: a node that already carries a committed repr is SKIPPED, so each
# node can be written at most once, so only finitely many writes exist.
#
# `_is_narrowed` is therefore a TERMINATION LATCH, not merely an optimisation.
#
# This was measured, not reasoned. Making `Scalar` refinable -- returning false
# from `_is_narrowed` for it, which reads as an obviously-safe change since
# `Scalar` is the answer you give when you could not choose -- makes the loop
# DIVERGE: corpus case `logical.md` L3b alone reached iteration 457,642 before
# it was killed. The node re-joins to `Scalar` forever, setting `$changed`
# every pass.
#
# So anyone loosening `_is_narrowed` must FIRST make the writes conditional
# (`$changed = 1` only on an actual move). That is the load-bearing half; the
# predicate change is the cosmetic half. This file fails if the two halves are
# landed in the wrong order.

subtest 'the latch and the write discipline stay in step' => sub {
    my $src = do {
        open my $fh, '<', 'lib/Chalk/IR/Analysis.pm' or die "Analysis.pm: $!";
        local $/;
        <$fh>;
    };

    my ($body) = $src =~ /\nsub _propagate_computed_reprs \(\$graphs\) \{(.*?)\n\}\n/s
        or die 'could not find _propagate_computed_reprs';

    my $writes = () = $body =~ /\$changed = 1;/g;
    cmp_ok $writes, '>', 0, "the loop has $writes \$changed writes to account for";

    # Does the latch still admit exactly one write per node?
    my ($pred) = $src =~ /\nsub _is_narrowed \(\$repr\) \{(.*?)\n\}\n/s
        or die 'could not find _is_narrowed';
    my $latches = $pred !~ /return\s+false\b/;

    like $body, qr/next if _is_narrowed\(\$node->representation\)/,
        'the loop skips already-narrowed nodes';

    # THE PAIRING. If someone loosens _is_narrowed so a repr can be revisited,
    # the unconditional writes above stop being finite and the loop diverges.
    # The prerequisite is making the writes conditional on an actual move.
  SKIP: {
        skip 'the latch is intact, so unconditional writes are still bounded', 1
            if $latches;

        my $conditional = () = $body =~ /next if defined \$prev/g;
        cmp_ok $conditional, '>', 0,
            '_is_narrowed was loosened, so the writes MUST be conditional first '
          . '(see the header: the predicate change is the cosmetic half)';
    }
};

# The behavioural half: the latch does its job on the shape that provoked the
# divergence -- a merge whose join is `Scalar`, which _is_narrowed counts as
# committed. If a future change makes Scalar refinable without making the
# writes conditional, this hangs instead of failing, so it is bounded.
subtest 'a Scalar-joined merge settles instead of re-joining forever' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $i = 0;
    my @in = map {
        my $n = $f->make( 'Constant', const_type => 'integer', value => ++$i );
        $n->set_representation($_);
        $n;
    } ( 'Undef', 'Int' );

    my $d = $f->make( 'DefinedOr', inputs => \@in );
    my $g = Chalk::IR::Graph->new;
    $g->merge($_) for $d, @in;

    my $done = 0;
    my $err;
    {
        local $SIG{ALRM} = sub { die "propagate did not terminate\n" };
        alarm 10;
        $err = $@ unless eval {
            Chalk::IR::Analysis::_propagate_computed_reprs( { g => $g } );
            $done = 1;
        };
        alarm 0;
    }

    ok $done, 'the fixpoint terminated'
        or diag("error: " . ($err // $@ // 'timed out'));

    is $d->representation, 'Scalar',
        'and it settled on Scalar -- written once, then latched';
};

done_testing;
