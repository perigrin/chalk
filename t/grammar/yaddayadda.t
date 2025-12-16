# ABOUTME: Tests for YaddaYadda semantic action
# ABOUTME: Verifies YaddaYadda generates Die node with "Unimplemented" message

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::YaddaYadda;
use Chalk::IR::Node::Die;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Scope;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Helper to create a mock context for YaddaYadda
sub mock_context {
    # YaddaYadda expects a scope with control in the environment
    my $start = Chalk::IR::Node::Start->new(label => 'test');

    # Create a mock scope object with current_control method
    package MockScope {
        sub new {
            my ($class, %args) = @_;
            bless { control => $args{control} }, $class;
        }
        sub current_control { $_[0]->{control} }
        sub with_binding { $_[0] }  # No-op for testing
    }

    my $scope = MockScope->new(control => $start);

    # Create simple mock for the '...' token
    package MockYaddaToken {
        use overload '""' => sub { '...' };
        sub new { bless { value => '...' }, $_[0] }
        sub extract { $_[0] }
    }

    my $token = MockYaddaToken->new();

    my $token_ctx = Chalk::EvalContext->new(
        focus => $token,
        children => [],
        start_pos => 0,
        end_pos => 3,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );

    return Chalk::EvalContext->new(
        children => [$token_ctx],
        focus => undef,
        start_pos => 0,
        end_pos => 3,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );
}

subtest 'YaddaYadda generates Die node' => sub {
    my $context = mock_context();

    my $yadda = Chalk::Grammar::Chalk::Rule::YaddaYadda->new(
        lhs => 'YaddaYadda',
        rhs => []
    );
    my $result = $yadda->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::Die'),
       'Result is Die node') or diag "Got: " . (ref($result) || "'$result'");
};

subtest 'Die node has Unimplemented message' => sub {
    my $context = mock_context();

    my $yadda = Chalk::Grammar::Chalk::Rule::YaddaYadda->new(
        lhs => 'YaddaYadda',
        rhs => []
    );
    my $result = $yadda->evaluate($context);

    ok($result->isa('Chalk::IR::Node::Die'), 'Result is Die node');

    # Verify message is a Constant with "Unimplemented" value
    my $message = $result->message;
    ok(defined($message), 'Die has message');
    ok(blessed($message), 'Message is blessed');
    ok($message->can('value'), 'Message has value method');
    is($message->value, 'Unimplemented', 'Message value is "Unimplemented"');
};

subtest 'Die node has control from scope' => sub {
    my $context = mock_context();

    my $yadda = Chalk::Grammar::Chalk::Rule::YaddaYadda->new(
        lhs => 'YaddaYadda',
        rhs => []
    );
    my $result = $yadda->evaluate($context);

    ok($result->isa('Chalk::IR::Node::Die'), 'Result is Die node');

    # Verify control is set
    my $control = $result->control;
    ok(defined($control), 'Die has control');
    ok($control->isa('Chalk::IR::Node::Start'), 'Control is Start node');
};

done_testing();
