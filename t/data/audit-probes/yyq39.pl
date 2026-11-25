my $x=1; (my $y = $x) =~ s/1/9/; (my $z = $x)++; (my $w = $x) .= "!"; chop(my $v = "ab"); print "$x$y$z$w$v\n";
