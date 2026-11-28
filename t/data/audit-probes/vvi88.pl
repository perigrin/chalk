$_ = "a1b2"; my $s = ""; while (/(\d)/g) { $s .= $1 . pos } print "$s\n";
