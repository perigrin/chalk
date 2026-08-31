# ABOUTME: Count node — the number of elements in an aggregate.
# ABOUTME: Distinct from Length: that is characters in a string, this is a count.
use 5.42.0;
use utf8;
use experimental 'class';
use Chalk::IR::Node::UnaryOp;

# `scalar(@a)` and `length($s)` are different questions and perl answers them
# differently. Measured on 5.42: `length(@a)` over a 3-element array is 1, not
# 3 -- @a goes to scalar context (3) and length("3") is 1.
#
# perl has a `length` OP; it has no count op at all, because `scalar(@a)` is
# just the array in scalar context. The producer synthesises this node for
# that shape (perl5-son 93a2d12), and the split is SUBTRACTIVE: sites that
# arrived as Length now arrive as Count, and Length narrowed to strings.
class Chalk::IR::Node::Count :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Count' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { 'scalar' }
}
