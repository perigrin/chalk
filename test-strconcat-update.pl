#!/usr/bin/env perl
# Test that StrConcat node works without Builder dependency
use 5.42.0;
use lib 'lib';
use Test::More;

# Test Phase 1: StrConcat IR Node
{
    use Chalk::IR::Node::StrConcat;
    use Chalk::IR::Node::Constant;

    # Create simple constant nodes
    my $left = Chalk::IR::Node::Constant->new(
        value => "hello",
        type => "String"
    );

    my $right = Chalk::IR::Node::Constant->new(
        value => " world",
        type => "String"
    );

    # Create StrConcat node with direct node references (v2 style)
    my $concat = Chalk::IR::Node::StrConcat->new(
        left => $left,
        right => $right
    );

    ok($concat, 'StrConcat node created');
    is($concat->op, 'StrConcat', 'StrConcat has correct op');
    like($concat->id, qr/^concat_/, 'StrConcat ID has concat_ prefix');
    like($concat->id, qr/const_String_hello/, 'StrConcat ID includes left operand');
    like($concat->id, qr/const_String_ world/, 'StrConcat ID includes right operand');

    my $inputs = $concat->inputs;
    ok($inputs, 'StrConcat has inputs');
    is(scalar(@$inputs), 2, 'StrConcat has 2 inputs');

    my $hash = $concat->to_hash;
    ok($hash, 'StrConcat can convert to hash');
    is($hash->{op}, 'StrConcat', 'Hash has correct op');
    ok($hash->{attributes}, 'Hash has attributes');
    ok($hash->{attributes}{left_id}, 'Attributes have left_id');
    ok($hash->{attributes}{right_id}, 'Attributes have right_id');
}

# Test Phase 2: ConcatenationOp Rule (syntax check)
{
    use Chalk::Grammar;
    use Chalk::Grammar::Chalk::Rule::ConcatenationOp;

    ok(Chalk::Grammar::Chalk::Rule::ConcatenationOp->can('evaluate'), 'ConcatenationOp has evaluate method');
}

done_testing();
