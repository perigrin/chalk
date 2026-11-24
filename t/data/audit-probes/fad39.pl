use feature 'try'; no warnings; sub f { try { return 5 } catch ($e) { return 6 } return 7 } print f(),"\n";
