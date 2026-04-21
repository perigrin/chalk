# ABOUTME: Tests for Chalk::MOP::Class resolution methods.
# ABOUTME: Verifies find_method, ancestors, and resolve_adjust_blocks across inheritance chains.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# find_method on direct class
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Widget');
    $cls->declare_method('render');
    $cls->declare_method('update');

    my $found = $cls->find_method('render');
    ok(defined $found, 'find_method finds direct method');
    is($found->name, 'render', 'correct method found');
}

# find_method returns undef for missing method
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Empty');

    my $found = $cls->find_method('nonexistent');
    ok(!defined $found, 'find_method returns undef for missing method');
}

# find_method walks ancestor chain
{
    my $mop = Chalk::MOP->new;
    my $base = $mop->declare_class('Animal');
    $base->declare_method('breathe');

    my $middle = $mop->declare_class('Mammal', superclass => $base);
    $middle->declare_method('nurse');

    my $derived = $mop->declare_class('Dog', superclass => $middle);
    $derived->declare_method('bark');

    # Direct method
    my $bark = $derived->find_method('bark');
    ok(defined $bark, 'finds direct method on derived');
    is($bark->name, 'bark', 'correct direct method');

    # Parent method
    my $nurse = $derived->find_method('nurse');
    ok(defined $nurse, 'finds method on parent');
    is($nurse->name, 'nurse', 'correct parent method');

    # Grandparent method
    my $breathe = $derived->find_method('breathe');
    ok(defined $breathe, 'finds method on grandparent');
    is($breathe->name, 'breathe', 'correct grandparent method');

    # Missing method on full chain
    my $missing = $derived->find_method('fly');
    ok(!defined $missing, 'returns undef when no ancestor has method');
}

# find_method prefers closer ancestor (method override)
{
    my $mop = Chalk::MOP->new;
    my $base = $mop->declare_class('Base');
    $base->declare_method('speak', return_type => 'Str');

    my $derived = $mop->declare_class('Override', superclass => $base);
    $derived->declare_method('speak', return_type => 'Int');

    my $found = $derived->find_method('speak');
    is($found->return_type, 'Int', 'find_method returns derived override, not base');
}

# ancestors() returns empty for class with no superclass
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Root');

    my @ancestors = $cls->ancestors;
    is(scalar @ancestors, 0, 'no ancestors for a root class');
}

# ancestors() returns chain from parent to root
{
    my $mop = Chalk::MOP->new;
    my $a = $mop->declare_class('A');
    my $b = $mop->declare_class('B', superclass => $a);
    my $c = $mop->declare_class('C', superclass => $b);
    my $d = $mop->declare_class('D', superclass => $c);

    my @ancestors = $d->ancestors;
    is(scalar @ancestors, 3, 'D has 3 ancestors');
    is($ancestors[0]->name, 'C', 'first ancestor is immediate parent');
    is($ancestors[1]->name, 'B', 'second ancestor is grandparent');
    is($ancestors[2]->name, 'A', 'third ancestor is root');
}

# resolve_adjust_blocks — single class, source order
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Single');
    $cls->declare_adjust();
    $cls->declare_adjust();

    my @blocks = $cls->resolve_adjust_blocks;
    is(scalar @blocks, 2, 'two adjust blocks');
    is($blocks[0]->source_position, 0, 'first block first');
    is($blocks[1]->source_position, 1, 'second block second');
}

# resolve_adjust_blocks — base-class-first ordering
{
    my $mop = Chalk::MOP->new;

    my $base = $mop->declare_class('Base');
    $base->declare_adjust();

    my $middle = $mop->declare_class('Middle', superclass => $base);
    $middle->declare_adjust();
    $middle->declare_adjust();

    my $derived = $mop->declare_class('Derived', superclass => $middle);
    $derived->declare_adjust();

    my @blocks = $derived->resolve_adjust_blocks;
    is(scalar @blocks, 4, 'all 4 adjust blocks from chain');

    # Base's block first
    is(refaddr($blocks[0]->class), refaddr($base), 'first block from base');

    # Middle's two blocks next
    is(refaddr($blocks[1]->class), refaddr($middle), 'second block from middle');
    is(refaddr($blocks[2]->class), refaddr($middle), 'third block from middle');
    is($blocks[1]->source_position, 0, 'middle blocks in source order (0)');
    is($blocks[2]->source_position, 1, 'middle blocks in source order (1)');

    # Derived's block last
    is(refaddr($blocks[3]->class), refaddr($derived), 'last block from derived');
}

# resolve_adjust_blocks — class with no ancestors and no blocks
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NoAdjust');

    my @blocks = $cls->resolve_adjust_blocks;
    is(scalar @blocks, 0, 'no adjust blocks for class with none');
}

# resolve_adjust_blocks — ancestors have blocks but derived doesn't
{
    my $mop = Chalk::MOP->new;
    my $base = $mop->declare_class('HasAdjust');
    $base->declare_adjust();

    my $derived = $mop->declare_class('NoOwnAdjust', superclass => $base);

    my @blocks = $derived->resolve_adjust_blocks;
    is(scalar @blocks, 1, 'inherits base adjust block');
    is(refaddr($blocks[0]->class), refaddr($base), 'block belongs to base');
}

done_testing();
