my @a = (1,2,3); sub mod { my @c = @_; $c[0] = 9; @c } my @n = mod(@a); print "@a|@n\n";
