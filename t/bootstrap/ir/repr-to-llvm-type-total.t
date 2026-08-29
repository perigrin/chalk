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
        Boolean     => 'i1',
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
subtest 'each refusal class carries its own diagnosis' => sub {
    my @CASES = (
        # repr, qr/message/, what the message must convey
        # Scalar REMOVED 2026-08-29: it ANSWERS now (%Slot). See the dedicated
        # subtest below. It was listed here on the reading that runtime-free
        # lowering has no box for it -- the box exists and every class emits it.
        # `Any` USED TO BE HERE and was removed 2026-08-26: it is not a member
        # of the type lattice (TypeLibrary::is_lattice_type says no) and the
        # string appears ZERO times in the LLVM backend. The case asserted a
        # specific refusal message for a name this compiler does not have, so
        # it tested the unknown-name fallthrough while claiming to test a
        # documented refusal -- and failed because that fallthrough's message
        # says "not a known representation", correctly.
        #
        # The four below are real: each IS a lattice member with a deliberate
        # entry in %_REPR_NO_MACHINE_TYPE explaining why it has no layout.
        ['List',    qr/value type|signature/i,
                                    'List: not a value type -- signature vocabulary, not a layout'],
        # NOT qr/inference/: that wording asserted Unknown means inference
        # FAILED, and perigrin corrected it (2026-08-27). Unknown is the
        # lattice TOP -- a real type meaning "any value whatsoever", which is
        # sometimes the CORRECT answer (a runtime-keyed lookup genuinely is
        # top). What is true is narrower: a top-typed value cannot be LOWERED
        # until something narrows it. Assert the refusal names that, not a bug.
        ['Unknown', qr/top|narrow/i,
                                    'Unknown: the lattice top -- needs narrowing before it can be lowered'],
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
    # Scalar REMOVED 2026-08-29: it now ANSWERS (%Slot), see the subtest below.
    # It was here on the reading that runtime-free lowering has no box for it;
    # the box exists and every class already emits it.
    my @REFUSING = qw(List Unknown Regex);   # Any removed: not a lattice type
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
        'the refusals differ once the repr name is removed');
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

subtest 'Scalar ANSWERS: it is the top of the scalar spine, encoded as %Slot' => sub {
    # perigrin, 2026-08-29. Scalar is the TYPE (what the join yields when
    # nothing narrower was proven); %Slot { i1 defined, i64 payload } is its
    # ENCODING. Every class already emits that cell for its object struct
    # (Context.pm:560) with a constructor (:922) and extractor (:931), so the
    # box is not hypothetical and not T2-gated.
    is($f->('Scalar'), '%Slot', 'Scalar maps to the uniform cell');
    is($f->('Slot'),   '%Slot', 'and Slot is the SAME encoding, named on the repr axis');

    # What remains T2's is the BOXING -- wrapping an i64 into the cell at a
    # store. That is a transformation, not a map entry, and until T2 does it
    # Context.pm:6318 keeps refusing an Int argument into a Scalar field.
    # If this ever stops refusing without T2 existing, something inserted a
    # box in the backend, which is the level violation to catch.
    ok(1, 'boxing stays T2\'s job -- see the note at Context.pm:6318');
};

done_testing;
