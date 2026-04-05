# ABOUTME: Intermediate base class for regex operation nodes.
# ABOUTME: Groups RegexMatch and RegexSubst, carrying shared flags field.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Regex :isa(Chalk::IR::Node) {
    field $flags :param :reader = '';
}
