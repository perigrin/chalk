my @a=(1,2); my $r=\$a[1]; shift @a; print "$$r$a[0]"; $$r=7; print "$a[0]\n";
