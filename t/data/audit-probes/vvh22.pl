sub f { eval { die [1, 2] }; "@{$@}" } print f(), "\n";
