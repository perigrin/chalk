# ABOUTME: Layer 2 of the return type -- the loader carries the producer's
# ABOUTME: declaration onto MOP::Sub and may only NARROW it, never weaken it.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

skip_all "perl5-son not found" unless -f "$SON/B/SoN.pm";
skip_all "perl 5.42 not found" unless -x $PERL;

use lib 'lib', 't/lib';
require Chalk::IR::Serialize::JSON;

# The producer DECLARES (layer 1, perl5-son t/sub-return-type.t). The loader
# CARRIES that declaration onto the metaobject, and may replace `Unknown` with
# something narrower once inference runs -- but must NEVER replace a determined
# type with a weaker one.
#
# `Unknown` is the sound top: everything is a subtype of it, so a naive join
# lets it swallow a known type (measured: join(Int,Unknown) = Unknown). That
# weakening is exactly what this layer forbids.
sub sub_meta ( $program, $class, $name ) {
    my ( $fh, $tmp ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $program;
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    my $cls = $mop && $mop->for_class($class) or return undef;
    my ($s) = grep { $_->name eq $name } $cls->subs;
    return $s;
}

subtest 'a determined return type reaches the metaobject' => sub {
    my $s = sub_meta( 'sub f { 42 } print f(), "\n";', 'main', 'f' );
    ok $s, 'sub f has a metaobject' or return;
    is $s->return_type, 'Int', 'the producer-declared Int reached MOP::Sub';
};

subtest 'a Str-returning sub carries Str' => sub {
    my $s = sub_meta( 'sub f { "hi" } print f(), "\n";', 'main', 'f' );
    ok $s, 'recorded' or return;
    is $s->return_type, 'Str', 'declared Str reached MOP::Sub';
};

# The undetermined case must arrive as `Unknown` -- a real lattice point -- and
# NOT as undef. An absent field is not a type; it forces every consumer to
# invent a meaning, which is the defect this whole arc keeps hitting.
subtest 'an undetermined return type arrives as Unknown, not undef' => sub {
    my $s = sub_meta(
        'sub fib { my $n = shift; $n < 2 ? $n : fib($n-1) + fib($n-2) } print fib(10), "\n";',
        'main', 'fib' );
    ok $s, 'sub fib has a metaobject' or return;
    is $s->return_type, 'Unknown',
        'Unknown is carried as a value, not collapsed to undef';
};

done_testing;
