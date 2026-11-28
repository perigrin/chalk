sub f { eval { die { code => 5 } }; $@->{code} } print f(), "\n";
