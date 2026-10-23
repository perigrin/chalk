# ABOUTME: A scalar handed to a call is a location (`@_` aliases it), read and
# ABOUTME: stored through memory: through B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# A `my $x` HANDED TO A CALL arrives in memory form: its PadAccess reads a
# memory version, not a VarDecl, and every store to it was refused ("Assign
# lhs ... got MemStart", 38 pvm corpus cases). It is one %Slot per variable
# per call -- an inlined sub's `my $x` is not its caller's -- stored boxed
# and read at its memory version, as a shared file lexical is.
for my $case (
    [ q{sub ld { "l" . ($_[0] // "n") } my $f = 2; print ld($f), "\n";}, "l2\n", 'a lexical handed to a call' ],
    [ q{sub ld { "l" . $_[0] } my $f = 2; $f = 5; print ld($f), "\n";}, "l5\n", 'the value it holds at the call' ],
    [ q{sub ld { "l" . $_[0] } my $f = 2; my $s = ld($f); $f = 7; print $s, ld($f), "\n";}, "l2l7\n", 'a read is at its memory version' ],
    [ q{sub ld { "l" . $_[0] } my $x = 1; print ld($x); { my $x = 2; print ld($x); } print ld($x), "\n";}, "l1l2l1\n", 'a shadowing my is another variable' ],
    [ q{sub ld { "l" . ($_[0] // "n") } sub find { my $want = shift; my $found; if ($want) { $found = "it"; } return ld($found) } print find(1), ";", find(0), "\n";}, "lit;ln\n", 'stored in an arm, in a sub called twice' ],
    [ q{sub ld { "l" . $_[0] } sub inner { my $x = 5; return ld($x) } sub outer { my $x = 1; my $r = inner(); return $r . ld($x) } print outer(), "\n";}, "l5l1\n", "a callee's my is not its caller's" ],
    [ q{sub ld { "l" . ($_[0] // "n") } for my $i (1 .. 3) { my $v; $v = $i if $i > 1; print ld($v) } print "\n";}, "lnl2l3\n", 'a my in a loop is fresh each pass' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A CALLEE THAT WRITES ITS ARGUMENT writes the caller's variable. Lowered
# with the argument bound by value, the caller would print 1: refused, or
# right -- never that.
{
    my $got = eval { through_llvm(q{sub inc { $_[0] = $_[0] + 1 } my $c = 1; inc($c); print "$c\n";}) };
    ok(!defined $got || ($got // '') eq "2\n", 'a write to $_[0] is refused or seen')
        or diag "got: " . ($got // $@);
}

done_testing;
