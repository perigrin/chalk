# ABOUTME: XS AST node for if/else statements
# ABOUTME: Represents structured control flow for XS code generation
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::Target::XS::AST::IfStatement :isa(Chalk::Target::XS::AST::Node) {
    field $condition :param :reader;   # Variable name holding condition result
    field $then_body :param :reader;   # Array of AST nodes for true branch
    field $else_body :param :reader = [];  # Array of AST nodes for false branch

    method emit() {
        my @lines;

        # Start if block
        push @lines, "if ($condition) {";

        # Emit then body with indentation
        for my $stmt ($then_body->@*) {
            my $emitted = $stmt->emit();
            push @lines, "    $emitted";
        }

        # If we have an else body, emit it
        if ($else_body->@*) {
            push @lines, "} else {";
            for my $stmt ($else_body->@*) {
                my $emitted = $stmt->emit();
                push @lines, "    $emitted";
            }
        }

        push @lines, "}";

        return join("\n", @lines);
    }
}

1;
