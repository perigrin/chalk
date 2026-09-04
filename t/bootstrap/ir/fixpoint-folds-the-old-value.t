# ABOUTME: Kildall's store discipline -- a fixpoint write JOINS the old value,
# ABOUTME: it never overwrites. Without that a stamp can move SIDEWAYS forever.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

require Chalk::Grammar::Perl::TypeLibrary;
my $join = \&Chalk::Grammar::Perl::TypeLibrary::join_types;

subtest 'a join that folds the old value is MONOTONE -- it only ascends' => sub {
    # Kildall 1973 step A4: the store is `P_N AND P_i` -- a meet with the old
    # stored value (a JOIN in this lattice's orientation), never a raw
    # overwrite -- and it happens only when the result differs from the old.
    # The change guard alone is HALF the proof; folding is the other half.
    #
    # Sideways movement is what folding prevents. Int and Undef are
    # incomparable-ish siblings under Scalar: without folding, a node stamped
    # Int whose inputs later say Undef would be REWRITTEN to Undef, and could
    # be rewritten back -- neither is a fixpoint.
    is($join->('Int', 'Undef'), 'Scalar',
       'joining the two gives their upper bound, which is stable');

    # Folding makes each successive store >= the last, so the sequence is an
    # ascending chain in a lattice of height ~6 and must halt.
    my $prev = 'Int';
    my $next = $join->($prev, 'Undef');
    is($next, 'Scalar', 'Int then Undef ascends to Scalar');
    is($join->($next, 'Int'), 'Scalar',
       'and a later Int does NOT drag it back down -- the chain is monotone');
};

subtest 'the main loop folds the old value into its join' => sub {
    # The structural check. _propagate_computed_reprs computed
    # `_join_repr(@reprs)` over INPUTS ONLY, so a store could move sideways
    # between incomparable elements; the change guard cannot stop that, and
    # today's termination was luck-of-reachable-moves rather than a proof.
    my $src = do {
        open my $fh, '<', 'lib/Chalk/IR/Analysis.pm' or die "Analysis.pm: $!";
        local $/; <$fh>;
    };
    my ($body) = $src =~ /\nsub _propagate_computed_reprs \(\$graphs\) \{(.*?)\n\}\n/s
        or die 'could not find _propagate_computed_reprs';

    like($body, qr/_join_repr\(\s*\$node->stamp\s*,/,
         'the join folds the node\'s existing stamp in as an operand');
};

done_testing;
