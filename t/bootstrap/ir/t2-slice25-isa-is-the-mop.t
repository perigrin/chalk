# ABOUTME: T2 slice 25 -- @Pkg::ISA is the run-time MOP's own parent list: push, unshift,
# ABOUTME: pop, shift and reads act on the array method lookup walks (perigrin: a tied @ISA).
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
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; sub hi { "B2::hi" } package C3; sub new { bless {}, shift } package main; my $o = C3->new; push @C3::ISA, "A"; print $o->hi, " ", $o->isa("A") ? "y" : "n", "\n";}, 'push onto ISA gives a parent' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; sub hi { "B2::hi" } package C3; sub new { bless {}, shift } package main; my $o = C3->new; push @C3::ISA, "A"; unshift @C3::ISA, "B2"; print $o->hi, " [@C3::ISA] ", scalar(@C3::ISA), "\n";}, 'unshift puts a parent first; the array reads as the parents' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; sub hi { "B2::hi" } package C3; sub new { bless {}, shift } package main; my $o = C3->new; @C3::ISA = ("A", "B2"); pop @C3::ISA; shift @C3::ISA; my $r = eval { $o->hi; 1 }; print defined $r ? "r\n" : "caught $@";}, 'pop and shift take parents away' ],
    [ q{package A; sub new { bless {}, shift } sub hi { "A::hi" } package B2; sub hi { "B2::hi" } package C3; sub new { bless {}, shift } package main; package D4; our @ISA; push @ISA, "A"; package main; print D4->hi, " $D4::ISA[0]\n";}, 'an unqualified ISA in its package' ],
    [ q{my @a = (3); my $n = unshift @a, 1, 2; unshift @a, 0; print "@a $n ", scalar(@a), "\n";}, 'unshift of a plain array' ],
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
