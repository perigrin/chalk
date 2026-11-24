my @a=(1,2,3); my @c; for my $x (@a) { push @c, \$x } ${$c[0]}=9; print "@a\n";
