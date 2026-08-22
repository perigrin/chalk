# ABOUTME: Ternary conditional expression node in the Chalk IR.
# ABOUTME: Represents condition ? true_expr : false_expr. Lowered to If+Proj+Region+Phi in a future pass.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Value;

class Chalk::IR::Node::TernaryExpr :isa(Chalk::IR::Value) {
    method operation() { 'TernaryExpr' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
}
