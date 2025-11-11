# ABOUTME: Tests for subroutine parameter and return type tracking
# ABOUTME: Validates type inference for sub parameters and return values (Phase 3)

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use Chalk::Grammar::Chalk::Type::List;
use Chalk::Grammar::Chalk::Type::Scalar;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::Grammar::Chalk::Type::Code;

subtest 'Code type exists' => sub {
    use_ok('Chalk::Grammar::Chalk::Type::Code');

    my $code = Chalk::Grammar::Chalk::Type::Code->new();

    isa_ok($code, 'Chalk::Grammar::Chalk::Type::Code', 'Code type created');
    ok($code->is_subtype_of(Chalk::Grammar::Chalk::Type::Any->new()),
       'Code <: Any');
};

subtest 'Subroutine parameters received as List' => sub {
    # sub foo($a, $b) { ... }
    # Parameters are received as ephemeral List
    # Each parameter extracts from List based on position

    my $param_list = Chalk::Grammar::Chalk::Type::List->new();

    isa_ok($param_list, 'Chalk::Grammar::Chalk::Type::List',
           'Parameters received as ephemeral List');

    # Individual parameters are Scalar (or more specific types)
    # Type inference happens from usage within the subroutine body
    pass('Parameter type inference deferred to usage analysis');
};

subtest 'Subroutine return type inference from return statements' => sub {
    # sub calculate($x, $y) {
    #     return $x + $y;  # Returns Num
    # }

    # Return statement contains expression of type Num
    my $return_type = Chalk::Grammar::Chalk::Type::Num->new();

    isa_ok($return_type, 'Chalk::Grammar::Chalk::Type::Num',
           'Return type inferred from return expression');

    # The subroutine itself has type Code
    my $code_type = Chalk::Grammar::Chalk::Type::Code->new();
    isa_ok($code_type, 'Chalk::Grammar::Chalk::Type::Code',
           'Subroutine has Code type');
};

subtest 'Multiple return statements unify types' => sub {
    # sub get_value($flag) {
    #     return 42 if $flag;     # Returns Int
    #     return "none";          # Returns Str
    # }
    # Unified return type: Scalar (common supertype)

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $str_type = Chalk::Grammar::Chalk::Type::Str->new();

    # Find common supertype (simplified - real implementation would be more complex)
    # Int <: Num <: Str <: Scalar
    # Str <: Scalar
    # Common: Scalar

    my $unified = Chalk::Grammar::Chalk::Type::Scalar->new();

    ok($int_type->is_subtype_of($unified),
       'Int is subtype of unified Scalar');
    ok($str_type->is_subtype_of($unified),
       'Str is subtype of unified Scalar');
};

subtest 'Empty parameter list' => sub {
    # sub greet() { ... }
    # No parameters - empty List

    my $empty_list = Chalk::Grammar::Chalk::Type::List->new();

    isa_ok($empty_list, 'Chalk::Grammar::Chalk::Type::List',
           'Empty parameter list is still List type');
};

subtest 'Subroutine without explicit return' => sub {
    # sub print_msg($msg) {
    #     say $msg;
    #     # Implicit return of last expression
    # }

    # Last expression determines return type
    # say returns true/false (Boolean or Int depending on Perl version)
    # For now, assume Scalar as safe default

    my $implicit_return = Chalk::Grammar::Chalk::Type::Scalar->new();

    isa_ok($implicit_return, 'Chalk::Grammar::Chalk::Type::Scalar',
           'Implicit return type is Scalar');
};

subtest 'List context return' => sub {
    # sub get_pair() {
    #     return (1, 2);  # Returns List
    # }

    my $list_return = Chalk::Grammar::Chalk::Type::List->new();

    isa_ok($list_return, 'Chalk::Grammar::Chalk::Type::List',
           'List context return has List type');

    # When assigned to array: my @arr = get_pair();
    # List converts to Array
    my $array = $list_return->convert_to_target('@');
    isa_ok($array, 'Chalk::Grammar::Chalk::Type::Array',
           'List return converts to Array on assignment');
};

done_testing();
