# ABOUTME: The loader holds L12-L14 (SoN::Verify's V7 record, V6 read-unversioned and V2b effect-floating,
# ABOUTME: ported): a wire the verifier rejects for one of them is refused by name when it is loaded.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use JSON::PP;
use File::Temp qw(tempdir);
use Chalk::IR::Serialize::JSON;

# WHY (fifth final audit, section 3). 17 of its 2576 probes broke a verifier
# rule, and the loader let all but one through: it held L1-L11 and not V6
# (every read of changeable state names a version), V7 (a record binds `my`
# variables only) or V2b (an effect is on the control chain). Ten of them
# printed a wrong answer (vf217, vq111-vq116 `substr($t,0,1)` of a package
# `$t` read before a call stores it; vo41-vo43 a record of package targets).
# Ported into the loader (Chalk::IR::Serialize::WireReads); this holds the
# port to the verifier's answer, wire by wire. (Over every probe and every
# chalk module the two agree too: t/bootstrap/ir/wire-verify.t.)
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
    my $w = qx($^X -I$SON -MO=-q,SoN,json $f 2>/dev/null);
    die "B::SoN wrote no wire for: $src\n" unless $w =~ /\S/;
    return $w;
}
sub refused ($json) { return eval { Chalk::IR::Serialize::JSON::from_json($json); 1 } ? '' : $@ }
sub rules ($json) { my %r = map { ( $_->{rule} =~ s/:.*//r => 1 ) } SoN::Verify::verify( decode_json($json) )->{violations}->@*; return join ' ', sort keys %r }

# (the audit's v/unverified probes, by the rule the verifier names; vk59's
# alias rule is L11's, loader-refuses-an-alias-that-is-not-private.t)
my %L = ( 'read-unversioned' => 'L13', record => 'L12', 'effect-floating' => 'L14' );
for my $case (
    [ 'record',           'our ($x, $y) = (1, 2); my ($p, $q) = ($x, $y) = ($y, $x); print "$x$y$p$q\n";' ],                 # vd84
    [ 'record',           'our ($x, $y); my @l = ((($x, $y) = (7,8)), $x = 9); print "@l\n";' ],                               # vo41
    [ 'record',           'our ($x, $y); sub z { $x = 9; 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n";' ],              # vo42
    [ 'record',           'our ($x, $y); sub z { local $x = 9; 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n";' ],        # vo43
    [ 'read-unversioned', 'my $x = "ab"; sub f { substr($_[0], 0, 1, "z"); $_[0] } print f($x), "$x\n";' ],                    # ve46
    [ 'read-unversioned', 'our $t = "a"; sub c { $t = "zz"; 2 } sub id { "@_" } print id(substr($t, 0, 1), c()), "\n";' ],     # vf217
    [ 'read-unversioned', 'our $s = "abc"; sub ed { substr($s, 0, 1) = "z"; 1 } my @l = ($s, ed(), $s); print "@l\n";' ],     # vi161
    [ 'read-unversioned', 'our $t = "a"; sub c { $t = "zz"; 2 } sub id { "@_" } print id(substr($t, 0), c()), "\n";' ],        # vq112
    [ 'read-unversioned', 'our $t = "a"; sub c { $t = "zz"; 2 } sub id { join ",", @_ } print id(substr($t, 0, 1), c()), "\n";' ],  # vq116
    [ 'read-unversioned', 'our $t = "a"; sub id { "@_" } print id(substr($t, 0, 1), $t = "zz"), "\n";' ],                      # vq117
    [ 'read-unversioned', 'my @t = ("abc"); sub c { $t[0] = "zzz"; 2 } sub id { "@_" } print id(substr($t[0], 0, 1), c()), "\n";' ],  # vq130
    [ 'effect-floating',  'my $t = "abc"; sub id { "@_" } print id(pos($t), $t = "z"), "\n";' ],                               # vq139
) {
    my ( $rule, $src ) = @$case;
    my $w = wire($src);
    is( rules($w), $rule, "the verifier names $rule: $src" );
    like( refused($w), qr/\AGAP: wire invariant $L{$rule}: /, "...and the loader refuses it by $L{$rule}" );
}

# (clean: the verifier names nothing, and each loads -- a record of `my`
# scalars, @_ bound to `my` aggregates, a package scalar read at its version,
# a substr of a `my` scalar, pos where it stands, a store through @_)
for my $src (
    'my ($x, $y) = (1, 2); ($x, $y) = ($y, $x); print "$x$y\n";',
    'sub f { my ($a, @r) = @_; "$a@r" } print f(1, 2, 3), "\n";',
    'our $t = "a"; sub c { $t = "zz"; 2 } my $s = substr($t, 0, 1); print $s, c(), "\n";',
    'my $t = "abc"; sub c { 2 } print substr($t, 0, 1), c(), "\n";',
    'my $t = "abc"; $t =~ /b/g; print pos($t), "\n";',
    'sub f { $_[0] = 5 } my $x = 1; f($x); print "$x\n";',
    'our @a = (1, 2); push @a, 3; print "@a\n";',
) {
    my $w = wire($src);
    is( rules($w), '', "the verifier is clean: $src" );
    unlike( refused($w), qr/wire invariant L1[234]/, '...and L12-L14 let it through' );
}

done_testing;
