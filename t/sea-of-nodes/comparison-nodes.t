# ABOUTME: Tests for polymorphic comparison IR node subclasses
# ABOUTME: Verifies GT, LT, EQ, NE, LE, GE comparison nodes using v2 API
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;
use builtin qw(true false is_bool);

# Test 1-8: Comparison node subclasses should be loadable
use_ok('Chalk::IR::Node::GT');
use_ok('Chalk::IR::Node::LT');
use_ok('Chalk::IR::Node::EQ');
use_ok('Chalk::IR::Node::NE');
use_ok('Chalk::IR::Node::LE');
use_ok('Chalk::IR::Node::GE');
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Type::TypeBool');

# Helper to create constant nodes for testing
sub make_const {
    my ($val) = @_;
    return Chalk::IR::Node::Constant->new(value => $val, type => 'Int');
}

# Test 9: GT node should implement op() method
{
    my $left = make_const(1);
    my $right = make_const(2);
    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);
    is($gt->op, 'GT', 'GT node returns correct op');
}

# Test 9-10: GT node should have left and right accessors
{
    my $left = make_const(5);
    my $right = make_const(6);
    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);
    is($gt->left->id, $left->id, 'GT node has left accessor');
    is($gt->right->id, $right->id, 'GT node has right accessor');
}

# Test 11: LT node should implement op() method
{
    my $left = make_const(7);
    my $right = make_const(8);
    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);
    is($lt->op, 'LT', 'LT node returns correct op');
}

# Test 12: EQ node should implement op() method
{
    my $left = make_const(9);
    my $right = make_const(10);
    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);
    is($eq->op, 'EQ', 'EQ node returns correct op');
}

# Test 13: NE node should implement op() method
{
    my $left = make_const(11);
    my $right = make_const(12);
    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);
    is($ne->op, 'NE', 'NE node returns correct op');
}

# Test 14: LE node should implement op() method
{
    my $left = make_const(13);
    my $right = make_const(14);
    my $le = Chalk::IR::Node::LE->new(left => $left, right => $right);
    is($le->op, 'LE', 'LE node returns correct op');
}

# Test 15: GE node should implement op() method
{
    my $left = make_const(15);
    my $right = make_const(16);
    my $ge = Chalk::IR::Node::GE->new(left => $left, right => $right);
    is($ge->op, 'GE', 'GE node returns correct op');
}

# Test 16: Polymorphism - calling op() on different comparison nodes
{
    my $c1 = make_const(1);
    my $c2 = make_const(2);
    my $c3 = make_const(3);
    my $c4 = make_const(4);
    my $c5 = make_const(5);
    my $c6 = make_const(6);
    my $c7 = make_const(7);
    my $c8 = make_const(8);
    my $c9 = make_const(9);
    my $c10 = make_const(10);
    my $c11 = make_const(11);
    my $c12 = make_const(12);
    my @nodes = (
        Chalk::IR::Node::GT->new(left => $c1, right => $c2),
        Chalk::IR::Node::LT->new(left => $c3, right => $c4),
        Chalk::IR::Node::EQ->new(left => $c5, right => $c6),
        Chalk::IR::Node::NE->new(left => $c7, right => $c8),
        Chalk::IR::Node::LE->new(left => $c9, right => $c10),
        Chalk::IR::Node::GE->new(left => $c11, right => $c12),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['GT', 'LT', 'EQ', 'NE', 'LE', 'GE'],
              'Polymorphic op() calls work for comparison nodes');
}

# Test 17-18: to_hash() should include attributes for GT
{
    my $left = make_const(10);
    my $right = make_const(20);
    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);
    my $hash = $gt->to_hash();
    is($hash->{attributes}{left_id}, $left->id, 'GT to_hash() includes left_id');
    is($hash->{attributes}{right_id}, $right->id, 'GT to_hash() includes right_id');
}

# Test 19: Numeric IDs work correctly
{
    my $left = make_const(50);
    my $right = make_const(60);
    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);
    like($eq->id, qr/^\d+$/, 'EQ has numeric id (refaddr)');
}

# Test 20: Numeric IDs work for NE
{
    my $left = make_const(70);
    my $right = make_const(80);
    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);
    like($ne->id, qr/^\d+$/, 'NE has numeric id (refaddr)');
}

