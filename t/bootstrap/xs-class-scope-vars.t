# ABOUTME: Tests that class-scope lexicals compile as static C variables in XS.
# ABOUTME: Verifies VarDecl parsing, static emission, refaddr intrinsic, and runtime correctness.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

use lib 'lib';
use lib 't/bootstrap/lib';

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

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Semiring::Boolean;

# ==========================================================
# Part 1: VarDecl merging fix — SemanticAction must have all
# 6 class-scope VarDecl nodes preserved (not merged with
# following SubDecl/VarDecl).
# ==========================================================

my $gen_sa = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSClassScopeVarDecl') };
ok(defined $gen_sa, 'grammar pipeline setup for SemanticAction')
    or BAIL_OUT("Cannot continue: $@");

my ($ir_sa, $sa_sa, $ctx_sa) = eval {
    parse_file_ir($gen_sa, 'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm');
};
ok(defined $ir_sa, 'SemanticAction parses to IR')
    or BAIL_OUT("Parse failed: $@");

# Walk the IR tree and count class-body VarDecl nodes.
# SemanticAction has 6 class-scope `my` variables:
#   %_ctx_cache, %_cfg_state, $_pending_cfg_update,
#   $_current_instance, $_type_context, $_one_singleton
my @var_decls;
my $walk_ir;
$walk_ir = sub ($node) {
    return unless defined $node;
    if ($node isa Chalk::Bootstrap::IR::Node::Constructor
            && $node->class() eq 'VarDecl') {
        my $var_node = $node->inputs()->[0];
        push @var_decls, $var_node->value() if defined $var_node;
    }
    if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
        for my $input ($node->inputs()->@*) {
            if (ref($input) eq 'ARRAY') {
                $walk_ir->($_) for $input->@*;
            } elsif (ref($input)) {
                $walk_ir->($input);
            }
        }
    }
};

# Walk from the class body (skip into ClassDecl)
my @class_body_var_decls;
my $find_class_vars;
$find_class_vars = sub ($node) {
    return unless defined $node;
    if ($node isa Chalk::Bootstrap::IR::Node::Constructor
            && $node->class() eq 'ClassDecl') {
        # Class body is in inputs — find VarDecl children
        my $body = $node->inputs()->[-1];
        if (ref($body) eq 'ARRAY') {
            for my $item ($body->@*) {
                next unless defined $item;
                if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                        && $item->class() eq 'VarDecl') {
                    my $var_node = $item->inputs()->[0];
                    push @class_body_var_decls, $var_node->value()
                        if defined $var_node;
                }
            }
        }
        return;
    }
    if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
        for my $input ($node->inputs()->@*) {
            if (ref($input) eq 'ARRAY') {
                $find_class_vars->($_) for $input->@*;
            } elsif (ref($input)) {
                $find_class_vars->($input);
            }
        }
    }
};
$find_class_vars->($ir_sa);

# SemanticAction should have 6 class-scope VarDecl nodes
cmp_ok(scalar @class_body_var_decls, '>=', 6,
    "SemanticAction has >= 6 class-body VarDecl nodes (got " .
    scalar(@class_body_var_decls) . ": " .
    join(', ', @class_body_var_decls) . ")");

# Verify specific variables are all present
my %var_names = map { $_ => 1 } @class_body_var_decls;
for my $expected (qw(%_ctx_cache %_cfg_state $_pending_cfg_update
                     $_current_instance $_type_context $_one_singleton)) {
    ok(exists $var_names{$expected},
        "VarDecl for $expected preserved in IR");
}

# ==========================================================
# Part 2: Static C variable emission — class-scope vars
# should appear as static declarations, not eval_pv fallback.
# ==========================================================

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSClassScope2') };
ok(defined $gen, 'grammar pipeline setup for Boolean')
    or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm');
};
ok(defined $ir, 'Boolean parses to IR') or BAIL_OUT("Parse failed: $@");

my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
$reg->register('Chalk::Bootstrap::Semiring::Boolean', {
    ir => $ir, sa => $sa, ctx => $ctx, uses => [],
});

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSClassScope',
    class_registry => $reg,
);

my @entries = ({
    class_name => 'Chalk::Bootstrap::Semiring::Boolean',
    ir => $ir, sa => $sa, ctx => $ctx,
});

