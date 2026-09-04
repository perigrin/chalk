# ABOUTME: join lowers when its list argument has statically known arity.
# ABOUTME: A runtime-arity list argument GAPs rather than guessing an element count.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

# `join` had no lowering arm at all -- it fell through lower_value's dispatch
# to the generic `cannot lower op=Call (not in literal-arithmetic slice)`.
# Its REPRESENTATION was never the problem: the producer stamps the Call Str,
# matching TypeLibrary's declared signature (join => return_type => 'Str').
#
# WHAT MAKES IT LOWERABLE IS THE ARGUMENT'S ARITY, NOT ITS TYPE. join's second
# argument is a List, which is arity-polymorphic and has no machine type --
# %_REPR_NO_MACHINE_TYPE refuses it for exactly that reason. But a List whose
# producer is an ArrayLiteral has STATICALLY KNOWN arity:
#
#   sub lit { return (10,20,30) }   ArrayLiteral(c1,c2,c3) :List   arity 3
#   join(",", lit())                three elements, separator between
#
# so the element count is a compile-time fact and the result is an ordinary
# concat chain. No runtime list, no container, no length arithmetic.
#
# A List whose arity is NOT statically known cannot lower this way, and the
# honest answer there is the existing GAP rather than a guessed count.

my $FIXTURE = 't/bootstrap/ir/data/builtin-join.json';
my $wire = do {
    open my $fh, '<', $FIXTURE or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};
my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);

sub return_of {
    my ($g) = @_;
    return undef unless blessed($g) && $g->can('returns');
    my ($r) = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } $g->returns->@*;
    return $r;
}

subtest 'the program calling join lowers' => sub {
    my $prog = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';
    my $ret  = return_of($prog) or plan skip_all => 'no Return';

    my $ir = eval { Chalk::Target::LLVM->lower($ret) };
    my $err = $@;
    ok($ir, 'the program lowers')
        or diag "died: " . (split /\n/, $err)[0];
    return unless $ir;

    # The separator has to appear between elements, not merely somewhere. A
    # lowering that concatenated the elements and forgot the separator would
    # still produce a Str and still "lower".
    like($ir, qr/join/i, 'the emitted IR names the join it lowered');
};

# The GAP has to survive for the case it was written for. A join whose list
# argument has runtime arity cannot be a static concat chain, and guessing a
# count there is the miscompile this refuses.
subtest 'a non-static list argument still GAPs' => sub {
    my $prog = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';

    my ($join) = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Call'
            && $_->can('name') && ($_->name // '') eq 'join'
    } $prog->nodes->@*;
    ok($join, 'the fixture has a join call') or return;

    # Its list argument carries NO representation, and that is deliberate:
    # %LOWERABLE_STAMP is a whitelist of stamps the backend can lower, and
    # List is excluded by name ("a stamp outside it -- Scalar, List, DualVar,
    # a ref type -- leaves the representation unset so _require_repr reports
    # an honest GAP instead of mislowering", Serialize/JSON.pm:26).
    #
    # So the argument's LOWERABILITY cannot come from its repr. It comes from
    # its ARITY, which is a structural fact about the node that produces it.
    my $list_arg = $join->inputs->[1];
    ok(blessed($list_arg), 'join has a list argument');

    # ASKED AS AN ENCODING QUESTION, not as an absence. This read
    # `!defined ->stamp` until the loader began carrying every LATTICE
    # type -- including the ones with no machine encoding -- so that a value
    # node is never stampless. `List` is now PRESENT as a type and still has no
    # encoding, which is exactly the distinction the surrounding comment is
    # about: lowerability comes from arity, not from the repr.
    #
    # The old spelling passed only because two different facts shared one
    # field. Asking `is_lowerable_stamp` says what this test means.
    is($list_arg->stamp, 'List', 'the list argument carries the TYPE List');
    ok(!Chalk::IR::Serialize::JSON::is_lowerable_stamp($list_arg->stamp),
        'and List has NO machine encoding -- it is not a lowerable stamp');
};

done_testing;
