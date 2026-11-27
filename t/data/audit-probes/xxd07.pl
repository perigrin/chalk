my @a=(1,2); my $r=\$a[0]; shift @a; print "$$r @a\n";
