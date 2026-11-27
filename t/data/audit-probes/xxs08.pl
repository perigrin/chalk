my $s = "aabb"; (my $t = $s) =~ tr/a//d; my $u = $s =~ tr/a-b//sr; print "$s$t$u\n";
