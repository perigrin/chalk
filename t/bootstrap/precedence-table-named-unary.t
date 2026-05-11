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

subtest 'named_unary_level returns an integer' => sub {
    my $level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
    ok(defined $level, 'named_unary_level returns a defined value');
    like("$level", qr/^\d+$/, 'named_unary_level returns an integer');
};

subtest 'named_unary_level is between 0 and 100' => sub {
    my $level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
    cmp_ok($level, '>', 0,   'named_unary_level is greater than 0');
    cmp_ok($level, '<', 100, 'named_unary_level is less than 100');
    is($level, 50, 'named_unary_level is exactly 50 (perlop L10)');
};

subtest 'named_unary_assoc returns nonassoc' => sub {
    is(Chalk::Grammar::Perl::PrecedenceTable::named_unary_assoc(), 'nonassoc',
        "named_unary_assoc returns 'nonassoc' per perlop");
};

done_testing;
