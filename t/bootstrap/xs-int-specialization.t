# ABOUTME: Tests type-directed operator specialization for Int operands.
# ABOUTME: Validates that Int+Int emits SvIV/newSViv instead of SvNV/newSVnv.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Build IR: a class with a method that does integer arithmetic
# method add_one($self, $n) { return $n + 1; }
my $method = $factory->make('Constructor',
    class  => 'MethodDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'add_one'),
    params => [
        $factory->make('Constant', const_type => 'string', value => '$self'),
        $factory->make('Constant', const_type => 'string', value => '$n'),
    ],
    body   => [
        $factory->make('Constructor',
            class => 'ReturnStmt',
            value => $factory->make('Constructor',
                class => 'BinaryExpr',
                op    => $factory->make('Constant', const_type => 'string', value => '+'),
                left  => $factory->make('Constant', const_type => 'variable', value => '$n'),
                right => $factory->make('Constant', const_type => 'string', value => '1'),
            ),
        ),
    ],
    return_type => undef,
);

my $class_decl = $factory->make('Constructor',
    class  => 'ClassDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'Test::IntSpec'),
    parent => undef,
    body   => [$method],
);

my $program = $factory->make('Constructor',
    class      => 'Program',
    statements => [$class_decl],
);

my $target = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::IntSpec');
my $c_result = eval { $target->generate_c_files($program, undef, undef) };
ok(defined $c_result, 'generate_c_files succeeds') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

# Find the .c file and look at the add_one function
my ($c_file) = grep { /\.c$/ } keys $c_result->{files}->%*;
my $c_code = $c_result->{files}{$c_file};

# The binary expression $n + 1 should use SvIV/newSViv when the right
# operand is an integer literal. Currently it uses SvNV/newSVnv.
# After specialization: newSViv(SvIV(n) + 1) instead of newSVnv(SvNV(n) + SvNV(...))

# Test: the + operation in add_one should use integer arithmetic
# when one operand is a known integer literal
like($c_code, qr/newSViv.*\+/, 'Int + literal: uses newSViv for addition result');
unlike($c_code, qr/SvNV.*\+.*SvNV/, 'Int + literal: does not use SvNV for both operands');

done_testing();
