my @a = (1,2,3); my $s = ""; for my $e (@a) { for my $f (@a) { $f++ if $e == 1 } $s .= $e } print "$s\n";
