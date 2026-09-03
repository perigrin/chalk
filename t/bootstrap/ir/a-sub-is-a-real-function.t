# ABOUTME: A named sub emits a real LLVM define and its calls are real calls.
# ABOUTME: Inlining is an optimization; it was standing in for the mechanism itself.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# THE INLINER WAS A PREMATURE OPTIMIZATION THAT BECAME LOAD-BEARING.
# `_lower_call_direct` substitutes the callee's body at every call site, and it
# is the ONLY direct-call mechanism -- so an optimization is doing correctness's
# job, which inverts this project's stated order (correctness > performance).
#
# The cost is visible in the code: 169 lines, and 17 GAP sites of the form
# "direct call to '$name': callee has X". Almost every one of those exists only
# because there is no fallback -- with real calls they become the inliner's
# DECLINATION CRITERIA rather than compile failures.
#
# And one ceiling it cannot raise at all: RECURSION. Inlining cannot terminate
# on a cycle, so `fib` is not a missing optimization but a language feature the
# compiler cannot express. `docs/plans/2026-07-19-bare-file-protocol-toplevel-entry.md:303`
# calls this "THE BIG ONE, AND MANDATORY".
#
# WHAT THIS FILE PINS: that a sub is a FUNCTION -- defined once, called by name,
# with its arguments passed rather than substituted. Behavioural throughout,
# because an emission change can produce a module that verifies and computes the
# wrong value.
#
# NOTE ON THE PRIOR ATTEMPT, which is why the duplication subtest exists:
# registering main's subs while the inliner still ran made corpus F9/F10/F11/F13
# each print their callee's output TWICE (gate 214 -> 207, measured). A body
# must be emitted once and reached once; "it lowers" does not catch a body that
# runs twice.

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

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $spath 2>/dev/null);
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

subtest 'a sub with an argument is defined once and called' => sub {
    my ($perl, $lli, $ll, $err) = compile(<<'PROG');
use 5.42.0;
sub twice { my $n = shift; $n * 2 }
print twice(21), "\n";
PROG
    is $perl, "42\n", 'perl doubles' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';

    # THE STRUCTURAL HALF. Behaviour alone cannot distinguish a real call from
    # a perfect inline -- both print 42 -- so the mechanism is asserted too.
    like $ll, qr/^define .*\@"?main::twice"?/m,
        'the sub has its own define'
        or diag('  no define: the body was substituted, not emitted');
    like $ll, qr/call .*\@"?main::twice"?/,
        'and the call site calls it by name';
};

# ONE BODY, ONE EMISSION. The measured failure of the previous attempt was a
# body reached TWICE, which prints the right answer twice rather than failing.
subtest 'an effectful sub called twice runs exactly twice' => sub {
    my ($perl, $lli, $ll, $err) = compile(<<'PROG');
use 5.42.0;
sub noisy { print "x"; 1 }
my $a = noisy();
my $b = noisy();
print "\n";
PROG
    is $perl, "xx\n", 'perl prints x once per call' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- "xxxx" means each call ran the body twice';

    my @defs = ($ll =~ /^define .*\@"?main::noisy"?/mg);
    is scalar(@defs), 1, 'the body is emitted EXACTLY once, not per call site'
        or diag('  emitted ' . scalar(@defs) . ' times');
};

# THE CEILING THE INLINER CANNOT RAISE. Recursion is not a missing optimization;
# it is a language feature inlining structurally cannot express.
subtest 'a recursive sub compiles and runs' => sub {
    my ($perl, $lli, undef, $err) = compile(<<'PROG');
use 5.42.0;
sub down { my $n = shift; $n <= 0 ? 0 : down($n - 1) }
print down(3), "\n";
PROG
    is $perl, "0\n", 'perl bottoms out' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

subtest 'fib(10) is 55' => sub {
    # The proof case named in the bare-file-protocol plan as THE BIG ONE.
    my ($perl, $lli, undef, $err) = compile(<<'PROG');
use 5.42.0;
sub fib { my $n = shift; $n < 2 ? $n : fib($n-1) + fib($n-2) }
print fib(10), "\n";
PROG
    is $perl, "55\n", 'perl computes fib(10)' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# MULTIPLE ARGUMENTS, IN ORDER. Subtraction is not commutative, so a swapped
# pair gives a different answer rather than the same one.
subtest 'two arguments arrive in the right order' => sub {
    my ($perl, $lli, undef, $err) = compile(<<'PROG');
use 5.42.0;
sub diff { my ($a, $b) = @_; $a - $b }
print diff(10, 3), "\n";
PROG
    is $perl, "7\n", 'perl computes 10 - 3' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- -7 means the pair was swapped';
};

# THE CONTROL. Everything the inliner already lowered must still work. These
# shapes are green today, and a change of mechanism is exactly where they break.
subtest 'the shapes that already worked still do' => sub {
    my ($perl, $lli, undef, $err) = compile(<<'PROG');
use 5.42.0;
sub f { 7 }
my $a = f(); my $b = f();
print $a + $b, "\n";
PROG
    is $perl, "14\n", 'a constant sub called twice' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

done_testing;
