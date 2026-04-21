# ABOUTME: Abstract base class for phaser metaobjects (lifecycle hooks with executable bodies).
# ABOUTME: Provides graph and source_position accessors shared by all phaser types.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::MOP::Phaser {
    field $graph           :param :reader = undef;
    field $source_position :param :reader = 0;
}
