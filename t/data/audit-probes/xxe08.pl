sub a1 { "a" } { no warnings; local *a1 = sub { "L" }; print a1() } print a1(), "\n";
