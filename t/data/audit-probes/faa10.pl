my @a=(1,2); my $r=\$a[0]; shift @a; $a[0]=7; print "$$r\n";
