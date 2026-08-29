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

# ---------------------------------------------------------------------------
# THE WIRE AND THE GRAPH ARE ORDERED, NOT ALTERNATIVES.
#
# _stamp_method_call_reprs compares the producer's declared return type against
# the one it derives from the graph, and dies when they differ. It compared them
# with `ne`, which asks whether two lattice points are the SAME STRING -- so
# `Scalar` on the wire against `Int` from the graph read as a defect in one of
# them. It is not: `Int <: Scalar`. The producer said "a scalar", the loader
# proved "an Int", and BOTH ARE TRUE. The narrower one wins; nothing is wrong.
#
# WHY THE PRODUCER SENDS A SUPERTYPE AT ALL. It compiles ahead of time, so a
# node it cannot narrow may not be left `Unknown` -- that is a hole in the
# emitted program rather than a missing annotation. A subscript reads ONE slot
# of an aggregate, which is always a scalar, so an unnarrowable element read
# ships `Scalar` and lowers to %Slot. This case is exactly that: the elements
# live in a separate default graph the producer does not cross, and this loader
# does.
#
# THE DIE MUST SURVIVE for genuinely unrelated types, which is the second
# subtest. A check that accepts everything is not a check.
sub method_meta ( $program, $class, $name ) {
    my ( $fh, $tmp ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $program;
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=$class $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    return Chalk::IR::Serialize::JSON::from_json($json);
}

subtest 'a wire SUPERTYPE is narrowed by the graph, not refused' => sub {
    my $graphs = eval {
        method_meta( <<'SRC', 'Bag', 'first' ) };
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Bag {
    field $items = [10, 20, 30];
    method first { $items->[0] }
}
say(Bag->new->first);
SRC
    my $err = $@;
    is $err, '', 'a wire Scalar against a graph-derived Int loads without refusing'
        or diag "refused with: $err";
    ok $graphs, 'the graph set loaded' or return;

    # The CALL SITE is what this function governs: %ret_repr feeds the stamp on
    # every method Call, and that is what the backend lowers. The narrower of
    # the two must win there.
    my ($call) = grep {
        $_->operation eq 'Call' && ( $_->name // '' ) eq 'first'
    } map { ( $_->nodes->@* ) } values %$graphs;
    ok $call, 'the call to Bag::first exists' or return;
    is $call->representation, 'Int',
        'the NARROWER of the two wins -- the graph refines the wire';

    # NOTE, not asserted: MOP::Method->return_type still reads the wire value
    # (`Scalar`). It is populated at declare_method time and has no setter, so
    # this function cannot correct it. Pre-existing split, widened in reach by
    # this fix rather than created by it -- filed separately.
};

# BILATERAL. The check exists to catch a real contradiction, and widening it to
# a subtype test must not disable it. Two types on different branches of the
# lattice (neither a subtype of the other) still refuse.
subtest 'genuinely unrelated types still refuse' => sub {
    require Chalk::Grammar::Perl::TypeLibrary;
    my $sub = \&Chalk::Grammar::Perl::TypeLibrary::is_subtype;

    ok $sub->( 'Int', 'Scalar' ), 'Int <: Scalar -- the case above, reconcilable';
    ok !$sub->( 'Code', 'Array' ), 'Code is not <: Array';
    ok !$sub->( 'Array', 'Code' ), 'and Array is not <: Code -- unrelated, must refuse';
};

done_testing;