my $dist = eval { $xs->generate_distribution_multi_class(\@entries) };
ok(defined $dist, 'distribution generated') or BAIL_OUT("Dist gen failed: $@");

my $xs_text = $dist->{'lib/Test/XSClassScope.xs'};
ok(defined $xs_text, 'XS text present in dist');

# Boolean has `my $ZERO = []` at class scope.
# After this change, it should appear as a static SV* declaration.
like($xs_text, qr/static\s+SV\s*\*\s*_csv_.*ZERO/,
    'XS contains static SV* declaration for $ZERO');

# The static should be initialized in BOOT
like($xs_text, qr/BOOT:.*_csv_.*ZERO/s,
    'BOOT block initializes $ZERO static');

# Methods that previously fell back due to class-scope vars
# should now compile to _impl_ helpers (not eval_pv)
# Boolean::zero() references $ZERO directly
like($xs_text, qr/_impl_.*_zero/,
    'zero() compiled to _impl_ helper (not fallback)');

# ==========================================================
# Part 3: refaddr intrinsic — should compile to PTR2UV
# ==========================================================

# Parse SemanticAction which uses refaddr() extensively
my $reg2 = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
$reg2->register('Chalk::Bootstrap::Semiring::SemanticAction', {
    ir => $ir_sa, sa => $sa_sa, ctx => $ctx_sa, uses => [],
});

my $xs2 = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSRefaddr',
    class_registry => $reg2,
);

my @entries2 = ({
    class_name => 'Chalk::Bootstrap::Semiring::SemanticAction',
    ir => $ir_sa, sa => $sa_sa, ctx => $ctx_sa,
});

my $dist2 = eval { $xs2->generate_distribution_multi_class(\@entries2) };
ok(defined $dist2, 'SemanticAction distribution generated')
    or BAIL_OUT("Dist gen failed: $@");

my $xs_text2 = $dist2->{'lib/Test/XSRefaddr.xs'};
ok(defined $xs_text2, 'SemanticAction XS text present');

# refaddr() calls should compile to PTR2UV, not eval_pv("refaddr(...)")
like($xs_text2, qr/PTR2UV\(SvRV\(/,
    'refaddr compiles to PTR2UV(SvRV(...))');

# Should NOT have eval_pv("refaddr(...)") patterns
unlike($xs_text2, qr/eval_pv\("refaddr/,
    'no eval_pv fallback for refaddr calls');

# ==========================================================
# Part 4: Runtime correctness — Boolean with static vars
# ==========================================================

my $tmpdir = tempdir(CLEANUP => 1);
for my $path (sort keys $dist->%*) {
    my $full_path = "$tmpdir/$path";
    make_path(dirname($full_path)) unless -d dirname($full_path);
    open(my $wfh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
    print $wfh $dist->{$path};
    close $wfh;
}

{
    my $output = `cd "$tmpdir" && "$^X" -Ilib Build.PL 2>&1`;
    is($? >> 8, 0, 'Build.PL succeeds') or BAIL_OUT("Build.PL failed: $output");
}
{
    my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
    my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
    is($? >> 8, 0, 'Build succeeds') or BAIL_OUT("Build failed: $output");
}

unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
eval { require Test::XSClassScope };
is($@, '', 'XS loads') or BAIL_OUT("Load failed: $@");

# Boolean has `my $ZERO = []` at class scope. After XS override,
# zero() must still return an arrayref (not undef), and is_zero()
# must correctly detect it.
my $bool = Chalk::Bootstrap::Semiring::Boolean->new();

my $zero = $bool->zero();
ok(defined $zero, 'Boolean::zero() returns a defined value');
ok(ref($zero), 'Boolean::zero() returns a reference');

my $iz = $bool->is_zero($zero);
ok($iz, 'Boolean::is_zero(zero()) returns true');

my $one = $bool->one();
ok(!$bool->is_zero($one), 'Boolean::is_zero(one()) returns false');

my $mul = $bool->multiply($one, $one);
ok(!$bool->is_zero($mul), 'multiply(one, one) is not zero');

my $mul_z = $bool->multiply($zero, $one);
ok($bool->is_zero($mul_z), 'multiply(zero, one) is zero');

done_testing();
