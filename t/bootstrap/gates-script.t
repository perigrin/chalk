# ABOUTME: tools/gates.sh runs every gate of the wire v2 plan from this checkout;
# ABOUTME: this holds its list of gates, and that it refuses by name without B::SoN.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

ok( -x 'tools/gates.sh', 'tools/gates.sh is there and runs' );

# WITHOUT B::SoN IT SAYS SO: the gates are B::SoN's script, run on this tree.
{
    local $ENV{PERL5_SON_LIB} = '/nonexistent/lib';
    my $out = qx(tools/gates.sh --list 2>&1);
    isnt( $?, 0, 'no B::SoN: a non-zero exit' );
    like( $out, qr/^GAP: B::SoN's tools\/gates\.sh is not beside/, 'and the reason, by name' );
}

SKIP: {
    skip "perl5-son's tools/gates.sh not found beside $SON (set PERL5_SON_LIB)", 2
        unless -x "$SON/../tools/gates.sh";
    my @listed = map { ( split ' ' )[0] } split /\n/, qx(tools/gates.sh --list 2>&1);
    is( $?, 0, '--list exits 0' );
    is_deeply(
        [ sort @listed ],
        [ sort qw(producer-suite chalk-suite census corpus-gate probes ratchet) ],
        '--list names each gate of the plan, and no other'
    );
}

done_testing;
