# ABOUTME: Every lattice edge is DERIVED from perl -- membership and substitutability, both measured.
# ABOUTME: The verdict is computed, not declared, and the type table must agree with it.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(reftype blessed);
use lib 'lib';

use Chalk::Grammar::Perl::TypeLibrary;

# WHAT THIS FILE IS FOR, and how it differs from type-library.t.
#
# type-library.t asserts `is_subtype('Int','Num')` and friends. That is a
# CHANGE DETECTOR and a useful one -- it catches an edit to the table that
# nobody reflected in the tests. What it cannot catch is a table that was
# WRONG FROM THE START, because the table is its own oracle. It was green for
# the entire time `Boolean => 'Str'` was wrong.
#
# This file uses PERL as the oracle. Each edge's verdict is COMPUTED from two
# measurements, and the table is then required to agree with what was computed.
#
#     A <: B  iff  (A subset-of B) and (every op of B holds for values of A)
#
# THE VERDICT IS NOT WRITTEN DOWN. An earlier version of this file carried a
# hand-written `holds => 0|1` per edge and asserted table == holds and
# perl == holds. That is a three-way agreement in which one term is an
# assertion of belief, so an edge whose author got BOTH the table and the flag
# wrong agreed with itself. Now `holds` is `factor1 && factor2`, derived here,
# and the only claim a human makes is which WITNESSES to test -- which is
# checkable by reading them.
#
# Boolean under Str is the worked example of why both factors are needed.
# Factor 2 PASSES -- every string operation works on a boolean with no
# coercion. Factor 1 FAILS, on `false` only. A single-factor test, or a
# single-value probe, gets it wrong; both mistakes were actually made before
# the edge was corrected.

# ---------------------------------------------------------------------------
# FACTOR 1: MEMBERSHIP.
#
# Two oracles, because the lattice has two kinds of type and one question
# cannot reach both.
#
# INTERPRETIVE (the scalar spine). `v` is in B iff interpreting it as B
# directly agrees with interpreting it as B via some ADMISSIBLE detour type S.
# This is what catches `false`: it stringifies directly to "" but reaches "0"
# through every numeric detour, so no detour preserves it.
#
# STRUCTURAL (references, collections, globs). A CodeRef does not "interpret"
# as anything -- asking what it stringifies to measures its address, not its
# type. Membership there is a question about what a value IS, which perl
# answers directly through ref/reftype/blessed. Using the interpretive oracle
# on these types is what limited the earlier version of this file to three
# types; it was a property of the machinery, not of the lattice.
# ---------------------------------------------------------------------------
my %INTERPRET_AS = (
    Str => sub { no warnings; "" . $_[0] },
    Num => sub { no warnings; 0 + $_[0] },
    Int => sub { no warnings; int(0 + $_[0]) },
);

# ONLY S = B IS EXCLUDED, and only that. Interpreting as B and then as B again
# is the identity on every value of B, so it would certify membership for
# anything -- the vacuous test the well-formedness rule exists to forbid.
#
# S = A (the child) is NOT excluded, and an earlier version of this file
# wrongly did exclude it. That over-exclusion made `Num <: Str` fail on 3.5:
# the only detour left was Int, which truncates to "3" against a direct "3.5".
# The circularity rule bans a detour that would make B's definition depend on
# B -- not one that passes through a proper subtype of B on the way.
#
# The rule that does the real work is therefore narrow, and a wider one is not
# safer: it manufactures false negatives, which look exactly like findings.
sub admissible_detours_for ($B) {
    return grep { $_ ne $B } sort keys %INTERPRET_AS;
}

sub interpretive_member ($v, $B) {
    my $direct = $INTERPRET_AS{$B}->($v);
    for my $S (admissible_detours_for($B)) {
        my $detour = $INTERPRET_AS{$B}->($INTERPRET_AS{$S}->($v));
        return 1 if $detour eq $direct;
    }
    return 0;
}

