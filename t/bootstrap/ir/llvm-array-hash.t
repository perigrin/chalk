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

# Helper: build a factory and common constants
sub _mk {
    my $f = Chalk::IR::NodeFactory->new;
    return $f;
}

# ---------------------------------------------------------------------------
# A1: ArrayRef (1,2,3) + Length -> Int:3
#
# Equivalent to: my @a = (1,2,3); scalar @a
# Result: Int:3. Canonical ArrayRef; Length reads its len field.
# ---------------------------------------------------------------------------
subtest 'A1: ArrayRef(1,2,3) + Length -> Int:3' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('ArrayRef');

    my $len = $f->make('Length', inputs => [$arr]);
    $len->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$len]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A1 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/,   'A1 .ll: no Perl_ symbols');
        unlike($ll, qr/\bSV\b/,  'A1 .ll: no SV symbols');
        unlike($ll, qr/\bAV\b/,  'A1 .ll: no AV symbols');
        unlike($ll, qr/\bHV\b/,  'A1 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A1 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:3', 'A1 lli output is Int:3 (scalar @a = 3)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A2: ArrayRef + Subscript (in-bounds) -> Int:2
#
# Equivalent to: my @a = (1,2,3); $a[1]
# Result: Int:2. Bounds check is emitted but index=1 < len=3 always.
# ---------------------------------------------------------------------------
subtest 'A2: ArrayRef(1,2,3) + Subscript(idx=1) -> Int:2' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A2 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A2 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A2 .ll: no libperl reference');
        like($ll, qr/icmp ult/,  'A2 .ll: bounds check (icmp ult) present');

        my $out = run_ll($ll);
        is($out, 'Int:2', 'A2 lli output is Int:2 ($a[1] = 2)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A3: Subscript out-of-bounds -> Undef:
#
# Equivalent to: my @a = (1,2,3); $a[9]
# Result: Undef:. Bounds check fails, undef slot returned. Never segfaults.
# ---------------------------------------------------------------------------
subtest 'A3: Subscript OOB (idx=9 on len=3) -> Undef:' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('ArrayRef');

    my $idx = $f->make('Constant', value => '9', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_representation('Slot');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A3 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A3 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A3 .ll: no libperl reference');
        like($ll, qr/icmp ult/,  'A3 .ll: bounds check (icmp ult) present');

        my $out = run_ll($ll);
        is($out, 'Undef:', 'A3 lli output is Undef: (OOB array read)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A4: HashRef + Subscript (existing key) -> Int:1
#
# Equivalent to: my %h = (a => 1, b => 2); $h{a}
# Result: Int:1. Linear-scan lookup finds key "a".
# ---------------------------------------------------------------------------
subtest 'A4: HashRef(a=>1,b=>2) + Subscript("a") -> Int:1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $hash = $f->make('HashRef', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_representation('HashRef');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('Subscript', inputs => [$hash, $lk]);
    $val->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A4 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A4 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A4 .ll: no libperl reference');
        like($ll, qr/memcmp/,    'A4 .ll: uses memcmp for key comparison');

        my $out = run_ll($ll);
        is($out, 'Int:1', 'A4 lli output is Int:1 ($h{a} = 1)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A5: Subscript missing key -> Undef:
#
# Equivalent to: my %h = (a => 1, b => 2); $h{z}
# Result: Undef:. Key "z" not found -> undef slot.
# ---------------------------------------------------------------------------
subtest 'A5: Subscript missing key -> Undef:' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $hash = $f->make('HashRef', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_representation('HashRef');

    my $lk = $f->make('Constant', value => 'z', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('Subscript', inputs => [$hash, $lk]);
    $val->set_representation('Slot');

    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A5 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A5 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A5 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Undef:', 'A5 lli output is Undef: (missing key)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A6: ArrayRef [1,2,3] + deref -> Int:1
#
# Equivalent to: my $r = [1,2,3]; $r->[0]
# Result: Int:1. ArrayRef = pointer to Array; deref = load-through-pointer.
# ---------------------------------------------------------------------------
subtest 'A6: ArrayRef[1,2,3] deref [0] -> Int:1' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $ref = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $ref->set_representation('ArrayRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '@');
    $deref->set_representation('Array');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$deref, $idx]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A6 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A6 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A6 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:1', 'A6 lli output is Int:1 ($r->[0] = 1)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A7: HashRef {a=>1, b=>2} + deref -> Int:1
#
# Equivalent to: my $r = {a=>1, b=>2}; $r->{a}
# Result: Int:1. HashRef = pointer to Hash; deref = load-through-pointer.
# ---------------------------------------------------------------------------
subtest 'A7: HashRef{a=>1,b=>2} deref {a} -> Int:1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $ref = $f->make('HashRef', inputs => [$ka, $v1, $kb, $v2]);
    $ref->set_representation('HashRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '%');
    $deref->set_representation('Hash');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('Subscript', inputs => [$deref, $lk]);
    $val->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A7 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A7 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A7 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:1', 'A7 lli output is Int:1 ($r->{a} = 1)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A8: ArrayWrite + Subscript -> Int:42
#
# Equivalent to: my @a = (1,2,3); $a[0] = 42; $a[0]
# Result: Int:42. Store then load.
# ---------------------------------------------------------------------------
subtest 'A8: ArrayWrite(0,42) then Subscript(0) -> Int:42' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('ArrayRef');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');

    my $newval = $f->make('Constant', value => '42', const_type => 'integer');
    $newval->set_representation('Int');

    # ArrayWrite returns the array (for chaining)
    my $arr2 = $f->make('ArrayWrite', inputs => [$arr, $idx, $newval]);
    $arr2->set_representation('Array');

    my $idx2 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx2->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$arr2, $idx2]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A8 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A8 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:42', 'A8 lli output is Int:42 ($a[0]=42; $a[0])');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A9: HashWrite + Subscript -> Int:99
#
# Equivalent to: my %h = (k => 0); $h{k} = 99; $h{k}
# Result: Int:99. Store then load.
# ---------------------------------------------------------------------------
subtest 'A9: HashWrite then Subscript -> Int:99' => sub {
    my $f = _mk();

    my $kk = $f->make('Constant', value => 'k', const_type => 'string');
    $kk->set_representation('Str');
    my $v0 = $f->make('Constant', value => '0', const_type => 'integer');
    $v0->set_representation('Int');

    my $hash = $f->make('HashRef', inputs => [$kk, $v0]);
    $hash->set_representation('HashRef');

    my $wk = $f->make('Constant', value => 'k', const_type => 'string');
    $wk->set_representation('Str');
    my $wv = $f->make('Constant', value => '99', const_type => 'integer');
    $wv->set_representation('Int');

    # HashWrite returns the hash (for chaining)
    my $hash2 = $f->make('HashWrite', inputs => [$hash, $wk, $wv]);
    $hash2->set_representation('Hash');

    my $rk = $f->make('Constant', value => 'k', const_type => 'string');
    $rk->set_representation('Str');

    my $val = $f->make('Subscript', inputs => [$hash2, $rk]);
    $val->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A9 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A9 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:99', 'A9 lli output is Int:99 ($h{k}=99; $h{k})');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A10: Nested ArrayRef deref -> Int:3
#
# Equivalent to: my $r = [[1,2],[3,4]]; $r->[1][0]
# Result: Int:3. Two load-through-pointer levels.
# ---------------------------------------------------------------------------
subtest 'A10: nested ArrayRef [[1,2],[3,4]] ->[1][0] -> Int:3' => sub {
    my $f = _mk();

    # Inner arrays
    my $ca1 = $f->make('Constant', value => '1', const_type => 'integer');
    $ca1->set_representation('Int');
    my $ca2 = $f->make('Constant', value => '2', const_type => 'integer');
    $ca2->set_representation('Int');
    my $ca3 = $f->make('Constant', value => '3', const_type => 'integer');
    $ca3->set_representation('Int');
    my $ca4 = $f->make('Constant', value => '4', const_type => 'integer');
    $ca4->set_representation('Int');

    # Inner refs (canonical ArrayRef with inline elements)
    my $ref0 = $f->make('ArrayRef', inputs => [$ca1, $ca2]);
    $ref0->set_representation('ArrayRef');
    my $ref1 = $f->make('ArrayRef', inputs => [$ca3, $ca4]);
    $ref1->set_representation('ArrayRef');

    # Outer array of refs: [(ref to [1,2]), (ref to [3,4])]
    my $outer_ref = $f->make('ArrayRef', inputs => [$ref0, $ref1]);
    $outer_ref->set_representation('ArrayRef');

    # Deref outer: $r->[1] = inner array ref (an ArrayRef pointer)
    my $outer_arr = $f->make('PostfixDeref', inputs => [$outer_ref], sigil => '@');
    $outer_arr->set_representation('Array');

    my $idx1 = $f->make('Constant', value => '1', const_type => 'integer');
    $idx1->set_representation('Int');

    # $r->[1] returns a slot containing an ArrayRef pointer
    my $inner_ref_slot = $f->make('Subscript', inputs => [$outer_arr, $idx1]);
    $inner_ref_slot->set_representation('ArrayRef');

    # Deref inner: $r->[1][0]
    my $inner_arr = $f->make('PostfixDeref', inputs => [$inner_ref_slot], sigil => '@');
    $inner_arr->set_representation('Array');

    my $idx0 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx0->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$inner_arr, $idx0]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A10 lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A10 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:3', 'A10 lli output is Int:3 ($r->[1][0] = 3)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A11: TypeTag extended — llvm_prefixes contains Slot entry.
#
# The Slot repr (tagged-scalar {i1,i64}) needs a TypeTag entry so the
# LLVM epilogue can branch on the defined-bit to print Int: or Undef:.
# This is an EXTENSION of the TypeTag contract (not a duplication).
# ---------------------------------------------------------------------------
subtest 'A11: TypeTag has Slot entry in llvm_prefixes' => sub {
    use_ok('Chalk::CodeGen::Harness::TypeTag');
    my $prefixes = Chalk::CodeGen::Harness::TypeTag->llvm_prefixes();
    ok(exists $prefixes->{Slot}, 'TypeTag::llvm_prefixes has Slot key');
    if (exists $prefixes->{Slot}) {
        ok(defined $prefixes->{Slot}{perl_tag_prefix_int},   'Slot entry has perl_tag_prefix_int');
        ok(defined $prefixes->{Slot}{perl_tag_prefix_undef}, 'Slot entry has perl_tag_prefix_undef');
        is($prefixes->{Slot}{perl_tag_prefix_int},   'Int:',    'Slot int prefix is Int:');
        is($prefixes->{Slot}{perl_tag_prefix_undef}, 'Undef:',  'Slot undef prefix is Undef:');
    }
    done_testing;
};

# ---------------------------------------------------------------------------
# A12: canonical Subscript(Array, idx) -> Int:2  (Phase 1.1)
#
# Subscript with Array container dispatches to bounds-checked slot load.
# Equivalent to: my @a = (1,2,3); $a[1] -> Int:2
# ---------------------------------------------------------------------------
subtest 'A12: canonical Subscript(ArrayRef, idx=1) -> Int:2' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$arr, $idx]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A12 Subscript(Array) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A12 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A12 .ll: no libperl reference');
        like($ll, qr/icmp ult/,  'A12 .ll: bounds check (icmp ult) present');

        my $out = run_ll($ll);
        is($out, 'Int:2', 'A12 lli output is Int:2 ($a[1] via Subscript)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A13: canonical Subscript(Hash, key) -> Int:1  (Phase 1.1)
#
# Subscript with Hash container dispatches to memcmp key scan.
# Equivalent to: my %h = (a=>1, b=>2); $h{a} -> Int:1
# ---------------------------------------------------------------------------
subtest 'A13: canonical Subscript(HashRef, key="a") -> Int:1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $hash = $f->make('HashRef', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_representation('HashRef');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $elem = $f->make('Subscript', inputs => [$hash, $lk]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A13 Subscript(Hash) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A13 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A13 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:1', 'A13 lli output is Int:1 ($h{a} via Subscript)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A14: canonical PostfixDeref(@, ArrayRef) -> Array  (Phase 1.2)
#
# PostfixDeref(sigil="@", ref) deref an ArrayRef to Array*.
# Equivalent to: my $r = [1,2,3]; ${deref $r}[0] -> Int:1 via Subscript
# ---------------------------------------------------------------------------
subtest 'A14: canonical PostfixDeref(sigil=@, ArrayRef) deref -> Int:1' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $ref = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $ref->set_representation('ArrayRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '@');
    $deref->set_representation('Array');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$deref, $idx]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A14 PostfixDeref(@) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bAV\b/,  'A14 .ll: no AV symbols');
        unlike($ll, qr/libperl/, 'A14 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:1', 'A14 lli output is Int:1 ($r->[0] via PostfixDeref)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A15: canonical PostfixDeref(%, HashRef) -> Hash  (Phase 1.2)
#
# PostfixDeref(sigil="%", ref) derefs a HashRef to Hash*.
# ---------------------------------------------------------------------------
subtest 'A15: canonical PostfixDeref(sigil=%, HashRef) deref -> Int:1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $ref = $f->make('HashRef', inputs => [$ka, $v1, $kb, $v2]);
    $ref->set_representation('HashRef');

    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '%');
    $deref->set_representation('Hash');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('Subscript', inputs => [$deref, $lk]);
    $val->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A15 PostfixDeref(%) lower() does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/\bHV\b/,  'A15 .ll: no HV symbols');
        unlike($ll, qr/libperl/, 'A15 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:1', 'A15 lli output is Int:1 ($r->{a} via PostfixDeref)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A16: canonical ArrayRef used as container for Length  (Phase 2.1)
#
# ArrayRef(1,2,3) :ArrayRef + Length -> Int:3.
# The canonical ref-producing constructor feeds Length directly.
# ---------------------------------------------------------------------------
subtest 'A16: canonical ArrayRef(1,2,3) + Length -> Int:3' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $aref = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $aref->set_representation('ArrayRef');

    my $len = $f->make('Length', inputs => [$aref]);
    $len->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$len]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A16 canonical ArrayRef + Length does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A16 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:3', 'A16 lli output is Int:3 (Length via canonical ArrayRef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A17: canonical ArrayRef used for Subscript  (Phase 2.1)
#
# ArrayRef(1,2,3) :ArrayRef + Subscript(idx=1) -> Int:2.
# ---------------------------------------------------------------------------
subtest 'A17: canonical ArrayRef(1,2,3) + Subscript(1) -> Int:2' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $aref = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $aref->set_representation('ArrayRef');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('Subscript', inputs => [$aref, $idx]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A17 canonical ArrayRef + Subscript does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A17 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:2', 'A17 lli output is Int:2 (Subscript via canonical ArrayRef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A18: canonical HashRef used for Subscript  (Phase 2.1)
#
# HashRef(a=>1,b=>2) :HashRef + Subscript("a") -> Int:1.
# ---------------------------------------------------------------------------
subtest 'A18: canonical HashRef(a=>1,b=>2) + Subscript("a") -> Int:1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $href = $f->make('HashRef', inputs => [$ka, $v1, $kb, $v2]);
    $href->set_representation('HashRef');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $elem = $f->make('Subscript', inputs => [$href, $lk]);
    $elem->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$elem]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A18 canonical HashRef + Subscript does not die: $@") or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A18 .ll: no libperl reference');

        my $out = run_ll($ll);
        is($out, 'Int:1', 'A18 lli output is Int:1 (Subscript via canonical HashRef)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# A19: Assign(Subscript-lvalue) emits a store  (Phase 3.0)
#
# Assign(%lval, %nv) where %lval = Subscript(%arr, %idx=0) in lvalue position.
# The Assign detects Subscript lvalue and emits an in-place slot write.
# It returns the stored value (%nv=42). Verifies: no die, store emitted, Int:42.
# ---------------------------------------------------------------------------
subtest 'A19: Assign(Subscript-lvalue, 42) emits store and returns Int:42' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayRef', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('ArrayRef');

    # Subscript(%arr, idx=0) in lvalue position
    my $idx0 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx0->set_representation('Int');
    my $lval = $f->make('Subscript', inputs => [$arr, $idx0]);
    $lval->set_representation('Int');

    my $nv = $f->make('Constant', value => '42', const_type => 'integer');
    $nv->set_representation('Int');

    # Assign is the element store; its return value is nv (42).
    my $store = $f->make('Assign', inputs => [$lval, $nv]);
    $store->set_representation('Int');

    # Return the Assign result (42).
    my $ret = $f->make_cfg('Return', inputs => [$store]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "A19 Assign(Subscript-lvalue) lower() does not die: $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/libperl/, 'A19 .ll: no libperl reference');
        like($ll, qr/store i1 true/, 'A19 .ll: emits slot-defined store');

        my $out = run_ll($ll);
        is($out, 'Int:42', 'A19 lli output is Int:42 (Assign returns stored value)');
    }

    done_testing;
};

done_testing;
