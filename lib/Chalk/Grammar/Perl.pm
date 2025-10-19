# ABOUTME: Chalk grammar for parsing Modern Perl (5.42+) with class syntax
# ABOUTME: Based on Guacamole grammar structure with chalk-specific extensions
package Chalk::Grammar::Perl;
use 5.42.0;
use utf8;
use open qw(:std :utf8);
use experimental qw(class builtin keyword_any keyword_all defer);
use Exporter 'import';
use Chalk::Grammar;
use Chalk::BNF;
use FindBin qw($RealBin);

our @EXPORT = qw($chalk_grammar);

# Load grammar rules from BNF file instead of complex nested arrayref
# This allows the grammar to parse itself during bootstrap
use File::Basename qw(dirname);
use File::Spec;

my $grammar_file = File::Spec->catfile(dirname(__FILE__), '..', '..', '..', 'grammar', 'perl-full.bnf');

my $rules = Chalk::BNF::parse_bnf_file($grammar_file);

# Ensure Program is the first rule (start symbol)
my @ordered_rules = (
    (grep { $_->[0] eq 'Program' } @$rules),
    (grep { $_->[0] ne 'Program' } @$rules)
);

our $chalk_grammar = Chalk::Grammar->build_grammar(
    rules       => \@ordered_rules
);

1;
