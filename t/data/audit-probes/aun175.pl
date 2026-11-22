my $s = "x"; my $t = ($s .= "y") . ($s .= "z"); print "$t $s\n";
