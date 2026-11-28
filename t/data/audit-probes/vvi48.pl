my $s = "abc"; my $t = sprintf("%s%s", $s, $s .= "d"); print "$t\n";
