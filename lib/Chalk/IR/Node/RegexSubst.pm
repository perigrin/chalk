# ABOUTME: Regex substitution operation node in the Chalk IR.
# ABOUTME: Represents a substitution (s///) applied to an input expression.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Regex;

class Chalk::IR::Node::RegexSubst :isa(Chalk::IR::Node::Regex) {
    method operation() { 'RegexSubst' }
}
