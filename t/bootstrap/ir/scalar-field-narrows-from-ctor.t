# ABOUTME: A Scalar field type is un-narrowed, so constructor inference must refine it.
# ABOUTME: `defined` is the wrong guard once the producer sends Scalar instead of nothing.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;

# WHY: `_infer_param_field_types` skipped any field with `defined $f->{type}`.
# The producer used to send NO type for an untyped :param field; it now sends
# `Scalar` -- the honest un-narrowed top. `Scalar` is defined, so the guard
# stopped the inference that used to run, and every `:reader` return stayed
# Scalar. That reaches the backend as Coerce[Scalar -> Num], which has no arm.
#
# `_is_narrowed` already states the rule (Scalar and Unknown are NOT narrowed).
# The guard has to use it.

my $wire = do {
    open my $fh, '<', 't/bootstrap/ir/data/scalar-field-ctor.json' or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);

subtest 'a Scalar :param field narrows to its constructor argument' => sub {
    my $g = $graphs->{'main::__PROGRAM__'} or die 'no driver graph';

    my @calls = grep { $_->operation eq 'Call'
                       && ($_->name // '') =~ /^(left|right)$/ } $g->nodes->@*;
    ok scalar(@calls) >= 2, 'found the :reader calls' or diag 'no reader calls';

    for my $c (@calls) {
        is $c->stamp, 'Int',
            ($c->name // '?') . " returns Int, not Scalar -- ctor passed an Int";
    }
};

subtest 'no Coerce from an un-narrowed Scalar survives' => sub {
    my @bad;
    for my $name (sort keys $graphs->%*) {
        my $g = $graphs->{$name};
        next unless ref $g && $g->can('nodes');
        next unless $name =~ /^(main|Pair)::/;   # user code only
        for my $n ($g->nodes->@*) {
            next unless $n->operation eq 'Coerce';
            push @bad, "$name: Coerce[" . ($n->from_repr // '?') . ' -> '
                     . ($n->to_repr // '?') . ']'
                if ($n->from_repr // '') eq 'Scalar';
        }
    }
    is_deeply \@bad, [], 'no Coerce[Scalar -> *] in user code'
        or diag join "\n", @bad;
};

done_testing;
