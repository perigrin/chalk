my @a = (1,2,3); my @r = \(@a); ${$r[2]} = 9; print "@a\n";
