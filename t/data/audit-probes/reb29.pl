use feature "try"; no warnings; our $g=1; sub f { try { local $g=2; die "a\n" } catch ($e) { return "c$g" } } print f(), $g, "\n";
