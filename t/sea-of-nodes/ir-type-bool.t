# ABOUTME: Unit tests for TypeBool IR type
# ABOUTME: Tests native bool type using builtin::true/builtin::false

use lib 'lib';
use v5.42;
use experimental qw(builtin);
use Test::More;
use builtin qw(true false is_bool);
use Scalar::Util qw(refaddr);

use_ok('Chalk::IR::Type::TypeBool');

subtest 'TypeBool TRUE singleton' => sub {
    my $true1 = Chalk::IR::Type::TypeBool->TRUE;
    my $true2 = Chalk::IR::Type::TypeBool->TRUE;

    ok($true1, 'TRUE returns a value');
    is(refaddr($true1), refaddr($true2), 'TRUE returns same singleton');
    ok($true1 isa Chalk::IR::Type::TypeBool, 'TRUE is a TypeBool');
    ok($true1->is_constant, 'TRUE is constant');
    ok(is_bool($true1->value), 'TRUE value is native bool');
    ok($true1->value, 'TRUE value is truthy');
};

subtest 'TypeBool FALSE singleton' => sub {
    my $false1 = Chalk::IR::Type::TypeBool->FALSE;
    my $false2 = Chalk::IR::Type::TypeBool->FALSE;

    ok(defined($false1), 'FALSE returns a value');
    is(refaddr($false1), refaddr($false2), 'FALSE returns same singleton');
    ok($false1 isa Chalk::IR::Type::TypeBool, 'FALSE is a TypeBool');
    ok($false1->is_constant, 'FALSE is constant');
    ok(is_bool($false1->value), 'FALSE value is native bool');
    ok(!$false1->value, 'FALSE value is falsy');
};

subtest 'TypeBool constant() factory' => sub {
    my $from_true = Chalk::IR::Type::TypeBool->constant(1);
    my $from_false = Chalk::IR::Type::TypeBool->constant(0);

    is(refaddr($from_true), refaddr(Chalk::IR::Type::TypeBool->TRUE), 'constant(1) returns TRUE');
    is(refaddr($from_false), refaddr(Chalk::IR::Type::TypeBool->FALSE), 'constant(0) returns FALSE');
};

subtest 'TypeBool inherits from Chalk::IR::Type' => sub {
    my $bool = Chalk::IR::Type::TypeBool->TRUE;
    ok($bool isa Chalk::IR::Type, 'TypeBool inherits from Type');
};

done_testing();
