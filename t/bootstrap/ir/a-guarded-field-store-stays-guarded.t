# ABOUTME: A one-armed `if` guarding a field store must run only when the guard holds.
# ABOUTME: The producer built no If for this shape, so the store ran unconditionally.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `method bump { if ($n > 5) { $n = $n + 3 } return $n }` emitted a method body
# containing a field load and a return and NOTHING ELSE -- no compare, no
# branch, no store. The guard was gone and the store with it.
#
# BOTH POLARITIES ARE REQUIRED, and only one of them can see the bug:
#
#   n=10   perl 13   chalk 10    <- the taken branch: store DROPPED
#   n=1    perl  1   chalk  1    <- the untaken branch: AGREES
#
# The untaken polarity agrees for the wrong reason -- dropping a store whose
# guard is false is coincidentally correct. A test that ran only that case would
# have been green throughout. This is the "run the CONTROL" discipline in its
# sharpest form: the case that looks the same whether or not you are right
# proves nothing, and here it is half the input space.
#
# ROOT CAUSE was in the producer (perl5-son b96087c), not chalk: a one-armed
# `if` compiles to an `and` op rather than a cond_expr, and the and/or
# void-branch gate tested for an element store, a void call and a die -- but not
# a FIELD store. The cond_expr gate tested for all four, so if/ELSE worked,
# which made this look covered.
#
# Kept on the chalk side as a BEHAVIOURAL pin: this file asserts what the
# compiled program PRINTS, so it stays meaningful regardless of how the producer
# chooses to represent the branch.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

sub compile_and_run ($src, $pkgs) {
    my ($sfh, $spath) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$sfh} $src;
    close $sfh;

    my $oracle = qx($PERL $spath 2>/dev/null);

    my $json = qx($PERL -I$SON -MO=SoN,json,$pkgs $spath 2>/dev/null);
    return ($oracle, undef, 'producer emitted no JSON') unless $json =~ /\S/;

    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new
        ->run_detail($json, $select, program_mode => 1);
    return ($oracle, undef, "load: $err")        if $err;
    return ($oracle, undef, 'no lowerable unit') unless @$units;
    return ($oracle, undef, $units->[0]{err})    unless $units->[0]{ok};

    my ($lfh, $lpath) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lfh, ':utf8';
    print {$lfh} $units->[0]{ll};
    close $lfh;
    return ($oracle, scalar qx($LLI $lpath 2>&1), undef);
}

sub bump_source ($n) {
    return <<"PROG";
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field \$n :param = 0;
    method bump { if (\$n > 5) { \$n = \$n + 3 } return \$n }
}
package main;
say(C->new(n => $n)->bump);
PROG
}

subtest 'the guard is TAKEN: the store happens' => sub {
    my ($perl, $lli, $err) = compile_and_run(bump_source(10), 'package=main,package=C');
    is $perl, "13\n", 'perl stores when 10 > 5' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- 10 here means the guarded store was dropped';
};

# THE CONTROL. It passed before the fix too, and that is exactly why it is here:
# it proves the fix did not simply make the store unconditional in the other
# direction, which would trade one miscompile for its mirror image.
subtest 'the guard is NOT taken: the store does not happen' => sub {
    my ($perl, $lli, $err) = compile_and_run(bump_source(1), 'package=main,package=C');
    is $perl, "1\n", 'perl leaves the field alone when 1 > 5 is false' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- 4 here would mean the store became unconditional';
};

# The two shapes that ALREADY worked, for the same reason the producer-side test
# carries them: each differs from the broken case in exactly one way, so a fix
# that broke either fixed the wrong thing.
subtest 'a two-armed if/else still works' => sub {
    my $src = <<'PROG';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field $n :param = 0;
    method pick { if ($n > 5) { $n = $n + 3 } else { $n = 0 } return $n }
}
package main;
say(C->new(n => 10)->pick);
say(C->new(n => 1)->pick);
PROG
    my ($perl, $lli, $err) = compile_and_run($src, 'package=main,package=C');
    is $perl, "13\n0\n", 'perl takes each arm' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees on both arms';
};

# THE VOID-CALL ARM, restored. It was left out when this file landed because a
# `print` inside a method body tripped a SEPARATE defect -- @fmt_print_str
# emitted undeclared, lli rejecting the module -- which would have made this a
# permanently-red subtest saying nothing about the guard. That defect is fixed
# (the format global joins the post-class re-emit), so the control can do its
# job: it differs from the broken case in exactly one way, and it already
# worked, so a fix that broke it fixed the wrong thing.
subtest 'a one-armed if with a void print still works' => sub {
    my $src = <<'PROG';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field $n :param = 0;
    method show { if ($n > 5) { print "big\n" } return 1 }
}
package main;
C->new(n => 10)->show;
C->new(n => 1)->show;
PROG
    my ($perl, $lli, $err) = compile_and_run($src, 'package=main,package=C');
    is $perl, "big\n", 'perl prints once, for the taken guard only' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- a void-call arm was never affected';
};

done_testing;
