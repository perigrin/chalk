my @a = (1,2,3); my $s = "@a[0,1]"; local $" = "-"; print "$s @a\n";
