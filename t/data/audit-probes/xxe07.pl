sub a1 { "a" } sub b1 { "b" } { no warnings; *a1 = \&b1; } print a1(), "\n";