# The structural oracle: what perl says a value IS. Each predicate is written
# from perl's own classification, never from the lattice -- otherwise the table
# would be grading its own homework again.
my %STRUCTURALLY_IS = (
    # Every reference is a Ref, whatever it points at.
    Ref       => sub { ref($_[0]) ne '' },
    # SCALAR and REF are both scalar-cell references: `\$x` reports SCALAR,
    # `\\$x` reports REF, and both deref with $$.
    ScalarRef => sub { (reftype($_[0]) // '') =~ /^(?:SCALAR|REF)$/ },
    ArrayRef  => sub { (reftype($_[0]) // '') eq 'ARRAY' },
    HashRef   => sub { (reftype($_[0]) // '') eq 'HASH'  },
    CodeRef   => sub { (reftype($_[0]) // '') eq 'CODE'  },
    GlobRef   => sub { (reftype($_[0]) // '') eq 'GLOB'  },
    LValueRef => sub { (reftype($_[0]) // '') eq 'LVALUE' },
    Object    => sub { defined blessed($_[0]) },
    Regex     => sub { (reftype($_[0]) // '') eq 'REGEXP' },
    Undef     => sub { !defined $_[0] },
    # Scalar is the top of the single-value branch: anything holding one value.
    Scalar    => sub { !ref($_[0]) || ref($_[0]) ne '' },

    # THE COLLECTION BRANCH IS AN ARITY QUESTION, and that is a THIRD oracle,
    # not a variant of the other two. `List` is not something a value
    # interprets as, nor a structural kind ref() reports: it is "how many
    # values does this yield in list context". Measured: a scalar yields 1, a
    # three-element array 3, a two-key hash 4, an empty list 0.
    #
    # So membership in List is satisfied by ANY arity -- every value yields
    # some number of values, including zero. That makes `Scalar <: List` the
    # claim that one value is a list of length one, which is exactly what the
    # type library's comment on that line says ("{1} is a subset of
    # {0,1,2,...}").
    #
    # Witnesses reach this oracle already flattened, so what is measured here
    # is the arity of what the caller passed, not of a container it was
    # wrapped in. `Array` and `Hash` therefore need witnesses passed as lists
    # rather than as references -- which is why they are not yet covered.
    List      => sub { 1 },
);

sub structural_member ($v, $B) {
    my $p = $STRUCTURALLY_IS{$B} or return undef;   # no oracle for this type
    return $p->($v) ? 1 : 0;
}

# member_of dispatches to whichever oracle can answer, structural first (it is
# the more direct question), falling back to interpretive. `undef` means NO
# ORACLE, which is reported as untested rather than silently passing.
sub member_of ($v, $B) {
    my $s = structural_member($v, $B);
    return $s if defined $s;
    return interpretive_member($v, $B) if exists $INTERPRET_AS{$B};
    return undef;
}

# ---------------------------------------------------------------------------
# FACTOR 2: SUBSTITUTABILITY. Every operation of B must work on a value of A
# with no coercion. These are B's characteristic operations, run for effect --
# a die means the operation does not hold.
# ---------------------------------------------------------------------------
my %OPERATIONS_OF = (
    Str => [
        [ 'concat'  => sub { my $r = 'x' . $_[0] . 'y'; 1 } ],
        [ 'length'  => sub { my $n = length $_[0];      1 } ],
        [ 'uc'      => sub { my $s = uc $_[0];          1 } ],
        [ 'eq'      => sub { my $b = ($_[0] eq $_[0]);  1 } ],
        [ 'substr'  => sub { my $s = substr("$_[0]", 0, 1); 1 } ],
        [ 'match'   => sub { my $m = ("$_[0]" =~ /^/);  1 } ],
    ],
    Num => [
        [ 'add'     => sub { no warnings; my $n = $_[0] + 1;  1 } ],
        [ 'mul'     => sub { no warnings; my $n = $_[0] * 2;  1 } ],
        [ 'numcmp'  => sub { no warnings; my $b = ($_[0] <=> 0); 1 } ],
        [ 'abs'     => sub { no warnings; my $n = abs $_[0];  1 } ],
    ],
    Int => [
        [ 'modulo'  => sub { no warnings; my $n = $_[0] % 2;  1 } ],
        [ 'bitand'  => sub { no warnings; my $n = $_[0] & 1;  1 } ],
    ],
    # A reference's characteristic operations: it compares, it stringifies to
    # an address, and ref() classifies it. Deref is NOT here -- it is specific
    # to each ref kind, so it belongs to the kind, not to Ref.
    Ref => [
        [ 'ref'      => sub { my $k = ref $_[0];        1 } ],
        [ 'boolean'  => sub { my $b = $_[0] ? 1 : 0;    1 } ],
        [ 'refaddr'  => sub { no warnings; my $a = 0 + $_[0]; 1 } ],
        [ 'stringify'=> sub { no warnings; my $s = "$_[0]"; 1 } ],
    ],
    ScalarRef => [
        [ 'deref'    => sub { my $v = ${ $_[0] };       1 } ],
        [ 'assign'   => sub { ${ $_[0] } = ${ $_[0] };  1 } ],
    ],
    Object => [
        [ 'blessed'  => sub { my $c = blessed $_[0];    1 } ],
        [ 'can'      => sub { my $m = $_[0]->can('x');  1 } ],
        [ 'isa'      => sub { my $b = $_[0]->isa('X');  1 } ],
    ],
    Scalar => [
        [ 'assign'   => sub { my $copy = $_[0];         1 } ],
        [ 'boolean'  => sub { my $b = $_[0] ? 1 : 0;    1 } ],
        [ 'defined'  => sub { my $d = defined $_[0];    1 } ],
    ],
    List => [
        [ 'flatten'  => sub { my @l = ($_[0]);          1 } ],
        [ 'count'    => sub { my $n = scalar(() = ($_[0])); 1 } ],
    ],
);

# ---------------------------------------------------------------------------
# THE EDGES. Witnesses only -- the VERDICT is computed below.
#
# A type is only as tested as its witnesses are representative, so a type whose
# members disagree (Boolean: `true` passes Str membership, `false` does not)
# must list both. That is the one judgement a human still makes here, and it is
# checkable by reading it.
# ---------------------------------------------------------------------------
my $scalar_x   = 5;
my $scalar_ref = \$scalar_x;
my $ref_to_ref = \$scalar_ref;
my $lv_target  = 'hello';

my @EDGES = (
    # --- the scalar spine, interpretive oracle -----------------------------
    { child => 'Int',     parent => 'Num',
      witnesses => [ ['42', 42], ['0', 0], ['-7', -7] ] },
    { child => 'Num',     parent => 'Str',
      witnesses => [ ['3.5', 3.5], ['0.0', 0.0], ['-2.25', -2.25] ] },
    # Transitive, and asserted directly rather than inferred: if it held only
    # by transitivity through Num, a broken Int<:Num would hide here.
    { child => 'Int',     parent => 'Str',
      witnesses => [ ['42', 42], ['0', 0] ] },
    # THE EDGE THAT WAS WRONG. Both polarities, because `true` passes.
    { child => 'Boolean', parent => 'Str',
      witnesses => [ ['true', !!1], ['false', !!0] ] },

    # --- direct children of Scalar ----------------------------------------
    { child => 'Str',     parent => 'Scalar',
      witnesses => [ ['hi', 'hi'], ['empty', ''] ] },
    { child => 'Boolean', parent => 'Scalar',
      witnesses => [ ['true', !!1], ['false', !!0] ] },
    { child => 'Undef',   parent => 'Scalar',
      witnesses => [ ['undef', undef] ] },
    { child => 'Ref',     parent => 'Scalar',
      witnesses => [ ['ref-to-ref', $ref_to_ref] ] },

    # --- the reference branch, structural oracle --------------------------
    { child => 'ScalarRef', parent => 'Ref',
      witnesses => [ ['\\$x', $scalar_ref] ] },
    { child => 'ArrayRef',  parent => 'Ref',
      witnesses => [ ['[1,2]', [1,2]], ['[]', []] ] },
    { child => 'HashRef',   parent => 'Ref',
      witnesses => [ ['{a=>1}', {a=>1}], ['{}', {}] ] },
    { child => 'CodeRef',   parent => 'Ref',
      witnesses => [ ['sub{1}', sub {1}] ] },
    { child => 'GlobRef',   parent => 'Ref',
      witnesses => [ ['\\*STDOUT', \*STDOUT] ] },
    { child => 'Object',    parent => 'Ref',
      witnesses => [ ['bless {}', bless({}, 'Lattice::Witness')] ] },
    { child => 'Regex',     parent => 'Object',
      witnesses => [ ['qr/x/', qr/x/] ] },
    # LValueRef <: ScalarRef IS THE REFERENCE BRANCH'S BOOLEAN, and this suite
    # found it on its first run: factor 2 HOLDS (both `$$lv` and assignment
    # through it work) while factor 1 FAILS (perl reports LVALUE, a kind
    # distinct from SCALAR/REF). Exactly the shape that made `Boolean => 'Str'`
    # look right for years.
    #
    # THE MEASUREMENT THAT SETTLES IT is not the reftype name -- a name alone
    # would be a claim about capitalisation, the mistake made about `Ref`
    # earlier. It is that the alias does not follow a scalar CELL:
    #
    #     my $t = 'world'; my $lv = \substr($t, 0, 2);
    #     $t = 'REPLACED';
    #     $$lv       # 'RE', not 'wo' -- it tracks a RANGE of whatever $t holds
    #
    # A ScalarRef would still see the value it referred to. This sees a
    # position. The type library's own comment on this line says as much --
    # "\substr: aliases a RANGE, not a whole scalar" -- and then parents it to
    # ScalarRef anyway, so the rationale for the edge is written beside it and
    # contradicts it.
    #
    # MARKED `expect_disagreement` RATHER THAN FIXED. Repointing LValueRef
    # (presumably to Ref, alongside its siblings) is a lattice change with
    # consumers -- join/meet results move, and the backend's refusal message at
    # Context.pm:4553 is written against the current shape. That is perigrin's
    # call, not a test's. What this file does is refuse to let the
    # contradiction stay invisible: the edge is measured, the disagreement is
    # reported, and the day the table changes this marker must be removed or
    # the suite fails.
    { child => 'LValueRef', parent => 'ScalarRef',
      expect_disagreement =>
          'perl reports LVALUE (a range alias), not a scalar cell; the table '
        . "parents it to ScalarRef anyway. See this edge's comment.",
      witnesses => [ ['\\substr($s,0,2)', \substr($lv_target, 0, 2)] ] },

    # --- the collection branch --------------------------------------------
    # Scalar <: List is the arity claim: one value is a list of length 1.
    { child => 'Scalar',  parent => 'List',
      witnesses => [ ['42', 42], ['hi', 'hi'], ['undef', undef] ] },
);

# ---------------------------------------------------------------------------
# COMPUTE the verdict for every edge, ONCE, and reuse it everywhere below.
# ---------------------------------------------------------------------------
sub measure_edge ($e) {
    my ($A, $B) = ($e->{child}, $e->{parent});

    my (@f1_fail, @f1_untested, @f2_fail);
    for my $w ($e->{witnesses}->@*) {
        my ($label, $v) = $w->@*;

        my $m = member_of($v, $B);
        if    (!defined $m) { push @f1_untested, $label }
        elsif (!$m)         { push @f1_fail,     $label }

        for my $op (($OPERATIONS_OF{$B} // [])->@*) {
            push @f2_fail, "$label/$op->[0]" unless eval { $op->[1]->($v); 1 };
        }
    }

    # An edge with no membership oracle is UNTESTED, not passing. Reporting it
    # as a pass is how absence gets rendered as success -- the same defect the
    # corpus gate's shape leg had for a pure-GAP block.
    my $testable = !@f1_untested;
    my $f1 = @f1_fail ? 0 : 1;
    my $f2 = @f2_fail ? 0 : 1;

    return {
        child => $A, parent => $B,
        expect_disagreement => $e->{expect_disagreement},
        testable => $testable,
        f1 => $f1, f2 => $f2,
        holds => ($f1 && $f2) ? 1 : 0,
        f1_fail => \@f1_fail, f2_fail => \@f2_fail,
        untested => \@f1_untested,
    };
}

my @MEASURED = map { measure_edge($_) } @EDGES;

# THIS CHECK CAUGHT A REAL DEFECT IN THIS FILE, which is why it exists. The
# first version of the generalised suite had no `List` oracle, so
# `Scalar <: List` measured factor1 as... nothing, and the verdict came back
# holds=1 anyway. An edge with no way to answer was reporting a pass -- the
# same "absence rendered as success" shape as a pure-GAP corpus block being
# counted green. An unmeasurable edge must be loud.
subtest 'every edge has a membership oracle that can answer' => sub {
    my @blind = grep { !$_->{testable} } @MEASURED;
    is_deeply([ map {; "$_->{child} <: $_->{parent}" } @blind ], [],
        'no edge is silently unmeasurable')
        or diag("  add a %STRUCTURALLY_IS or %INTERPRET_AS oracle for the parent");
};

subtest 'the two factors, measured against perl' => sub {
    for my $m (@MEASURED) {
        my $edge = "$m->{child} <: $m->{parent}";
        note(sprintf('%-24s factor1=%s factor2=%s => holds=%d',
             $edge, ($m->{f1} ? 'yes' : 'NO '), ($m->{f2} ? 'yes' : 'NO '), $m->{holds}));
        note("    membership failed on: @{$m->{f1_fail}}")     if $m->{f1_fail}->@*;
        note("    operations failed:    @{$m->{f2_fail}}")     if $m->{f2_fail}->@*;
    }
    pass('measurements recorded above');
};

# THE ASSERTION THAT MATTERS. Not "the table says what I wrote down", but
# "the table says what PERL SAYS". Nothing here declares an expected answer:
# is_subtype is compared against a verdict computed from measurements.
subtest 'the type table agrees with perl on every edge' => sub {
    for my $m (@MEASURED) {
        my ($A, $B) = ($m->{child}, $m->{parent});
        my $table = Chalk::Grammar::Perl::TypeLibrary::is_subtype($A, $B) ? 1 : 0;

        # A KNOWN, RECORDED disagreement is asserted to PERSIST. Skipping it
        # would hide it; asserting it keeps the finding visible AND makes the
        # eventual fix fail here, forcing the marker to be removed rather than
        # left behind to rot.
        if (defined $m->{expect_disagreement}) {
            isnt($table, $m->{holds},
                "$A <: $B -- KNOWN DISAGREEMENT still present (table $table, perl $m->{holds})");
            note("    $m->{expect_disagreement}");
            note('    when the table is corrected, DELETE the expect_disagreement marker');
            next;
        }

        is($table, $m->{holds},
           sprintf('%s <: %s -- table says %s, perl says %s',
                   $A, $B, ($table ? 'yes' : 'no'), ($m->{holds} ? 'yes' : 'no')))
            or diag(sprintf(
                "  factor1 (membership)      : %s%s\n"
              . "  factor2 (substitutability): %s%s\n"
              . "  => a disagreement here means the TABLE is wrong, or the\n"
              . "     witnesses do not represent the type. Fix whichever;\n"
              . "     do NOT adjust the measurement to match the table.",
                ($m->{f1} ? 'holds' : 'FAILS'),
                ($m->{f1_fail}->@* ? " (on @{$m->{f1_fail}})" : ''),
                ($m->{f2} ? 'holds' : 'FAILS'),
                ($m->{f2_fail}->@* ? " (on @{$m->{f2_fail}})" : '')));
    }
};

# The asymmetry, asserted on whichever edges actually exhibit it. Substitut-
# ability without membership is the shape that made `Boolean => 'Str'` look
# right for so long, so it is worth pinning that the suite can still see it
# rather than assuming Boolean is the only instance.
subtest 'substitutability does not imply membership' => sub {
    my @asymmetric = grep { $_->{f2} && !$_->{f1} } @MEASURED;
    isnt(scalar @asymmetric, 0,
        'at least one edge passes factor 2 and fails factor 1');
    for my $m (@asymmetric) {
        note(sprintf('  %s <: %s -- every op of %s works, but %s is not a member',
             $m->{child}, $m->{parent}, $m->{parent},
             join(',', $m->{f1_fail}->@*)));
        next if defined $m->{expect_disagreement};   # asserted above instead
        is(Chalk::Grammar::Perl::TypeLibrary::is_subtype($m->{child}, $m->{parent}) ? 1 : 0,
           0, "  and the table correctly places $m->{child} OUTSIDE $m->{parent}");
    }
};

# A coercion existing is not evidence of a subtype relation. Kept because it is
# the argument that a reader reaches for first, and it is wrong.
subtest 'a coercion existing is not evidence: it must be lossless and behaviour-preserving' => sub {
    no warnings;
    my $aref = [1, 2, 3];
    my $as_num = 0 + $aref;

    ok($as_num > 0, 'ArrayRef DOES coerce to Num -- perl does not complain');
    is(0 + $as_num, $as_num, 'and the number round-trips as a number');
    is(ref(\$as_num), 'SCALAR', 'but it is NOT a reference any more -- the value is gone');
    ok(!eval { my @copy = @$as_num; 1 },
        'and dereferencing it fails -- the operations did not come along');

    is(Chalk::Grammar::Perl::TypeLibrary::is_subtype('ArrayRef', 'Num') ? 1 : 0, 0,
        'so the lattice does not place ArrayRef under Num');
    is(Chalk::Grammar::Perl::TypeLibrary::is_subtype('ArrayRef', 'Str') ? 1 : 0, 0,
        'nor under Str, for the same reason');
};

# WHAT IS STILL NOT COVERED, named rather than hidden. Untested is a fact about
# this suite; leaving it unstated would let absence read as success.
subtest 'the untested edges are named, not hidden' => sub {
    # `+{` disambiguator not needed here, but the leading string makes perl
    # read the block as a hashref constructor -- `map {; ... }` forces a block.
    my %tested = map {; "$_->{child} <: $_->{parent}" => 1 } @MEASURED;

    # EVERY EDGE, read out of the type library's OWN %PARENT table rather than
    # restated here -- so adding a type to the lattice makes it appear in this
    # list without anyone remembering to update the test. The library exposes
    # no enumeration accessor (is_subtype/join_types answer questions ABOUT
    # types, never "which types are there"), and inventing one just to satisfy
    # a test would put API surface on the library for the test's convenience.
    # Reading its source keeps ONE source of truth; the alternative -- a second
    # copy of the edge list in this file -- is the thing that goes stale.
    my $lib = 'lib/Chalk/Grammar/Perl/TypeLibrary.pm';
    open my $fh, '<', $lib or die "cannot read $lib: $!";
    my $src = do { local $/; <$fh> };
    close $fh;

    my ($table) = $src =~ /my \%PARENT = \((.*?)^    \);/ms;
    ok(defined $table, 'found the %PARENT table in the type library')
        or return;

    my @all_edges;
    for my $line (split /\n/, $table) {
        next if $line =~ /^\s*#/;                 # comment
        my ($child, $parent) = $line =~ /^\s*(\w+)\s*=>\s*'(\w+)'/ or next;
        push @all_edges, "$child <: $parent";
    }
    cmp_ok(scalar @all_edges, '>=', 20,
        'parsed a plausible number of edges out of %PARENT')
        or diag('  the table format changed; this parse needs updating');

    my @uncovered = sort grep { !$tested{$_} } @all_edges;
    note("covered:   " . scalar(keys %tested));
    note("uncovered: " . scalar(@uncovered));
    note("  $_") for @uncovered;

    # Not a failure -- a ratchet. It records the number so a REGRESSION in
    # coverage is visible, while leaving room to add edges incrementally.
    cmp_ok(scalar(keys %tested), '>=', 17,
        'edge coverage does not regress below what has been measured');
};

done_testing;
