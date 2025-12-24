# ABOUTME: XS AST node that combines multiple child nodes for sequential emission
# ABOUTME: Used to group MODULE declaration with XSUBs in generated output
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::CompositeNode :isa(Chalk::Target::XS::AST::Node) {
    field $children :param :reader = [];

    method emit() {
        my @output;
        for my $child ($children->@*) {
            push @output, $child->emit();
        }
        return join("\n", @output);
    }
}

1;
