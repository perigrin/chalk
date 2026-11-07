# ABOUTME: T2 slice 23 -- qualified method names: Pkg::m starts its lookup at Pkg, Pkg::SUPER::m
# ABOUTME: at Pkg's @ISA (the package the call is in); a miss is perl's die, naming that package.
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
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = B2->new; print $o->up, "\n";}, 'SUPER:: looks from the package the call is in' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = C3->new; print $o->up, "\n";}, 'SUPER:: of an inherited method is still its own package' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = B2->new; print $o->A::hi, " ", B2->A::hi, "\n";}, 'a qualified name starts at its package' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = C3->new; print $o->C3::hi, " ", $o->B2::hi, "\n";}, 'a qualified name walks the @ISA of its package' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = B2->new; my $r = eval { $o->nope; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a SUPER:: no parent answers' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = B2->new; my $r = eval { $o->A::zz; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a qualified name its package lacks' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = B2->new; my $r = eval { $o->Nope::zz; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a qualified name of a package not loaded' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $u = $ENV{NO_SUCH_VAR}; my $r = eval { $u->A::hi; 1 }; print defined $r ? "r\n" : "caught $@";}, 'a qualified name on undef' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; our @ISA = ("A"); sub hi { "B2::hi" } sub up { $_[0]->SUPER::hi } sub nope { $_[0]->SUPER::zz } package C3; our @ISA = ("B2"); package main; my $o = C3->new; print $o->B2::SUPER::hi, "\n";}, 'Pkg::SUPER:: starts at the @ISA of Pkg' ],
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
