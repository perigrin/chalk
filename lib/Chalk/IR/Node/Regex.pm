# ABOUTME: Intermediate base class for regex operation nodes.
# ABOUTME: Groups RegexMatch and RegexSubst, carrying shared pattern and flags fields.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::Regex :isa(Chalk::IR::Value) {
    field $pattern :param :reader = '';
    field $flags   :param :reader = '';
    # The bodies of a match's `(?{ ... })` blocks, in pattern order.
    field $code_bodies :param :reader = undef;

    method content_hash() {
        return join('|', $self->operation(), "pattern=$pattern", "flags=$flags",
            ( $code_bodies ? "code=" . join(',', @$code_bodies) : () ), $self->_serialize_inputs());
    }
}
