# ABOUTME: The C target reads the keywords undef/true/false from a Constant's type,
# ABOUTME: never from its value: the strings 'undef', 'true', 'false' stay strings.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

my $f = Chalk::IR::NodeFactory->new;
my $c = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'UndefByType');

my sub const($type, $value) { $f->make('Constant', const_type => $type, value => $value) }

my %kw = (
    undef => const('undef', 'undef'),
    true  => const('bool',  'true'),
    false => const('bool',  'false'),
);
my %str = map { $_ => const('string', $_) } qw(undef true false);
my %want = (undef => '&PL_sv_undef', true => '&PL_sv_yes', false => '&PL_sv_no');

for my $w (sort keys %want) {
    # An expression operand.
    is($c->_emit_const_expr($kw{$w}, {}), $want{$w}, "expression: the keyword $w");
    unlike($c->_emit_const_expr($str{$w}, {}), qr/PL_sv_/, "expression: the string '$w' is a string");

    # A scalar's initializer (`my $x = undef`).
    is($c->_emit_init_expr($kw{$w}, '$'), $want{$w}, "initializer: the keyword $w");
    unlike($c->_emit_init_expr($str{$w}, '$'), qr/PL_sv_/, "initializer: the string '$w' is a string");

    # A sub or method whose body returns the constant.
    like(join("\n", $c->_emit_simple_return_sub("f_$w", [], $kw{$w})->{helper}->@*),
        qr/\Q$want{$w}\E/, "sub returning the keyword $w");
    unlike(join("\n", $c->_emit_simple_return_sub("g_$w", [], $str{$w})->{helper}->@*),
        qr/PL_sv_/, "sub returning the string '$w'");
    like(join("\n", $c->_emit_simple_return_method("f_$w", [], $kw{$w})->{helper}->@*),
        qr/\Q$want{$w}\E/, "method returning the keyword $w");
    unlike(join("\n", $c->_emit_simple_return_method("g_$w", [], $str{$w})->{helper}->@*),
        qr/PL_sv_/, "method returning the string '$w'");

    # A field default in the XS wrapper.
    like(join("\n", $c->_emit_defop_for_xs_wrapper($kw{$w})), qr/\Q$want{$w}\E/,
        "field default: the keyword $w");
    unlike(join("\n", $c->_emit_defop_for_xs_wrapper($str{$w})), qr/PL_sv_/,
        "field default: the string '$w'");
}

# The Perl-source spelling of a field default.
is($c->_ir_default_to_perl($kw{undef}), undef, 'perl default: the keyword undef is the default');
is($c->_ir_default_to_perl($str{undef}), "'undef'", "perl default: the string 'undef' is a string");
is($c->_ir_default_to_perl($kw{true}), 'true', 'perl default: the keyword true');
is($c->_ir_default_to_perl($str{true}), "'true'", "perl default: the string 'true' is a string");

done_testing();
