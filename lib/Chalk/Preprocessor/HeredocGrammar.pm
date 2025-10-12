# ABOUTME: Grammar for parsing heredoc declarations in Perl code
# ABOUTME: Minimal grammar that recognizes strings, comments, and heredoc markers
package Chalk::Preprocessor::HeredocGrammar;
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use Chalk::Grammar;

our @EXPORT = qw($heredoc_grammar);

# This mini-grammar only needs to recognize:
# 1. String literals (to skip heredocs inside strings)
# 2. Comments (to skip heredocs inside comments)
# 3. Heredoc markers (to capture and transform)
# 4. Everything else (pass through)

our $heredoc_grammar = Chalk::Grammar->build_grammar(
    auto_insert => [],  # No automatic whitespace insertion
    rules => [
        # A line is a sequence of tokens followed by newline
        [ 'Line' => ['TokenList', 'Newline'], 1.0 ],
        [ 'Line' => ['TokenList'], 1.0 ],  # Last line might not have newline
        [ 'Line' => ['Newline'], 1.0 ],     # Empty line

        # Token list
        [ 'TokenList' => ['Token'], 1.0 ],
        [ 'TokenList' => ['Token', 'TokenList'], 1.0 ],

        # Tokens - order matters for precedence
        [ 'Token' => ['Comment'], 1.0 ],
        [ 'Token' => ['SingleQuotedString'], 1.0 ],
        [ 'Token' => ['DoubleQuotedString'], 1.0 ],
        [ 'Token' => ['HeredocMarker'], 1.0 ],
        [ 'Token' => ['OtherChar'], 1.0 ],

        # Comments - everything from # to end of line
        [ 'Comment' => [qr/#[^\n]*/], 1.0 ],

        # Single-quoted strings - handle escaped quotes
        [ 'SingleQuotedString' => [qr/'(?:[^'\\]|\\.)*'/], 1.0 ],

        # Double-quoted strings - handle escaped quotes
        [ 'DoubleQuotedString' => [qr/"(?:[^"\\]|\\.)*"/], 1.0 ],

        # Heredoc markers - all forms
        # Order matters: check quoted forms before bare forms
        [ 'HeredocMarker' => [qr/<<~'[^']+'/], 1.0 ],    # <<~'EOF'
        [ 'HeredocMarker' => [qr/<<~"[^"]+"/], 1.0 ],    # <<~"EOF"
        [ 'HeredocMarker' => [qr/<<~\\\w+/], 1.0 ],      # <<~\EOF
        [ 'HeredocMarker' => [qr/<<~\w+/], 1.0 ],        # <<~EOF
        [ 'HeredocMarker' => [qr/<<'[^']+'/], 1.0 ],     # <<'EOF'
        [ 'HeredocMarker' => [qr/<<"[^"]+"/], 1.0 ],     # <<"EOF"
        [ 'HeredocMarker' => [qr/<<\\\w+/], 1.0 ],       # <<\EOF
        [ 'HeredocMarker' => [qr/<<\w+/], 1.0 ],         # <<EOF

        # Everything else - one character at a time
        [ 'OtherChar' => [qr/[^\n#'"<]/], 1.0 ],  # Anything except newline, #, quote, or <
        [ 'OtherChar' => [qr/</], 0.5 ],          # < by itself (not part of heredoc)

        # Newline
        [ 'Newline' => [qr/\n/], 1.0 ],
    ]
);

1;
