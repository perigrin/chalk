# ABOUTME: Tests that Target::C emits direct C function calls for self-calls.
# ABOUTME: Verifies self-call optimization produces slug_method() instead of call_method().
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::C;

# === Setup: Parse Boolean.pm to IR ===
# Boolean.pm is ideal: multiply() calls $self->is_zero(), add() calls
# $self->is_zero(), on_scan() calls $self->multiply() and $self->one().

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::CSelfCall') };
ok(defined $gen, 'grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

my ($ir, $sa, $ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm')
};
ok(defined $ir, 'Boolean.pm parsed to IR')
    or BAIL_OUT("Cannot continue without IR: $@");

# === Generate C via Target::C ===

my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Chalk::Bootstrap::Semiring::Boolean',
);

my $result = eval { $target->generate_c_files($ir, $sa, $ctx) };
is($@, '', 'generate_c_files does not die')
    or BAIL_OUT("generate_c_files died: $@");

# === Part 1: Self-call optimization — direct C calls ===

my $c_text = $result->{files}{'boolean.c'};
ok(defined $c_text, 'boolean.c generated');

# multiply() calls $self->is_zero($left) and $self->is_zero($right)
# These should be direct boolean_is_zero(aTHX_ self, ...) calls
like($c_text, qr/boolean_is_zero\(aTHX_ self/,
    'self-call to is_zero uses direct C function');

# on_scan() calls $self->multiply($item->{value}, $self->one())
like($c_text, qr/boolean_multiply\(aTHX_ self/,
    'self-call to multiply uses direct C function');

like($c_text, qr/boolean_one\(aTHX_ self\)/,
    'self-call to one uses direct C function');

# No call_method for any of these self-calls
# Count call_method occurrences — should be zero for Boolean since
# the only external call is $item->{value} which is a hash access, not a method call
my @call_method_hits = ($c_text =~ /call_method/g);
is(scalar @call_method_hits, 0,
    'boolean.c has zero call_method dispatches (all self-calls optimized)');

# === Part 2: Verify SvREFCNT_inc is NOT used for self-calls ===
# Direct C calls return owned SVs — wrapping in SvREFCNT_inc would leak.

# Check that self-call results are NOT wrapped in SvREFCNT_inc
unlike($c_text, qr/SvREFCNT_inc\(boolean_is_zero\(/,
    'self-call to is_zero not wrapped in SvREFCNT_inc');
unlike($c_text, qr/SvREFCNT_inc\(boolean_multiply\(/,
    'self-call to multiply not wrapped in SvREFCNT_inc');
unlike($c_text, qr/SvREFCNT_inc\(boolean_one\(/,
    'self-call to one not wrapped in SvREFCNT_inc');

done_testing;
