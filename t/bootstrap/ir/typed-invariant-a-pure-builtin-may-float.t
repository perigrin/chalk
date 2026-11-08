# ABOUTME: the control-chain leg exempts a PURE builtin Call (join, keys, values, a sort perl
# ABOUTME: folded): B::SoN floats them, as it does a value op; any other Call must be pinned.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;
require Chalk::IR::Graph::TypedInvariant;

sub violations ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my (undef, $graphs) = Chalk::CodeGen::Pipeline->new->run_detail($json, sub { () }, program_mode => 1);
    my $r = Chalk::IR::Graph::TypedInvariant->check($graphs->{'main::__PROGRAM__'});
    return grep { $_->{message} =~ /broken effect chain/ } @{ $r->{violations} // [] };
}
is(scalar violations(q{my @s = sort { $a <=> $b } (3,1,2); print "$s[0]\n";}), 0, 'a folded sort floats (corpus F18)');
is(scalar violations(q{my %h = (a => 1, b => 2); print join(",", sort keys %h), "\n";}), 0, 'keys, a folded sort and join float');
done_testing;
