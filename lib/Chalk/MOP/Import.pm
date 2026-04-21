# ABOUTME: Compile-time metaobject recording a use-statement import within a class.
# ABOUTME: Tracks which module was imported and with what arguments.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::MOP::Import {
    field $module :param :reader;
    field $class  :param :reader;
    field $args   :param = [];

    method args() { return $args->@* }
}
