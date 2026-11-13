# ABOUTME: SubDefined node -- B::SoN's `defined &NAME` asked where the program runs:
# ABOUTME: its answer as compiled, and the graphs whose run may change it.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::SubDefined :isa(Chalk::IR::Value) {
    field $name   :param :reader;        # Stash::name
    field $answer :param :reader;        # defined as compiled (1 or '')
    field $unless :param :reader = [];   # graphs whose run may change it

    method operation() { 'SubDefined' }
    sub identity_kind { 'hash_consed' }

    method content_hash() {
        return join('|', 'SubDefined', "name=$name", 'answer=' . ( $answer ? 1 : 0 ),
            'unless=' . join(',', @$unless), $self->_serialize_inputs());
    }
}
