sub f { my ($x, @r) = @_; $x = 0; $r[0] = 0; "@_" } my @a = (1,2); print f(@a), "@a\n";
