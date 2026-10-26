# ABOUTME: a hash built from a list -- @_, an array, a map, pairs around them -- and one
# ABOUTME: whose keys repeat keeps the last of each: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

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

# A hash literal with a list among its pairs was refused (pvm 070 084 176
# 228); one whose keys repeat kept every pair, and a read found the first
# (older: `(a => 1, a => 3)` read 1, with 2 keys).
for my $c (
    [ q{my %h = (a => 1, b => 2, a => 3); print $h{a}, scalar(keys %h), "\n";} ],
    [ q{my $h = { a => 1, a => 3 }; print $h->{a}, scalar(keys %$h), "\n";} ],
    [ q{my ($k, $j) = ("x", "x"); my %h = ($k => 1, $j => 2); print $h{x}, scalar(keys %h), "\n";} ],
    [ q{sub f { my %o = @_; join ",", map { "$_=$o{$_}" } sort keys %o } print f(a => 1, b => 2), "|", f(), "\n";} ],
    [ q{my @l = (a => 1, a => 2); my %h = @l; print $h{a}, scalar(keys %h), "\n";} ],
    [ q{my @l = ("a"); my %h = @l; print exists $h{a} ? "e" : "n", defined $h{a} ? "d" : "u", "\n";} ],
    [ q{my %h = map { $_ => length $_ } qw(aa b); print "$h{aa}$h{b}\n";} ],
    [ q{my @l = (b => 2); my %h = (a => 1, @l, c => 3); print join(",", map { "$_$h{$_}" } sort keys %h), "\n";} ],
    [ q{my @l = (k => [1, 2]); my %h = @l; print scalar(@{ $h{k} }), "\n";} ],
    [ q{sub f { my %o = @_; exists $o{a} ? $o{a} : "dflt" } print f(a => 1), f(b => 2), "\n";} ],
    # A HASH AMONG THE PAIRS is its pairs (pvm 176).
    [ q{my %a = (x => 1, y => 2); my %b = (%a, y => 3, z => 4); print join(",", map { "$_$b{$_}" } sort keys %b), "\n";} ],
    [ q{my $s = { c => { a => 1 } }; my $t = { %{ $s->{c} }, n => 1 }; print join(",", sort keys %$t), "\n";} ],
    [ q{my %a = (k => "v"); my @l = (0, %a); print scalar(@l), " $l[1]$l[2]\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
