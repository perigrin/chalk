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
    field $graph       :param :reader = undef;
}
