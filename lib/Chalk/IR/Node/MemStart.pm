# ABOUTME: Initial aggregate-memory value for a Chalk computation graph (memory-SSA).
# ABOUTME: Has no inputs; the memory state at function entry, before any element store.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::MemStart :isa(Chalk::IR::Node) {
    method operation() { 'MemStart' }
}
