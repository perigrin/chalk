# ABOUTME: Metadata struct for a method declaration.
# ABOUTME: Stores name, params, return type, and the per-method computation graph.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::MethodInfo {
    field $name        :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;
    field $graph       :param :reader = undef;
}
