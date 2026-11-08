# ABOUTME: a file lexical shared with a sub or a sort block (B::SoN file) is one variable for the
# ABOUTME: program: one global -- a scalar's slot, a hash's or array's reference made at first use.
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
    [ q{my $n = 0; sub f { $n++ } f(); f(); print "$n\n";}, 'a file lexical a sub increments' ],
    [ q{my $t = "a"; sub g { $t .= "b" } sub h { "$t!" } g(); g(); print h(), "\n";}, 'two subs share one file lexical' ],
    [ q{my $c = 0; sub inc { $c = $c + 1; $c } print inc(), inc(), " $c\n";}, 'a sub stores, the program reads' ],
    [ q{my %h = (x => 3, y => 1, z => 2); print join(",", sort { $h{$a} <=> $h{$b} } keys %h), "\n";}, 'a comparator reading a hash of the program' ],
    [ q{my @k = (5, 3, 9); print join(",", sort { $k[$a] <=> $k[$b] } 0 .. 2), "\n";}, 'a comparator reading an array of the program' ],
    [ q{my %h = (x => 3, y => 1, z => 2); my $r = \%h; print join(",", sort { $r->{$a} <=> $r->{$b} } keys %h), "\n";}, 'a comparator reading a reference of the program' ],
    [ q{my $m = -1; my @s = sort { $m * ($a <=> $b) } 3, 1, 2; print "@s\n";}, 'a comparator reading a scalar of the program' ],
    [ q{my %w = (x => 3, y => 1, z => 2); my $r = \%w; print join(",", sort { $r->{$a} <=> $r->{$b} } keys %w), "\n";}, 'a comparator through a reference to a hash of the program' ],
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
