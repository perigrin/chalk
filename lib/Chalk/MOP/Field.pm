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
    # Does this field synthesize a reader method?
    #
    # ON THE PROTOCOL, not recovered from an attribute string. A `:reader`
    # field has no method graph -- the backend synthesizes the accessor and its
    # return repr IS the field type -- so an inference pass running AFTER the
    # seal has to be able to ask. Reaching into the raw wire record for
    # `is_reader` was one of four such reads that kept type inference tied to
    # deserialization.
    field $is_reader     :param :reader = false;
    field $attributes    :param = [];

    method attributes() { return $attributes->@* }

    method has_attribute($name) {
        return scalar grep { $_ eq ":$name" } $attributes->@*;
    }
    method is_param()   { return $self->has_attribute('param') }
    method has_reader() { return $self->has_attribute('reader') }
}
