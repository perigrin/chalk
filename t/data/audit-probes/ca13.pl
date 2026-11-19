sub f { my @a = @_; $a[0] = 9; return @a } my @x = (1,2); my @y = f(@x); print "@x|@y\n";
