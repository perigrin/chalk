# ABOUTME: Test that try/catch CFG nodes are properly registered in cfg_lookup.
# ABOUTME: Verifies _build_cfg_lookup handles try_node contexts and _collect_var_decls recurses into try/catch.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::XS;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

# Skip if no C compiler
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

# Parse Earley.pm which has try/catch blocks in _complete
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSTryCatchLookup') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed: $@");

# Build cfg_lookup via XS target
my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatchLookup');
$xs->_build_cfg_lookup($sa, $ctx);

# Find _complete method
my $class_decl;
for my $item ($ir->inputs()->[0]->@*) {
    if ($item isa Chalk::Bootstrap::IR::Node::Constructor && $item->class() eq 'ClassDecl') {
        $class_decl = $item;
        last;
    }
}
my $body = $class_decl->inputs()->[2];
my $complete_method;
for my $item ($body->@*) {
    next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
    next unless $item->class() eq 'MethodDecl';
    my $name = $item->inputs()->[0]->value();
    if ($name eq '_complete') { $complete_method = $item; last; }
}
ok(defined $complete_method, '_complete method found') or BAIL_OUT('No _complete method');

# Emit _complete with cfg_lookup populated
my $method_lines = eval { $xs->_emit_xs_method($complete_method) };
ok(defined $method_lines, '_emit_xs_method succeeds') or BAIL_OUT("Emit failed: $@");

my $xs_output = join("\n", $method_lines->@*);

# Check for NULL unsupported markers
my @null_markers;
while ($xs_output =~ /(NULL \/\* unsupported \*\/)/g) {
    push @null_markers, $1;
}

# Check for unknown node markers
my @unknown_markers;
while ($xs_output =~ /(\/\* unknown node \*\/)/g) {
    push @unknown_markers, $1;
}

is(scalar @null_markers, 0, '_complete has no NULL unsupported markers');
is(scalar @unknown_markers, 0, '_complete has no unknown node markers');

# Verify _needs_eval_fallback returns false
ok(!$xs->_needs_eval_fallback($xs_output), '_complete does not need eval_pv fallback');

# Full integration: generate distribution and verify _complete is native XSUB
my $xs2 = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatchFull');
my $dist = eval { $xs2->generate_distribution_with_cfg($ir, $sa, $ctx) };
ok(ref($dist) eq 'HASH', 'XS distribution generated');

my ($xs_file) = grep { /\.xs$/ } sort keys $dist->%*;
my $xs_code = $dist->{$xs_file};

# _complete should be a native XSUB
like($xs_code, qr/^_complete\(self[,)]/m, '_complete is a native XSUB');

# _complete should NOT have an eval_pv fallback stub
unlike($xs_code, qr/eval_pv\("sub [^"]+::_complete\s*\{/, '_complete has no eval_pv fallback stub');

done_testing();
