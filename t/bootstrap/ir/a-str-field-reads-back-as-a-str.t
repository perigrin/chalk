# ABOUTME: A Str-typed field written by the constructor must read back as that Str.
# ABOUTME: The read's tag dispatch dropped its Str arm, so the cell fell to the undef path.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `field $s :param = "hi"; method get { $s }` printed an EMPTY LINE where perl
# prints `hi`. Not a refusal -- the module lowered, lli exited 0, and the wrong
# answer came out.
#
# Both halves of the write path were correct. The constructor boxes "hi" into a
# heap %StrPair and stores the pointer as the Slot payload with tag=3 (Str);
# the method returns that Slot intact. The READ is where it was lost: the
# method-body field read narrowed its tag dispatch to Int/Num/Boolean, so a
# Str-tagged cell matched nothing and fell to the undef arm, which yields "".
#
# THE ARM WAS DROPPED FOR AN EMISSION-ORDER REASON, not a semantic one: the Str
# arm GEPs a %StrPair, and a method body is lowered before the prologue that
# declares it. The real defect was one level up, in the pre-scan that decides
# whether to declare the type -- it asked which methods RETURN Str, and a Str
# FIELD builds a %StrPair without any method returning one. Here `get` returns
# `Scalar` (a :param field admits anything), so the scan saw no Str at all.
#
# This pins the BEHAVIOUR, not the emission: a test that only checked for a Str
# arm in the IR would pass on a module lli refuses.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON"  unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

# Compile a program through the real pipeline and RUN it, returning
# (perl_stdout, lli_stdout, lower_error).
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
    return ($oracle, undef, "load: $err")            if $err;
    return ($oracle, undef, 'no lowerable unit')     unless @$units;
    return ($oracle, undef, $units->[0]{err})        unless $units->[0]{ok};

    my ($lfh, $lpath) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lfh, ':utf8';
    print {$lfh} $units->[0]{ll};
    close $lfh;
    my $out = qx($LLI $lpath 2>&1);
    return ($oracle, $out, undef);
}

subtest 'a Str field read in a method returns the string, not undef' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG', 'package=main,package=Counter');
use 5.42.0;
use experimental "class";
class Counter { field $s :param = "hi"; method get { $s } }
package main;
say(Counter->new->get);
PROG

    is $perl, "hi\n", 'perl prints the field value' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl,
        'lli agrees with perl -- the Str-tagged cell is not read as undef'
        or diag("  an empty result means the Str arm of the tag dispatch is\n"
              . "  missing, so the cell fell to the undef path");
};

# The Int case shares the dispatch and must not regress: restoring the Str arm
# adds a tag test, and a wrong tag ORDER would send an Int cell down it.
subtest 'an Int field still reads back as its Int' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG', 'package=main,package=Box');
use 5.42.0;
use experimental "class";
class Box { field $n :param = 7; method get { $n } }
package main;
say(Box->new->get);
PROG

    is $perl, "7\n", 'perl prints the Int field' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- the Int arm is unaffected';
};

# A Str field passed as a constructor ARGUMENT rather than taken from the
# default: the same read path, reached with a value the class never saw at
# compile time.
subtest 'a Str field bound from a constructor argument reads back' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG', 'package=main,package=Tag');
use 5.42.0;
use experimental "class";
class Tag { field $s :param = "default"; method get { $s } }
package main;
say(Tag->new(s => "passed")->get);
PROG

    is $perl, "passed\n", 'perl prints the passed value' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees for an argument-bound Str field';
};

done_testing;
