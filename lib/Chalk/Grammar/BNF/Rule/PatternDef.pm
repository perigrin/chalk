# ABOUTME: Semantic action for PatternDef - builds pattern definition rule
# ABOUTME: Extracts pattern name and regex content (currently returns undef to skip)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::PatternDef :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Two alternatives:
        # 1. PatternDef -> '%' NAME '%' WS '=' WS '/' REST_OF_LINE (8 children)
        # 2. PatternDef -> '%' NAME '%' WS '=' WS '//' REGEX '//' FLAGS (10 children)

        my $children = $context->children();
        my @children = $children->@*;

        # Extract pattern name (child 1)
        my $name_child = $children[1];
        my $name = $name_child->focus;

        my ($regex_content, $flags);

        if (scalar(@children) == 8) {
            # Single-slash with rest-of-line (alternative 1)
            my $rest = $children[7]->focus;

            # Parse rest using index to find last /
            my $last_slash = rindex($rest, '/');
            if ($last_slash >= 0) {
                $regex_content = substr($rest, 0, $last_slash);
                $flags = substr($rest, $last_slash + 1) // '';
            } else {
                die "Invalid single-slash pattern definition: /$rest\n";
            }
        } elsif (scalar(@children) == 9 || scalar(@children) == 10) {
            # Double-slash with explicit structure (alternative 2)
            # 9 children if flags empty, 10 if flags present
            $regex_content = $children[7]->focus;
            my $flags_child = $children[9];
            $flags = '';
            if (defined($flags_child)) {
                $flags = $flags_child->focus;
            }
            $flags //= '';
        } else {
            # Debug: show what we got
            my $child_summary = join(", ", map {
                defined($_) ? (defined($_->focus) ? "'" . $_->focus . "'" : "undef-focus") : "undef"
            } @children);
            die "Unexpected PatternDef structure with " . scalar(@children) . " children: [$child_summary]\n";
        }

        # Compile the regex with flags
        my $compiled_regex;
        if ($flags ne '') {
            $compiled_regex = qr/(?$flags:$regex_content)/;
        } else {
            $compiled_regex = qr/$regex_content/;
        }

        # Store in pattern table (env->{patterns})
        my $env = $context->env;
        $env->{patterns}->{$name} = $compiled_regex;

        # Return undef to signal this should be filtered from grammar rules
        # (pattern definitions are metadata, not grammar productions)
        return;
    }
}