# Native bool tests for GT
subtest 'GT execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 10,
        "node:" . $right->id => 5,
    );

    my $result = $gt->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'GT execute() returns native bool');
    ok($result, 'GT 10 > 5 is true');
};

subtest 'GT execute() returns native false' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 3,
        "node:" . $right->id => 5,
    );

    my $result = $gt->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'GT execute() returns native bool');
    ok(!$result, 'GT 3 > 5 is false');
};

subtest 'GT compute() returns TypeBool for constant inputs' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my $type = $gt->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'GT compute() returns TypeBool');
    ok($type->is_constant, 'GT result is constant when inputs constant');
    ok($type->value, 'GT 10 > 5 compute() is true');
};

subtest 'GT peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my $result = $gt->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'GT peephole() returns Constant');
    is($result->type, 'Bool', 'GT peephole() returns Bool type');
    ok(is_bool($result->value), 'GT peephole() value is native bool');
    ok($result->value, 'GT peephole() 10 > 5 is true');
};

# LT native bool tests
subtest 'LT execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 3,
        "node:" . $right->id => 5,
    );

    my $result = $lt->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'LT execute() returns native bool');
    ok($result, 'LT 3 < 5 is true');
};

subtest 'LT compute() returns TypeBool for constant inputs' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);

    my $type = $lt->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'LT compute() returns TypeBool');
    ok($type->value, 'LT 3 < 5 compute() is true');
};

subtest 'LT peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);

    my $result = $lt->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'LT peephole() returns Constant');
    is($result->type, 'Bool', 'LT peephole() returns Bool type');
    ok($result->value, 'LT peephole() 3 < 5 is true');
};

# EQ tests
subtest 'EQ execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 5,
    );

    my $result = $eq->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'EQ execute() returns native bool');
    ok($result, 'EQ 5 == 5 is true');
};

subtest 'EQ compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);

    my $type = $eq->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'EQ compute() returns TypeBool');
    ok($type->value, 'EQ 5 == 5 compute() is true');
};

subtest 'EQ peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);

    my $result = $eq->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'EQ peephole() returns Constant');
    is($result->type, 'Bool', 'EQ peephole() returns Bool type');
    ok($result->value, 'EQ peephole() 5 == 5 is true');
};

# NE tests
subtest 'NE execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 3,
    );

    my $result = $ne->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'NE execute() returns native bool');
    ok($result, 'NE 5 != 3 is true');
};

subtest 'NE compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);

    my $type = $ne->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'NE compute() returns TypeBool');
    ok($type->value, 'NE 5 != 3 compute() is true');
};

subtest 'NE peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);

    my $result = $ne->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'NE peephole() returns Constant');
    is($result->type, 'Bool', 'NE peephole() returns Bool type');
    ok($result->value, 'NE peephole() 5 != 3 is true');
};

# LE tests
subtest 'LE execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $le = Chalk::IR::Node::LE->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 5,
    );

    my $result = $le->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'LE execute() returns native bool');
    ok($result, 'LE 5 <= 5 is true');
};

subtest 'LE compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $le = Chalk::IR::Node::LE->new(left => $left, right => $right);

    my $type = $le->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'LE compute() returns TypeBool');
    ok($type->value, 'LE 5 <= 5 compute() is true');
};

subtest 'LE peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $le = Chalk::IR::Node::LE->new(left => $left, right => $right);

    my $result = $le->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'LE peephole() returns Constant');
    is($result->type, 'Bool', 'LE peephole() returns Bool type');
    ok($result->value, 'LE peephole() 5 <= 5 is true');
};

# GE tests
subtest 'GE execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $ge = Chalk::IR::Node::GE->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 5,
    );

    my $result = $ge->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'GE execute() returns native bool');
    ok($result, 'GE 5 >= 5 is true');
};

subtest 'GE compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $ge = Chalk::IR::Node::GE->new(left => $left, right => $right);

    my $type = $ge->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'GE compute() returns TypeBool');
    ok($type->value, 'GE 5 >= 5 compute() is true');
};

subtest 'GE peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $ge = Chalk::IR::Node::GE->new(left => $left, right => $right);

    my $result = $ge->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'GE peephole() returns Constant');
    is($result->type, 'Bool', 'GE peephole() returns Bool type');
    ok($result->value, 'GE peephole() 5 >= 5 is true');
};

done_testing();
