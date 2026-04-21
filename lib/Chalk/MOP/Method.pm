# ABOUTME: Compile-time metaobject for a method declaration within a class.
# ABOUTME: Owns the method's name, params, return type, and (future) IR graph.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::MOP::Method {
    field $name        :param :reader;
    field $class       :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;
    field $graph       :param :reader = undef;
}
