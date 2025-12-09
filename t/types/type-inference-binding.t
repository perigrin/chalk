# ABOUTME: Tests for type binding establishment in TypeInference semiring
# ABOUTME: Validates on_complete extracts variable names and establishes type bindings

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use Chalk::Semiring::TypeInference;
use Chalk::Grammar::Chalk::TypeLattice;
use Chalk::Grammar::Token;
use Chalk::Parser;
use Chalk::Grammar;

subtest 'TypeInferenceElement has required fields' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int_type = $lattice->type_from_name('Int');

    my $elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $int_type,
        type_env => {},
        children => [],
        token => undef
    );

    ok(defined($elem), 'Element created with all fields');
    ok(defined($elem->type_env), 'Element has type_env field');
    is(ref($elem->type_env), 'HASH', 'type_env is a hash');
    ok(defined($elem->children), 'Element has children field');
    is(ref($elem->children), 'ARRAY', 'children is an array');
    ok(!defined($elem->token), 'Element has token field (undef)');
};

subtest 'multiply appends child elements' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int_type = $lattice->type_from_name('Int');
    my $any_type = $lattice->type_from_name('Any');

    my $elem1 = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $any_type,
        type_env => {},
        children => [],
        token => undef
    );

    my $elem2 = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $int_type,
        type_env => {},
        children => [],
        token => undef
    );

    my $result = $elem1->multiply($elem2);

    ok(defined($result), 'multiply returns result');
    is(scalar($result->children->@*), 1, 'Result has one child');
    is($result->children->[0], $elem2, 'Child is the multiplied element');
};

subtest 'on_scan stores token in element' => sub {
    my $semiring = Chalk::Semiring::TypeInference->new();
    my $token = Chalk::Grammar::Token::Int->new(
        value => '42',
        pattern_name => 'INTEGER'
    );

    my $item = undef; # Mock item - not used in current on_scan
    my $element = $semiring->one(); # Start with top type

    my $result = $semiring->on_scan($item, $element, 0, $token, 'INTEGER');

    ok(defined($result), 'on_scan returns result');
    is(scalar($result->children->@*), 1, 'Result has one child (the terminal)');
    ok(defined($result->children->[0]->token), 'Child element has token stored');
    isa_ok($result->children->[0]->token, 'Chalk::Grammar::Token::Int', 'Token is Int type');
    is($result->children->[0]->token->value, '42', 'Token value preserved');
};

subtest 'Basic type binding: my $x = 0' => sub {
    plan skip_all => 'Test will pass once on_complete is implemented';

    my $code = q{my $x = 0;};
    my $grammar = Chalk::Grammar->new();
    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $type_sr
    );

    my $element = $parser->parse_string($code);

    ok(defined($element), 'Parse succeeded');
    ok(defined($element->type_env), 'Element has type_env');
    ok(exists($element->type_env->{'$x'}), '$x binding exists in type_env');
    isa_ok($element->type_env->{'$x'}, 'Chalk::Grammar::Chalk::Type::Int',
           '$x bound to Int type');
};

subtest 'Type environment propagates upward' => sub {
    plan skip_all => 'Test will pass once on_complete is implemented';

    my $code = q{my $x = 0; my $y = 1;};
    my $grammar = Chalk::Grammar->new();
    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $type_sr
    );

    my $element = $parser->parse_string($code);

    ok(defined($element->type_env), 'Element has type_env');
    ok(exists($element->type_env->{'$x'}), '$x binding exists');
    ok(exists($element->type_env->{'$y'}), '$y binding exists');
    isa_ok($element->type_env->{'$x'}, 'Chalk::Grammar::Chalk::Type::Int',
           '$x bound to Int');
    isa_ok($element->type_env->{'$y'}, 'Chalk::Grammar::Chalk::Type::Int',
           '$y bound to Int');
};

subtest 'Different types in bindings' => sub {
    plan skip_all => 'Test will pass once on_complete is implemented';

    my $code = q{my $x = 0; my $y = 1.5;};
    my $grammar = Chalk::Grammar->new();
    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $type_sr
    );

    my $element = $parser->parse_string($code);

    ok(defined($element->type_env), 'Element has type_env');
    isa_ok($element->type_env->{'$x'}, 'Chalk::Grammar::Chalk::Type::Int',
           '$x bound to Int');
    isa_ok($element->type_env->{'$y'}, 'Chalk::Grammar::Chalk::Type::Num',
           '$y bound to Num');
};

done_testing();
