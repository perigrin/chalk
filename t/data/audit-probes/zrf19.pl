my @a=(1,2,3); my $r; for my $x (@a) { $r=\$x if $x==2 } $$r=9; print "@a\n";
