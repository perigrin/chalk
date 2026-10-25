# ABOUTME: A `return` from inside a loop leaves the sub there, with its value, skipping the
# ABOUTME: rest of the loop and what follows it: B::SoN -> chalk -> lli == perl.
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

# A RETURN INSIDE A LOOP is another way out of it: B::SoN joins it with the
# loop's own exit at the sub's return, a Region with no If of its own. It was
# refused ("Phi node encountered ... before its enclosing structure", pvm 100,
# 138, 139 -- the last now refused on its loop condition instead).
for my $case (
    [ q{sub f { for my $i (1 .. 3) { return "E$i" if $i == $_[0] } return "L" } print f(2), f(9), "\n";}, "E2L\n", 'a return in a foreach' ],
    [ q{sub f { my $n = 0; while ($n < 10) { $n++; if ($n * $n > $_[0]) { return "past $n" } } return "none" } print f(20), " ", f(500), "\n";}, "past 5 none\n", 'a return in a while, from an if' ],
    [ q{sub f { for my $i (1 .. 5) { return "two" if $i == 2 && $_[0]; return "four" if $i == 4 } "end" } print f(1), f(0), "\n";}, "twofour\n", 'two returns in one loop' ],
    [ q{my %cache; sub f { my $n = 0; while ($n < 5) { $n++; if ($n == $_[0]) { $cache{$_[0]} = "hit"; return "at $n" } $cache{$_[0]} = "miss" } return "out" } print f(3), " ", f(9), " ", join(",", map { "$_=$cache{$_}" } sort keys %cache), "\n";}, "at 3 out 3=hit,9=miss\n", 'with a store in the arm and before it' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
