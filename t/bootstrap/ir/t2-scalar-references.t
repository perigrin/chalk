# ABOUTME: scalar references: \$x is the variable's heap cell (tag 9), $$r reads and stores through it,
# ABOUTME: and a deref of no SCALAR reference dies as perl's does, at its site (B::SoN's), its eval's to catch.
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
    [ q{my $x = 5; my $r = \$x; print $$r, "\n"; $$r = 7; print "$x ", ref($r), "\n";}, 'a reference to a variable: read, store through it, ref' ],
    [ q{use strict; my $x = 5; my $r = \$x; my $v = eval { $$r }; print "$v\n";}, 'a deref in an eval' ],
    [ q{use strict; my $r = [1]; my $v = eval { my $t = $$r; 1 }; print defined $v ? "ok" : "died: $@";}, 'a deref of an array reference dies, caught' ],
    [ q{use strict; my $r = "abc"; eval { my $t = $$r; 1 } or print "d: $@"; print "after\n";}, 'a deref of a string under strict refs dies, caught' ],
    [ q{use strict; my $r = "abcdefghijklmnopqrstuvwxyz0123456789"; eval { my $t = $$r; 1 } or print "d: $@";}, 'the string in the message is cut at 32' ],
    [ q{use strict; my $r; eval { my $t = $$r; 1 } or print "d: $@"; print "a\n";}, 'a deref of undef under strict refs dies, caught' ],
    [ q{my $r; my $v = $$r; print defined $v ? "d" : "u", "\n";}, 'a deref of undef without strict is undef' ],
    [ q{sub inc { my $r = shift; $$r++ } my $n = 1; inc(\$n); inc(\$n); print "$n\n";}, 'a sub increments through a reference' ],
    [ q{sub f { 7 } my $c = \&f; my $x = 5; my $r = \$x; print $$r, " ", ref($c), " ", $c->(), "\n";}, 'a code reference beside a scalar deref' ],
    [ q{use strict; sub f { 7 } my $c = \&f; eval { my $t = $$c; 1 } or print "d: $@"; print "after\n";}, 'a deref of a code reference dies, caught' ],
    # `$$r .= "x"` (perl's multiconcat appending through the reference:
    # B::SoN refused it before)
    [ q{my $s = "a"; my $r = \$s; $$r .= "x"; print "$s\n";}, 'an append of a constant through a reference' ],
    [ q{my $s; my $r = \$s; $$r .= "x"; print "$s\n";}, 'an append of a constant to undef through a reference' ],
    [ q{my $s = "a"; my $r = \$s; my $y = 3; $$r .= "x${y}z"; print "$s\n";}, 'an append of strings and a value through a reference' ],
    [ q{my $s = "a"; my $r = \$s; $$r .= "x" for 1 .. 3; print "$s\n";}, 'an append through a reference in a loop' ],
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
