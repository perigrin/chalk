# ABOUTME: Metadata struct for a complete Perl program.
# ABOUTME: Stores use declarations, classes, and top-level subroutines.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Program {
    field $use_decls      :param :reader = [];
    field $classes        :param :reader = [];
    field $top_level_subs :param :reader = [];
}
