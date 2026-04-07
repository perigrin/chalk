# ABOUTME: IR node for accessing a package (stash) variable in the Sea of Nodes graph.
# ABOUTME: Represents reads of package globals like $Foo::bar or %Foo::.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::StashAccess :isa(Chalk::IR::Node::Access) {
    field $stash_name :param :reader = '';
    field $var_name   :param :reader = '';

    method operation() { 'StashAccess' }

    method content_hash() {
        return join('|', 'StashAccess', "stash_name=$stash_name",
            "var_name=$var_name", $self->_serialize_inputs());
    }
}
