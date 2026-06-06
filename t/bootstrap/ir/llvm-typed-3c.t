# ABOUTME: Tests for Phase 3c typed-IR lowering: arith-div, arith-mod, VarDecl/PadAccess alloca model.
# ABOUTME: Each group is a RED->GREEN TDD cycle; tests cover Num representation and mutable scalars.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Coerce;
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# ---------------------------------------------------------------------------
# Helper: run .ll through lli; return (stdout_chomped, exit_code).
# ---------------------------------------------------------------------------
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

# Helper: make Int constant node
sub int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

# Helper: make Num constant node
sub num_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'number');
    $c->set_representation('Num');
    return $c;
}

# ===========================================================================
# GROUP 1: arith-div — Perl `/` is float division
#
# `3 / 4` under Perl = 0.75 (not 0 as truncating int division).
# The correct lowering: Coerce(Int->Num) both operands, fdiv double, print %g.
# ===========================================================================

# DIV-1: Divide node with Num representation lowers to fdiv double.
{
    my $f = Chalk::IR::NodeFactory->new;

    # Build: Return(Divide(Coerce[Int->Num](3), Coerce[Int->Num](4)))
    # The Divide op has representation Num.
    my $c3   = int_const($f, 3);
    my $c4   = int_const($f, 4);
    my $coe3 = $f->make('Coerce', inputs => [$c3], from_repr => 'Int', to_repr => 'Num');
    $coe3->set_representation('Num');
    my $coe4 = $f->make('Coerce', inputs => [$c4], from_repr => 'Int', to_repr => 'Num');
    $coe4->set_representation('Num');

    my $div = $f->make('Divide', inputs => [$coe3, $coe4]);
    $div->set_representation('Num');

    my $ret = $f->make_cfg('Return', inputs => [$div]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "arith-div DIV-1: Divide(Num) lowers without dying")
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        like($ll, qr/fdiv double/, 'arith-div DIV-1: .ll contains fdiv double');
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'arith-div DIV-1: .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-div DIV-1: lli exits 0');
        is($out, '0.75', "arith-div DIV-1: lli output '0.75' matches perl oracle");
    }
}

# DIV-2: Divide with Int representation must still reject (not a silent miscompile).
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c3  = int_const($f, 3);
    my $c4  = int_const($f, 4);
    my $div = $f->make('Divide', inputs => [$c3, $c4]);
    $div->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$div]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok($@, 'arith-div DIV-2: Divide with Int repr still dies (preserves correctness guard)');
    like($@, qr/GAP|Divide.*Int|not.*float/i,
        'arith-div DIV-2: error message mentions Divide or Int repr problem');
}

# ===========================================================================
# GROUP 2: arith-mod — Perl `%` follows the right-operand sign
#
# `-7 % 3` under Perl = 2 (not -1 as LLVM srem gives).
# The sign-correction formula:
#   t = a srem b
#   if (t != 0 && (t xor b) < 0) then t = t + b
# ===========================================================================

# MOD-1: Modulo node with Int representation and sign-correction lowers to perl-semantics modulo.
{
    my $f = Chalk::IR::NodeFactory->new;

    # Build: Return(Modulo(Constant(-7, Int), Constant(3, Int))) with Int representation.
    # Perl: -7 % 3 = 2.
    my $cm7 = int_const($f, -7);
    my $c3  = int_const($f, 3);
    my $mod = $f->make('Modulo', inputs => [$cm7, $c3]);
    $mod->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$mod]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'arith-mod MOD-1: Modulo(Int,Int) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 4 unless defined $ll;
        like($ll, qr/srem i64/, 'arith-mod MOD-1: .ll contains srem i64');
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'arith-mod MOD-1: .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-mod MOD-1: lli exits 0');
        is($out, '2', "arith-mod MOD-1: lli output '2' matches perl oracle (-7 % 3 == 2)");
    }
}

# MOD-2: Modulo with positive operands should also be correct (7 % 3 = 1).
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c7  = int_const($f, 7);
    my $c3  = int_const($f, 3);
    my $mod = $f->make('Modulo', inputs => [$c7, $c3]);
    $mod->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$mod]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'arith-mod MOD-2: Modulo(7,3) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 2 unless defined $ll;
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-mod MOD-2: lli exits 0');
        is($out, '1', "arith-mod MOD-2: lli output '1' matches perl oracle (7 % 3 == 1)");
    }
}

# MOD-3: Modulo with negative RHS: 7 % -3 under Perl = -2.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c7   = int_const($f, 7);
    my $cm3  = int_const($f, -3);
    my $mod  = $f->make('Modulo', inputs => [$c7, $cm3]);
    $mod->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$mod]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'arith-mod MOD-3: Modulo(7,-3) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 2 unless defined $ll;
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-mod MOD-3: lli exits 0');
        is($out, '-2', "arith-mod MOD-3: lli output '-2' matches perl oracle (7 % -3 == -2)");
    }
}

done_testing;
