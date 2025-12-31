# ABOUTME: Semantic action for DoubleQuotedString - handles escape sequences and interpolation
# ABOUTME: Returns Constant for plain strings or InterpolatedString for strings with variables

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::InterpolatedString;
use Chalk::IR::Node::Load;
use Chalk::IR::Node::UnboundVariable;
use Chalk::Grammar::Chalk::Type::Str;

class Chalk::Grammar::Chalk::Rule::DoubleQuotedString :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # DoubleQuotedString -> %DOUBLE_QUOTED_STRING%
        # Process escape sequences and variable interpolation

        my $string_with_quotes = $context->child(0);
        die "DoubleQuotedString: expected string token at child(0), got undefined"
            unless defined $string_with_quotes;

        # Strip surrounding double quotes
        my $content = "$string_with_quotes";
        if (length($content) >= 2 && $content =~ m/^"/) {
            $content = substr($content, 1, length($content) - 2);
        }

        # Scan for unescaped variable interpolation: $identifier
        # Pattern: $ followed by identifier characters, not preceded by backslash
        my @parts;
        my $pos = 0;

        while ($content =~ /(?<!\\)\$([a-zA-Z_]\w*)/g) {
            my $var_name = $1;
            my $match_start = $-[0];  # Start of match ($)
            my $match_end = $+[0];    # End of match (after identifier)

            # Add literal segment before this variable (if any)
            if ($match_start > $pos) {
                my $literal = substr($content, $pos, $match_start - $pos);
                $literal = $self->_process_escapes($literal);
                push @parts, Chalk::IR::Node::Constant->new(
                    type => Chalk::Grammar::Chalk::Type::Str->new(),
                    value => $literal,
                );
            }

            # Add variable reference
            # Try to look up in scope, fall back to UnboundVariable
            my $scope = $context->env->{scope};
            my $full_name = '$' . $var_name;
            my $var_node;

            if ($scope) {
                my $found = $scope->lookup($full_name);
                if (defined($found) && ref($found) && $found->can('id')) {
                    # Found in scope - wrap in Load node
                    $var_node = Chalk::IR::Node::Load->new(
                        inputs => [$found->id],
                        name => $full_name,
                        value => $found,
                    );
                }
            }

            # If not found in scope, create UnboundVariable
            unless ($var_node) {
                $var_node = Chalk::IR::Node::UnboundVariable->new(
                    name => $full_name
                );
            }

            push @parts, $var_node;
            $pos = $match_end;
        }

        # If we found interpolation, handle the final segment and return InterpolatedString
        if (@parts > 0) {
            # Add any remaining literal after last variable
            if ($pos < length($content)) {
                my $literal = substr($content, $pos);
                $literal = $self->_process_escapes($literal);
                push @parts, Chalk::IR::Node::Constant->new(
                    type => Chalk::Grammar::Chalk::Type::Str->new(),
                    value => $literal,
                );
            }

            return Chalk::IR::Node::InterpolatedString->new(
                parts => \@parts,
            );
        }

        # No interpolation found - process escapes and return simple Constant
        my $value = $self->_process_escapes($content);
        return Chalk::IR::Node::Constant->new(
            type => Chalk::Grammar::Chalk::Type::Str->new(),
            value => $value,
        );
    }

    method _process_escapes($str) {
        # Process common escape sequences
        # \n -> newline, \t -> tab, \r -> carriage return
        # \\ -> backslash, \" -> quote, \$ -> dollar, \@ -> at
        my %escapes = (
            'n' => "\n",
            't' => "\t",
            'r' => "\r",
            '\\' => '\\',
            '"' => '"',
            '$' => '$',
            '@' => '@',
        );

        # Use different strategy to avoid interpolation issues
        $str =~ s/\\([ntr])/$escapes{$1}/ge;  # Simple escapes
        $str =~ s/\\\\/\\/g;                   # Backslash
        $str =~ s/\\"/"/g;                     # Quote
        $str =~ s/\\\$/\$/g;                   # Dollar
        $str =~ s/\\\@/\@/g;                   # At sign
        return $str;
    }
}

1;
