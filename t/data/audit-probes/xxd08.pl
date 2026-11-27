my @a=(1,2); my $r=\$a[1]; $#a = 0; push @a, 5; print "$$r @a\n";
