# ABOUTME: IR node for accessing a package (stash) variable in the Sea of Nodes graph.
# ABOUTME: Represents reads of package globals like $Foo::bar or %Foo::.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::EntryDef :isa(Chalk::IR::Node::Access) {
    field $package :param :reader = '';

    # `symbol` is the BARE identifier -- 'g', never '$g'. perl's own terms, from
    # Symbol.pm: qualify turns unqualified SYMBOL NAMES into qualified VARIABLE
    # NAMES, and qualify("x") is "main::x" with no sigil, because the symbol
    # table is sigil-free and the sigil selects a slot within the glob.
    field $symbol  :param :reader = '';

    # THE SIGIL IS PART OF THE IDENTITY, and it is REQUIRED -- there is no
    # sensible default.
    #
    # `_` alone names THREE different things in perl: the scalar `$_`, the
    # argument array `@_`, and the bareword `_` filetest handle (`-f _`, which
    # reuses the last stat buffer). A name-only identity hash-consed the first
    # two into ONE node -- measured, a single EntryDef(_) fed both a
    # `shift @_` Call and a RegexMatch subject. The same applies to any stash
    # holding one name under two sigils: `$g` and `@g` are unrelated variables.
    #
    # No default, deliberately: a default lets a construction site omit the
    # sigil and still hash-cons, which is exactly how the collision hid. A
    # sigil-less variable lookup should be impossible to express.
    field $sigil      :param :reader;

    method operation() { 'EntryDef' }
    sub identity_kind { q(hash_consed) }

    # The qualified spelling, composed in ONE place -- see the note on
    # PadAccess::name. This is the variable's name WITHOUT its package;
    # `_pkg_*_global_name` consumers pass `package` alongside it.
    method name() { $sigil . $symbol }

    method content_hash() {
        return join('|', 'EntryDef', "package=$package",
            "sigil=$sigil", "symbol=$symbol", $self->_serialize_inputs());
    }
}
