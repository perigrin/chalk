# ABOUTME: Metadata struct for a class field declaration.
# ABOUTME: Stores name, attributes (param/reader/writer), and optional default value.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::FieldInfo {
    field $name          :param :reader;
    field $attributes    :param :reader = [];
    field $default_value :param :reader = undef;
}
