my @a = (1,2,3); my $r = \$a[1]; shift @a; print $$r, $a[0], "\n";
