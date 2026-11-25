my ($x,$y)=(1,2); my $c=0; my $r = $c ? \$x : \$y; $$r++; print "$x$y\n";
