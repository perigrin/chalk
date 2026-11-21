# ABOUTME: SON_WIRE in the environment is the wire version chalk's harnesses ask B::SoN for
# ABOUTME: (the audit probes, the corpus gate): wire v2 stage 5 runs the gates on wire 2.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Harness::Producer;
require Chalk::CodeGen::Harness::AuditProbe;

{
    local $ENV{SON_WIRE};
    is( Chalk::CodeGen::Harness::Producer->wire_option, '', 'no SON_WIRE: no wire option (B::SoN\'s default)' );
    local $ENV{SON_WIRE} = 2;
    is( Chalk::CodeGen::Harness::Producer->wire_option, ',wire=2', 'SON_WIRE=2: wire=2' );
}

# A wire B::SoN does not write is its refusal by name: the probe harness asked for it.
my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh qq{print "x\\n";\n};
close $fh;
{
    local $ENV{SON_WIRE} = 7;
    my $res = Chalk::CodeGen::Harness::AuditProbe::run_probe($pl);
    is( $res->[0], 'REFUSED', 'the probe harness: SON_WIRE=7 is refused' );
    like( $res->[1], qr/wire=7/, '...by B::SoN, naming the wire it was asked for' );
}
{
    local $ENV{SON_WIRE} = 2;
    is( Chalk::CodeGen::Harness::AuditProbe::run_probe($pl)->[0], 'SAME', 'the probe harness: SON_WIRE=2 runs' );
}
like( do { local ( @ARGV, $/ ) = 't/bootstrap/corpus/son-corpus-wide.t'; <> },
    qr/Producer->wire_option/, 'the corpus gate asks for the wire the same way' );
done_testing;
