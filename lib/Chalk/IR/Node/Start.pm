# ABOUTME: Start node representing function entry point in the IR graph
# ABOUTME: MultiNode that returns (ctrl, arg) tuple for Chapter 4 compliance
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Start :isa(Chalk::IR::Node::CFGNode) {
    use Chalk::IR::Node::CFGNode;
    use Chalk::IR::Type::Tuple;
    use Chalk::IR::Type::Ctrl;
    use Chalk::IR::Type::Integer;
    use Chalk::IR::Type::Top;

    field $function_name :param :reader = undef;
    field $params        :param :reader = undef;
    # Alias fields for backward compat with different attribute names
    field $label :param :reader = undef;      # v2-style alias
    field $function :param = undef;           # v1-style alias
    field $arg_value :param :reader = undef;  # @ARGV[0] passed at construction
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    ADJUST {
        # Allow label or function to be used as alias for function_name
        $function_name //= $label // $function;
        $label //= $function_name;
    }

    # Start nodes have no inputs (entry point)
    method inputs() { return []; }

    method op() { 'Start' }

    method is_multi() { return 1; }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Start',
            inputs => [],
            attributes => {
                function_name => $function_name,
                label         => $label,
                params        => $params,
                arg_value     => $arg_value,
            },
        };
    }

    method execute() {
        # Start node returns a control token (1 to indicate control is active)
        return 1;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $arg_type = defined($arg_value)
            ? Chalk::IR::Type::Integer->constant($arg_value)
            : Chalk::IR::Type::Top->top();

        return Chalk::IR::Type::Tuple->of(
            Chalk::IR::Type::Ctrl->CTRL(),
            $arg_type
        );
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Dominator tree: Start is the root, so idom returns undef
    method idom() { return undef; }

    # Dominator depth: Start is at depth 0
    method idepth() { return 0; }

    # Dominator check: Start dominates all nodes (by definition)
    method dominates($other) {
        # Start dominates every node, including itself
        return 1;
    }

    # Stub for transform tracking (not used in v2 but called by Builder)
    method record_transform(@args) {
        # No-op for compatibility
        return;
    }

}

1;
