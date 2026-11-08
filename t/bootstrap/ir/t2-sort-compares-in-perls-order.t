# ABOUTME: a sort's comparator is called on perl's pairs in perl's order (pp_sort.c's merge sort,
# ABOUTME: ported): a comparator with an effect -- a count, a print, a die, a call -- answers as perl's.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

for my $case (
    [ q{my $n = 0; my @s = sort { $n++; $a <=> $b } 5, 3, 9, 1, 7, 2, 8; print "@s $n\n";}, 'a comparator counting its calls: perl\'s count' ],
    [ q{my @s = sort { print "$a$b "; $a <=> $b } 3, 1, 2, 5, 4; print "\n@s\n";}, 'a comparator printing each pair: perl\'s pairs, in perl\'s order' ],
    [ q{my @r = sort { die "boom\n" if $a == 2 || $b == 2; $a <=> $b } 3, 1, 2; print "[@r]\n";}, 'a comparator that dies' ],
    [ q{my $n = 0; sub k { $n++; return $_[0] * 2 } my @s = sort { k($a) <=> k($b) } 4, 1, 3, 2; print "@s $n\n";}, 'a comparator calling a sub with an effect' ],
    [ q{my @s = sort { ($a % 3) <=> ($b % 3) or $a <=> $b } 1 .. 9; print "@s\n";}, 'a modulus in a comparator' ],
    [ q{my $n = 0; my @s = sort { $n++; $a <=> $b } map { ($_ * 7) % 26 } 1 .. 40; print "$n $s[0] $s[-1]\n";}, 'forty: perl\'s runs and merges, its count' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    ok(defined $ll && $ll =~ /^; chalk T2/m, "$name: lowered through T2") or diag $err // $units->[0]{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
