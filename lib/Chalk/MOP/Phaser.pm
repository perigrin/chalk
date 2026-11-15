# ABOUTME: Abstract base class for phaser metaobjects (lifecycle hooks with executable bodies).
# ABOUTME: Holds its source position and its body (a graph the compiler built, opaque here).
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::MOP::Phaser {
    # ITS BODY, opaque to the MOP: the compiler hands it the graph it built.
    field $graph           :param :reader = undef;
    field $source_position :param :reader = 0;
}
