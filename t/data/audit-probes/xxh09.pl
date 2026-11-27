sub f { my ($p) = @_; $$p[0] = 9; my ($q) = @_; $q->[0] } my @a = (1); print f(\@a), "@a\n";
