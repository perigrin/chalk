# ABOUTME: Simple BNF file parser for loading grammar rules
# ABOUTME: Avoids complex nested structures for bootstrap self-hosting
package Chalk::BNF;
use 5.42.0;
use utf8;

sub parse_bnf_file {
    my ($filename) = @_;

    open my $fh, '<:utf8', $filename or die "Cannot open $filename: $!";
    my %patterns;
    my @rules;

    while (my $line = <$fh>) {
        $line = trim($line);

        # Skip blank lines
        next if $line eq '';

        # Pattern definition: %NAME% = /regex/flags
        # Must match before comment stripping since patterns may contain #
        if ($line =~ /^%(\w+)%\s*=\s*\/(.+)\/([a-z]*)/) {
            my ($name, $pattern, $flags) = ($1, $2, $3 || '');
            $patterns{$name} = qr/(?$flags:$pattern)/;
            next;
        }

        # Strip comments AFTER checking for pattern definitions
        $line =~ s/#.*$//;
        $line = trim($line);
        next if $line eq '';

        # Grammar rule: LHS -> RHS
        if ($line =~ /^(\w+)\s*->\s*(.*)$/) {
            my ($lhs, $rhs) = ($1, $2);

            # Empty RHS means epsilon rule
            if ($rhs eq '') {
                push @rules, [$lhs => []];
                next;
            }

            # Parse RHS tokens
            my @rhs_tokens = parse_rhs($rhs, \%patterns);
            push @rules, [$lhs => \@rhs_tokens];
        }
        else {
            die "Invalid BNF syntax at line $.: $line\n";
        }
    }

    close $fh;
    return \@rules;
}

sub parse_rhs {
    my ($rhs, $patterns) = @_;
    my @tokens;

    # Tokenize RHS, handling quoted strings and regexes
    while ($rhs =~ /\S/) {
        $rhs = trim($rhs);

        # Single-quoted string (terminal)
        if ($rhs =~ /^'([^']*)'/) {
            push @tokens, $1;
            $rhs = substr($rhs, length($&));
        }
        # Pattern reference %NAME%
        elsif ($rhs =~ /^%(\w+)%/) {
            my $pattern_name = $1;
            if (exists $patterns->{$pattern_name}) {
                push @tokens, $patterns->{$pattern_name};
            }
            else {
                die "Undefined pattern: $pattern_name\n";
            }
            $rhs = substr($rhs, length($&));
        }
        # Regex pattern /pattern/flags
        elsif ($rhs =~ m{^/(.+?)/([a-z]*)?}) {
            my ($pattern, $flags) = ($1, $2 // '');
            push @tokens, qr/(?$flags:$pattern)/;
            $rhs = substr($rhs, length($&));
        }
        # Nonterminal or special symbol
        elsif ($rhs =~ /^([\w:]+|[^\s'\/]+)/) {
            push @tokens, $1;
            $rhs = substr($rhs, length($&));
        }
        else {
            last;
        }
    }

    return @tokens;
}

1;
