# ABOUTME: Semantic action for UseStatement - categorizes use statements and builds UseStatement IR nodes
# ABOUTME: UseStatement handles version checks, pragmas, modules, and external modules

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;

class Chalk::Grammar::Chalk::Rule::UseStatement :isa(Chalk::GrammarRule) {

    # Categorize use statement into: version, pragma, module, or external
    sub _categorize_use_statement($module_name) {

        # Version check: use 5.42.0;
        # Check if first char is digit (simple version detection)
        my $first_char = substr( $module_name, 0, 1 );
        if ( $first_char ge '0' && $first_char le '9' ) {
            return 'version';
        }

     # Pragma: use experimental qw(...);
     # Known pragmas that are no-ops for Chalk (Chalk provides these by default)
        if (   $module_name eq 'strict'
            || $module_name eq 'warnings'
            || $module_name eq 'utf8'
            || $module_name eq 'experimental'
            || $module_name eq 'feature' )
        {
            return 'pragma';
        }

        # Chalk module: use Chalk::IR::Node;
        # Check if module starts with 'Chalk::'
        if ( substr( $module_name, 0, 7 ) eq 'Chalk::' ) {
            return 'module';
        }

        # Everything else is external (builtin, Carp, etc.)
        return 'external';
    }

    # Extract import list from QuotedWordList child
    # QuotedWordList is qw(...) or qw/.../
    sub _extract_imports( $context, $start_index ) {
        my @imports = ();

        # Look for QuotedWordList child after the module name
        my $children       = $context->children;
        my @children_array = $children->@*;
        for my $i ( $start_index .. $#children_array ) {
            my $child = $context->child($i);
            next unless defined $child;

            # Check if this is a QuotedWordList
            if ( ref($child) eq 'ARRAY' ) {

                # QuotedWordList semantic value is array ref of import names
                @imports = $child->@*;
                last;
            }
            elsif ( blessed($child)
                && $child->can('type')
                && $child->type eq 'quoted_word_list' )
            {
                # Alternative representation
                @imports = $child->words->@* if $child->can('words');
                last;
            }
        }

        return \@imports;
    }

    method evaluate($context) {

# UseStatement grammar rules:
# UseStatement -> 'use' WS_OPT Number                                    # use 5.42.0
# UseStatement -> 'use' WS_OPT QualifiedIdentifier                       # use Module
# UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT QuotedWordList # use Module qw(...)
# UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT String         # use experimental 'class'
# UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT ExpressionList # use overload ... => ...

        my @children = $context->children->@*;
        my $builder  = $context->env->{ir_builder};

        # No builder means we're just parsing without IR generation
        return undef unless $builder;

        # Find the module name or version number (after 'use' and optional WS)
        my $module_name;
        my $module_index = -1;

        for my $i ( 0 .. $#children ) {
            my $child = $children[$i]->extract;

            # Skip 'use' keyword and whitespace/empty values
            next if !defined($child) || $child eq 'use' || $child eq '';

            # This should be the module name or version
            if ( defined($child) ) {
                # If child is an IR node (e.g., Constant from Number),
                # extract the value from its attributes
                if ( ref($child) && $child->can('op') && $child->op eq 'Constant' ) {
                    $module_name = $child->value;
                } else {
                    $module_name = $child;
                }
                $module_index = $i;
                last;
            }

           # Alternative: child is already extracted value (QualifiedIdentifier)
            elsif ( ref($child) eq 'HASH'
                && $child->{type} eq 'qualified_identifier' )
            {
                $module_name  = $child->{name};
                $module_index = $i;
                last;
            }
        }

        # If we can't find a module name, return undef (parse error)
        return undef unless defined($module_name);

        # Categorize the use statement
        my $type = _categorize_use_statement($module_name);

        # Extract import list if present
        my $imports = _extract_imports( $context, $module_index + 1 );

        # Build UseStatement IR node
        return $builder->build_use_statement_node( $type, $module_name,
            $imports );
    }
}

1;
