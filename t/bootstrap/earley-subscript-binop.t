# ABOUTME: Tests for binary expressions inside chained subscripts.
# ABOUTME: Tracks disambiguation bug where $a->[$x][$y - 1] fails without parens.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(build_perl_ir_parser perl_pipeline);
use Chalk::Bootstrap::BNF::Target::Perl;

my $raw_ir = perl_pipeline();
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $gen = $bnf_target->generate($raw_ir);
$gen =~ s/Chalk::Grammar::BNF::Generated/Test::SubscriptBinop/g;
eval "$gen; 1" or die $@;
no strict 'refs';
my $grammar = "Test::SubscriptBinop::grammar"->();

sub parse_ok($snippet, $label) {
    my $source = "use 5.42.0;\nuse utf8;\n$snippet;\n";
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    $parser->semiring()->reset_cache();
    my $result = $parser->parse_value($source);
    ok(defined($result), $label);
}

sub parse_todo($snippet, $label) {
    my $source = "use 5.42.0;\nuse utf8;\n$snippet;\n";
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    $parser->semiring()->reset_cache();
    my $result = $parser->parse_value($source);
    TODO: {
        local $TODO = 'chained subscript disambiguation: binop inside second+ subscript killed by Precedence add()';
        ok(defined($result), $label);
    }
}

# Working cases: single subscript with binop
parse_ok('$a->[$x - 1]', 'single subscript with binop');
parse_ok('$a->{$x - 1}', 'single hash subscript with binop');
parse_ok('$a[$x - 1]', 'bare subscript with binop');

# Working cases: chained subscripts without binop
parse_ok('$a->[$x][$y]', 'double chain, no binop');
parse_ok('$a->[$x][$y][$z]', 'triple chain, no binop');

# Working cases: binop in first subscript of a chain
parse_ok('$a->[$x - 1][$y]', 'binop in first subscript');

# Working workaround: parens around binop in later subscripts
parse_ok('$a->[$x][($y - 1)]', 'parens around binop in second subscript');
parse_ok('$a->[$x][$y][($z - 1)]', 'parens around binop in third subscript');

# Disambiguation bug: binop in second+ subscript without parens.
# The Precedence semiring's add() picks the wrong parse path when
# an unparenthesized binary expression appears inside the second or
# later subscript in a chain. The correct parse ($a->[$x])[$y - 1]
# exists (Boolean recognizes it) but loses to the wrong grouping
# ($a->[$x][$y]) - 1 during FilterComposite disambiguation.
parse_todo('$a->[$x][$y - 1]', 'binop in second subscript (no parens)');
parse_todo('$a->[$x][$y + $z]', 'addition in second subscript (no parens)');
parse_todo('$a->[$x][$y][$z - 1]', 'binop in third subscript (no parens)');
parse_todo('$a->{$x}{$y}{$z - 1}', 'hash: binop in third subscript (no parens)');

done_testing;
