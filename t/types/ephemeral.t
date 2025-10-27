# ABOUTME: Tests for ephemeral List type and conversion to Array/Hash
# ABOUTME: Validates List → Array/Hash conversion logic per Phase 3 of Issue #74

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use Chalk::Type::List;
use Chalk::Type::Array;
use Chalk::Type::Hash;
use Chalk::Type::Any;
use Chalk::Type::Int;

subtest 'List is ephemeral type' => sub {
    use_ok('Chalk::Type::List');

    my $list = Chalk::Type::List->new();

    isa_ok($list, 'Chalk::Type::List', 'List type created');
    ok($list->is_subtype_of(Chalk::Type::Any->new()), 'List <: Any');
};

subtest 'List converts to Array with @ sigil' => sub {
    my $list = Chalk::Type::List->new();

    my $array = $list->convert_to_target('@');

    isa_ok($array, 'Chalk::Type::Array', 'List converts to Array');
    ok(defined($array->element_type), 'Converted Array has element_type');
    isa_ok($array->element_type, 'Chalk::Type::Any',
           'Default element_type is Any');
};

subtest 'List converts to Hash with % sigil' => sub {
    my $list = Chalk::Type::List->new();

    my $hash = $list->convert_to_target('%');

    isa_ok($hash, 'Chalk::Type::Hash', 'List converts to Hash');
    ok(defined($hash->value_type), 'Converted Hash has value_type');
    isa_ok($hash->value_type, 'Chalk::Type::Any',
           'Default value_type is Any');
};

subtest 'List conversion to scalar sigil fails' => sub {
    my $list = Chalk::Type::List->new();

    eval {
        $list->convert_to_target('$');
    };

    ok($@, 'List to Scalar conversion throws error');
    like($@, qr/Cannot assign List to scalar variable/i,
         'Error message is descriptive');
};

subtest 'List with parameterized element type converts properly' => sub {
    my $int_type = Chalk::Type::Int->new();
    my $list = Chalk::Type::List->new(element_type => $int_type);

    my $array = $list->convert_to_target('@');

    isa_ok($array, 'Chalk::Type::Array', 'Parameterized List converts to Array');
    isa_ok($array->element_type, 'Chalk::Type::Int',
           'Element type preserved during conversion');
};

subtest 'Range operator produces List type' => sub {
    # This will be tested via semantic semiring
    # Range: 1..10 produces List
    # Assignment: my @arr = (1..10) converts List to Array
    pass('Range operator type inference tested in semantic-type-tracking.t');
};

done_testing();
