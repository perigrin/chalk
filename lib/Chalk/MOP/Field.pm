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
    # Does this field carry the `:reader` attribute?
    #
    # ON THE PROTOCOL, not recovered from an attribute string. `:reader` DOES
    # create a real reader method -- perl generates it, and the producer
    # translates it: measured, `field $x :reader` in class P yields a graph
    # named `P::x` on the wire exactly as an explicit method would.
    #
    # What it does NOT get is an entry in the class's `methods` RECORD.
    # Measured on the same pair: an explicit `method get` appears in
    # `classes.Q.methods`, while the generated `P::x` does not appear in
    # `classes.P.methods` at all -- that record lists only methods written in
    # the source.
    #
    # So a pass walking `$cls->methods` to collect return types never sees a
    # reader, and has to derive its return repr from THE FIELD instead: the
    # accessor returns the field, so its type is the field's type. That is why
    # the question has to be askable of a Field after the seal.
    field $is_reader     :param :reader = false;
    field $attributes    :param = [];

    method attributes() { return $attributes->@* }

    method has_attribute($name) {
        return scalar grep { $_ eq ":$name" } $attributes->@*;
    }
    method is_param()   { return $self->has_attribute('param') }
    method has_reader() { return $self->has_attribute('reader') }
}
