# ABOUTME: a sub whose last statement is an if (with a postfix if in its arm) returns perl's value:
# ABOUTME: the condition's where it is false, the arm's value where it is true.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
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
    [ q~my $calls = 0;
sub helper { $calls++ }
sub f { my ($x, $y) = @_; if ($x > 3) { helper() if $y > 3; } }
f(5, 5); f(5, 1); f(1, 5);
print "$calls\\n";
~, 'a postfix if in an if\'s arm, the sub\'s value unused' ],
    [ q~sub f { my ($x, $y) = @_; if ($x > 3) { "y$y" if $y > 3; } }
my @r = map { my $v = f(@$_); defined $v ? "[$v]" : "u" } [5, 5], [5, 1], [1, 5];
print "@r\\n";
~, 'its value read' ],
    [ q~sub f { my ($x, $y) = @_; unless ($x > 3) { "y$y" if $y > 3; } }
print join(",", map { f(@$_) // "u" } [5, 5], [1, 5], [1, 1]), "\\n";
~, 'an unless' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    ok(defined $ll, "$name: lowered through T2") or diag $err // $u->{path_why} // $u->{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lf, ':utf8'; print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
