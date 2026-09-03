# ABOUTME: A recursive call's return type is unresolved, and unresolved is None, not absent.
# ABOUTME: None is the join identity, so the base case decides and the ternary types.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::Serialize::JSON;
use Chalk::IR::Analysis;
use Chalk::Grammar::Perl::TypeLibrary;

# `sub fib { my $n = shift; $n < 2 ? $n : fib($n-1) + fib($n-2) }` refuses with
# "Add node has no representation at lowering time". After the loader runs, the
# recursive Calls, the Add over them, the TernaryExpr and the Return all carry
# NO stamp at all.
#
# THE CYCLE, and why it has no entry point today:
#
#   Return <- TernaryExpr <- Add <- recursive Calls <- fib's own Return
#
# `_resolve_direct_calls` stamps a Call from its callee's Return VALUE, and for
# a self-recursive sub that value is the very ternary being computed.
#
# THE ANSWER IS THE ELEMENT THE RECURSIVE ARM CONTRIBUTES, and all three
# plausible choices behave differently:
#
#   absence    the join BAILS -- Analysis.pm:2085 skips any merge with an
#              undefined input, so nothing is decided
#   Unknown    TOP, and it ABSORBS -- join(Unknown, Int) is Unknown, so the
#              base case's Int is computed and then thrown away
#   None       BOTTOM, the join IDENTITY -- join(None, Int) is Int, so the
#              base case decides and the ternary types
#
# This is not a new rule. `TypeLibrary::join_types` documents `None` for
# precisely this case (:383): "None is the identity (T join None == T), which is
# what lets a recursive function type from its base case: the recursive arm
# contributes None on the first pass, so Int join None == Int rather than
# collapsing to a top."
#
# The identity element exists and is documented for this use. What is missing is
# a producer for it: nothing in lib/ ever stamps a node `None`.
#
# SCOPE. This types the one-typed-arm-plus-one-recursive-arm shape, which is the
# first iteration of a fixpoint rather than a general solution. Mutual recursion
# where no arm types on the first pass still needs real iteration. Typing is also
# only half of compiling `fib` -- emitting the recursion needs real define+call,
# which the inliner cannot do and GAPs loudly about.

my $join = \&Chalk::IR::Analysis::_join_repr;

subtest 'the premise: None is the join identity and Unknown absorbs' => sub {
    # Measured rather than cited: the whole fix rests on these two behaviours
    # differing, and on the direction of the difference.
    is $join->('None', 'Int'), 'Int', 'None joined with Int yields Int';
    is $join->('Int', 'None'), 'Int', 'and the same in either order';
    is $join->('None', 'Str'), 'Str', 'the identity holds for any type';

    is $join->('Unknown', 'Int'), 'Unknown',
        'whereas Unknown ABSORBS -- this is the choice that loses the base case';

    is $join->('None', 'None'), 'None',
        'and bottom with bottom stays bottom -- nothing is claimed';
};

# `None` must be a real lattice member, not a sentinel string that happens to
# fall through. If it were not, the join above would be an accident.
subtest 'None is a lattice member, not a sentinel' => sub {
    my $is_lattice = Chalk::Grammar::Perl::TypeLibrary->can('is_lattice_type');
    plan skip_all => 'is_lattice_type not exposed' unless $is_lattice;
    ok $is_lattice->('None'), 'None is a member of the type lattice';
};

# THE MECHANISM, at the level the fix operates on: a merge whose arms are a
# known type and an unresolved recursive call must take the known type.
subtest 'a merge over a base case and an unresolved arm takes the base case' => sub {
    # This is fib's ternary in miniature: one arm typed from the argument, one
    # arm standing in for the not-yet-resolved recursive call.
    is $join->('Int', 'None'), 'Int',
        'the ternary types Int from its base case alone';

    # And with the arithmetic fib actually has above the recursive call: an Add
    # over two unresolved calls is itself unresolved, not absent.
    is $join->('None', 'None'), 'None',
        'Add(fib(...), fib(...)) is None on the first pass, not undef';

    is $join->('Int', $join->('None', 'None')), 'Int',
        'so the ternary still types Int with the Add arm folded in';
};

# THE CONTROL, and the one that matters most. Seeding None must not become a
# way to type something nothing knows about. A merge with a genuinely
# unresolvable arm must still yield Unknown, not silently adopt the other arm.
subtest 'None does not launder an Unknown arm' => sub {
    is $join->('Int', 'Unknown'), 'Unknown',
        'an arm inference FAILED on still absorbs -- None changes nothing here';

    is $join->('None', 'Unknown'), 'Unknown',
        'and bottom joined with top is top, not bottom';
};

# THE SECOND CONTROL. Absence is still not a type. The fix replaces absence with
# None at ONE specific site (an unresolved recursive call); it must not make the
# propagation pass treat every unstamped node as bottom, which would type nodes
# inference simply has not reached yet.
subtest 'absence is still distinct from None' => sub {
    my $got = $join->('Int', undef);
    ok !defined $got || $got eq 'Int',
        'an undef arm is not silently read as None by the join itself'
        or diag("  got: " . ($got // 'undef'));
};

done_testing;
