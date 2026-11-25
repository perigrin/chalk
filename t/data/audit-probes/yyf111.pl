my @a=(1,2,3); my $s=""; while (my ($i,$v) = each @a) { $s .= "$i=$v," } print "$s\n";
