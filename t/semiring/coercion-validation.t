# ABOUTME: Test coercion validation using Coercion infrastructure
# ABOUTME: Validates Phase 3 of #433 - context-triggered coercion validation

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar::Chalk::Type::Coercion;
use Chalk::Grammar::Chalk::TypeLattice;

# Create lattice and coercion instances
my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
my $coercion = Chalk::Grammar::Chalk::Type::Coercion->new();

subtest 'Valid numeric coercion: Str to Num' => sub {
    my $str_type = $lattice->type_from_name('Str');

    # Numeric string coerces to number
    my $result = eval { $coercion->to_num("42", $str_type) };
    ok(defined($result), "String '42' coerces to Num");
    is($result, 42, "Coercion produces correct numeric value");

    # Non-numeric string coerces to 0 with warning
    my $result2 = eval { $coercion->to_num("hello", $str_type) };
    ok(defined($result2), "String 'hello' coerces to Num");
    is($result2, 0, "Non-numeric string coerces to 0");
};

subtest 'Valid string coercion: Num to Str' => sub {
    my $num_type = $lattice->type_from_name('Num');
    my $int_type = $lattice->type_from_name('Int');

    # Number coerces to string
    my $result = eval { $coercion->to_str(42, $int_type) };
    ok(defined($result), "Int 42 coerces to Str");
    is($result, "42", "Coercion produces correct string value");

    # Float coerces to string
    my $result2 = eval { $coercion->to_str(3.14, $num_type) };
    ok(defined($result2), "Num 3.14 coerces to Str");
    is($result2, "3.14", "Float coercion produces correct string value");
};

subtest 'CodeRef to Num coerces to memory address' => sub {
    my $coderef_type = $lattice->type_from_name('CodeRef');
    my $dummy_coderef = sub { };

    my $result = eval { $coercion->to_num($dummy_coderef, $coderef_type) };
    my $error = $@;

    ok(!$error, "CodeRef coercion to Num succeeds");
    ok(defined($result), "Result is defined");
    ok($result > 0, "Coercion produces memory address");
};

subtest 'Undef coercion to Num' => sub {
    my $undef_type = $lattice->type_from_name('Undef');

    my $result = eval { $coercion->to_num(undef, $undef_type) };
    ok(defined($result), "Undef coerces to Num");
    is($result, 0, "Undef coerces to 0");
};

subtest 'Undef coercion to Str' => sub {
    my $undef_type = $lattice->type_from_name('Undef');

    my $result = eval { $coercion->to_str(undef, $undef_type) };
    ok(defined($result), "Undef coerces to Str");
    is($result, "", "Undef coerces to empty string");
};

# done_testing handled by defer at top
