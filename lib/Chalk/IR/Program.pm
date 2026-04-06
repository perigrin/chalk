# ABOUTME: Metadata struct for a complete Perl program.
# ABOUTME: Stores use declarations, classes, and top-level subroutines.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Program {
    field $use_decls      :param :reader = [];
    field $classes        :param :reader = [];
    field $top_level_subs :param :reader = [];
    # Bare computation nodes at the top level (e.g., in test snippets).
    # In well-formed production programs this is always empty.
    field $other_stmts    :param :reader = [];

    # Content-based ID for use in NodeFactory hash-cons keys.
    # Program objects are not hash-consed themselves, but may appear
    # as top-level outputs from the parser and need an addressable id.
    method id() {
        my $uses_str  = join(',', map { $_->id() } $use_decls->@*);
        my $cls_str   = join(',', map { $_->id() } $classes->@*);
        my $subs_str  = join(',', map { $_->id() } $top_level_subs->@*);
        return "Program:[$uses_str]:[$cls_str]:[$subs_str]";
    }

    # No-op: Program does not participate in the use-def chain.
    method add_consumer($consumer) {
        return;
    }
}
