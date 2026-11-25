my $x="a"; my @t = grep { s/a/z/ } ($x .= "a"); print "$x\n";
