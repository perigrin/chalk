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
# A1: ArrayLiteral (1,2,3) + ScalarLen -> Int:3
#
# Equivalent to: my @a = (1,2,3); scalar @a
# Result: Int:3. Array is intermediate; only len is returned.
# ---------------------------------------------------------------------------
subtest 'A1: ArrayLiteral(1,2,3) + ScalarLen -> Int:3' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('Array');

    my $len = $f->make('ScalarLen', inputs => [$arr]);
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
# A2: ArrayLiteral + ArrayRead (in-bounds) -> Int:2
#
# Equivalent to: my @a = (1,2,3); $a[1]
# Result: Int:2. Bounds check is emitted but index=1 < len=3 always.
# ---------------------------------------------------------------------------
subtest 'A2: ArrayLiteral(1,2,3) + ArrayRead(idx=1) -> Int:2' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('Array');

    my $idx = $f->make('Constant', value => '1', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('ArrayRead', inputs => [$arr, $idx]);
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
# A3: ArrayRead out-of-bounds -> Undef:
#
# Equivalent to: my @a = (1,2,3); $a[9]
# Result: Undef:. Bounds check fails, undef slot returned. Never segfaults.
# ---------------------------------------------------------------------------
subtest 'A3: ArrayRead OOB (idx=9 on len=3) -> Undef:' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('Array');

    my $idx = $f->make('Constant', value => '9', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('ArrayRead', inputs => [$arr, $idx]);
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
# A4: HashLiteral + HashRead (existing key) -> Int:1
#
# Equivalent to: my %h = (a => 1, b => 2); $h{a}
# Result: Int:1. Linear-scan lookup finds key "a".
# ---------------------------------------------------------------------------
subtest 'A4: HashLiteral(a=>1,b=>2) + HashRead("a") -> Int:1' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $hash = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_representation('Hash');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('HashRead', inputs => [$hash, $lk]);
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
# A5: HashRead missing key -> Undef:
#
# Equivalent to: my %h = (a => 1, b => 2); $h{z}
# Result: Undef:. Key "z" not found -> undef slot.
# ---------------------------------------------------------------------------
subtest 'A5: HashRead missing key -> Undef:' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');
    my $kb = $f->make('Constant', value => 'b', const_type => 'string');
    $kb->set_representation('Str');
    my $v2 = $f->make('Constant', value => '2', const_type => 'integer');
    $v2->set_representation('Int');

    my $hash = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $hash->set_representation('Hash');

    my $lk = $f->make('Constant', value => 'z', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('HashRead', inputs => [$hash, $lk]);
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

    my $inner = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $inner->set_representation('Array');

    my $ref = $f->make('MakeArrayRef', inputs => [$inner]);
    $ref->set_representation('ArrayRef');

    my $deref = $f->make('ArrayDeref', inputs => [$ref]);
    $deref->set_representation('Array');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');

    my $elem = $f->make('ArrayRead', inputs => [$deref, $idx]);
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

    my $inner = $f->make('HashLiteral', inputs => [$ka, $v1, $kb, $v2]);
    $inner->set_representation('Hash');

    my $ref = $f->make('MakeHashRef', inputs => [$inner]);
    $ref->set_representation('HashRef');

    my $deref = $f->make('HashDeref', inputs => [$ref]);
    $deref->set_representation('Hash');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('HashRead', inputs => [$deref, $lk]);
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
# A8: ArrayWrite + ArrayRead -> Int:42
#
# Equivalent to: my @a = (1,2,3); $a[0] = 42; $a[0]
# Result: Int:42. Store then load.
# ---------------------------------------------------------------------------
subtest 'A8: ArrayWrite(0,42) then ArrayRead(0) -> Int:42' => sub {
    my $f = _mk();

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    my $arr = $f->make('ArrayLiteral', inputs => [$c1, $c2, $c3]);
    $arr->set_representation('Array');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');

    my $newval = $f->make('Constant', value => '42', const_type => 'integer');
    $newval->set_representation('Int');

    # ArrayWrite returns the array (for chaining)
    my $arr2 = $f->make('ArrayWrite', inputs => [$arr, $idx, $newval]);
    $arr2->set_representation('Array');

    my $idx2 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx2->set_representation('Int');

    my $elem = $f->make('ArrayRead', inputs => [$arr2, $idx2]);
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
# A9: HashWrite + HashRead -> Int:99
#
# Equivalent to: my %h = (k => 0); $h{k} = 99; $h{k}
# Result: Int:99. Store then load.
# ---------------------------------------------------------------------------
subtest 'A9: HashWrite then HashRead -> Int:99' => sub {
    my $f = _mk();

    my $kk = $f->make('Constant', value => 'k', const_type => 'string');
    $kk->set_representation('Str');
    my $v0 = $f->make('Constant', value => '0', const_type => 'integer');
    $v0->set_representation('Int');

    my $hash = $f->make('HashLiteral', inputs => [$kk, $v0]);
    $hash->set_representation('Hash');

    my $wk = $f->make('Constant', value => 'k', const_type => 'string');
    $wk->set_representation('Str');
    my $wv = $f->make('Constant', value => '99', const_type => 'integer');
    $wv->set_representation('Int');

    # HashWrite returns the hash (for chaining)
    my $hash2 = $f->make('HashWrite', inputs => [$hash, $wk, $wv]);
    $hash2->set_representation('Hash');

    my $rk = $f->make('Constant', value => 'k', const_type => 'string');
    $rk->set_representation('Str');

    my $val = $f->make('HashRead', inputs => [$hash2, $rk]);
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

    my $arr0 = $f->make('ArrayLiteral', inputs => [$ca1, $ca2]);
    $arr0->set_representation('Array');
    my $arr1 = $f->make('ArrayLiteral', inputs => [$ca3, $ca4]);
    $arr1->set_representation('Array');

    # Inner refs
    my $ref0 = $f->make('MakeArrayRef', inputs => [$arr0]);
    $ref0->set_representation('ArrayRef');
    my $ref1 = $f->make('MakeArrayRef', inputs => [$arr1]);
    $ref1->set_representation('ArrayRef');

    # Outer array of refs: [(ref to [1,2]), (ref to [3,4])]
    # Each element is an ArrayRef (a pointer). Store as i64 (raw pointer).
    # The outer array holds ArrayRef pointers as Int-typed slots.
    my $outer = $f->make('ArrayLiteral', inputs => [$ref0, $ref1]);
    $outer->set_representation('Array');

    # Outer ref
    my $outer_ref = $f->make('MakeArrayRef', inputs => [$outer]);
    $outer_ref->set_representation('ArrayRef');

    # Deref outer: $r->[1] = inner array ref (an ArrayRef pointer)
    my $outer_arr = $f->make('ArrayDeref', inputs => [$outer_ref]);
    $outer_arr->set_representation('Array');

    my $idx1 = $f->make('Constant', value => '1', const_type => 'integer');
    $idx1->set_representation('Int');

    # $r->[1] returns a slot containing an ArrayRef pointer
    my $inner_ref_slot = $f->make('ArrayRead', inputs => [$outer_arr, $idx1]);
    $inner_ref_slot->set_representation('ArrayRef');

    # Deref inner: $r->[1][0]
    my $inner_arr = $f->make('ArrayDeref', inputs => [$inner_ref_slot]);
    $inner_arr->set_representation('Array');

    my $idx0 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx0->set_representation('Int');

    my $elem = $f->make('ArrayRead', inputs => [$inner_arr, $idx0]);
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

done_testing;
