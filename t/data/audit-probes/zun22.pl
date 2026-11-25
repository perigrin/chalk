use feature 'try'; no warnings; sub f { try { return 5 } catch ($e) { } 9 } print f(), "\n";
