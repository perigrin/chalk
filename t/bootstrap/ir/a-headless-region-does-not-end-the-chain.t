# ABOUTME: A Region with no If/Loop head must not truncate the control chain.
# ABOUTME: try/catch builds one, and every effect behind it was silently dropped.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `try { print "in\n"; $x = 1 } catch ($e) { $x = 2 }` emitted an EMPTY main().
# Not a refusal -- the module lowered, lli exited 0, and NOTHING printed where
# perl prints "in" and then 1. Both Prints were dropped, not just the try
# body's.
#
# TWO DEFECTS COMPOUND, and either alone would have been survivable:
#
#   1. _process_control_chain's Region arm asks the Region for its `head` (the
#      owning If/Loop) so it can process the head instead. A try/catch Region
#      HAS NO HEAD -- the producer desugars try/catch to a shared-control merge
#      with no runtime test to branch on -- so the arm fell to its else, pushed
#      the bare Region, and `last`. Everything behind it on the chain was
#      abandoned.
#
#   2. process_control_node handles If, Loop, statement-nodes and Unwind. A
#      Region matches none of them and falls off the end of the sub, so even
#      the one node that DID get pushed emitted nothing.
#
# The wire was correct throughout -- Print#6 (the try body) sits on the control
# chain at ctl=0 and Print#7 chains off it at ctl=6 -- and so was the loader.
# This is a backend walk that stopped early.
#
# The case is pinned BEHAVIOURALLY: a test that checked for the presence of a
# Print node would have passed the whole time, because the nodes exist in the
# graph and it is the WALK that skipped them.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

sub compile_and_run ($src) {
    my ($sfh, $spath) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$sfh} $src;
    close $sfh;

    my $oracle = qx($PERL $spath 2>/dev/null);

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $spath 2>/dev/null);
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

subtest 'a try body effect survives to the emitted program' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use feature "try";
no warnings "experimental::try";
my $x = 0;
try { print "in\n"; $x = 1 } catch ($e) { $x = 2 }
print $x, "\n";
PROG

    is $perl, "in\n1\n", 'perl runs the try body and then prints x' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees with perl'
        or diag("  an empty result means the control chain was truncated at\n"
              . "  the headless Region -- every effect behind it was dropped");
};

# A CAUGHT `die` MUST REFUSE, NOT ABORT -- and this subtest is the reason the
# previous version of it was not good enough.
#
# It used to assert the KNOWN WRONG ANSWER with `isnt`, because the producer
# dropped the die and the whole catch body. perl5-son then fixed that
# (b97f06f: two independent silent drops -- the catch arm was never walked,
# and the try body's die fell through an ungated path). My `isnt` KEPT PASSING
# across that fix, for a completely different reason: chalk had begun printing
# `caught` and then exiting 255, which is still not equal to perl.
#
# THAT IS THE FAILURE MODE THE ASSERTION WAS SUPPOSED TO CATCH. `isnt` says
# only "these differ" and cannot tell "the producer drops it" from "chalk
# aborts mid-program" -- two different defects, one green check. perl5-son
# asked me to verify it had started failing; it had not, and the check was the
# thing at fault.
#
# The property is now stated positively: a caught die must GAP. Chalk has no
# landingpad and no personality function, so an exception that must transfer
# control to a catch arm is genuinely unlowerable -- and the honest outcome is
# a refusal, not an `exit(255)` that kills every statement after the try/catch.
subtest 'a caught die REFUSES rather than aborting the program' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use feature "try";
no warnings "experimental::try";
my $x = 0;
try { die "boom\n"; $x = 1 } catch ($e) { print "caught\n"; $x = 2 }
print $x, "\n";
PROG

    is $perl, "caught\n2\n", 'perl catches and continues' or return;

    ok defined $err, 'chalk REFUSES rather than emitting a program'
        or diag("  it lowered and produced: " . (($lli // '') =~ s/\n/\\n/gr)
              . "\n  aborting at a caught die kills every statement after the\n"
              . "  try/catch -- a wrong answer where a GAP was available");

    like $err, qr/landingpad|personality|caught die|inside a try/i,
        'and the refusal names what is missing'
        if defined $err;
};

# THE GUARD THAT KEEPS THE FIX HONEST. An if/else Region HAS a head, and that
# path must keep working -- the fix touches the arm that both shapes go
# through, so the shape that already worked is the regression risk.
subtest 'an if/else Region still lowers (the head path is unbroken)' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $c = 1;
my $x = 0;
if ($c) { print "then\n"; $x = 1 } else { print "else\n"; $x = 2 }
print $x, "\n";
PROG

    is $perl, "then\n1\n", 'perl takes the then arm' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- an If-headed Region is unaffected';
};

done_testing;
