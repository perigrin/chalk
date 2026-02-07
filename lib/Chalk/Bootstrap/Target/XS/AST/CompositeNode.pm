# ABOUTME: XS AST node that groups child nodes for sequential emission.
# ABOUTME: Calls emit() on each child in order and concatenates the results.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::Bootstrap::Target::XS::AST::Node;

class Chalk::Bootstrap::Target::XS::AST::CompositeNode :isa(Chalk::Bootstrap::Target::XS::AST::Node) {
    field $children :param :reader;

    method emit() {
        return join('', map { $_->emit() } $children->@*);
    }
}
