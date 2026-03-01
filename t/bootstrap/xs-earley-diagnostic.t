# ABOUTME: Diagnostic test for Earley.pm XS compilation.
# ABOUTME: Reports which methods compile natively vs fall back to eval_pv stubs.
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

# Set up grammar pipeline
my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSEarleyDiag') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# Parse Earley.pm
my ($ir, $sa, $sem_ctx) = eval { parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed: $@");

# Generate XS with cfg support
my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Chalk::Bootstrap::XS::Diag::Earley',
);

my $dist;
eval {
    $dist = $xs_target->generate_distribution_with_cfg($ir, $sa, $sem_ctx);
};
ok(ref($dist) eq 'HASH', 'XS distribution generated') or BAIL_OUT("XS gen failed: $@");

# Find the .xs file
my ($xs_file) = grep { /\.xs$/ } sort keys $dist->%*;
ok(defined $xs_file, 'XS file found in distribution') or BAIL_OUT("No .xs file");

my $xs_code = $dist->{$xs_file};

# Find all XSUB method declarations (lines like "method_name(self, ...)" or "method_name(self)")
my @native_methods;
while ($xs_code =~ /^(\w+)\(self[,)]/mg) {
    push @native_methods, $1;
}

# Find fallback methods in BOOT block (eval_pv stubs)
# Pattern: sub Namespace::method_name {
my @fallback_methods;
while ($xs_code =~ /eval_pv\("sub [^"]+::(\w+)\s*\{/g) {
    push @fallback_methods, $1;
}

# Report
diag "";
diag "=== Earley.pm XS Compilation Report ===";
diag "";
diag "Native XSUB methods (" . scalar(@native_methods) . "):";
for my $m (sort @native_methods) {
    diag "  [NATIVE] $m";
}
diag "";
diag "Fallback eval_pv methods (" . scalar(@fallback_methods) . "):";
for my $m (sort @fallback_methods) {
    diag "  [FALLBACK] $m";
}
diag "";

# Check for eval_pv calls in native XSUBs (working but non-native builtins)
my ($pre_boot) = $xs_code =~ /^(.*?)BOOT:/s;
if (defined $pre_boot) {
    my @eval_pv_calls;
    while ($pre_boot =~ /eval_pv\("([^"]{0,80})/g) {
        push @eval_pv_calls, $1;
    }
    if (@eval_pv_calls) {
        diag "eval_pv calls in native XSUBs (working but delegated):";
        for my $e (@eval_pv_calls) {
            diag "  $e";
        }
        diag "";
    }
}

# Per-method analysis using generate_distribution_with_cfg output
# The cfg_lookup is populated after generate_distribution_with_cfg
my $class_decl;
for my $item ($ir->inputs()->[0]->@*) {
    if ($item isa Chalk::Bootstrap::IR::Node::Constructor && $item->class() eq 'ClassDecl') {
        $class_decl = $item;
        last;
    }
}

if (defined $class_decl) {
    my $body = $class_decl->inputs()->[2];
    my %is_fallback = map { $_ => 1 } @fallback_methods;

    diag "=== Per-Method Blocker Analysis (fallback methods) ===";
    for my $item ($body->@*) {
        next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
        next unless $item->class() eq 'MethodDecl';
        my $name = $item->inputs()->[0]->value();
        next unless $is_fallback{$name};

        # Try to emit with cfg_lookup available
        my $method_lines = eval { $xs_target->_emit_xs_method($item) };
        if ($@) {
            diag "  $name: EMIT ERROR: $@";
            next;
        }
        my $method_xs = join("\n", $method_lines->@*);

        my @issues;
        while ($method_xs =~ /(NULL \/\* [^*]+\*\/)/g) {
            push @issues, $1;
        }
        while ($method_xs =~ /(\/\* unknown node[^*]*\*\/)/g) {
            push @issues, $1;
        }
        diag "  $name: " . scalar(@issues) . " blocker(s)";
        for my $issue (@issues) {
            diag "    $issue";
        }
    }
}

# Assertions: track progress toward all-native goal
ok(scalar(@native_methods) >= 6, 'at least 6 methods compile natively');
is(scalar(@fallback_methods), 7, '7 methods still need fallback');

# Track specific methods we expect to be native
for my $expected (qw(gc_stats _chart_set _make_item parse_value _predict _scan _advance_from_completed)) {
    ok((grep { $_ eq $expected } @native_methods), "$expected compiles natively");
}

# Track which methods we're working to make native
for my $target (qw(_chart_has _chart_get _symbol_after_dot _is_complete _run_parse parse _complete)) {
    TODO: {
        local $TODO = "Phase 1-7: implement missing XS constructs";
        ok((grep { $_ eq $target } @native_methods), "$target compiles natively");
    }
}

done_testing();
