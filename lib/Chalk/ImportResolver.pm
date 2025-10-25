# ABOUTME: ImportResolver - Resolves module dependencies for Chalk self-compilation
# ABOUTME: Handles module name to path conversion, circular dependency detection, and recursive resolution

use 5.42.0;
use experimental 'class';

class Chalk::ImportResolver {
    # Track modules currently being parsed (for circular dependency detection)
    field $parsing :reader = {};

    # Cache of resolved module dependencies
    field $cache :reader = {};

    # Convert module name to file path
    # Chalk::IR::Node -> lib/Chalk/IR/Node.pm
    method module_to_path($module_name) {
        my $path = $module_name;
        $path =~ s/::/\//g;  # Replace :: with /
        return "lib/$path.pm";
    }

    # Check if a module is currently being parsed (circular dependency)
    method is_circular($module_name) {
        return exists $parsing->{$module_name};
    }

    # Extract Chalk::* dependencies from a module file
    # Uses simple regex scanning per Issue #97 recommendation (Option B)
    method extract_dependencies($file_path) {
        open(my $fh, '<', $file_path) or return [];

        my @dependencies = ();
        while (my $line = <$fh>) {
            # Match: use Chalk::Module::Name;
            # Only capture Chalk:: modules (not pragmas, version checks, or external modules)
            if ($line =~ /^\s*use\s+(Chalk::\S+?)(?:\s|;)/) {
                my $module = $1;
                # Remove trailing punctuation
                $module =~ s/[;,]$//;
                push @dependencies, $module;
            }
        }
        close($fh);

        return \@dependencies;
    }

    # Recursively resolve all dependencies for a module
    # Returns array of module names in dependency order (dependencies first)
    method resolve_dependencies($module_name) {
        # Check cache first
        return $cache->{$module_name} if exists $cache->{$module_name};

        # Check for circular dependencies
        if ($self->is_circular($module_name)) {
            # Allow circular dependencies (Perl-compatible behavior)
            # Just return empty list to avoid infinite recursion
            return [];
        }

        # Mark as being parsed
        $parsing->{$module_name} = 1;

        my @order = ();
        my %seen = ();

        # Get file path
        my $file_path = $self->module_to_path($module_name);

        # Skip if file doesn't exist
        if (! -f $file_path) {
            delete $parsing->{$module_name};
            $cache->{$module_name} = [];
            return [];
        }

        # Extract dependencies from this module
        my $deps = $self->extract_dependencies($file_path);

        # Recursively resolve each dependency
        for my $dep (@$deps) {
            next if $seen{$dep};

            my $dep_order = $self->resolve_dependencies($dep);

            # Add dependencies in order
            for my $mod (@$dep_order) {
                if (!$seen{$mod}) {
                    push @order, $mod;
                    $seen{$mod} = 1;
                }
            }

            # Add the dependency itself
            if (!$seen{$dep}) {
                push @order, $dep;
                $seen{$dep} = 1;
            }
        }

        # Add this module at the end (after its dependencies)
        if (!$seen{$module_name}) {
            push @order, $module_name;
            $seen{$module_name} = 1;
        }

        # Done parsing this module
        delete $parsing->{$module_name};

        # Cache the result
        $cache->{$module_name} = \@order;

        return \@order;
    }
}

1;
