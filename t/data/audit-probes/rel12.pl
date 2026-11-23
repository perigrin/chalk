my @a=(5,3,8); my ($mx,$ix)=(0,-1); for my $i (0..$#a) { if ($a[$i]>$mx) { $mx=$a[$i]; $ix=$i } } print "$mx $ix\n";
