use feature 'try'; no warnings; sub f { try { die "z\n" } catch ($e) { return "c$e" } 7 } print f();
