# ABOUTME: Compile-time metaobject for a subroutine declaration within a class.
# ABOUTME: Distinguished from Method by having no implicit $self and no method dispatch.
use 5.42.0;
use utf8;
use experimental 'class';


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
    # An :lvalue sub (the wire's `lvalue`): its value is the container it ends
    # at, not a copy -- a foreach over its call, an @_ of it, alias that.
    field $lvalue      :param :reader = false;
    # The wire's signature record, as declared: {kind, mandatory, optional,
    # params}. `mandatory` counts every positional parameter, named or not --
    # `params` above lists the named ones only.
    field $signature   :param :reader = undef;
    # The calling context this metaobject's graph is a copy for ('list'), or
    # undef for the sub's own graph (Serialize::JSON's CONTEXT_COPY).
    field $context     :param :reader = undef;
    # ITS BODY, opaque to the MOP: the compiler hands it the graph it built
    # (the MOP is the bottom layer -- it never makes or reads one).
    field $graph       :param :reader = undef;
    field $body        :param :reader = [];

    # The Maybe shim only (LLVM.pm _context_sees_maybe_as_scalar): it shows
    # Context Scalar for a Maybe[T] and puts it back -- not a narrowing, so
    # it does not go through set_return_type. Delete it with Context.
    method shim_return_type($type) { $return_type = $type; return }

    # set_return_type($type): the return type the compiler settled on. Which
    # answer wins -- the wire's or a narrower one whole-program analysis
    # derives -- is analysis's to decide (Chalk::IR::Analysis::
    # narrow_return_type: a return type only narrows); the metaobject holds it.
    method set_return_type($type) {
        die "MOP: return type must be defined\n" unless defined $type;
        $return_type = $type;
        return $return_type;
    }
}
