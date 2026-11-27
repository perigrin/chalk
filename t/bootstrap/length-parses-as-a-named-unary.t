# ABOUTME: `length` parses as perl's named unary wherever a scalar goes: in substr's
# ABOUTME: arguments, under a ternary, of a method call's result, and in arithmetic.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;

# Its type is Maybe[Int] (length(undef) is undef), and a reading of it must
# still satisfy a Num position: lib/Chalk/Bootstrap/Perl/Actions.pm's
# `substr($text, length($leaf->scanned_text()))` stopped parsing when it did not.
my $ir = perl_pipeline();
die 'Perl grammar failed', "\n" unless defined $ir;
my $generated = Chalk::Bootstrap::BNF::Target::Perl->new->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LengthParseTest/g;
eval $generated;
die "Generated grammar failed: $@", "\n" if $@;
my $parser = build_perl_ir_parser(
    Chalk::Grammar::Perl::LengthParseTest::grammar(), start => 'Program');

for my $src (
    'my $o = $c ? substr($text, length($leaf->scanned_text())) : $text;',
    'my $n = length($s) + 1;',
    'my $s = substr($t, 0, length $u);',
    'my $l = length $x;',
) {
    $parser->semiring->reset_cache;
    my $r = eval { $parser->parse_value($src) };
    ok( defined $r && !$@, "parses: $src" ) or diag $@;
}

done_testing;
