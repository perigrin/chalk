# ABOUTME: Start node representing function entry point in the IR graph
# ABOUTME: Defines the initial control and data state for a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Start {
    field $function_name :param :reader = undef;
    field $params        :param :reader = undef;
    # Alias fields for backward compat with different attribute names
    field $label :param :reader = undef;      # v2-style alias
    field $function :param = undef;           # v1-style alias
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    ADJUST {
        # Allow label or function to be used as alias for function_name
        $function_name //= $label // $function;
        $label //= $function_name;
    }

    # Content-addressable ID computed from label/function_name/function
    field $id :reader = "start_" . ($label // $function_name // $function // 'anonymous');

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

}

1;
