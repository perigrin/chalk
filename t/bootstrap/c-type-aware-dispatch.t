# ABOUTME: Tests type-aware dispatch for cross-class method calls on known types.
# ABOUTME: Verifies :reader calls become ObjectFIELDS access and explicit methods become direct C calls.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::C;

# === Setup: Parse Earley.pm ===
# Earley has cross-class calls to Symbol (value, is_reference, is_quantified, quantifier)
# and Rule (name, expressions). These should become direct field access or C calls
# when compiled_class_metadata is provided.

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::CTypeAware') };
ok(defined $gen, 'grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

my ($ir, $sa, $ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm')
};
ok(defined $ir, 'Earley.pm parsed to IR')
    or BAIL_OUT("Cannot continue without IR: $@");

# === Part 1: Without compiled_class_metadata — baseline ===
{
    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Earley',
        field_types => {
            semiring   => 'Chalk::Bootstrap::Semiring::FilterComposite',
            core_index => 'Chalk::Bootstrap::CoreItemIndex',
            lr0_dfa    => 'Chalk::Bootstrap::LR0DFA',
        },
    );
    my $result = eval { $target->_generate_c_files($ir, $sa, $ctx) };
    is($@, '', 'baseline _generate_c_files does not die');

    my $c_text = $result->{files}{'earley.c'};
    ok(defined $c_text, 'baseline earley.c generated');

    # Baseline: :reader calls should be call_method
    my @value_methods = ($c_text =~ /call_method\("value"/g);
    cmp_ok(scalar @value_methods, '>', 0,
        'baseline has call_method("value") dispatches');
}

# === Part 2: With compiled_class_metadata — type-aware dispatch ===
{
    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Earley',
        field_types => {
            semiring   => 'Chalk::Bootstrap::Semiring::FilterComposite',
            core_index => 'Chalk::Bootstrap::CoreItemIndex',
            lr0_dfa    => 'Chalk::Bootstrap::LR0DFA',
        },
        compiled_class_metadata => {
            'Chalk::Grammar::Symbol' => {
                slug    => 'symbol',
                readers => { type => 0, value => 1, quantifier => 2 },
                methods => { is_terminal => 1, is_reference => 1, is_quantified => 1, to_string => 1 },
            },
            'Chalk::Grammar::Rule' => {
                slug    => 'rule',
                readers => { name => 0, expressions => 1 },
                methods => { alternative_count => 1, is_terminal_rule => 1, to_string => 1 },
            },
        },
    );
    my $result = eval { $target->_generate_c_files($ir, $sa, $ctx) };
    is($@, '', 'type-aware _generate_c_files does not die');

    my $c_text = $result->{files}{'earley.c'};
    ok(defined $c_text, 'type-aware earley.c generated');

    # :reader calls should become ObjectFIELDS direct access
    like($c_text, qr/ObjectFIELDS\(SvRV\([^)]+\)\)\[1\]/,
        'value() (field index 1) becomes ObjectFIELDS access');
    like($c_text, qr/ObjectFIELDS\(SvRV\([^)]+\)\)\[0\]/,
        'name() (field index 0) becomes ObjectFIELDS access');

    # Explicit method calls should become direct C function calls
    like($c_text, qr/symbol_is_reference\(aTHX_/,
        'is_reference() becomes direct C call');
    like($c_text, qr/symbol_is_quantified\(aTHX_/,
        'is_quantified() becomes direct C call');

    # No call_method should remain for these methods
    my @remaining_cm = ($c_text =~ /call_method\("([^"]+)"/g);
    my %remaining = map { $_ => 1 } @remaining_cm;
    ok(!$remaining{value}, 'no call_method("value") remains');
    ok(!$remaining{name}, 'no call_method("name") remains');
    ok(!$remaining{expressions}, 'no call_method("expressions") remains');
    ok(!$remaining{quantifier}, 'no call_method("quantifier") remains');
    ok(!$remaining{is_reference}, 'no call_method("is_reference") remains');
    ok(!$remaining{is_quantified}, 'no call_method("is_quantified") remains');

    # Total call_method count should be zero
    my @all_cm = ($c_text =~ /call_method/g);
    is(scalar @all_cm, 0,
        'earley.c has ZERO call_method dispatches with type-aware dispatch');
}

done_testing;
