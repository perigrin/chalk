# ABOUTME: Tests for type coercion rules (to Num, to Str, to Bool)
# ABOUTME: Validates coercion behavior per formal spec in Issue #74 Phase 4

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Coercion;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Boolean;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Undef;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Ref;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::ArrayRef;

subtest 'Numeric coercion (to_num) - identity cases' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    # Numbers remain unchanged
    is($coercer->to_num(42, Chalk::Grammar::Chalk::Type::Int->new()), 42,
       'Integer 42 remains 42');
    is($coercer->to_num(3.14, Chalk::Grammar::Chalk::Type::Num->new()), 3.14,
       'Float 3.14 remains 3.14');
};

subtest 'Numeric coercion (to_num) - string to number' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    # Valid numeric strings parse
    is($coercer->to_num("42", Chalk::Grammar::Chalk::Type::Str->new()), 42,
       '"42" coerces to 42');
    is($coercer->to_num("3.14", Chalk::Grammar::Chalk::Type::Str->new()), 3.14,
       '"3.14" coerces to 3.14');
    is($coercer->to_num("  123  ", Chalk::Grammar::Chalk::Type::Str->new()), 123,
       '"  123  " coerces to 123 (trimmed)');
    is($coercer->to_num("42.5e2", Chalk::Grammar::Chalk::Type::Str->new()), 4250,
       '"42.5e2" coerces to 4250 (scientific notation)');

    # Invalid strings become 0
    is($coercer->to_num("hello", Chalk::Grammar::Chalk::Type::Str->new()), 0,
       '"hello" coerces to 0');
    is($coercer->to_num("abc123", Chalk::Grammar::Chalk::Type::Str->new()), 0,
       '"abc123" coerces to 0');
    is($coercer->to_num("", Chalk::Grammar::Chalk::Type::Str->new()), 0,
       'Empty string coerces to 0');
};

subtest 'Numeric coercion (to_num) - undef to number' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    is($coercer->to_num(undef, Chalk::Grammar::Chalk::Type::Undef->new()), 0,
       'undef coerces to 0');
};

subtest 'Numeric coercion (to_num) - reference to number' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    # References coerce to memory addresses (implementation-dependent)
    # We'll test that it returns a number, not the exact value
    my $arr_ref = [];
    my $result = $coercer->to_num($arr_ref, Chalk::Grammar::Chalk::Type::ArrayRef->new());

    like($result, qr/^\d+$/, 'ArrayRef coerces to numeric address');
};

subtest 'String coercion (to_str) - identity cases' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    # Strings remain unchanged
    is($coercer->to_str("hello", Chalk::Grammar::Chalk::Type::Str->new()), "hello",
       '"hello" remains "hello"');
    is($coercer->to_str("", Chalk::Grammar::Chalk::Type::Str->new()), "",
       'Empty string remains empty');
};

subtest 'String coercion (to_str) - number to string' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    is($coercer->to_str(42, Chalk::Grammar::Chalk::Type::Int->new()), "42",
       '42 coerces to "42"');
    is($coercer->to_str(3.14, Chalk::Grammar::Chalk::Type::Num->new()), "3.14",
       '3.14 coerces to "3.14"');
    is($coercer->to_str(0, Chalk::Grammar::Chalk::Type::Int->new()), "0",
       '0 coerces to "0"');
};

subtest 'String coercion (to_str) - undef to string' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    is($coercer->to_str(undef, Chalk::Grammar::Chalk::Type::Undef->new()), "",
       'undef coerces to empty string');
};

subtest 'String coercion (to_str) - reference to string' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    my $arr_ref = [];
    my $result = $coercer->to_str($arr_ref, Chalk::Grammar::Chalk::Type::ArrayRef->new());

    like($result, qr/^ARRAY\(0x[0-9a-fA-F]+\)$/,
         'ArrayRef coerces to "ARRAY(0x...)"');
};

subtest 'Boolean coercion (to_bool) - identity cases' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    # Perl 5.36+ true/false literals
    ok($coercer->to_bool(1, Chalk::Grammar::Chalk::Type::Boolean->new()),
       'true remains truthy');
    ok(!$coercer->to_bool(0, Chalk::Grammar::Chalk::Type::Boolean->new()),
       'false remains falsy');
};

subtest 'Boolean coercion (to_bool) - falsy values' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    # 0, '', undef are falsy
    ok(!$coercer->to_bool(0, Chalk::Grammar::Chalk::Type::Int->new()),
       '0 is falsy');
    ok(!$coercer->to_bool('', Chalk::Grammar::Chalk::Type::Str->new()),
       'Empty string is falsy');
    ok(!$coercer->to_bool(undef, Chalk::Grammar::Chalk::Type::Undef->new()),
       'undef is falsy');
    ok(!$coercer->to_bool("0", Chalk::Grammar::Chalk::Type::Str->new()),
       '"0" is falsy');
};

subtest 'Boolean coercion (to_bool) - truthy values' => sub {
    my $coercer = Chalk::Grammar::Chalk::Type::Coercion->new();

    # All other values are truthy
    ok($coercer->to_bool(1, Chalk::Grammar::Chalk::Type::Int->new()),
       '1 is truthy');
    ok($coercer->to_bool(42, Chalk::Grammar::Chalk::Type::Int->new()),
       '42 is truthy');
    ok($coercer->to_bool("hello", Chalk::Grammar::Chalk::Type::Str->new()),
       '"hello" is truthy');
    ok($coercer->to_bool("0.0", Chalk::Grammar::Chalk::Type::Str->new()),
       '"0.0" is truthy (not string "0")');

    my $ref = [];
    ok($coercer->to_bool($ref, Chalk::Grammar::Chalk::Type::ArrayRef->new()),
       'References are truthy');
};

done_testing();
