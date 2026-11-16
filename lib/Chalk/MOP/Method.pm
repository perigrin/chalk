# ABOUTME: Compile-time metaobject for a method declaration within a class.
# ABOUTME: Owns the method's name, params and return type; its body (a graph) is the compiler's, opaque here.
use 5.42.0;
use utf8;
use experimental 'class';


class Chalk::MOP::Method {
    field $name             :param :reader;
    field $class            :param :reader;
    field $params           :param :reader = [];
    field $return_type      :param :reader = undef;
    # ITS BODY, opaque to the MOP: the compiler hands it the graph it built
    # (the MOP is the bottom layer -- it never makes or reads one).
    field $graph            :param :reader = undef;
    field $body             :param :reader = [];
    field $lexical_bindings :param        = [];

    # Lexical bindings: VarDecl IR nodes declared in this method's body.
    # Returns the list (not the arrayref) so callers can scalar @list etc.
    method lexical_bindings() { return $lexical_bindings->@*; }

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
