# ABOUTME: Tests for constructor invocation detection in MethodCall
# ABOUTME: Verifies ClassName->new() generates Constructor IR node
use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use File::Spec;

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Loads Chalk::GrammarRule
use Chalk::EvalContext;
use Chalk::Grammar::Chalk::Type::Class;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::Grammar::Chalk::Rule::MethodCall;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Constructor;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::CallEnd;

# Test 1: MethodCall returns Constructor when class is registered and method is 'new'
{
    Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

    # Register a class in the TypeRegistry
    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => { '$x' => undef, '$y' => undef },
        param_fields => [
            { name => '$x', required => 1 },
            { name => '$y', required => 0 },
        ],
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Point', $class_type);

    # Create mock child nodes
    my $receiver_node = Chalk::IR::Node::Constant->new(
        value => 'Point',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    my $method_node = Chalk::IR::Node::Constant->new(
        value => 'new',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    my $key_node = Chalk::IR::Node::Constant->new(
        value => 'x',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    my $value_node = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );

    # Create mock child contexts
    my $arrow_ctx = bless { val => '->' }, 'MockContext';
    my $open_ctx = bless { val => '(' }, 'MockContext';
    my $close_ctx = bless { val => ')' }, 'MockContext';

    # Mock context methods
    no strict 'refs';
    *MockContext::focus = sub { shift->{val} };
    *MockContext::can = sub {
        my ($self, $method) = @_;
        return 0 if $method eq 'id';  # MockContext doesn't have id
        return 1;
    };
    *MockContext::extract = sub { shift->{val} };

    # Create the MethodCall context
    my $rule = Chalk::Grammar::Chalk::Rule::MethodCall->new(
        lhs => 'MethodCall',
        rhs => ['Variable', "'->'", 'Identifier', "'('", 'ExpressionList', "')'"],
    );

    my $context = Chalk::EvalContext->new(
        focus => undef,
        children => [$receiver_node, $arrow_ctx, $method_node, $open_ctx, $key_node, $value_node, $close_ctx],
        start_pos => 0,
        end_pos => 100,
        env => {},
        grammar => undef,
        rule => $rule,
    );

    # Override child() to return our nodes directly
    no warnings 'redefine';
    my $orig_child = \&Chalk::EvalContext::child;
    local *Chalk::EvalContext::child = sub {
        my ($self, $i) = @_;
        my @c = @{$self->children};
        return $c[$i];
    };

    my $result = $rule->evaluate($context);

    ok(blessed($result), 'MethodCall returns blessed object');
    isa_ok($result, 'Chalk::IR::Node::Constructor', 'Returns Constructor for registered class');

    if ($result isa Chalk::IR::Node::Constructor) {
        is($result->class_name, 'Point', 'Constructor class_name is correct');
    }
}

# Test 2: MethodCall returns CallEnd when class is NOT registered
{
    Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();
    # Don't register any class

    my $receiver_node = Chalk::IR::Node::Constant->new(
        value => 'Unknown',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    my $method_node = Chalk::IR::Node::Constant->new(
        value => 'new',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );

    my $arrow_ctx = bless { val => '->' }, 'MockContext';
    my $open_ctx = bless { val => '(' }, 'MockContext';
    my $close_ctx = bless { val => ')' }, 'MockContext';

    my $rule = Chalk::Grammar::Chalk::Rule::MethodCall->new(
        lhs => 'MethodCall',
        rhs => ['Variable', "'->'", 'Identifier', "'('", "')'"],
    );

    my $context = Chalk::EvalContext->new(
        focus => undef,
        children => [$receiver_node, $arrow_ctx, $method_node, $open_ctx, $close_ctx],
        start_pos => 0,
        end_pos => 100,
        env => {},
        grammar => undef,
        rule => $rule,
    );

    no warnings 'redefine';
    local *Chalk::EvalContext::child = sub {
        my ($self, $i) = @_;
        my @c = @{$self->children};
        return $c[$i];
    };

    my $result = $rule->evaluate($context);

    ok(blessed($result), 'MethodCall returns blessed object');
    ok(!($result isa Chalk::IR::Node::Constructor), 'Unregistered class does not return Constructor');
}

# Test 3: MethodCall returns CallEnd when method is NOT 'new'
{
    Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

    # Register the class
    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Foo',
        fields => { '$x' => undef },
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Foo', $class_type);

    my $receiver_node = Chalk::IR::Node::Constant->new(
        value => 'Foo',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    my $method_node = Chalk::IR::Node::Constant->new(
        value => 'some_method',  # Not 'new'
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );

    my $arrow_ctx = bless { val => '->' }, 'MockContext';
    my $open_ctx = bless { val => '(' }, 'MockContext';
    my $close_ctx = bless { val => ')' }, 'MockContext';

    my $rule = Chalk::Grammar::Chalk::Rule::MethodCall->new(
        lhs => 'MethodCall',
        rhs => ['Variable', "'->'", 'Identifier', "'('", "')'"],
    );

    my $context = Chalk::EvalContext->new(
        focus => undef,
        children => [$receiver_node, $arrow_ctx, $method_node, $open_ctx, $close_ctx],
        start_pos => 0,
        end_pos => 100,
        env => {},
        grammar => undef,
        rule => $rule,
    );

    no warnings 'redefine';
    local *Chalk::EvalContext::child = sub {
        my ($self, $i) = @_;
        my @c = @{$self->children};
        return $c[$i];
    };

    my $result = $rule->evaluate($context);

    ok(blessed($result), 'MethodCall returns blessed object');
    ok(!($result isa Chalk::IR::Node::Constructor), 'Non-new method does not return Constructor');
}

done_testing();
