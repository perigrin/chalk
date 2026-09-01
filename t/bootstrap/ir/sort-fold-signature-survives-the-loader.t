# ABOUTME: A folded sort's comparison kind and direction survive deserialization.
# ABOUTME: The loader silently drops wire fields no node declares, by design.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;

# perl FOLDS the standard comparators into flags on the sort op, so the block
# is gone by the time the producer sees it and there is nothing to drop. What
# perl retains is the DECISION: OPpSORT_NUMERIC and OPpSORT_DESCEND. The
# producer states those as sort_cmp/sort_order (perl5-son ebb46f0).
#
# Without them three DIFFERENT programs are one wire node:
#
#   sort { $a <=> $b } (3,1,2)   perl 1
#   sort { $b <=> $a } (3,1,2)   perl 3
#   sort (3,1,2)                 perl 1   <- STRING compare, not numeric
#
# and an implementation picking one silently miscompiles the others. Bare sort
# being a string compare is the case that breaks ordinary code, not an edge
# case: `sort (10, 9, 100)` is `10 100 9`.
#
# THIS TEST ASSERTS THE SIGNATURES ARE DISTINCT, not merely that each field has
# a value. A per-field assertion passes when every sort reports the same thing,
# which is exactly the bug. (Same reasoning bson used producer-side.)

my %expect = (
    'sort-fold-asc'  => { cmp => 'numeric', order => 'ascending'  },
    'sort-fold-desc' => { cmp => 'numeric', order => 'descending' },
    'sort-fold-str'  => { cmp => 'string',  order => 'ascending'  },
    'sort-fold-cmp'  => { cmp => 'string',  order => 'ascending'  },
);

my %seen;

for my $fixture (sort keys %expect) {
    subtest $fixture => sub {
        my $wire = do {
            open my $fh, '<', "t/bootstrap/ir/data/$fixture.json"
                or plan skip_all => "fixture missing: $!";
            local $/; <$fh>;
        };
        my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
        my $driver = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no driver';

        my ($sort) = grep {
            $_->operation eq 'Call' && ($_->name // '') eq 'sort'
        } $driver->nodes->@*;
        ok $sort, 'found Call(sort)' or return;

        ok $sort->can('sort_cmp'),   'the loaded node answers sort_cmp'   or return;
        ok $sort->can('sort_order'), 'the loaded node answers sort_order' or return;

        is $sort->sort_cmp,   $expect{$fixture}{cmp},
            "sort_cmp survives as $expect{$fixture}{cmp}";
        is $sort->sort_order, $expect{$fixture}{order},
            "sort_order survives as $expect{$fixture}{order}";

        $seen{$fixture} = ($sort->sort_cmp // '?') . '/' . ($sort->sort_order // '?');
    };
}

subtest 'the three distinct programs stay distinct' => sub {
    plan skip_all => 'fixtures did not all load' unless keys(%seen) == 4;

    isnt $seen{'sort-fold-asc'}, $seen{'sort-fold-desc'},
        'ascending and descending are not the same signature';
    isnt $seen{'sort-fold-asc'}, $seen{'sort-fold-str'},
        'numeric and string are not the same signature';

    # These two ARE the same operation -- `sort` and `sort { $a cmp $b }` both
    # mean an ascending string sort -- so agreeing here is correct, not a
    # collision.
    is $seen{'sort-fold-str'}, $seen{'sort-fold-cmp'},
        'bare sort and an explicit cmp block agree, because they are one operation';
};

done_testing;
