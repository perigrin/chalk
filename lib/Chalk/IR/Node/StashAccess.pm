# ABOUTME: IR node for accessing a package (stash) variable in the Sea of Nodes graph.
# ABOUTME: Represents reads of package globals like $Foo::bar or %Foo::.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::StashAccess :isa(Chalk::IR::Node::Access) {
    field $stash_name :param :reader = '';
    field $var_name   :param :reader = '';

    # THE SIGIL IS PART OF THE IDENTITY, and it is REQUIRED -- there is no
    # sensible default.
    #
    # `_` alone names THREE different things in perl: the scalar `$_`, the
    # argument array `@_`, and the bareword `_` filetest handle (`-f _`, which
    # reuses the last stat buffer). A name-only identity hash-consed the first
    # two into ONE node -- measured, a single StashAccess(_) fed both a
    # `shift @_` Call and a RegexMatch subject. The same applies to any stash
    # holding one name under two sigils: `$g` and `@g` are unrelated variables.
    #
    # No default, deliberately: a default lets a construction site omit the
    # sigil and still hash-cons, which is exactly how the collision hid. A
    # sigil-less variable lookup should be impossible to express.
    field $sigil      :param :reader;

    method operation() { 'StashAccess' }
    sub identity_kind { q(hash_consed) }

    method content_hash() {
        return join('|', 'StashAccess', "stash_name=$stash_name",
            "sigil=$sigil", "var_name=$var_name", $self->_serialize_inputs());
    }
}
