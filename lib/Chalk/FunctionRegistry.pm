# ABOUTME: Registry for storing function definitions during parsing and execution
# ABOUTME: Maps function names to FunctionDef nodes for dispatch
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::FunctionRegistry {
    field %functions;

    # Register a function definition
    method register($name, $func_def) {
        die "FunctionRegistry: function name required" unless defined $name;
        die "FunctionRegistry: func_def required" unless defined $func_def;
        $functions{$name} = $func_def;
    }

    # Look up a function by name
    method lookup($name) {
        return $functions{$name};
    }

    # Check if a function exists
    method has($name) {
        return exists $functions{$name};
    }

    # Get all registered function names
    method names() {
        return keys %functions;
    }

    # Clear all registrations (useful for testing)
    method clear() {
        %functions = ();
    }
}

1;
