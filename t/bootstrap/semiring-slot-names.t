# ABOUTME: Tests for slot_name() method on all five semiring classes.
# ABOUTME: Verifies each semiring reports its annotation slot for FilterComposite.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::SemanticAction;

# =========================================================================
# Boolean: writes 'boolean' annotation slot (active under FilterComposite)
# =========================================================================

{
    my $sr = Chalk::Bootstrap::Semiring::Boolean->new();
    ok($sr->can('slot_name'), 'Boolean has slot_name() method');
    is($sr->slot_name(), 'boolean', "Boolean slot_name() returns 'boolean'");
}

# =========================================================================
# Precedence: 'precedence' annotation slot
# =========================================================================

{
    my $sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    ok($sr->can('slot_name'), 'Precedence has slot_name() method');
    is($sr->slot_name(), 'precedence', "Precedence slot_name() returns 'precedence'");
}

# =========================================================================
# Structural: 'structural' annotation slot
# =========================================================================

{
    my $sr = Chalk::Bootstrap::Semiring::Structural->new();
    ok($sr->can('slot_name'), 'Structural has slot_name() method');
    is($sr->slot_name(), 'structural', "Structural slot_name() returns 'structural'");
}

# =========================================================================
# TypeInference: 'type' annotation slot
# =========================================================================

{
    my $sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    ok($sr->can('slot_name'), 'TypeInference has slot_name() method');
    is($sr->slot_name(), 'type', "TypeInference slot_name() returns 'type'");
}

# =========================================================================
# SemanticAction: no annotation slot (owns focus field + cfg annotation)
# =========================================================================

{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    ok($sr->can('slot_name'), 'SemanticAction has slot_name() method');
    is($sr->slot_name(), undef, 'SemanticAction slot_name() returns undef');
}

done_testing();
