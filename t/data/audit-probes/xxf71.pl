sub f { local $" = "+"; "@_" } print f(1,2), "@{[3,4]}\n";
