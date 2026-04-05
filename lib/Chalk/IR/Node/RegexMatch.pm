# ABOUTME: Regex match operation node in the Chalk IR.
# ABOUTME: Represents a pattern match (m//) against an input expression.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Regex;

class Chalk::IR::Node::RegexMatch :isa(Chalk::IR::Node::Regex) {
    method operation() { 'RegexMatch' }
}
