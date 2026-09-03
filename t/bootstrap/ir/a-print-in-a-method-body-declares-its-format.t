# ABOUTME: A `print` inside a method body must emit @fmt_print_str, not just reference it.
# ABOUTME: The prologue runs before method bodies lower, so the flag arrived too late.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `class C { method m { print "hi\n"; 1 } }` produced a module that REFERENCES
# @fmt_print_str once and DEFINES it zero times:
#
#   lli: error: use of undefined value '@fmt_print_str'
#     %tmp_8 = getelementptr inbounds [5 x i8], [5 x i8]* @fmt_print_str, ...
#
# THIS IS THE F6 BUG CLASS, and the machinery to fix it already existed. A
# method body lowers in its OWN Context, and its `_need_*` flags reach the
# parent only via absorb_need_flags_from -- which runs AFTER
# _emit_class_registry_ir, by which time render_need_flag_prologue has already
# decided what to declare. `render_need_flag_postclass_reemit` exists precisely
# to catch that, and already handled bool_str_globals, str_to_num_helper,
# memcmp and getenv. `_need_print_str_fmt` was simply not a member.
#
# IT IS AN lli-TIME MODULE REJECTION, NOT A DIAGNOSED GAP, which makes it worse
# than a refusal: the compiler reports success and hands back a module that
# cannot load.
#
# MEASURED: `_need_print_int_fmt` exists beside it in @NEED_FLAGS and in the
# prologue, but has NO SETTER anywhere in lib/ -- an Int print is coerced to Str
# first and takes the str path (verified: `print 42` in a method body fails on
# @fmt_print_str, not on an int format). It is dead rather than broken, so this
# fix does not touch it.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

sub compile ($src) {
    my ($sfh, $spath) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$sfh} $src;
    close $sfh;

    my $oracle = qx($PERL $spath 2>/dev/null);

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=C $spath 2>/dev/null);
    return ($oracle, undef, undef, 'producer emitted no JSON') unless $json =~ /\S/;

    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new
        ->run_detail($json, $select, program_mode => 1);
    return ($oracle, undef, undef, "load: $err")        if $err;
    return ($oracle, undef, undef, 'no lowerable unit') unless @$units;
    return ($oracle, undef, undef, $units->[0]{err})    unless $units->[0]{ok};

    my $ll = $units->[0]{ll};
    my ($lfh, $lpath) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lfh, ':utf8';
    print {$lfh} $ll;
    close $lfh;
    return ($oracle, scalar qx($LLI $lpath 2>&1), $ll, undef);
}

my $METHOD_PRINT = <<'PROG';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field $n :param = 0;
    method m { print "hi\n"; 1 }
}
package main;
C->new(n=>1)->m;
PROG

subtest 'a print inside a method body runs' => sub {
    my ($perl, $lli, $ll, $err) = compile($METHOD_PRINT);
    is $perl, "hi\n", 'perl prints from the method' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- an undefined-value error here means the '
                  . 'format global was referenced but never declared';
};

# THE STRUCTURAL ASSERTION, because the behavioural one above could in principle
# pass through some other route. Every global a module USES it must also DEFINE,
# exactly once -- referenced-but-undeclared is the defect, and declared-twice is
# what a careless fix produces instead.
subtest 'the format global is defined exactly once' => sub {
    my (undef, undef, $ll, $err) = compile($METHOD_PRINT);
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };

    my @defs = ($ll =~ /^\@fmt_print_str\s*=/mg);
    my @uses = ($ll =~ /\[5 x i8\]\* \@fmt_print_str/g);

    is scalar(@defs), 1, 'defined exactly once'
        or diag("  defined " . scalar(@defs) . " times, used " . scalar(@uses));
    cmp_ok scalar(@uses), '>=', 1, 'and actually used';
};

# THE DOUBLE-DECLARE CONTROL. A print in the MAIN graph makes the prologue emit
# the global; a print in a method body makes the post-class re-emit want to. If
# the re-emit is not guarded, a program with both defines it twice and lli
# rejects the module for a redefinition instead. This is the failure the fix
# must not introduce, so it is asserted before the fix rather than after.
subtest 'a print in BOTH the main graph and a method body defines it once' => sub {
    my $src = <<'PROG';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field $n :param = 0;
    method m { print "in\n"; 1 }
}
package main;
print "out\n";
C->new(n=>1)->m;
PROG
    my ($perl, $lli, $ll, $err) = compile($src);
    is $perl, "out\nin\n", 'perl prints from both' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };

    my @defs = ($ll =~ /^\@fmt_print_str\s*=/mg);
    is scalar(@defs), 1, 'still defined exactly once, not twice'
        or diag("  defined " . scalar(@defs) . " times");

    is $lli, $perl, 'lli agrees on both prints';
};

# THE REGRESSION CONTROL. A print ONLY in the main graph is the path the
# prologue always handled; it must be untouched.
subtest 'a print only in the main graph still works' => sub {
    my ($perl, $lli, $ll, $err) = compile(<<'PROG');
use 5.42.0;
print "plain\n";
PROG
    is $perl, "plain\n", 'perl prints' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- the prologue path is unchanged';
};

done_testing;
