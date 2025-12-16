# ABOUTME: Tests for Chalk::Grammar::Chalk::TypeInference module
# ABOUTME: Validates Chalk/Perl-specific type inference rules for operations

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use_ok('Chalk::Grammar::Chalk::TypeInference');
use_ok('Chalk::Grammar::Chalk::Type::Int');
use_ok('Chalk::Grammar::Chalk::Type::Num');
use_ok('Chalk::Grammar::Chalk::Type::Str');
use_ok('Chalk::Grammar::Chalk::Type::Boolean');
use_ok('Chalk::Grammar::Chalk::Type::Any');

my $inference = Chalk::Grammar::Chalk::TypeInference->new();
isa_ok($inference, 'Chalk::Grammar::Chalk::TypeInference');

subtest 'Arithmetic operations' => sub {
    my $int = Chalk::Grammar::Chalk::Type::Int->new();
    my $num = Chalk::Grammar::Chalk::Type::Num->new();

    # Int + Int = Int
    my $int_plus_int = $inference->infer_binary_op('+', $int, $int);
    isa_ok($int_plus_int, 'Chalk::Grammar::Chalk::Type::Int', 'Int + Int = Int');

    # Int - Int = Int
    my $int_minus_int = $inference->infer_binary_op('-', $int, $int);
    isa_ok($int_minus_int, 'Chalk::Grammar::Chalk::Type::Int', 'Int - Int = Int');

    # Int * Int = Int
    my $int_times_int = $inference->infer_binary_op('*', $int, $int);
    isa_ok($int_times_int, 'Chalk::Grammar::Chalk::Type::Int', 'Int * Int = Int');

    # Int + Num = Num
    my $int_plus_num = $inference->infer_binary_op('+', $int, $num);
    isa_ok($int_plus_num, 'Chalk::Grammar::Chalk::Type::Num', 'Int + Num = Num');

    # Num + Int = Num
    my $num_plus_int = $inference->infer_binary_op('+', $num, $int);
    isa_ok($num_plus_int, 'Chalk::Grammar::Chalk::Type::Num', 'Num + Int = Num');

    # Num + Num = Num
    my $num_plus_num = $inference->infer_binary_op('+', $num, $num);
    isa_ok($num_plus_num, 'Chalk::Grammar::Chalk::Type::Num', 'Num + Num = Num');
};

subtest 'Division always yields Num' => sub {
    my $int = Chalk::Grammar::Chalk::Type::Int->new();
    my $num = Chalk::Grammar::Chalk::Type::Num->new();

    # Int / Int = Num (division can yield fractions)
    my $int_div_int = $inference->infer_binary_op('/', $int, $int);
    isa_ok($int_div_int, 'Chalk::Grammar::Chalk::Type::Num', 'Int / Int = Num');

    # Int / Num = Num
    my $int_div_num = $inference->infer_binary_op('/', $int, $num);
    isa_ok($int_div_num, 'Chalk::Grammar::Chalk::Type::Num', 'Int / Num = Num');

    # Num / Int = Num
    my $num_div_int = $inference->infer_binary_op('/', $num, $int);
    isa_ok($num_div_int, 'Chalk::Grammar::Chalk::Type::Num', 'Num / Int = Num');

    # Num / Num = Num
    my $num_div_num = $inference->infer_binary_op('/', $num, $num);
    isa_ok($num_div_num, 'Chalk::Grammar::Chalk::Type::Num', 'Num / Num = Num');
};

subtest 'String concatenation yields Str' => sub {
    my $int = Chalk::Grammar::Chalk::Type::Int->new();
    my $num = Chalk::Grammar::Chalk::Type::Num->new();
    my $str = Chalk::Grammar::Chalk::Type::Str->new();

    # Str . Str = Str
    my $str_concat_str = $inference->infer_binary_op('.', $str, $str);
    isa_ok($str_concat_str, 'Chalk::Grammar::Chalk::Type::Str', 'Str . Str = Str');

    # Int . Str = Str (Int coerces to Str)
    my $int_concat_str = $inference->infer_binary_op('.', $int, $str);
    isa_ok($int_concat_str, 'Chalk::Grammar::Chalk::Type::Str', 'Int . Str = Str');

    # Num . Str = Str
    my $num_concat_str = $inference->infer_binary_op('.', $num, $str);
    isa_ok($num_concat_str, 'Chalk::Grammar::Chalk::Type::Str', 'Num . Str = Str');
};

subtest 'Comparison operators yield Boolean' => sub {
    my $int = Chalk::Grammar::Chalk::Type::Int->new();
    my $str = Chalk::Grammar::Chalk::Type::Str->new();

    # Numeric comparisons
    my $eq = $inference->infer_binary_op('==', $int, $int);
    isa_ok($eq, 'Chalk::Grammar::Chalk::Type::Boolean', '== yields Boolean');

    my $ne = $inference->infer_binary_op('!=', $int, $int);
    isa_ok($ne, 'Chalk::Grammar::Chalk::Type::Boolean', '!= yields Boolean');

    my $lt = $inference->infer_binary_op('<', $int, $int);
    isa_ok($lt, 'Chalk::Grammar::Chalk::Type::Boolean', '< yields Boolean');

    my $gt = $inference->infer_binary_op('>', $int, $int);
    isa_ok($gt, 'Chalk::Grammar::Chalk::Type::Boolean', '> yields Boolean');

    my $le = $inference->infer_binary_op('<=', $int, $int);
    isa_ok($le, 'Chalk::Grammar::Chalk::Type::Boolean', '<= yields Boolean');

    my $ge = $inference->infer_binary_op('>=', $int, $int);
    isa_ok($ge, 'Chalk::Grammar::Chalk::Type::Boolean', '>= yields Boolean');

    # String comparisons
    my $str_eq = $inference->infer_binary_op('eq', $str, $str);
    isa_ok($str_eq, 'Chalk::Grammar::Chalk::Type::Boolean', 'eq yields Boolean');

    my $str_ne = $inference->infer_binary_op('ne', $str, $str);
    isa_ok($str_ne, 'Chalk::Grammar::Chalk::Type::Boolean', 'ne yields Boolean');

    my $str_lt = $inference->infer_binary_op('lt', $str, $str);
    isa_ok($str_lt, 'Chalk::Grammar::Chalk::Type::Boolean', 'lt yields Boolean');

    my $str_gt = $inference->infer_binary_op('gt', $str, $str);
    isa_ok($str_gt, 'Chalk::Grammar::Chalk::Type::Boolean', 'gt yields Boolean');

    my $str_le = $inference->infer_binary_op('le', $str, $str);
    isa_ok($str_le, 'Chalk::Grammar::Chalk::Type::Boolean', 'le yields Boolean');

    my $str_ge = $inference->infer_binary_op('ge', $str, $str);
    isa_ok($str_ge, 'Chalk::Grammar::Chalk::Type::Boolean', 'ge yields Boolean');
};

subtest 'Unknown operators yield Any' => sub {
    my $int = Chalk::Grammar::Chalk::Type::Int->new();

    # Unknown operator
    my $unknown = $inference->infer_binary_op('???', $int, $int);
    isa_ok($unknown, 'Chalk::Grammar::Chalk::Type::Any', 'Unknown operator yields Any');
};

done_testing();
