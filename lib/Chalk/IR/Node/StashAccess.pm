# ABOUTME: IR node for accessing a package (stash) variable in the Sea of Nodes graph.
# ABOUTME: Represents reads of package globals like $Foo::bar or %Foo::.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::StashAccess :isa(Chalk::IR::Node::Access) {
    field $stash_name :param :reader = '';
    field $var_name   :param :reader = '';

    # THE SIGIL IS PART OF THE IDENTITY. `$_` and `@_` are DIFFERENT variables
    # sharing the glob name `_`; this node is hash-consed, so a name-only
    # identity merged them into ONE node -- measured on the producer side, a
    # single StashAccess(_) fed both a `shift @_` Call and a RegexMatch subject.
    # One node cannot be two variables. Same for `$g` vs `@g` in one stash.
    field $sigil      :param :reader = '$';

    method operation() { 'StashAccess' }
    sub identity_kind { q(hash_consed) }

    method content_hash() {
        return join('|', 'StashAccess', "stash_name=$stash_name",
            "sigil=$sigil", "var_name=$var_name", $self->_serialize_inputs());
    }
}
