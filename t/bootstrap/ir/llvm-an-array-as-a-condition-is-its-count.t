# ABOUTME: An array or hash as a condition is true when it holds anything -- its count,
# ABOUTME: not zero: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# An array as a condition was refused ("If.cond[Array->Boolean]", pvm 088
# 089 174).
for my $c (
    [ q{my @a = (3, 1, 2); if (!@ARGV) { print "none\n" } if (@a) { print "some\n" }},         "none\nsome\n", 'an if' ],
    [ q{my @e = (); my @f = (1); print @e ? "e" : "-", @f ? "f" : "-", "\n";},               "-f\n",         'a ternary' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A HASH as a condition is its count of keys, at the memory version B::SoN
# reads it at (Count(hash, memory)): a `my %h`, and a package hash by name
# (its EntryDef), whose count was an array's length ("an array element read
# through no ARRAY reference" at run time).
for my $c (
    [ q{my @e = (); my %h = (a => 1); print @e ? "e" : "-", %h ? "h" : "-", "\n";},        "-h\n",      'a hash in a ternary' ],
    [ q{my %h; my $a = %h ? 1 : 0; $h{k} = 1; my $b = %h ? 1 : 0; delete $h{k}; print "$a$b", (%h ? 1 : 0), "\n";}, "010\n", 'a hash read before a store, after it, and emptied' ],
    [ q{my %h; my $n = %h; $h{a} = 1; $h{b} = 2; my $m = %h; print "$n $m ", %h + 1, "\n"; print "e\n" if !%h;}, "0 2 3\n", 'a hash as a number' ],
    [ q{our %g; print %g ? "y" : "n"; $g{a} = 1; print %g ? "y" : "n"; my $n = %g; %g = (); print " $n ", (!%g ? "e" : "ne"), "\n";}, "ny 1 e\n", 'a package hash, declared with no value' ],
    [ q{our %g; sub add { $g{$_[0]} = 1 } my $a = %g; add("x"); my $b = %g; add("y"); print "$a $b ", scalar(%g), "\n";}, "0 1 2\n", 'a package hash a called sub fills' ],
    [ q{our %g = (a => 1, b => 2); if (%g) { print scalar(%g), "\n" }},                    "2\n",       'a package hash, stored whole' ],
    [ q{package P; our %reg; sub n { return scalar(%reg) } package main; $P::reg{a} = 1; $P::reg{b} = 2; print P::n(), " ", (%P::reg ? "t" : "f"), "\n";}, "2 t\n", 'a hash of another package' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
