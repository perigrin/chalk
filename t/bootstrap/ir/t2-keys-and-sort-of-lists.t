# ABOUTME: keys and values of a hash through a reference, and sort over a list value
# ABOUTME: (keys, an array) -- each a list where a list is wanted.
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
    [ q{my %h = (b => 2, a => 1); my $r = \%h; print join(",", sort keys %$r), " ", scalar(keys %$r), "\n";}, 'keys of a hash through a reference' ],
    [ q{my $r = { y => 1, x => 2 }; print join(",", sort values %$r), "\n";}, 'values through a reference' ],
    [ q{sub f { my ($k, %o) = @_; "$k:" . join(",", map { "$_=$o{$_}" } sort keys %o) } print f("a", y => 2, x => 1), "\n";}, 'sort over keys of a slurpy hash' ],
    [ q{my %h = (b => 2, a => 1, c => 3); my @k = sort keys %h; print "@k ", scalar(@k), "\n";}, 'sort keys into an array' ],
    [ q{my @a = (3, 1, 2); print join(",", sort { $a <=> $b } @a), " ", join(",", reverse sort @a), "\n";}, 'sort of an array, and reversed' ],
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
