our $g = 1; sub t { $main::{g} ? 1 : 0 } *alias = \$g; our $alias; $alias = 9; print "$g ", t(), "\n";
