sub f { my $v = eval { return 5 }; $v + 1 } print f(), "\n";
