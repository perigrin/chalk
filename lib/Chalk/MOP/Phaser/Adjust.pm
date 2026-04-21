# ABOUTME: Compile-time metaobject for an ADJUST phaser block within a class.
# ABOUTME: Runs during instance construction in MRO order, source order within each class.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::MOP::Phaser;

class Chalk::MOP::Phaser::Adjust :isa(Chalk::MOP::Phaser) {
    field $class :param :reader;
}
