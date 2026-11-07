# ABOUTME: T2 slice 22 -- the dies perl makes itself (a zero divisor, a zero modulus) are dies
# ABOUTME: like any other: an eval catches them, with perl's message in $@; uncaught they exit.
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
    [ q{my $z = $ENV{NO_SUCH_VAR} // 0; my $r = eval { 7 / $z }; print defined $r ? "r=$r\n" : "caught $@";}, 'a zero divisor in an eval' ],
    [ q{my $z = $ENV{NO_SUCH_VAR} // 0; my $r = eval { 7 % $z }; print defined $r ? "r=$r\n" : "caught $@";}, 'a zero modulus in an eval' ],
    [ q{sub d { return $_[0] / $_[1] } my $r = eval { d(1, 2) + d(1, 0) }; print defined $r ? "r=$r\n" : "caught $@"; print d(9, 3), "\n";}, 'a zero divisor in a called sub' ],
    [ q{my $z = $ENV{NO_SUCH_VAR} // 0; my $r = eval { 1 }; print "ok\n"; print 7 / $z, "\n"; print "never\n";}, 'a zero divisor outside an eval still exits' ],
    [ q{package C; sub new { bless {}, shift } package main; my $r = eval { C->new->nope; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a method no class answers' ],
    [ q{package C; sub m { 1 } package main; my $r = eval { Nope->m; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a method of a package not loaded' ],
    [ q{package C; sub m { 1 } package main; my $o = $ENV{NO_SUCH_VAR}; my $r = eval { $o->m; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a method on undef' ],
    [ q{package C; sub m { 1 } package main; my $o = {}; my $r = eval { $o->m; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a method on an unblessed reference' ],
    [ q{package C; sub new { bless {}, shift } package main; my $r = eval { 1 }; print "ok\n"; C->new->nope; print "never\n";}, 'a method no class answers, outside an eval, exits' ],
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
