# ABOUTME: a sub returning a merge one way of which is a call (`return g()` in an arm): each way
# ABOUTME: in the caller's context -- the call's handed on, another value a list of it or it.
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

# lower($src) -> (ll or undef, the .pl, why)
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

for my $case (
    [ q{sub g { return (4, 5, 6) } sub f { my ($x) = @_; if ($x) { return g(); } return 7; } my @a = f(1); my $s = f(1); my $t = f(0); print scalar(@a), $s, $t, "\n";},
      'a list-returning call in one arm, a value after' ],
    [ q{sub g { 5 } sub f { my ($x) = @_; if ($x) { return g() } return 7 } my @a = f(1); my @b = f(0); my $s = f(1); print "@a|@b|$s\n";},
      'a call of one value in one arm' ],
    [ q{sub g { return (4, 5, 6) } sub f { return g() if $_[0]; 7 } print join(",", f(1)), " ", scalar(f(1)), " ", join(",", f(0)), "\n";},
      'a call returned in a postfix if, a last value' ],
    # (A MERGE OF SCALARS, a call of the sub itself one way: its value, as before)
    [ q{sub f { my $n = shift; return f($n - 1) if $n > 0; 7 } my @a = f(2); my $s = f(1); print scalar(@a), " $a[0] $s\n";},
      'a recursive call returned in one arm, a value after' ],
) {
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

# A WAY THAT IS A LIST of its own (`return (1, 2)` beside a call): refused by name.
{
    my ($ll, undef, $why) = lower(q{sub g { return (4, 5) } sub f { my @l = (1, 2); return g() if $_[0]; @l } my @a = f(0); print "@a\n";});
    ok(!defined $ll, 'a list way beside a call: refused');
    like($why // '', qr/T2: out of its slices \(/, 'by T2') or diag $why;
}

done_testing;
