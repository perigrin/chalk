my @a = (5,6); my $s = ""; while (my ($i,$v) = each @a) { $s .= "$i$v" } print "$s\n";
