my @a = (1,2,3); my $s = "@a" . (shift @a) . "@a"; print "$s\n";
