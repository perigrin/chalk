# ABOUTME: Metadata struct for a subroutine declaration.
# ABOUTME: Stores name, params, scope (my/our/package), body statements, and the computation graph.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::SubInfo {
    field $name   :param :reader;
    field $params :param :reader = [];
    field $scope  :param :reader = 'package';
    field $body   :param :reader = [];
    field $graph  :param :reader = undef;

    # Content-based ID for use in NodeFactory hash-cons keys.
    # SubInfo objects are not hash-consed themselves, but may appear as
    # inputs inside hash-consed Constructor nodes (e.g., ClassDecl body).
    method id() {
        my $params_str = join(',', map { defined $_ ? "$_" : 'undef' } $params->@*);
        return "SubInfo:$name:[$params_str]:$scope";
    }

    # No-op: SubInfo does not participate in the use-def chain.
    method add_consumer($consumer) {
        return;
    }
}
