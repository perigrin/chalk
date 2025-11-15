# ABOUTME: Semantic action for PatternDef - builds pattern definition rule
# ABOUTME: Extracts pattern name and regex content (currently returns undef to skip)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::PatternDef :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # PatternDef -> '%' NAME '%' WS '=' WS '/' REST_OF_LINE (8 children)
        # Parses: %NAME% = /regex/flags

        my $children = $context->children();
        my @children = $children->@*;

        # Verify we have expected structure
        if (scalar(@children) != 8) {
            my $child_summary = join(", ", map {
                defined($_) ? (defined($_->focus) ? "'" . $_->focus . "'" : "undef-focus") : "undef"
            } @children);
            die "Unexpected PatternDef structure with " . scalar(@children) . " children (expected 8): [$child_summary]\n";
        }

        # Extract pattern name (child 1)
        my $name_child = $children[1];
        my $name = $name_child->focus;

        # Extract rest of line after first '/' (child 7)
        my $rest = $children[7]->focus;

        # Parse rest using rindex to find last /
        # This handles cases like /\|\||/ where / appears in the regex
        my $last_slash = rindex($rest, '/');
        if ($last_slash < 0) {
            die "Invalid pattern definition for %$name%: /$rest (missing closing /)\n";
        }

        my $regex_content = substr($rest, 0, $last_slash);

        # Compile the regex with capture group
        # terminal_to_regex assumes Regexp terminals already have captures
        my $compiled_regex = qr/($regex_content)/;

        # Store in pattern table (env->{patterns})
        my $env = $context->env;
        $env->{patterns}->{$name} = $compiled_regex;

        # Return undef to signal this should be filtered from grammar rules
        # (pattern definitions are metadata, not grammar productions)
        return;
    }
}

