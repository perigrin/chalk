my @a=(1); my $f = sub { push @a, 2; "" }; my $s = join(",", @a, $f->(), @a); print "$s\n";
