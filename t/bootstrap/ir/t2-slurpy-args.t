# ABOUTME: a slurpy target takes the arguments past the positional ones -- `my ($c, @x) = @_`
# ABOUTME: and `sub f ($c, @x)` alike (perigrin: identical), and @_ after shifts.
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
    [ q{sub f { my ($c, @x) = @_; "$c:" . join(",", @x) . ":" . scalar(@x) } print f(1, 2, 3), " ", f(4), "\n";}, 'my ($c, @x) = @_' ],
    [ q{use v5.36; sub f ($c, @x) { "$c:" . join(",", @x) . ":" . scalar(@x) } print f(1, 2, 3), " ", f(4), "\n";}, 'sub f ($c, @x)' ],
    [ q{sub f { my ($k, %o) = @_; "$k:$o{x},$o{y}:" . scalar(keys %o) } print f("a", y => 2, x => 1), "\n";}, 'my ($k, %o) = @_' ],
    [ q{use v5.36; sub f ($k, %o) { "$k:$o{x},$o{y}:" . scalar(keys %o) } print f("a", y => 2, x => 1), "\n";}, 'sub f ($k, %o)' ],
    [ q{sub f { my $s = shift; my $n = shift; "$s$n:" . join(",", @_) } print f("a", 1, 7, 8), "\n";}, '@_ read as a list after shifts' ],
    [ q{sub f { my ($c, @x) = @_; push @x, 9; "@x" } my @a = (1, 2); print f(0, @a), " @a\n";}, 'the slurpy array is a copy' ],
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
