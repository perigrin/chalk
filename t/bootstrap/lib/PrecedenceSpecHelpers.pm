# ABOUTME: Shared helpers for precedence-spec test files derived from perlop.pod.
# ABOUTME: Builds the Perl grammar once per process; exports parse_expr / shape_of / isa_with_shape.
use 5.42.0;
use utf8;

package PrecedenceSpecHelpers;

use Test::Chalk;
use Exporter 'import';
our @EXPORT_OK = qw(parse_expr shape_of isa_with_shape);

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Program;
use Chalk::IR::Node;
use Chalk::IR::Node::VarDecl;

# Build the Perl grammar pipeline once per process. The grammar object is
# reused by every parse_expr call; the IR NodeFactory is reset per call so
# tests don't share node IDs.
my $_grammar;
my $_grammar_built = 0;

sub _ensure_grammar() {
    return if $_grammar_built;
    my $raw_ir = perl_pipeline()
        or die "PrecedenceSpecHelpers: perl_pipeline() returned undef\n";
    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($raw_ir);
    # Use a unique package name so multiple .t files in the same process don't
    # collide. The caller doesn't see the package; only $_grammar matters.
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PrecSpecShared/g;
    eval $generated;
    die "PrecedenceSpecHelpers: grammar eval failed: $@\n" if $@;
    $_grammar = Chalk::Grammar::Perl::PrecSpecShared::grammar();
    die "PrecedenceSpecHelpers: grammar() returned undef\n" unless defined $_grammar;
    $_grammar_built = 1;
}

# parse_expr($source) → IR node, or undef on parse failure.
#
# Wraps $source in `my $_ = $source;` to give the parser a well-formed
# statement, then unwraps the VarDecl and returns the initializer expression.
# Returns undef on parse failure (caller can mark TODO with diagnostic).
#
# An expression looser than assignment (`$a or $b`, `print 1 or die`) does
# not fit in the initializer: `my $_ = $a or $b` is `(my $_ = $a) or $b`.
# For one of those the statement is not the VarDecl, and the source is
# parsed again as a statement of its own, whose node is returned.
sub parse_expr($source) {
    _ensure_grammar();
    my $first = _first_statement("my \$_ = $source;");
    return $first->inputs()->[1] if $first isa Chalk::IR::Node::VarDecl;
    return defined $first ? _first_statement("$source;") : undef;
}

sub _first_statement($stmt) {
    my $parser = build_perl_ir_parser($_grammar, start => 'Program');
    my $result = eval { $parser->parse_value($stmt) };
    return undef if $@ || !defined $result || $result->is_zero();
    my $ir = $result->extract();
    return undef unless $ir isa Chalk::IR::Program;
    my $stmts = $ir->other_stmts();
    return undef unless $stmts && $stmts->@*;
    return $stmts->[0];
}

# shape_of($node) → a one-line string description of the IR shape.
#
# Used in diagnostic output for failing tests. Format:
#   Add(Const(2),Multiply(Const(3),Const(4)))
# The class name is shortened by stripping the Chalk::IR::Node:: prefix.
sub shape_of($node) {
    return 'undef' unless defined $node;
    return 'ARRAY[' . join(',', map { shape_of($_) } $node->@*) . ']'
        if ref($node) eq 'ARRAY';
    return "SCALAR($node)" unless ref($node);
    my $cls = ref($node);
    if ($node isa Chalk::IR::Node::Constant) {
        return "Const(" . ($node->value() // '<undef>') . ")";
    }
    my @children;
    if ($node->can('inputs') && defined $node->inputs()) {
        @children = map { shape_of($_) } $node->inputs()->@*;
    }
    my $short = $cls =~ s/^Chalk::IR::Node:://r;
    return @children ? "$short(" . join(',', @children) . ")" : $short;
}

# isa_with_shape($node, $type, $label) → $node on success, undef on failure.
#
# Asserts $node is an instance of $type. On failure, diag()s the actual shape
# so the test reader can see exactly what the parser produced. Returns the
# node so callers can chain assertions on its inputs:
#   my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Add', 'top is Add')
#       or return;
#   isa_with_shape($outer->inputs()->[2], 'Chalk::IR::Node::Multiply', 'right is Multiply');
#
# The local $Test::Builder::Level bump tells Test::Builder to look one stack
# frame higher when resolving $TODO and the failure-line caller. Without it,
# Test::Builder reads $TODO from PrecedenceSpecHelpers' package (where it's
# never set) and reports the helper itself as the failure site. With the
# bump, callers can wrap isa_with_shape in TODO blocks and the failure is
# reported as a TODO failure pointing at the calling test file.
sub isa_with_shape($node, $type, $label) {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    if (ref($node) && $node->isa($type)) {
        Test::Chalk::pass($label);
        return $node;
    }
    Test::Chalk::fail($label);
    Test::Chalk::diag("  expected isa $type");
    Test::Chalk::diag("  got shape: " . shape_of($node));
    return undef;
}

1;
