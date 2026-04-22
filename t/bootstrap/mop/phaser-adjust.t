# ABOUTME: Tests for Chalk::MOP::Phaser and Chalk::MOP::Phaser::Adjust metaobjects.
# ABOUTME: Verifies construction, accessors, source_position tracking, and class backref.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Basic ADJUST construction via declare_adjust
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Validated');
    my $adjust = $cls->declare_adjust();

    isa_ok($adjust, 'Chalk::MOP::Phaser::Adjust');
    isa_ok($adjust, 'Chalk::MOP::Phaser');
    is(refaddr($adjust->class), refaddr($cls), 'adjust class points back');
}

# source_position tracks declaration order
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('MultiAdjust');
    my $a0 = $cls->declare_adjust();
    my $a1 = $cls->declare_adjust();
    my $a2 = $cls->declare_adjust();

    is($a0->source_position, 0, 'first adjust at position 0');
    is($a1->source_position, 1, 'second adjust at position 1');
    is($a2->source_position, 2, 'third adjust at position 2');
}

# graph defaults to a fresh Chalk::IR::Graph instance
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Stub');
    my $adjust = $cls->declare_adjust();

    isa_ok($adjust->graph, 'Chalk::IR::Graph', 'graph is a Chalk::IR::Graph');
}

# adjust_blocks enumeration
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('ThreeAdjust');
    $cls->declare_adjust();
    $cls->declare_adjust();
    $cls->declare_adjust();

    my @blocks = $cls->adjust_blocks;
    is(scalar @blocks, 3, 'three adjust blocks declared');
    for my $i (0..2) {
        is($blocks[$i]->source_position, $i, "block $i at correct position");
    }
}

done_testing();
