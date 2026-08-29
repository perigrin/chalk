# ABOUTME: Compile-time metaobject for a method declaration within a class.
# ABOUTME: Owns the method's name, params, return type, and IR graph (with per-method hash-cons scope).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::VarDecl;
use Chalk::Grammar::Perl::TypeLibrary;   # is_subtype: the lattice

class Chalk::MOP::Method {
    field $name             :param :reader;
    field $class            :param :reader;
    field $params           :param :reader = [];
    field $return_type      :param :reader = undef;
    field $graph            :param :reader = Chalk::IR::Graph->new;
    field $factory          :param :reader = Chalk::IR::NodeFactory->new;
    field $body             :param :reader = [];
    field $lexical_bindings :param        = [];

    # Delegate graph operations to this method's $graph. The per-method
    # $graph IS the source of truth for which nodes belong to this method,
    # so these delegators are honest (per-graph isolation works). The
    # $factory field is currently unused scaffolding (see mop.md), so
    # there are no make/make_cfg delegators here — production code
    # constructs nodes via $ctx->factory->make(...) using the per-parse
    # factory.
    method merge($node)  { $graph->merge($node) }
    method next_cfg_id() { $graph->next_cfg_id }

    # Lexical bindings: VarDecl IR nodes declared in this method's body.
    # Returns the list (not the arrayref) so callers can scalar @list etc.
    method lexical_bindings() { return $lexical_bindings->@*; }

    # set_return_type($type) -- NARROW the return type, never weaken it.
    #
    # declare_method populates return_type from the WIRE, the producer's answer.
    # This loader then walks the graph and can often do better: it has the whole
    # program where the producer works one CV at a time. When the two are ORDERED
    # -- the graph derives a subtype of what the wire declared -- the narrower one
    # is the answer, and it has to land HERE, because Target::LLVM reads
    # return_type directly for the callee's signature. A metaobject left holding
    # the wider type emits a wider return than its call sites expect.
    #
    # NARROWING ONLY. Accepting anything would let a later pass weaken a
    # determined type, which is exactly what t/bootstrap/loader-return-type.t
    # forbids: "may only NARROW it, never weaken it." `Unknown` and undef are not
    # determined types, so any answer replaces them.
    method set_return_type($type) {
        die "MOP: return type must be defined\n" unless defined $type;

        if ( defined $return_type && $return_type ne 'Unknown' ) {
            return $return_type if $type eq $return_type;
            unless ( Chalk::Grammar::Perl::TypeLibrary::is_subtype( $type, $return_type ) ) {
                my $where = $class->name . "::" . $name;
                die "MOP: refusing to widen $where return type from "
                  . "'$return_type' to '$type' -- a return type may only narrow.\n";
            }
        }

        $return_type = $type;
        return $return_type;
    }
}
