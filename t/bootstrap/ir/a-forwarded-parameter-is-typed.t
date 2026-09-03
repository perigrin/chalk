# ABOUTME: A parameter passed onward reads as PadAccess, and must still get a type.
# ABOUTME: Only a Parameter node was seeded, so a forwarded parameter reached the backend untyped.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `method outer($k) { $self->inner($k) }` -- the parameter is PASSED ONWARD
# rather than consumed by an operation. Measured on the wire:
#
#   C::outer  PadAccess stamp=Object   {varname: '$self'}
#             PadAccess stamp=Unknown  {varname: '$k'}     <- no type
#             Call      stamp=Num      {name: 'inner'}
#
#   signature: {kind: declared, mandatory: 1,
#               params: [{index: 0, name: '$k', sigil: '$'}]}
#
# The producer names the BINDING -- the signature says `$k` is parameter 0 --
# and simply does not know its type, because it works method-by-method and
# cannot see a caller. The loader has the whole program and can.
#
# WHY IT WAS MISSED: the argument-seeding pass stamps `Parameter` NODES by
# index. A forwarded parameter never becomes a Parameter node; it is a pad read.
# So the seeding found nothing to stamp and the PadAccess reached the backend
# with no representation:
#
#   GAP: PadAccess reached LLVM backend with NO representation (undef)
#
# THE PRECEDENT IS ALREADY IN THE FILE. A `:reader` accessor's body reads its
# field through a PadAccess, and that is typed by matching `varname` against a
# known declaration (Analysis.pm:2418). This is the same mechanism keyed on the
# method signature instead of a field.
#
# THE SOUNDNESS RULE THIS MUST RESPECT: backward inference may only FILL A HOLE,
# never preempt a source. Every case below asserts a pad read that is
# `Unknown` -- a hole. A PadAccess that already carries a type must be left
# alone, which the last subtest pins from the other direction.

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

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=C $spath 2>/dev/null);
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

sub cls ($body, $call) {
    return <<"PROG";
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field \$n :param = 0;
$body
}
package main;
$call
PROG
}

subtest 'a forwarded parameter reaches the callee' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls("    method inner(\$v) { \$v + 1 }\n    method outer(\$k) { \$self->inner(\$k) }",
            'say(C->new(n=>1)->outer(41));'));
    is $perl, "42\n", 'perl forwards the argument and adds 1' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# TWO FORWARDED PARAMETERS, IN ORDER. One cannot distinguish "slot 0" from
# "the only slot", and subtraction is not commutative, so a swapped pair gives a
# different answer rather than the same one.
subtest 'two forwarded parameters keep their order' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls("    method sub2(\$a, \$b) { \$a - \$b }\n"
          . "    method outer(\$x, \$y) { \$self->sub2(\$x, \$y) }",
            'say(C->new(n=>1)->outer(10, 3));'));
    is $perl, "7\n", 'perl computes 10 - 3' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- -7 would mean the pair was swapped';
};

# A FORWARDED PARAMETER OF A DIFFERENT TYPE. If the fill were hardcoded to a
# single repr rather than derived from the callsite, this would be the case that
# exposes it -- a Str argument arriving where an Int was assumed.
subtest 'a forwarded Str parameter is typed as a Str' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls("    method inner(\$v) { \$v . \"!\" }\n    method outer(\$k) { \$self->inner(\$k) }",
            'say(C->new(n=>1)->outer("hi"));'));
    is $perl, "hi!\n", 'perl concatenates' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- the forwarded parameter carried Str, not Int';
};

# THE SOUNDNESS CONTROL, and it is the one that matters most. A pad read that
# ALREADY has a type must not be overwritten by this fill. `$self` is stamped
# Object on the wire; a fill that preempted it would either retype the invocant
# or refuse. Asserted POSITIVELY -- the program must still produce the right
# answer -- because a negative claim would be satisfied by any unrelated defect.
subtest 'a pad read that already has a type keeps it' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls("    method inner(\$v) { \$v + 1 }\n"
          . "    method outer(\$k) { \$self->inner(\$k) + \$n }",
            'say(C->new(n=>100)->outer(41));'));
    is $perl, "142\n", 'perl reads the field AND forwards the parameter' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- $self kept Object and $n kept its field type';
};

# THE REGRESSION CONTROL. A parameter CONSUMED by an operation still becomes a
# real Parameter node and is seeded by the existing path. It must not change.
subtest 'a consumed parameter still works' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls('    method plus($k) { $n + $k }', 'say(C->new(n=>10)->plus(32));'));
    is $perl, "42\n", 'perl adds field and argument' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- the Parameter-node path is untouched';
};

done_testing;
