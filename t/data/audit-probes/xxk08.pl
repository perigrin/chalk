my ($x,$y) = ("a","b"); my $c = 0; ($c ? $x : $y) =~ s/b/B/; ($c ? $x : $y) =~ tr/B/Q/; print "$x$y\n";
