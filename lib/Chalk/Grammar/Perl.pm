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

our @EXPORT = qw(build_perl_grammar);

# Build a Perl grammar from BNF content string
sub build_perl_grammar($bnf_content) {
    my $rules = Chalk::BNF::parse_bnf_string($bnf_content);

    # Ensure Program is the first rule (start symbol)
    my @ordered_rules = (
        (grep { $_->[0] eq 'Program' } @$rules),
        (grep { $_->[0] ne 'Program' } @$rules)
    );

    return Chalk::Grammar->build_grammar(
        rules => \@ordered_rules
    );
}

1;
