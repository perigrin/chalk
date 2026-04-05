# ABOUTME: Metadata struct for a class declaration.
# ABOUTME: Stores name, parent, fields, methods, and subs.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::ClassInfo {
    field $name    :param :reader;
    field $parent  :param :reader = undef;
    field $fields  :param :reader = [];
    field $methods :param :reader = [];
    field $subs    :param :reader = [];
}
