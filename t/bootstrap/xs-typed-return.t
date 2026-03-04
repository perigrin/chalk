# ABOUTME: Tests that TypeInference return types flow through Actions.pm into IR MethodDecl nodes.
# ABOUTME: Verifies the pipeline from TI method_return_type to IR return_type to XS C type mapping.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::IR::Node::Constructor;
use Chalk::Bootstrap::IR::Node::Constant;
use File::Temp qw(tempfile);

# --- Helper: parse source, extract IR, find MethodDecl return_type ---
sub parse_and_get_return_type($source, $method_name) {
    my ($fh, $filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
    print $fh $source;
    close $fh;

    my $gen_grammar = setup_xs_grammar(
        'Chalk::Grammar::Perl::XSTypedReturnTest' . int(rand(100000))
    );
    my ($ir, $sa, $sem_ctx) = parse_file_ir($gen_grammar, $filename);
    return (undef, undef, undef) unless defined $ir;

    # Walk IR to find MethodDecl with the given name
    my @stack = ref($ir) eq 'ARRAY' ? $ir->@* : ($ir);
    while (@stack) {
        my $node = pop @stack;
        next unless defined $node;
        if ($node isa Chalk::Bootstrap::IR::Node::Constructor
                && $node->class() eq 'MethodDecl') {
            my $name_node = $node->inputs()->[0];
            if (defined $name_node
                    && $name_node isa Chalk::Bootstrap::IR::Node::Constant
                    && $name_node->value() eq $method_name) {
                # return_type is inputs->[3]
                my $rt_node = $node->inputs()->[3];
                my $rt = defined $rt_node ? $rt_node->value() : undef;
                return ($rt, $ir, $sa, $sem_ctx);
            }
        }
        if ($node isa Chalk::Bootstrap::IR::Node) {
            for my $input ($node->inputs()->@*) {
                if (ref($input) eq 'ARRAY') {
                    push @stack, $input->@*;
                } else {
                    push @stack, $input;
                }
            }
        }
    }
    return (undef, $ir, $sa, $sem_ctx);
}

# ===========================================================
# Test 1: Method returning integer literal → return_type 'Int'
# ===========================================================
{
    my $source = q{use 5.42.0;
use utf8;

class IntReturn {
    method get_count() {
        return 42;
    }
}
};
    my ($rt, $ir) = parse_and_get_return_type($source, 'get_count');
    ok(defined $ir, 'Int return: parse produces IR');
    is($rt, 'Int', 'Int return: MethodDecl return_type is Int');
}

# ===========================================================
# Test 2: Method returning string literal → return_type 'Str'
# ===========================================================
{
    my $source = q{use 5.42.0;
use utf8;

class StrReturn {
    method get_name() {
        return "hello";
    }
}
};
    my ($rt, $ir) = parse_and_get_return_type($source, 'get_name');
    ok(defined $ir, 'Str return: parse produces IR');
    is($rt, 'Str', 'Str return: MethodDecl return_type is Str');
}

# ===========================================================
# Test 3: Method with assignment body → TI infers last expr type
# ===========================================================
# TI uses _get_rightmost_type which picks up the type of the last expression.
# In Perl, assignments return the assigned value, so `$x = 1` has type Int.
# This verifies TI's implicit-return type inference.
{
    my $source = q{use 5.42.0;
use utf8;

class ImplicitReturn {
    field $x :param;

    method set_x() {
        $x = 1;
    }
}
};
    my ($rt, $ir) = parse_and_get_return_type($source, 'set_x');
    ok(defined $ir, 'Implicit return: parse produces IR');
    is($rt, 'Int', 'Implicit return: assignment body gets Int from TI');
}

# ===========================================================
# Test 4: Method returning boolean expression → return_type 'Bool'
# ===========================================================
{
    my $source = q{use 5.42.0;
use utf8;

class BoolReturn {
    field $x :param;

    method is_valid() {
        return defined($x);
    }
}
};
    my ($rt, $ir) = parse_and_get_return_type($source, 'is_valid');
    ok(defined $ir, 'Bool return: parse produces IR');
    is($rt, 'Bool', 'Bool return: MethodDecl return_type is Bool');
}

# ===========================================================
# Test 5: XS emitter uses _xs_c_type_for (SV* for non-void, void for Void)
# ===========================================================
{
    my $source = q{use 5.42.0;
use utf8;

class XSTypeTest {
    method get_int() {
        return 1;
    }

    method get_str() {
        return "hello";
    }
}
};
    my ($fh, $filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
    print $fh $source;
    close $fh;

    my $gen_grammar = setup_xs_grammar(
        'Chalk::Grammar::Perl::XSTypedReturnXSTest' . int(rand(100000))
    );
    my ($ir, $sa, $sem_ctx) = parse_file_ir($gen_grammar, $filename);
    ok(defined $ir, 'XS type test: parse produces IR');

    SKIP: {
        skip 'no IR', 2 unless defined $ir;

        my $target = Chalk::Bootstrap::Perl::Target::XS->new(
            module_name => 'XSTypeTest',
        );
        my $xs_output = $target->generate_with_cfg($ir, $sa, $sem_ctx);

        # get_int returns Int → SV * return type
        like($xs_output, qr/^SV \*\nget_int\(/m,
            'XS: Int method has SV * return type');

        # get_str returns Str → SV * return type
        like($xs_output, qr/^SV \*\nget_str\(/m,
            'XS: Str method has SV * return type');
    }
}

done_testing;
