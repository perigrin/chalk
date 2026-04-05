# ABOUTME: Method, subroutine, or builtin call node in the Chalk IR.
# ABOUTME: Carries dispatch kind (method/sub/builtin) and callee name.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Call :isa(Chalk::IR::Node) {
    field $dispatch_kind :param :reader;
    field $name          :param :reader;

    method operation() { 'Call' }

    method content_hash() {
        my @input_ids;
        for my $input ($self->inputs()->@*) {
            if (!defined $input) {
                push @input_ids, 'undef';
            } elsif (ref($input) eq 'ARRAY') {
                my @ids = map { defined($_) ? $_->id() : 'undef' } $input->@*;
                push @input_ids, '[' . join(',', @ids) . ']';
            } else {
                push @input_ids, $input->id();
            }
        }
        return "Call|dispatch_kind=" . $dispatch_kind
             . "|name=" . $name
             . "|" . join('|', @input_ids);
    }
}
