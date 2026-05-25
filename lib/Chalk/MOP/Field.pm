# ABOUTME: Compile-time metaobject for a field declaration within a class.
# ABOUTME: Tracks name, sigil, position, param attribute, default presence, and raw attributes.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::MOP::Field {
    field $name          :param :reader;
    field $sigil         :param :reader;
    field $class         :param :reader;
    field $fieldix       :param :reader = 0;
    field $param_name    :param :reader = undef;
    field $has_default   :param :reader = false;
    field $default_value :param :reader = undef;
    field $type          :param :reader = undef;
    field $attributes    :param = [];

    method attributes() { return $attributes->@* }

    method has_attribute($name) {
        return scalar grep { $_ eq ":$name" } $attributes->@*;
    }
    method is_param()   { return $self->has_attribute('param') }
    method has_reader() { return $self->has_attribute('reader') }
}
