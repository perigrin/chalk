# ABOUTME: Tests for the named-unary table additions to PrecedenceTable.pm.
# ABOUTME: Verifies is_named_unary, named_unary_level, and named_unary_assoc.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Grammar::Perl::PrecedenceTable;

subtest 'is_named_unary returns true for defined' => sub {
    ok(Chalk::Grammar::Perl::PrecedenceTable::is_named_unary('defined'),
        "'defined' is a named-unary operator");
};

subtest 'is_named_unary returns true for exists' => sub {
    ok(Chalk::Grammar::Perl::PrecedenceTable::is_named_unary('exists'),
        "'exists' is a named-unary operator");
};

subtest 'is_named_unary returns true for ref' => sub {
    ok(Chalk::Grammar::Perl::PrecedenceTable::is_named_unary('ref'),
        "'ref' is a named-unary operator");
};

subtest 'is_named_unary returns true for scalar' => sub {
    ok(Chalk::Grammar::Perl::PrecedenceTable::is_named_unary('scalar'),
        "'scalar' is a named-unary operator");
};

subtest 'is_named_unary returns true for length' => sub {
    ok(Chalk::Grammar::Perl::PrecedenceTable::is_named_unary('length'),
        "'length' is a named-unary operator");
};

subtest 'is_named_unary returns false for not_a_builtin' => sub {
    ok(!Chalk::Grammar::Perl::PrecedenceTable::is_named_unary('not_a_builtin'),
        "'not_a_builtin' is not a named-unary operator");
};

subtest 'is_named_unary returns false for binary op +' => sub {
    ok(!Chalk::Grammar::Perl::PrecedenceTable::is_named_unary('+'),
        "'+' is not a named-unary operator");
};

subtest 'named_unary_level returns a numeric value' => sub {
    my $level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
    ok(defined $level, 'named_unary_level returns a defined value');
    ok($level == $level + 0, 'named_unary_level returns a numeric value');
};

subtest 'named_unary_level is between levels 4 and 5 (between << and isa)' => sub {
    my $level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
    cmp_ok($level, '>', 4,   'named_unary_level is greater than level 4 (<< >>)');
    cmp_ok($level, '<', 5,   'named_unary_level is less than level 5 (isa)');
    is($level, 4.5, 'named_unary_level is 4.5 (fractional slot between << and isa)');
};

subtest 'named_unary_assoc returns nonassoc' => sub {
    is(Chalk::Grammar::Perl::PrecedenceTable::named_unary_assoc(), 'nonassoc',
        "named_unary_assoc returns 'nonassoc' per perlop");
};

done_testing;
