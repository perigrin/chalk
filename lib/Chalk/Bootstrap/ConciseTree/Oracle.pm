# ABOUTME: Invokes perl -MO=Concise,-exec and parses the output into a ConciseTree.
# ABOUTME: Provides both live invocation (concise_for) and output parsing (parse_concise_output).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::ConciseOp;
use Chalk::Bootstrap::ConciseTree;

class Chalk::Bootstrap::ConciseTree::Oracle {

    # Run perl -MO=Concise,-exec on the given source code and return a ConciseTree
    method concise_for($source) {
        # Escape single quotes in source for shell
        my $escaped = $source;
        $escaped =~ s/'/'\\''/g;
        my $output = `perl -MO=Concise,-exec -e '$escaped' 2>&1`;
        return $self->parse_concise_output($output);
    }

    # Parse B::Concise -exec output text into a ConciseTree.
    # Each line has format: SEQ  <ARITY> OPNAME[TYPE_INFO] FLAGS/PRIVATE
    method parse_concise_output($text) {
        my $tree = Chalk::Bootstrap::ConciseTree->new();

        for my $line (split /\n/, $text) {
            # Skip non-op lines (e.g., "-e syntax OK", blank lines)
            # B::Concise uses base-36 sequence labels (0-9, a-z), not hex.
            next unless $line =~ /^\s*[0-9a-z]+\s+</;

            # Parse the line:
            # SEQ  <ARITY> OPNAME[TYPEINFO] FLAGS/PRIVATE
            # or: SEQ  <ARITY> OPNAME(DETAILS) FLAGS/PRIVATE
            # Bracket/paren groups can contain spaces (e.g. "const[IV 42]",
            # "nextstate(main 3 -e:1)"), so we match them explicitly.
            next unless $line =~ m{
                ^\s*[0-9a-z]+       # sequence number (base-36: 0-9, a-z)
                \s+
                <([^>]+)>           # arity marker (capture group 1)
                \s+
                ([a-z_]+)           # bare op name (capture group 2)
                (?:                 # optional bracketed/parenthesized info
                    \(([^\)]*)\)    # parens: nextstate(main 3 -e:1) (capture group 3)
                    (?:\[([^\]]*)\])? # optional brackets after parens: enteriter(...)[$i] (capture group 4)
                  | \[([^\]]*)\]    # brackets only: const[IV 42] (capture group 5)
                )?
                (?:\s+(.*))?        # optional remaining flags (capture group 6)
                $
            }x;

            my $arity = $1;
            my $name = $2;
            # Brackets take priority for type_info (variable name, constant value);
            # parens contain branch targets which are stripped by Comparator.
            my $type_info = $4 // $5 // $3;
            my $remaining = $6 // '';

            # Extract private flags (start with /) from remaining
            my $private = '';
            my $flags = $remaining;
            if ($remaining =~ m{((?:/[A-Z]+)+)\s*$}) {
                $private = $1;
                $flags = substr($remaining, 0, length($remaining) - length($private));
                $flags =~ s/\s+$//;
            }

            $tree->push_op(Chalk::Bootstrap::ConciseOp->new(
                name      => $name,
                arity     => $arity,
                type_info => $type_info,
                flags     => $flags,
                private   => $private,
            ));
        }

        return $tree;
    }
}
