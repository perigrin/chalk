# ABOUTME: A wire whose `start_up` names what runs before the main line and is not on the wire (an INIT
# ABOUTME: block, a followed module's file-level code) is refused by the loader, in B::SoN's words.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use JSON::PP;
use File::Temp qw(tempdir);
use Chalk::IR::Serialize::JSON;

# WHY (third final audit, N9). The wire starts the main line from a followed
# module's package data as it stood at CHECK; a module's file lexicals, its
# prints at load, its import's stores and INIT blocks were not on it, and
# chalk ran from a guess (`use YPriv; print YPriv::priv()` printed nothing
# for 5). B::SoN names such a start-up on the wire (`start_up`); a consumer
# that runs the program from the wire refuses it.
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub refused ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $f 2>/dev/null);
    return eval { Chalk::IR::Serialize::JSON::from_json($json); 1 } ? '' : $@;
}

like( refused('INIT { print "i" } print "r\n";'), qr/\AGAP: an INIT block of the program runs before the main line/, 'an INIT block: refused in B::SoN\'s words' );
is( refused('BEGIN { print "" } print "r\n";'), '', 'a program with none loads' );
done_testing;
