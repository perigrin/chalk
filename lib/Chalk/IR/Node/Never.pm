# ABOUTME: Never node in the IR graph
# ABOUTME: Represents a "never true" condition for infinite loop exits
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Never :isa(Chalk::IR::Node::If) {
    use Chalk::IR::Node::If;
    use Chalk::IR::Type::Tuple;
    use Chalk::IR::Type::Ctrl;
    use Chalk::IR::Type::Bottom;

    method op() { 'Never' }

    # Never node always returns Bottom type
    # This indicates the condition is never true
    method compute() {
        # Never branch: false branch only (condition never true)
        return Chalk::IR::Type::Tuple->of(
            Chalk::IR::Type::Bottom->BOTTOM(),  # True branch never taken
            Chalk::IR::Type::Ctrl->CTRL()       # False branch always taken
        );
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Never',
            inputs => $self->inputs,
            attributes => {},
        };
    }
}

1;
