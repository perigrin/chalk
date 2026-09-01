# ABOUTME: sort orders an %Array in place by the producer's folded comparator.
# ABOUTME: join over a runtime-arity array loops rather than refusing.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

# perl FOLDS the standard comparators into flags on the sort op, so by the
# time a producer sees `sort { $a <=> $b }` the block is gone and what remains
# is the DECISION. Three different programs are otherwise one node:
#
#   sort { $a <=> $b } (3,1,2)   perl 1
#   sort { $b <=> $a } (3,1,2)   perl 3
#   sort (3,1,2)                 perl 1   <- STRING compare, not numeric
#
# Bare `sort` defaulting to a string compare is the case that breaks ordinary
# code rather than an edge case: `sort (10, 9, 100)` is `10 100 9`.
#
# THIS IS THE CASE THE CORPUS ACTUALLY WANTS. references.md R11 is
# `join(",", sort keys %h)`, which needs all three of keys, sort and join, and
# the arity is NOT static -- it is the hash's runtime key count. So join can
# no longer require a compile-time element count; it loops.

my %FIXTURE = (
    'sort keys, joined' => 't/bootstrap/ir/data/builtin-sort-keys.json',
);

for my $name (sort keys %FIXTURE) {
    subtest $name => sub {
        my $wire = do {
            open my $fh, '<', $FIXTURE{$name} or plan skip_all => "fixture missing: $!";
            local $/; <$fh>;
        };
        my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
        my $prog = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';
        my ($ret) = grep {
            blessed($_) && $_->can('operation') && $_->operation eq 'Return'
        } $prog->returns->@*;
        ok($ret, 'the program has a Return') or return;

        my $ir = eval { Chalk::Target::LLVM->lower($ret) };
        my $err = $@;
        ok($ir, 'it lowers') or do {
            diag "died: " . (split /\n/, $err)[0];
            return;
        };

        # The comparator must reach the emitted code. A sort that lowered
        # without one would order by whatever the buffer already held and
        # still "lower" -- and for `sort keys %h` that is insertion order,
        # which is right often enough to hide the bug.
        like($ir, qr/sort:/, 'the emitted IR names the sort it lowered');
    };
}

# The folded comparator is the whole of what perl kept, so it must survive to
# the node. Asserting the two fields DIFFER across cases is what makes this
# discriminating -- a per-field check passes when every sort reports the same
# thing, which is exactly the bug.
subtest 'the folded comparator reaches the node' => sub {
    my $wire = do {
        open my $fh, '<', $FIXTURE{'sort keys, joined'} or plan skip_all => 'fixture missing';
        local $/; <$fh>;
    };
    my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
    my $prog = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';

    my ($sort) = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Call'
            && $_->can('name') && ($_->name // '') eq 'sort'
    } $prog->nodes->@*;
    ok($sort, 'the fixture has a sort call') or return;

    is($sort->sort_cmp,   'string',    'sort keys %h is a STRING compare');
    is($sort->sort_order, 'ascending', 'ascending');
    is($sort->representation // '<undef>', 'Array',
        'and it yields an Array -- the ordered keys');
};

done_testing;
