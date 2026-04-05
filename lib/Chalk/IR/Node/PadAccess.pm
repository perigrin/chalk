# ABOUTME: IR node for accessing a lexical pad slot by target index and variable name.
# ABOUTME: Used to represent $x, @arr, %hash style variable reads in the Sea of Nodes graph.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::PadAccess :isa(Chalk::IR::Node::Access) {
    field $targ    :param :reader;
    field $varname :param :reader;

    method operation() { 'PadAccess' }

    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        return "PadAccess|targ=" . $targ . "|varname=" . $varname . "|" . join('|', @input_ids);
    }
}
