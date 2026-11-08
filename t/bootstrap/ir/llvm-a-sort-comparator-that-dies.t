# ABOUTME: a sort comparator that can die: perl's answer through B::SoN -> chalk -> lli,
# ABOUTME: or refused by name -- never the die dropped and the sort finished.
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

sub through_llvm ($src, $env) {
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
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    return ("exit " . ($? >> 8) . ": $out", $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    my $out = qx($^X $pl 2>&1);
    return "exit " . ($? >> 8) . ": $out";
}




# The comparator's die was dropped: `[1 2 3]` printed where perl dies (and,
# in an eval, where perl gives the empty list and sets $@ -- pvm 092).
for my $case (
    [ q{my @r = sort { die "boom\n" if $a == 2; $a <=> $b } 3, 1, 2; print "[@r]\n";}, 'outside an eval' ],
    [ q{my @r = eval { sort { die "boom\n" if $a == 2; $a <=> $b } 3, 1, 2 }; print "[@r] $@";}, 'pvm 092' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); next }
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# A comparator that cannot die still sorts.
{
    my $src = q{my @r = sort { $a <=> $b } 3, 1, 2; print "[@r]\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "a comparator that cannot die: perl's answer") or diag $@;
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
