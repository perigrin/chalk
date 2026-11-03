# ABOUTME: T2 slice 3 -- a sub called directly is a T2 function: its scalar arguments and
# ABOUTME: its scalar return typed once (a %Slot where callers differ). Perl's answer.
our $LAST_LL;
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

sub through_llvm ($src, $env) {
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
    $LAST_LL = $units->[0]{ll};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

for my $case (
    [ q{sub fact { my $n = shift; return $n <= 1 ? 1 : $n * fact($n - 1) } print fact(5), "\n";}, 'a recursive sub' ],
    [ q{use v5.36; sub add ($x, $y) { return $x + $y } print add(2, 3), " ", add(0.5, 1), "\n";}, 'a signature, called with Ints and with a Num' ],
    [ q{sub pick { my $c = shift; return $c ? 0.1 + 0.2 : "x" } my $v = pick(1); print $v == 0.3 ? "eq" : "ne", " ", pick(0), "\n";}, 'a return of a number or a string' ],
    [ q{sub sq { my $x = shift; return $x * $x } my $t = 0; my $i = 1; while ($i <= 3) { $t = $t + sq($i); $i++ } print "$t\n";}, 'called in a loop' ],
    [ q{sub hi { my $who = shift; print "hi $who\n"; return 1 } hi("a"); hi("b");}, 'a sub that prints, its value unused' ],
    # A VARIABLE PASSED TO A SUB is kept in memory: its ++ is perl's, magic on a string.
    [ q{sub id { return $_[0] } my $s = "az"; id($s); $s++; my $n = 9; id($n); $n++; print "$s $n\n";}, '++ on a variable in memory, magic and numeric' ],
    # A READ BEFORE A STORE is the value before it.
    [ q{sub id { return $_[0] } my $i = 1; id($i); my $x = $i; $i = 5; print "$x $i\n";}, 'a read made before a store' ],
    # ...and before a store in an arm: $x is read before the if, not after it.
    [ q{sub id { return $_[0] } my $c = $ENV{NOPE} // 1; my $i = 1; id($i); my $x = $i; if ($c) { $i = 5 } print "$x $i\n";}, 'a read made before a store in an arm' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# PERL'S ANSWER, through T2 or not: a signature default is not T2's yet (its
# default was dropped: pvm 030 gave 1 for 4), and a big integer numified from
# a call keeps its digits (through a double it was 9.00719925474099e+15).
for my $case (
    [ q{use v5.36; sub add_up ($a, $b = 3) { $a + $b } print add_up(1), " ", add_up(1, 10), "\n";}, 'a signature default' ],
    [ q{sub g { return $_[0] } print g(9007199254740993) + 0, g("x"), "\n";}, 'a big integer numified' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

done_testing;
