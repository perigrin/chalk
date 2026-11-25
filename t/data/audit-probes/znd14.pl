my @a=(1,2,3); my @w=grep { $_->[1] } map { [$_, $_ % 2] } @a; $_->[0]*=10 for @w; print join(",", map { $_->[0] } @w), "@a\n";
