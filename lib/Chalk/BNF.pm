# ABOUTME: Simple BNF file parser for loading grammar rules
# ABOUTME: Avoids complex nested structures for bootstrap self-hosting
package Chalk::BNF;
use 5.42.0;
use utf8;
use Chalk::Grammar;
use Chalk::Grammar::BNF;
use Chalk::Parser;
use Chalk::Semiring::Semantic;

sub parse_bnf_file($filename) {
    open my $fh, '<:utf8', $filename or die "Cannot open $filename: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    return parse_bnf_string($content);
}

sub parse_with_semantic_actions($bnf_content) {
    # Parse BNF using hand-coded BNF grammar with semantic actions
    # Returns Chalk::Grammar object directly from parsing
    #
    # NOTE: The hand-coded BNF grammar currently supports basic BNF syntax
    # (grammar rules, terminals, nonterminals, pattern definitions, comments).
    # More complex features in perl.bnf may not parse yet. Use parse_bnf_string()
    # for full compatibility with existing BNF files.

    my $bnf_grammar = Chalk::Grammar::BNF->grammar;

    # Create environment with pattern table for storing %NAME% definitions
    my %env = (
        patterns => {}  # Pattern name => compiled regex
    );

    my $semiring = Chalk::Semiring::Semantic->new(
        env => \%env,
        grammar => $bnf_grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $bnf_grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string($bnf_content);

    # Extract Grammar object from semantic result
    return $result ? $result->context->extract : undef;
}

sub build_chalk_grammar($bnf_content, $start_symbol = undef) {
    my $rules = parse_bnf_string($bnf_content);

    # If start symbol specified, ensure it's first
    if (defined $start_symbol) {
        my @ordered_rules = (
            (grep { $_->[0] eq $start_symbol } @$rules),
            (grep { $_->[0] ne $start_symbol } @$rules)
        );
        $rules = \@ordered_rules;
    }

    return Chalk::Grammar->build_grammar(rules => $rules);
}

sub parse_bnf_string($content) {
    my %patterns;
    my @rules;

    my @lines = split /\n/, $content;
    for my $line (@lines) {
        $line = trim($line);

        # Skip blank lines
        next if $line eq '';

        # Pattern definition: %NAME% = /regex/flags
        # Must match before comment stripping since patterns may contain #
        if ( $line =~ /^%(\w+)%\s*=\s*\/(.+)\/([a-z]*)/ ) {
            my ( $name, $pattern, $flags ) = ( $1, $2, $3 || '' );
            $patterns{$name} = qr/(?$flags:$pattern)/;
            next;
        }

        # Strip comments AFTER checking for pattern definitions
        $line =~ s/#.*$//;
        $line = trim($line);
        next if $line eq '';

        # Grammar rule: LHS -> RHS
        if ( $line =~ /^(\w+)\s*->\s*(.*)$/ ) {
            my ( $lhs, $rhs ) = ( $1, $2 );

            # Empty RHS means epsilon rule
            if ( $rhs eq '' ) {
                push @rules, [ $lhs => [] ];
                next;
            }

            # Parse RHS tokens
            my @rhs_tokens = parse_rhs( $rhs, \%patterns );
            push @rules, [ $lhs => \@rhs_tokens ];
        }
        else {
            die "Invalid BNF syntax: $line\n";
        }
    }

    return \@rules;
}

sub parse_rhs {
    my ( $rhs, $patterns ) = @_;
    my @tokens;

    # Tokenize RHS, handling quoted strings and regexes
    while ( $rhs =~ /\S/ ) {
        $rhs = trim($rhs);

        # Single-quoted string (terminal)
        # Match the same pattern as Terminal rule: (?:[^'\\]|\\.)*
        if ( $rhs =~ /^'((?:[^'\\]|\\.)*)'/ ) {
            my $content = $1;
            my $matched_len = length($&);  # IMPORTANT: Save length before any substitutions!
            # Unescape backslash sequences to match new parser behavior
            # IMPORTANT: Process \\ first to avoid double-processing
            $content =~ s/\\\\/\x00/g;  # Temporarily replace \\ with null byte
            $content =~ s/\\n/\n/g;
            $content =~ s/\\t/\t/g;
            $content =~ s/\\r/\r/g;
            $content =~ s/\\'/'/g;   # \' becomes '
            $content =~ s/\x00/\\/g;  # Restore \\ as single \
            push @tokens, $content;
            $rhs = substr( $rhs, $matched_len );  # Use saved length, not $&
        }

        # Pattern reference %NAME%
        elsif ( $rhs =~ /^%(\w+)%/ ) {
            my $pattern_name = $1;
            if ( exists $patterns->{$pattern_name} ) {
                push @tokens, $patterns->{$pattern_name};
            }
            else {
                die "Undefined pattern: $pattern_name\n";
            }
            $rhs = substr( $rhs, length($&) );
        }

        # Regex pattern /pattern/flags
        elsif ( $rhs =~ m{^/(.+?)/([a-z]*)?} ) {
            my ( $pattern, $flags ) = ( $1, $2 // '' );
            push @tokens, qr/(?$flags:$pattern)/;
            $rhs = substr( $rhs, length($&) );
        }

        # Nonterminal or special symbol
        elsif ( $rhs =~ /^([\w:]+|[^\s'\/]+)/ ) {
            push @tokens, $1;
            $rhs = substr( $rhs, length($&) );
        }
        else {
            last;
        }
    }

    return @tokens;
}

1;
