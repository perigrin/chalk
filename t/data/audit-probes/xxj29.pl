my $s = "ab"; if ($s =~ /(a)(b)/) { my ($x,$y) = ($2,$1); print "$x$y$&\n" }
