print defined $ENV{PATH} ? "path" : "none", exists $ENV{NO_SUCH_VAR_Y} ? "y" : "n", "\n";
