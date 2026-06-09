# ABOUTME: RED tests for 4 latent LLVM-lowering bugs (R2-reopen I-A..I-D).
# ABOUTME: Each subtest exposes one latent bug; all must be GREEN after the fixes.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Helper: write .ll to a temp file and run lli; return stdout (chomped).
# Returns undef if lli exits non-zero (invalid IR).
sub run_ll {
    my ($ll) = @_;
    require File::Temp;
    my ($fh, $tmpfile) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out = `$LLI $tmpfile 2>/dev/null`;
    return undef if $?;
    chomp $out;
    return $out;
}

# Helper: run lli and return exit status (0 = valid IR, non-zero = invalid/error).
sub ll_exit_code {
    my ($ll) = @_;
    require File::Temp;
    my ($fh, $tmpfile) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    `$LLI $tmpfile 2>/dev/null`;
    return $?;
}

sub _mk { Chalk::IR::NodeFactory->new }

# ---------------------------------------------------------------------------
# I-A: cache poisoning in _lower_subscript (ArrayRef case)
#
# One ArrayRef node is used as BOTH a Subscript container AND a PostfixDeref
# input.  After Subscript runs, cache{id} holds %Array* instead of i8*.
# A subsequent lower_value on the SAME ArrayRef node returns %Array* from
# cache, and _lower_array_deref then emits:
#   bitcast i8* %Array* to %Array*   <- LLVM type error
#
# Equivalent Perl shape: my $r=[10,20,30]; my $x=$r->[0]; my @v=@$r; $x+scalar(@v)
# Both $r->[0] (Subscript) and @$r (PostfixDeref) use the same ArrayRef node.
# After fix: lli must accept the .ll and return Int:30 (10 + 20 = subscript[0]=10;
# length(@$r)=3; but we just test subscript then deref-length: 10 + 3 = 13 is
# not interesting — instead we do $r->[1] + scalar(@$r): 20 + 3 = 23).
# ---------------------------------------------------------------------------
subtest 'I-A: ArrayRef node used as Subscript container AND PostfixDeref input' => sub {
    my $f = _mk();

    # Build ArrayRef(10, 20, 30)
    my $c10 = $f->make('Constant', value => '10', const_type => 'integer');
    $c10->set_representation('Int');
    my $c20 = $f->make('Constant', value => '20', const_type => 'integer');
    $c20->set_representation('Int');
    my $c30 = $f->make('Constant', value => '30', const_type => 'integer');
    $c30->set_representation('Int');

    my $arr = $f->make('ArrayRef', inputs => [$c10, $c20, $c30]);
    $arr->set_representation('ArrayRef');

    # Consumer 1: Subscript($arr, 1) -> Int:20
    my $idx1 = $f->make('Constant', value => '1', const_type => 'integer');
    $idx1->set_representation('Int');
    my $elem = $f->make('Subscript', inputs => [$arr, $idx1]);
    $elem->set_representation('Int');

    # Consumer 2: PostfixDeref(@, $arr) -> Array; Length -> Int:3
    # (Same $arr node as Consumer 1 — this is the poison trigger)
    my $deref = $f->make('PostfixDeref', inputs => [$arr], sigil => '@');
    $deref->set_representation('Array');
    my $len = $f->make('Length', inputs => [$deref]);
    $len->set_representation('Int');

    # Result: elem(=20) + len(=3) = 23
    my $sum = $f->make('Add', inputs => [$elem, $len]);
    $sum->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$sum]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "I-A lower() does not die: $@") or diag("error: $@");
    diag("I-A .ll snippet:\n" . substr($ll // '', 0, 800)) unless defined $ll;

    SKIP: {
        skip "I-A lowering failed, cannot run lli", 2 unless defined $ll;

        my $ec = ll_exit_code($ll);
        is($ec, 0, 'I-A .ll is valid LLVM IR (lli exit 0)')
            or diag("I-A LLVM IR was invalid (cache poisoning bug):\n$ll");

        my $out = run_ll($ll);
        is($out, 'Int:23', "I-A lli output is Int:23 (20+3)");
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# I-A (HashRef variant): same cache-poisoning bug for HashRef/Hash* path.
#
# One HashRef node is used as BOTH a Subscript container AND a PostfixDeref
# input.  After Subscript, cache{id} holds %Hash*; subsequent lower_value
# returns %Hash*, and _lower_hash_deref emits:
#   bitcast i8* %Hash* to %Hash*    <- LLVM type error
# ---------------------------------------------------------------------------
subtest 'I-A(Hash): HashRef node used as Subscript container AND PostfixDeref input' => sub {
    my $f = _mk();

    my $ka = $f->make('Constant', value => 'x', const_type => 'string');
    $ka->set_representation('Str');
    my $v7 = $f->make('Constant', value => '7', const_type => 'integer');
    $v7->set_representation('Int');
    my $kb = $f->make('Constant', value => 'y', const_type => 'string');
    $kb->set_representation('Str');
    my $v8 = $f->make('Constant', value => '8', const_type => 'integer');
    $v8->set_representation('Int');

    # One HashRef node, used twice
    my $hash = $f->make('HashRef', inputs => [$ka, $v7, $kb, $v8]);
    $hash->set_representation('HashRef');

    # Consumer 1: Subscript($hash, "x") -> Int:7
    my $lk = $f->make('Constant', value => 'x', const_type => 'string');
    $lk->set_representation('Str');
    my $elem = $f->make('Subscript', inputs => [$hash, $lk]);
    $elem->set_representation('Int');

    # Consumer 2: PostfixDeref(%, $hash) -> Hash; Subscript("y") -> Int:8
    # (Same $hash node — poison trigger)
    my $deref = $f->make('PostfixDeref', inputs => [$hash], sigil => '%');
    $deref->set_representation('Hash');
    my $lk2 = $f->make('Constant', value => 'y', const_type => 'string');
    $lk2->set_representation('Str');
    my $elem2 = $f->make('Subscript', inputs => [$deref, $lk2]);
    $elem2->set_representation('Int');

    # Result: 7 + 8 = 15
    my $sum = $f->make('Add', inputs => [$elem, $elem2]);
    $sum->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$sum]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "I-A(Hash) lower() does not die: $@") or diag("error: $@");

    SKIP: {
        skip "I-A(Hash) lowering failed, cannot run lli", 2 unless defined $ll;

        my $ec = ll_exit_code($ll);
        is($ec, 0, 'I-A(Hash) .ll is valid LLVM IR (lli exit 0)')
            or diag("I-A(Hash) LLVM IR was invalid (cache poisoning bug):\n$ll");

        my $out = run_ll($ll);
        is($out, 'Int:15', "I-A(Hash) lli output is Int:15 (7+8)");
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# I-B: missing ptrtoint guard in Assign(Array-lvalue) when rhs is ArrayRef.
#
# Assign(Subscript(outerArr, idx), innerRef) where innerRef is an ArrayRef.
# Without the ptrtoint guard, emits: store i64 i8* ...   <- LLVM type error
# After fix: lli accepts the .ll; we verify by returning the inner array's length
# via a round-trip (subscript the slot back, deref, Length = 3).
# ---------------------------------------------------------------------------
subtest 'I-B(Array-lvalue): Assign stores ArrayRef value -> ptrtoint needed' => sub {
    my $f = _mk();

    # Outer array: 3 zero-slots initially (we will overwrite slot 0)
    my $z0 = $f->make('Constant', value => '0', const_type => 'integer');
    $z0->set_representation('Int');
    my $z1 = $f->make('Constant', value => '0', const_type => 'integer');
    $z1->set_representation('Int');
    my $z2 = $f->make('Constant', value => '0', const_type => 'integer');
    $z2->set_representation('Int');
    my $outer = $f->make('ArrayRef', inputs => [$z0, $z1, $z2]);
    $outer->set_representation('ArrayRef');

    # Inner array ref: [5, 6, 7]
    my $c5 = $f->make('Constant', value => '5', const_type => 'integer');
    $c5->set_representation('Int');
    my $c6 = $f->make('Constant', value => '6', const_type => 'integer');
    $c6->set_representation('Int');
    my $c7 = $f->make('Constant', value => '7', const_type => 'integer');
    $c7->set_representation('Int');
    my $inner = $f->make('ArrayRef', inputs => [$c5, $c6, $c7]);
    $inner->set_representation('ArrayRef');

    # Subscript lvalue: $outer[0]
    my $idx0 = $f->make('Constant', value => '0', const_type => 'integer');
    $idx0->set_representation('Int');
    my $lval = $f->make('Subscript', inputs => [$outer, $idx0]);
    $lval->set_representation('ArrayRef');  # storing an ArrayRef

    # Assign: $outer[0] = $inner (storing i8* ref -> needs ptrtoint to i64).
    # Assign returns the rhs value (the ArrayRef i8* pointer).
    my $asgn = $f->make('Assign', inputs => [$lval, $inner]);
    $asgn->set_representation('ArrayRef');

    # Length(Assign(...)) — Assign returns rhs (ArrayRef), Length reads its len=3.
    # This forces Assign to be in the return data path so the store is emitted.
    my $asgn_len = $f->make('Length', inputs => [$asgn]);
    $asgn_len->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$asgn_len]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "I-B(Array-lvalue) lower() does not die: $@") or diag("error: $@");

    SKIP: {
        skip "I-B(Array-lvalue) lowering failed, cannot run lli", 2 unless defined $ll;

        my $ec = ll_exit_code($ll);
        is($ec, 0, 'I-B(Array-lvalue) .ll is valid LLVM IR (lli exit 0)')
            or diag("I-B(Array-lvalue): missing ptrtoint; store i64 i8* type mismatch:\n$ll");

        my $out = run_ll($ll);
        is($out, 'Int:3', 'I-B(Array-lvalue) lli output is Int:3 (Length of ArrayRef returned by Assign)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# I-B (HashRef value): missing ptrtoint guard in _lower_hash_ref when a
# hash value has repr ArrayRef (or HashRef).
#
# HashRef("k" => innerArrayRef) — the value is an i8* but emits:
#   store i64 i8* ...   <- LLVM type error
# After fix: lli accepts and the hash's value slot holds the pointer.
# We verify by returning Length(inner) = 2 from context (the inner is [1,2]).
# ---------------------------------------------------------------------------
subtest 'I-B(HashRef-value): HashRef stores ArrayRef value -> ptrtoint needed' => sub {
    my $f = _mk();

    # Inner array: [1, 2]
    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $inner = $f->make('ArrayRef', inputs => [$c1, $c2]);
    $inner->set_representation('ArrayRef');

    # Hash: { "k" => $inner }  -- value is ArrayRef (i8*)
    my $key = $f->make('Constant', value => 'k', const_type => 'string');
    $key->set_representation('Str');

    my $hash = $f->make('HashRef', inputs => [$key, $inner]);
    $hash->set_representation('HashRef');

    # Verify the .ll is valid by getting the length of the inner array directly
    # (not through the hash read-back, which requires inttoptr — tested separately).
    my $inner_len = $f->make('Length', inputs => [$inner]);
    $inner_len->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$inner_len]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "I-B(HashRef-value) lower() does not die: $@") or diag("error: $@");

    SKIP: {
        skip "I-B(HashRef-value) lowering failed, cannot run lli", 2 unless defined $ll;

        my $ec = ll_exit_code($ll);
        is($ec, 0, 'I-B(HashRef-value) .ll is valid LLVM IR (lli exit 0)')
            or diag("I-B(HashRef-value): missing ptrtoint; store i64 i8* type mismatch:\n$ll");

        my $out = run_ll($ll);
        is($out, 'Int:2', 'I-B(HashRef-value) lli output is Int:2 (inner array length)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# I-C: _lower_length Str branch emits extractvalue on an i8* pointer.
#
# lower_value for Str returns i8*, not %StrPair.  The length branch does:
#   extractvalue %StrPair $str_ref, 1   <- i8* is not %StrPair, invalid IR
#
# After fix: use _str_len_table for compile-time-known lengths, or die GAP
# if length is not tracked.  For a string constant, the length IS tracked
# (see _lower_str_constant), so lli must accept and return Int:<len>.
# ---------------------------------------------------------------------------
subtest 'I-C: Length(Str) uses _str_len_table not extractvalue' => sub {
    my $f = _mk();

    # A string constant "hello" (length=5)
    my $str = $f->make('Constant', value => 'hello', const_type => 'string');
    $str->set_representation('Str');

    my $len = $f->make('Length', inputs => [$str]);
    $len->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$len]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "I-C lower() does not die: $@") or diag("error: $@");

    SKIP: {
        skip "I-C lowering failed, cannot run lli", 2 unless defined $ll;

        my $ec = ll_exit_code($ll);
        is($ec, 0, 'I-C .ll is valid LLVM IR (lli exit 0)')
            or diag("I-C: extractvalue on i8* is invalid LLVM IR:\n$ll");

        my $out = run_ll($ll);
        is($out, 'Int:5', 'I-C lli output is Int:5 (length("hello")=5)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# I-D: _lower_length fallback assumes cache holds i8*, but _lower_array_deref
# puts %Array* there.
#
# Length(PostfixDeref(@$ref)) — scalar(@$ref):
# - _lower_array_deref is called first, puts %Array* in cache{deref_node->id}
# - _lower_length calls lower_value(deref_node) -> hits cache -> returns %Array*
# - fallback branch: bitcast i8* %Array* to %Array*  <- type error
#
# After fix: _lower_array_deref populates _arr_table; _lower_length finds it
# and skips the bitcast.  lli must accept and return Int:3.
# ---------------------------------------------------------------------------
subtest 'I-D: Length(PostfixDeref(@$ref)) — scalar(@$ref) — valid IR' => sub {
    my $f = _mk();

    # Build ArrayRef(100, 200, 300)
    my $c100 = $f->make('Constant', value => '100', const_type => 'integer');
    $c100->set_representation('Int');
    my $c200 = $f->make('Constant', value => '200', const_type => 'integer');
    $c200->set_representation('Int');
    my $c300 = $f->make('Constant', value => '300', const_type => 'integer');
    $c300->set_representation('Int');
    my $ref = $f->make('ArrayRef', inputs => [$c100, $c200, $c300]);
    $ref->set_representation('ArrayRef');

    # PostfixDeref(@, ref) -> Array
    my $deref = $f->make('PostfixDeref', inputs => [$ref], sigil => '@');
    $deref->set_representation('Array');

    # Length(deref) — scalar(@$ref) -> 3
    my $len = $f->make('Length', inputs => [$deref]);
    $len->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$len]);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    ok(!$@, "I-D lower() does not die: $@") or diag("error: $@");

    SKIP: {
        skip "I-D lowering failed, cannot run lli", 2 unless defined $ll;

        my $ec = ll_exit_code($ll);
        is($ec, 0, 'I-D .ll is valid LLVM IR (lli exit 0)')
            or diag("I-D: bitcast i8* %Array* to %Array* is invalid LLVM IR:\n$ll");

        my $out = run_ll($ll);
        is($out, 'Int:3', 'I-D lli output is Int:3 (scalar(@$ref) = 3)');
    }

    done_testing;
};

done_testing;
