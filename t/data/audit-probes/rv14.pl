sub f { my ($c, @x) = @_; push @x, 9; "@x" } my @a = (1, 2); print f(0, @a), " @a\n";
