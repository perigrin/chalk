# ABOUTME: The loader holds L11 (SoN::Verify's V12, ported): an argument or a foreach/map/grep item carried
# ABOUTME: as a value must not be read after a store perl's alias would see; it agrees with the verifier.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use JSON::PP;
use File::Temp qw(tempdir);
use Chalk::IR::Serialize::JSON;

# WHY (third final audit, risk 5). SoN::Verify's two alias rules caught nine
# wrong wires, and the loader did not run them: chalk compiled all nine
# (ya49 `113` for perl's `123`). Ported into the loader as L11
# (Chalk::IR::Serialize::WireAliases); this holds the port to the verifier's
# answer, wire by wire.
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
unshift @INC, $SON;
require SoN::Verify;

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -I$SON -MO=-q,SoN,json $f 2>/dev/null);
}
sub refused ($json) { return eval { Chalk::IR::Serialize::JSON::from_json($json); 1 } ? '' : $@ }
sub v12 ($json) { return scalar grep { $_->{rule} eq 'alias-not-private' } SoN::Verify::verify( decode_json($json) )->{violations}->@* }

# (the audit's y probes the verifier flags: five wrong, the rest right by luck)
for my $src (
    'my $x=1; sub f { my $s=""; for my $i (1..2) { my ($p)=@_; $s.=$p; $x++ } $s } print f($x), "$x\n";',
    'my $x=1; sub f { my $s=""; my $i=0; while ($i++ < 2) { my ($p)=@_; $s.=$p; $x++ } $s } print f($x), "$x\n";',
    'my $x=1; sub g { $x++ } sub f { my $s=""; for my $i (1..2) { $s.=$_[0]; g() } $s } print f($x), "$x\n";',
    'my @a=(1,2); sub z { $a[1]=7 } for (@a) { my $v=$_; z(); print $v } print "\n";',
    'my @a=(1,2); print map { my $v=$_; $a[1]=7; $v } @a; print "\n";',
) {
    my $w = wire($src);
    ok( v12($w), "the verifier flags it: $src" );
    like( refused($w), qr/\AGAP: wire invariant L11: /, "...and the loader refuses it by L11" );
}

# (no store between: both clean, and it loads)
for my $src (
    'my $x=1; sub f { my ($p)=@_; $p+1 } print f($x), "$x\n";',
    'our @a=(1,2,3); my $s=""; for my $v (@a) { $s.=$v } print "$s\n";',
    'my $x=1; sub g { 1 } sub f { my $s=""; for my $i (1..2) { $s.=$_[0]; g() } $s } print f($x), "$x\n";',
) {
    my $w = wire($src);
    is( v12($w), 0, "the verifier is clean: $src" );
    unlike( refused($w), qr/L11/, '...and L11 lets it through' );
}

done_testing;
