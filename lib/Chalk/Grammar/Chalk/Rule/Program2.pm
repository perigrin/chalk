# ABOUTME: Semantic action for Program (v2 rewrite)
# ABOUTME: Creates Start2/Return2 wrapper around program statements
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Program2 {
    use Chalk::IR::Node::Start2;
    use Chalk::IR::Node::Return2;
    use Chalk::IR::Node::Constant2;
    use Scalar::Util qw(blessed);

    method evaluate($context) {
        # Get scope from environment
        my $scope = $context->env->{scope};
        return undef unless $scope;

        # Create Start node (program entry point)
        my $start = Chalk::IR::Node::Start2->new(label => 'main');
        $scope->set_current_control($start);

        # Find StatementList in children
        # Program -> WS_OPT StatementList WS_OPT
        my @children = $context->children->@*;
        my @statements;

        for my $child_ctx (@children) {
            next unless $child_ctx && $child_ctx->can('focus');
            my $focus = $child_ctx->focus;
            # StatementList returns an arrayref of statements
            if (ref($focus) eq 'ARRAY') {
                @statements = $focus->@*;
                last;
            }
        }

        # Get last statement for return value
        my $last_stmt = @statements ? $statements[-1] : undef;
        my $return_value;
        my $final_control = $scope->current_control;

        if ($last_stmt && blessed($last_stmt) && $last_stmt->can('op')) {
            my $op = $last_stmt->op;

            if ($op eq 'Return') {
                # Last statement is already a Return - use it directly
                return $last_stmt;
            } elsif ($op eq 'Store') {
                # Last statement is a Store - return the stored value
                $return_value = $last_stmt->value;
                $final_control = $last_stmt;
            } else {
                # Other expression - use as return value
                $return_value = $last_stmt;
            }
        }

        # Default return value (undef constant)
        $return_value //= Chalk::IR::Node::Constant2->new(
            type  => 'Undef',
            value => 'undef',
        );

        # Create Return node
        return Chalk::IR::Node::Return2->new(
            control => $final_control,
            value   => $return_value,
        );
    }
}

1;
