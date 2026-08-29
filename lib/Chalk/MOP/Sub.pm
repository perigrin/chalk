# ABOUTME: Compile-time metaobject for a subroutine declaration within a class.
# ABOUTME: Distinguished from Method by having no implicit $self and no method dispatch.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::Grammar::Perl::TypeLibrary;   # is_subtype: the lattice

class Chalk::MOP::Sub {
    field $name        :param :reader;
    field $class       :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;

    # Does the body read `@_`? A CALLEE property (the sub is compiled once, so
    # every call site conforms), recorded by the producer's CV walk rather than
    # derived here: `@_` has three IR spellings and vanishes entirely from the
    # graph for `my ($a,$b) = @_`, so a scan cannot answer it reliably.
    #
    # Consumed by the calling convention -- params by default, `@_` materialised
    # only when the body actually touches it.
    field $uses_args   :param :reader = false;
    field $graph       :param :reader = Chalk::IR::Graph->new;
    field $factory     :param :reader = Chalk::IR::NodeFactory->new;
    field $body        :param :reader = [];

    # Delegate graph operations to this sub's $graph. See MOP::Method
    # for rationale: $graph is per-sub (honest); $factory is currently
    # unused scaffolding so there are no make/make_cfg delegators.
    method merge($node)  { $graph->merge($node) }
    method next_cfg_id() { $graph->next_cfg_id }

    # set_return_type($type) -- NARROW the return type, never weaken it.
    #
    # declare_sub populates return_type from the WIRE, the producer's answer.
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
