my $x = 0; my @c = (sub { $x += 1 }, sub { $x *= 3 }); for my $k (0,1,0,1) { $c[$k]->() } print "$x\n";
