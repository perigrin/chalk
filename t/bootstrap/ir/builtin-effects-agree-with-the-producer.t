# ABOUTME: BuiltinTable's effect_* columns say what B::SoN's EffectTable says of every builtin: what it
# ABOUTME: writes, is a version of, faults on, the state it reads, and whether it is known at all.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use Chalk::Grammar::Perl::BuiltinTable;

# WHY. The loader checks a wire's reads and effects (WireReads, L13 and L14)
# by these columns; the producer places builtins by its own table. Two tables
# drift (the memory note "the memory table must be scraped"): this holds them
# to one answer, for every builtin either names.
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN/EffectTable.pm";
unshift @INC, $SON;
require B::SoN::EffectTable;

sub fact ( $n, $c ) { Chalk::Grammar::Perl::BuiltinTable::fact( $n, $c ) }
sub known ($n) { ( grep { fact( $n, $_ ) } qw(effect_writes effect_version effect_faults effect_reads effect_pure effect_own_handler effect_elsewhere) ) ? 1 : 0 }

my %names = map { ( $_ => 1 ) } B::SoN::EffectTable::names(), grep { known($_) } Chalk::Grammar::Perl::BuiltinTable::names();
ok( keys(%names) > 150, scalar( keys %names ) . ' builtins' );
for my $n ( sort keys %names ) {
    my %chalk = (
        known   => known($n),
        writes  => fact( $n, 'effect_own_handler' ) || !known($n) || fact( $n, 'effect_writes' ) ? 1 : 0,
        version => fact( $n, 'effect_own_version' ) || fact( $n, 'effect_version' ) ? 1 : 0,
        faults  => fact( $n, 'effect_faults' ) ? 1 : 0,
        reads   => fact( $n, 'effect_reads' ) // '',
    );
    my %son = (
        known   => B::SoN::EffectTable::known($n),
        writes  => B::SoN::EffectTable::writes($n),
        version => B::SoN::EffectTable::is_version($n),
        faults  => B::SoN::EffectTable::faults($n),
        reads   => B::SoN::EffectTable::reads_state($n) // '',
    );
    is_deeply( \%chalk, \%son, "$n: as B::SoN says" );
}

done_testing;
