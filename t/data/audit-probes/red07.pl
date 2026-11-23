use feature "try"; no warnings; sub f { try { die "a\n" } catch ($e) { return "c" } "n" } print f(), "\n";
