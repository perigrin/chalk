our $g=1; sub p { defined $g ? $g : "u" } sub t { local $g; p() } print t(), p(), "\n";
