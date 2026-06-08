# ABOUTME: Tests for Undef representation + DefinedOr (//) lowering in the LLVM backend.
# ABOUTME: Validates that Constant(undef), VarDecl(:Undef), and DefinedOr lower without libperl.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::Return;
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# ---------------------------------------------------------------------------
# U1: Constant(undef) :Undef lowers without dying.
#
# An Undef-typed constant must produce an i1 defined-bit (false) in LLVM IR.
# The representation is Undef. The lowering must not call any libperl symbol.
# ---------------------------------------------------------------------------
subtest 'U1: Constant(undef) :Undef lowers without dying' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Constant(undef) :Undef — the undef literal
    my $cundef = $f->make('Constant', value => undef, const_type => 'undef');
    $cundef->set_representation('Undef');

    # Build a graph: return the undef value itself (Undef result)
    my $ret = $f->make_cfg('Return', inputs => [$cundef]);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "lower() does not die for Undef-repr return: $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/, 'U1 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'U1 .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'U1 .ll: no sv_ function calls');
        unlike($ll, qr/libperl/,'U1 .ll: no libperl reference');
        like($ll, qr/alloca|store|Undef/i, 'U1 .ll: Undef constant emits alloca or Undef marker');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# U2: DefinedOr(Int_lhs, Int_rhs) :Int — defined-left path returns lhs.
