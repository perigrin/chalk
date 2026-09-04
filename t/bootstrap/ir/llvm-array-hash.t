# ABOUTME: Tests for Array/Hash/Ref LLVM lowering (G4 value-rep group).
# ABOUTME: Validates R1-R8 corpus cases plus adversarial OOB/missing-key cases.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::Return;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Helper: run LLVM IR text through lli and return output
sub run_ll {
    my ($ll) = @_;
    use File::Temp qw(tempfile);
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out = `$LLI $tmpfile 2>/dev/null`;
    chomp $out;
    return $out;
}


# Helper: make the graph a PROGRAM -- it PRINTS its value the way a compiled
# program does (stdout), rather than exposing it through a harness type tag.
# Print takes a Str, so a non-Str value is bridged with a Coerce, exactly as a
# source program's stringification does. The Return yields Undef because a
# program has no return value -- only stdout and an exit status.
sub _print_and_return {
    my ($f, $val) = @_;

    my $arg = $val;
    if ($val->stamp ne 'Str') {
        $arg = $f->make('Coerce', inputs => [$val],
                        from_repr => $val->stamp, to_repr => 'Str');
        $arg->set_stamp('Str');
    }

    my $start = $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$arg]);
    $print->set_control_in($start);

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);
    return $ret;
}

# Helper: build a factory and common constants
sub _mk {
    my $f = Chalk::IR::NodeFactory->new;
    return $f;
}

