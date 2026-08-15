# ABOUTME: _repr_to_llvm_type must be TOTAL over every representation Chalk can construct.
# ABOUTME: Machine types answer; the four non-representable classes each refuse with their own message.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::Target::LLVM::Context;

my $f = \&Chalk::Target::LLVM::Context::_repr_to_llvm_type;

# ---------------------------------------------------------------------------
# 1. Concrete representations answer with a machine type.
#
# The shapes are the ones docs/architecture/typed-ir-representation.md's
# "Realized representation lattice" table records, and the ones
# Target/LLVM.pm:1210-1213 actually emits.
# ---------------------------------------------------------------------------
subtest 'concrete representations map to their documented machine type' => sub {
    my %EXPECT = (
        Int      => 'i64',
        Num      => 'double',
        Bool     => 'i1',
        # A Str VALUE is the first-class aggregate, so a phi/select over Str
        # values is typed %Str and the length cannot desynchronize from the ptr.
        Str      => '%Str',
        Slot     => '%Slot',      # { i1, i64 } -- the uniform field/element cell
        Array    => '%Array*',    # { i64, i64, %Slot* }
        Hash     => '%Hash*',     # { i64, i64, %HashEntry* }
        ArrayRef => 'i8*',        # boxed pointer to an %Array
        HashRef  => 'i8*',        # boxed pointer to a %Hash
        CodeRef  => 'i8*',
        Object   => 'i8*',        # ptr to { vtable*, %Slot... }
    );
    plan tests => scalar keys %EXPECT;
    for my $repr (sort keys %EXPECT) {
        my $got = eval { $f->($repr) };
        is($got, $EXPECT{$repr}, "$repr -> $EXPECT{$repr}"
            . (defined $got ? '' : " (DIED: $@)"));
    }
};

# ---------------------------------------------------------------------------
# 2. Undef is a UNIT TYPE: one value, no data.
#
# It is NOT a refusal class. The target may pick whatever constant suits it --
# the backend already does exactly this in DefinedOr's fallback
# (Context.pm:2445-2453), synthesizing a type-appropriate zero on demand.
# ---------------------------------------------------------------------------
subtest 'Undef answers (a unit type, not a refusal)' => sub {
    plan tests => 2;
    my $got = eval { $f->('Undef') };
    ok(defined $got, 'Undef has an answer rather than refusing')
        or diag("DIED: $@");
    is($got, 'i1', 'Undef is the target-chosen constant (today an i1 defined-bit)');
};

# ---------------------------------------------------------------------------
# 3. THE FOUR REFUSAL CLASSES.
#
# Each names a DIFFERENT upstream bug, so each must be distinguishable from the
# message alone. A single generic fallthrough merges four bugs into one
# undiagnosable report -- exactly the merge the Unknown/Scalar split exists to
# undo (TypeLibrary.pm:101-104).
# ---------------------------------------------------------------------------
subtest 'the four refusal classes each carry their own diagnosis' => sub {
    my @CASES = (
        # repr, qr/message/, what the message must convey
        ['Scalar',  qr/narrow/i,    'Scalar: not yet narrowed (arity 1, could get a repr later)'],
        ['Any',     qr/value type|signature/i,
                                    'Any: not a value type -- signature vocabulary'],
        ['List',    qr/value type|signature/i,
                                    'List: not a value type -- synonym of Any as a required type'],
        ['Unknown', qr/inference/i, 'Unknown: inference never typed this'],
        ['Regex',   qr/compile.time|statical/i,
                                    'Regex: resolved statically, never reaches runtime'],
    );
    plan tests => 2 * scalar @CASES;
    for my $c (@CASES) {
        my ($repr, $want, $desc) = @$c;
        my $got = eval { $f->($repr) };
        ok(!defined $got, "$repr refuses rather than answering");
        like($@, $want, $desc);
    }
};

# ---------------------------------------------------------------------------
# 4. The refusals must be DISTINGUISHABLE from each other, not merely present.
#
# This is the discriminating check: four `die "no LLVM type for '$repr'"`
# fallthroughs would satisfy subtest 3's `ok(!defined)` half while telling the
# reader nothing. The messages must differ.
# ---------------------------------------------------------------------------
subtest 'refusal messages are mutually distinct' => sub {
    my @REFUSING = qw(Scalar Any Unknown Regex);
    plan tests => 1 + scalar @REFUSING;

    my %seen;
    for my $repr (@REFUSING) {
        eval { $f->($repr) };
        my $msg = $@ // '';
        # Strip the repr name itself: a generic message that merely interpolates
        # $repr would otherwise look "distinct" without carrying a diagnosis.
        $msg =~ s/\Q$repr\E//g;
        $seen{$repr} = $msg;
        ok(length($msg) > 20, "$repr's refusal says something beyond the repr name");
    }
    my %uniq = map { $_ => 1 } values %seen;
    is(scalar keys %uniq, scalar @REFUSING,
        'all four refusals differ once the repr name is removed');
};

# ---------------------------------------------------------------------------
# 5. An undef repr keeps its existing, distinct diagnosis.
# ---------------------------------------------------------------------------
subtest 'an undef representation still refuses on its own terms' => sub {
    plan tests => 2;
    my $got = eval { $f->(undef) };
    ok(!defined $got, 'undef repr refuses');
    like($@, qr/NO representation|explicit repr/i,
        'undef repr names the missing-stamp bug, distinct from the four classes');
};

done_testing;
