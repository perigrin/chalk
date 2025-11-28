# ABOUTME: Start node representing function entry point in the IR graph
# ABOUTME: Defines the initial control and data state for a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Start {
    field $function_name :param :reader = undef;
    field $params        :param :reader = undef;
    # v2-style 'label' field (alias for function_name for backward compat)
    field $label :param :reader = undef;
    field $source_info :param :reader = undef;

    ADJUST {
        # Allow label to be used as alias for function_name
        $function_name //= $label;
        $label //= $function_name;
    }

    # Content-addressable ID computed from label/function_name
    field $id :reader = "start_" . ($label // $function_name // 'anonymous');

    # Start nodes have no inputs (entry point)
    method inputs() { return []; }

    method op() { 'Start' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Start',
            inputs => [],
            attributes => {
                function_name => $function_name,
                label         => $label,
                params        => $params,
            },
        };
    }

    method execute() {
        # Start node returns a control token (undef for now)
        return undef;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
        return $self;
    }

    # Stub for transform tracking (not used in v2 but called by Builder)
    method record_transform(@args) {
        # No-op for compatibility
        return;
    }

    method get_transform_chain() {
        return [];
    }
}

1;
