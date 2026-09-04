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
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

use File::Temp qw(tempfile);

# Wrap a Str-repr value node in a program: print it bracketed by literal
# sentinels, then return Undef. A program's observable contract is stdout plus
# exit status; there is no type-tag channel. The brackets are load-bearing —
# undef's printed face IS the empty string, so "[]" separates "correctly
# printed empty" from "printed nothing at all".
sub print_program {
    my ($f, $value_node, $control_tail) = @_;

    my $lb = $f->make('Constant', value => '[', const_type => 'string');
    $lb->set_stamp('Str');
    my $rb = $f->make('Constant', value => ']', const_type => 'string');
    $rb->set_stamp('Str');

    my $head = $control_tail // $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$lb, $value_node, $rb]);
    $print->set_control_in($head);

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    return $ret;
}

sub run_lli {
    my ($ll) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
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
    $cundef->set_stamp('Undef');

    # A program observes the undef the way perl does: by printing it. Print
    # takes a Str, so the undef goes through Coerce(Undef->Str) — the same
    # coercion the producer inserts for a print argument. Printing an Undef
    # directly is refused by the backend ("Print takes Str, so this needs a
    # Coerce"), which is the correct shape, not a limitation.
    my $to_str = $f->make('Coerce',
        from_repr => 'Undef', to_repr => 'Str', inputs => [$cundef]);
    $to_str->set_stamp('Str');

    is($cundef->stamp, 'Undef',
        'U1: the constant is Undef-repr (unobservable from stdout: undef and "" both print as nothing)');

    my $ret = print_program($f, $to_str);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "lower() does not die for an Undef-valued program: $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/, 'U1 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'U1 .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'U1 .ll: no sv_ function calls');
        unlike($ll, qr/libperl/,'U1 .ll: no libperl reference');
        like($ll, qr/alloca|store|Undef/i, 'U1 .ll: Undef constant emits alloca or Undef marker');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'U1: lli exits 0');
        # perl: `print undef` puts nothing on stdout (measured under 5.42.0).
        is($out, '[]', 'U1: undef prints as the empty string, like perl');
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
    $cn_a->set_stamp('Str');
    my $ca    = $f->make('Constant', value => '3',  const_type => 'integer');
    $ca->set_stamp('Int');
    my $vda   = $f->make('VarDecl', inputs => [$cn_a, $ca]);
    $vda->set_stamp('Int');
    my $pa    = $f->make('PadAccess', targ => 0, varname => '$a', inputs => [$vda]);
    $pa->set_stamp('Int');

    # $b = 7
    my $cn_b  = $f->make('Constant', value => '$b', const_type => 'string');
    $cn_b->set_stamp('Str');
    my $cb    = $f->make('Constant', value => '7',  const_type => 'integer');
    $cb->set_stamp('Int');
    my $vdb   = $f->make('VarDecl', inputs => [$cn_b, $cb]);
    $vdb->set_stamp('Int');
    my $pb    = $f->make('PadAccess', targ => 0, varname => '$b', inputs => [$vdb]);
    $pb->set_stamp('Int');

    # $a // $b :Int
    my $dor   = $f->make('DefinedOr', inputs => [$pa, $pb]);
    $dor->set_stamp('Int');

    # Print takes a Str, so the Int result is stringified — the same coercion
    # the producer inserts for a print argument.
    is($dor->stamp, 'Int',
        'U2: the // result is Int-repr (the type half of the old Int: tag; a Str "3" prints identically)');

    my $to_str = $f->make('Coerce',
        from_repr => 'Int', to_repr => 'Str', inputs => [$dor]);
    $to_str->set_stamp('Str');

    $vdb->set_control_in($vda);
    my $ret = print_program($f, $to_str, $vdb);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "lower() does not die for DefinedOr(Int,Int): $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/, 'U2 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'U2 .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'U2 .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/,'U2 .ll: no libperl reference');

        my ($lli_out, $lli_exit) = run_lli($ll);
        is($lli_exit, 0, 'U2: lli exits 0');
        is($lli_out, '[3]', 'U2 prints 3 (3//7 = 3, left is defined)');
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
    $cn_a->set_stamp('Str');
    my $cundef = $f->make('Constant', value => undef, const_type => 'undef');
    $cundef->set_stamp('Undef');
    my $vda    = $f->make('VarDecl', inputs => [$cn_a, $cundef]);
    $vda->set_stamp('Undef');
    my $pa     = $f->make('PadAccess', targ => 0, varname => '$a', inputs => [$vda]);
    $pa->set_stamp('Undef');

    # $b = 7
    my $cn_b  = $f->make('Constant', value => '$b', const_type => 'string');
    $cn_b->set_stamp('Str');
    my $cb    = $f->make('Constant', value => '7',  const_type => 'integer');
    $cb->set_stamp('Int');
    my $vdb   = $f->make('VarDecl', inputs => [$cn_b, $cb]);
    $vdb->set_stamp('Int');
    my $pb    = $f->make('PadAccess', targ => 0, varname => '$b', inputs => [$vdb]);
    $pb->set_stamp('Int');

    # $a // $b :Int
    my $dor   = $f->make('DefinedOr', inputs => [$pa, $pb]);
    $dor->set_stamp('Int');

    # Print takes a Str, so the Int result is stringified — the same coercion
    # the producer inserts for a print argument.
    is($dor->stamp, 'Int',
        'U3: the // result is Int-repr (the type half of the old Int: tag; a Str "7" prints identically)');

    my $to_str = $f->make('Coerce',
        from_repr => 'Int', to_repr => 'Str', inputs => [$dor]);
    $to_str->set_stamp('Str');

    $vdb->set_control_in($vda);
    my $ret = print_program($f, $to_str, $vdb);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
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

        my ($lli_out, $lli_exit) = run_lli($ll);
        is($lli_exit, 0, 'U3: lli exits 0');
        is($lli_out, '[7]', 'U3 prints 7 (undef//7 = 7, right operand)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# U4: REMOVED — it pinned the type-tag mechanism, which is being deleted.
#
# U4 asserted that Chalk::CodeGen::Harness::TypeTag->llvm_prefixes has an Undef
# entry whose perl_tag_prefix is "Undef:" and whose llvm_fmt_c is the bytes of
# "Undef:\n\0". Those are properties of the type-tag epilogue itself — the
# channel a program does not have — so there is nothing to convert them into.
# A program's undef is observed by printing it, which U1 now does.
#
# If TypeTag survives for other consumers, its Undef entry belongs in a TypeTag
# unit test, not here.
#
# ---------------------------------------------------------------------------
# U5: REMOVED — same reason, one layer down.
#
# U5 asserted that the return-value epilogue prints "Undef:" for an Undef-repr
# result. That IS the epilogue. With it deleted a program returning undef
# prints nothing and exits 0, which is what the U5-shaped case below checks.
# ---------------------------------------------------------------------------
subtest 'U5: a program whose result is undef prints nothing and exits 0' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # No Print at all: the whole program is `return undef`. Its entire
    # observable contract is empty stdout plus exit 0.
    my $cundef = $f->make('Constant', value => undef, const_type => 'undef');
    $cundef->set_stamp('Undef');
    my $start = $f->make_cfg('Start');
    my $ret = $f->make_cfg('Return', inputs => [$cundef]);
    $ret->set_control_in($start);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "lower() does not die for an undef-result program: $@")
        or diag("error: $@");

    if (defined $ll) {
        unlike($ll, qr/Perl_/,  'U5 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/libperl/,'U5 .ll: no libperl reference');

        my ($lli_out, $lli_exit) = run_lli($ll);
        is($lli_exit, 0,  'U5: lli exits 0');
        is($lli_out,  '', 'U5: nothing on stdout - no type-tag epilogue');

        # Control: the SAME program shape with a Print does reach stdout, so
        # the empty result above is a real empty and not a dead lowering.
        my $g = Chalk::IR::NodeFactory->new;
        my $lit = $g->make('Constant', value => 'x', const_type => 'string');
        $lit->set_stamp('Str');
        my $ll2 = Chalk::Target::LLVM->lower(print_program($g, $lit), program_mode => 1);
        my ($out2, $exit2) = run_lli($ll2);
        is($exit2, 0,    'U5 control: the printing twin exits 0');
        is($out2,  '[x]','U5 control: the printing twin does reach stdout');
    }

    done_testing;
};

done_testing;
