our $x = 1; my $y = "ab"; *x = \$y; $x .= "c"; $x =~ s/a/z/; print "$y\n";
