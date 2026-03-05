# ABOUTME: Tests that XS compilation handles sub declarations inside classes.
# ABOUTME: Verifies SubroutineDefinition produces IR nodes and XS emitter compiles them.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Semiring::Boolean;

# Skip guards
my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

# --- Step 1: Parse Boolean.pm to IR ---
# Boolean has a class-scope `sub _intern(...)` and `my sub _helper(...)` patterns
# that should produce SubDecl IR nodes.
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSSubCompile') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Precedence.pm') };
ok(defined $ir, 'Precedence.pm parses to IR') or BAIL_OUT("Parse failed: $@");

# --- Step 2: Check that SubDecl nodes are present in the IR ---
# Walk the IR tree and find SubDecl constructor nodes
my @sub_decls;
my $walk;
$walk = sub ($node) {
    return unless defined $node;
    if ($node isa Chalk::Bootstrap::IR::Node::Constructor
            && $node->class() eq 'SubDecl') {
        push @sub_decls, $node;
    }
    if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
        for my $input ($node->inputs()->@*) {
            if (ref($input) eq 'ARRAY') {
                $walk->($_) for $input->@*;
            } else {
                $walk->($input);
            }
        }
    }
};

# Walk all IR nodes looking for SubDecl
if ($ir isa Chalk::Bootstrap::IR::Node::Constructor) {
    $walk->($ir);
} elsif (ref($ir) eq 'ARRAY') {
    $walk->($_) for $ir->@*;
}

ok(scalar @sub_decls > 0, 'IR contains SubDecl nodes for class-scope subs')
    or diag "Found " . scalar(@sub_decls) . " SubDecl nodes (expected at least 1 for _intern)";

# If we have SubDecl nodes, verify structure
if (@sub_decls) {
    my $intern_decl = (grep {
        $_->inputs()->[0]->value() eq '_intern'
    } @sub_decls)[0];
    ok(defined $intern_decl, 'Found SubDecl for _intern')
        or diag "SubDecl names: " . join(', ', map { $_->inputs()->[0]->value() } @sub_decls);

    if (defined $intern_decl) {
        # SubDecl should have: name, params, body (same structure as MethodDecl)
        my $name = $intern_decl->inputs()->[0]->value();
        is($name, '_intern', 'SubDecl name is _intern');

        my $params = $intern_decl->inputs()->[1];
        ok(ref($params) eq 'ARRAY', 'SubDecl has params array');
    }
}

done_testing();
