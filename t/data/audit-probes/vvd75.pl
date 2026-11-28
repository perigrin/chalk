my $x = "abc"; (my $y = $x) =~ tr/a-c/A-C/; print "$x$y\n";
