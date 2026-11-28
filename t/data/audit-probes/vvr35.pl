my @a = (1,2,3); my @r = \(@a); shift @a; ${$r[1]} = 9; ${$r[2]} = 8; print "@a\n";
