my ($x,$y) = ("a","b"); (my $t = $x) =~ tr/a/z/; ($y = $x) =~ tr/a/q/; print "$x$y$t\n";