# ---------------------------------------------------------------------------
# A1: ArrayRef (1,2,3) + Length -> 3
#
# Equivalent to: my @a = (1,2,3); scalar @a
# Result: 3. Canonical ArrayRef; Length reads its len field.
# ---------------------------------------------------------------------------
subtest 'A1: ArrayRef(1,2,3) + Length -> 3' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $len = $f->make('Length', inputs => [$arr]);
    $len->set_stamp('Int');

    my $ret = _print_and_return($f, $len);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A1 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/,   'A1 .ll: no Perl_ symbols');
        unlike($ll, qr/\bSV\b/,  'A1 .ll: no SV symbols');
        unlike($ll, qr/\bAV\b/,  'A1 .ll: no AV symbols');
        unlike($ll, qr/\bHV\b/,  'A1 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A1 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '3', 'A1 lli output is 3 (scalar @a = 3)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A2: ArrayRef + Subscript (in-bounds) -> 2
#
# Equivalent to: my @a = (1,2,3); $a[1]
# Result: 2. Bounds check is emitted but index=1 < len=3 always.
# ---------------------------------------------------------------------------
subtest 'A2: ArrayRef(1,2,3) + Subscript(idx=1) -> 2' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A2 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A2 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A2 .ll: no libperl reference');
        like($ll, qr/icmp ult/,  'A2 .ll: bounds check (icmp ult) present');

        my $out = run_ll($ll);
        is($out, '2', 'A2 lli output is 2 ($a[1] = 2)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A3: Subscript out-of-bounds -> undef
#
# Equivalent to: my @a = (1,2,3); $a[9]
# Result: undef. Bounds check fails, undef slot returned. Never segfaults.
# ---------------------------------------------------------------------------
subtest 'A3: Subscript OOB (idx=9 on len=3) -> undef' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '9', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_stamp('Slot');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A3 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A3 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A3 .ll: no libperl reference');
        like($ll, qr/icmp ult/,  'A3 .ll: bounds check (icmp ult) present');

        my $out = run_ll($ll);
        # Printed, an undef and an Int 0 are both "". The repr assertion keeps
        # what the type tag used to carry: this read is a runtime-checked Slot,
        # not a value folded at compile time.
        is($elem->stamp, 'Slot',
            'A3 the OOB read is a Slot (runtime defined-bit)');
        is($out, '', 'A3 lli output is empty (OOB array read prints undef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A3d: Defined over an OOB array read -> false  (019f61ab)
#
# Equivalent to: my @a = (1,2,3); defined($a[9])
# The OOB Subscript is repr Slot (its runtime defined bit is the answer).
# defined() over it must consult the runtime bounds/defined check, NOT fold to
# compile-time true. Guards the silent miscompile where Defined(Slot) returned
# i1 true and defined() of an out-of-bounds element wrongly reported true.
# ---------------------------------------------------------------------------
subtest 'A3d: Defined(Subscript OOB, Slot) -> false' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '9', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_stamp('Slot');

    my $def = $f->make('Defined', inputs => [$elem]);
    $def->set_stamp('Boolean');

    my $ret = _print_and_return($f, $def);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A3d lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        like($ll, qr/icmp ult/, 'A3d .ll: bounds check (icmp ult) present (not folded)');

        my $out = run_ll($ll);
        # A false Boolean and an undef both print "". The repr assertion is what
        # keeps this test honest: without it a regression that dropped the
        # Defined() entirely and printed the raw undef Slot would still pass.
        # A3e is the other half of the teeth -- defined() of an in-bounds
        # element must print "1", so "always empty" cannot pass both.
        is($def->stamp, 'Boolean',
            'A3d the result is a Boolean (defined()), not the raw Slot');
        is($out, '',
            'A3d lli output is empty (defined(OOB element) is false)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A3e: Defined over an in-bounds array read -> true  (019f61ab, teeth)
#
# Equivalent to: my @a = (1,2,3); defined($a[1])
# The in-bounds Subscript is repr Int. defined() of a defined element is true.
# Bilateral teeth for A3d: the fix must not turn every array-read defined() false.
# ---------------------------------------------------------------------------
subtest 'A3e: Defined(Subscript in-bounds, Int) -> true' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_stamp('Int');

    my $def = $f->make('Defined', inputs => [$elem]);
    $def->set_stamp('Boolean');

    my $ret = _print_and_return($f, $def);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A3e lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        my $out = run_ll($ll);
        is($def->stamp, 'Boolean',
            'A3e the result is a Boolean (defined()), not the element value');
        is($out, '1',
            'A3e lli output is 1 (defined(in-bounds element) is true)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A3f: DefinedOr over an OOB array read -> 99 (rhs)  (019f6654)
#
# Equivalent to: my @a = (1,2,3); $a[9] // 99
# The OOB Subscript is repr Slot. `//` must branch on its RUNTIME defined bit
# and, on the DEFINED path, yield the Slot's i64 PAYLOAD (not the def-bit).
# The bug: _lower_defined_or treated a Slot LHS as always-defined and used the
# i1 def-bit as the i64 phi value -- lli rejected "i1 but expected i64", and a
# well-typed variant would silently yield the element instead of the rhs on OOB.
# ---------------------------------------------------------------------------
subtest 'A3f: DefinedOr(Subscript OOB Slot, 99) -> 99 (rhs)' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '9', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_stamp('Slot');

    my $rhs = $f->make('Constant', value => '99', const_type => 'integer');
    $rhs->set_stamp('Int');

    my $dor = $f->make('DefinedOr', inputs => [$elem, $rhs]);
    $dor->set_stamp('Int');

    my $ret = _print_and_return($f, $dor);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A3f lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        like($ll, qr/icmp ult/, 'A3f .ll: bounds check (icmp ult) present (not folded)');

        my $out = run_ll($ll);
        is($out, '99', 'A3f lli output is 99 (OOB element // 99 = 99)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A3g: DefinedOr over an in-bounds array read -> 2 (element)  (019f6654 teeth)
#
# Equivalent to: my @a = (1,2,3); $a[1] // 99
# The in-bounds Subscript is repr Int (always defined). `//` must yield the
# element, not the rhs. Bilateral teeth for A3f: the Slot fix must not make
# every `element // rhs` yield the rhs.
# ---------------------------------------------------------------------------
subtest 'A3g: DefinedOr(Subscript in-bounds Int, 99) -> 2 (element)' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_stamp('Int');

    my $rhs = $f->make('Constant', value => '99', const_type => 'integer');
    $rhs->set_stamp('Int');

    my $dor = $f->make('DefinedOr', inputs => [$elem, $rhs]);
    $dor->set_stamp('Int');

    my $ret = _print_and_return($f, $dor);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A3g lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        my $out = run_ll($ll);
        is($out, '2', 'A3g lli output is 2 (in-bounds element // 99 = element)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A4: HashRef + Subscript (existing key) -> 1
#
# Equivalent to: my %h = (a => 1, b => 2); $h{a}
# Result: 1. Linear-scan lookup finds key "a".
# ---------------------------------------------------------------------------
subtest 'A4: HashRef(a=>1,b=>2) + Subscript("a") -> 1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_stamp('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_stamp('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_stamp('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_stamp('Int');

    my $hash = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_stamp('HashRef');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_stamp('Str');

    my $val = $f->make('Subscript', inputs => [$hash, $lk]);
    $val->set_stamp('Int');

    my $ret = _print_and_return($f, $val);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A4 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A4 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A4 .ll: no libperl reference');
        like($ll, qr/memcmp/,    'A4 .ll: uses memcmp for key comparison');

        my $out = run_ll($ll);
        is($out, '1', 'A4 lli output is 1 ($h{a} = 1)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A5: Subscript missing key -> undef
#
# Equivalent to: my %h = (a => 1, b => 2); $h{z}
# Result: undef. Key "z" not found -> undef slot.
# ---------------------------------------------------------------------------
subtest 'A5: Subscript missing key -> undef' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_stamp('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_stamp('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_stamp('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_stamp('Int');

    my $hash = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_stamp('HashRef');

    my $lk = $f->make('Constant', value => 'z', const_type => 'string');
    $lk->set_stamp('Str');

    my $val = $f->make('Subscript', inputs => [$hash, $lk]);
    $val->set_stamp('Slot');

    my $ret = _print_and_return($f, $val);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A5 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A5 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A5 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($val->stamp, 'Slot',
            'A5 the missing-key read is a Slot (runtime defined-bit)');
        is($out, '', 'A5 lli output is empty (missing key prints undef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A6: ArrayRef [1,2,3] + deref -> 1
#
# Equivalent to: my $r = [1,2,3]; $r->[0]
# Result: 1. ArrayRef = pointer to Array; deref = load-through-pointer.
# ---------------------------------------------------------------------------
subtest 'A6: ArrayRef[1,2,3] deref [0] -> 1' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $ref = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $ref->set_stamp('ArrayRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '@');
    $deref->set_stamp('Array');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$deref, $idx]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A6 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A6 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A6 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '1', 'A6 lli output is 1 ($r->[0] = 1)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A7: HashRef {a=>1, b=>2} + deref -> 1
#
# Equivalent to: my $r = {a=>1, b=>2}; $r->{a}
# Result: 1. HashRef = pointer to Hash; deref = load-through-pointer.
# ---------------------------------------------------------------------------
subtest 'A7: HashRef{a=>1,b=>2} deref {a} -> 1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_stamp('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_stamp('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_stamp('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_stamp('Int');

    my $ref = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $ref->set_stamp('HashRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '%');
    $deref->set_stamp('Hash');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_stamp('Str');

    my $val = $f->make('Subscript', inputs => [$deref, $lk]);
    $val->set_stamp('Int');

    my $ret = _print_and_return($f, $val);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A7 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A7 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A7 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '1', 'A7 lli output is 1 ($r->{a} = 1)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A8: Assign(Subscript-lvalue) + return stored value -> 42
#
# Equivalent to: my @a = (1,2,3); $a[0] = 42; $a[0]
# Result: 42. Assign over Subscript lvalue stores and returns the value.
# ---------------------------------------------------------------------------
subtest 'A8: Assign(Subscript-lvalue, 42) -> 42' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_stamp('Int');

    # Subscript lvalue
    my $lval = $f->make('Subscript', inputs => [$arr, $idx]);
    $lval->set_stamp('Int');

    my $newval = $f->make('Constant', value => '42', const_type => 'integer');
    $newval->set_stamp('Int');

    # Assign returns the stored value (42)
    my $elem = $f->make('Assign', inputs => [$lval, $newval]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A8 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A8 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '42', 'A8 lli output is 42 ($a[0]=42; $a[0])');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A9: Assign(Hash-Subscript-lvalue) -> 99
#
# Equivalent to: my %h = (k => 0); $h{k} = 99; $h{k}
# Result: 99. Assign over hash Subscript lvalue stores and returns 99.
# ---------------------------------------------------------------------------
subtest 'A9: Assign(Hash-Subscript-lvalue, 99) -> 99' => sub {
    my $f = _mk();

    my $kk = $f->make('Constant', value => 'k', const_type => 'string');
    $kk->set_stamp('Str');
    my $v0 = $f->make('Constant', value => '0', const_type => 'integer');
    $v0->set_stamp('Int');

    my $hash = $f->make('HashLiteral', inputs => [$kk, $v0]);
    $hash->set_stamp('HashRef');

    my $wk = $f->make('Constant', value => 'k', const_type => 'string');
    $wk->set_stamp('Str');

    # Hash Subscript lvalue
    my $lval = $f->make('Subscript', inputs => [$hash, $wk]);
    $lval->set_stamp('Int');

    my $wv = $f->make('Constant', value => '99', const_type => 'integer');
    $wv->set_stamp('Int');

    # Assign returns the stored value (99)
    my $val = $f->make('Assign', inputs => [$lval, $wv]);
    $val->set_stamp('Int');

    my $ret = _print_and_return($f, $val);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A9 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A9 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '99', 'A9 lli output is 99 ($h{k}=99; $h{k})');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A10: Nested ArrayRef deref -> 3
#
# Equivalent to: my $r = [[1,2],[3,4]]; $r->[1][0]
# Result: 3. Two load-through-pointer levels.
# ---------------------------------------------------------------------------
subtest 'A10: nested ArrayRef [[1,2],[3,4]] ->[1][0] -> 3' => sub {
    my $f = _mk();

    # Inner arrays
    my $ca1 = $f->make('Constant', value => '1', const_type => 'integer');
    $ca1->set_stamp('Int');
    my $ca2 = $f->make('Constant', value => '2', const_type => 'integer');
    $ca2->set_stamp('Int');
    my $ca3 = $f->make('Constant', value => '3', const_type => 'integer');
    $ca3->set_stamp('Int');
    my $ca4 = $f->make('Constant', value => '4', const_type => 'integer');
    $ca4->set_stamp('Int');

    # Inner refs (canonical ArrayRef with inline elements)
    my $ref0 = $f->make('ArrayLiteral', inputs => [$ca1, $ca2]);
    $ref0->set_stamp('ArrayRef');
    my $ref1 = $f->make('ArrayLiteral', inputs => [$ca3, $ca4]);
    $ref1->set_stamp('ArrayRef');

    # Outer array of refs: [(ref to [1,2]), (ref to [3,4])]
    my $outer_ref = $f->make('ArrayLiteral', inputs => [$ref0, $ref1]);
    $outer_ref->set_stamp('ArrayRef');

    # Deref outer: $r->[1] = inner array ref (an ArrayRef pointer)
    my $outer_arr = $f->make('PostfixDeref', inputs => [$outer_ref], sigil => '@');
    $outer_arr->set_stamp('Array');

    my $idx1 = $f->make('Constant', value => '1', const_type => 'integer');
    $idx1->set_stamp('Int');

    # $r->[1] returns a slot containing an ArrayRef pointer
    my $inner_ref_slot = $f->make('Subscript', inputs => [$outer_arr, $idx1]);
    $inner_ref_slot->set_stamp('ArrayRef');

    # Deref inner: $r->[1][0]
    my $inner_arr = $f->make('PostfixDeref', inputs => [$inner_ref_slot], sigil => '@');
    $inner_arr->set_stamp('Array');

    my $idx0 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx0->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$inner_arr, $idx0]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A10 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A10 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '3', 'A10 lli output is 3 ($r->[1][0] = 3)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A11: a Slot read discriminates defined from undefined at runtime.
#
# The Slot repr is a tagged scalar {i1 defined, i64 payload}. What matters to a
# program is that the defined-bit actually selects between printing the payload
# and printing nothing -- so this reads the SAME array at an in-bounds and an
# out-of-bounds index and requires the two outputs to differ. A lowering that
# ignored the defined-bit would make both reads print the same thing.
# ---------------------------------------------------------------------------
subtest 'A11: a Slot read discriminates defined from undefined at runtime' => sub {
    # Build the same array twice and read it at an in-bounds and an
    # out-of-bounds index, both typed Slot. Both graphs are identical apart
    # from the index, so the two outputs can only differ via the Slot's
    # runtime defined-bit -- which is the property the printed program has to
    # preserve.
    my @out;
    for my $idx_val ('1', '9') {
        my $f = _mk();

        my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
        $c1->set_stamp('Int');
        my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
        $c2->set_stamp('Int');
        my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
        $c3->set_stamp('Int');

        my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
        $arr->set_stamp('ArrayRef');

        my $idx = $f->make('Constant', value => $idx_val, const_type => 'integer');
        $idx->set_stamp('Int');

        my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
        $elem->set_stamp('Slot');
        is($elem->stamp, 'Slot', "A11 idx=$idx_val read is a Slot");

        my $ret = _print_and_return($f, $elem);

        my $ll;
        eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
        ok(!$@, "A11 idx=$idx_val lower() does not die: $@") or diag("error: $@");
        like($ll, qr/icmp ult/, "A11 idx=$idx_val bounds check present (not folded)");
        push @out, run_ll($ll);
    }

    is($out[0], '2',  'A11 in-bounds Slot prints its payload');
    is($out[1], '',   'A11 out-of-bounds Slot prints undef (empty)');
    isnt($out[0], $out[1],
        'A11 the defined-bit actually discriminates the two reads');

    done_testing;
};

# ---------------------------------------------------------------------------
# A12: canonical Subscript(Array, idx) -> 2  (Phase 1.1)
#
# Subscript with Array container dispatches to bounds-checked slot load.
# Equivalent to: my @a = (1,2,3); $a[1] -> 2
# ---------------------------------------------------------------------------
subtest 'A12: canonical Subscript(ArrayRef, idx=1) -> 2' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A12 Subscript(Array) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A12 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A12 .ll: no libperl reference');
        like($ll, qr/icmp ult/,  'A12 .ll: bounds check (icmp ult) present');

        my $out = run_ll($ll);
        is($out, '2', 'A12 lli output is 2 ($a[1] via Subscript)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A13: canonical Subscript(Hash, key) -> 1  (Phase 1.1)
#
# Subscript with Hash container dispatches to memcmp key scan.
# Equivalent to: my %h = (a=>1, b=>2); $h{a} -> 1
# ---------------------------------------------------------------------------
subtest 'A13: canonical Subscript(HashRef, key="a") -> 1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_stamp('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_stamp('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_stamp('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_stamp('Int');

    my $hash = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_stamp('HashRef');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_stamp('Str');

    my $elem = $f->make('Subscript', inputs => [$hash, $lk]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A13 Subscript(Hash) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A13 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A13 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '1', 'A13 lli output is 1 ($h{a} via Subscript)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A14: canonical PostfixDeref(@, ArrayRef) -> Array  (Phase 1.2)
#
# PostfixDeref(sigil="@", ref) deref an ArrayRef to Array*.
# Equivalent to: my $r = [1,2,3]; ${deref $r}[0] -> 1 via Subscript
# ---------------------------------------------------------------------------
subtest 'A14: canonical PostfixDeref(sigil=@, ArrayRef) deref -> 1' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $ref = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $ref->set_stamp('ArrayRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '@');
    $deref->set_stamp('Array');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$deref, $idx]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A14 PostfixDeref(@) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A14 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A14 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '1', 'A14 lli output is 1 ($r->[0] via PostfixDeref)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A15: canonical PostfixDeref(%, HashRef) -> Hash  (Phase 1.2)
#
# PostfixDeref(sigil="%", ref) derefs a HashRef to Hash*.
# ---------------------------------------------------------------------------
subtest 'A15: canonical PostfixDeref(sigil=%, HashRef) deref -> 1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_stamp('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_stamp('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_stamp('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_stamp('Int');

    my $ref = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $ref->set_stamp('HashRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '%');
    $deref->set_stamp('Hash');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_stamp('Str');

    my $val = $f->make('Subscript', inputs => [$deref, $lk]);
    $val->set_stamp('Int');

    my $ret = _print_and_return($f, $val);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A15 PostfixDeref(%) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A15 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A15 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '1', 'A15 lli output is 1 ($r->{a} via PostfixDeref)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A16: canonical ArrayRef used as container for Length  (Phase 2.1)
#
# ArrayRef(1,2,3) :ArrayRef + Length -> 3.
# The canonical ref-producing constructor feeds Length directly.
# ---------------------------------------------------------------------------
subtest 'A16: canonical ArrayRef(1,2,3) + Length -> 3' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $aref = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $aref->set_stamp('ArrayRef');

    my $len = $f->make('Length', inputs => [$aref]);
    $len->set_stamp('Int');

    my $ret = _print_and_return($f, $len);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A16 canonical ArrayRef + Length does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A16 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '3', 'A16 lli output is 3 (Length via canonical ArrayRef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A17: canonical ArrayRef used for Subscript  (Phase 2.1)
#
# ArrayRef(1,2,3) :ArrayRef + Subscript(idx=1) -> 2.
# ---------------------------------------------------------------------------
subtest 'A17: canonical ArrayRef(1,2,3) + Subscript(1) -> 2' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $aref = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $aref->set_stamp('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_stamp('Int');

    my $elem = $f->make('Subscript', inputs => [$aref, $idx]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A17 canonical ArrayRef + Subscript does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A17 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '2', 'A17 lli output is 2 (Subscript via canonical ArrayRef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A18: canonical HashRef used for Subscript  (Phase 2.1)
#
# HashRef(a=>1,b=>2) :HashRef + Subscript("a") -> 1.
# ---------------------------------------------------------------------------
subtest 'A18: canonical HashRef(a=>1,b=>2) + Subscript("a") -> 1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_stamp('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_stamp('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_stamp('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_stamp('Int');

    my $href = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $href->set_stamp('HashRef');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_stamp('Str');

    my $elem = $f->make('Subscript', inputs => [$href, $lk]);
    $elem->set_stamp('Int');

    my $ret = _print_and_return($f, $elem);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A18 canonical HashRef + Subscript does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A18 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, '1', 'A18 lli output is 1 (Subscript via canonical HashRef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A19: Assign(Subscript-lvalue) emits a store  (Phase 3.0)
#
# Assign(%lval, %nv) where %lval = Subscript(%arr, %idx=0) in lvalue position.
# The Assign detects Subscript lvalue and emits an in-place slot write.
# It returns the stored value (%nv=42). Verifies: no die, store emitted, 42.
# ---------------------------------------------------------------------------
subtest 'A19: Assign(Subscript-lvalue, 42) emits store and returns 42' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_stamp('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_stamp('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_stamp('ArrayRef');

    # Subscript(%arr, idx=0) in lvalue position
    my $idx0 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx0->set_stamp('Int');
    my $lval = $f->make('Subscript', inputs => [$arr, $idx0]);
    $lval->set_stamp('Int');

    my $nv = $f->make('Constant', value => '42', const_type => 'integer');
    $nv->set_stamp('Int');

    # Assign is the element store; its return value is nv (42).
    my $store = $f->make('Assign', inputs => [$lval, $nv]);
    $store->set_stamp('Int');

    # Return the Assign result (42).
    my $ret = _print_and_return($f, $store);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "A19 Assign(Subscript-lvalue) lower() does not die: $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A19 .ll: no libperl reference');
        like($ll, qr/store i1 true/, 'A19 .ll: emits slot-defined store');

        my $out = run_ll($ll);
        is($out, '42', 'A19 lli output is 42 (Assign returns stored value)');
    }

    done_testing;
};

done_testing;
