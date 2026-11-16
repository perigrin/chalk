# ABOUTME: an element dereferenced for a write -- a foreach's list, a store two down an argument,
# ABOUTME: a push -- is made a hash or array first where it is undef (B::SoN's `//= []`), as perl's.
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

# lower($src) -> (ll or undef, the .pl, why): through T2 alone
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

# as_perl([src, name], ...): each through T2 alone, its output, message and exit code perl's.
sub as_perl (@cases) {
    for my $case (@cases) {
        my ($src, $name) = @$case;
        my ($ll, $pl, $why) = lower($src);
        ok(defined $ll, "$name: lowered through T2") or diag $why;
        next unless defined $ll;
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $ll; close $lf;
        my $got  = run("timeout 20 $LLI $llp");
        my $want = run("$^X $pl");
        is($got->[0], $want->[0], "$name: perl's output");
        is($got->[1], $want->[1], "$name: perl's message");
        is($got->[2], $want->[2], "$name: perl's exit code");
    }
}

as_perl(
    # A FOREACH OVER AN UNDEF ELEMENT makes it an array (its list is an lvalue).
    [ q{my %h; my $n = 0; for my $e (@{$h{x}}) { $n++ } print $n, exists $h{x} ? " viv\n" : " no\n";}, "a foreach over a `my` hash's element" ],
    [ q{my %in = (a => [[1, 2], 3], b => [4]); my @o; for my $d (qw(a b c)) { for my $i ($in{$d}->@*) { push @o, ref $i ? "r" : "$d$i" } } print "@o ", join(",", sort keys %in), "\n";}, 'in a loop body, over a key not there' ],
    [ q{sub f { my ($n) = @_; my $c = 0; for my $k ($n->{kids}->@*) { $c++ } return $c . (exists $n->{kids} ? "v" : "n") } print f({}), f({kids => [1, 2]}), "\n";}, 'through a reference an argument holds (pvm c135)' ],
    [ q{sub f { my ($r) = @_; my $c = 0; for my $k (@{$r->[1]}) { $c++ } return $c . scalar(@$r) } print f([]), f([0, [1]]), "\n";}, "an array reference's element" ],
    # A STORE TWO DOWN A REFERENCE AN ARGUMENT HOLDS makes the middle one.
    [ q{sub f { my ($s, $k) = @_; $s->{t}{$k} = 1; return } my $s = {}; f($s, "a"); f($s, "b"); print join(",", sort keys %{$s->{t}}), "\n";}, 'a hash two down an argument (pvm c175)' ],
    [ q{sub f { my ($s) = @_; push @{$s->{l}}, 1; push $s->{l}->@*, 2; return scalar @{$s->{l}} } my $s = {}; print f($s), f($s), "\n";}, 'a push onto an array an argument\'s element holds' ],
    [ q{sub f { my ($s, @k) = @_; $s->{t}{$_} = 1 for @k; return join ",", sort keys %{$s->{t}} } print f({}, qw(a b)), "\n";}, 'in a loop body (pvm c224)' ],
    [ q{sub f { my ($s, $k) = @_; if ($k) { $s->{t}{$k} = 1 } else { $s->{u}[2] = 0 } return } my $s = {}; f($s, "a"); f($s, 0); print join(",", sort keys %$s), scalar(@{$s->{u}}), "\n";}, 'in either arm of an if' ],
);
done_testing;
