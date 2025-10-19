#!/usr/bin/env perl
# ABOUTME: Dump Grammar::Perl rules to BNF format
# ABOUTME: Converts the current arrayref-based grammar to line-based BNF
use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use Chalk::Grammar::Perl;

# Get the grammar object
my $grammar = $Chalk::Grammar::Perl::chalk_grammar;

# First pass: collect all regex patterns that are used
my %patterns;
my $pattern_counter = 0;

# Get all rules from the rules hash
my $rules_hash = $grammar->rules;

# Iterate through all rules and find qr// patterns
for my $lhs (keys %$rules_hash) {
    for my $rule ($rules_hash->{$lhs}->@*) {
        for my $symbol ($rule->rhs->@*) {
            if (ref($symbol) eq 'Regexp') {
                my $pattern_str = "$symbol";  # Stringify the regex
                unless (exists $patterns{$pattern_str}) {
                    $pattern_counter++;
                    $patterns{$pattern_str} = "PATTERN_$pattern_counter";
                }
            }
        }
    }
}

# Output pattern definitions
say "# Pattern definitions";
for my $pattern_str (sort { $patterns{$a} cmp $patterns{$b} } keys %patterns) {
    my $name = $patterns{$pattern_str};
    # Extract pattern and flags from stringified regex
    # Format is (?FLAGS:PATTERN) or (?^FLAGS:PATTERN)
    # We want to extract just PATTERN and FLAGS

    my $pattern = $pattern_str;
    my $flags = '';

    # Match (?^FLAGS:PATTERN) - Perl 5.14+ format
    if ($pattern =~ /^\(\?\^([a-z]*):(.*)\)$/s) {
        $flags = $1;
        $pattern = $2;
    }
    # Match (?FLAGS-FLAGS:PATTERN) - older format
    elsif ($pattern =~ /^\(\?([a-z]*)-[a-z]*:(.*)\)$/s) {
        $flags = $1;
        $pattern = $2;
    }
    # Match (?:PATTERN) - no flags
    elsif ($pattern =~ /^\(\?:(.*)\)$/s) {
        $pattern = $1;
    }

    say "%$name% = /$pattern/$flags";
}

say "";
say "# Grammar rules";

# Output rules in sorted order for consistency
for my $lhs (sort keys %$rules_hash) {
    for my $rule ($rules_hash->{$lhs}->@*) {
        my @rhs = $rule->rhs->@*;

    # Convert RHS elements to BNF format
    my @rhs_bnf;
    for my $symbol (@rhs) {
        if (ref($symbol) eq 'Regexp') {
            # Replace with pattern reference
            my $pattern_str = "$symbol";
            my $name = $patterns{$pattern_str};
            push @rhs_bnf, "%$name%";
        }
        elsif ($symbol =~ /^[a-zA-Z_]\w*$/ || $symbol =~ /::/) {
            # Nonterminal - keep as-is
            push @rhs_bnf, $symbol;
        }
        else {
            # Terminal - quote it
            push @rhs_bnf, "'$symbol'";
        }
    }

        my $rhs_str = @rhs_bnf ? join(' ', @rhs_bnf) : '';
        say "$lhs -> $rhs_str";
    }
}
