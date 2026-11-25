my @a = (1,2,3); print $a[-1], $a[-3], defined $a[-4] ? "d" : "u", defined $a[5] ? "d" : "u", scalar(@a), $#a, "\n";
