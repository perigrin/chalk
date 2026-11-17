# ABOUTME: a sub stored into a glob's code slot at run time (*name = sub {...}, *name = \&other) is in
# ABOUTME: its package's run-time stash from then on: a call by the name, can() and a method call find it there.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

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
    [ q~my $n = $ENV{X} // 3;
*sq = sub { $_[0] * $_[0] };
print sq($n), " ", $n * 2, "\\n";
~, 'an anonymous sub stored into a glob, called by its name', q~~ ],
    [ q~package A; sub rr { "rr$_[0]" }
package B; *rr = \\&A::rr; sub f { return rr($_[0]) }
package main; *rr = \\&A::rr; print B::f(3), rr(4), "\\n";
~, 'a named sub stored into two packages\' globs, one called from a sub', q~~ ],
    [ q~sub f { return g(2) }
my $r = eval { f() };
print defined $r ? "got $r" : "died: $@";
*g = sub { "g$_[0]" };
print f(), "\\n";
~, 'called before the glob holds it: perl\'s die', q~~ ],
    [ q~package P; sub new { bless {}, shift }
package main;
print P->can("hi") ? "y" : "n";
*P::hi = sub { "hi from P" };
print P->can("hi") ? "y" : "n", " ", P->new->hi, "\\n";
~, 'can() finds what the glob holds', q~~ ],
    [ q~my $c = sub { 7 }; *h = $c; print h(), "\\n";
~, 'a glob given a code value B::SoN folded to its sub', q~~ ],
    [ q~my $k = 5; *h = sub { $k + 1 }; $k = 9; print h(), "\\n";
~, 'a glob given a closure', q~a glob given a closure~ ],
) {
    my ($src, $name, $refuse) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    if (length $refuse) {
        ok(!$err && ( $u->{path} // '' ) ne 't2' && ( $u->{path_why} // '' ) =~ /$refuse/, "$name: refused by name") or diag $err // $u->{path_why} // 'lowered';
        next;
    }
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
