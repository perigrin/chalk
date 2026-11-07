# ABOUTME: T2 slice 26 -- UNIVERSAL::VERSION: a package's $VERSION (its own, not inherited), and
# ABOUTME: with a wanted version perl's check -- decimal or dotted -- dying as perl does.
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
    [ q{package A; our $VERSION = "1.5"; sub new { bless {}, shift } package B2; sub b { 1 } package C; our $VERSION = "1.2.3"; package D; our @ISA = ("A"); package main; print A->VERSION, "|", defined(B2->VERSION) ? "d" : "u", "|", defined(D->VERSION) ? "d" : "u", "|", A->new->VERSION, "\n";}, 'VERSION is the package VERSION, not inherited' ],
    [ q{package A; our $VERSION = "1.5"; sub new { bless {}, shift } package B2; sub b { 1 } package C; our $VERSION = "1.2.3"; package D; our @ISA = ("A"); package main; print A->VERSION(1.2), " ", A->VERSION("1.10"), "\n";}, 'a version check that passes gives the version' ],
    [ q{package A; our $VERSION = "1.5"; sub new { bless {}, shift } package B2; sub b { 1 } package C; our $VERSION = "1.2.3"; package D; our @ISA = ("A"); package main; my $r = eval { A->VERSION(2); 1 }; print defined $r ? "r\n" : "caught $@";}, 'a version too low dies' ],
    [ q{package A; our $VERSION = "1.5"; sub new { bless {}, shift } package B2; sub b { 1 } package C; our $VERSION = "1.2.3"; package D; our @ISA = ("A"); package main; my $r = eval { B2->VERSION(1); 1 }; print defined $r ? "r\n" : "caught $@";}, 'a package with no VERSION dies' ],
    [ q{package A; our $VERSION = "1.5"; sub new { bless {}, shift } package B2; sub b { 1 } package C; our $VERSION = "1.2.3"; package D; our @ISA = ("A"); package main; my $r = eval { C->VERSION("1.3"); 1 }; print defined $r ? "r\n" : "caught $@"; print C->VERSION("1.2"), "\n";}, 'a dotted version compares part by part' ],
    [ q{package A; our $VERSION = "1.5"; sub new { bless {}, shift } package B2; sub b { 1 } package C; our $VERSION = "1.2.3"; package D; our @ISA = ("A"); package main; my $r = eval { Nope->VERSION(1); 1 }; print defined $r ? "r\n" : "caught $@";}, 'a package not loaded dies' ],
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
