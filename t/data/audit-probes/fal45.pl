my @a=(1,2,3); my @c; for my $x (@a) { my $y=$x; push @c, \$y } ${$c[0]}=9; print "@a ${$c[1]}\n";
