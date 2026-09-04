# ABOUTME: An ArrayLiteral the producer stamps `List` must load as an Array, not as nothing.
# ABOUTME: The rescue existed for builtin Calls only, so grep/map's source list arrived untyped.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::Serialize::JSON;

# `%LOWERABLE_STAMP` deliberately drops `List`: it is a real TYPE and an
# invalid REPRESENTATION -- arity-polymorphic, refused by name in
# %_REPR_NO_MACHINE_TYPE -- and what enters the representation field must be an
# encoding.
#
# A rescue already existed for one shape: a BUILTIN CALL stamped `List` is
# re-stamped `Array`, because "the encoding of a materialised list of scalars
# is %Array*". That reasoning is about the VALUE, not about which op produced
# it -- and an `ArrayLiteral` stamped `List` is the same value by the same
# argument.
#
# It was not covered, and grep/map is where it showed. Measured on the wire for
# `my @g = grep { $_ > 1 } (3,1,2)`:
#
#     #13 ArrayLiteral  stamp=List      <- the SOURCE list
#     #23 ListAppend    stamp=Array     <- the accumulator
#
# The accumulator was fine; the source list arrived with NO representation, and
# the backend refused at `Length.operand ... with NO representation (undef)` --
# a message that names TypeInference, sending a reader to the wrong layer
# entirely. Nothing had failed to infer: the answer was on the wire and the
# loader dropped it.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

sub load ($src) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} $src;
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    return $graphs->{'main::__PROGRAM__'};
}

sub nodes_of ($g, $op) {
    return grep { $_->operation eq $op } $g->nodes->@*;
}

subtest 'the producer really does stamp the source list List' => sub {
    # Measured on the WIRE, before the loader touches it -- otherwise this
    # file would be asserting the loader's behaviour against itself.
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} "my \@g = grep { \$_ > 1 } (3,1,2); say(scalar(\@g));\n";
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    plan skip_all => 'producer emitted no JSON' unless $json =~ /\S/;

    like $json, qr/"stamp"\s*:\s*"List"/,
        'the wire carries a List stamp somewhere in this graph'
        or diag('  if the producer stopped emitting List here, this test is '
              . 'measuring nothing');
};

subtest 'a List-stamped ArrayLiteral loads with a representation' => sub {
    my $g = load("my \@g = grep { \$_ > 1 } (3,1,2); say(scalar(\@g));\n")
        or plan skip_all => 'no graph';

    my @lits = nodes_of($g, 'ArrayLiteral');
    cmp_ok scalar @lits, '>=', 1, 'the graph has an ArrayLiteral' or return;

    my @untyped = grep { !defined $_->stamp } @lits;
    is_deeply [ map { $_->operation } @untyped ], [],
        'no ArrayLiteral arrives with NO representation'
        or diag("  an untyped source list makes the backend refuse at\n"
              . "  `Length.operand ... NO representation`, which names\n"
              . "  TypeInference for a value the WIRE had already typed");
};

subtest 'map is the same shape and must not be fixed separately' => sub {
    my $g = load("my \@m = map { \$_ * 2 } (1,2,3); say(scalar(\@m));\n")
        or plan skip_all => 'no graph';

    my @untyped = grep { !defined $_->stamp } nodes_of($g, 'ArrayLiteral');
    is_deeply [ map { $_->operation } @untyped ], [],
        'map, reached through the other block-taking builtin, is covered too';
};

# THE RESCUE MUST NOT OVER-REACH. `List` is dropped on purpose for values that
# genuinely have no single encoding; re-stamping every one of them `Array`
# would be the guess the drop exists to prevent. This pins that the plain
# array literal -- already stamped `Array` by the producer -- is untouched.
subtest 'an already-typed literal keeps the type it had' => sub {
    my $g = load("my \@a = (1,2,3); say(\$a[0]);\n") or plan skip_all => 'no graph';

    my ($lit) = nodes_of($g, 'ArrayLiteral');
    ok $lit, 'found the array literal' or return;
    is $lit->stamp, 'Array',
        'a producer-stamped Array is still Array, not overwritten';
};

done_testing;
