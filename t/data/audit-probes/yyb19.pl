my @a=(1,2); my @c; for my $x (@a) { push @c, sub { $x } } $a[0]=9; print $c[0]->(), "\n";
