# ABOUTME: Tests for Chalk::IR::Node::Coerce — the explicit coercion edge mechanism.
# ABOUTME: Verifies from_repr/to_repr are in content_hash and hash-consing works correctly.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Coerce;

# C1: Coerce class exists and is loadable.
ok(defined &Chalk::IR::Node::Coerce::new || Chalk::IR::Node::Coerce->can('new'),
    'Chalk::IR::Node::Coerce is loadable');

# C2: Factory can make a Coerce node.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '42', const_type => 'string');
    my $coerce = $f->make('Coerce',
        from_repr => 'Str',
        to_repr   => 'Num',
        inputs    => [$input],
    );
    isa_ok($coerce, 'Chalk::IR::Node::Coerce',
        'factory make("Coerce") returns a Coerce node');
}

# C3: from_repr and to_repr are readable.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '42', const_type => 'string');
    my $coerce = $f->make('Coerce',
        from_repr => 'Str',
        to_repr   => 'Num',
        inputs    => [$input],
    );
    is($coerce->from_repr(), 'Str', 'from_repr() returns correct value');
    is($coerce->to_repr(),   'Num', 'to_repr() returns correct value');
}

# C4: Coerce input node is accessible.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '42', const_type => 'string');
    my $coerce = $f->make('Coerce',
        from_repr => 'Str',
        to_repr   => 'Num',
        inputs    => [$input],
    );
    is(refaddr($coerce->inputs->[0]), refaddr($input),
        'Coerce input is the correct node');
}

# C5: from_repr/to_repr ARE in content_hash — Coerce[Str->Num](x) and
# Coerce[Str->Int](x) are DIFFERENT nodes.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '42', const_type => 'string');

    my $cn = $f->make('Coerce', from_repr => 'Str', to_repr => 'Num', inputs => [$input]);
    my $ci = $f->make('Coerce', from_repr => 'Str', to_repr => 'Int', inputs => [$input]);

    isnt(refaddr($cn), refaddr($ci),
        'Coerce[Str->Num] and Coerce[Str->Int] are DIFFERENT nodes (from/to in hash)');
}

# C6: Two consumers needing the SAME coercion share ONE hash-consed Coerce node.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '42', const_type => 'string');

    my $c1 = $f->make('Coerce', from_repr => 'Str', to_repr => 'Num', inputs => [$input]);
    my $c2 = $f->make('Coerce', from_repr => 'Str', to_repr => 'Num', inputs => [$input]);

    is(refaddr($c1), refaddr($c2),
        'two calls for the same Coerce[Str->Num](same_input) return the same node');
}

# C7: Different from_repr yields different node.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '3', const_type => 'integer');

    my $c_in = $f->make('Coerce', from_repr => 'Int', to_repr => 'Str', inputs => [$input]);
    my $c_nu = $f->make('Coerce', from_repr => 'Num', to_repr => 'Str', inputs => [$input]);

    isnt(refaddr($c_in), refaddr($c_nu),
        'Coerce[Int->Str] and Coerce[Num->Str] are DIFFERENT nodes');
}

# C8: content_hash contains from_repr and to_repr.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '1', const_type => 'integer');
    my $coerce = $f->make('Coerce',
        from_repr => 'Int',
        to_repr   => 'Num',
        inputs    => [$input],
    );
    my $hash = $coerce->content_hash();
    like($hash, qr/Int/, 'content_hash contains from_repr');
    like($hash, qr/Num/, 'content_hash contains to_repr');
}

# C9: Coerce operation() returns 'Coerce'.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $input = $f->make('Constant', value => '1', const_type => 'integer');
    my $coerce = $f->make('Coerce',
        from_repr => 'Int',
        to_repr   => 'Num',
        inputs    => [$input],
    );
    is($coerce->operation(), 'Coerce', 'operation() returns "Coerce"');
}

done_testing;
