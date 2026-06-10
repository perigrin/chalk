# ABOUTME: Metadata struct for a method declaration.
# ABOUTME: Stores name, params, return type, body statements, and optional per-method computation graph.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::MethodInfo {
    field $name        :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;
    field $body        :param :reader = [];
    field $graph       :param :reader = undef;

    # body_node: the IR value node that this method lowers to (i.e., the root of
    # the method's SoN sub-graph). Used by the LLVM backend to lower the method
    # body. Defaults to undef; set when constructing MethodInfo from an ir-block.
    field $body_node   :param :reader = undef;

    # return_repr: the LLVM representation of the method's return value
    # (e.g. 'Int', 'Str', 'Bool'). Defaults to undef; set from ir-block return_repr attr.
    field $return_repr :param :reader = undef;

    # Content-based ID for use in NodeFactory hash-cons keys.
    # MethodInfo objects are not hash-consed themselves, but may appear as
    # inputs inside hash-consed Constructor nodes (e.g., ClassDecl body).
    method id() {
        my $params_str = join(',', map { defined $_ ? "$_" : 'undef' } $params->@*);
        my $rt = defined $return_type ? $return_type : 'undef';
        return "MethodInfo:$name:[$params_str]:$rt";
    }

    # No-op: MethodInfo does not participate in the use-def chain.
    method add_consumer($consumer) {
        return;
    }
}
