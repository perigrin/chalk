# ABOUTME: Tests for the `representation` field on Chalk::IR::Node.
# ABOUTME: Verifies representation is a per-use decoration excluded from content_hash.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);
use lib 'lib';

use Chalk::IR::NodeFactory;

# D1: Node has a representation() reader.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => '1', const_type => 'integer');
    ok($c->can('representation'),
        'Constant node has representation() reader');
}

# D2: representation defaults to undef.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => '1', const_type => 'integer');
    is($c->representation(), undef,
        'representation defaults to undef');
}

# D3: Node has a set_representation() setter.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => '1', const_type => 'integer');
    ok($c->can('set_representation'),
        'Constant node has set_representation() setter');
}

# D4: set_representation() sets the value readable via representation().
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => '1', const_type => 'integer');
    $c->set_representation('Int');
    is($c->representation(), 'Int',
        'set_representation("Int") is readable back');
}

# D5: representation is EXCLUDED from content_hash — the hash-consing identity contract.
# Two calls to make() with identical content but different representations set POST-
# construction must still return the SAME node (same refaddr). The representation
# is a per-use decoration; it must not fork identity.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '42', const_type => 'integer');
    $c1->set_representation('Int');

    my $c2 = $f->make('Constant', value => '42', const_type => 'integer');
    $c2->set_representation('Scalar');

    is(refaddr($c1), refaddr($c2),
        'same-content nodes with different representation still hash-cons to one object');
}

# D6: content_hash does NOT contain the word "representation".
# Confirming the field is explicitly NOT included in the hash string.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => '7', const_type => 'integer');
    $c->set_representation('Num');
    my $hash = $c->content_hash();
    unlike($hash, qr/representation/,
        'content_hash() does not contain the string "representation"');
}

# D7: representation field works on non-Constant nodes (Add).
{
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => '1', const_type => 'integer');
    my $rhs = $f->make('Constant', value => '2', const_type => 'integer');
    my $add = $f->make('Add', inputs => [$lhs, $rhs]);
    $add->set_representation('Int');
    is($add->representation(), 'Int',
        'Add node also carries representation');
}

done_testing;
