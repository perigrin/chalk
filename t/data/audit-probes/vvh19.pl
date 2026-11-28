sub f { my @v = eval { return (5, 6) }; scalar @v } print f(), "\n";