#
# $a = 3 (Int, always defined), $b = 7. $a // $b => 3.
# DefinedOr with an Int-typed LHS: always-defined, so result = lhs = 3.
# lli output must equal perl oracle (Int:3). Libperl-free.
# ---------------------------------------------------------------------------
subtest 'U2: DefinedOr(Int :defined, Int) => left operand via lli' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # $a = 3
    my $cn_a  = $f->make('Constant', value => '$a', const_type => 'string');
    $cn_a->set_representation('Str');
    my $ca    = $f->make('Constant', value => '3',  const_type => 'integer');
    $ca->set_representation('Int');
    my $vda   = $f->make('VarDecl', inputs => [$cn_a, $ca]);
    $vda->set_representation('Int');
    my $pa    = $f->make('PadAccess', targ => 0, varname => '$a', inputs => [$vda]);
    $pa->set_representation('Int');

    # $b = 7
    my $cn_b  = $f->make('Constant', value => '$b', const_type => 'string');
    $cn_b->set_representation('Str');
    my $cb    = $f->make('Constant', value => '7',  const_type => 'integer');
    $cb->set_representation('Int');
    my $vdb   = $f->make('VarDecl', inputs => [$cn_b, $cb]);
    $vdb->set_representation('Int');
    my $pb    = $f->make('PadAccess', targ => 0, varname => '$b', inputs => [$vdb]);
    $pb->set_representation('Int');

    # $a // $b :Int
    my $dor   = $f->make('DefinedOr', inputs => [$pa, $pb]);
    $dor->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$dor]);
    $ret->set_control_in($vdb);
    $vdb->set_control_in($vda);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "lower() does not die for DefinedOr(Int,Int): $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/, 'U2 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'U2 .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'U2 .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/,'U2 .ll: no libperl reference');

        # Run through lli and check the result
        use File::Temp qw(tempfile);
        my ($fh, $tmpfile) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $fh $ll;
        close $fh;

        my $lli_out = `$LLI $tmpfile 2>/dev/null`;
        chomp $lli_out;
        is($lli_out, 'Int:3', 'U2 lli output is Int:3 (3//7 = 3, left is defined)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# U3: DefinedOr(Undef_lhs, Int_rhs) :Int — undef-left path returns rhs.
#
# $a = undef (Undef repr, always undefined), $b = 7. $a // $b => 7.
# DefinedOr with an Undef-typed LHS: always-undefined, so result = rhs = 7.
# lli output must equal perl oracle (Int:7). Libperl-free.
#
# RUNTIME-undef: the defined bit for the Undef-typed variable is produced via
# alloca+store+load, which prevents any LLVM optimizer from constant-folding
# the branch away. The alloca/store/load round-trip is a memory barrier that
# makes the value "opaque" to scalar replacement optimizations without mem2reg.
# ---------------------------------------------------------------------------
subtest 'U3: DefinedOr(Undef :undef, Int) => right operand via lli' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # $a = undef
    my $cn_a   = $f->make('Constant', value => '$a', const_type => 'string');
    $cn_a->set_representation('Str');
    my $cundef = $f->make('Constant', value => undef, const_type => 'undef');
    $cundef->set_representation('Undef');
    my $vda    = $f->make('VarDecl', inputs => [$cn_a, $cundef]);
    $vda->set_representation('Undef');
    my $pa     = $f->make('PadAccess', targ => 0, varname => '$a', inputs => [$vda]);
    $pa->set_representation('Undef');

    # $b = 7
    my $cn_b  = $f->make('Constant', value => '$b', const_type => 'string');
    $cn_b->set_representation('Str');
    my $cb    = $f->make('Constant', value => '7',  const_type => 'integer');
    $cb->set_representation('Int');
    my $vdb   = $f->make('VarDecl', inputs => [$cn_b, $cb]);
    $vdb->set_representation('Int');
    my $pb    = $f->make('PadAccess', targ => 0, varname => '$b', inputs => [$vdb]);
    $pb->set_representation('Int');

    # $a // $b :Int
    my $dor   = $f->make('DefinedOr', inputs => [$pa, $pb]);
    $dor->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$dor]);
    $ret->set_control_in($vdb);
    $vdb->set_control_in($vda);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "lower() does not die for DefinedOr(Undef,Int): $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/, 'U3 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'U3 .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'U3 .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/,'U3 .ll: no libperl reference');

        # The .ll must use alloca+store+load to ensure the defined bit is runtime
        # (not constant-foldable by LLVM optimizers).
        like($ll, qr/alloca/, 'U3 .ll: alloca present (prevents constant-folding of defined bit)');
        like($ll, qr/store i1/, 'U3 .ll: store i1 present (defined bit stored to alloca slot)');
        like($ll, qr/load i1/, 'U3 .ll: load i1 present (defined bit loaded at runtime)');

        # Run through lli and check the result
        use File::Temp qw(tempfile);
        my ($fh, $tmpfile) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $fh $ll;
        close $fh;

        my $lli_out = `$LLI $tmpfile 2>/dev/null`;
        chomp $lli_out;
        is($lli_out, 'Int:7', 'U3 lli output is Int:7 (undef//7 = 7, right operand)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# U4: TypeTag extended — llvm_prefixes contains Undef entry.
#
# The TypeTag module must have an Undef entry in llvm_prefixes().
# This is the pinning test: TypeTag is the single source of truth for tag
# prefixes; the LLVM backend hard-codes these, pinned equal by this test.
# ---------------------------------------------------------------------------
subtest 'U4: TypeTag has Undef entry in llvm_prefixes' => sub {
    use_ok('Chalk::CodeGen::Harness::TypeTag');
    my $prefixes = Chalk::CodeGen::Harness::TypeTag->llvm_prefixes();
    ok(exists $prefixes->{Undef}, 'TypeTag::llvm_prefixes has Undef key');
    if (exists $prefixes->{Undef}) {
        ok(defined $prefixes->{Undef}{perl_tag_prefix}, 'Undef entry has perl_tag_prefix');
        ok(defined $prefixes->{Undef}{llvm_fmt_c},      'Undef entry has llvm_fmt_c');
        is($prefixes->{Undef}{perl_tag_prefix}, 'Undef:', 'Undef perl_tag_prefix is "Undef:"');
        # "Undef:\n\0" = U,n,d,e,f,:,\n,\0 = 8 bytes
        is($prefixes->{Undef}{llvm_fmt_c}, 'Undef:\0A\00', 'Undef llvm_fmt_c is "Undef:\\0A\\00"');
    }
    done_testing;
};

# ---------------------------------------------------------------------------
# U5: Undef return path — lli prints "Undef:" when result repr is Undef.
#
# A graph that returns a Constant(undef) :Undef must produce lli output
# matching the TypeTag oracle "Undef:". This exercises the return-value
# epilogue for Undef-typed results.
# ---------------------------------------------------------------------------
subtest 'U5: Undef return repr prints "Undef:" via lli' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $cundef = $f->make('Constant', value => undef, const_type => 'undef');
    $cundef->set_representation('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$cundef]);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "lower() does not die for Undef return: $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/, 'U5 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/libperl/,'U5 .ll: no libperl reference');

        use File::Temp qw(tempfile);
        my ($fh, $tmpfile) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $fh $ll;
        close $fh;

        my $lli_out = `$LLI $tmpfile 2>/dev/null`;
        chomp $lli_out;
        is($lli_out, 'Undef:', 'U5 lli output is "Undef:" (type-tagged undef)');
    }

    done_testing;
};

done_testing;
