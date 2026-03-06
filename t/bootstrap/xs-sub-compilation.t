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

# --- Step 3: Generate XS and verify SubDecl produces _impl_ helpers ---
my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
$reg->register('Chalk::Bootstrap::Semiring::Precedence', {
    ir => $ir, sa => $sa, ctx => $ctx, uses => [],
});

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSSubCompile',
    class_registry => $reg,
);

my @entries = ({
    class_name => 'Chalk::Bootstrap::Semiring::Precedence',
    ir => $ir, sa => $sa, ctx => $ctx,
});

my $xs_code = eval { $xs->generate_multi_class(\@entries) };
ok(defined $xs_code, 'multi-class XS generation succeeds')
    or diag "XS gen failed: $@";

# The XS emitter should recognize SubDecl nodes and emit _impl_ helpers
# for class-scope subs like _intern, so they can be called directly from C
# instead of via broken eval_pv calls.
if (defined $xs_code) {
    # _intern references %_cache (class-scope var). Now that class-scope vars
    # compile as static C variables, _intern should compile to an _impl_ helper
    # (direct call) or at minimum use call_pv with FQ name (not eval_pv).
    unlike($xs_code, qr/eval_pv\("_intern/,
        'XS code does NOT use eval_pv for bare _intern calls');

    # With static class-scope vars, _intern may compile to _impl_ helper
    # or fall back to call_pv with FQ name. Either is acceptable.
    my $has_impl = $xs_code =~ /_impl_precedence__intern/;
    my $has_call_pv = $xs_code =~ /call_pv\("Chalk::Bootstrap::Semiring::Precedence::_intern"/;
    ok($has_impl || $has_call_pv,
        'XS code uses _impl_ helper or call_pv with FQ name for _intern');
}

done_testing();
